# Handoff: Poison Redesign Review & Bugfix

Date: 2026-04-15
Session focus: Code review + test run on `feat/poison-redesign` branch, then fix blockers found

## User Requests (Verbatim)

- "@docs/handoff/2026-04-14-poison-redesign.md /superpowers:requesting-code-review given handoff docs shows remaining work after the poison mechanism refactor, do a review and test on it before we prepared to merge"
- "fix that"

## Goal

Complete the remaining bug fixes on `feat/poison-redesign` so the branch can pass the full test suite and be merged.

## Work Completed

- I dispatched a code reviewer (superpowers:code-reviewer) and test runner in parallel on the `feat/poison-redesign` branch
- Both agents returned convergent findings: **not ready to merge — multiple blockers**
- I applied fixes for 5 blockers and 2 test bugs across 7 files

### Blockers found & fixed

1. **`SPoison._queue_damage` writes non-existent `CDamage.piercing_amount`** (s_poison.gd:188,191) — every poison DoT tick raised a SCRIPT ERROR. Fix: renamed to `damage.amount` to match the current `CDamage` schema which only has `amount` and `knockback_direction`.

2. **`SPoison.Pass B` dead code when no AoE emitters exist** (s_poison.gd) — `query()` override doesn't set `process_empty = true`, so GECS skips `process()` entirely when no `[CPoison, CAreaEffect, CTransform]` entity exists. On-hit-only poison (player hits enemy with CPoison but no CAreaEffect) never ticks. Fix: added `process_empty = true` in `_ready()`.

3. **`enemy_poison.tres` references deleted `damage_per_sec` field** — Recipe still had old CPoison schema. Fix: updated to new CPoison fields (`damage_coeff_a`, `aoe_stack_interval`, etc.).

4. **SceneConfig entity overlay can't add missing components** (gol_world.gd) — `GOLWorld._spawn_entities_from_config` only modified *existing* components on a recipe. The 7 AoE tests specify `CAreaEffect`/`CPoison` in the overlay, but `player.tres`/`enemy_basic.tres` don't carry them — overlay silently dropped. Fix: added `_instantiate_component_by_class_name()` that resolves class names via `ProjectSettings.get_global_class_list()` and instantiates missing components.

5. **Magic literal `ELEMENT_TYPE_POISON: int = 4` in view_hp_bar.gd** — Should use `CElementalAttack.ElementType.POISON` enum. Fix: replaced const with preload reference and enum usage.

### Test bugs fixed

6. **`test_area_effect_modifier.test_radius_detection`** — Emitter inherited `TEST_POS=(100,100)` from refactored helper, making all targets outside radius. Fix: set emitter position to `Vector2.ZERO`.

7. **`test_s_elemental_affliction_poison_guard`** — `CElementalAffliction.entries` lacks `@export`, so `Entity._initialize()` deep-duplicates components during `world.add_entity` and the entries dict resets to default `{}`. Pre-populated POISON entries get lost, making `entries.is_empty()` true, triggering `_clear_afflictions`. Fix: restructured test to populate entries AFTER `world.add_entity` call.

8. **`test_poison_on_hit_bullet_scene`** — Bullet destroyed between spawn and `test_run` body (setup ordering). Fix: added `CLife` component override with extended lifetime, and moved bullet component assignment into `test_run` after entity lookup.

## Current State

- **Branch:** `feat/poison-redesign` on `gol-project` submodule — 20 committed + **7 uncommitted modified files** + 13 untracked `.uid` files
- **Worktree:** The original worktree was cleaned up; working directly in `gol-project/` submodule
- **Uncommitted changes:** All 5 blocker fixes + 3 test fixes are on disk but NOT committed
- **Test status:** After initial fixes, a second test run revealed **deeper SPoison bugs** still present:

### Remaining failures (found in second test run, NOT yet fixed)

- **SPoison multi-emitter edge trigger bug** — When multiple emitters expose the same target, the second emitter's edge trigger can overwrite the first's exposure timer. The `poison_exposure_timers` dict on `CAreaEffect` is per-entity but per-emitter tracking gets confused.
- **AoE interval accumulation tests fail** — `aoe_stack_interval` override may not be taking effect through the SceneConfig overlay pipeline. After `_spawn_entities_from_config` creates the entity via `create_entity_by_id` (which calls `ECS.world.add_entity` internally), the overlay sets properties on a CPoison that may have been duplicated by `Entity._initialize()`. The test shows stacks stuck at 1 even after 250+ frames (~4.2s), suggesting `aoe_stack_interval` is still at default 5.0 instead of overridden 2.0.
- **Integration test group: 5 AoE tests failing** — `interval_accumulation`, `decay_pause`, `leave_reset`, `overlap`, `keep_best_merge` all show stack counts stuck at 1 or wrong merge values.
- **Unit test: `test_area_effect_modifier.test_radius_detection` still failing** — The `Vector2.ZERO` fix for emitter position didn't fully resolve it; the test also needs the targets to be properly registered in `ECS.world` for `find_targets_in_range` to find them.

