# Damage Mechanism Design Review

**Date:** 2026-04-17
**Submodule commit:** `gol-project @ f678727` (branch `main`)
**Reviewer:** Claude (design review, no code changes made)
**Scope:** `scripts/systems/s_damage.gd`, `s_melee_attack.gd`, `s_elemental_affliction.gd`, `configs/config.gd`, related components

---

## Summary

The damage pipeline is functional and expresses several distinctive design ideas — reverse composition on lethal hits, elemental affliction, component-cap-driven cost. But several design decisions create hidden balance traps, anti-synergies, or remove gameplay axes that could otherwise exist. This report catalogs each issue with its location, root cause, gameplay impact, and a proposed fix sketch so fixes can be picked up later.

Issues are prioritized P0 → P3. P0 items are either observable bugs or silently cap major build axes; P1 items are feel/design regressions; P2/P3 are polish and depth expansions.

---

## Prioritization Table

| # | Priority | Change | Files | Effort | Gameplay impact |
|---|----------|--------|-------|--------|-----------------|
| 1 | **P0** | Per-source i-frames OR don't consume bullet during i-frame | `s_damage.gd` | M | Unlocks attack-speed builds |
| 2 | **P0** | Scope fire-intensity erosion to WET hits (remove from generic damage path) | `s_damage.gd` | S | Removes anti-synergy bug |
| 3 | **P1** | Replace player knockback immunity with `CKnockbackResist` | `s_damage.gd`, new component | S | Restores enemy-design space |
| 4 | **P1** | Scale knockback by damage / per-weapon multiplier | `s_damage.gd`, `c_bullet.gd`, `c_melee.gd` | S | Weapon feel variety |
| 5 | **P1** | Spawner enrage decay / hysteresis | `s_damage.gd`, `c_spawner.gd` | S | Tactical counterplay |
| 6 | **P2** | Melee hit VFX parity with bullets | `s_damage.gd` / `s_melee_attack.gd` | S | Visual polish / clarity |
| 7 | **P2** | Soften lethal drop-count curve | `s_damage.gd`, `config.gd` | S | Build retention |
| 8 | **P2** | Distinct visual when player is console-invincible | `s_damage.gd` | S | Debug ergonomics |
| 9 | **P2** | Global enemy damage multiplier (mirror player side) | `service_console.gd`, `s_damage.gd`, `s_melee_attack.gd` | S | Difficulty tuning knob |
| 10 | **P2** | Scale `_spawner_death_burst` count | `s_damage.gd`, `c_spawner.gd` | S | Late vs early-game feel |
| 11 | **P3** | Introduce crit / weak-point / resistance axis | many | L | Strategic depth |
| 12 | **P3** | Piercing / multi-hit / splash bullet options | `s_damage.gd`, `c_bullet.gd` | M | Weapon-design vocabulary |

---

## Issue 1 — I-frames silently cap effective attack speed (P0)

**Location:** `scripts/systems/s_damage.gd:23, 346–356, 369`

**Current behavior:**

```gdscript
const HURT_INVINCIBLE_TIME: float = 0.3

# ...in _take_damage:
if hp.invincible_time > 0:
    return true       # <- bullet is CONSUMED even though no damage landed
...
hp.invincible_time = HURT_INVINCIBLE_TIME
```

**Gameplay impact:**

- A single 0.3s i-frame is shared across all sources → any weapon firing faster than ~3.3 hits/sec/enemy silently loses DPS it paid composition cost for.
- A 10 rps rifle lands only ~33% of shots on a focused target; a 0.5 rps sniper lands 100%. Attack-speed upgrades are cost-inefficient in a way that is not visible to the player.
- Returning `true` for invincible hits means **bullets are destroyed on impact with no damage dealt**, so the visible weapon does nothing for 0.3s windows. Feels like a hit detection bug.

**Proposed fix (pick one):**

**Option A — Don't consume bullet during i-frame** (smallest change):

```gdscript
if hp.invincible_time > 0:
    return false   # let bullet continue / expire naturally
```

Downside: bullet could re-hit the same frame; need a "hit targets this frame" guard on the bullet.

**Option B — Per-source i-frames** (recommended):

Store a small dict on `CHP`: `recent_hits: Dictionary = {}` keyed by source entity instance id or bullet id, value is expiry time. Reject only if the same source hit within `HURT_INVINCIBLE_TIME`. Different sources bypass the window.

**Option C — Damage-scaled i-frame:**

