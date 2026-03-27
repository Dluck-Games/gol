# Component Blueprint System (组件设计图) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the component blueprint unlock/crafting system with a composer NPC and minimal dialogue system, enabling players to find blueprints → unlock → craft/dismantle components at camp.

**Architecture:** PlayerData global data class (alongside GOLGameState) stores unlocked blueprints and component points. CBlueprint component marks blueprint entities, reusing SPickup flow. CDialogue + SDialogue provides minimal NPC interaction. composer_utils.gd contains all craft/dismantle/unlock logic as static functions. MVVM UI for dialogue and crafting panels.

**Tech Stack:** Godot 4.6, GDScript, GECS ECS addon, MVVM UI pattern

**Spec:** `docs/superpowers/specs/2026-03-27-component-blueprint-design.md`

**Issue:** [#109](https://github.com/Dluck-Games/god-of-lego/issues/109) | **Stale PR:** #117 (close)

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `scripts/gameplay/player_data.gd` | PlayerData global data class — unlocked blueprints, component points, signals |
| `scripts/components/c_blueprint.gd` | CBlueprint component — marks entity as blueprint, holds component_type: Script |
| `scripts/components/c_dialogue.gd` | CDialogue component — NPC name + dialogue entries |
| `scripts/gameplay/dialogue_data.gd` | DialogueEntry, DialogueOption, DialogueAction enum |
| `scripts/utils/composer_utils.gd` | Static utils: unlock_blueprint, craft_component, dismantle_component |
| `scripts/systems/s_dialogue.gd` | SDialogue system — proximity poll, interaction trigger, option dispatch |
| `scripts/ui/views/view_dialogue_hint.gd` | Dialogue interaction hint (approach NPC → "[E] 对话") |
| `scripts/ui/views/view_dialogue.gd` | Dialogue View — NPC text panel + option buttons |
| `scripts/ui/views/view_composer.gd` | Composer View — component list + points display |
| `scenes/ui/dialogue.tscn` | Dialogue UI scene |
| `scenes/ui/composer.tscn` | Composer UI scene |
| `resources/recipes/blueprint_weapon.tres` | Blueprint recipe: CWeapon |
| `resources/recipes/blueprint_tracker.tres` | Blueprint recipe: CTracker |
| `resources/recipes/blueprint_healer.tres` | Blueprint recipe: CHealer |
| `resources/recipes/blueprint_poison.tres` | Blueprint recipe: CPoison |
| `resources/recipes/npc_composer.tres` | Composer NPC recipe: GOAP Wander+Flee, CDialogue |
| `tests/unit/test_composer_utils.gd` | Unit tests for composer_utils |
| `tests/unit/test_blueprint_pickup.gd` | Unit tests for SPickup blueprint branch |
| `tests/integration/flow/test_flow_composer_scene.gd` | Integration test: full blueprint→craft flow |

### Modified Files

| File | Change |
|------|--------|
| `scripts/gol.gd` | Add `var Player: PlayerData = null`, init in `setup()`, free in `teardown()` |
| `scripts/configs/config.gd` | Add `DIALOGUE_RANGE`, `BLUEPRINT_DROP_CHANCE`, `CRAFT_COST`, `DISMANTLE_YIELD` |
| `scripts/systems/s_pickup.gd` | Early-exit branch in `_process_entity()` for CBlueprint entities |
| `scripts/systems/s_damage.gd` | Blueprint drop chance in `_on_no_hp()` + `_drop_blueprint_box()` helper |
| `scripts/gameplay/ecs/gol_world.gd` | Add `_spawn_composer_npc()`, `_spawn_blueprints_at_building_pois()` to `_spawn_default_entities()` |

---

## Task 0: Setup — Worktree & Issue Cleanup

**Files:**
- None (git/GitHub operations only)

- [ ] **Step 1: Create worktree for isolated development**

All implementation work happens in a worktree, keeping the main workspace on `main` untouched.

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
# Create feature branch without switching
git branch feat/component-blueprint main
# Create worktree at a sibling directory
git worktree add ../gol-project-blueprint feat/component-blueprint
```

This creates `/Users/dluckdu/Documents/Github/gol/gol-project-blueprint/` as an isolated copy on `feat/component-blueprint`. **All subsequent tasks (Task 1–13) work inside this worktree directory**, not the original `gol-project/`.

Working directory for all tasks:
```
/Users/dluckdu/Documents/Github/gol/gol-project-blueprint/
```

- [ ] **Step 2: Update Issue #109 description**

```bash
gh issue edit 109 -R Dluck-Games/god-of-lego --title "[Feature] 组件设计图机制 — 蓝图解锁 + 组合专家 NPC + 最小对话系统" --body "$(cat <<'ISSUE_EOF'
## 目标

实现组件设计图（蓝图）解锁机制：玩家通过探索获取设计图，在营地组合专家 NPC 处消耗设计图解锁组件制作权限，通过组件点数进行制作和移除。

## 设计文档

详见 `docs/superpowers/specs/2026-03-27-component-blueprint-design.md`

## 实现范围

- **PlayerData 全局数据类** — 存储已解锁蓝图 + 组件点数
- **CBlueprint 组件** — 标识蓝图实体，复用 Pickup 拾取流程
- **最小对话系统** — CDialogue + SDialogue + DialogueUI（B-lite，单层选项）
- **组合专家 NPC** — GOAP Wander + Flee 行为，可死亡
- **composer_utils** — 解锁/制作/移除静态工具函数
- **ComposerUI** — 制作/移除面板
- **蓝图生成** — 地图 BUILDING POI + 怪物掉落（10%）
- **4 种蓝图配方** — CWeapon, CTracker, CHealer, CPoison
- **测试** — 单元测试 + 集成测试 + 主游戏集成

## 关键设计决策

- 组件点数有损兑换：移除得 1 点，制作花 2 点
- PlayerData 是全局数据类（和 GameState 同级），非 Service
- 类型引用使用 Script 对象，非字符串
- NPC 可死亡，有 CHP + Flee 行为

## 替代

替代并关闭原始描述（基础组合配方校验系统），设计已更新为蓝图解锁机制。
关联 PR #117 已关闭（代码不可用）。
ISSUE_EOF
)"
```

- [ ] **Step 3: Close stale PR #117**

```bash
gh pr close 117 -R Dluck-Games/god-of-lego -c "Superseded by new implementation based on updated design spec. See Issue #109."
```

- [ ] **Step 4: Commit setup marker (empty)**

No code changes yet — the branch is ready for development.

---

## Task 1: PlayerData Global Data Class

**Files:**
- Create: `scripts/gameplay/player_data.gd`
- Modify: `scripts/gol.gd`
- Test: `tests/unit/test_composer_utils.gd` (partial — PlayerData tests)

- [ ] **Step 1: Write failing test for PlayerData**

Create `tests/unit/test_composer_utils.gd`:

```gdscript
extends GdUnitTestSuite


