# Poison Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current ad-hoc poison-as-area-damage handling with a two-layer system: a shared effect layer (poison entries in `CElementalAffliction`) fed by two delivery modes (AoE via `SPoison`, on-hit via `SMeleeAttack`/`SDamage` hooks), with a dedicated `SPoison` system owning all poison-specific logic.

**Architecture:** Poison stacks (discrete, 1..max) live inside `CElementalAffliction.entries[POISON]` with a schema distinct from elemental entries. `SPoison` has two passes per frame — Pass A (AoE emission with per-emitter exposure timers) and Pass B (affliction tick with decay and damage formula). On-hit delivery routes through `POISON_UTILS.apply_on_hit`. A mode mutex on the source entity prevents double application when both `CPoison` and `CAreaEffect(apply_poison=true)` are present.

**Tech Stack:** Godot 4.6, GDScript, GECS ECS addon, gdUnit4 (unit tests), SceneConfig (integration tests), v3 test harness via skill delegation.

**Spec:** `docs/superpowers/specs/2026-04-14-poison-redesign-design.md` — read first for full architectural context.

---

## Workflow Notes (important — read before starting)

- **Submodule branching.** All code changes happen inside the `gol-project/` submodule. Per project rules: **create a feature branch — never push directly to `main` on the submodule.** The parent management repo (`gol/`) is only updated via submodule pointer commits at the end.
- **Worktree isolation.** Create a worktree under `gol/.worktrees/poison-redesign/` from inside the submodule. Do all code edits inside that worktree, not in the submodule root checkout.
- **Test delegation is mandatory.** Main agents never write or run tests directly. Every test step in this plan is a `task()` delegation to `gol-test-writer-unit`, `gol-test-writer-integration`, or `gol-test-runner`. The delegation prompt in each step contains the full spec the writer needs.
- **Two logical PRs.** Tasks 2–8 form a "prep" commit group (no player-visible behavior change). Tasks 9–18 form the "activation" commit group (new behavior ships). Both can land as a single feature branch with distinct commits, or split into two PRs depending on reviewer preference. The plan keeps them on one branch for simplicity.
- **Never skip hooks.** No `--no-verify`. No bypassing signing. If a pre-commit hook fails, fix the issue and create a NEW commit — do not amend.

---

## File Structure

### New files (in `gol-project/`)

| Path | Responsibility |
|---|---|
| `scripts/systems/s_poison.gd` | `SPoison` — AoE emission (Pass A) + affliction tick (Pass B) |
| `scripts/utils/poison_utils.gd` | `POISON_UTILS.apply_stack` + `POISON_UTILS.apply_on_hit` chokepoints |
| `scripts/utils/area_effect_utils.gd` | `AreaEffectUtils.find_targets_in_range` — shared target-scan helper |
| `resources/poison_icon.gdshader` | Semi-transparent overlay + progress edge-line for poison status icon |
| `scenes/ui/poison_status_icon.tscn` | Control with `ColorRect` + `Label` stack count |
| `tests/unit/test_c_poison.gd` | Defaults, `on_merge` keep-best, idempotency |
| `tests/unit/test_poison_utils_apply_stack.gd` | Entry creation, keep-best merge, stack cap, decay_timer reset |
| `tests/unit/test_poison_utils_apply_on_hit.gd` | Mode mutex, dead target skip, missing CPoison no-op |
| `tests/unit/test_s_elemental_affliction_poison_guard.gd` | Regression: elemental system doesn't erase POISON entries |
| `tests/unit/test_poison_damage_formula.gd` | `(a*x + b) * tick_interval` math |
| `tests/integration/test_poison_on_hit_melee_scene.gd` | Player melee → enemy gets stack, takes tick damage |
| `tests/integration/test_poison_on_hit_bullet_scene.gd` | Player bullet → enemy gets stack |
| `tests/integration/test_poison_aoe_edge_trigger_scene.gd` | First contact = immediate +1 stack |
| `tests/integration/test_poison_aoe_interval_accumulation_scene.gd` | +1 stack per 5s while in range |
| `tests/integration/test_poison_aoe_leave_reset_scene.gd` | Leave mid-interval → timer resets on re-entry |
| `tests/integration/test_poison_aoe_decay_pause_scene.gd` | Decay pauses while in range, resumes on exit |
| `tests/integration/test_poison_aoe_overlap_scene.gd` | Two clouds → independent contributions |
| `tests/integration/test_poison_aoe_mutex_onhit_scene.gd` | Both components → AoE only, no double |
| `tests/integration/test_poison_keep_best_merge_scene.gd` | Two emitters different tuning → merged keep-best |
| `tests/integration/test_poison_drop_on_lethal_scene.gd` | **Bug #1 regression** — enemy dying from poison drops CPoison box |
| `tests/integration/test_poison_icon_visible_scene.gd` | **Bug #2 regression** — stack gain fires entries_changed, POISON key appears in ViewModel |

### Modified files

| Path | Change |
|---|---|
| `scripts/components/c_poison.gd` | Full rewrite — per-instance tuning + keep-best `on_merge` |
| `scripts/components/c_area_effect.gd` | Add `poison_exposure_timers: Dictionary` runtime field; clear in `on_merge` |
| `scripts/components/c_elemental_attack.gd` | Add `ElementType.POISON = 4` |
| `scripts/systems/s_elemental_affliction.gd` | One-line POISON guard at top of entry loop |
| `scripts/systems/s_area_effect_modifier.gd` | Delete poison channel; adopt `AreaEffectUtils.find_targets_in_range` |
| `scripts/systems/s_melee_attack.gd` | Add `POISON_UTILS.apply_on_hit` call in `_apply_on_hit_element` |
| `scripts/systems/s_damage.gd` | Add `POISON_UTILS.apply_on_hit` call in `_apply_bullet_effects` |
| `scripts/ui/views/view_hp_bar.gd` | Add `POISON` case to icon factory (instantiates `PoisonStatusIcon.tscn`) |

### Files explicitly NOT touched

- `scripts/ui/viewmodels/viewmodel_hp_bar.gd` — existing `entries_changed` binding works automatically for new element types
- `scripts/systems/s_damage.gd`'s damage-processing / drop / blueprint paths — only `_apply_bullet_effects` changes

---

## Task 1: Worktree and feature branch setup

**Files:** none modified yet.

- [ ] **Step 1: Verify current state**

Run from the management repo root:
```bash
cd /Users/dluckdu/Documents/Github/gol
git submodule status gol-project
```
Expected: clean status line with a commit hash.

- [ ] **Step 2: Create worktree dir if missing**

```bash
mkdir -p /Users/dluckdu/Documents/Github/gol/.worktrees
```

- [ ] **Step 3: Create the worktree from inside the submodule**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
git fetch origin main
git worktree add -b feat/poison-redesign \
    /Users/dluckdu/Documents/Github/gol/.worktrees/poison-redesign \
    origin/main
```
Expected: "Preparing worktree (new branch 'feat/poison-redesign')" and the new directory exists.

- [ ] **Step 4: Verify worktree**

```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/poison-redesign
git branch --show-current
```
Expected: `feat/poison-redesign`.

- [ ] **Step 5: From this point onward, all file paths below are relative to the worktree root.** Do not edit files in the parent submodule checkout.

---

## Task 2: Add `ElementType.POISON = 4`

**Files:**
- Modify: `scripts/components/c_elemental_attack.gd` (enum definition)

- [ ] **Step 1: Locate the `ElementType` enum**

Read `scripts/components/c_elemental_attack.gd` and find the `ElementType` enum declaration. Note the existing values (FIRE, WET, COLD, ELECTRIC) and the convention (uppercase, starts at 0).

- [ ] **Step 2: Add POISON member**

Edit the enum block to add `POISON = 4` as a new member. Example:

```gdscript
enum ElementType {
    FIRE = 0,
    WET = 1,
    COLD = 2,
    ELECTRIC = 3,
    POISON = 4,
}
```

Match whatever existing style is used (explicit `= N` or bare). Do not renumber existing members.

- [ ] **Step 3: Verify the file parses**

```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/poison-redesign
# If godot CLI is available:
godot --headless --check-only --quiet scripts/components/c_elemental_attack.gd 2>&1 || true
```
If the check CLI isn't wired up, skip — the first test run will catch a parse error.

- [ ] **Step 4: Commit**

```bash
git add scripts/components/c_elemental_attack.gd
git commit -m "feat(poison): add ElementType.POISON enum value

Preparatory change for poison redesign. No behavior change — the new
enum member is not yet referenced anywhere in production code."
```

---

## Task 3: Extract `AreaEffectUtils.find_targets_in_range`

Pure refactor. `SAreaEffectModifier` currently inlines target-scan / radius / camp filtering. `SPoison.Pass A` needs the same logic. Extract to a shared helper so the two systems can't drift.

**Files:**
- Create: `scripts/utils/area_effect_utils.gd`
- Modify: `scripts/systems/s_area_effect_modifier.gd`

- [ ] **Step 1: Create the helper file**

Create `scripts/utils/area_effect_utils.gd`:

```gdscript
class_name AreaEffectUtils

## Shared target-scanning utility for systems that emit area effects.
## Factored out of SAreaEffectModifier so both SAreaEffectModifier and
## SPoison use identical radius + camp filtering semantics.