```gdscript
hp.invincible_time = clamp(amount / hp.max_hp, 0.05, HURT_INVINCIBLE_TIME)
```

Small hits stagger briefly, big hits have real recovery. Simple, no data-structure changes.

Recommended: Option A + Option C together — cheap, removes the bullet-eating bug, and preserves the "big hits knock back harder" feel.

---

## Issue 2 — Fire affliction erodes on *any* damage (P0)

**Location:** `scripts/systems/s_damage.gd:379–387`

**Current behavior:**

```gdscript
if target_entity.has_component(COMPONENT_ELEMENTAL_AFFLICTION):
    var affliction: Variant = target_entity.get_component(COMPONENT_ELEMENTAL_AFFLICTION)
    if affliction != null and affliction.entries.has(ElementType.FIRE):
        var fire_entry: Dictionary = affliction.entries[ElementType.FIRE]
        fire_entry["intensity"] = maxf(0.0, float(fire_entry.get("intensity", 0.0)) - amount * 0.02)
        ...
```

Any damage at all — player gunfire, melee, even another DoT tick — reduces fire intensity by 2% of damage dealt. This runs for both enemies and the player.

**Gameplay impact:**

- **Anti-synergy:** Hosing a burning enemy with bullets actively extinguishes your own DoT. Players who combine fire + rapid-fire weapons are penalized for using both.
- Reads like a half-implemented "wet cancels fire" rule that leaked into the generic damage path.
- Fire already has `decay_per_second` in `s_elemental_affliction.gd` — this secondary decay is undocumented.

**Proposed fix:**

Remove the block entirely, OR scope it to the `WET → FIRE` counter. The counter belongs in `s_elemental_affliction.gd` where it can be expressed symmetrically:

```gdscript
# In _apply_tick_effect or a new _apply_counter_interactions:
if affliction.entries.has(WET) and affliction.entries.has(FIRE):
    # wet actively suppresses fire intensity
    fire_entry["intensity"] -= WET_FIRE_SUPPRESSION * delta
```

Keep fire decay *visible* — either via VFX or via the affliction UI — so players can predict it.

---

## Issue 3 — Player is knockback-immune (P1)

**Location:** `scripts/systems/s_damage.gd:668–673`

```gdscript
func _apply_knockback(target_entity: Entity, direction: Vector2) -> void:
    var camp: CCamp = target_entity.get_component(CCamp)
    if camp and camp.camp == CCamp.CampType.PLAYER:
        return
```

**Gameplay impact:**

- Removes an entire axis of enemy design: chargers, slammers, shockwave bosses, shield-bash enemies have no mechanical bite.
- Melee enemies feel toothless because contact only costs HP, not position.

**Proposed fix:**

Add a scalar `CKnockbackResist` component (or field on `CMovement`). Apply:

```gdscript
var resist := 0.0
if target_entity.has_component(CKnockbackResist):
    resist = target_entity.get_component(CKnockbackResist).resist
movement.velocity += direction * KNOCKBACK_FORCE * (1.0 - resist)
```

Start player at `resist = 0.7` — stable in most cases, but heavy hits still land. Elite enemies get higher resist; bosses get 1.0.

---

## Issue 4 — Knockback is a constant impulse (P1)

**Location:** `scripts/systems/s_damage.gd:20, 684`

```gdscript
const KNOCKBACK_FORCE: float = 2000.0
...
movement.velocity += direction * KNOCKBACK_FORCE
```

A grazing 1-damage DoT tick punts a target as hard as a point-blank 50-damage shotgun.

**Gameplay impact:**

- Weapons feel uniform on contact. No "light and fast" vs "slow and heavy" feel axis.
- Elemental DoT ticks cause repeated micro-knockbacks that can push enemies out of other attacks — unintended crowd control.

**Proposed fix:**

Add `knockback_scale: float = 1.0` to `CBullet` and `CMelee`. Optionally scale by damage:

```gdscript
var scale: float = source_knockback_scale * clamp(amount / REFERENCE_DAMAGE, 0.1, 2.0)
movement.velocity += direction * KNOCKBACK_FORCE * scale
```

Skip knockback for DoT ticks (pass `knockback_direction = Vector2.ZERO` from `s_elemental_affliction.gd` — already done, but verify).

---

## Issue 5 — Spawner enrage is permanent and globally triggered (P1)

**Location:** `scripts/systems/s_damage.gd:372–377`