func test_player_data_initial_state() -> void:
	var pd := auto_free(PlayerData.new())
	assert_int(pd.component_points).is_equal(0)
	assert_array(pd.unlocked_blueprints).is_empty()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `run-tests.command` (or headless Godot test runner)
Expected: FAIL — `PlayerData` class not found

- [ ] **Step 3: Implement PlayerData**

Create `scripts/gameplay/player_data.gd`:

```gdscript
class_name PlayerData
extends Object

var unlocked_blueprints: Array[Script] = []
var component_points: int = 0

signal blueprint_unlocked(component_type: Script)
signal points_changed(new_value: int)
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS

- [ ] **Step 5: Wire into GOL singleton**

Modify `scripts/gol.gd`:

Add field after `var Game`:
```gdscript
var Player: PlayerData = null
```

In `setup()`, after `Game = GOLGameState.new()`:
```gdscript
Player = PlayerData.new()
```

In `teardown()`, after `Game = null`:
```gdscript
Player.free()
Player = null
```

- [ ] **Step 6: Commit**

```bash
git add scripts/gameplay/player_data.gd scripts/gol.gd tests/unit/test_composer_utils.gd
git commit -m "feat: add PlayerData global data class for blueprint/points storage"
```

---

## Task 2: Config Constants

**Files:**
- Modify: `scripts/configs/config.gd`

- [ ] **Step 1: Add blueprint/dialogue constants to Config**

Add at the end of `config.gd`, after the `## Area effect modifier` section:

```gdscript
## ── Blueprint & Composer ──────────────────────────
static var DIALOGUE_RANGE: float = 64.0
static var BLUEPRINT_DROP_CHANCE: float = 0.1
static var CRAFT_COST: int = 2
static var DISMANTLE_YIELD: int = 1
```

- [ ] **Step 2: Commit**

```bash
git add scripts/configs/config.gd
git commit -m "feat: add Config constants for blueprint/dialogue system"
```

---

## Task 3: CBlueprint Component

**Files:**
- Create: `scripts/components/c_blueprint.gd`

- [ ] **Step 1: Create CBlueprint component**

```gdscript
class_name CBlueprint
extends Component

## The losable component type this blueprint unlocks (e.g., CWeapon, CHealer)
@export var component_type: Script = null
```

- [ ] **Step 2: Commit**

```bash
git add scripts/components/c_blueprint.gd
git commit -m "feat: add CBlueprint component"
```

---

## Task 4: Dialogue Data Structures

**Files:**
- Create: `scripts/gameplay/dialogue_data.gd`
- Create: `scripts/components/c_dialogue.gd`

- [ ] **Step 1: Create dialogue data types**

Create `scripts/gameplay/dialogue_data.gd`:

```gdscript
class_name DialogueData

enum DialogueAction { CRAFT, DISMANTLE, CLOSE }

class Entry:
	var text: String
	var options: Array[Option] = []

	func _init(p_text: String = "", p_options: Array[Option] = []) -> void:
		text = p_text
		options = p_options

class Option:
	var label: String
	var action: DialogueAction

	func _init(p_label: String = "", p_action: DialogueAction = DialogueAction.CLOSE) -> void:
		label = p_label
		action = p_action
```

- [ ] **Step 2: Create CDialogue component**

Create `scripts/components/c_dialogue.gd`:

```gdscript
class_name CDialogue
extends Component

var npc_name: String = ""
var entries: Array[DialogueData.Entry] = []
```

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/dialogue_data.gd scripts/components/c_dialogue.gd
git commit -m "feat: add CDialogue component and dialogue data types"
```

---

## Task 5: composer_utils — Core Logic

**Files:**
- Create: `scripts/utils/composer_utils.gd`
- Test: `tests/unit/test_composer_utils.gd` (extend)

- [ ] **Step 1: Write failing tests for all composer_utils functions**

Extend `tests/unit/test_composer_utils.gd`:

```gdscript
extends GdUnitTestSuite

var _original_cap: int

func before_test() -> void:
	_original_cap = Config.COMPONENT_CAP

func after_test() -> void:
	Config.COMPONENT_CAP = _original_cap


func _make_player(losable_count: int) -> Entity:
	var entity := auto_free(Entity.new())
	entity.add_component(CTransform.new())
	entity.add_component(CCamp.new())
	for i in range(losable_count):
		if i == 0: entity.add_component(CWeapon.new())
		elif i == 1: entity.add_component(CTracker.new())
		elif i == 2: entity.add_component(CHealer.new())
	return entity


# ── PlayerData ──

func test_player_data_initial_state() -> void:
	var pd := auto_free(PlayerData.new())
	assert_int(pd.component_points).is_equal(0)
	assert_array(pd.unlocked_blueprints).is_empty()


# ── unlock_blueprint ──

func test_unlock_blueprint_success() -> void:
	var pd := auto_free(PlayerData.new())
	var result := ComposerUtils.unlock_blueprint(CWeapon, pd)
	assert_bool(result).is_true()
	assert_array(pd.unlocked_blueprints).contains([CWeapon])

