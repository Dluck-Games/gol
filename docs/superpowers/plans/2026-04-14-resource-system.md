# Resource System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the general resource substrate (CStockpile + Script-ref resource types) and deliver a vertical slice (PCG trees → GOAP worker → camp cube → HUD) that proves the architecture end-to-end, while migrating `PlayerData.component_points` into the new layer.

**Architecture:** Four new ECS components (`CStockpile`, `CResourceNode`, `CCarrying`, `CWorker`) plus a `Script`-reference convention for resource types (`RWood`, `RComponentPoint`). A new GOAP goal `Work` with 5 new actions drives an autonomous worker NPC. `PlayerData.component_points` is deleted and replaced by a `CStockpile` on the player entity; `composer_utils` and HUD/composer viewmodels rebind accordingly.

**Tech Stack:** GDScript / Godot 4.6, GECS, existing GOAP planner, gdUnit4 (unit tests), SceneConfig (integration tests).

**Spec:** `docs/superpowers/specs/2026-04-14-resource-system-design.md`

---

## Pre-flight: Read These First

Before starting Task 1, the implementing agent should read these for orientation:

1. **Spec:** `docs/superpowers/specs/2026-04-14-resource-system-design.md` — the design this plan implements. **Non-negotiable.** Every decision lives there.
2. **Testing rules:** `gol-project/tests/AGENTS.md` — three-tier test architecture and delegation rules.
3. **Component catalog:** `gol-project/scripts/components/AGENTS.md` — existing component patterns, ObservableProperty usage.
4. **System patterns:** `gol-project/scripts/systems/AGENTS.md` — query shape, group assignment.
5. **GOAP architecture:** `gol-project/scripts/gameplay/AGENTS.md` — existing facts, goals, action patterns.
6. **PCG orientation:** `gol-project/scripts/pcg/AGENTS.md` — pipeline phase structure (this plan adds tree spawning in `GOLWorld`, not a new PCG phase, but the implementer should understand the context).

**Testing delegation rule (from `gol/CLAUDE.md`):** Main agents NEVER write or run tests directly. Delegate via `task(category=quick, load_skills=["gol-test-writer-unit"], prompt=...)` for unit tests, `task(category=deep, load_skills=["gol-test-writer-integration"], ...)` for integration tests, and `task(category=quick, load_skills=["gol-test-runner"], prompt=...)` for running them. The plan steps that say "write test" / "run test" MUST be executed via that delegation pattern, not by editing test files directly.

**Branching (from project memory):** gol-project submodule uses feature branches — never commit directly to `main`. All work happens in a worktree with a feature branch.

---

## Pre-flight: Worktree Setup

### Task 0: Create worktree and feature branch

**Files:** none

- [ ] **Step 1: Create the worktree and branch**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
git fetch origin main
git worktree add -b feat/resource-system ../.worktrees/manual/resource-system origin/main
```

Expected: new directory at `gol/.worktrees/manual/resource-system` containing a gol-project checkout on branch `feat/resource-system`.

- [ ] **Step 2: Verify**

```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/manual/resource-system
git status
git branch --show-current
```

Expected:
- `git status` clean
- branch: `feat/resource-system`

**All remaining tasks happen inside `gol/.worktrees/manual/resource-system`.**

---

## File Structure

### New files (29)

**Resource type classes (2):**
- `scripts/resources/r_wood.gd`
- `scripts/resources/r_component_point.gd`

**ECS components (4):**
- `scripts/components/c_stockpile.gd`
- `scripts/components/c_resource_node.gd`
- `scripts/components/c_carrying.gd`
- `scripts/components/c_worker.gd`

**GOAP actions (5):** (file names follow existing convention — no `goap_action_` prefix; class names do use the `GoapAction_` prefix)
- `scripts/gameplay/goap/actions/find_work_target.gd` → `class_name GoapAction_FindWorkTarget`
- `scripts/gameplay/goap/actions/move_to_resource_node.gd` → `class_name GoapAction_MoveToResourceNode`
- `scripts/gameplay/goap/actions/gather_resource.gd` → `class_name GoapAction_GatherResource`
- `scripts/gameplay/goap/actions/move_to_stockpile.gd` → `class_name GoapAction_MoveToStockpile`
- `scripts/gameplay/goap/actions/deposit_resource.gd` → `class_name GoapAction_DepositResource`

**GOAP goal (1):**
- `resources/goals/work.tres`

**Entity recipes (3):**
- `resources/recipes/npc_worker.tres`
- `resources/recipes/camp_stockpile.tres`
- `resources/recipes/tree.tres`

**UI scene (2):**
- `scenes/ui/progress_bar.tscn`
- `scripts/ui/views/view_progress_bar.gd`

**Unit tests (4 new + 1 rewrite):**
- `tests/unit/test_cstockpile.gd` (new)
- `tests/unit/test_cresource_node.gd` (new)
- `tests/unit/test_goap_action_find_work_target.gd` (new)
- `tests/unit/test_goap_action_deposit_resource.gd` (new)
- `tests/unit/test_composer_utils.gd` (**REWRITE** — already exists at this path; currently tests the old `PlayerData.component_points` path)

**Integration tests (2 new + 1 modify):**
- `tests/integration/flow/test_flow_worker_gather.gd`
- `tests/integration/flow/test_flow_worker_flee.gd`

**Docs (optional):**
- Update `scripts/components/AGENTS.md`, `scripts/systems/AGENTS.md`, `scripts/gameplay/AGENTS.md` catalogs.

### Modified files (9)

- `scripts/gameplay/player_data.gd` — delete `component_points`, `points_changed`
- `scripts/utils/composer_utils.gd` — migrate `craft_component` / `dismantle_component` to use player entity's `CStockpile`
- `scripts/ui/viewmodels/viewmodel_hud.gd` — rebind to player `CStockpile`, add wood observable bound to camp cube `CStockpile`
- `scripts/ui/viewmodels/viewmodel_composer.gd` — rebind to player `CStockpile`
- `scripts/ui/views/view_hud.gd` — add wood label, wire to new observable
- `scenes/ui/view_hud.tscn` — add `WoodPanel` node
- `scripts/ui/views/view_composer.gd` — rebind disabled-button check
- `scripts/gameplay/ecs/gol_world.gd` — spawn camp stockpile + worker, add `CStockpile` to player entity, scatter trees
- `scripts/configs/config.gd` — new constants
- `scripts/gameplay/goap/actions/move_to.gd` (read to understand base class — no modification needed)
- `scripts/systems/s_ai.gd` — clear `has_delivered` after Work goal plan completes
- `tests/integration/flow/test_flow_composer_scene.gd` (if exists) — adapt to new signatures

---

## Task 1: Resource type classes (RWood, RComponentPoint)

**Files:**
- Create: `scripts/resources/r_wood.gd`
- Create: `scripts/resources/r_component_point.gd`

No tests — these are const-only classes with no behavior.

- [ ] **Step 1: Create `scripts/resources/` directory (if missing) and `r_wood.gd`**

```gdscript
# scripts/resources/r_wood.gd
class_name RWood
extends Resource

const DISPLAY_NAME: String = "木材"
const ICON_PATH: String = "res://assets/icons/resources/wood.png"
const MAX_STACK: int = 999
```

- [ ] **Step 2: Create `r_component_point.gd`**

```gdscript
# scripts/resources/r_component_point.gd
class_name RComponentPoint
extends Resource

const DISPLAY_NAME: String = "组件点"
const ICON_PATH: String = "res://assets/icons/resources/component_point.png"
const MAX_STACK: int = 9999
```

- [ ] **Step 3: Verify Godot parse**

Run in the worktree:
```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/manual/resource-system
# Let Godot compile-check by opening headlessly
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

Expected: `No parse errors`. If Godot complains about missing icon paths, that's fine — the icon paths are string constants, not preloaded assets.

- [ ] **Step 4: Commit**

```bash
git add scripts/resources/
git commit -m "feat(resource): add RWood and RComponentPoint resource type classes

Introduce Script-reference resource type convention. RWood and
RComponentPoint are const-only Resource classes carrying display
metadata. Consumers identify types via the Script reference itself
(e.g., CStockpile.add(RWood, 5)).

Part of the resource system prototype (spec: 2026-04-14-resource-system-design).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: CStockpile component (TDD)

**Files:**
- Create: `scripts/components/c_stockpile.gd`
- Test: `tests/unit/test_cstockpile.gd`

- [ ] **Step 1: Delegate test creation via category+skill**

Delegate the following to `task(category="quick", load_skills=["gol-test-writer-unit"], prompt=...)`:

```
Prompt to the test writer:

Create a gdUnit4 unit test file at `tests/unit/test_cstockpile.gd` that
verifies the contract of the CStockpile component (to be created at
`scripts/components/c_stockpile.gd`).

CStockpile API to test:
  class_name CStockpile extends Component
  @export var contents: Dictionary = {}              # Script -> int
  @export var per_type_caps: Dictionary = {}         # Script -> int
  var changed_observable: ObservableProperty        # emits contents dict on change

  func get_amount(resource_type: Script) -> int
  func add(resource_type: Script, amount: int) -> int          # returns accepted amount
  func withdraw(resource_type: Script, amount: int) -> bool    # true iff full amount withdrew
  func can_accept(resource_type: Script, amount: int) -> bool

Required tests:
  1. test_empty_stockpile_returns_zero_for_any_type
     - new CStockpile → get_amount(RWood) == 0
  2. test_add_and_get
     - add(RWood, 5) → returns 5, get_amount(RWood) == 5
  3. test_add_accumulates
     - add(RWood, 3); add(RWood, 4) → get_amount(RWood) == 7
  4. test_add_different_types_independent
     - add(RWood, 5); add(RComponentPoint, 10) → both present, independent
  5. test_withdraw_full_amount
     - add(RWood, 5); withdraw(RWood, 3) → returns true, get_amount == 2
  6. test_withdraw_insufficient_returns_false
     - add(RWood, 5); withdraw(RWood, 10) → returns false, get_amount == 5 (unchanged)
  7. test_withdraw_from_empty_returns_false
     - withdraw(RWood, 1) → returns false
  8. test_can_accept_under_script_max_stack
     - add(RWood, 500); can_accept(RWood, 499) → true (RWood.MAX_STACK == 999)
  9. test_can_accept_over_script_max_stack
     - add(RWood, 500); can_accept(RWood, 500) → false (would exceed MAX_STACK)
 10. test_per_type_cap_overrides_max_stack
     - CStockpile with per_type_caps = {RWood: 10}; add(RWood, 15) → returns 10, get_amount == 10
 11. test_changed_observable_emits_on_add
     - Subscribe to changed_observable; add(RWood, 1) → observer called exactly once
 12. test_changed_observable_emits_on_withdraw
     - add(RWood, 5); reset observer; withdraw(RWood, 2) → observer called exactly once
 13. test_negative_add_is_rejected
     - add(RWood, -1) → returns 0, get_amount unchanged
 14. test_negative_withdraw_is_rejected
     - withdraw(RWood, -1) → returns false, unchanged