static func find_targets_in_range(
    emitter: Entity,
    area_effect: CAreaEffect,
    emitter_camp_type: int
) -> Array:
    var results: Array = []
    if ECS.world == null:
        return results
    var transform: CTransform = emitter.get_component(CTransform)
    if transform == null:
        return results
    var candidates: Array = ECS.world.query.with_all([CTransform, CHP]).execute()
    var radius_sq: float = area_effect.radius * area_effect.radius
    for target_variant in candidates:
        var target: Entity = target_variant as Entity
        if target == null or not is_instance_valid(target):
            continue
        if not target.has_component(CTransform) or not target.has_component(CHP):
            continue
        var target_transform: CTransform = target.get_component(CTransform)
        if target_transform == null:
            continue
        if transform.position.distance_squared_to(target_transform.position) > radius_sq:
            continue
        if not _should_affect_target(emitter, target, area_effect, emitter_camp_type):
            continue
        results.append(target)
    return results


static func _should_affect_target(
    emitter: Entity,
    target: Entity,
    area_effect: CAreaEffect,
    emitter_camp_type: int
) -> bool:
    if emitter == target:
        return area_effect.affects_self
    var target_camp: CCamp = target.get_component(CCamp)
    var target_camp_type: int = target_camp.camp if target_camp else CCamp.CampType.PLAYER
    var is_ally: bool = target_camp_type == emitter_camp_type
    if is_ally:
        return area_effect.affects_allies
    return area_effect.affects_enemies
```

- [ ] **Step 2: Update `SAreaEffectModifier` to call the helper**

In `scripts/systems/s_area_effect_modifier.gd`:
1. Remove the `_get_potential_targets`, `_is_in_radius`, and `_should_affect_target` private methods.
2. Rewrite `_process_entity` to use the helper. The body becomes:

```gdscript
func _process_entity(entity: Entity, delta: float) -> void:
    var area_effect: CAreaEffect = entity.get_component(CAreaEffect)
    var transform: CTransform = entity.get_component(CTransform)
    if area_effect == null or transform == null:
        return

    var emitter_camp: CCamp = entity.get_component(CCamp)
    var emitter_camp_type: int = emitter_camp.camp if emitter_camp else CCamp.CampType.PLAYER

    var targets: Array = AreaEffectUtils.find_targets_in_range(
        entity, area_effect, emitter_camp_type
    )
    for target in targets:
        _apply_effects(entity, target, area_effect, delta)
```

- [ ] **Step 3: Delegate a refactor-safety unit test**

Use `task()` with category `quick`, load skill `gol-test-writer-unit`, and this prompt:

```
Add a unit test to tests/unit/test_area_effect_utils.gd (create if missing)
verifying AreaEffectUtils.find_targets_in_range:

1. test_respects_radius: place a mock emitter at origin with radius 100, two
   mock targets at distance 50 and 150, both with CTransform and CHP. Verify
   only the in-radius target is returned.

2. test_respects_affects_self: emitter with affects_self=false → emitter is
   not in results even if "in radius" against itself. Then with
   affects_self=true → emitter IS in results.

3. test_respects_camp_filtering: with affects_allies=false and
   affects_enemies=true, allies (same CCamp) are filtered out and enemies
   remain.

4. test_null_world_returns_empty: when ECS.world is null, returns empty array
   without errors.

Use auto_free() for all allocated entities. Base class GdUnitTestSuite.
Follow patterns in existing tests/unit/system/ files.
```

- [ ] **Step 4: Run the new unit test + existing area-effect tests**

Delegate via `task()` with category `quick`, load skill `gol-test-runner`, prompt:

```
Run the following unit tests and report PASS/FAIL:
- tests/unit/test_area_effect_utils.gd (new)
- Any existing tests/unit/ that reference SAreaEffectModifier or CAreaEffect

Diagnose any failures. This task is a pure refactor; any regression in
existing AoE behavior is a bug in the extraction, not a design issue.
```

Expected: all PASS. If a prior test fails, the extraction missed behavior — fix before proceeding.

- [ ] **Step 5: Commit**

```bash
git add scripts/utils/area_effect_utils.gd \
        scripts/systems/s_area_effect_modifier.gd \
        tests/unit/test_area_effect_utils.gd
git commit -m "refactor(area-effect): extract find_targets_in_range helper

Factor the radius + camp filtering logic out of SAreaEffectModifier
into AreaEffectUtils so SPoison can reuse identical semantics without
duplicating the scan loop. Pure refactor — no behavior change."
```

---

## Task 4: Rewrite `CPoison` with per-instance tuning

**Files:**
- Modify: `scripts/components/c_poison.gd`
- Test: delegated to `tests/unit/test_c_poison.gd`

- [ ] **Step 1: Replace `c_poison.gd` wholesale**

Overwrite `scripts/components/c_poison.gd` with:

```gdscript
class_name CPoison
extends Component

## Poison source. Presence on an attacker enables on-hit poison delivery
## (via SMeleeAttack._apply_on_hit_element / SDamage._apply_bullet_effects).
## Combined with CAreaEffect(apply_poison=true), enables AoE delivery instead
## (via SPoison.Pass A). The two modes are mutually exclusive per source.
##
## Losable — drops as a component box on lethal damage via existing SDamage
## _drop_component_box path. No code change needed to enable drops.

@export var damage_coeff_a: float     = 1.5   # dps = a * stacks + b
@export var damage_coeff_b: float     = 0.5
@export var max_stacks: int           = 10
@export var aoe_stack_interval: float = 5.0   # seconds in-range per +1 stack
@export var decay_interval: float     = 3.0   # seconds per -1 stack while idle
@export var tick_interval: float      = 0.5   # damage emission cadence


func on_merge(other: CPoison) -> void:
    # Keep-best semantics: better fields always win, matching CMelee.on_merge.
    # Lower is better for aoe_stack_interval (faster stack application) and
    # tick_interval (smoother damage). Higher is better for everything else.
    damage_coeff_a     = maxf(damage_coeff_a, other.damage_coeff_a)
    damage_coeff_b     = maxf(damage_coeff_b, other.damage_coeff_b)
    max_stacks         = maxi(max_stacks, other.max_stacks)
    aoe_stack_interval = minf(aoe_stack_interval, other.aoe_stack_interval)
    decay_interval     = maxf(decay_interval, other.decay_interval)
    tick_interval      = minf(tick_interval, other.tick_interval)
```

- [ ] **Step 2: Delegate the unit test**

`task()` with category `quick`, skill `gol-test-writer-unit`, prompt:

```
Create tests/unit/test_c_poison.gd (extends GdUnitTestSuite) with these cases:

1. test_defaults_match_spec:
   Construct a fresh CPoison via CPoison.new() (auto_free it). Assert:
   - damage_coeff_a == 1.5
   - damage_coeff_b == 0.5
   - max_stacks == 10
   - aoe_stack_interval == 5.0
   - decay_interval == 3.0
   - tick_interval == 0.5

2. test_on_merge_keeps_best_per_field:
   Create two CPoison instances. Set distinct values so each field has a
   clearly "better" winner:
     a.damage_coeff_a=2.0, b.damage_coeff_a=1.0 → expect a after merge
     a.damage_coeff_b=0.3, b.damage_coeff_b=0.9 → expect b's value (0.9)
     a.max_stacks=12,      b.max_stacks=8      → expect 12
     a.aoe_stack_interval=6.0, b.aoe_stack_interval=4.0 → expect 4.0 (min)
     a.decay_interval=2.0, b.decay_interval=5.0 → expect 5.0
     a.tick_interval=0.6, b.tick_interval=0.3 → expect 0.3 (min)
   Call a.on_merge(b) and assert each field on `a` matches the expected value.

3. test_on_merge_idempotent:
   Create one CPoison with default values, clone it (new instance, same values).
   Call original.on_merge(clone). Assert all fields on original are still
   equal to the defaults.

auto_free() all CPoison instances. No World, no ECS — pure component data tests.
```

- [ ] **Step 3: Run the test**

Delegate via `gol-test-runner`, prompt:

```
Run tests/unit/test_c_poison.gd and report PASS/FAIL. Diagnose any failures.
```
Expected: all three cases PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/components/c_poison.gd tests/unit/test_c_poison.gd
git commit -m "feat(poison): per-instance tuning on CPoison with keep-best merge

CPoison is no longer a data-less marker. Each instance carries its own
tuning (damage_coeff_a/b, max_stacks, intervals), so different poison
sources can ship different stats. on_merge uses keep-best semantics,
mirroring CMelee.on_merge. Defaults live inline in the component source.

No references to these new fields exist yet — dead code until SPoison
lands in a later task."
```

---

## Task 5: Add POISON skip guard to `SElementalAffliction`

The existing per-entry loop in `SElementalAffliction._process_entity` unconditionally decrements `remaining_duration` and `intensity`, then erases the entry if either reaches zero. Poison entries don't use those fields and would be erased on frame 1 without this guard.

**Files:**
- Modify: `scripts/systems/s_elemental_affliction.gd`
- Test: delegated

- [ ] **Step 1: Add the guard line**

Find the loop in `_process_entity`:
```gdscript
for element_type_variant in affliction.entries.keys().duplicate():
    var element_type := int(element_type_variant)
    var entry: Dictionary = affliction.entries.get(element_type, {})
```

Insert immediately after the `var element_type := int(element_type_variant)` line:

```gdscript
    if element_type == COMPONENT_ELEMENTAL_ATTACK.ElementType.POISON:
        continue  # SPoison owns poison entries; elemental tick must not touch them
```

Verify no other spot in `SElementalAffliction` iterates `affliction.entries` — if there is, add the same guard there.

- [ ] **Step 2: Delegate regression unit test**

`task()` category `quick`, skill `gol-test-writer-unit`, prompt:

```
Create tests/unit/test_s_elemental_affliction_poison_guard.gd (extends
GdUnitTestSuite) verifying that SElementalAffliction's per-frame tick does
NOT modify or erase poison entries inside CElementalAffliction.entries.

Setup:
- Construct an Entity via auto_free, add CElementalAffliction with a
  synthetic poison entry dict containing:
    {
        "element_type": CElementalAttack.ElementType.POISON,
        "stacks": 5,
        "max_stacks": 10,
        "decay_timer": 1.2,
        "decay_interval": 3.0,
        "tick_timer": 0.3,
        "tick_interval": 0.5,
        "damage_coeff_a": 1.5,
        "damage_coeff_b": 0.5,
        "accumulation_progress": 0.0,
        "source_entity": null,
    }
- This test constructs SElementalAffliction directly (unit scope) without a
  World. Call its _process_entity(entity, 0.1) directly if reachable, OR
  use whatever pattern the existing system unit tests use (check
  tests/unit/system/ for reference).

Assert after one tick:
- entries still contains the POISON key
- entries[POISON]["stacks"] == 5 (unchanged)
- entries[POISON]["decay_timer"] == 1.2 (unchanged)
- entries[POISON]["tick_timer"] == 0.3 (unchanged)

This is a regression test for the POISON guard. Without the guard, the
existing elemental loop would zero out remaining_duration (default 0.0)
and _should_remove_entry would erase the entry on frame 1.

If SElementalAffliction's _process_entity requires a real World and can't
be unit-tested, adapt the test to construct a minimal GECS world. Check
tests/unit/system/ for existing patterns.
```

- [ ] **Step 3: Run the test**

Delegate via `gol-test-runner`:
```
Run tests/unit/test_s_elemental_affliction_poison_guard.gd. Report PASS/FAIL.
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/systems/s_elemental_affliction.gd \
        tests/unit/test_s_elemental_affliction_poison_guard.gd
git commit -m "feat(poison): skip POISON entries in SElementalAffliction tick

Add a one-line guard at the top of the per-entry loop so SPoison can
own poison entries without the elemental tick overwriting their schema.
Load-bearing: without this, the existing remaining_duration/intensity
decrement logic would erase poison entries on frame 1."
```

---

## Task 6: Create `POISON_UTILS` (chokepoint for stack application)

**Files:**
- Create: `scripts/utils/poison_utils.gd`
- Test: delegated to `tests/unit/test_poison_utils_apply_stack.gd` and `tests/unit/test_poison_utils_apply_on_hit.gd`

- [ ] **Step 1: Create the utility file**

Create `scripts/utils/poison_utils.gd`:

```gdscript
class_name PoisonUtils

## Single chokepoint for every poison-stack mutation. Both SPoison.Pass A
## (AoE emission) and the on-hit hooks in SMeleeAttack / SDamage route
## through apply_stack, so all invariants (ensure affliction, stack cap,
## decay_timer reset, keep-best merge, signal emission) live in one place.

const COMPONENT_ELEMENTAL_ATTACK = preload("res://scripts/components/c_elemental_attack.gd")
const COMPONENT_ELEMENTAL_AFFLICTION = preload("res://scripts/components/c_elemental_affliction.gd")


## Apply `count` poison stacks to `target`, attributed to `source`.
## Idempotent and safe to call from any system. Emits entries_changed
## on the target's affliction component when anything mutates.
static func apply_stack(target: Entity, count: int, source: Entity) -> void:
    if target == null or not is_instance_valid(target):
        return
    if not target.has_component(CHP):
        return
    if target.has_component(CDead):
        return
    if source == null or not is_instance_valid(source):
        return
    var src: CPoison = source.get_component(CPoison)
    if src == null:
        return

    var affliction = _ensure_affliction(target)
    if affliction == null:
        return

    var poison_key := COMPONENT_ELEMENTAL_ATTACK.ElementType.POISON
    var entry: Dictionary = affliction.entries.get(poison_key, {})
    var had_existing := not entry.is_empty()

    if not had_existing:
        entry = {
            "element_type": poison_key,
            "stacks": 0,
            "max_stacks": src.max_stacks,
            "decay_timer": 0.0,
            "decay_interval": src.decay_interval,
            "tick_timer": 0.0,
            "tick_interval": src.tick_interval,
            "damage_coeff_a": src.damage_coeff_a,
            "damage_coeff_b": src.damage_coeff_b,
            "accumulation_progress": 0.0,
            "source_entity": source,
        }
    else:
        # Keep-best merge — better fields always win. Matches CPoison.on_merge.
        entry["max_stacks"]     = maxi(int(entry["max_stacks"]), src.max_stacks)
        entry["decay_interval"] = maxf(float(entry["decay_interval"]), src.decay_interval)
        entry["tick_interval"]  = minf(float(entry["tick_interval"]), src.tick_interval)
        entry["damage_coeff_a"] = maxf(float(entry["damage_coeff_a"]), src.damage_coeff_a)
        entry["damage_coeff_b"] = maxf(float(entry["damage_coeff_b"]), src.damage_coeff_b)
        entry["source_entity"]  = source

    entry["stacks"] = mini(
        int(entry["stacks"]) + count,
        int(entry["max_stacks"])
    )
    entry["decay_timer"] = 0.0  # any add resets decay per spec

    affliction.entries[poison_key] = entry
    affliction.notify_entries_changed()


## Trigger on-hit poison delivery. Called from SMeleeAttack._apply_on_hit_element
## and SDamage._apply_bullet_effects. Suppressed when attacker is an AoE
## poison emitter — the AoE path owns delivery in that case.
static func apply_on_hit(attacker: Entity, target: Entity) -> void:
    if attacker == null or not is_instance_valid(attacker):
        return
    if not attacker.has_component(CPoison):
        return
    # Mode mutex: if attacker emits AoE poison, skip on-hit to prevent double-dip.
    var area_effect: CAreaEffect = attacker.get_component(CAreaEffect)
    if area_effect != null and area_effect.apply_poison:
        return
    apply_stack(target, 1, attacker)


static func _ensure_affliction(target: Entity):
    var affliction = target.get_component(COMPONENT_ELEMENTAL_AFFLICTION)
    if affliction != null:
        return affliction
    affliction = COMPONENT_ELEMENTAL_AFFLICTION.new()
    var movement: CMovement = target.get_component(CMovement)
    if movement != null:
        affliction.base_max_speed = movement.max_speed
    target.add_component(affliction)
    return affliction
```

- [ ] **Step 2: Delegate `apply_stack` unit test**

`task()` category `quick`, skill `gol-test-writer-unit`, prompt:

```
Create tests/unit/test_poison_utils_apply_stack.gd (extends GdUnitTestSuite)
with these cases. All entities should use auto_free.

Helper: make_poisoned_attacker(tuning_overrides) → Entity
  Creates an Entity with a CPoison component. Override any fields from
  the tuning_overrides dictionary.

Helper: make_target() → Entity
  Creates an Entity with CHP and CTransform.

1. test_first_application_creates_entry_with_source_tuning:
   attacker has CPoison with damage_coeff_a=2.0, max_stacks=15.
   target has no CElementalAffliction.
   Call PoisonUtils.apply_stack(target, 1, attacker).
   Assert:
   - target now has CElementalAffliction
   - entries contains POISON key
   - entries[POISON]["stacks"] == 1
   - entries[POISON]["max_stacks"] == 15
   - entries[POISON]["damage_coeff_a"] == 2.0
   - entries[POISON]["decay_timer"] == 0.0

2. test_repeated_application_increments_stacks_up_to_cap:
   attacker CPoison has max_stacks=3. Apply 5 times.
   Final entries[POISON]["stacks"] == 3 (capped).

3. test_keep_best_merge_across_sources:
   attackerA: damage_coeff_a=1.0, max_stacks=10
   attackerB: damage_coeff_a=3.0, max_stacks=5
   apply_stack(target, 1, attackerA)
   apply_stack(target, 1, attackerB)
   Assert:
   - entries[POISON]["damage_coeff_a"] == 3.0 (max)
   - entries[POISON]["max_stacks"] == 10 (max — attackerA wins here)
   - entries[POISON]["stacks"] == 2
   - entries[POISON]["source_entity"] == attackerB (most recent)

4. test_stacks_not_decremented_by_weaker_source_ceiling:
   attackerA: max_stacks=15, apply 1 stack, then apply 11 more times (stacks=12).
   attackerB: max_stacks=10, apply_stack(target, 1, attackerB).
   Assert:
   - entries[POISON]["max_stacks"] == 15 (stays at higher)
   - entries[POISON]["stacks"] == 13 (NOT clamped down to 10; grew to 13)

5. test_decay_timer_reset_on_add:
   First apply_stack creates entry with decay_timer=0.
   Manually set entries[POISON]["decay_timer"] = 2.5.
   Call apply_stack again.
   Assert: entries[POISON]["decay_timer"] == 0.0

6. test_dead_target_noop:
   target has CDead. Call apply_stack. Assert target.has_component(
   CElementalAffliction) is still false.

7. test_null_source_noop:
   Call apply_stack(target, 1, null). No exception, no state change.

8. test_entries_changed_signal_emitted:
   Connect a counter to target's CElementalAffliction.entries_changed signal
   (get/create affliction first). Call apply_stack. Verify signal fired
   at least once.

Use GECS ElementType reference: CElementalAttack.ElementType.POISON.
Prefer const POISON_KEY := CElementalAttack.ElementType.POISON for brevity.
```