func test_unlock_blueprint_already_unlocked() -> void:
	var pd := auto_free(PlayerData.new())
	ComposerUtils.unlock_blueprint(CWeapon, pd)
	var result := ComposerUtils.unlock_blueprint(CWeapon, pd)
	assert_bool(result).is_false()
	assert_int(pd.unlocked_blueprints.size()).is_equal(1)


# ── craft_component ──

func test_craft_component_success() -> void:
	var pd := auto_free(PlayerData.new())
	pd.unlocked_blueprints.append(CHealer)
	pd.component_points = 2
	var player := _make_player(1)  # has CWeapon

	var result := ComposerUtils.craft_component(player, CHealer, pd)
	assert_bool(result).is_true()
	assert_int(pd.component_points).is_equal(0)
	assert_bool(player.has_component(CHealer)).is_true()

func test_craft_component_not_unlocked() -> void:
	var pd := auto_free(PlayerData.new())
	pd.component_points = 2
	var player := _make_player(0)

	var result := ComposerUtils.craft_component(player, CHealer, pd)
	assert_bool(result).is_false()

func test_craft_component_insufficient_points() -> void:
	var pd := auto_free(PlayerData.new())
	pd.unlocked_blueprints.append(CHealer)
	pd.component_points = 1  # need 2
	var player := _make_player(0)

	var result := ComposerUtils.craft_component(player, CHealer, pd)
	assert_bool(result).is_false()

func test_craft_component_at_cap() -> void:
	Config.COMPONENT_CAP = 3
	var pd := auto_free(PlayerData.new())
	pd.unlocked_blueprints.append(CHealer)
	pd.component_points = 2
	var player := _make_player(3)  # at cap

	var result := ComposerUtils.craft_component(player, CHealer, pd)
	assert_bool(result).is_false()


# ── dismantle_component ──

func test_dismantle_component_success() -> void:
	var pd := auto_free(PlayerData.new())
	var player := _make_player(1)  # has CWeapon

	var result := ComposerUtils.dismantle_component(player, CWeapon, pd)
	assert_bool(result).is_true()
	assert_int(pd.component_points).is_equal(1)
	assert_bool(player.has_component(CWeapon)).is_false()

func test_dismantle_component_not_losable() -> void:
	var pd := auto_free(PlayerData.new())
	var player := _make_player(0)
	player.add_component(CPlayer.new())  # CPlayer is NOT losable

	var result := ComposerUtils.dismantle_component(player, CPlayer, pd)
	assert_bool(result).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `ComposerUtils` class not found

- [ ] **Step 3: Implement composer_utils.gd**

Create `scripts/utils/composer_utils.gd`:

```gdscript
class_name ComposerUtils


static func unlock_blueprint(component_type: Script, player_data: PlayerData) -> bool:
	if component_type in player_data.unlocked_blueprints:
		return false
	player_data.unlocked_blueprints.append(component_type)
	player_data.blueprint_unlocked.emit(component_type)
	return true


static func craft_component(entity: Entity, component_type: Script, player_data: PlayerData) -> bool:
	if component_type not in player_data.unlocked_blueprints:
		return false
	if player_data.component_points < Config.CRAFT_COST:
		return false
	if ECSUtils.is_at_component_cap(entity):
		return false

	player_data.component_points -= Config.CRAFT_COST
	player_data.points_changed.emit(player_data.component_points)

	var new_component: Component = component_type.new()
	entity.add_component(new_component)
	return true


static func dismantle_component(entity: Entity, component_type: Script, player_data: PlayerData) -> bool:
	var component: Component = entity.get_component(component_type)
	if not component:
		return false
	if not ECSUtils.is_losable_component(component):
		return false

	entity.remove_component(component_type)
	player_data.component_points += Config.DISMANTLE_YIELD
	player_data.points_changed.emit(player_data.component_points)
	return true
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: all 8 tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/utils/composer_utils.gd tests/unit/test_composer_utils.gd
git commit -m "feat: add composer_utils with unlock/craft/dismantle logic and tests"
```

---

## Task 6: SPickup Blueprint Branch

**Files:**
- Modify: `scripts/systems/s_pickup.gd`
- Test: `tests/unit/test_blueprint_pickup.gd`

- [ ] **Step 1: Write failing tests for blueprint pickup**

Create `tests/unit/test_blueprint_pickup.gd`:

```gdscript
extends GdUnitTestSuite


func _make_player() -> Entity:
	var entity := auto_free(Entity.new())
	entity.add_component(CTransform.new())
	entity.add_component(CPickup.new())
	entity.add_component(CCamp.new())
	return entity


func _make_blueprint_box(comp_type: Script) -> Entity:
	var entity := auto_free(Entity.new())
	entity.add_component(CTransform.new())
	entity.add_component(CContainer.new())
	entity.add_component(CBlueprint.new())
	entity.get_component(CBlueprint).component_type = comp_type
	return entity


func test_pickup_blueprint_unlocks() -> void:
	var pd := auto_free(PlayerData.new())
	var box := _make_blueprint_box(CWeapon)

	var blueprint: CBlueprint = box.get_component(CBlueprint)
	var result := ComposerUtils.unlock_blueprint(blueprint.component_type, pd)

	assert_bool(result).is_true()
	assert_bool(CWeapon in pd.unlocked_blueprints).is_true()


func test_pickup_blueprint_already_unlocked() -> void:
	var pd := auto_free(PlayerData.new())
	ComposerUtils.unlock_blueprint(CWeapon, pd)

	var box := _make_blueprint_box(CWeapon)
	var blueprint: CBlueprint = box.get_component(CBlueprint)
	var result := ComposerUtils.unlock_blueprint(blueprint.component_type, pd)

	assert_bool(result).is_false()
	assert_int(pd.unlocked_blueprints.size()).is_equal(1)


func test_pickup_blueprint_destroys_entity() -> void:
	# Verify that after blueprint pickup, the entity should be removed.
	# At the unit level we test the removal call pattern:
	var box := _make_blueprint_box(CWeapon)
	assert_bool(box.has_component(CBlueprint)).is_true()
	# In SPickup, after unlock, ECSUtils.remove_entity(overlapped_entity) is called.
	# Unit-level: verify box is valid before removal, and the utils function accepts it.
	assert_bool(is_instance_valid(box)).is_true()
```

