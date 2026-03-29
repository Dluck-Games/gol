# 05-coder-rework-revert-scope-creep.md

## Completed Work

Reworked PR #219 per reviewer (04-reviewer) feedback. Reverted all scope creep changes and kept only the approved core fixes plus a same-category bug fix.

| File | Operation | Description |
|------|-----------|-------------|
| `scripts/systems/s_enemy_spawn.gd` | Unchanged | Core fix preserved: `ECS.world.add_entity(new_entity)` at line 85 |
| `scripts/systems/s_damage.gd` | Added 2 lines | Same-category fix: `ECS.world.add_entity(new_entity)` in `_spawner_death_burst()` (line 334) |
| `tests/integration/flow/test_flow_enemy_spawn_scene.gd` | Rewritten | Added spawner-to-world verification test (Test 1), kept recipe component tests (Tests 2-3) |
| `tests/unit/system/test_spawner_system.gd` | Unchanged | 6 unit tests for max_spawn_count and cleanup logic |

### Reverted scope creep (deleted from PR)

| File | Type | Reason |
|------|------|--------|
| `scripts/components/c_loot_point.gd` + `.uid` | New component | Not in planner. Loot respawn system is a separate feature. |
| `scripts/systems/s_loot_spawn.gd` + `.uid` | New system | Not in planner. Part of loot respawn system. |
| `scripts/gameplay/ecs/gol_world.gd` | Behavior change | Loot box -> loot point refactor not approved. Restored `_spawn_loot_box_at_position`. |
| `scripts/systems/s_damage.gd` (loot pool) | Behavior change | Loot pool expansion (100% weapon -> 78% weapon + 22% materia) changes game balance. Restored hardcoded weapon list. |
| `scripts/systems/s_area_effect_modifier.gd` | Independent bug fix | CDead guard not in planner. Should be separate PR. |
| `scripts/components/AGENTS.md`, `scripts/systems/AGENTS.md` | Documentation | CLootPoint/SLootSpin catalog entries removed with scope creep. |
| `tests/unit/system/test_loot_spawn.gd` + `.uid` | Unit test | Tests for removed scope creep code. |
| `tests/unit/test_loot_point_component.gd` + `.uid` | Unit test | Tests for removed scope creep code. |
| `tests/unit/test_spawner_loot_drop.gd` + `.uid` | Unit test | Tests for removed scope creep code. |
| `tests/unit/system/test_area_effect_modifier.gd` (CDead tests) | Unit test | Tests for removed scope creep code. |
| `tests/integration/flow/test_flow_loot_spawn_scene.gd` | Integration test | Tests for removed scope creep code. |
| `tests/integration/flow/test_flow_loot_respawn_scene.gd` | Integration test | Tests for removed scope creep code. |
| `tests/integration/flow/test_flow_spawner_loot_drop_scene.gd` | Integration test | Tests for removed scope creep code. |

### New changes (not in previous PR)

| File | Change | Reason |
|------|--------|--------|
| `scripts/systems/s_damage.gd:334` | Added `ECS.world.add_entity(new_entity)` | Reviewer finding #2: same-category bug in `_spawner_death_burst()`. Spawner death burst creates 3 enemies via `create_entity_by_id()` but never adds them to the world. |
| `tests/integration/flow/test_flow_enemy_spawn_scene.gd` | Added Test 1: spawner spawns entity into world | Reviewer finding #3: core fix was not directly tested. New test creates a CSpawner entity, lets SEnemySpawn process, and verifies entity count increased and spawned entity has CHP. Also verifies `spawner.spawned` tracking. |

## Test Contract Coverage

### Unit Tests (`tests/unit/system/test_spawner_system.gd`)

| Contract | Status | Notes |
|----------|--------|-------|
| `test_spawn_wave_adds_entity_to_world` | Covered (integration) | Moved to integration test level. See Test 1 in `test_flow_enemy_spawn_scene.gd`. |
| `test_spawn_wave_sets_correct_position` | Not covered | Position depends on runtime random numbers. E2E-level verification needed. |
| `test_spawn_wave_empty_recipe_id_no_crash` | Indirectly covered | Existing `test_spawner_with_empty_recipe_id` covers AuthoringSpawner level. `_spawn_wave` empty recipe branch (push_error + return) not directly tested. |
| `test_spawn_wave_respects_max_spawn_count` | Partially covered | 3 tests cover count calculation logic. `_spawn_wave` integration not directly tested (needs World). |