- [ ] **Step 3: Delegate `apply_on_hit` unit test**

`task()` category `quick`, skill `gol-test-writer-unit`, prompt:

```
Create tests/unit/test_poison_utils_apply_on_hit.gd (extends GdUnitTestSuite)
with these cases:

1. test_attacker_without_cpoison_noop:
   attacker has no CPoison. target is a normal target with CHP.
   PoisonUtils.apply_on_hit(attacker, target).
   Assert target has no CElementalAffliction.

2. test_attacker_with_cpoison_applies_one_stack:
   attacker has CPoison (defaults). target is normal.
   apply_on_hit → assert target.entries[POISON]["stacks"] == 1.

3. test_attacker_with_aoe_poison_suppressed:
   attacker has CPoison AND CAreaEffect with apply_poison=true.
   apply_on_hit → assert target has NO CElementalAffliction (mode mutex).

4. test_attacker_with_area_effect_but_no_apply_poison_still_fires:
   attacker has CPoison AND CAreaEffect with apply_poison=false.
   (This is an AoE melee/heal user who happens to also be a poison source.)
   apply_on_hit → assert target got 1 poison stack.
   Rationale: only the apply_poison=true case enables AoE poison delivery;
   otherwise on-hit still applies.

5. test_dead_target_noop:
   target has CDead. apply_on_hit → no state change on target.

6. test_null_attacker_noop:
   apply_on_hit(null, target). No exception.

auto_free everything. Use CElementalAttack.ElementType.POISON.
```

- [ ] **Step 4: Run both tests**

Delegate via `gol-test-runner`:
```
Run tests/unit/test_poison_utils_apply_stack.gd and
tests/unit/test_poison_utils_apply_on_hit.gd. Report PASS/FAIL per case.
```
Expected: all cases PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/utils/poison_utils.gd \
        tests/unit/test_poison_utils_apply_stack.gd \
        tests/unit/test_poison_utils_apply_on_hit.gd
git commit -m "feat(poison): add PoisonUtils chokepoint for stack application

Every +stack event — AoE emission, on-hit, future sources — routes through
PoisonUtils.apply_stack. Keep-best merge, stack cap, decay_timer reset,
and entries_changed signaling all live in one place. apply_on_hit carries
the mode mutex: AoE emitters suppress on-hit delivery to prevent double-dip."
```

---

## Task 7: Extend `CAreaEffect` with poison exposure timers

**Files:**
- Modify: `scripts/components/c_area_effect.gd`

- [ ] **Step 1: Add the runtime field**

At the end of `c_area_effect.gd`'s field declarations (after `apply_poison`), add:

```gdscript
## Runtime state — per-target exposure timers for poison AoE emission.
## NOT exported, not serialized, NOT deep-copied. Owned by SPoison.Pass A.
## Maps target Entity → seconds of continuous in-range exposure.
var poison_exposure_timers: Dictionary = {}
```

- [ ] **Step 2: Clear the dict in `on_merge`**

Find `on_merge` and append to the body:

```gdscript
    # New CAreaEffect instance replaces the old — drop stale target refs.
    poison_exposure_timers.clear()
```

- [ ] **Step 3: Commit**

```bash
git add scripts/components/c_area_effect.gd
git commit -m "feat(poison): add poison_exposure_timers runtime field to CAreaEffect

Pure data addition owned by SPoison.Pass A. Tracks per-target seconds of
continuous in-range exposure so the 5s cadence rule can reset when a
target leaves the radius. Cleared in on_merge to avoid dangling Entity
references surviving a materia swap."
```

---

## Task 8: Prep-work checkpoint

At this point, all groundwork is in place but no new behavior ships. The game runs exactly as before because `SPoison` doesn't exist yet and `SAreaEffectModifier` still owns the old poison channel.

- [ ] **Step 1: Run the full unit test suite**

Delegate via `gol-test-runner`:
```
Run all unit tests in tests/unit/ and report PASS/FAIL. Diagnose any
failures. At this checkpoint, no existing test should regress — all
changes so far are additive or pure refactors.
```
Expected: all PASS. If an elemental or area-effect test fails, that's a refactor bug in Task 3 or Task 5.

- [ ] **Step 2: Verify branch state**

```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/poison-redesign
git log --oneline origin/main..HEAD
```
Expected: 6 commits (Tasks 2–7, one commit each).

---

## Task 9: Create `SPoison` system — Pass A (AoE emission)

**Files:**
- Create: `scripts/systems/s_poison.gd`
- Test: delegated integration tests in later tasks

- [ ] **Step 1: Create the system file with Pass A + stub Pass B**

Create `scripts/systems/s_poison.gd`:

```gdscript
class_name SPoison
extends System

## Owns all poison-specific logic:
## - Pass A: AoE emission with per-emitter exposure timers, edge triggers,
##           eviction on leave
## - Pass B: affliction tick (decay, damage formula, entry cleanup)
##
## Pass A runs before Pass B each frame so that any +stack event resets
## decay_timer before Pass B advances it.

const COMPONENT_ELEMENTAL_ATTACK = preload("res://scripts/components/c_elemental_attack.gd")
const COMPONENT_ELEMENTAL_AFFLICTION = preload("res://scripts/components/c_elemental_affliction.gd")
const POISON_KEY := COMPONENT_ELEMENTAL_ATTACK.ElementType.POISON


func _ready() -> void:
    group = "gameplay"


func query() -> QueryBuilder:
    # Framework query: poison emitters (Pass A). Pass B does a manual world
    # query for afflicted entities inside process().
    return q.with_all([CPoison, CAreaEffect, CTransform])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    _pass_a_emission(entities, delta)
    _pass_b_tick(delta)


# ----------------------- Pass A: AoE emission ------------------------

func _pass_a_emission(emitters: Array[Entity], delta: float) -> void:
    for emitter in emitters:
        if emitter == null or not is_instance_valid(emitter):
            continue
        var area_effect: CAreaEffect = emitter.get_component(CAreaEffect)
        if area_effect == null or not area_effect.apply_poison:
            continue
        _process_emitter(emitter, area_effect, delta)


func _process_emitter(emitter: Entity, area_effect: CAreaEffect, delta: float) -> void:
    var emitter_camp: CCamp = emitter.get_component(CCamp)
    var emitter_camp_type: int = emitter_camp.camp if emitter_camp else CCamp.CampType.PLAYER

    var in_range: Array = AreaEffectUtils.find_targets_in_range(
        emitter, area_effect, emitter_camp_type
    )

    # Build a set-like dict for fast membership test
    var in_range_set: Dictionary = {}
    for t in in_range:
        in_range_set[t] = true

    # Eviction: any timer key NOT in the current in-range set is cleared.
    # Targets that left the radius (or got freed) lose their 5s timer AND
    # their accumulation_progress UI mirror.
    for target_key in area_effect.poison_exposure_timers.keys().duplicate():
        if not in_range_set.has(target_key) or not is_instance_valid(target_key):
            area_effect.poison_exposure_timers.erase(target_key)
            _clear_accumulation_progress(target_key)

    var src_poison: CPoison = emitter.get_component(CPoison)
    if src_poison == null:
        return

    for target in in_range:
        var stacks := _get_poison_stacks(target)
        if stacks == 0:
            # Edge trigger — first contact grants 1 stack immediately
            PoisonUtils.apply_stack(target, 1, emitter)
            area_effect.poison_exposure_timers[target] = 0.0
            _write_accumulation_progress(target, 0.0)
        else:
            var elapsed: float = float(
                area_effect.poison_exposure_timers.get(target, 0.0)
            ) + delta
            if elapsed >= src_poison.aoe_stack_interval:
                PoisonUtils.apply_stack(target, 1, emitter)
                elapsed -= src_poison.aoe_stack_interval
            area_effect.poison_exposure_timers[target] = elapsed
            _write_accumulation_progress(
                target,
                elapsed / src_poison.aoe_stack_interval
            )


# ----------------------- Pass B: affliction tick ---------------------

func _pass_b_tick(delta: float) -> void:
    if ECS.world == null:
        return
    var afflicted: Array = ECS.world.query.with_all(
        [COMPONENT_ELEMENTAL_AFFLICTION]
    ).execute()
    for entity_variant in afflicted:
        var entity: Entity = entity_variant as Entity
        if entity == null or not is_instance_valid(entity):
            continue
        if entity.has_component(CDead):
            continue
        _tick_entity_poison(entity, delta)