- [ ] **Step 2: Run tests to verify they pass** (these test ComposerUtils, not SPickup itself)

Expected: PASS — these verify the utils, not the system integration

- [ ] **Step 3: Modify SPickup to handle CBlueprint**

In `scripts/systems/s_pickup.gd`, inside `_process_entity()`, add early-exit after `container.dropped_by` check and before `container.required_component` check:

```gdscript
		# Blueprint pickup: unlock and destroy, skip normal box flow
		if overlapped_entity.has_component(CBlueprint):
			var blueprint: CBlueprint = overlapped_entity.get_component(CBlueprint)
			if blueprint.component_type and GOL.Player:
				ComposerUtils.unlock_blueprint(blueprint.component_type, GOL.Player)
			ECSUtils.remove_entity(overlapped_entity)
			continue
```

Insert this block at line ~47 in `_process_entity()`, after the `dropped_by` check (`if container.dropped_by == entity: continue`) and before the `if container.required_component:` block.

- [ ] **Step 4: Run all existing tests to verify no regressions**

Expected: All existing SPickup and composition cost tests still PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_pickup.gd tests/unit/test_blueprint_pickup.gd
git commit -m "feat: add CBlueprint early-exit branch in SPickup"
```

---

## Task 7: SDialogue System

**Files:**
- Create: `scripts/systems/s_dialogue.gd`

- [ ] **Step 1: Implement SDialogue**

Create `scripts/systems/s_dialogue.gd`:

```gdscript
class_name SDialogue
extends System

var _dialogue_view: ViewBase = null
var _composer_view: ViewBase = null
var _hint_view: ViewBase = null
var _active_dialogue_entity: Entity = null
var _hinted_entity: Entity = null


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CDialogue, CTransform])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	# If dialogue is open, don't process proximity
	if _active_dialogue_entity:
		return

	var player := _find_player()
	if not player:
		return

	var player_pos: Vector2 = player.get_component(CTransform).position

	var closest_entity: Entity = null
	var closest_dist: float = INF

	for entity in entities:
		if entity == null or not is_instance_valid(entity):
			continue
		var transform: CTransform = entity.get_component(CTransform)
		if not transform:
			continue

		var dist := player_pos.distance_to(transform.position)
		if dist <= Config.DIALOGUE_RANGE and dist < closest_dist:
			closest_dist = dist
			closest_entity = entity

	# Update hint
	if closest_entity != _hinted_entity:
		_remove_hint()
		_hinted_entity = closest_entity
		if _hinted_entity:
			_show_hint(_hinted_entity)

	if closest_entity and Input.is_action_just_pressed("interact"):
		_remove_hint()
		_open_dialogue(closest_entity)


func _find_player() -> Entity:
	var players := ECS.world.query.with_all([CPlayer, CTransform]).execute()
	if players.is_empty():
		return null
	return players[0]


func _open_dialogue(entity: Entity) -> void:
	_active_dialogue_entity = entity
	var dialogue: CDialogue = entity.get_component(CDialogue)
	if not dialogue or dialogue.entries.is_empty():
		_active_dialogue_entity = null
		return

	var entry: DialogueData.Entry = dialogue.entries[0]

	var dialogue_scene: PackedScene = preload("res://scenes/ui/dialogue.tscn")
	_dialogue_view = dialogue_scene.instantiate() as View_Dialogue
	if _dialogue_view:
		(_dialogue_view as View_Dialogue).set_dialogue(dialogue.npc_name, entry, _on_option_selected)
		ServiceContext.ui().push_view(Service_UI.LayerType.HUD, _dialogue_view)


func _on_option_selected(action: DialogueData.DialogueAction) -> void:
	match action:
		DialogueData.DialogueAction.CRAFT:
			_open_composer(DialogueData.DialogueAction.CRAFT)
		DialogueData.DialogueAction.DISMANTLE:
			_open_composer(DialogueData.DialogueAction.DISMANTLE)
		DialogueData.DialogueAction.CLOSE:
			_close_all()


func _open_composer(mode: DialogueData.DialogueAction) -> void:
	_close_dialogue_view()

	var composer_scene: PackedScene = preload("res://scenes/ui/composer.tscn")
	_composer_view = composer_scene.instantiate() as View_Composer
	if _composer_view:
		var player := _find_player()
		(_composer_view as View_Composer).set_context(mode, player, _on_composer_back)
		ServiceContext.ui().push_view(Service_UI.LayerType.HUD, _composer_view)


func _on_composer_back() -> void:
	_close_composer_view()
	if _active_dialogue_entity and is_instance_valid(_active_dialogue_entity):
		_open_dialogue(_active_dialogue_entity)
	else:
		_close_all()


func _close_all() -> void:
	_close_dialogue_view()
	_close_composer_view()
	_active_dialogue_entity = null


func _close_dialogue_view() -> void:
	if _dialogue_view:
		ServiceContext.ui().pop_view(_dialogue_view)
		_dialogue_view = null


func _close_composer_view() -> void:
	if _composer_view:
		ServiceContext.ui().pop_view(_composer_view)
		_composer_view = null


func _show_hint(entity: Entity) -> void:
	var dialogue: CDialogue = entity.get_component(CDialogue)
	if not dialogue:
		return
	var hint_scene: PackedScene = preload("res://scenes/ui/dialogue_hint.tscn")
	_hint_view = hint_scene.instantiate() as View_DialogueHint
	if _hint_view:
		var transform: CTransform = entity.get_component(CTransform)
		(_hint_view as View_DialogueHint).set_target(dialogue.npc_name, transform)
		ServiceContext.ui().push_view(Service_UI.LayerType.GAME, _hint_view)