### Integration Tests (`tests/integration/flow/test_flow_enemy_spawn_scene.gd`)

| Contract | Status | Notes |
|----------|--------|-------|
| `test_spawner_spawns_enemy_into_world` | Covered | New Test 1: creates CSpawner entity with `enemy_basic` recipe, verifies entity count increases, spawned enemy has CHP, spawner tracks it. |
| `test_poison_enemy_visible_with_area_effect` | Covered | Test 3: verifies CPoison and CAreaEffect components on `enemy_poison` recipe entity. |

### E2E Tests

| Contract | Status | Notes |
|----------|--------|-------|
| `test_poison_fog_visible_on_map` | Not covered | Requires AI Debug Bridge for runtime visual verification. |

## Decision Records

1. **Soft-reset branch to origin/main**: Squashed all 6 previous commits into 1 clean commit. The old history contained scope creep commits (CDead guard, loot system, gol_world refactor) mixed with the core fix. A single clean commit makes the PR easier to review.

2. **Added `ECS.world.add_entity()` to `_spawner_death_burst()`**: Reviewer identified this as the same bug category as the core fix. `create_entity_by_id()` is called but the entity is never added to the world, making the death burst (3 enemies on spawner kill) invisible. This was pre-existing code, not scope creep.

3. **Reverted `s_damage.gd` loot pool to hardcoded weapons**: The scope creep change expanded the pool from 7 weapons to 9 items (7 weapons + 2 materia), changing game balance. This is a behavior change that should be discussed separately.

4. **Integration test creates spawner via `Entity.new()` + `ECS.world.add_entity()`**: This pattern matches the approach used in the (now reverted) loot spawn tests. The spawner entity needs CSpawner + CTransform components, which are set before `add_entity`. The `ALWAYS` active condition ensures immediate first wave spawn.

5. **Did NOT add `SDamage` system to integration test**: Testing `_spawner_death_burst()` requires killing a spawner, which needs SDamage + SCollision systems and a damage source entity. This crosses into the complexity territory better suited for a separate integration test file.

## Repository State

- **branch**: `foreman/issue-196`
- **commit SHA**: `db89e9a`
- **PR**: https://github.com/Dluck-Games/god-of-lego/pull/219 (force-pushed, 1 commit)
- **Commit message**: `fix(systems): add missing ECS.world.add_entity() calls in SEnemySpawn and SDamage (#196)`

### Test Results

Could not run tests in this worktree — gdUnit4 requires `.godot` import cache which is not present in foreman worktrees. Tests should be verified in CI or a manual worktree.

Expected test results:
- `test_spawner_system.gd` (unit): 8 tests (2 AuthoringSpawner + 4 max_spawn_count + 2 cleanup)
- `test_spawner_destroyable.gd` (unit): 14 tests (pre-existing, unchanged)
- `test_flow_enemy_spawn_scene.gd` (integration): 9 assertions across 3 test sections
- Total: ~31 test assertions

### Files changed vs origin/main

```
 scripts/systems/s_damage.gd                        |   2 +
 scripts/systems/s_enemy_spawn.gd                   |   1 +
 tests/integration/flow/test_flow_enemy_spawn_scene.gd | 149 +++++++++
 tests/unit/system/test_spawner_system.gd           | 169 +++++++++++++
 4 files changed, 315 insertions(+), 6 deletions(-)
```

## Unfinished Items

- E2E test via AI Debug Bridge (runtime verification of poison fog particles) — requires live game environment
- Unit test for `_spawn_wave` with `empty_recipe_id` (push_error + return branch) — requires World environment, covered indirectly
- Unit test for `_spawn_wave` position calculation — requires World environment, E2E-level verification needed