func _tick_entity_poison(entity: Entity, delta: float) -> void:
    var affliction = entity.get_component(COMPONENT_ELEMENTAL_AFFLICTION)
    if affliction == null:
        return
    var entry: Dictionary = affliction.entries.get(POISON_KEY, {})
    if entry.is_empty():
        return

    # Decay
    entry["decay_timer"] = float(entry["decay_timer"]) + delta
    var erased := false
    while float(entry["decay_timer"]) >= float(entry["decay_interval"]):
        entry["decay_timer"] = float(entry["decay_timer"]) - float(entry["decay_interval"])
        entry["stacks"] = int(entry["stacks"]) - 1
        if int(entry["stacks"]) <= 0:
            affliction.entries.erase(POISON_KEY)
            affliction.notify_entries_changed()
            erased = true
            break
    if erased:
        return

    # Damage tick
    entry["tick_timer"] = float(entry["tick_timer"]) + delta
    while float(entry["tick_timer"]) >= float(entry["tick_interval"]):
        entry["tick_timer"] = float(entry["tick_timer"]) - float(entry["tick_interval"])
        var dps: float = float(entry["damage_coeff_a"]) * int(entry["stacks"]) \
                       + float(entry["damage_coeff_b"])
        _queue_damage(entity, dps * float(entry["tick_interval"]))

    affliction.entries[POISON_KEY] = entry


# ----------------------- Helpers -------------------------------------

func _get_poison_stacks(target: Entity) -> int:
    if target == null or not is_instance_valid(target):
        return 0
    var affliction = target.get_component(COMPONENT_ELEMENTAL_AFFLICTION)
    if affliction == null:
        return 0
    var entry: Dictionary = affliction.entries.get(POISON_KEY, {})
    if entry.is_empty():
        return 0
    return int(entry["stacks"])


func _write_accumulation_progress(target: Entity, progress: float) -> void:
    if target == null or not is_instance_valid(target):
        return
    var affliction = target.get_component(COMPONENT_ELEMENTAL_AFFLICTION)
    if affliction == null:
        return
    var entry: Dictionary = affliction.entries.get(POISON_KEY, {})
    if entry.is_empty():
        return
    # Max across overlapping emitters so the UI doesn't flicker
    var current: float = float(entry.get("accumulation_progress", 0.0))
    entry["accumulation_progress"] = maxf(current, clampf(progress, 0.0, 1.0))
    affliction.entries[POISON_KEY] = entry


func _clear_accumulation_progress(target) -> void:
    if target == null or not (target is Entity) or not is_instance_valid(target):
        return
    var affliction = (target as Entity).get_component(COMPONENT_ELEMENTAL_AFFLICTION)
    if affliction == null:
        return
    var entry: Dictionary = affliction.entries.get(POISON_KEY, {})
    if entry.is_empty():
        return
    entry["accumulation_progress"] = 0.0
    affliction.entries[POISON_KEY] = entry


func _queue_damage(entity: Entity, amount: float) -> void:
    if amount <= 0.0:
        return
    var damage: CDamage = entity.get_component(CDamage)
    if damage == null:
        damage = CDamage.new()
        damage.piercing_amount = amount
        entity.add_component(damage)
        return
    damage.piercing_amount += amount
```

- [ ] **Step 2: Register `SPoison` in whatever the project uses to register systems**

Check how existing systems get registered — `scripts/systems/s_area_effect_modifier.gd` and `s_elemental_affliction.gd` must be loaded somewhere (a system loader, autoload, or scene). Grep for the elemental system name:

```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/poison-redesign
grep -r "SElementalAffliction" --include="*.gd" --include="*.tscn" . | grep -v tests/
```

Follow the same registration pattern for `SPoison`. Add it wherever `SElementalAffliction` or `SAreaEffectModifier` are listed. Both the class_name and any explicit add_child / instantiate call need attention.

- [ ] **Step 3: Commit the system scaffolding**

```bash
git add scripts/systems/s_poison.gd <any files modified for registration>
git commit -m "feat(poison): add SPoison system (Pass A emission + Pass B tick)

Concentrates all poison-specific mechanics in one system. Pass A handles
AoE emission with per-emitter exposure timers and eviction-on-leave;
Pass B handles decay + damage formula. SAreaEffectModifier still owns
poison in parallel at this commit — the channel is not removed until
Task 11, so both systems emit temporarily (idempotent because
PoisonUtils.apply_stack is the single chokepoint)."
```

---

## Task 10: Integration tests for `SPoison` AoE emission

**Files:**
- Test: delegated to `tests/integration/test_poison_aoe_*_scene.gd`

- [ ] **Step 1: Delegate the edge-trigger test**

`task()` category `deep`, skill `gol-test-writer-integration`, prompt:

```
Create tests/integration/test_poison_aoe_edge_trigger_scene.gd
(extends SceneConfig).

Scenario:
- Spawn an emitter entity at origin with CPoison + CAreaEffect(radius=200,
  apply_poison=true, affects_enemies=true) + CTransform + CCamp(PLAYER).
- Spawn a target enemy at position (50, 0) with CHP, CTransform, CCamp(ENEMY).
- Advance one physics frame.

Assertions:
- target.has_component(CElementalAffliction) is true
- CElementalAffliction.entries contains POISON key
- entries[POISON]["stacks"] == 1 (edge trigger)
- emitter's CAreaEffect.poison_exposure_timers has target as a key with
  value 0.0

Use the existing test recipes if they exist for player/enemy spawning.
Otherwise construct via CPoison.new() etc. and ensure auto_free via the
SceneConfig base class lifecycle.
Required systems in the scene config: SPoison.
```

- [ ] **Step 2: Delegate the interval accumulation test**

`task()`:
```
Create tests/integration/test_poison_aoe_interval_accumulation_scene.gd
(extends SceneConfig).

Scenario:
- Emitter with CPoison (aoe_stack_interval=5.0) + CAreaEffect(apply_poison=true).
- Enemy target in range.
- Apply one frame → stacks should become 1 (edge trigger).
- Advance simulated time by 5.1 seconds (use whatever time-advance API
  SceneConfig tests use — check existing integration tests for the pattern).
- After the advance, stacks should be 2.
- Advance another 5.1 seconds → stacks should be 3.

If SceneConfig's time advancement is frame-based, figure out the target
frame count to cover 5.1 seconds of gameplay and document in the test
comment. If the project has a test-time fake-clock pattern, use that.
```

- [ ] **Step 3: Delegate the leave-reset test**

`task()`:
```
Create tests/integration/test_poison_aoe_leave_reset_scene.gd (extends SceneConfig).

Scenario:
- Emitter with CPoison(aoe_stack_interval=5.0) + CAreaEffect(radius=100,
  apply_poison=true) at origin.
- Target at (50, 0). Edge trigger gives 1 stack. Advance 3 seconds.
- At this point, target's entry in emitter.poison_exposure_timers should
  be ~3.0 (not yet reached 5.0).
- Teleport target to (300, 0) — out of range.
- Advance one frame.
- Assertion: emitter.poison_exposure_timers no longer contains target as
  a key. Target's accumulation_progress (if entry still exists) is 0.0.
- Teleport target back to (50, 0). Advance 4 seconds.
- Assertion: no new stack has been applied yet (timer should be at 4,
  not at 4+3).
- Advance another 1.5 seconds (total 5.5 since re-entry).
- Assertion: stacks == 2 (the 5s cadence completed from the fresh re-entry
  timer).

NOTE: because target still had 1 stack from the original edge trigger,
re-entry takes the elapsed branch, not the stacks==0 branch. So no
immediate +1 on re-entry — the 5s wait is fresh. This matches the spec.
```

- [ ] **Step 4: Delegate the decay pause test**

`task()`:
```
Create tests/integration/test_poison_aoe_decay_pause_scene.gd (extends SceneConfig).

Scenario:
- Emitter CPoison(decay_interval=3.0, aoe_stack_interval=5.0) + CAreaEffect
- Target in range. Accumulate to 3 stacks (advance 11 seconds — edge + two 5s cycles).
- Verify stacks == 3.
- Advance 10 seconds while target stays in range.
- Assertion: stacks stayed >= 3 (should be 5 after 2 more cycles; the key
  assertion is stacks did NOT decay below 3). decay_timer should be ~0
  each frame because Pass A keeps resetting it.
- Teleport target out of range. Advance 9.1 seconds.
- Assertion: stacks decayed by 3 (at -1 per 3 seconds). Final stacks == 2
  (or whatever the value was before minus 3).
```

- [ ] **Step 5: Delegate the overlap test**

`task()`:
```
Create tests/integration/test_poison_aoe_overlap_scene.gd (extends SceneConfig).

Scenario:
- Two emitters at (0,0) and (10,0), each with CPoison + CAreaEffect(radius=200,
  apply_poison=true). Both emitters have independent poison_exposure_timers.
- Target at (5, 0), in range of both clouds.
- Edge trigger: target gets 1 stack (from whichever emitter runs first; doesn't
  matter which).
- Advance 5.1 seconds. Both emitter's exposure timers should have elapsed
  5.1s, so both apply +1 stacks.
- Assertion: stacks == 3 (edge trigger + 2 overlapping contributions).
- If the test framework allows it, assert this again after another 5.1s:
  stacks == 5 (each cloud contributes 1 per 5s cycle).
```

- [ ] **Step 6: Delegate the AoE+on-hit mutex test**

`task()`:
```
Create tests/integration/test_poison_aoe_mutex_onhit_scene.gd (extends SceneConfig).

Scenario:
- Attacker with CPoison + CAreaEffect(apply_poison=true, radius=200) + CMelee
  (range=30, damage=5).