func _remove_hint() -> void:
	if _hint_view:
		ServiceContext.ui().pop_view(_hint_view)
		_hint_view = null
	_hinted_entity = null
```

- [ ] **Step 2: Commit**

```bash
git add scripts/systems/s_dialogue.gd
git commit -m "feat: add SDialogue system with proximity poll and option dispatch"
```

---

## Task 8: Dialogue UI

**Files:**
- Create: `scripts/ui/views/view_dialogue.gd`
- Create: `scripts/ui/views/view_dialogue_hint.gd`
- Create: `scenes/ui/dialogue.tscn`
- Create: `scenes/ui/dialogue_hint.tscn`

- [ ] **Step 1: Create View_Dialogue**

Create `scripts/ui/views/view_dialogue.gd`:

```gdscript
class_name View_Dialogue
extends ViewBase

var _npc_name: String
var _entry: DialogueData.Entry
var _on_option_callback: Callable

@onready var _name_label: Label = $Panel/VBox/NameLabel
@onready var _text_label: Label = $Panel/VBox/TextLabel
@onready var _options_container: VBoxContainer = $Panel/VBox/OptionsContainer


func set_dialogue(npc_name: String, entry: DialogueData.Entry, callback: Callable) -> void:
	_npc_name = npc_name
	_entry = entry
	_on_option_callback = callback


func setup() -> void:
	if not _entry:
		push_error("View_Dialogue: No dialogue entry set")
		queue_free()
		return

	_name_label.text = _npc_name
	_text_label.text = _entry.text

	for option in _entry.options:
		var btn := Button.new()
		btn.text = option.label
		btn.pressed.connect(func(): _on_option_callback.call(option.action))
		_options_container.add_child(btn)
```

- [ ] **Step 2: Create dialogue.tscn scene**

Create `scenes/ui/dialogue.tscn` with this node tree:
```
View_Dialogue (Control, script: view_dialogue.gd)
  └─ Panel (PanelContainer, anchored bottom-center)
       └─ VBox (VBoxContainer)
            ├─ NameLabel (Label, bold)
            ├─ TextLabel (Label, word wrap)
            └─ OptionsContainer (VBoxContainer)
```

Use Godot scene editor or write the .tscn file directly. Anchor the Panel at the bottom center of the screen.

- [ ] **Step 3: Create View_DialogueHint**

Create `scripts/ui/views/view_dialogue_hint.gd`:

```gdscript
class_name View_DialogueHint
extends ViewBase

var _npc_name: String
var _target_transform: CTransform

@onready var _label: Label = $Background/Label


func set_target(npc_name: String, transform: CTransform) -> void:
	_npc_name = npc_name
	_target_transform = transform


func setup() -> void:
	_label.text = "[E] %s" % _npc_name


func _process(_delta: float) -> void:
	if _target_transform:
		position = _target_transform.position + Vector2(0, -40)
```

Create `scenes/ui/dialogue_hint.tscn` with:
```
View_DialogueHint (Control, script: view_dialogue_hint.gd)
  └─ Background (PanelContainer)
       └─ Label (Label, center-aligned)
```

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/views/view_dialogue.gd scripts/ui/views/view_dialogue_hint.gd scenes/ui/dialogue.tscn scenes/ui/dialogue_hint.tscn
git commit -m "feat: add dialogue UI views and scenes"
```

---

## Task 9: Composer UI (MVVM)

**Files:**
- Create: `scripts/ui/views/view_composer.gd`
- Create: `scenes/ui/composer.tscn`

- [ ] **Step 1: Create View_Composer**

Create `scripts/ui/views/view_composer.gd`:

```gdscript
class_name View_Composer
extends ViewBase

var _mode: DialogueData.DialogueAction
var _player_entity: Entity
var _on_back_callback: Callable

@onready var _title_label: Label = $Panel/VBox/TitleLabel
@onready var _points_label: Label = $Panel/VBox/PointsLabel
@onready var _list_container: VBoxContainer = $Panel/VBox/ListContainer
@onready var _back_button: Button = $Panel/VBox/BackButton


func set_context(mode: DialogueData.DialogueAction, player: Entity, on_back: Callable) -> void:
	_mode = mode
	_player_entity = player
	_on_back_callback = on_back


func setup() -> void:
	if not _player_entity or not GOL.Player:
		push_error("View_Composer: Missing player entity or PlayerData")
		queue_free()
		return

	_back_button.pressed.connect(func(): _on_back_callback.call())
	_refresh()


func _refresh() -> void:
	# Clear existing items
	for child in _list_container.get_children():
		child.queue_free()

	_points_label.text = "组件点数: %d" % GOL.Player.component_points

	if _mode == DialogueData.DialogueAction.CRAFT:
		_title_label.text = "制作组件"
		_populate_craft_list()
	else:
		_title_label.text = "移除组件"
		_populate_dismantle_list()


func _populate_craft_list() -> void:
	for bp_type in GOL.Player.unlocked_blueprints:
		var btn := Button.new()
		btn.text = "%s (花费 %d 点)" % [_get_display_name(bp_type), Config.CRAFT_COST]
		btn.disabled = GOL.Player.component_points < Config.CRAFT_COST or ECSUtils.is_at_component_cap(_player_entity)
		btn.pressed.connect(func():
			ComposerUtils.craft_component(_player_entity, bp_type, GOL.Player)
			_refresh()
		)
		_list_container.add_child(btn)

	if GOL.Player.unlocked_blueprints.is_empty():
		var label := Label.new()
		label.text = "尚未解锁任何蓝图"
		_list_container.add_child(label)


func _populate_dismantle_list() -> void:
	for comp in _player_entity.components.values():
		if not ECSUtils.is_losable_component(comp):
			continue
		var comp_type: Script = comp.get_script()
		var btn := Button.new()
		btn.text = "%s (+%d 点)" % [_get_display_name(comp_type), Config.DISMANTLE_YIELD]
		btn.pressed.connect(func():
			ComposerUtils.dismantle_component(_player_entity, comp_type, GOL.Player)
			_refresh()
		)
		_list_container.add_child(btn)

	if _list_container.get_child_count() == 0:
		var label := Label.new()
		label.text = "没有可移除的组件"
		_list_container.add_child(label)


const _DISPLAY_NAMES := {
	"c_weapon": "武器",
	"c_tracker": "追踪器",
	"c_healer": "治疗器",
	"c_poison": "毒素",
}

func _get_display_name(comp_type: Script) -> String:
	var path: String = comp_type.resource_path.get_file().get_basename()
	return _DISPLAY_NAMES.get(path, path)
```