```gdscript
if spawner and not spawner.damage_enraged:
    spawner.damage_enraged = true
    spawner.enraged = true
```

`damage_enraged` is set by **any** damage amount from **any** source (including stray elemental propagation, AoE splash, or reflected damage) and **never resets**.

**Gameplay impact:**

- One misfire enrages a spawner for the whole run. No counter-play.
- No "calm down and retreat" tactic is possible.
- Combined with `SPresencePenalty` enrage (component-count driven), spawners become stuck enraged from the first minute of a full build.

**Proposed fix (choose one):**

- **Decay:** Add `damage_enrage_timer: float` to `CSpawner`. Refreshed to e.g. 15s on each damage hit. Expire → flip off.
- **Threshold:** Require cumulative damage (e.g., 20% of max HP) across a rolling window before flipping.
- **Hybrid:** Threshold to enter, timer-based decay to exit.

---

## Issue 6 — Melee attacks do not spawn hit VFX (P2)

**Location:** `scripts/systems/s_damage.gd:105–107` (bullet path only) vs `s_melee_attack.gd:138–154` (no VFX call)

`_spawn_hit_vfx` is gated behind bullet collision. Elemental melee does the damage and affliction but skips the visual burst.

**Gameplay impact:**

- Melee feels visually flat compared to ranged; elemental melee lacks the satisfying hit reaction.
- Inconsistency makes it harder to read which hits landed in a chaotic fight.

**Proposed fix:**

Lift `_spawn_hit_vfx(position, element_type)` into `_take_damage` (or a post-damage event) keyed on whether the attack carried an elemental type. Both bullet and melee paths share the same feedback.

---

## Issue 7 — Lethal drop-count curve is swingy near the cap (P2)

**Location:** `scripts/systems/s_damage.gd:613–614`, `scripts/configs/config.gd:51, 53`

```gdscript
static func calculate_drop_count(losable_count: int) -> int:
    return 1 + maxi(0, losable_count - Config.LETHAL_DROP_THRESHOLD)

# With COMPONENT_CAP = 5 and LETHAL_DROP_THRESHOLD = 3:
#   losable 1-3 → drop 1
#   losable 4   → drop 2
#   losable 5   → drop 3  (60% of build gone in one lethal hit)
```

**Gameplay impact:**

- Full-build players are punished too hard for one mistake; mid-build players experience a flat cost.
- Encourages staying at ≤3 components (below threshold) → the whole composition-cost system's "lean into full build" fantasy is blunted.

**Proposed fix:**

Softer curve, e.g.:

```gdscript
return 1 + int(floor(maxi(0, losable_count - T) / 2.0))
# 3→1, 4→1, 5→2, 7→2, 8→2, 9→3
```

Or weight the random pick so the *most recently acquired* component is most likely to drop — creates "commit to your build" tension rather than random-erasure frustration.

---

## Issue 8 — Console-invincibility still plays normal hit blink (P2)

**Location:** `scripts/systems/s_damage.gd:359–364`

```gdscript
if camp and camp.camp == CCamp.CampType.PLAYER:
    if ServiceContext.console().is_player_invincible():
        _play_hit_blink(target_entity)   # <- same flash as real damage
        return true
```

**Gameplay impact:**

- Testers using `/god` mode can't distinguish "hit but invincible" from "hit normally" — debugging tool reduces its own legibility.

**Proposed fix:**

Introduce a tinted variant: `_play_hit_blink(target, Color.GOLD)` for invincible hits, or a distinct shader parameter. Minor, but makes debug sessions clearer.

---

## Issue 9 — Damage multiplier is one-sided (P2)

**Location:** `scripts/services/impl/service_console.gd:970–971`, used at `s_damage.gd:97` and `s_melee_attack.gd:105`.

Only `get_player_effective_damage` exists. No equivalent for enemy damage.

**Gameplay impact:**

- No global difficulty knob. Difficulty tuning has to happen per-entity.
- Makes future "difficulty presets" or "new game +" harder to implement.

**Proposed fix:**

Add symmetric `get_enemy_effective_damage(base)` in `ServiceConsole` and apply in both `_process_bullet_collision` and `_apply_melee_hit` on enemy-owned attacks.

---

## Issue 10 — Hardcoded spawner death burst (P2)

**Location:** `scripts/systems/s_damage.gd:458–473`

```gdscript
for i in range(3):   # always 3 enemies regardless of spawner tier
```

**Gameplay impact:**

- Early-game and late-game spawners die the same way. No scaling with difficulty or progression.