- Enemy in melee range (position 20, 0).
- Trigger a melee attack via CMelee.attack_pending = true and attack_direction.
- Advance one frame (melee and SPoison both tick).

Assertion:
- target has exactly 1 stack (from AoE edge trigger). The on-hit path is
  suppressed by the mutex — only AoE applied.
- Compare with a control case: same setup but apply_poison=false on the
  CAreaEffect. In that case, the attacker is NOT an AoE poison emitter
  (because apply_poison is false), so on-hit DOES fire. Target should
  have 1 stack from on-hit instead. (Note: no AoE stack because
  apply_poison gates the AoE path too.)

This test verifies that apply_poison is the single switch between modes.
```

- [ ] **Step 7: Delegate the keep-best merge test**

`task()`:
```
Create tests/integration/test_poison_keep_best_merge_scene.gd (extends SceneConfig).

Scenario:
- Two emitters, both AoE poison, overlapping on a target:
    emitterA: damage_coeff_a=1.0, max_stacks=15
    emitterB: damage_coeff_a=3.0, max_stacks=5
- Both apply edge triggers on the same frame.
- Accumulate several stacks (advance enough seconds).

Assertion:
- entries[POISON]["damage_coeff_a"] == 3.0 (max)
- entries[POISON]["max_stacks"] == 15 (max)
- stacks grows to 15 eventually (merged ceiling)
- Verify that the DPS calculation at stacks=15 uses the merged coefficients
  via a snapshot of CDamage.piercing_amount over several ticks.
```

- [ ] **Step 8: Run all the Pass A integration tests**

Delegate via `gol-test-runner`:
```
Run these integration tests and report PASS/FAIL per case:
- tests/integration/test_poison_aoe_edge_trigger_scene.gd
- tests/integration/test_poison_aoe_interval_accumulation_scene.gd
- tests/integration/test_poison_aoe_leave_reset_scene.gd
- tests/integration/test_poison_aoe_decay_pause_scene.gd
- tests/integration/test_poison_aoe_overlap_scene.gd
- tests/integration/test_poison_aoe_mutex_onhit_scene.gd
- tests/integration/test_poison_keep_best_merge_scene.gd

Diagnose any failures. If the mutex test fails, SAreaEffectModifier's old
poison channel is likely still firing in parallel — this is expected until
Task 13 removes it. If the mutex test fails here, flag it as "expected to
pass after Task 13" and move on. All other tests should pass now.
```

- [ ] **Step 9: Commit**

```bash
git add tests/integration/test_poison_aoe_*.gd tests/integration/test_poison_keep_best_*.gd
git commit -m "test(poison): integration tests for SPoison AoE delivery

Covers edge trigger, interval accumulation, leave-reset, decay pause,
overlap, AoE/on-hit mutex, and keep-best merge across sources."
```

---

## Task 11: Remove poison channel from `SAreaEffectModifier`

**Files:**
- Modify: `scripts/systems/s_area_effect_modifier.gd`

- [ ] **Step 1: Delete poison-related code**

In `scripts/systems/s_area_effect_modifier.gd`:
1. Remove the `const _CPoison := preload(...)` line at the top.
2. Delete the `_apply_poison_damage` function.
3. Delete the `_should_apply_poison` function.
4. Remove the `apply_poison` term from `_has_channel_overrides`:
   ```gdscript
   # Before
   return area_effect.apply_melee or area_effect.apply_healer or area_effect.apply_poison
   # After
   return area_effect.apply_melee or area_effect.apply_healer
   ```
5. Remove the poison branch from `_apply_effects`:
   ```gdscript
   # Delete these lines
   if _should_apply_poison(area_effect) and source.has_component(_CPoison):
       _apply_poison_damage(source, target, area_effect, delta)
   ```

- [ ] **Step 2: Verify the file still parses + existing tests still pass**

Delegate via `gol-test-runner`:
```
Run the full tests/unit/ suite plus tests/integration/test_poison_aoe_*.gd.
Report PASS/FAIL. The AoE+on-hit mutex test that was flagged in Task 10
should now PASS because only SPoison is emitting poison.
```

- [ ] **Step 3: Commit**

```bash
git add scripts/systems/s_area_effect_modifier.gd
git commit -m "refactor(poison): remove poison channel from SAreaEffectModifier

SPoison is now the sole system applying poison stacks. SAreaEffectModifier
is back to handling only CMelee and CHealer channels — one less
responsibility per system. The apply_poison flag on CAreaEffect stays
(still used by SPoison.Pass A to select which emitters poison targets)."
```

---

## Task 12: On-hit delivery — wire `SMeleeAttack`

**Files:**
- Modify: `scripts/systems/s_melee_attack.gd`
- Test: delegated

- [ ] **Step 1: Add the PoisonUtils call**

Find `_apply_on_hit_element` in `s_melee_attack.gd`:

```gdscript
func _apply_on_hit_element(attacker: Entity, target: Entity) -> void:
    ELEMENTAL_UTILS.apply_attack(attacker, target)
```

Replace with:

```gdscript
func _apply_on_hit_element(attacker: Entity, target: Entity) -> void:
    ELEMENTAL_UTILS.apply_attack(attacker, target)
    PoisonUtils.apply_on_hit(attacker, target)
```

- [ ] **Step 2: Delegate the on-hit melee integration test**

`task()` category `deep`, skill `gol-test-writer-integration`, prompt:

```
Create tests/integration/test_poison_on_hit_melee_scene.gd (extends SceneConfig).

Scenario:
- Player with CPoison (defaults) + CMelee(damage=5, range=30, attack_interval=1.0)
  at origin.
- Enemy with CHP(hp=100, max_hp=100) + CTransform + CCamp(ENEMY) at (20, 0).
- Set player's CMelee.attack_pending = true and attack_direction = Vector2.RIGHT.
- Advance one physics frame so SMeleeAttack fires.

Assertions:
- Enemy has CElementalAffliction with entries[POISON]["stacks"] == 1
- Enemy's HP has been decremented by the melee damage (normal melee path)
  — verify poison didn't break elemental/melee damage
- entries[POISON]["source_entity"] == player
- entries[POISON]["damage_coeff_a"] matches the player's CPoison defaults

Additional case: advance time by 1.0 seconds (2 tick intervals) and verify
HP decreased further due to poison ticks. Expected additional damage:
2 ticks × (1.5 * 1 + 0.5) * 0.5 = 2 × 1.0 = 2.0 HP from poison.
```

- [ ] **Step 3: Run the test**

```
Delegate to gol-test-runner:
Run tests/integration/test_poison_on_hit_melee_scene.gd. Report PASS/FAIL.
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/systems/s_melee_attack.gd \
        tests/integration/test_poison_on_hit_melee_scene.gd
git commit -m "feat(poison): wire on-hit poison delivery for melee attacks

SMeleeAttack._apply_on_hit_element now calls PoisonUtils.apply_on_hit
alongside the existing ELEMENTAL_UTILS.apply_attack. Both hooks are
invoked symmetrically — poison and elemental afflictions trigger on
every successful melee hit."
```

---

## Task 13: On-hit delivery — wire `SDamage` bullet path

**Files:**
- Modify: `scripts/systems/s_damage.gd`
- Test: delegated

- [ ] **Step 1: Add the PoisonUtils call**

Find `_apply_bullet_effects` in `s_damage.gd`:

```gdscript
func _apply_bullet_effects(bullet_entity: Entity, target_entity: Entity) -> void:
    var bullet: CBullet = bullet_entity.get_component(CBullet)
    if not bullet or not bullet.owner_entity or not is_instance_valid(bullet.owner_entity):
        return
    # Generic elemental path: if the bullet's owner has CElementalAttack, apply it to the target
    if bullet.owner_entity.has_component(COMPONENT_ELEMENTAL_ATTACK):
        ELEMENTAL_UTILS.apply_attack(bullet.owner_entity, target_entity)
```

Add one line at the end of the function body:

```gdscript
    PoisonUtils.apply_on_hit(bullet.owner_entity, target_entity)
```

- [ ] **Step 2: Delegate the on-hit bullet integration test**

`task()` category `deep`, skill `gol-test-writer-integration`, prompt:

```
Create tests/integration/test_poison_on_hit_bullet_scene.gd (extends SceneConfig).

Scenario:
- Player with CPoison (defaults) at origin.
- Enemy with CHP + CTransform + CCamp(ENEMY) at (100, 0).
- Spawn a bullet entity with CBullet(owner_entity=player, damage=10) +
  CTransform(position=(95, 0)) + CCollision + CMovement(velocity=Vector2.RIGHT * 100)
  so it's about to collide with the enemy.
- Advance physics frames until the bullet hits the enemy (1 or 2 frames).

Assertions:
- Enemy has CElementalAffliction with entries[POISON]["stacks"] == 1
- Enemy HP decreased by bullet damage (normal bullet path works)
- source_entity in entries[POISON] == player (not the bullet)

Check existing integration tests for the recipe/pattern to spawn bullets
(e.g., tests/integration/test_combat.gd if present).
```

- [ ] **Step 3: Run the test**

```
Delegate to gol-test-runner:
Run tests/integration/test_poison_on_hit_bullet_scene.gd. Report PASS/FAIL.
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/systems/s_damage.gd \
        tests/integration/test_poison_on_hit_bullet_scene.gd