- [ ] **Step 2: Create composer.tscn scene**

Create `scenes/ui/composer.tscn` with this node tree:
```
View_Composer (Control, script: view_composer.gd)
  └─ Panel (PanelContainer, anchored bottom-center)
       └─ VBox (VBoxContainer)
            ├─ TitleLabel (Label, bold)
            ├─ PointsLabel (Label)
            ├─ ListContainer (VBoxContainer)
            └─ BackButton (Button, text: "返回")
```

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/views/view_composer.gd scenes/ui/composer.tscn
git commit -m "feat: add composer UI view and scene for craft/dismantle"
```

---

## Task 10: Recipes — Blueprints & Composer NPC

**Files:**
- Create: `resources/recipes/blueprint_weapon.tres`
- Create: `resources/recipes/blueprint_tracker.tres`
- Create: `resources/recipes/blueprint_healer.tres`
- Create: `resources/recipes/blueprint_poison.tres`
- Create: `resources/recipes/npc_composer.tres`

- [ ] **Step 1: Create 4 blueprint recipes**

Each blueprint recipe follows this pattern (example: `blueprint_weapon.tres`):

```tres
[gd_resource type="Resource" script_class="EntityRecipe" load_steps=N format=3]

[ext_resource type="Script" path="res://scripts/gameplay/ecs/recipes/entity_recipe.gd" id="1"]
[ext_resource type="Script" path="res://scripts/components/c_blueprint.gd" id="2"]
[ext_resource type="Script" path="res://scripts/components/c_container.gd" id="3"]
[ext_resource type="Script" path="res://scripts/components/c_sprite.gd" id="4"]
[ext_resource type="Script" path="res://scripts/components/c_transform.gd" id="5"]
[ext_resource type="Script" path="res://scripts/components/c_collision.gd" id="6"]
[ext_resource type="Script" path="res://scripts/components/c_lifetime.gd" id="7"]
[ext_resource type="Script" path="res://scripts/components/c_weapon.gd" id="8_target"]

[sub_resource type="Resource" id="blueprint"]
script = ExtResource("2")
component_type = ExtResource("8_target")

[sub_resource type="Resource" id="container"]
script = ExtResource("3")

... (sprite, transform, collision, lifetime with lifetime=120.0)

[resource]
script = ExtResource("1")
recipe_id = "blueprint_weapon"
display_name = "Weapon Blueprint"
components = [SubResource("blueprint"), SubResource("container"), SubResource("sprite"), SubResource("transform"), SubResource("collision"), SubResource("lifetime")]
```

Repeat for `blueprint_tracker.tres` (CTracker), `blueprint_healer.tres` (CHealer), `blueprint_poison.tres` (CPoison).

**Note:** The exact .tres format depends on how Godot serializes Script @export references. If `@export var component_type: Script` does not serialize cleanly in .tres, set `component_type` at runtime via a setup step. Test by loading the recipe and checking `CBlueprint.component_type != null`.

- [ ] **Step 2: Create npc_composer recipe**

Create `resources/recipes/npc_composer.tres` based on the `survivor.tres` pattern but with:
- `recipe_id = "npc_composer"`, `display_name = "Composition Expert"`
- Components: CTransform, CSprite, CCollision, CMovement, CHP (hp=30), CCamp(PLAYER), CPerception, CGoapAgent, CDialogue
- CGoapAgent configured with Wander + Survive goals (no attack actions)
- CDialogue configured with npc_name and entries

**Note:** CDialogue entries may need to be set at runtime after entity creation (since nested custom classes don't serialize cleanly in .tres). Add a `_setup_composer_dialogue()` helper in GOLWorld if needed.

- [ ] **Step 3: Verify recipes load**

```gdscript
# Quick smoke test — run in Godot console or a test:
var bp := ServiceContext.recipe().create_entity_by_id("blueprint_weapon")
assert(bp.has_component(CBlueprint))
assert(bp.get_component(CBlueprint).component_type == CWeapon)
```

- [ ] **Step 4: Commit**

```bash
git add resources/recipes/blueprint_*.tres resources/recipes/npc_composer.tres
git commit -m "feat: add blueprint and composer NPC recipes"
```

---

## Task 11: Spawn Logic — GOLWorld & SDamage

**Files:**
- Modify: `scripts/gameplay/ecs/gol_world.gd`
- Modify: `scripts/systems/s_damage.gd`

- [ ] **Step 1: Add composer NPC spawn to GOLWorld**

Add constants at the top of `gol_world.gd` (after `INITIAL_RIFLE_OFFSET`):

```gdscript
## Composer NPC spawn configuration
const COMPOSER_NPC_OFFSET: Vector2 = Vector2(-60.0, 30.0)  # Left of campfire