**Proposed fix:**

Add `death_burst_count: int = 3` to `CSpawner` (data-driven). Late-game spawners can define higher bursts.

---

## Issue 11 — No crit / weak-point / resistance axis (P3)

**Locations:** `CBullet.damage`, `CMelee.damage`, `_take_damage` — damage is a flat scalar everywhere.

**Gameplay impact:**

- Weapon comparison collapses to "higher number wins" modulated by elemental DoT.
- No build archetypes like "crit-focused", "armor-pen", "glass cannon".
- The ECS is already ideal for this — components compose naturally.

**Proposed fix (large, plan before implementing):**

- `CCritical` on attacker: `crit_chance`, `crit_multiplier`.
- `CResistance` on target: `{physical: 0.2, fire: 0.0, electric: -0.5}` (negatives = vulnerability).
- Resolve in `_take_damage`:
  ```gdscript
  var is_crit := randf() < attacker_crit.crit_chance
  var final := amount * (is_crit ? attacker_crit.crit_multiplier : 1.0)
  final *= 1.0 - target_resist.get(damage_type, 0.0)
  ```
- Requires threading `damage_type` + `source_entity` through the existing `CDamage` pending-component path (currently only `amount` and `knockback_direction`).

---

## Issue 12 — Bullet hits only the closest target (P3)

**Location:** `scripts/systems/s_damage.gd:60–109, 329–343`

`_find_closest_entity` resolves a bullet to exactly one target, then deletes the bullet.

**Gameplay impact:**

- No piercing (sniper rifles), no multi-hit (shotgun pellets through crowd), no splash (rocket).
- Every multi-target weapon has to be "many bullets" → more entities, more physics load.

**Proposed fix:**

Add `CBullet.pierce_count: int = 0` (hits this many targets before consumption) and `CBullet.splash_radius: float = 0.0` (AoE at impact). Modify `_process_bullet_collision` to apply damage to all valid targets within the splash, and decrement pierce instead of removing bullet immediately.

---

## Cross-cutting observations

- The `_take_damage` return value has two overloaded meanings: "damage was dealt" *and* "bullet should be consumed." Splitting them into an explicit `DamageOutcome` enum (`APPLIED`, `BLOCKED_INVINCIBLE`, `NO_HP`, `IGNORED`) would make call sites more self-documenting and unblock fix #1.
- `_on_no_hp` has four branches (campfire / spawner / component-loss-survives / component-loss-dies). It's readable today but adding crit/resist/piercing will strain it. Consider extracting death-resolution strategies per entity archetype.
- Several tuning constants live at the top of `s_damage.gd` (knockback, i-frame, hit effect timings) while others live in `Config`. Consolidating into `Config` makes balance passes and future data-driven difficulty easier.

---

## Suggested fix order (incremental, low-risk first)

1. **Issue 2** (fire erosion) — remove 8 lines, big anti-synergy gone.
2. **Issue 1 Option A** (don't consume bullet on i-frame) — 1-line return change; verify with rapid-fire weapon play-test.
3. **Issue 4** (damage-scaled knockback) — small per-weapon data, improves feel immediately.
4. **Issue 3** (`CKnockbackResist`) — pair with #4; enables new enemy designs.
5. **Issue 5** (spawner enrage decay) — unblocks stealth/retreat tactics.
6. **Issues 6–10** — polish passes, any order.
7. **Issues 11–12** — plan as a separate design doc; they reshape `CDamage` and affect many systems.

---

## Files referenced

- `gol-project/scripts/systems/s_damage.gd`
- `gol-project/scripts/systems/s_melee_attack.gd`
- `gol-project/scripts/systems/s_elemental_affliction.gd`
- `gol-project/scripts/systems/s_presence_penalty.gd`
- `gol-project/scripts/components/c_damage.gd`
- `gol-project/scripts/components/c_bullet.gd`
- `gol-project/scripts/components/c_melee.gd`
- `gol-project/scripts/components/c_hp.gd`
- `gol-project/scripts/components/c_spawner.gd`
- `gol-project/scripts/configs/config.gd`
- `gol-project/scripts/services/impl/service_console.gd`
- `gol-project/scripts/utils/ecs_utils.gd`

## Related prior design docs

- `docs/superpowers/specs/2026-03-22-reverse-composition-design.md` — component-drop-on-death rationale
- `docs/superpowers/specs/2026-03-24-composition-cost-design.md` — component-cap + penalty system