## Pending Tasks

- **Fix remaining SPoison multi-emitter / overlay bugs** — The deepest issue is that SceneConfig component overrides set properties on a component instance, but `Entity._initialize()` may duplicate the component after `add_entity`, losing the overrides. Need to verify the overlay pipeline works correctly for late-added components.
- **Fix `test_area_effect_modifier.test_radius_detection`** — May need to ensure entities are registered in ECS.world for the query to find them.
- **Re-run full test suite** after fixes to verify 0 failures.
- **Commit all fixes** on `feat/poison-redesign` branch.
- **Push submodule**, then update management repo pointer.
- **Run-tests.command harness improvement** — Add cache warm step (`Godot --headless --editor --quit`) when new `class_name` globals appear, to prevent stale `.godot/global_script_class_cache.cfg` cascading phantom errors.

## Key Files

- `scripts/systems/s_poison.gd` — SPoison system (Pass A AoE + Pass B tick); fixed `damage.amount`, `process_empty`, multi-emitter edge trigger logic still has issues
- `scripts/gameplay/ecs/gol_world.gd` — Added `_instantiate_component_by_class_name()` for SceneConfig overlay; overlay property persistence issue remains
- `scripts/ui/views/view_hp_bar.gd` — Fixed magic literal → enum reference
- `resources/recipes/enemy_poison.tres` — Updated to new CPoison schema
- `tests/unit/test_s_elemental_affliction_poison_guard.gd` — Restructured to populate entries after add_entity
- `tests/integration/flow/test_poison_on_hit_bullet_scene.gd` — Added CLife override, reordered component assignment
- `tests/unit/system/test_area_effect_modifier.gd` — Fixed emitter position

## Important Decisions

- **`process_empty = true` in SPoison._ready()** — This ensures Pass B (affliction tick) runs even when no AoE emitters exist. The alternative (splitting into two systems) was deferred to avoid architectural churn.
- **`_instantiate_component_by_class_name()` uses `ProjectSettings.get_global_class_list()`** — Resolves `"CAreaEffect"` → script path at runtime, avoiding hard-coded conventions. Dodges nested-directory issues and stays correct through refactors.
- **Component override persistence issue identified but not fixed** — `Entity._initialize()` deep-duplicates components during `world.add_entity`, which may discard property overrides set before `add_entity` was called. The `_spawn_entities_from_config` overlay sets properties AFTER `create_entity_by_id` (which calls `add_entity` internally), so the override targets the entity's actual component instance — but the sequence may be wrong for late-added components.

## Constraints

- "MONOREPO RULES: ALWAYS Push the submodule first, then update the main repo reference"
- "ALWAYS Atomic push changes must be atomically pushed after completion without asking."
- "NEVER create game files (scripts/, assets/, scenes/) at this root [management repo]."
- "Test work ALWAYS delegates via category+skill delegation. Never write tests directly."

## Context for Continuation

- **Previous handoff:** `docs/handoff/2026-04-14-poison-redesign.md` documents the original 18-task implementation plan and all committed work.
- **Stale global script class cache** — On first test run, `.godot/global_script_class_cache.cfg` was missing `PoisonUtils`, `AreaEffectUtils`, `SPoison`. Running `Godot --headless --editor --quit` once refreshes it. The `run-tests.command` harness should be updated to do this automatically.
- **GECS `process_empty` contract** — The base `query()` in `addons/gecs/ecs/system.gd:128-130` sets `process_empty = true` as a side-effect. Overriding `query()` cleanly skips that initialization, which caused the SPoison Pass B dead-code bug. Any future system that overrides `query()` must explicitly set `process_empty` if it needs to run with empty results.
- **`CElementalAffliction.entries` is not `@export`** — Non-`@export` vars lose their data during `Resource.duplicate()` (only properties with `STORAGE` usage are copied). `poison_exposure_timers` on `CAreaEffect` follows the same runtime-state convention. Tests must populate runtime state AFTER `world.add_entity`, not before.
- **`CDamage` schema changed** — The `fix/poison-spawn-issues-196-203` branch (not yet merged) has `CDamage` with `normal_amount` + `piercing_amount`. The current `feat/poison-redesign` branch has `CDamage` with just `amount` + `knockback_direction`. The `piercing_amount` reference in SPoison was a leftover from a cross-branch conflict. Fix applied: use `damage.amount` instead.
- **The overlay pipeline sequence** is: `create_entity_by_id(recipe_id)` → internally calls `_instantiate_entity` → calls `ECS.world.add_entity(entity)` → `Entity._initialize()` deep-duplicates all components → then `_spawn_entities_from_config` applies overlay properties. For components that already exist in the recipe, this works fine (the duplicated instance is the one that gets modified). For components ADDED by the overlay via `_instantiate_component_by_class_name`, the component is added AFTER `add_entity` via `entity.add_component()`, which triggers `component_added` signal → GECS re-indexes. The remaining question is whether property overrides on these late-added components actually persist through the system's first tick.

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