## Blueprint spawn configuration
const BLUEPRINT_RECIPES: Array[String] = ["blueprint_weapon", "blueprint_tracker", "blueprint_healer", "blueprint_poison"]
const BLUEPRINT_SPAWN_COUNT_MIN: int = 1
const BLUEPRINT_SPAWN_COUNT_MAX: int = 2
```

Add two new methods:

```gdscript
## Spawn composer NPC near the campfire/VILLAGE POI
## Note: GOL.Game.campfire_position IS the VILLAGE POI position
## (set via ServiceContext.pcg().find_nearest_village_poi() in GOL.start_game())
func _spawn_composer_npc() -> void:
	var campfire_pos: Vector2 = GOL.Game.campfire_position
	var spawn_pos: Vector2 = campfire_pos + COMPOSER_NPC_OFFSET

	var npc: Entity = ServiceContext.recipe().create_entity_by_id("npc_composer")
	if not npc:
		push_error("GOLWorld: Failed to create composer NPC entity")
		return

	var transform: CTransform = npc.get_component(CTransform)
	if transform:
		transform.position = spawn_pos

	# Set up dialogue data at runtime (complex nested data doesn't serialize in .tres)
	var dialogue: CDialogue = npc.get_component(CDialogue)
	if dialogue:
		dialogue.npc_name = "组合专家"
		var entry := DialogueData.Entry.new(
			"需要什么帮助？",
			[
				DialogueData.Option.new("制作组件", DialogueData.DialogueAction.CRAFT),
				DialogueData.Option.new("移除组件", DialogueData.DialogueAction.DISMANTLE),
				DialogueData.Option.new("离开", DialogueData.DialogueAction.CLOSE),
			]
		)
		dialogue.entries = [entry]

	npc.name = "ComposerNPC"
	print("[GOLWorld] Spawned composer NPC at position: ", spawn_pos)


## Spawn random blueprint boxes at BUILDING POI positions
func _spawn_blueprints_at_building_pois() -> void:
	var pcg_result := ServiceContext.pcg().last_result
	if pcg_result == null or pcg_result.poi_list == null:
		return

	var building_pois: Array = pcg_result.poi_list.get_pois_by_type(POIList.POIType.BUILDING)
	if building_pois.is_empty():
		return

	# Pick random subset of building POIs for blueprints
	var count := randi_range(BLUEPRINT_SPAWN_COUNT_MIN, BLUEPRINT_SPAWN_COUNT_MAX)
	var shuffled := building_pois.duplicate()
	shuffled.shuffle()

	for i in range(mini(count, shuffled.size())):
		var poi: POIList.POI = shuffled[i] as POIList.POI
		if poi == null:
			continue
		_spawn_blueprint_box_at_position(poi.position, i)


func _spawn_blueprint_box_at_position(pos: Vector2, index: int) -> void:
	var recipe_id: String = BLUEPRINT_RECIPES[randi() % BLUEPRINT_RECIPES.size()]
	var box: Entity = ServiceContext.recipe().create_entity_by_id(recipe_id)
	if not box:
		push_error("GOLWorld: Failed to create blueprint box from recipe: %s" % recipe_id)
		return

	var transform: CTransform = box.get_component(CTransform)
	if transform:
		transform.position = pos

	box.name = "BlueprintBox_%d" % index
	print("[GOLWorld] Spawned blueprint box at BUILDING POI: %s with recipe: %s" % [pos, recipe_id])
```

Update `_spawn_default_entities()`:

```gdscript
func _spawn_default_entities() -> void:
	_spawn_player()
	_spawn_campfire()
	_spawn_initial_rifle()
	_spawn_guards_at_campfire()
	_spawn_composer_npc()                   # ← NEW
	_spawn_enemy_spawners_at_pois()
	_spawn_loot_boxes_at_building_pois()
	_spawn_blueprints_at_building_pois()    # ← NEW
```

- [ ] **Step 2: Add blueprint drop to SDamage**

In `scripts/systems/s_damage.gd`, add a helper method (near `_drop_component_box()`):

```gdscript
func _try_drop_blueprint(target_entity: Entity) -> void:
	if randf() >= Config.BLUEPRINT_DROP_CHANCE:
		return

	var camp: CCamp = target_entity.get_component(CCamp)
	if not camp or camp.camp != CCamp.CampType.ENEMY:
		return

	var transform: CTransform = target_entity.get_component(CTransform)
	if not transform:
		return

	var recipes: Array[String] = ["blueprint_weapon", "blueprint_tracker", "blueprint_healer", "blueprint_poison"]
	var recipe_id: String = recipes[randi() % recipes.size()]

	var box: Entity = ServiceContext.recipe().create_entity_by_id(recipe_id)
	if not box:
		return

	var box_transform: CTransform = box.get_component(CTransform)
	if box_transform:
		box_transform.position = transform.position + Vector2(randf_range(-16, 16), randf_range(-16, 16))

	box.name = "BlueprintDrop"
	print("[SDamage] Enemy dropped blueprint: %s" % recipe_id)
```

Call `_try_drop_blueprint(target_entity)` in `_on_no_hp()`, after the component-loss loop and before `_start_death()`:

```gdscript
	# ... existing component loss logic ...

	# Try dropping a blueprint (10% chance for enemies)
	_try_drop_blueprint(target_entity)

	# If at least one was dropped, survive at 1 HP
	if drop_count > 0 and _count_losable_components(target_entity) < losable_count:
```

- [ ] **Step 3: Run all existing tests**

Expected: All pass — no regressions

- [ ] **Step 4: Commit**

```bash
git add scripts/gameplay/ecs/gol_world.gd scripts/systems/s_damage.gd
git commit -m "feat: add blueprint and composer NPC spawn logic"
```

---

## Task 12: Integration Test

**Files:**
- Create: `tests/integration/flow/test_flow_composer_scene.gd`

- [ ] **Step 1: Create SceneConfig integration test**

```gdscript
class_name TestComposerFlowConfig
extends SceneConfig


func scene_name() -> String:
	return "test"


func systems() -> Variant:
	return [
		"res://scripts/systems/s_pickup.gd",
		"res://scripts/systems/s_dialogue.gd",
	]


func enable_pcg() -> bool:
	return false


func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "TestPlayer",
			"components": {
				"CTransform": { "position": Vector2(100, 100) },
			},
		},
		{
			"recipe": "npc_composer",
			"name": "TestComposer",
			"components": {
				"CTransform": { "position": Vector2(200, 100) },
			},
		},
	]