git commit -m "feat(poison): wire on-hit poison delivery for bullets

SDamage._apply_bullet_effects now calls PoisonUtils.apply_on_hit using
bullet.owner_entity as the poison source. Matches the existing elemental
attack pattern — the shooter is the poison source, not the bullet itself."
```

---

## Task 14: Bug #1 regression test — drop on lethal

This is the test that proves bug #1 is fixed. It should have failed on main before this work and pass now.

**Files:**
- Test: delegated to `tests/integration/test_poison_drop_on_lethal_scene.gd`

- [ ] **Step 1: Delegate the regression test**

`task()` category `deep`, skill `gol-test-writer-integration`, prompt:

```
Create tests/integration/test_poison_drop_on_lethal_scene.gd (extends SceneConfig).

Purpose: REGRESSION TEST for a historical bug — enemies killed by poison
damage must drop a CPoison component box per the losable-component pipeline
in SDamage._on_no_hp. Before the poison redesign, CPoison was handled by
SAreaEffectModifier as a direct damage writer and never participated in
the losable drops.

Scenario:
- Emitter (player) with CPoison (defaults) + CAreaEffect(radius=200,
  apply_poison=true, affects_enemies=true) at origin.
- Enemy with CHP(hp=5, max_hp=5) + CTransform + CCamp(ENEMY) at (50, 0).
  HP is low so poison kills quickly. Also add CPoison to the enemy so
  it is eligible for component loss on lethal damage (losable pipeline
  picks a losable component to drop).
- Advance simulated time until enemy HP reaches 0 from poison ticks.

Assertions:
- After enemy death, a new entity exists in the world with CContainer
  (the drop box). Scan ECS.world.query.with_all([CContainer]).execute()
  and look for a CContainer where stored_components contains a CPoison.
- OR assert enemy.has_component(CPoison) == false after the drop
  (component was lost).
- OR both.

This test is the acceptance criterion for the "poison sources now drop
on the map" part of the redesign.
```

- [ ] **Step 2: Run the test**

```
Delegate to gol-test-runner:
Run tests/integration/test_poison_drop_on_lethal_scene.gd. Report PASS/FAIL.
```
Expected: PASS. If it fails, diagnose whether CPoison is losable (check
ECSUtils.is_losable_component behavior) or whether the enemy is actually
dying from poison ticks.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_poison_drop_on_lethal_scene.gd
git commit -m "test(poison): regression test for CPoison drop on lethal damage

Acceptance test for bug #1 fix. Enemies killed by poison DoT must drop
a CPoison component box via the existing SDamage._on_no_hp losable
pipeline. Before the poison redesign this was impossible because
CPoison had no standalone tick path — it only existed as an
SAreaEffectModifier data source."
```

---

## Task 15: Create `poison_icon.gdshader`

**Files:**
- Create: `resources/poison_icon.gdshader`

- [ ] **Step 1: Create the shader file**

```bash
mkdir -p /Users/dluckdu/Documents/Github/gol/.worktrees/poison-redesign/resources
```

Create `resources/poison_icon.gdshader`:

```glsl
shader_type canvas_item;

// Progress value 0..1 — driven by SPoison via the view.
// Represents max(accumulation_progress, 1 - decay_timer / decay_interval).
uniform float progress : hint_range(0.0, 1.0) = 0.0;

// Visual tunables — exposed as uniforms for easy tweaking without touching code.
uniform vec4 base_color : source_color    = vec4(0.35, 0.80, 0.30, 1.0);  // poison green
uniform vec4 overlay_color : source_color = vec4(0.00, 0.00, 0.00, 0.55); // semi-transparent dim
uniform vec4 edge_color : source_color    = vec4(1.00, 1.00, 1.00, 1.0);  // progress line
uniform float edge_thickness : hint_range(0.0, 0.1) = 0.025;

void fragment() {
    vec4 col = base_color;

    // Overlay covers UV.y ∈ (progress, 1] — icon revealed from the top as progress grows.
    // At progress=0 the entire icon is covered; at progress=1 nothing is covered.
    if (UV.y > progress) {
        col = mix(col, overlay_color, overlay_color.a);
    }

    // Thin horizontal edge line at UV.y == progress, drawn only when mid-animation.
    float edge_dist = abs(UV.y - progress);
    if (edge_dist < edge_thickness && progress > 0.0 && progress < 1.0) {
        col = mix(col, edge_color, edge_color.a);
    }

    COLOR = col;
}
```

- [ ] **Step 2: Commit**

```bash
git add resources/poison_icon.gdshader
git commit -m "feat(ui): poison status icon shader

Minimal single-pass canvas_item shader. Renders the base green color,
overlays a semi-transparent dim on the bottom (1-progress) portion of
the icon, and draws a thin white edge line at the current progress
boundary. No external assets required."
```

---

## Task 16: Create `PoisonStatusIcon` scene + wire view factory

**Files:**
- Create: `scenes/ui/poison_status_icon.tscn`
- Modify: `scripts/ui/views/view_hp_bar.gd`

- [ ] **Step 1: Author the scene**

Create `scenes/ui/poison_status_icon.tscn`. Godot scene format — use the Godot editor OR hand-write a minimal scene file. The node tree is:

```
PoisonStatusIcon (Control, size=(32, 32))
├── Icon (ColorRect)
│   - anchor_left=0, anchor_top=0, anchor_right=1, anchor_bottom=1
│   - color = Color(1, 1, 1, 1)  (base_color lives in shader, overridden per-instance if needed)
│   - material = ShaderMaterial with shader = preload("res://resources/poison_icon.gdshader")
└── StackLabel (Label)
    - anchor_right=1, anchor_bottom=1
    - offset_left=-14, offset_top=-14
    - text = "0"
    - theme_font_size overrides as appropriate for 32x32
```

Recommended approach: open the Godot editor, create the scene via the UI to get proper .tscn metadata (uid, type hints), save it, then commit. If editing by hand, check an existing small .tscn in `scenes/ui/` for the header format.

- [ ] **Step 2: Create a matching script if needed**

If the existing `view_hp_bar.gd` icon factory expects each icon type to have a dedicated script that exposes a `set_state(entry: Dictionary)` method or similar, create `scripts/ui/views/poison_status_icon.gd`:

```gdscript
class_name PoisonStatusIcon
extends Control

@onready var _icon: ColorRect = $Icon
@onready var _stack_label: Label = $StackLabel
var _material: ShaderMaterial


func _ready() -> void:
    if _icon.material is ShaderMaterial:
        _material = _icon.material.duplicate() as ShaderMaterial
        _icon.material = _material
    else:
        _material = ShaderMaterial.new()
        _material.shader = preload("res://resources/poison_icon.gdshader")
        _icon.material = _material


## Update the icon from the current poison entry dictionary.
## Call whenever the bound entry changes.
func update_from_entry(entry: Dictionary) -> void:
    if entry.is_empty():
        visible = false
        return
    visible = true
    var accumulation := float(entry.get("accumulation_progress", 0.0))
    var decay_timer := float(entry.get("decay_timer", 0.0))
    var decay_interval := float(entry.get("decay_interval", 1.0))
    var progress: float = maxf(accumulation, 1.0 - decay_timer / decay_interval)
    _material.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
    _stack_label.text = str(int(entry.get("stacks", 0)))
```

Attach this as the root script of `PoisonStatusIcon.tscn`.

- [ ] **Step 3: Extend `view_hp_bar.gd` icon factory**

Read `scripts/ui/views/view_hp_bar.gd` and find where it iterates `entries` and creates icons per element type. Look for something like `match element_type:` with FIRE / WET / COLD / ELECTRIC cases. Add a POISON branch that instantiates `PoisonStatusIcon.tscn`:

```gdscript
const POISON_STATUS_ICON_SCENE = preload("res://scenes/ui/poison_status_icon.tscn")

# ... inside the factory function that builds an icon for an entry ...
match element_type:
    # ... existing FIRE / WET / COLD / ELECTRIC cases ...
    CElementalAttack.ElementType.POISON:
        var icon: PoisonStatusIcon = POISON_STATUS_ICON_SCENE.instantiate()
        icon.update_from_entry(entry)
        return icon
```

Also find the per-frame / per-event update path in `view_hp_bar.gd` and make sure it calls `icon.update_from_entry(entry)` when the bound entry changes. If the existing views just re-create the icon on entries_changed, do the same — the factory call is enough.

- [ ] **Step 4: Manual QA smoke test**

Open Godot editor, run the game, give the player a `CPoison + CAreaEffect(apply_poison=true)` via whatever debug command exists (`spawn_box` or similar), walk near an enemy, verify:
- Poison icon appears on the enemy's HP bar
- Stack count visible in bottom-right
- Icon mask animates as accumulation progresses
- Icon disappears after decay finishes

This is a manual step — agentic execution may need to flag this for a human QA pass.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/poison_status_icon.tscn \
        scripts/ui/views/poison_status_icon.gd \
        scripts/ui/views/view_hp_bar.gd
git commit -m "feat(ui): poison status icon with animated mask and stack count

