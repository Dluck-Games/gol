# Guard AI Behavior & Bullet-Wall Collision Fix

**Date:** 2026-05-26
**Status:** Draft
**Scope:** Night Raid guard combat effectiveness — two independent fixes

---

## Problem Statement

Recorded Night Raid playtests show two guard behavior failures:

1. **Guard walks to wall perimeter and oscillates** — the guard post position is computed 144px from the campfire along the campfire→guard direction, which lands outside the wall enclosure. The guard tries to reach an unreachable position and oscillates at the wall.

2. **Bullets die on friendly walls** — `s_fire_bullet.gd` correctly ignores friendly walls for line-of-sight checks (guard can "decide to fire"), but `s_move.gd` kills bullets on any `_dynamic_blocked` grid cell regardless of faction. Bullets spawned by the guard hit the camp's own fences and are destroyed before reaching enemies.

## Design Decision

- **Walls (wooden fences) are short barriers** — bullets fly over them. Bullets should pass through wall-type blockers.
- **Other buildings** (workbench, stockpile, healing station, watchtower) still block bullets.
- **Movement blocking is unchanged** — entities (players, NPCs, enemies) cannot walk through walls.

---

## Fix A: Bullets Pass Through Walls

### Root Cause

`Service_Map._dynamic_blocked` is `Dictionary[Vector2i, bool]`. When a bullet enters a blocked cell, `s_move.gd` adds `CDead` unconditionally — it cannot distinguish wall from other building.

### Approach

Upgrade `_dynamic_blocked` value from `bool` to `int` (blocker type enum). Bullet collision in `s_move.gd` checks the blocker type and only kills the bullet for non-wall blockers.

### Changes

**1. `service_map.gd`**

- Add blocker type constants: `BLOCKER_NONE = 0`, `BLOCKER_WALL = 1`, `BLOCKER_BUILDING = 2`
- Change `_dynamic_blocked` from `Dictionary[Vector2i, bool]` to `Dictionary[Vector2i, int]`
- `mark_blocked(pos)` → `mark_blocked(pos, type: int = BLOCKER_BUILDING)` — backward compatible default
- `mark_blocked_many(positions)` → `mark_blocked_many(positions, type: int = BLOCKER_BUILDING)`
- `is_position_blocked(pos)` → unchanged semantics: `return _dynamic_blocked.get(pos, 0) > 0`
- New method: `get_blocker_type(pos: Vector2i) -> int` — returns the blocker type constant
- `mark_unblocked(pos)` → unchanged: sets value to `BLOCKER_NONE` (or erases key)

**2. `s_build_site_complete.gd`**

- When registering blockers, pass `BLOCKER_WALL` for entities with `CWall`, `BLOCKER_BUILDING` for others
- Logic: `var type = Service_Map.BLOCKER_WALL if entity.has_component(CWall) else Service_Map.BLOCKER_BUILDING`

**3. `s_move.gd`**

- In `_resolve_wall_slide_position()`, when `entity.has_component(CBullet)`:
  - Query `map.get_blocker_type(next_grid)`
  - If `BLOCKER_WALL` → allow passage (`return next_position`)
  - If `BLOCKER_BUILDING` or other → kill bullet (`add_component(CDead.new())`)

**4. `spawn_command.gd`** (minor)

- Console wall spawn: pass `BLOCKER_WALL` when registering

**5. `s_dead.gd`** (no change needed)

- `mark_unblocked()` already clears the position regardless of type

### Behavior Matrix

| Scenario | Before | After |
|----------|--------|-------|
| Player bullet → friendly wall | Dies | Passes through |
| Player bullet → enemy wall | Dies | Passes through |
| Enemy bullet → player wall | Dies | Passes through |
| Any bullet → building (non-wall) | Dies | Dies |
| Any entity movement → wall | Blocked | Blocked (unchanged) |
| Pathfinding through wall | Blocked | Blocked (unchanged) |

Note: All bullets pass through all walls regardless of faction. This is symmetric and matches the "short fence" design intent. Faction-specific behavior can be added later by checking `CCamp` on the bullet's owner if needed.

### Risk Assessment

- **Pathfinding**: Unaffected — `is_position_blocked()` semantics unchanged (`> 0` check)
- **A* / PathSolver**: Unaffected — only calls `is_position_blocked()`, never reads the value
- **Door system**: Unaffected — doors use separate `_doors` dictionary
- **Enemy bullets**: Also pass through walls (symmetric). This is intentional for now.
- **Existing tests**: `test_fire_bullet_los.gd` tests LOS, not movement collision. May need a new test for bullet-wall passthrough.

---

## Fix B: Guard Post Position Outside Wall Enclosure

### Root Cause

`_choose_guard_post_position()` in `s_semantic_translation.gd` computes the guard post as:

```
campfire_position + direction_to_guard.normalized() * 144.0
```

In the night raid scenario:
- Campfire at grid (10,10) → world (32, 336)
- Guard spawns at grid (11,11) → world (32, 368)
- Distance = 32px < MIN_GUARD_POST_DISTANCE (96px)
- Direction = (0, 1) (straight south)
- Guard post = (32, 336 + 144) = (32, 480)
- South wall at grid (x, 13) → world Y ≈ 432
- **Guard post is 48px south of the wall — outside the enclosure**

The guard walks toward (32, 480), hits the south wall, cannot pass, and oscillates.

### Approach

After computing the guard post position, validate it is reachable (not blocked by walls). If blocked, clamp to the nearest unblocked position inside the enclosure.

### Changes

**1. `s_semantic_translation.gd`**

- In `_choose_guard_post_position()`, after computing the candidate position:
  - Convert to grid coordinates
  - Check `Service_Map.is_position_blocked(grid_pos)`
  - If blocked: binary search or step back along the direction vector until finding an unblocked position
  - Ensure the final position is at least `MIN_GUARD_POST_DISTANCE` from campfire if possible, but prefer a reachable position over the exact distance
- Alternative simpler approach: clamp `GUARD_POST_RING_DISTANCE` to stay within the wall perimeter by checking blocked positions along the ray

**2. `patrol_step.gd`** (defensive)

- In `_generate_safe_patrol_waypoint()` / `_generate_patrol_waypoint()`:
  - After generating a random patrol point, verify it is not in a blocked cell
  - If blocked, regenerate (up to N attempts, then fall back to current position)
  - This prevents patrol waypoints from landing on walls even if the guard post is correctly placed

### Risk Assessment

- **Other scenarios**: Fix applies to any scenario where guard spawns close to campfire near walls — not night-raid-specific
- **Performance**: One `is_position_blocked()` call per guard post initialization (once per guard lifetime) — negligible
- **Patrol radius**: If the enclosure is small, patrol points may cluster. Acceptable for now.

---

## Implementation Order

1. **Fix A first** (bullet passthrough) — smaller change, more certain, immediately verifiable
2. **Fix B second** (guard post position) — requires Fix A to see full effect (guard in correct position + bullets reaching enemies)

Both fixes are independent and can be developed in parallel.

## Verification Plan

1. `gol test unit --suite system` — existing movement/bullet tests pass
2. `gol test unit --suite ai` — existing AI tests pass
3. `gol test playtest --suite night_raid --record` — video shows:
   - Guard stays inside camp enclosure (not walking to wall edge)
   - Guard bullets pass through fences and hit external enemies
   - Enemy bullets can also pass through fences
   - Entities still cannot walk through walls
   - Night raid reaches dawn without campfire/player destruction
4. New unit test: bullet passes through wall-type blocker but dies on building-type blocker