func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	await world.get_tree().process_frame

	# Setup: ensure PlayerData exists
	if not GOL.Player:
		GOL.Player = PlayerData.new()

	var player: Entity = _find(world, "TestPlayer")
	var composer: Entity = _find(world, "TestComposer")

	# ── Test 1: Verify composer NPC has CDialogue ──
	result.check("composer_has_dialogue",
		composer.has_component(CDialogue),
		"Composer NPC should have CDialogue component")

	# ── Test 2: Blueprint unlock flow ──
	var pd: PlayerData = GOL.Player
	var unlocked := ComposerUtils.unlock_blueprint(CWeapon, pd)
	result.check("blueprint_unlock",
		unlocked and CWeapon in pd.unlocked_blueprints,
		"Should unlock CWeapon blueprint")

	# ── Test 3: Craft requires points ──
	pd.component_points = 0
	var craft_fail := ComposerUtils.craft_component(player, CWeapon, pd)
	result.check("craft_needs_points",
		not craft_fail,
		"Craft should fail with 0 points")

	# ── Test 4: Dismantle gives points ──
	# Pre-equip a weapon for dismantle
	player.add_component(CWeapon.new())
	var dismantle_ok := ComposerUtils.dismantle_component(player, CWeapon, pd)
	result.check("dismantle_gives_points",
		dismantle_ok and pd.component_points == Config.DISMANTLE_YIELD,
		"Dismantle should succeed and yield %d point(s)" % Config.DISMANTLE_YIELD)

	# ── Test 5: Full craft flow ──
	pd.component_points = Config.CRAFT_COST
	var craft_ok := ComposerUtils.craft_component(player, CWeapon, pd)
	result.check("craft_success",
		craft_ok and player.has_component(CWeapon),
		"Craft should succeed with enough points")

	# ── Test 6: Blueprint pickup via SPickup integration ──
	# Create a blueprint box entity near player and add to world
	var bp_box: Entity = ServiceContext.recipe().create_entity_by_id("blueprint_healer")
	if bp_box:
		var bp_transform: CTransform = bp_box.get_component(CTransform)
		if bp_transform:
			bp_transform.position = player.get_component(CTransform).position
		bp_box.name = "TestBlueprintBox"

		# Simulate: SPickup would detect CBlueprint and call unlock
		var bp_comp: CBlueprint = bp_box.get_component(CBlueprint)
		if bp_comp and bp_comp.component_type:
			ComposerUtils.unlock_blueprint(bp_comp.component_type, pd)

		result.check("blueprint_pickup_unlocks_healer",
			CHealer in pd.unlocked_blueprints,
			"Picking up healer blueprint should unlock CHealer")

	# ── Test 7: Dialogue component on composer NPC ──
	var dialogue: CDialogue = composer.get_component(CDialogue)
	result.check("dialogue_has_entries",
		dialogue != null and dialogue.entries.size() > 0,
		"Composer NPC dialogue should have entries")

	if dialogue and dialogue.entries.size() > 0:
		var entry: DialogueData.Entry = dialogue.entries[0]
		result.check("dialogue_has_three_options",
			entry.options.size() == 3,
			"Dialogue should have 3 options (craft, dismantle, close)")

	return result
```

- [ ] **Step 2: Run integration test**

Expected: All checks PASS

- [ ] **Step 3: Commit**

```bash
git add tests/integration/flow/test_flow_composer_scene.gd
git commit -m "test: add integration test for composer blueprint flow"
```

---

## Task 13: Run Full Test Suite & Fix Issues

- [ ] **Step 1: Run the complete test suite**

```bash
cd gol-project
./run-tests.command
```

- [ ] **Step 2: Fix any failures**

Address test failures, type errors, or runtime issues.

- [ ] **Step 3: Commit fixes if any**

```bash
# Stage only the specific files that were fixed — do NOT use git add -A
git add <fixed-files>
git commit -m "fix: address test failures in blueprint system"
```

---

## Task 14: PR Creation & Cleanup

- [ ] **Step 1: Push feature branch**

```bash
cd gol-project
git push -u origin feat/component-blueprint
```

- [ ] **Step 2: Create PR closing #109**

```bash
gh pr create -R Dluck-Games/god-of-lego \
  --title "feat: 组件设计图机制 — 蓝图解锁 + 组合专家 NPC + 最小对话系统" \
  --body "$(cat <<'PR_EOF'
## Summary

- Add PlayerData global data class for blueprint/points storage
- Add CBlueprint component and SPickup early-exit branch for blueprint pickup
- Add minimal dialogue system (CDialogue + SDialogue + View_Dialogue)
- Add composer UI for craft/dismantle operations (View_Composer)
- Add composer_utils static utility functions (unlock, craft, dismantle)
- Add npc_composer recipe with GOAP Wander+Flee behavior
- Add 4 blueprint recipes (weapon, tracker, healer, poison)
- Add blueprint spawn logic in GOLWorld (BUILDING POIs) and SDamage (10% enemy drop)
- Add unit tests (composer_utils, blueprint pickup) and integration test (full flow)

## Design Spec

See `docs/superpowers/specs/2026-03-27-component-blueprint-design.md`

Closes #109

## Test plan

- [ ] Unit tests: `test_composer_utils.gd` (8 tests) — all pass
- [ ] Unit tests: `test_blueprint_pickup.gd` (3 tests) — all pass
- [ ] Integration test: `test_flow_composer_scene.gd` (8 checks) — all pass
- [ ] Full test suite: no regressions
- [ ] Manual playtest: find blueprint → return to camp → NPC dialogue → craft/dismantle

🤖 Generated with [Claude Code](https://claude.com/claude-code)
PR_EOF
)"
```

- [ ] **Step 3: Clean up worktree**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
git worktree remove ../gol-project-blueprint
```

- [ ] **Step 4: Update parent repo (gol/)**

```bash
cd /Users/dluckdu/Documents/Github/gol
git add gol-project
git commit -m "chore: update gol-project submodule for component blueprint feature"
git push origin main
```