PoisonStatusIcon is a 32x32 Control with a ColorRect using the poison
shader and a Label for the stack count badge. view_hp_bar.gd's icon
factory gains a POISON case that instantiates the scene and binds it
to the entries_changed signal via the existing ViewModel_HPBar path —
no ViewModel changes required."
```

---

## Task 17: Bug #2 regression test — icon visible on stack gain

**Files:**
- Test: delegated to `tests/integration/test_poison_icon_visible_scene.gd`

- [ ] **Step 1: Delegate the test**

`task()` category `deep`, skill `gol-test-writer-integration`, prompt:

```
Create tests/integration/test_poison_icon_visible_scene.gd (extends SceneConfig).

Purpose: REGRESSION TEST for bug #2 — when poison is applied to a target,
the UI must receive a notification so the status icon can render. Before
this redesign, poison had no target-side state and never triggered the
HP bar's entries_changed signal.

Scenario:
- Player with CPoison + CAreaEffect(apply_poison=true) at origin.
- Enemy with CHP + CTransform + CCamp(ENEMY) at (50, 0).
- ViewModel_HPBar must be initialized with a binding to the enemy entity.
- Attach a counter to ViewModel_HPBar.elemental_entries[enemy].
  value_changed (or equivalent ObservableProperty signal).
- Advance one physics frame so SPoison.Pass A triggers the edge +1 stack.

Assertions:
- The ObservableProperty's stored dictionary contains a POISON key after
  the frame.
- The signal counter is >= 1 (the dictionary value was updated).

This test verifies the UI wire-up WITHOUT needing a headless rendering
backend. We test that the DATA flows through the ViewModel — the shader
rendering itself is covered by manual QA in Task 16 Step 4.
```

- [ ] **Step 2: Run the test**

```
Delegate to gol-test-runner:
Run tests/integration/test_poison_icon_visible_scene.gd. Report PASS/FAIL.
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/test_poison_icon_visible_scene.gd
git commit -m "test(poison): regression test for UI icon visibility on stack gain

Verifies the entries_changed signal chain: SPoison applies stack →
PoisonUtils emits entries_changed → ViewModel_HPBar.elemental_entries
ObservableProperty updates → any bound view refreshes. Locks in the
bug #2 fix at the data-flow layer without needing a rendering harness."
```

---

## Task 18: Full test pass, branch push, submodule bump

**Files:** none directly modified; branch / submodule housekeeping only.

- [ ] **Step 1: Run the full test suite**

Delegate via `gol-test-runner`:
```
Run the full test suite:
- All unit tests in tests/unit/
- All integration tests in tests/integration/

Report PASS/FAIL per file. Diagnose any failures.
```
Expected: all PASS. Any regression indicates a bug somewhere above; fix before proceeding.

- [ ] **Step 2: Manual UI QA checklist**

Open Godot editor, run the game, verify each of:
- Player gains CPoison via debug drop → on-hit poison stacks appear on enemies
- Player gains CAreaEffect(apply_poison=true) → radius poison cloud visible via status icon on enemies
- Enemy dies from poison → drops CPoison component box on the map
- Poison icon stack count badge reads correctly
- Icon mask animates smoothly (accumulation fill + decay drain)

This is a manual agent step. If running autonomously and unable to start Godot, flag each unverified item as "requires manual QA" in the summary.

- [ ] **Step 3: Verify branch history**

```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/poison-redesign
git log --oneline origin/main..HEAD
```
Expected: ~17 commits covering Tasks 2–17 (Task 1 created the branch; Task 18 is housekeeping).

- [ ] **Step 4: Push the feature branch**

```bash
git push -u origin feat/poison-redesign
```

If a pre-push hook fails, diagnose and fix — do not bypass.

- [ ] **Step 5: Update the management repo submodule pointer**

```bash
cd /Users/dluckdu/Documents/Github/gol
git add gol-project
git status
```

Verify the only staged change is `gol-project` (new commit hash). Commit:

```bash
git commit -m "chore: bump gol-project submodule (poison redesign feat branch)

Two-layer poison system with dedicated SPoison. Feature branch
feat/poison-redesign pending PR review on the submodule side.

Spec: docs/superpowers/specs/2026-04-14-poison-redesign-design.md
Plan: docs/superpowers/plans/2026-04-14-poison-redesign.md"
```

Note: this commits the submodule pointer to the **tip of the feature branch**, not main. That's intentional — it lets the management repo reference the in-progress work while the PR is still open.

- [ ] **Step 6: Push management repo**

```bash
git push origin main
```

- [ ] **Step 7: Open a PR on the submodule (optional, depending on project workflow)**

If the project uses PRs:

```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/poison-redesign
gh pr create --title "feat(poison): two-layer poison system with dedicated SPoison" --body "$(cat <<'EOF'
## Summary

- Rewrites poison as a two-layer system: shared effect layer in `CElementalAffliction.entries[POISON]` + two delivery modes (AoE via new `SPoison` system, on-hit via `SMeleeAttack`/`SDamage` hooks).
- Concentrates all poison-specific logic in a new `SPoison` system — removes poison branches from `SAreaEffectModifier` and adds one skip guard to `SElementalAffliction`.
- `CPoison` becomes a per-instance tuned component with keep-best `on_merge` and keep-best entry-level merging across sources.
- Fixes two legacy bugs: CPoison now drops on lethal damage (bug #1) and has a visible status icon with animated progress mask (bug #2).

Spec: `docs/superpowers/specs/2026-04-14-poison-redesign-design.md`
Plan: `docs/superpowers/plans/2026-04-14-poison-redesign.md`

## Test plan

- [ ] All unit tests pass (`tests/unit/`)
- [ ] All integration tests pass (`tests/integration/`)
- [ ] Manual QA: on-hit poison applies stacks via melee
- [ ] Manual QA: on-hit poison applies stacks via bullet
- [ ] Manual QA: AoE poison cloud stacks on enemies in radius
- [ ] Manual QA: enemy killed by poison drops CPoison box
- [ ] Manual QA: poison status icon visible with animated mask + stack count

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Post-plan notes

- **Worktree cleanup** after the PR merges (handle in the next session, not this plan):
  ```bash
  cd /Users/dluckdu/Documents/Github/gol/gol-project
  git worktree remove /Users/dluckdu/Documents/Github/gol/.worktrees/poison-redesign
  ```
- **Deferred work** (not this plan):
  - Rename `CElementalAffliction` → `CStatusEffects` when a third non-elemental, non-poison status effect is added.
  - Balance pass on `damage_coeff_a`, `damage_coeff_b`, `max_stacks`, `aoe_stack_interval`, `decay_interval`.
  - Proper poison icon art to replace the placeholder `ColorRect` green.

---

## Self-Review

**Spec coverage check (against `2026-04-14-poison-redesign-design.md`):**
- §3 Two-layer architecture → Tasks 9, 12, 13 (SPoison, on-hit wiring).
- §4.1 `CPoison` rewrite → Task 4.
- §4.2 `CAreaEffect.poison_exposure_timers` → Task 7.
- §4.3 `ElementType.POISON` + entry schema → Task 2; schema is materialized inside `PoisonUtils.apply_stack` in Task 6.
- §4.4 Naming debt deferred → documented in Post-plan notes.
- §5.1 `SPoison` Pass A + Pass B → Task 9.
- §5.2 `POISON_UTILS.apply_stack` → Task 6.
- §5.3 `POISON_UTILS.apply_on_hit` → Task 6.
- §5.4 `SElementalAffliction` POISON guard → Task 5.
- §5.5 `SAreaEffectModifier` poison channel removal → Task 11.
- §5.6 `AreaEffectUtils.find_targets_in_range` → Task 3.
- §5.7 On-hit hook integration → Tasks 12, 13.
- §6 UI integration (shader, scene, view factory) → Tasks 15, 16.
- §8 Edge cases → covered by integration tests in Tasks 10, 12, 13, 14, 17.
- §9 Test strategy → unit tests in Tasks 4, 5, 6; integration tests in Tasks 10, 12, 13, 14, 17.
- §10 Migration order → preserved in task order.
- §11 Open questions → single-system form used in Task 9 (matches spec default).

All sections covered.

**Placeholder scan:** No TBD / TODO / "implement later" / "handle edge cases" / vague references found. All test steps are delegations with complete specs. All code steps contain full code blocks.

**Type consistency:**
- `CPoison` fields: `damage_coeff_a`, `damage_coeff_b`, `max_stacks`, `aoe_stack_interval`, `decay_interval`, `tick_interval` — consistent across Tasks 4, 6, 9.
- `POISON_UTILS` vs `PoisonUtils`: the class is declared as `class_name PoisonUtils` in Task 6, so calls use `PoisonUtils.apply_stack` / `PoisonUtils.apply_on_hit`. The spec text uses `POISON_UTILS` colloquially; the plan consistently uses `PoisonUtils`.
- `entries[POISON]` dict keys: `stacks`, `max_stacks`, `decay_timer`, `decay_interval`, `tick_timer`, `tick_interval`, `damage_coeff_a`, `damage_coeff_b`, `accumulation_progress`, `source_entity`, `element_type` — consistent across Tasks 6, 9.
- `ElementType.POISON` referenced as `CElementalAttack.ElementType.POISON` (fully qualified) or via `POISON_KEY` const — consistent.
- `find_targets_in_range` returns `Array` (not `Array[Entity]`) in Task 3 to match the existing GECS query return pattern — Task 9 calls match.
- `apply_stack(target, count, source)` signature stays identical across the utility definition, Pass A call site, and `apply_on_hit` forwarding call.

No inconsistencies found.
