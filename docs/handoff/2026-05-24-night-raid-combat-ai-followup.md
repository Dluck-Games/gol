# Handoff: Night Raid Combat AI Follow-up

**Date:** 2026-05-24
**Topic:** Night Raid guard combat AI runtime behavior
**Participants:** User (Dluck) + Codex
**Status:** Baseline combat fixes saved; guard AI behavior still needs runtime debugging

---

## Current State

The current saved baseline is pushed:

- `gol-project`: `2a4834b fix(combat): simplify targeted melee and night raid flow`
- parent `gol`: `192113e chore: update gol-project combat baseline`

The baseline deliberately does not claim that guard behavior is fixed. It preserves verified lower-level combat improvements and Night Raid playtest stability so the next pass can focus on the real runtime AI behavior without losing a clean checkpoint.

Completed at a high level:

- Melee attacks are target-based: a queued melee attack has one explicit `attack_target`, and the melee system does not pick a fallback target after a failed check.
- Player melee input now only queues a melee attack when a hittable target exists in the aimed direction.
- Enemy wall-blocker selection no longer collapses every attacker onto the same last wall candidate.
- Night Raid playtest can run long enough to survive to dawn by raising protected core/player HP and using camp-core damage as a flow checkpoint.
- GOAP docs were updated so `FightTemplate` and `SA_Guard` descriptions match the saved baseline.

## Remaining Problem

The recorded Night Raid playtest still shows guard behavior that is not acceptable:

- At the beginning of the raid, the guard walks toward the lower-left wall area and gets stuck oscillating left/right around a tile.
- Before walls are breached, the guard does not visibly perform ranged attacks against enemies outside the camp.
- After enemies breach the camp, the guard does not visibly switch to effective melee against nearby enemies.
- Workers currently look much better than the guard: when enemies enter the camp, workers can engage in melee and kill intruding zombies.

This means the automated playtest checkpoints passing is not enough evidence for this specific behavior. The next pass should use video plus debug bridge evidence to verify guard action, step, target, weapon state, bullet spawning/collision, and HP changes.

## Expected Behavior After Fix

When the fix is actually successful, the Night Raid video should show:

- Guard stays functionally useful inside/near the camp instead of walking into the lower-left wall and oscillating.
- While walls are still intact, an armed guard prefers ranged combat from inside the camp against visible external enemies.
- Guard ranged attacks produce visible/effective damage on external enemies, or there is an explicit design decision explaining why walls block that shot.
- When an enemy becomes adjacent or enters melee range, the guard switches to target-based melee and deals damage to that specific enemy.
- Workers keep their current good behavior: repair when appropriate, and fight intruders when the camp is breached.
- Zombies continue selecting nearby attackable wall targets instead of all converging on one wall.
- The Night Raid playtest still reaches dawn and retreats without ending early because the campfire/player were destroyed.

## Debugging Focus

Do not start from another broad rewrite. Use debug bridge to prove the exact failing link first.

Recommended checks during a fresh `--playtest=night_raid` run:

1. Guard navigation/patrol:
   - Current GOAP action and active template step while it walks to the lower-left wall.
   - Guard world/grid position, waypoint/target position, and movement velocity.
   - Whether the selected patrol point is actor-walkable and reachable from the guard.

2. Guard ranged combat before breach:
   - Whether `CVision._nearest_enemy` is set for the guard.
   - Whether `CGoapAgent.blackboard["entity_to_attack"]` points to an external enemy.
   - Whether `CWeapon.can_fire` becomes true, cooldown reaches interval, and bullets are spawned.
   - Whether bullet line-of-fire logic or bullet collision consumes shots on friendly walls/doors before enemies can be damaged.

3. Guard close combat after breach:
   - Whether the guard still has `CWeapon` and/or `CMelee`; logs have shown the guard can lose `CWeapon` after taking damage.
   - Whether `CMelee.attack_target` is set to a nearby intruder.
   - Whether `SMeleeAttack` applies `CDamage` to that exact target.
   - Whether the target HP actually drops, accounting for invincibility frames and component-drop death behavior.

4. Planner priority:
   - Whether `SA_Fight` preempts `SA_Guard`/`SA_Patrol` when the guard sees a threat.
   - Whether `SA_Guard.is_viable()` and patrol facts cause the guard to continue non-combat behavior despite a valid threat.

## Useful Commands

Run from `gol-project/` unless noted:

```bash
gol test unit --suite ai --verbose
gol test unit --suite system --verbose
gol test integration --suite night_raid --verbose
gol test playtest --suite night_raid --verbose
gol test playtest --suite night_raid --record
```

For live/debug-bridge investigation:

```bash
gol run game --detach -- --skip-menu --playtest=night_raid
gol debug script ../.debug/scripts/<diagnostic-script>.gd
gol stop
```

Debug scripts should stay under the parent repo `.debug/scripts/` and should not be committed.

## Relevant Files

- `gol-project/scripts/gameplay/goap/templates/fight_template.gd`
- `gol-project/scripts/gameplay/goap/steps/attack_step.gd`
- `gol-project/scripts/gameplay/goap/steps/patrol_step.gd`
- `gol-project/scripts/gameplay/goap/strategic_actions/sa_guard.gd`
- `gol-project/scripts/systems/s_perception.gd`
- `gol-project/scripts/systems/s_fire_bullet.gd`
- `gol-project/scripts/systems/s_melee_attack.gd`
- `gol-project/tests/playtest/playtest_night_raid.gd`
- `gol-project/tests/unit/ai/test_night_raid_goap_defense.gd`
- `gol-project/tests/unit/ai/test_survivor_ai.gd`
- `gol-project/tests/unit/system/test_melee_attack_los.gd`
- `gol-project/tests/unit/system/test_fire_bullet_los.gd`

## Suggested Next Acceptance Criteria

- A recorded Night Raid playtest clearly shows the guard firing at enemies before breach or documents why that is intentionally blocked.
- The same recording shows the guard damaging a nearby intruder after breach when a target is in melee range.
- Debug bridge output confirms the guard's active action/step, target, weapon/melee state, and at least one enemy HP decrease caused by the guard.
- Existing unit/system/night_raid/playtest suites still pass.

## Notes

The workers' current behavior is a useful reference point. They demonstrate that the lower-level target-based melee path can work in the Night Raid scenario. The guard problem should therefore be investigated as a guard-specific decision/positioning/ranged-fire pipeline issue before changing the shared melee implementation again.