Use gdUnit4 patterns following the existing `tests/unit/` style. Do NOT
require a GECS World — CStockpile is pure data + logic, testable in
isolation. Import RWood and RComponentPoint via const preload at the top
of the test file.
```

The test writer returns the created file. Save it to `tests/unit/test_cstockpile.gd`.

- [ ] **Step 2: Delegate test run to verify FAIL**

```
task(category="quick", load_skills=["gol-test-runner"], prompt="
Run tests/unit/test_cstockpile.gd and report PASS/FAIL.
")
```

Expected: FAIL — `CStockpile` not defined (file doesn't exist yet).

- [ ] **Step 3: Create `scripts/components/c_stockpile.gd`**

```gdscript
# scripts/components/c_stockpile.gd
class_name CStockpile
extends Component

## Resource holdings: Script -> int
@export var contents: Dictionary = {}

## Optional per-type caps; empty dict means uncapped per type.
## If a type has an entry here, it's enforced INSTEAD OF the R*.MAX_STACK.
@export var per_type_caps: Dictionary = {}

## Observable for UI binding. Emits the full contents dict on change.
var changed_observable: ObservableProperty = ObservableProperty.new({})


func get_amount(resource_type: Script) -> int:
	return int(contents.get(resource_type, 0))


func can_accept(resource_type: Script, amount: int) -> bool:
	if amount <= 0:
		return false
	var cap := _cap_for(resource_type)
	return get_amount(resource_type) + amount <= cap


func add(resource_type: Script, amount: int) -> int:
	if amount <= 0:
		return 0
	var current := get_amount(resource_type)
	var cap := _cap_for(resource_type)
	var accepted: int = min(amount, cap - current)
	if accepted <= 0:
		return 0
	contents[resource_type] = current + accepted
	changed_observable.set_value(contents)
	return accepted


func withdraw(resource_type: Script, amount: int) -> bool:
	if amount <= 0:
		return false
	var current := get_amount(resource_type)
	if current < amount:
		return false
	contents[resource_type] = current - amount
	changed_observable.set_value(contents)
	return true


func _cap_for(resource_type: Script) -> int:
	if per_type_caps.has(resource_type):
		return int(per_type_caps[resource_type])
	# Fall back to R*.MAX_STACK via the script class's constant.
	if resource_type != null and "MAX_STACK" in resource_type:
		return int(resource_type.MAX_STACK)
	return 9223372036854775807   # effectively uncapped
```

- [ ] **Step 4: Delegate test run to verify PASS**

```
task(category="quick", load_skills=["gol-test-runner"], prompt="
Run tests/unit/test_cstockpile.gd and report PASS/FAIL with details on any failures.
")
```

Expected: PASS (all 14 tests).

If any fail, inspect the report, fix `c_stockpile.gd` OR adjust the test prompt and re-delegate. Do not proceed to Task 3 until this is green.

- [ ] **Step 5: Commit**

```bash
git add scripts/components/c_stockpile.gd tests/unit/test_cstockpile.gd
git commit -m "feat(resource): add CStockpile component with test coverage

CStockpile holds Dictionary[Script, int] resource counts with per-type
caps (fallback to R*.MAX_STACK). Exposes add/withdraw/get_amount/
can_accept and an ObservableProperty for UI binding.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: CResourceNode component (TDD)

**Files:**
- Create: `scripts/components/c_resource_node.gd`
- Test: `tests/unit/test_cresource_node.gd`

- [ ] **Step 1: Delegate test creation**

```
task(category="quick", load_skills=["gol-test-writer-unit"], prompt="
Create tests/unit/test_cresource_node.gd verifying the CResourceNode
component contract.

CResourceNode API:
  class_name CResourceNode extends Component
  @export var yield_type: Script          # e.g., RWood
  @export var yield_amount: int = 1
  @export var gather_duration: float = 2.0
  @export var infinite: bool = true
  @export var remaining_yield: int = -1   # -1 = infinite; >= 0 = depletable

  func can_gather() -> bool   # true if infinite OR remaining_yield > 0
  func consume_yield() -> int  # returns yield_amount and decrements remaining_yield if not infinite

Tests:
  1. test_infinite_node_can_always_gather
     - node with infinite=true → can_gather() == true after 100 consume_yield() calls
  2. test_depletable_node_initial_state
     - node with infinite=false, remaining_yield=3 → can_gather() == true
  3. test_depletable_node_decrements_on_consume
     - remaining_yield=3 → consume_yield() returns yield_amount, remaining_yield == 2
  4. test_depletable_node_exhausts
     - remaining_yield=1 → consume_yield(); can_gather() == false; consume_yield() returns 0
  5. test_infinite_node_consume_returns_amount_without_decrement
     - infinite=true, remaining_yield=-1 → consume_yield() returns yield_amount; remaining_yield still -1
  6. test_default_field_values
     - new CResourceNode → gather_duration == 2.0, infinite == true, remaining_yield == -1

Pure logic, no GECS World needed.
")
```

- [ ] **Step 2: Delegate test run, verify FAIL**

Expected: FAIL (file doesn't exist).

- [ ] **Step 3: Create `c_resource_node.gd`**

```gdscript
# scripts/components/c_resource_node.gd
class_name CResourceNode
extends Component

@export var yield_type: Script
@export var yield_amount: int = 1
@export var gather_duration: float = 2.0
@export var infinite: bool = true
@export var remaining_yield: int = -1


func can_gather() -> bool:
	if infinite:
		return true
	return remaining_yield > 0


func consume_yield() -> int:
	if not can_gather():
		return 0
	if not infinite:
		remaining_yield -= 1
	return yield_amount
```

- [ ] **Step 4: Delegate test run, verify PASS**

Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/components/c_resource_node.gd tests/unit/test_cresource_node.gd
git commit -m "feat(resource): add CResourceNode component with test coverage

CResourceNode marks an entity as a gatherable resource source. Supports
infinite and depletable nodes via the \`infinite\` flag and
\`remaining_yield\` counter. \`can_gather()\` and \`consume_yield()\`
encapsulate the depletion logic.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: CCarrying and CWorker tag components

**Files:**
- Create: `scripts/components/c_carrying.gd`
- Create: `scripts/components/c_worker.gd`

No dedicated tests — CCarrying is pure data with no behavior, CWorker is a tag. They'll be covered by integration tests later.

- [ ] **Step 1: Create `c_carrying.gd`**

```gdscript
# scripts/components/c_carrying.gd
class_name CCarrying
extends Component

@export var resource_type: Script
@export var amount: int = 0
```

- [ ] **Step 2: Create `c_worker.gd`**

```gdscript
# scripts/components/c_worker.gd
class_name CWorker
extends Component
# Tag marker; identifies a GOAP agent as a worker. No fields.
```

- [ ] **Step 3: Parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add scripts/components/c_carrying.gd scripts/components/c_worker.gd
git commit -m "feat(resource): add CCarrying and CWorker components

CCarrying is a transient worker payload marker (resource_type + amount)
added during the chop-haul cycle and removed on deposit. CWorker is a
tag marker identifying an entity as a worker NPC (parallel to CGuard).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: composer_utils migration + PlayerData.component_points deletion

**Files:**
- Modify: `scripts/gameplay/player_data.gd` (delete 2 lines)
- Modify: `scripts/utils/composer_utils.gd` (rewrite 2 functions)
- Rewrite: `tests/unit/test_composer_utils.gd` (**already exists** — currently tests the old PlayerData.component_points path; must be adapted to the new CStockpile path)

Existing code to replace:

**`player_data.gd` (12 lines):** currently has both `unlocked_blueprints` and `component_points` + `points_changed` signal. After: only `unlocked_blueprints` and `blueprint_unlocked`.

**`composer_utils.gd` (43 lines):** currently takes `player_data: PlayerData` as a parameter for craft/dismantle. After: takes `player_entity: Entity` and reads `CStockpile` from it, using `RComponentPoint` as the resource type. `unlock_blueprint` still takes `player_data` because `unlocked_blueprints` stays on PlayerData.

**`test_composer_utils.gd` (existing, ~124 lines):** has these tests today (read the file to confirm):
- `test_player_data_initial_state`
- `test_unlock_blueprint_success` / `test_unlock_blueprint_already_unlocked`
- `test_craft_component_success` / `not_unlocked` / `insufficient_points` / `at_cap`
- `test_dismantle_component_success` / `not_losable`

All craft/dismantle tests currently do `player_data.component_points = 2` then call `ComposerUtils.craft_component(player, CHealer, player_data)`. After the rewrite, they must `player.add_component(stockpile)` where `stockpile.add(RComponentPoint, 2)`, and the call becomes `ComposerUtils.craft_component(player, CHealer)`.

- [ ] **Step 1: Delegate test rewrite**

```
task(category="quick", load_skills=["gol-test-writer-unit"], prompt="
Rewrite tests/unit/test_composer_utils.gd. The file already exists and
currently tests the old PlayerData.component_points path. You must
preserve all test case names and intent while adapting them to the new
CStockpile-based API.

New composer_utils signatures:
  static func unlock_blueprint(component_type: Script, player_data: PlayerData) -> bool  # UNCHANGED
  static func craft_component(player_entity: Entity, component_type: Script) -> bool     # CHANGED (removed player_data arg)
  static func dismantle_component(player_entity: Entity, component_type: Script) -> bool # CHANGED (removed player_data arg)

Preserve these existing tests (same names):
  - test_player_data_initial_state — NOW asserts unlocked_blueprints is empty; DELETE the component_points assertion (the field no longer exists)
  - test_unlock_blueprint_success — UNCHANGED (still uses player_data)
  - test_unlock_blueprint_already_unlocked — UNCHANGED
  - test_craft_component_success — player entity needs a CStockpile pre-loaded with RComponentPoint=2; after craft, stockpile.get_amount(RComponentPoint) == 0; GOL.Player.unlocked_blueprints must contain the blueprint (note: the current implementation will read GOL.Player to check unlocks — the test needs GOL.Player set up)
  - test_craft_component_not_unlocked — stockpile has RComponentPoint=2, no unlocks; assert false and stockpile unchanged
  - test_craft_component_insufficient_points — stockpile has RComponentPoint=1; assert false
  - test_craft_component_at_cap — pre-populate player with 3 losable components; stockpile has RComponentPoint=2; assert false
  - test_dismantle_component_success — player has CWeapon and empty stockpile; after dismantle, stockpile.get_amount(RComponentPoint) == 1
  - test_dismantle_component_not_losable — pass CPlayer (not losable); assert false

IMPORTANT:
- Add preload const for CStockpile and RComponentPoint at the top:
    const CStockpile = preload(\"res://scripts/components/c_stockpile.gd\")
    const RComponentPoint = preload(\"res://scripts/resources/r_component_point.gd\")
- Update _create_player_entity() helper to also add a CStockpile
- composer_utils internally reads GOL.Player.unlocked_blueprints for the unlock check, so the test harness must assign GOL.Player = player_data at the start of each craft test case (or in before_test)
- Use auto_free() for PlayerData and Entity instances
- Follow gdUnit4 patterns as in the existing file

Return the rewritten file content.
")
```

- [ ] **Step 2: Delegate test run, verify FAIL**

Expected: FAIL — old signatures don't accept a player_entity-only call; old PlayerData.component_points reference causes parse errors.

- [ ] **Step 3: Update `scripts/gameplay/player_data.gd`**

Replace the entire file with:

```gdscript
class_name PlayerData
extends Object


@warning_ignore("unused_signal")
signal blueprint_unlocked(component_type: Script)

var unlocked_blueprints: Array[Script] = []
```

(Deletes `component_points` field and `points_changed` signal. Keeps `unlocked_blueprints` and `blueprint_unlocked`.)

- [ ] **Step 4: Update `scripts/utils/composer_utils.gd`**

Replace the entire file with:

```gdscript
class_name ComposerUtils

const CONFIG = preload("res://scripts/configs/config.gd")
const PlayerData = preload("res://scripts/gameplay/player_data.gd")
const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const RComponentPoint = preload("res://scripts/resources/r_component_point.gd")


static func unlock_blueprint(component_type: Script, player_data: PlayerData) -> bool:
	if component_type in player_data.unlocked_blueprints:
		return false
	player_data.unlocked_blueprints.append(component_type)
	player_data.blueprint_unlocked.emit(component_type)
	return true


static func craft_component(player_entity: Entity, component_type: Script) -> bool:
	var config := CONFIG.new()
	if component_type not in GOL.Player.unlocked_blueprints:
		return false

	var stockpile: CStockpile = player_entity.get_component(CStockpile)
	if stockpile == null or stockpile.get_amount(RComponentPoint) < config.CRAFT_COST:
		return false
	if ECSUtils.is_at_component_cap(player_entity):
		return false

	if not stockpile.withdraw(RComponentPoint, config.CRAFT_COST):
		return false

	var new_component: Component = component_type.new()
	player_entity.add_component(new_component)
	return true


static func dismantle_component(player_entity: Entity, component_type: Script) -> bool:
	var config := CONFIG.new()
	var component: Component = player_entity.get_component(component_type)
	if not component:
		return false
	if not ECSUtils.is_losable_component(component):
		return false

	var stockpile: CStockpile = player_entity.get_component(CStockpile)
	if stockpile == null:
		return false

	player_entity.remove_component(component_type)
	stockpile.add(RComponentPoint, config.DISMANTLE_YIELD)
	return true
```

**Note:** `unlock_blueprint` still takes `player_data` because `unlocked_blueprints` stays on `PlayerData`. Only the resource-touching functions migrate.

- [ ] **Step 5: Delegate test run, verify PASS**

Expected: PASS (8 tests).

If FAIL due to `GOL.Player` being null in unit test context: the test setup will need to initialize `GOL.Player = PlayerData.new()`. If the test writer didn't do this, re-delegate with the clarification.

- [ ] **Step 6: Commit**

```bash
git add scripts/gameplay/player_data.gd scripts/utils/composer_utils.gd tests/unit/test_composer_utils.gd
git commit -m "refactor(resource): migrate component_points from PlayerData to CStockpile

Delete PlayerData.component_points and points_changed signal. Rewire
composer_utils.craft_component/dismantle_component to read/write the
player entity's CStockpile using RComponentPoint as the resource type.
PlayerData shrinks to progression state only (unlocked_blueprints).

Note: this leaves ViewModelHud and ViewModelComposer still referencing
the deleted signal — fixed in the next commit.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Viewmodel + view rebindings (HUD)

**Files:**
- Modify: `scripts/ui/viewmodels/viewmodel_hud.gd`
- Modify: `scripts/ui/views/view_hud.gd`
- Modify: `scenes/ui/view_hud.tscn` (add WoodPanel)

The game currently won't compile because `viewmodel_hud.gd:37` references `GOL.Player.component_points` which no longer exists. This task fixes it.

- [ ] **Step 1: Read existing `viewmodel_hud.gd`**

```bash
cat scripts/ui/viewmodels/viewmodel_hud.gd
```

Use this as the structural template — match its style for the new wood binding.

- [ ] **Step 2: Rewrite `viewmodel_hud.gd`**

```gdscript
class_name ViewModelHud
extends ViewModelBase

const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const RComponentPoint = preload("res://scripts/resources/r_component_point.gd")
const RWood = preload("res://scripts/resources/r_wood.gd")

var component_points: ObservableProperty = ObservableProperty.new(0)
var wood_count: ObservableProperty = ObservableProperty.new(0)

var _player_stockpile: CStockpile = null
var _camp_stockpile: CStockpile = null


func setup(context) -> void:
	super.setup(context)
	_bind_component_points()
	_bind_wood_count()


func teardown() -> void:
	component_points.teardown()
	wood_count.teardown()
	super.teardown()


func _bind_component_points() -> void:
	var player_entity: Entity = _find_entity_with([CPlayer, CStockpile])
	if player_entity == null:
		component_points.set_value(0)
		return
	_player_stockpile = player_entity.get_component(CStockpile)
	component_points.set_value(_player_stockpile.get_amount(RComponentPoint))
	_player_stockpile.changed_observable.subscribe(func(_contents):
		component_points.set_value(_player_stockpile.get_amount(RComponentPoint))
	)


func _bind_wood_count() -> void:
	var camp_entity: Entity = _find_entity_with([CStockpile], [CPlayer])
	if camp_entity == null:
		wood_count.set_value(0)
		return
	_camp_stockpile = camp_entity.get_component(CStockpile)
	wood_count.set_value(_camp_stockpile.get_amount(RWood))
	_camp_stockpile.changed_observable.subscribe(func(_contents):
		wood_count.set_value(_camp_stockpile.get_amount(RWood))
	)


func _find_entity_with(required: Array, excluded: Array = []) -> Entity:
	if ECS.world == null:
		return null
	var query := ECS.world.query.with_all(required)
	if excluded.size() > 0:
		query = query.with_none(excluded)
	var entities := query.execute()
	return entities[0] if entities.size() > 0 else null
```

**Notes:**
- If the existing `ViewModelHud` has a different base class or setup pattern, adapt accordingly. Read `viewmodel_base.gd` first if unsure.
- The `_find_entity_with` helper locates the singleton entities. For the prototype, the player is the only `CPlayer` and the camp cube is the only `CStockpile`-without-`CPlayer`.

- [ ] **Step 3: Update `view_hud.gd`**

Current (from earlier recon, lines 5 and 17-18):
```gdscript
@onready var component_points_label: Label = $ComponentPointsPanel/ComponentPointsLabel
...
vm.component_points.subscribe(func(value: Variant) -> void:
    component_points_label.text = "组件点: %d" % int(value)
)
```

Add a wood label and subscribe:

```gdscript
@onready var component_points_label: Label = $ComponentPointsPanel/ComponentPointsLabel
@onready var wood_label: Label = $WoodPanel/WoodLabel
...
# In _ready / setup_viewmodel:
var vm: ViewModelHud = get_viewmodel() as ViewModelHud
vm.component_points.subscribe(func(value: Variant) -> void:
	component_points_label.text = "组件点: %d" % int(value)
)
vm.wood_count.subscribe(func(value: Variant) -> void:
	wood_label.text = "木材: %d" % int(value)
)
```

- [ ] **Step 4: Update `scenes/ui/view_hud.tscn`**

Open the scene in the Godot editor. Add a new Panel named `WoodPanel` as a sibling of `ComponentPointsPanel`, positioned below it. Inside it, add a Label named `WoodLabel` with placeholder text `木材: 0`. Save the scene.

If editing the .tscn file directly (not via the editor), add these nodes. The simplest layout is:

```
[node name="WoodPanel" type="Panel" parent="."]
anchors_preset = 0
offset_left = 16.0
offset_top = 64.0
offset_right = 160.0
offset_bottom = 96.0

[node name="WoodLabel" type="Label" parent="WoodPanel"]
anchors_preset = 15
text = "木材: 0"
```

Adjust offsets to match existing `ComponentPointsPanel` style. The exact layout can be refined later.

- [ ] **Step 5: Parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

Expected: `OK`. If errors mention the scene file, open the scene in Godot and save it once to regenerate metadata.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/viewmodels/viewmodel_hud.gd scripts/ui/views/view_hud.gd scenes/ui/view_hud.tscn
git commit -m "refactor(ui): rebind HUD to CStockpile observables

ViewModelHud.component_points now binds to the player entity's
CStockpile.changed_observable (via RComponentPoint) instead of the
deleted PlayerData.points_changed signal. Adds a wood_count observable
bound to the camp stockpile entity's CStockpile (via RWood). View_hud
gains a WoodPanel label below ComponentPointsPanel.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Viewmodel + view rebindings (Composer)

**Files:**
- Modify: `scripts/ui/viewmodels/viewmodel_composer.gd`
- Modify: `scripts/ui/views/view_composer.gd`

Same rebinding pattern as Task 6, but for the composer dialogue UI.

- [ ] **Step 1: Read existing files**

```bash
cat scripts/ui/viewmodels/viewmodel_composer.gd
cat scripts/ui/views/view_composer.gd
```

Note the current `component_points` observable and the disabled-button check in view_composer.gd that reads `GOL.Player.component_points`.

- [ ] **Step 2: Update `viewmodel_composer.gd`**

Replace the `component_points` observable setup so it binds from the player entity's CStockpile. Pattern:

```gdscript
const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const RComponentPoint = preload("res://scripts/resources/r_component_point.gd")

var component_points: ObservableProperty
var _player_stockpile: CStockpile = null


func _init() -> void:
	component_points = ObservableProperty.new(0)


func setup(context) -> void:
	super.setup(context)
	# _bind_component_points replaces the old PlayerData.points_changed subscription
	_bind_component_points()


func _bind_component_points() -> void:
	var player_entity: Entity = _find_player_entity()
	if player_entity == null:
		component_points.set_value(0)
		return
	_player_stockpile = player_entity.get_component(CStockpile)
	if _player_stockpile == null:
		component_points.set_value(0)
		return
	component_points.set_value(_player_stockpile.get_amount(RComponentPoint))
	_player_stockpile.changed_observable.subscribe(func(_contents):
		component_points.set_value(_player_stockpile.get_amount(RComponentPoint))
	)


func _find_player_entity() -> Entity:
	if ECS.world == null:
		return null
	var entities := ECS.world.query.with_all([CPlayer, CStockpile]).execute()
	return entities[0] if entities.size() > 0 else null
```

Preserve any existing fields that aren't related to component_points.

- [ ] **Step 3: Update `view_composer.gd`**

Current (from earlier recon, line 87):
```gdscript
button.disabled = GOL.Player.component_points < craft_cost or ECSUtils.is_at_component_cap(_player_entity)
```

Replace with a read through the viewmodel:

```gdscript
var vm: ViewModelComposer = get_viewmodel() as ViewModelComposer
var current_points := int(vm.component_points.value)
button.disabled = current_points < craft_cost or ECSUtils.is_at_component_cap(_player_entity)
```

If `get_viewmodel()` is not the existing pattern, read the existing view_composer.gd to see how the viewmodel is accessed (likely cached in a field) and adapt.

- [ ] **Step 4: Parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/viewmodels/viewmodel_composer.gd scripts/ui/views/view_composer.gd
git commit -m "refactor(ui): rebind composer dialogue to CStockpile observable

ViewModelComposer.component_points now binds to the player entity's
CStockpile.changed_observable. View_composer reads the current count
from the viewmodel instead of GOL.Player.component_points.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Config constants

**Files:**
- Modify: `scripts/configs/config.gd`

Add the resource system constants in one commit. Referenced by Tasks 9–18.

- [ ] **Step 1: Append to `config.gd`**

Add at the end of the existing file (after the Blueprint & Composer section):

```gdscript

## ── Resource System ──────────────────────────
# Tree scatter (placed by GOLWorld after PCG)
static var TREE_SCATTER_COUNT: int = 50
static var TREE_POI_EXCLUSION_RADIUS: float = 64.0

# Gather timing (default for CResourceNode; overridable per-node)
static var DEFAULT_GATHER_DURATION: float = 2.0

# Worker behavior
static var WORKER_SEARCH_RADIUS: float = 2000.0
static var MOVE_ARRIVAL_THRESHOLD: float = 24.0

# Spawn offsets from campfire
static var WORKER_SPAWN_OFFSET: Vector2 = Vector2(-48, 0)
static var STOCKPILE_SPAWN_OFFSET: Vector2 = Vector2(48, 0)

# Initial camp stockpile cap (generous for prototype)
static var CAMP_STOCKPILE_DEFAULT_CAP: int = 9999
```

- [ ] **Step 2: Parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/configs/config.gd
git commit -m "feat(resource): add resource system config constants

TREE_SCATTER_COUNT, DEFAULT_GATHER_DURATION, WORKER_SEARCH_RADIUS,
MOVE_ARRIVAL_THRESHOLD, spawn offsets, and camp stockpile cap.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: GoapAction_FindWorkTarget (TDD)

**Files:**
- Create: `scripts/gameplay/goap/actions/find_work_target.gd`
- Test: `tests/unit/test_goap_action_find_work_target.gd`

Orient first: read one existing GOAP action and the base class to confirm the pattern.

- [ ] **Step 1: Read existing actions for orientation**

```bash
cat scripts/gameplay/goap/actions/move_to.gd
cat scripts/gameplay/goap/actions/wander.gd
cat scripts/gameplay/goap/actions/flee.gd
cat scripts/gameplay/goap/goap_action.gd
cat scripts/gameplay/goap/goap_world_state.gd
```

**Key GOAP API facts (verified from move_to.gd and wander.gd):**
- `_init()` sets `action_name: String`, `cost: float`, `preconditions: Dictionary`, `effects: Dictionary`
- `perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, context: Dictionary) -> bool` — returns `true` when the action is done (success OR failure), `false` to keep running
- Blackboard access is via two-argument helpers, always passing the agent_component:
  - `get_blackboard(agent_component, key, default)` — read
  - `set_blackboard(agent_component, key, value)` — write
- There is **no `fail_plan()` method** in the base class. To signal failure, set `movement.velocity = Vector2.ZERO` and return `true` — the planner will see that effects weren't achieved and replan
- Effects declared in `_init()` are for planning only; runtime may also need to write corresponding facts to `agent_component.world_state`. **Read `goap_world_state.gd` to find the actual setter method** (likely `set_fact(name, value)` or direct dict mutation); this plan assumes `agent_component.world_state.set_fact(name, value)`, which the implementer must verify before each action touches world_state.

- [ ] **Step 2: Delegate test creation**

```
task(category="quick", load_skills=["gol-test-writer-unit"], prompt="
Create tests/unit/test_goap_action_find_work_target.gd.

Context: GoapAction_FindWorkTarget is a GOAP action that scans the ECS
world for CResourceNode entities within Config.WORKER_SEARCH_RADIUS of the
worker's CTransform, picks the nearest one where CResourceNode.can_gather()
is true, writes the target Entity to the agent's blackboard under key
'work_target_entity', and returns true.

Per the existing pattern in move_to.gd and wander.gd:
  - perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, context: Dictionary) -> bool
  - Returns true when done, false to keep running
  - Reads/writes blackboard via get_blackboard(agent_component, key, default) / set_blackboard(agent_component, key, value)
  - On failure, sets movement.velocity=Vector2.ZERO and returns true (no fail_plan() method exists)

Required tests (spin up a GECS World, add entities, call perform() directly):

  1. test_finds_nearest_gatherable_node
     - Worker entity at position (0, 0) with CTransform, CMovement, CGoapAgent
     - 3 CResourceNode entities at (100, 0), (200, 0), (50, 0) — all infinite, RWood yield
     - action.perform(worker, agent_component, 0.0, {}) → returns true
     - get_blackboard(agent_component, 'work_target_entity', null) points to the (50, 0) node
     - agent_component.world_state has has_work_target == true

  2. test_skips_exhausted_nodes
     - Worker at origin
     - Node A at (50, 0): infinite=false, remaining_yield=0 (not gatherable)
     - Node B at (100, 0): infinite=true (gatherable)
     - perform() → returns true
     - blackboard target is Node B

  3. test_no_nodes_available
     - Worker alone, no resource node entities
     - perform() → returns true (action done), worker.get_component(CMovement).velocity == Vector2.ZERO
     - blackboard 'work_target_entity' is null (never set)
     - agent_component.world_state does NOT have has_work_target=true

  4. test_ignores_nodes_beyond_search_radius
     - Worker at (0, 0), node at (Config.WORKER_SEARCH_RADIUS + 100, 0)
     - perform() → returns true, no target set, has_work_target not true

Use auto_free() for entities. Preload CResourceNode, RWood, CTransform,
CMovement, CGoapAgent at the top. Use ECS.world (the global world) or
whatever pattern the existing s_ai tests use for world setup.
")
```

- [ ] **Step 3: Delegate test run, verify FAIL**

Expected: FAIL.

- [ ] **Step 4: Create the action**

```gdscript
# scripts/gameplay/goap/actions/find_work_target.gd
class_name GoapAction_FindWorkTarget
extends GoapAction

const CResourceNode = preload("res://scripts/components/c_resource_node.gd")


func _init() -> void:
	action_name = "FindWorkTarget"
	cost = 1.0
	preconditions = {
		"is_carrying": false,
		"has_work_target": false,
	}
	effects = {
		"has_work_target": true,
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var worker_transform := agent_entity.get_component(CTransform)
	var movement := agent_entity.get_component(CMovement)
	if worker_transform == null:
		if movement:
			movement.velocity = Vector2.ZERO
		return true

	var search_radius_sq: float = Config.WORKER_SEARCH_RADIUS * Config.WORKER_SEARCH_RADIUS

	var nearest: Entity = null
	var nearest_dist_sq: float = INF

	var candidates: Array = ECS.world.query.with_all([CResourceNode, CTransform]).execute()
	for node_entity in candidates:
		if node_entity == null or not is_instance_valid(node_entity):
			continue
		var node: CResourceNode = node_entity.get_component(CResourceNode)
		if node == null or not node.can_gather():
			continue
		var node_transform: CTransform = node_entity.get_component(CTransform)
		var dist_sq: float = worker_transform.position.distance_squared_to(node_transform.position)
		if dist_sq > search_radius_sq:
			continue
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = node_entity

	if nearest == null:
		if movement:
			movement.velocity = Vector2.ZERO
		return true   # action done, effect not achieved → planner will replan

	set_blackboard(agent_component, "work_target_entity", nearest)
	agent_component.world_state.set_fact("has_work_target", true)
	return true
```

**Note on `Config`:** `Config` is a global class_name with static vars, so `Config.WORKER_SEARCH_RADIUS` works directly — no instantiation needed. If the existing actions use `Config.new().FIELD` instead, adapt accordingly.

**Note on `world_state.set_fact`:** Verify this method exists in `goap_world_state.gd`. If the facts are a plain dict, use `agent_component.world_state["has_work_target"] = true` or whatever the idiom is. The test prompt already accommodates either form by checking the fact existence via whatever inspection method the harness supports.

- [ ] **Step 5: Delegate test run, verify PASS**

Expected: PASS.

If tests fail, inspect `scripts/gameplay/goap/actions/wander.gd` for the exact failure/completion idiom and adjust the action implementation accordingly.

- [ ] **Step 6: Commit**

```bash
git add scripts/gameplay/goap/actions/find_work_target.gd tests/unit/test_goap_action_find_work_target.gd
git commit -m "feat(goap): add GoapAction_FindWorkTarget

Scans the ECS world for the nearest gatherable CResourceNode within
WORKER_SEARCH_RADIUS of the worker. Writes the target entity to the
agent blackboard and sets has_work_target fact.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: GoapAction_MoveToResourceNode

**Files:**
- Create: `scripts/gameplay/goap/actions/move_to_resource_node.gd`

Extends `GoapAction_MoveTo`. The base class reads a `Vector2` position from blackboard at `target_key` and moves toward it each frame. For entity-following, our override writes the entity's *current* position to that key each tick before calling `super.perform()`.

- [ ] **Step 1: Create the action**

```gdscript
# scripts/gameplay/goap/actions/move_to_resource_node.gd
class_name GoapAction_MoveToResourceNode
extends GoapAction_MoveTo


func _init() -> void:
	super._init()
	action_name = "MoveToResourceNode"
	target_key = "work_target_pos"   # distinct from base default "move_target"
	cost = 1.0
	preconditions = {
		"has_work_target": true,
		"reached_work_target": false,
	}
	effects = {
		"reached_work_target": true,
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, context: Dictionary) -> bool:
	var target: Entity = get_blackboard(agent_component, "work_target_entity", null) as Entity
	var movement := agent_entity.get_component(CMovement)
	if target == null or not is_instance_valid(target):
		if movement:
			movement.velocity = Vector2.ZERO
		return true

	var target_transform := target.get_component(CTransform)
	if target_transform == null:
		if movement:
			movement.velocity = Vector2.ZERO
		return true

	# Refresh the target position in the blackboard so super.perform() uses
	# the latest entity position even if the target moved.
	set_blackboard(agent_component, target_key, target_transform.position)

	var done := super.perform(agent_entity, agent_component, delta, context)
	if done:
		# Arrival detection lives in the base class (velocity=0 once within reach_threshold).
		# Only set the effect fact if we actually arrived (not if target vanished mid-move).
		var agent_transform := agent_entity.get_component(CTransform)
		if agent_transform != null:
			var dist := agent_transform.position.distance_to(target_transform.position)
			if dist <= reach_threshold:
				agent_component.world_state.set_fact("reached_work_target", true)
	return done
```

- [ ] **Step 2: Parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/goap/actions/move_to_resource_node.gd
git commit -m "feat(goap): add GoapAction_MoveToResourceNode

Extends GoapAction_MoveTo. Reads the work_target_entity from the
blackboard each tick and writes its current position to work_target_pos
so the base class drives movement toward it. Sets reached_work_target
on arrival within reach_threshold.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: GoapAction_GatherResource

**Files:**
- Create: `scripts/gameplay/goap/actions/gather_resource.gd`

This action runs a timer for the target node's `gather_duration` and adds `CCarrying` to the worker on completion. Since the existing base `GoapAction` may or may not support `on_plan_enter` / `on_plan_exit` hooks (we haven't verified), timer state is tracked using a blackboard key that resets each time the action starts. Progress bar wiring happens in Task 15 (which adds fields + hooks if available).

- [ ] **Step 1: Verify plan lifecycle hooks**

```bash
cat scripts/gameplay/goap/goap_action.gd
```

Look for `on_plan_enter` / `on_plan_exit` virtual methods on the base class. If they exist, use them for timer init/cleanup. If not, track elapsed time in a blackboard key and reset it when the action first runs after a new plan (detected by checking a `gather_started_at` key).

- [ ] **Step 2: Create the action (blackboard-timer variant)**

```gdscript
# scripts/gameplay/goap/actions/gather_resource.gd
class_name GoapAction_GatherResource
extends GoapAction

const CCarrying = preload("res://scripts/components/c_carrying.gd")
const CResourceNode = preload("res://scripts/components/c_resource_node.gd")


func _init() -> void:
	action_name = "GatherResource"
	cost = 2.0
	preconditions = {
		"reached_work_target": true,
		"is_carrying": false,
	}
	effects = {
		"is_carrying": true,
		"has_work_target": false,
		"reached_work_target": false,
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, _context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	if movement:
		movement.velocity = Vector2.ZERO

	var target: Entity = get_blackboard(agent_component, "work_target_entity", null) as Entity
	if target == null or not is_instance_valid(target):
		return true

	var node: CResourceNode = target.get_component(CResourceNode)
	if node == null or not node.can_gather():
		return true

	# Accumulate elapsed time in the blackboard (reset when the action re-enters
	# after a fresh plan — signaled by the blackboard key being absent).
	var elapsed: float = get_blackboard(agent_component, "gather_elapsed", -1.0)
	if elapsed < 0.0:
		elapsed = 0.0
	elapsed += delta
	set_blackboard(agent_component, "gather_elapsed", elapsed)

	if elapsed < node.gather_duration:
		return false   # still gathering

	# Completed
	var yielded := node.consume_yield()
	set_blackboard(agent_component, "gather_elapsed", -1.0)   # reset for next cycle

	if yielded <= 0:
		return true

	var carrying := CCarrying.new()
	carrying.resource_type = node.yield_type
	carrying.amount = yielded
	agent_entity.add_component(carrying)

	agent_component.world_state.set_fact("is_carrying", true)
	agent_component.world_state.set_fact("has_work_target", false)
	agent_component.world_state.set_fact("reached_work_target", false)
	set_blackboard(agent_component, "work_target_entity", null)
	return true
```

**Note:** The `gather_elapsed` reset-to-`-1.0` trick handles the fact that blackboard values persist across action runs. When the NEXT gather cycle starts, `get_blackboard()` will return `-1.0`, which we treat as "just started." A cleaner approach is `on_plan_enter` / `on_plan_exit` hooks if the base class supports them — switch to those in Step 1 if verified.

- [ ] **Step 3: Parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/gameplay/goap/actions/gather_resource.gd
git commit -m "feat(goap): add GoapAction_GatherResource

Runs a timer for the target node's gather_duration. On completion,
consumes yield, adds CCarrying to the worker, and updates GOAP facts.
Progress bar view wiring arrives in a later commit.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: GoapAction_MoveToStockpile

**Files:**
- Create: `scripts/gameplay/goap/actions/move_to_stockpile.gd`

Extends `GoapAction_MoveTo` using the same pattern as `MoveToResourceNode`: override `perform()`, resolve (or cache) a stockpile Entity from blackboard, write its position to `target_key`, delegate to `super.perform()`.

- [ ] **Step 1: Create the action**

```gdscript
# scripts/gameplay/goap/actions/move_to_stockpile.gd
class_name GoapAction_MoveToStockpile
extends GoapAction_MoveTo

const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const CCarrying = preload("res://scripts/components/c_carrying.gd")


func _init() -> void:
	super._init()
	action_name = "MoveToStockpile"
	target_key = "stockpile_target_pos"   # distinct from base default
	cost = 1.0
	preconditions = {
		"is_carrying": true,
		"reached_stockpile": false,
	}
	effects = {
		"reached_stockpile": true,
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	var stockpile_entity: Entity = get_blackboard(agent_component, "stockpile_target_entity", null) as Entity
	if stockpile_entity == null or not is_instance_valid(stockpile_entity):
		stockpile_entity = _find_accepting_stockpile(agent_entity)
		if stockpile_entity == null:
			if movement:
				movement.velocity = Vector2.ZERO
			return true
		set_blackboard(agent_component, "stockpile_target_entity", stockpile_entity)

	var target_transform := stockpile_entity.get_component(CTransform)
	if target_transform == null:
		if movement:
			movement.velocity = Vector2.ZERO
		return true

	set_blackboard(agent_component, target_key, target_transform.position)

	var done := super.perform(agent_entity, agent_component, delta, context)
	if done:
		var agent_transform := agent_entity.get_component(CTransform)
		if agent_transform != null:
			var dist := agent_transform.position.distance_to(target_transform.position)
			if dist <= reach_threshold:
				agent_component.world_state.set_fact("reached_stockpile", true)
	return done


func _find_accepting_stockpile(worker: Entity) -> Entity:
	var carrying: CCarrying = worker.get_component(CCarrying)
	if carrying == null:
		return null
	var worker_transform := worker.get_component(CTransform)
	if worker_transform == null:
		return null

	var best: Entity = null
	var best_dist_sq: float = INF
	var candidates: Array = ECS.world.query.with_all([CStockpile, CTransform]).execute()
	for cand in candidates:
		if cand == worker or not is_instance_valid(cand):
			continue
		# Skip worker-owned stockpiles (in case a worker ever carries a CStockpile itself)
		if cand.has_component(CWorker):
			continue
		var sp: CStockpile = cand.get_component(CStockpile)
		if sp == null or not sp.can_accept(carrying.resource_type, carrying.amount):
			continue
		var t: CTransform = cand.get_component(CTransform)
		if t == null:
			continue
		var dist_sq: float = worker_transform.position.distance_squared_to(t.position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = cand
	return best
```

- [ ] **Step 2: Parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/goap/actions/move_to_stockpile.gd
git commit -m "feat(goap): add GoapAction_MoveToStockpile

Extends MoveTo. Resolves the nearest stockpile that can accept the
worker's carried load (skipping worker-owned stockpiles). Caches
the target in the blackboard after the first resolve.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: GoapAction_DepositResource (TDD)

**Files:**
- Create: `scripts/gameplay/goap/actions/deposit_resource.gd`
- Test: `tests/unit/test_goap_action_deposit_resource.gd`

- [ ] **Step 1: Delegate test creation**

```
task(category="quick", load_skills=["gol-test-writer-unit"], prompt="
Create tests/unit/test_goap_action_deposit_resource.gd.

Context: GoapAction_DepositResource transfers the worker's CCarrying
payload into the target stockpile entity's CStockpile, removes CCarrying,
and sets GOAP facts is_carrying=false, reached_stockpile=false, has_delivered=true.
Target stockpile comes from blackboard key 'stockpile_target_entity'.

Signature (matches existing action pattern in move_to.gd / wander.gd):
  class_name GoapAction_DepositResource extends GoapAction
  func perform(agent_entity: Entity, agent_component: CGoapAgent,
               delta: float, context: Dictionary) -> bool

Failure pattern (also matches existing actions): on failure, set
movement.velocity = Vector2.ZERO and return true. There is no fail_plan()
method in the base class.

Required tests:
  1. test_deposit_transfers_to_stockpile
     - Worker entity with CCarrying(RWood, 3), CMovement, CTransform
     - Stockpile entity with empty CStockpile
     - Pre-populate blackboard: set_blackboard(agent_component, 'stockpile_target_entity', stockpile_entity)
     - action.perform(worker, agent_component, 0.0, {}) returns true
     - stockpile.get_component(CStockpile).get_amount(RWood) == 3
     - worker.has_component(CCarrying) == false
     - agent_component.world_state has_delivered=true, is_carrying=false, reached_stockpile=false

  2. test_deposit_missing_carrying
     - Worker without CCarrying
     - perform() returns true, no stockpile mutation, no fact changes
     - worker movement velocity == Vector2.ZERO

  3. test_deposit_missing_target
     - Worker with CCarrying, blackboard target not set
     - perform() returns true, CCarrying still present, no mutation

  4. test_deposit_rejected_by_full_stockpile
     - Worker with CCarrying(RWood, 5)
     - Stockpile with per_type_caps = {RWood: 2} pre-loaded with 2 RWood
     - perform() returns true
     - stockpile amount still 2 (add() was blocked by can_accept)
     - worker still has CCarrying (no partial transfer)

Use auto_free() for entities. Preload CStockpile, CCarrying, RWood,
CMovement, CTransform, CGoapAgent.
")
```

- [ ] **Step 2: Delegate test run, verify FAIL**

Expected: FAIL.

- [ ] **Step 3: Create the action**

```gdscript
# scripts/gameplay/goap/actions/deposit_resource.gd
class_name GoapAction_DepositResource
extends GoapAction

const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const CCarrying = preload("res://scripts/components/c_carrying.gd")


func _init() -> void:
	action_name = "DepositResource"
	cost = 1.0
	preconditions = {
		"reached_stockpile": true,
		"is_carrying": true,
	}
	effects = {
		"has_delivered": true,
		"is_carrying": false,
		"reached_stockpile": false,
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	if movement:
		movement.velocity = Vector2.ZERO

	var carrying: CCarrying = agent_entity.get_component(CCarrying)
	if carrying == null:
		return true

	var target: Entity = get_blackboard(agent_component, "stockpile_target_entity", null) as Entity
	if target == null or not is_instance_valid(target):
		return true

	var stockpile: CStockpile = target.get_component(CStockpile)
	if stockpile == null:
		return true

	if not stockpile.can_accept(carrying.resource_type, carrying.amount):
		return true

	var accepted := stockpile.add(carrying.resource_type, carrying.amount)
	if accepted != carrying.amount:
		# Defensive: can_accept said yes but add accepted less. Bail without
		# partial transfer — effect facts stay unset, planner will retry.
		return true

	agent_entity.remove_component(CCarrying)
	agent_component.world_state.set_fact("has_delivered", true)
	agent_component.world_state.set_fact("is_carrying", false)
	agent_component.world_state.set_fact("reached_stockpile", false)
	set_blackboard(agent_component, "stockpile_target_entity", null)
	return true
```

- [ ] **Step 4: Delegate test run, verify PASS**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay/goap/actions/deposit_resource.gd tests/unit/test_goap_action_deposit_resource.gd
git commit -m "feat(goap): add GoapAction_DepositResource

Transfers CCarrying payload into target stockpile, removes CCarrying,
flips has_delivered/is_carrying/reached_stockpile facts. Defensive:
aborts without partial transfer if add() accepts less than expected.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: SAI replanning hook for Work goal

**Files:**
- Modify: `scripts/systems/s_ai.gd`

The `Work` goal's desired state is `has_delivered: true`. Once reached, the plan is complete but the worker should immediately replan to continue working. Since trees are infinite, this loops indefinitely. SAI needs to clear `has_delivered` after a Work-goal plan completes.

- [ ] **Step 1: Read SAI**

```bash
cat scripts/systems/s_ai.gd
```

Locate where a completed plan is detected (likely after `action.perform()` returns true on the last step, or in a `_on_plan_complete()` method).

- [ ] **Step 2: Add the fact-clearing hook**

In the plan-completion branch, add logic equivalent to:

```gdscript
# After a plan completes successfully, if the goal's name/id indicates Work,
# clear has_delivered so the next tick's replan rebuilds the gather cycle.
if completed_goal != null and completed_goal.goal_name == "Work":
	agent.world_state.set_fact("has_delivered", false)
```

**Note:** The exact field used to identify the goal (`goal_name`, `resource_path`, etc.) depends on `GoapGoal` — check the existing goal resources in `resources/goals/*.tres` and `goap_goal.gd` to see which field identifies them. If goals have a `goal_name: String` property, use that. If they only have `resource_path`, compare against `"res://resources/goals/work.tres"`.

- [ ] **Step 3: Parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/systems/s_ai.gd
git commit -m "feat(goap): SAI clears has_delivered after Work goal completes

Enables continuous replanning for the worker's Work goal: once
DepositResource sets has_delivered=true and the plan finishes, SAI
clears the fact so the next tick rebuilds the gather cycle.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: ProgressBarView scene and GatherResource wiring

**Files:**
- Create: `scenes/ui/progress_bar.tscn`
- Create: `scripts/ui/views/view_progress_bar.gd`
- Modify: `scripts/gameplay/goap/actions/gather_resource.gd`

- [ ] **Step 1: Create `view_progress_bar.gd`**

```gdscript
# scripts/ui/views/view_progress_bar.gd
class_name ViewProgressBar
extends Control

@onready var _fill: ColorRect = $Fill
@onready var _background: ColorRect = $Background

var _followed_entity: Entity = null
var _offset: Vector2 = Vector2(0, -32)


func set_progress(ratio: float) -> void:
	ratio = clamp(ratio, 0.0, 1.0)
	if _fill == null:
		return
	_fill.size.x = _background.size.x * ratio


func follow_entity(entity: Entity, offset: Vector2 = Vector2(0, -32)) -> void:
	_followed_entity = entity
	_offset = offset


func _process(_delta: float) -> void:
	if _followed_entity == null or not is_instance_valid(_followed_entity):
		return
	var t: CTransform = _followed_entity.get_component(CTransform)
	if t == null:
		return
	# Convert world position to screen position via the active camera.
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		global_position = t.position + _offset
	else:
		global_position = t.position + _offset   # simplification — full projection is a later refinement
```

- [ ] **Step 2: Create `scenes/ui/progress_bar.tscn`**

Create a scene with this structure:

```
ViewProgressBar (Control, script: view_progress_bar.gd)
├── Background (ColorRect) — size (32, 4), color = Color(0, 0, 0, 0.6)
└── Fill       (ColorRect) — size (0, 4), color = Color(0.3, 0.8, 0.3, 1)
```

If creating the .tscn file directly, use this template:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/views/view_progress_bar.gd" id="1"]

[node name="ViewProgressBar" type="Control"]
custom_minimum_size = Vector2(32, 4)
script = ExtResource("1")

[node name="Background" type="ColorRect" parent="."]
offset_right = 32.0
offset_bottom = 4.0
color = Color(0, 0, 0, 0.6)

[node name="Fill" type="ColorRect" parent="."]
offset_right = 0.0
offset_bottom = 4.0
color = Color(0.3, 0.8, 0.3, 1)
```

- [ ] **Step 3: Wire progress bar into GatherResource action**

Update `scripts/gameplay/goap/actions/gather_resource.gd` to show/hide a progress bar during gathering.

Add at the top of the file (after existing consts):

```gdscript
const PROGRESS_BAR_SCENE = preload("res://scenes/ui/progress_bar.tscn")
```

Replace the current `perform()` body so the progress bar is created on first tick (when `gather_elapsed` transitions from `-1.0` to `0.0`), updated each subsequent tick, and cleaned up on completion or failure. The blackboard-based lifetime means the view reference itself lives in the blackboard too (under `gather_progress_view`):

```gdscript
func perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, _context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	if movement:
		movement.velocity = Vector2.ZERO

	var target: Entity = get_blackboard(agent_component, "work_target_entity", null) as Entity
	if target == null or not is_instance_valid(target):
		_cleanup_progress_bar(agent_component)
		return true

	var node: CResourceNode = target.get_component(CResourceNode)
	if node == null or not node.can_gather():
		_cleanup_progress_bar(agent_component)
		return true

	var elapsed: float = get_blackboard(agent_component, "gather_elapsed", -1.0)
	if elapsed < 0.0:
		elapsed = 0.0
		_create_progress_bar(agent_entity, agent_component)

	elapsed += delta
	set_blackboard(agent_component, "gather_elapsed", elapsed)

	_update_progress_bar(agent_component, elapsed / node.gather_duration)

	if elapsed < node.gather_duration:
		return false

	# Completed
	var yielded := node.consume_yield()
	set_blackboard(agent_component, "gather_elapsed", -1.0)
	_cleanup_progress_bar(agent_component)

	if yielded <= 0:
		return true

	var carrying := CCarrying.new()
	carrying.resource_type = node.yield_type
	carrying.amount = yielded
	agent_entity.add_component(carrying)

	agent_component.world_state.set_fact("is_carrying", true)
	agent_component.world_state.set_fact("has_work_target", false)
	agent_component.world_state.set_fact("reached_work_target", false)
	set_blackboard(agent_component, "work_target_entity", null)
	return true


func _create_progress_bar(agent_entity: Entity, agent_component: CGoapAgent) -> void:
	var view: ViewProgressBar = PROGRESS_BAR_SCENE.instantiate() as ViewProgressBar
	if view == null:
		return
	ServiceContext.ui().push_view(Service_UI.LayerType.GAME, view)
	view.follow_entity(agent_entity)
	view.set_progress(0.0)
	set_blackboard(agent_component, "gather_progress_view", view)


func _update_progress_bar(agent_component: CGoapAgent, ratio: float) -> void:
	var view: ViewProgressBar = get_blackboard(agent_component, "gather_progress_view", null) as ViewProgressBar
	if view != null and is_instance_valid(view):
		view.set_progress(ratio)


func _cleanup_progress_bar(agent_component: CGoapAgent) -> void:
	var view: ViewProgressBar = get_blackboard(agent_component, "gather_progress_view", null) as ViewProgressBar
	if view != null and is_instance_valid(view):
		ServiceContext.ui().pop_view(view)
	set_blackboard(agent_component, "gather_progress_view", null)
```

**Note:** The `ServiceContext.ui().push_view(Service_UI.LayerType.GAME, ...)` pattern is lifted from the existing `box_hint_view` usage in `scripts/systems/s_pickup.gd`. Verify by re-reading that file before editing.

**Note:** A downside of storing the view in the blackboard is that if the plan is aborted mid-gather (e.g., worker flees), the blackboard entry persists until the next gather. Mitigation: `_cleanup_progress_bar` checks `is_instance_valid` and tolerates a stale reference. If SAI has a clearer plan-abort hook, wire the cleanup there instead.

- [ ] **Step 4: Parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/progress_bar.tscn scripts/ui/views/view_progress_bar.gd scripts/gameplay/goap/actions/gather_resource.gd
git commit -m "feat(ui): add worker progress bar view and wire into GatherResource

ViewProgressBar is a minimal Control with a background + fill ColorRect
that follows an entity in world space. GoapAction_GatherResource owns
its lifetime: instantiate in on_plan_enter, update fill ratio each
perform() tick, free in on_plan_exit.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 16: Work goal + entity recipes (.tres)

**Files:**
- Create: `resources/goals/work.tres`
- Create: `resources/recipes/npc_worker.tres`
- Create: `resources/recipes/camp_stockpile.tres`
- Create: `resources/recipes/tree.tres`

These are Godot Resource files. Create them in the editor where possible; the text format below is a fallback.

- [ ] **Step 1: Read an existing goal for reference**

```bash
cat resources/goals/patrol_camp.tres
cat resources/goals/survive.tres
```

Note the field names and values (likely `goal_name`, `priority`, `desired_state`).

- [ ] **Step 2: Create `work.tres`**

Matching the pattern of existing goals:

```
[gd_resource type="Resource" script_class="GoapGoal" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/gameplay/goap/goap_goal.gd" id="1"]

[resource]
script = ExtResource("1")
goal_name = "Work"
priority = 20
desired_state = { "has_delivered": true }
```

Adjust field names to match `goap_goal.gd`.

- [ ] **Step 3: Read an existing recipe for reference**

```bash
cat resources/recipes/survivor.tres
cat resources/recipes/npc_composer.tres
```

Note how components are referenced (likely as a list of `Component` resources or a dict).

- [ ] **Step 4: Create `npc_worker.tres`**

Base on `survivor.tres` but:
- Remove `CGuard`
- Add `CWorker`
- Replace goal list with `[Survive, Flee, Work]`
- Actions list must include: `Flee`, `FindWorkTarget`, `MoveToResourceNode`, `GatherResource`, `MoveToStockpile`, `DepositResource` (plus whatever Survive requires)

Exact field layout depends on `entity_recipe.gd` — read it once to understand the schema.

- [ ] **Step 5: Create `camp_stockpile.tres`**

Components:
- `CTransform`
- `CSprite` (use an existing cube/box texture from `assets/` — check `box_re_texture.png` or similar)
- `CCollision` (32x32 solid RectangleShape2D)
- `CStockpile` (empty contents, empty per_type_caps for the prototype)

- [ ] **Step 6: Create `tree.tres`**

Components:
- `CTransform`
- `CSprite` (use a placeholder — check existing assets for a plant/tree-like texture, or repurpose an enemy sprite temporarily)
- `CCollision` (small solid RectangleShape2D, 16x16)
- `CResourceNode` with:
  - `yield_type` = preload `r_wood.gd` (set via editor picker)
  - `yield_amount = 1`
  - `gather_duration = 2.0`
  - `infinite = true`
  - `remaining_yield = -1`

- [ ] **Step 7: Parse check + register recipes in ServiceContext**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

If `ServiceContext.recipe()` auto-discovers recipes from the `resources/recipes/` folder, nothing else is needed. If it uses an explicit registry, read `service_recipe.gd` and add the 3 new entries.

- [ ] **Step 8: Commit**

```bash
git add resources/goals/work.tres resources/recipes/npc_worker.tres resources/recipes/camp_stockpile.tres resources/recipes/tree.tres
git commit -m "feat(resource): add Work goal and worker/stockpile/tree recipes

- work.tres: GOAP goal with desired_state has_delivered=true, priority 20
- npc_worker.tres: survivor-based recipe with CWorker and Work goal
- camp_stockpile.tres: static box entity with CStockpile
- tree.tres: static entity with CResourceNode(RWood, infinite)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 17: GOLWorld spawn extensions + tree scatter

**Files:**
- Modify: `scripts/gameplay/ecs/gol_world.gd`

Three changes here:
1. Add `CStockpile` to player entity on spawn
2. Spawn 1 `camp_stockpile.tres` and 1 `npc_worker.tres` at camp offsets
3. Scatter `tree.tres` entities across the map after PCG completes

- [ ] **Step 1: Read GOLWorld**

```bash
cat scripts/gameplay/ecs/gol_world.gd
```

Locate:
- Where the player is spawned (search for `create_entity_by_id("player")`)
- Where the campfire is spawned (look for `campfire` recipe usage)
- Where PCG result is read (likely in `initialize()` or `_ready()`)
- Where POI-driven entity placement happens

- [ ] **Step 2: Add CStockpile to player**

Right after the player entity is created and before it's added to the world, append:

```gdscript
var player_stockpile := CStockpile.new()
player_entity.add_component(player_stockpile)
```

- [ ] **Step 3: Spawn camp stockpile and worker**

In the same function that spawns the campfire (or a dedicated `spawn_camp` helper), after the campfire is spawned, add:

```gdscript
var config := CONFIG.new()  # if not already available in the function
var campfire_pos: Vector2 = ... # the position used for campfire spawn

# Camp stockpile
var stockpile_entity := ServiceContext.recipe().create_entity_by_id("camp_stockpile")
var stockpile_transform: CTransform = stockpile_entity.get_component(CTransform)
stockpile_transform.position = campfire_pos + config.STOCKPILE_SPAWN_OFFSET
ECS.world.add_entity(stockpile_entity)

# Worker NPC
var worker_entity := ServiceContext.recipe().create_entity_by_id("npc_worker")
var worker_transform: CTransform = worker_entity.get_component(CTransform)
worker_transform.position = campfire_pos + config.WORKER_SPAWN_OFFSET
ECS.world.add_entity(worker_entity)
```

- [ ] **Step 4: Add tree scatter helper**

At the end of the PCG-post-processing phase (after campfire/guards/composer are spawned), call a new helper:

```gdscript
func _scatter_tree_entities(pcg_result: PCGResult) -> void:
	var config := CONFIG.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(pcg_result.seed if "seed" in pcg_result else 0))

	var walkable_cells: Array[Vector2i] = _collect_walkable_cells(pcg_result, config.TREE_POI_EXCLUSION_RADIUS)
	if walkable_cells.is_empty():
		return

	var placed := 0
	while placed < config.TREE_SCATTER_COUNT and walkable_cells.size() > 0:
		var idx := rng.randi_range(0, walkable_cells.size() - 1)
		var cell := walkable_cells[idx]
		walkable_cells.remove_at(idx)

		var world_pos := _cell_to_world(cell)   # use the existing conversion helper
		var tree := ServiceContext.recipe().create_entity_by_id("tree")
		var t: CTransform = tree.get_component(CTransform)
		t.position = world_pos
		ECS.world.add_entity(tree)
		placed += 1


func _collect_walkable_cells(pcg_result: PCGResult, exclusion_radius_px: float) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	# Iterate pcg_result.grid (Dictionary[Vector2i, PCGCell])
	# Include cells where:
	#   cell.logic_type == GROUND (or whatever the walkable tag is)
	#   cell.poi_type == NONE
	# Additionally filter cells within exclusion_radius_px of ANY POI cell
	# (use a simple distance check against a pre-computed POI cell list)
	for key in pcg_result.grid:
		var cell: PCGCell = pcg_result.grid[key]
		# Exact enum values live in PCGCell / poi_list.gd — read those files to
		# use the right constants. The conceptual check is:
		#   cell is GROUND logic, cell has no POI, cell is outside exclusion radius
		if _is_walkable_ground(cell) and _is_outside_poi_exclusion(key, pcg_result, exclusion_radius_px):
			cells.append(key)
	return cells
```

**Important:** This pseudo-implementation requires reading `pcg_cell.gd` and `poi_list.gd` to use the correct enum constants. The implementer should replace the `_is_walkable_ground` and `_is_outside_poi_exclusion` helpers with concrete implementations based on actual PCG types. If those types aren't obvious, fall back to a simpler strategy: just pick random grid cells where `cell.poi_type == NONE`, ignoring exclusion radius for the prototype.

Call `_scatter_tree_entities(pcg_result)` from the post-PCG initialization block, after camp spawn.

- [ ] **Step 5: Parse check + smoke run**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "OK"
```

- [ ] **Step 6: Commit**

```bash
git add scripts/gameplay/ecs/gol_world.gd
git commit -m "feat(resource): GOLWorld spawns camp stockpile, worker, and trees

- Player entity gains CStockpile on spawn (home for RComponentPoint)
- spawn_camp extended: one camp_stockpile + one npc_worker at offsets
- Post-PCG: scatter TREE_SCATTER_COUNT tree entities on walkable cells
  outside the POI exclusion radius

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 18: Integration test — worker gather loop

**Files:**
- Create: `tests/integration/flow/test_flow_worker_gather.gd`

- [ ] **Step 1: Delegate test creation**

```
task(category="deep", load_skills=["gol-test-writer-integration"], prompt="
Create tests/integration/flow/test_flow_worker_gather.gd.

Use the SceneConfig integration test pattern (see tests/integration/
AGENTS.md and existing test_flow_*.gd files).

Scene setup:
  - 1 player entity (position irrelevant, but must exist for any system
    that queries CPlayer)
  - 1 camp stockpile entity at (0, 0) with empty CStockpile
  - 1 worker entity at (0, 0) with CWorker, CGoapAgent (goals: Survive/Flee/Work,
    actions: Flee/FindWorkTarget/MoveToResourceNode/GatherResource/MoveToStockpile/DepositResource),
    CTransform, CMovement, CHP, CCollision, CSprite
  - 1 tree entity at (100, 0) with CResourceNode(RWood, yield_amount=1,
    gather_duration=0.5, infinite=true), CTransform, CCollision

Test:
  test_worker_gathers_and_deposits_wood
    - Initial: camp_stockpile.get_amount(RWood) == 0
    - Step the world forward (use whatever step helper the harness
      provides — likely something like 'await _step_world(seconds)')
      for 10 seconds
    - Assert: camp_stockpile.get_amount(RWood) >= 1 (at least one full
      gather+deposit cycle happened)
    - Assert: worker entity has no CCarrying component after the cycle
      (it's either pre-gather or post-deposit, not mid-haul)

  test_worker_completes_multiple_cycles
    - Same scene
    - Step forward 30 seconds
    - Assert: camp_stockpile.get_amount(RWood) >= 3

Use gather_duration=0.5 (shorter than prototype default) so the test
runs fast. Worker movement speed should be the default from survivor
recipe.

Tier: deep (uses SceneConfig + full World).
")
```

- [ ] **Step 2: Delegate test run**

```
task(category="quick", load_skills=["gol-test-runner"], prompt="
Run tests/integration/flow/test_flow_worker_gather.gd and report
PASS/FAIL with details on any failure.
")
```

Expected: PASS (assuming all previous tasks landed correctly).

**If FAIL**, the failure is almost certainly in one of these common spots:
1. **Goal priority / action preconditions** — planner can't build a plan. Check that `Work` goal's `desired_state` has a fact that's achievable only via the action chain.
2. **Fact clearing** — worker completes one plan and stops. Task 14's SAI hook is the culprit.
3. **MoveTo base class mismatch** — wrong hook names in MoveToResourceNode / MoveToStockpile. Re-read the base class.
4. **Entity query context** — `ECS.world` is not the same world the test uses. Check how the test harness wires ECS.

Iterate until green before moving on.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/flow/test_flow_worker_gather.gd
git commit -m "test(resource): integration test for full worker gather loop

Scene: player + camp stockpile + worker + 1 tree. Verifies that the
worker autonomously gathers wood and deposits it into the camp
stockpile over a short time window. Also verifies multiple-cycle
continuous operation.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 19: Integration test — worker flee from threat

**Files:**
- Create: `tests/integration/flow/test_flow_worker_flee.gd`

- [ ] **Step 1: Delegate test creation**

```
task(category='deep', load_skills=['gol-test-writer-integration'], prompt='
Create tests/integration/flow/test_flow_worker_flee.gd.

Scene: same as test_flow_worker_gather plus one enemy entity with
CCamp.ENEMY spawned at (50, 0) after the worker has been running for
a moment.

Test:
  test_worker_flees_on_threat_and_resumes
    - Step forward 2 seconds so the worker starts gathering
    - Spawn enemy at (50, 0) — close enough to trigger CPerception
    - Step forward 3 seconds
    - Assert: worker Survive/Flee goal is active (can check via
      agent.blackboard or last action type — use whatever inspection
      the test harness provides)
    - Remove the enemy entity
    - Step forward 10 seconds
    - Assert: camp_stockpile.get_amount(RWood) >= 1 (worker resumed
      Work after threat cleared)

  test_worker_retains_carrying_during_flee
    - Configure tree with gather_duration=0.3 so first load happens fast
    - Step forward 1 second (enough for the first chop + CCarrying add)
    - Assert: worker has CCarrying(RWood, 1)
    - Spawn enemy; step 2 seconds
    - Assert: worker still has CCarrying (flee doesn't drop the load)
    - Remove enemy; step 10 seconds
    - Assert: stockpile has at least 1 wood (worker delivered the load
      after fleeing)

Tier: deep.
')
```

- [ ] **Step 2: Delegate test run, iterate until PASS**

Expected: PASS. Common failures: worker flees toward the camp and eventually gets back into gather range organically — that's fine, as long as the assertion windows are met.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/flow/test_flow_worker_flee.gd
git commit -m "test(resource): integration test for worker flee behavior

Verifies that Survive/Flee preempts Work when a threat appears, the
worker retains CCarrying during flee, and resumes gathering once the
threat is removed.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 20: Adapt existing composer integration test

**Files:**
- Modify: `tests/integration/flow/test_flow_composer_scene.gd` (if it exists)

Orient first:

```bash
ls tests/integration/flow/ | grep -i composer
```

- [ ] **Step 1: If the test file exists, delegate adaptation**

```
task(category='deep', load_skills=['gol-test-writer-integration'], prompt='
Adapt tests/integration/flow/test_flow_composer_scene.gd to the new
composer_utils signatures.

Changes required:
1. Player entity setup must include a CStockpile with initial
   RComponentPoint amount appropriate for each test case
2. Any call to composer_utils.craft_component or dismantle_component
   must use the new signature: (player_entity, component_type) — the
   player_data argument is removed
3. Any assertion about GOL.Player.component_points or
   PlayerData.component_points must become an assertion about
   player_entity.get_component(CStockpile).get_amount(RComponentPoint)
4. Any call or subscription to PlayerData.points_changed must be
   removed or replaced with a subscription to the stockpile
   changed_observable

Preserve all test cases (names and intent). Keep existing assertions
about unlocked_blueprints.

Return the adapted file.
')
```

If the file does NOT exist, skip this task.

- [ ] **Step 2: Delegate test run**

```
task(category="quick", load_skills=["gol-test-runner"], prompt="
Run tests/integration/flow/test_flow_composer_scene.gd and report PASS/FAIL.
")
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/flow/test_flow_composer_scene.gd
git commit -m "test(resource): adapt composer integration test to CStockpile

Player entity now gets CStockpile(RComponentPoint) instead of
PlayerData.component_points. Craft/dismantle assertions read from the
stockpile via get_amount(RComponentPoint).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 21: Full regression — run all tests

**Files:** none

- [ ] **Step 1: Delegate full test run**

```
task(category='quick', load_skills=['gol-test-runner'], prompt='
Run the full project test suite (both unit and integration tiers) and
report PASS/FAIL with a summary of any failing tests.
')
```

Expected: PASS across the board.

**If anything fails**, inspect and fix. Likely culprits after a big change like this:
- Pre-existing tests that touch `PlayerData.component_points` (search for any we missed in Task 5/20)
- Pre-existing tests that assume `points_changed` signal exists
- Scene fixtures that load view_hud.tscn and fail to find the new WoodPanel

Do not commit until green.

- [ ] **Step 2: If fixes were needed, commit**

```bash
git add -A
git commit -m "test(resource): fix pre-existing tests affected by component_points migration

<describe which tests and why>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 22: Manual smoke test

**Files:** none

- [ ] **Step 1: Launch the game**

```bash
godot --path . 2>&1 | tee /tmp/gol-smoke.log
```

- [ ] **Step 2: Verify observable behavior**

Check list:
- [ ] Game boots without errors. No SCRIPT ERROR in `/tmp/gol-smoke.log`.
- [ ] A worker NPC is visible at the camp near the stockpile cube.
- [ ] The worker walks toward a visible tree (may be visible or just off-screen — watch the worker's movement direction).
- [ ] While chopping, a progress bar appears above the worker and fills over ~2 seconds.
- [ ] The worker then walks back to the camp cube.
- [ ] On arrival, the HUD's "木材: N" counter increments by 1.
- [ ] The worker immediately picks another tree and repeats the cycle.
- [ ] The existing composer dialogue at the composer NPC still works: can dismantle a losable component and see `组件点: N` increment; can craft after dismantling enough.
- [ ] Spawning an enemy near the worker (via debug console if available, or by walking near an enemy spawner) causes the worker to flee. After the enemy dies, the worker resumes gathering.

- [ ] **Step 3: If any visual issues (overlapping sprites, wrong Z-order, etc.), note them as follow-ups**

These are not blockers for the prototype — the spec explicitly scopes "no animations" and placeholder art is fine.

- [ ] **Step 4: No commit needed for smoke test alone**

If smoke test revealed a real bug (not art), fix it and commit with a clear `fix(resource): ...` message.

---

## Task 23: Push and update submodule pointer

**Files:** (management repo)

- [ ] **Step 1: Push the feature branch to gol-project origin**

```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/manual/resource-system
git push -u origin feat/resource-system
```

- [ ] **Step 2: Return to the main gol-project checkout and fast-forward / merge**

The submodule `main` needs to point at the new commit. Since development happens on a feature branch, this typically means opening a PR, merging it, then updating the submodule pointer. For an autonomous agent without PR flow, the sequence is:

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
git fetch origin
# Only merge to main if the user has authorized it. Otherwise stop here
# and report the PR-ready state.
```

**STOP and ask the user** whether to open a PR or merge directly. This is a non-local action.

- [ ] **Step 3: Once merged (or if user authorizes a direct merge), update the management repo pointer**

```bash
cd /Users/dluckdu/Documents/Github/gol
git add gol-project
git commit -m "chore: bump gol-project submodule for resource system prototype

Includes:
- CStockpile / CResourceNode / CCarrying / CWorker components
- RWood / RComponentPoint resource type classes
- 5 new GOAP actions (FindWorkTarget, MoveToResourceNode,
  GatherResource, MoveToStockpile, DepositResource) and Work goal
- Worker NPC recipe + camp stockpile recipe + tree recipe
- PlayerData.component_points migration into CStockpile
- HUD wood counter + worker progress bar
- Integration tests for full gather loop and flee-resume

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
git push
```

- [ ] **Step 4: Clean up the worktree**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
git worktree remove ../.worktrees/manual/resource-system
```

---

## Wrap-up checklist

Before declaring the task complete:

- [ ] All 22 implementation tasks committed
- [ ] Full test suite green (unit + integration)
- [ ] Manual smoke test passed
- [ ] Submodule feature branch pushed
- [ ] (If authorized) Submodule merged and management repo pointer updated and pushed
- [ ] (If authorized) Worktree cleaned up
- [ ] No uncommitted files under `docs/`

Stale AGENTS.md catalog entries — note them for the user:
- `scripts/components/AGENTS.md` should gain rows for `CStockpile`, `CResourceNode`, `CCarrying`, `CWorker`
- `scripts/gameplay/AGENTS.md` GOAP catalogs should gain the new goal, facts, and action rows

These can be done as a follow-up commit or deferred to the user per the "stale AGENTS.md" rule in `gol/CLAUDE.md`.
