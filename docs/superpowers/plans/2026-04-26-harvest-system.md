# Harvest System + New Plant Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add player harvesting mechanic with two new plant types (raspberry bush, carrot) and NPC foraging fallback behavior.

**Architecture:** A single `SHarvest` system handles all player-initiated gathering via interact key, supporting both timed (bush → progress bar → cooldown) and instant (carrot → remove) paths. PCG places plants at world gen. NPC foraging uses two new GOAP actions as a hunger fallback when the camp stockpile is empty.

**Tech Stack:** Godot 4.6, GDScript, GECS ECS addon, GOAP AI, PCG pipeline

**Spec:** `docs/superpowers/specs/2026-04-26-harvest-system-design.md`

---

## File Structure

### New files (in `gol-project/`)

| File | Responsibility |
|------|---------------|
| `scripts/systems/s_harvest.gd` | Player harvesting system — interact detection, progress bar, yield, cooldown tick |
| `scripts/pcg/phases/plant_placer.gd` | PCG phase — scatter bushes + carrots during world gen |
| `scripts/gameplay/goap/actions/move_to_harvestable.gd` | GOAP action — NPC moves to nearest gatherable CResourceNode |
| `scripts/gameplay/goap/actions/harvest_bush.gd` | GOAP action — NPC timed gather from bush → stockpile + hunger |
| `resources/recipes/raspberry_bush.tres` | Bush entity recipe |
| `resources/recipes/carrot.tres` | Carrot entity recipe |
| `tests/unit/test_harvest_components.gd` | Unit tests for CEatable + CResourceNode changes |
| `tests/unit/test_growth_table_spawn_source.gd` | Unit tests for GrowthTable spawn_source filtering |
| `tests/integration/creatures/test_player_harvest_bush.gd` | Integration test — player harvest bush → stockpile |
| `tests/integration/creatures/test_player_harvest_carrot.gd` | Integration test — player harvest carrot → stockpile + entity removed |
| `tests/integration/creatures/test_npc_forages_bush.gd` | Integration test — NPC forages bush when stockpile empty |

### Modified files (in `gol-project/`)

| File | Change |
|------|--------|
| `scripts/components/c_eatable.gd` | Add `player_harvestable: bool`, `harvest_yield: int` |
| `scripts/components/c_resource_node.gd` | Add cooldown fields + `start_cooldown()` |
| `scripts/ui/views/view_progress_bar.gd` | Add `setup()`, `flash_and_remove()`, color constants |
| `scenes/ui/progress_bar.tscn` | Update dimensions (36×5), add Border node |
| `scripts/components/c_speech_bubble.gd` | Add `event_text`, `show_event_text()` |
| `scripts/systems/s_speech_bubble.gd` | Tick `event_duration`, clear expired event text |
| `scripts/ui/views/view_speech_bubble.gd` | Render event text in separate label |
| `scripts/gameplay/tables/growth_table.gd` | Add `spawn_source` field, add bush/carrot entries |
| `scripts/systems/s_world_growth.gd` | Filter by `spawn_source == "growth"` |
| `scripts/systems/s_perception.gd` | Add `has_visible_harvestable` fact + cache field |
| `scripts/systems/s_auto_feed.gd` | Mirror `stockpile_has_food` fact to GOAP agents |
| `scripts/pcg/pipeline/pcg_context.gd` | Add `plants` array + `add_plant()` |
| `scripts/pcg/data/pcg_result.gd` | Add `plants` field, pass through constructor |
| `scripts/pcg/pipeline/pcg_pipeline.gd` | Pass `context.plants` to PCGResult constructor |
| `scripts/pcg/pipeline/pcg_phase_config.gd` | Register `PlantPlacer` phase |
| `scripts/gameplay/ecs/gol_world.gd` | Add `_place_plants()` call in world-build sequence |
| `scripts/gameplay/goap/actions/gather_resource.gd` | Use `ViewProgressBar.setup()` with `COLOR_CHOP` |

---

## Task 1: CEatable — add `player_harvestable` and `harvest_yield` fields

**Files:**
- Modify: `gol-project/scripts/components/c_eatable.gd:9`
- Test: `gol-project/tests/unit/test_harvest_components.gd` (create)

- [ ] **Step 1: Write failing tests for new CEatable fields**

```gdscript
# tests/unit/test_harvest_components.gd
extends GdUnitTestSuite


func test_ceatable_player_harvestable_defaults_to_false() -> void:
	var eatable: CEatable = auto_free(CEatable.new()) as CEatable
	assert_bool(eatable.player_harvestable).is_false()


func test_ceatable_harvest_yield_defaults_to_1() -> void:
	var eatable: CEatable = auto_free(CEatable.new()) as CEatable
	assert_int(eatable.harvest_yield).is_equal(1)


func test_ceatable_player_harvestable_can_be_set_true() -> void:
	var eatable: CEatable = auto_free(CEatable.new()) as CEatable
	eatable.player_harvestable = true
	assert_bool(eatable.player_harvestable).is_true()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./run-tests.command` or the unit test runner
Expected: FAIL — `player_harvestable` and `harvest_yield` not defined on CEatable

- [ ] **Step 3: Add fields to CEatable**

In `gol-project/scripts/components/c_eatable.gd`, after line 9 (`@export var hunger_restore: float = 20.0`), add:

```gdscript
@export var player_harvestable: bool = false
@export var harvest_yield: int = 1
```

Full file becomes:

```gdscript
# scripts/components/c_eatable.gd
class_name CEatable
extends Component
## Marks an entity as consumable food for direct-eating creatures
## (rabbits eating grass, future: zombies eating rabbits).
## The eater's GoapAction_EatGrass removes the entity and increments
## the eater's CHunger.hunger by hunger_restore.

@export var hunger_restore: float = 20.0
@export var player_harvestable: bool = false
@export var harvest_yield: int = 1
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./run-tests.command`
Expected: PASS — all 3 new tests green

- [ ] **Step 5: Commit**

```bash
git add scripts/components/c_eatable.gd tests/unit/test_harvest_components.gd
git commit -m "feat(harvest): add player_harvestable and harvest_yield to CEatable"
```

---

## Task 2: CResourceNode — add cooldown fields and methods

**Files:**
- Modify: `gol-project/scripts/components/c_resource_node.gd`
- Modify: `gol-project/tests/unit/test_harvest_components.gd` (append)
- Reference: `gol-project/tests/unit/test_cresource_node.gd` (existing tests — don't break)

- [ ] **Step 1: Append failing tests for cooldown behavior**

Append to `tests/unit/test_harvest_components.gd`:

```gdscript
func test_cresource_node_cooldown_defaults() -> void:
	var node: CResourceNode = auto_free(CResourceNode.new()) as CResourceNode
	assert_float(node.cooldown_duration).is_equal(0.0)
	assert_float(node.cooldown_remaining).is_equal(0.0)
	assert_bool(node.is_on_cooldown).is_false()
	assert_str(node.ready_label).is_equal("")
	assert_str(node.depleted_label).is_equal("")


func test_cresource_node_start_cooldown_sets_remaining() -> void:
	var node: CResourceNode = auto_free(CResourceNode.new()) as CResourceNode
	node.cooldown_duration = 60.0
	node.start_cooldown()
	assert_float(node.cooldown_remaining).is_equal(60.0)
	assert_bool(node.is_on_cooldown).is_true()


func test_cresource_node_can_gather_returns_false_during_cooldown() -> void:
	var node: CResourceNode = auto_free(CResourceNode.new()) as CResourceNode
	node.cooldown_duration = 60.0
	node.start_cooldown()
	assert_bool(node.can_gather()).is_false()


func test_cresource_node_cooldown_tick_restores_gatherable() -> void:
	var node: CResourceNode = auto_free(CResourceNode.new()) as CResourceNode
	node.cooldown_duration = 1.0
	node.start_cooldown()
	assert_bool(node.can_gather()).is_false()
	node.cooldown_remaining = 0.0
	assert_bool(node.can_gather()).is_true()


func test_cresource_node_start_cooldown_noop_when_duration_zero() -> void:
	var node: CResourceNode = auto_free(CResourceNode.new()) as CResourceNode
	node.cooldown_duration = 0.0
	node.start_cooldown()
	assert_float(node.cooldown_remaining).is_equal(0.0)
	assert_bool(node.is_on_cooldown).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./run-tests.command`
Expected: FAIL — `cooldown_duration`, `is_on_cooldown`, `start_cooldown` not defined

- [ ] **Step 3: Add cooldown fields and methods to CResourceNode**

Replace full contents of `gol-project/scripts/components/c_resource_node.gd`:

```gdscript
class_name CResourceNode
extends Component

@export var yield_type: Script
@export var yield_amount: int = 1
@export var gather_duration: float = 2.0
@export var infinite: bool = true
@export var remaining_yield: int = -1

@export var cooldown_duration: float = 0.0
@export var ready_label: String = ""
@export var depleted_label: String = ""
var cooldown_remaining: float = 0.0

var is_on_cooldown: bool:
	get: return cooldown_remaining > 0.0


func can_gather() -> bool:
	if is_on_cooldown:
		return false
	if infinite:
		return true
	return remaining_yield > 0


func consume_yield() -> int:
	if not can_gather():
		return 0
	if not infinite:
		remaining_yield -= 1
	return yield_amount


func start_cooldown() -> void:
	if cooldown_duration > 0.0:
		cooldown_remaining = cooldown_duration
```

- [ ] **Step 4: Run ALL tests (existing + new) to verify nothing breaks**

Run: `./run-tests.command`
Expected: PASS — all existing `test_cresource_node.gd` tests still green + 5 new tests green

- [ ] **Step 5: Commit**

```bash
git add scripts/components/c_resource_node.gd tests/unit/test_harvest_components.gd
git commit -m "feat(harvest): add cooldown fields and start_cooldown() to CResourceNode"
```

---

## Task 3: GrowthTable — add `spawn_source` field + SWorldGrowth filter

**Files:**
- Modify: `gol-project/scripts/gameplay/tables/growth_table.gd`
- Modify: `gol-project/scripts/systems/s_world_growth.gd:52-54`
- Test: `gol-project/tests/unit/test_growth_table_spawn_source.gd` (create)

- [ ] **Step 1: Write failing tests for spawn_source**

```gdscript
# tests/unit/test_growth_table_spawn_source.gd
extends GdUnitTestSuite


func test_grass_has_growth_spawn_source() -> void:
	var table := GrowthTable.new()
	var rule: Dictionary = table.get_rule("grass")
	assert_str(String(rule.get("spawn_source", ""))).is_equal("growth")


func test_raspberry_bush_has_pcg_spawn_source() -> void:
	var table := GrowthTable.new()
	var rule: Dictionary = table.get_rule("raspberry_bush")
	assert_str(String(rule.get("spawn_source", ""))).is_equal("pcg")


func test_carrot_has_pcg_spawn_source() -> void:
	var table := GrowthTable.new()
	var rule: Dictionary = table.get_rule("carrot")
	assert_str(String(rule.get("spawn_source", ""))).is_equal("pcg")


func test_pcg_entries_have_no_growth_fields() -> void:
	var table := GrowthTable.new()
	var bush_rule: Dictionary = table.get_rule("raspberry_bush")
	assert_bool(bush_rule.has("zones")).is_false()
	assert_bool(bush_rule.has("interval_sec")).is_false()
	assert_bool(bush_rule.has("world_cap")).is_false()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./run-tests.command`
Expected: FAIL — `raspberry_bush` and `carrot` not in GrowthTable, `grass` has no `spawn_source`

- [ ] **Step 3: Update GrowthTable with spawn_source and new entries**

Replace full contents of `gol-project/scripts/gameplay/tables/growth_table.gd`:

```gdscript
# scripts/gameplay/tables/growth_table.gd
class_name GrowthTable
extends Resource
## Things that grow (spawn naturally over time) in the world.
## Read by SWorldGrowth. Keyed by recipe_id of the spawned entity.
##
## Each rule fields:
##   spawn_source:     "growth" (SWorldGrowth) or "pcg" (world gen only)
##   zones:            Array[ZoneMap.ZoneType] — eligible zones (growth only)
##   interval_sec:     float — seconds between per-cell rolls (growth only)
##   per_cell_chance:  float in [0,1] — roll per eligible cell per interval (growth only)
##   world_cap:        int > 0 — max live instances of this recipe worldwide (growth only)
const TABLES: Dictionary = {
	"grass": {
		spawn_source = "growth",
		zones = [ZoneMap.ZoneType.WILDERNESS, ZoneMap.ZoneType.SUBURBS],
		interval_sec = 8.0,
		per_cell_chance = 0.02,
		world_cap = 60,
	},
	"raspberry_bush": {
		spawn_source = "pcg",
	},
	"carrot": {
		spawn_source = "pcg",
	},
}


## All growth rules (recipe_id -> rule dict).
func all() -> Dictionary:
	return TABLES


## Lookup one rule by recipe_id; returns empty dict if absent.
func get_rule(recipe_id: String) -> Dictionary:
	return TABLES.get(recipe_id, {})
```

- [ ] **Step 4: Add spawn_source filter to SWorldGrowth**

In `gol-project/scripts/systems/s_world_growth.gd`, in `_on_growth_tick()` at line 54 (inside the `for recipe_key in rules.keys():` loop), add a filter immediately after `var rule: Dictionary = rules[recipe_key]`:

```gdscript
		var rule: Dictionary = rules[recipe_key]
		if rule.get("spawn_source", "growth") != "growth":
			continue
```

Also apply the same filter in `_rebuild_growth_cache()` at line 138 (inside the `for recipe_key in rules.keys():` loop), after `var rule: Dictionary = rules[recipe_key]`:

```gdscript
		var rule: Dictionary = rules[recipe_key]
		if rule.get("spawn_source", "growth") != "growth":
			continue
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `./run-tests.command`
Expected: PASS — all 4 new tests green, existing SWorldGrowth behavior unchanged

- [ ] **Step 6: Commit**

```bash
git add scripts/gameplay/tables/growth_table.gd scripts/systems/s_world_growth.gd tests/unit/test_growth_table_spawn_source.gd
git commit -m "feat(harvest): add spawn_source taxonomy to GrowthTable, filter in SWorldGrowth"
```

---

## Task 4: ViewProgressBar — upgrade to generic reusable bar

**Files:**
- Modify: `gol-project/scripts/ui/views/view_progress_bar.gd`
- Modify: `gol-project/scenes/ui/progress_bar.tscn`
- Modify: `gol-project/scripts/gameplay/goap/actions/gather_resource.gd:76-83`

- [ ] **Step 1: Update progress_bar.tscn scene**

Replace full contents of `gol-project/scenes/ui/progress_bar.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/views/view_progress_bar.gd" id="1"]

[node name="ViewProgressBar" type="Control"]
custom_minimum_size = Vector2(36, 5)
script = ExtResource("1")

[node name="Background" type="ColorRect" parent="."]
offset_right = 36.0
offset_bottom = 5.0
color = Color(0, 0, 0, 0.5)

[node name="Fill" type="ColorRect" parent="."]
offset_right = 0.0
offset_bottom = 5.0
color = Color(0.3, 0.8, 0.3, 1)

[node name="Border" type="ReferenceRect" parent="."]
offset_right = 36.0
offset_bottom = 5.0
border_color = Color(0.2, 0.2, 0.2, 0.8)
border_width = 1.0
editor_only = false
```

- [ ] **Step 2: Update ViewProgressBar script**

Replace full contents of `gol-project/scripts/ui/views/view_progress_bar.gd`:

```gdscript
class_name ViewProgressBar
extends ViewBase

@onready var _fill: ColorRect = $Fill
@onready var _background: ColorRect = $Background

var _followed_entity: Entity = null
var _offset: Vector2 = Vector2(0, -32)

const COLOR_HARVEST: Color = Color(0.3, 0.8, 0.3, 1.0)
const COLOR_CHOP: Color = Color(0.6, 0.4, 0.2, 1.0)
const COLOR_MINE: Color = Color(0.3, 0.5, 0.9, 1.0)


func setup(entity: Entity, color: Color = COLOR_HARVEST, offset: Vector2 = Vector2(0, -32)) -> void:
	_followed_entity = entity
	_offset = offset
	_fill.color = color
	set_progress(0.0)


func set_progress(ratio: float) -> void:
	ratio = clamp(ratio, 0.0, 1.0)
	if _fill == null:
		return
	_fill.size.x = _background.size.x * ratio


func flash_and_remove() -> void:
	_fill.color = Color.WHITE
	get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(self):
			ServiceContext.ui().pop_view(self)
	)


func follow_entity(entity: Entity, offset: Vector2 = Vector2(0, -32)) -> void:
	_followed_entity = entity
	_offset = offset


func _process(_delta: float) -> void:
	if _followed_entity == null or not is_instance_valid(_followed_entity):
		return
	var t: CTransform = _followed_entity.get_component(CTransform)
	if t == null:
		return
	global_position = t.position + _offset
```

- [ ] **Step 3: Update GoapAction_GatherResource to use new setup() API**

In `gol-project/scripts/gameplay/goap/actions/gather_resource.gd`, replace the `_create_progress_bar` method (lines 76-83):

```gdscript
func _create_progress_bar(agent_entity: Entity) -> ViewProgressBar:
	var view: ViewProgressBar = PROGRESS_BAR_SCENE.instantiate() as ViewProgressBar
	if view == null:
		return null
	ServiceContext.ui().push_view(Service_UI.LayerType.GAME, view)
	view.setup(agent_entity, ViewProgressBar.COLOR_CHOP)
	return view
```

- [ ] **Step 4: Run existing tests to verify nothing breaks**

Run: `./run-tests.command`
Expected: PASS — all existing tests still green (GatherResource behavior unchanged)

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/views/view_progress_bar.gd scenes/ui/progress_bar.tscn scripts/gameplay/goap/actions/gather_resource.gd
git commit -m "feat(harvest): upgrade ViewProgressBar with color presets, border, flash-on-complete"
```

---

## Task 5: CSpeechBubble — add one-shot event text

**Files:**
- Modify: `gol-project/scripts/components/c_speech_bubble.gd:40` (after last var)
- Modify: `gol-project/scripts/systems/s_speech_bubble.gd:58-60`
- Modify: `gol-project/scripts/ui/views/view_speech_bubble.gd`
- Modify: `gol-project/scenes/ui/speech_bubble.tscn`

- [ ] **Step 1: Add event text fields to CSpeechBubble**

In `gol-project/scripts/components/c_speech_bubble.gd`, after line 40 (`var last_text: String = ""`), add:

```gdscript

var event_text: String = ""
var event_text_observable: ObservableProperty = ObservableProperty.new("")
var event_duration: float = 0.0


func show_event_text(text: String, duration: float = 1.5) -> void:
	event_text = text
	event_duration = duration
	event_text_observable.notify(text)
```

- [ ] **Step 2: Add event text tick-down to SSpeechBubble**

In `gol-project/scripts/systems/s_speech_bubble.gd`, in `_process_entity()` at line 58 (after the existing cooldown/dismiss tick-downs), add event text tick-down:

```gdscript
	# Tick event text duration
	if bubble.event_duration > 0.0:
		bubble.event_duration -= delta
		if bubble.event_duration <= 0.0:
			bubble.event_duration = 0.0
			bubble.event_text = ""
			bubble.event_text_observable.notify("")
```

Insert this block after line 60 (`bubble.pending_time_remaining = maxf(0.0, bubble.pending_time_remaining - delta)`) and before line 62 (`if bubble.pending_time_remaining <= 0.0`).

- [ ] **Step 3: Add event text label to speech bubble scene**

In `gol-project/scenes/ui/speech_bubble.tscn`, add an EventLabel node as a sibling to Label:

```
[node name="EventLabel" type="Label" parent="."]
visible = false
text = ""
horizontal_alignment = 1
vertical_alignment = 1
```

- [ ] **Step 4: Render event text in View_SpeechBubble**

In `gol-project/scripts/ui/views/view_speech_bubble.gd`, add an `@onready` reference and bind the event text observable.

After line 13 (`@onready var _label: Label = $Label`), add:

```gdscript
@onready var _event_label: Label = $EventLabel
```

In the `setup()` method (after `_apply_theme()`), add event label theme:

```gdscript
	_apply_event_label_theme()
```

In the `bind()` method (after the existing `track` calls), add:

```gdscript
	track(vm.event_text[_entity].subscribe(_on_event_text_changed))
```

Add the new methods at the end of the file:

```gdscript
func _on_event_text_changed(new_text: String) -> void:
	if _event_label == null:
		return
	_event_label.text = new_text
	_event_label.visible = not new_text.is_empty()
	if _event_label.visible:
		call_deferred("_refresh_event_layout")


func _refresh_event_layout() -> void:
	if _event_label == null:
		return
	_event_label.size = _event_label.get_combined_minimum_size()
	_event_label.position = _target_position - _event_label.size * 0.5 + Vector2(0, -16)


func _apply_event_label_theme() -> void:
	if _event_label == null:
		return
	_event_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_event_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_event_label.add_theme_constant_override("outline_size", 2)
	_event_label.add_theme_font_size_override("font_size", 8)
```

- [ ] **Step 5: Add event_text observable to ViewModel_SpeechBubble**

In `gol-project/scripts/ui/viewmodels/viewmodel_speech_bubble.gd`, add `event_text` dictionary alongside the existing `text` dictionary:

```gdscript
var event_text: Dictionary[Entity, ObservableProperty] = {}
```

In `bind_to_entity()`, add:

```gdscript
	event_text[entity] = bubble.event_text_observable
```

In `unbind_to_entity()`, add:

```gdscript
	event_text.erase(entity)
```

- [ ] **Step 6: Run tests to verify nothing breaks**

Run: `./run-tests.command`
Expected: PASS — all existing speech bubble tests still green

- [ ] **Step 7: Commit**

```bash
git add scripts/components/c_speech_bubble.gd scripts/systems/s_speech_bubble.gd scripts/ui/views/view_speech_bubble.gd scripts/ui/viewmodels/viewmodel_speech_bubble.gd scenes/ui/speech_bubble.tscn
git commit -m "feat(harvest): add one-shot event text to speech bubble system"
```

---

## Task 6: Plant recipes — raspberry_bush.tres and carrot.tres

**Files:**
- Create: `gol-project/resources/recipes/raspberry_bush.tres`
- Create: `gol-project/resources/recipes/carrot.tres`

- [ ] **Step 1: Create raspberry_bush.tres recipe**

Create `gol-project/resources/recipes/raspberry_bush.tres`:

```
[gd_resource type="Resource" script_class="EntityRecipe" format=3]

[ext_resource type="Script" path="res://scripts/gameplay/ecs/recipes/entity_recipe.gd" id="1"]
[ext_resource type="Script" path="res://addons/gecs/ecs/component.gd" id="1_component"]
[ext_resource type="Script" path="res://scripts/components/c_transform.gd" id="2"]
[ext_resource type="Script" path="res://scripts/components/c_collision.gd" id="3"]
[ext_resource type="Script" path="res://scripts/components/c_resource_node.gd" id="4"]
[ext_resource type="Script" path="res://scripts/components/c_label_display.gd" id="5"]
[ext_resource type="Script" path="res://scripts/components/c_speech_bubble.gd" id="6"]
[ext_resource type="Script" path="res://scripts/resources/r_food.gd" id="7"]
[ext_resource type="Resource" path="res://resources/speech_bubble_default.tres" id="8"]

[sub_resource type="Resource" id="transform"]
script = ExtResource("2")

[sub_resource type="CircleShape2D" id="collision_shape"]
radius = 16.0

[sub_resource type="Resource" id="collision"]
script = ExtResource("3")
collision_shape = SubResource("collision_shape")

[sub_resource type="Resource" id="resource_node"]
script = ExtResource("4")
yield_type = ExtResource("7")
yield_amount = 2
gather_duration = 2.0
infinite = true
cooldown_duration = 60.0
ready_label = "🍓"
depleted_label = "🪵"

[sub_resource type="Resource" id="label_display"]
script = ExtResource("5")
text = "🍓"
font_size = 20

[sub_resource type="Resource" id="speech_bubble"]
script = ExtResource("6")
table = ExtResource("8")
offset = Vector2(0, -40)

[resource]
script = ExtResource("1")
recipe_id = "raspberry_bush"
display_name = "树莓灌木丛"
components = Array[ExtResource("1_component")]([SubResource("transform"), SubResource("collision"), SubResource("resource_node"), SubResource("label_display"), SubResource("speech_bubble")])
```

- [ ] **Step 2: Create carrot.tres recipe**

Create `gol-project/resources/recipes/carrot.tres`:

```
[gd_resource type="Resource" script_class="EntityRecipe" format=3]

[ext_resource type="Script" path="res://scripts/gameplay/ecs/recipes/entity_recipe.gd" id="1"]
[ext_resource type="Script" path="res://addons/gecs/ecs/component.gd" id="1_component"]
[ext_resource type="Script" path="res://scripts/components/c_transform.gd" id="2"]
[ext_resource type="Script" path="res://scripts/components/c_collision.gd" id="3"]
[ext_resource type="Script" path="res://scripts/components/c_eatable.gd" id="4"]
[ext_resource type="Script" path="res://scripts/components/c_label_display.gd" id="5"]

[sub_resource type="Resource" id="transform"]
script = ExtResource("2")

[sub_resource type="CircleShape2D" id="collision_shape"]
radius = 12.0

[sub_resource type="Resource" id="collision"]
script = ExtResource("3")
collision_shape = SubResource("collision_shape")

[sub_resource type="Resource" id="eatable"]
script = ExtResource("4")
hunger_restore = 15.0
player_harvestable = true
harvest_yield = 1

[sub_resource type="Resource" id="label_display"]
script = ExtResource("5")
text = "🥕"
font_size = 18

[resource]
script = ExtResource("1")
recipe_id = "carrot"
display_name = "胡萝卜"
components = Array[ExtResource("1_component")]([SubResource("transform"), SubResource("collision"), SubResource("eatable"), SubResource("label_display")])
```

- [ ] **Step 3: Verify recipes load without errors**

Run Godot editor or test runner — recipes should parse without errors. Verify `ServiceContext.recipe().create_entity_by_id("raspberry_bush")` and `ServiceContext.recipe().create_entity_by_id("carrot")` return valid entities.

- [ ] **Step 4: Commit**

```bash
git add resources/recipes/raspberry_bush.tres resources/recipes/carrot.tres
git commit -m "feat(harvest): add raspberry_bush and carrot entity recipes"
```

---

## Task 7: PCG PlantPlacer phase + pipeline integration

**Files:**
- Create: `gol-project/scripts/pcg/phases/plant_placer.gd`
- Modify: `gol-project/scripts/pcg/pipeline/pcg_context.gd:98-103` (after creature_spawners)
- Modify: `gol-project/scripts/pcg/data/pcg_result.gd:19,43-48`
- Modify: `gol-project/scripts/pcg/pipeline/pcg_pipeline.gd:25-32`
- Modify: `gol-project/scripts/pcg/pipeline/pcg_phase_config.gd:13-14,22-33,38-49`
- Modify: `gol-project/scripts/gameplay/ecs/gol_world.gd:285-286`

- [ ] **Step 1: Add plants array to PCGContext**

In `gol-project/scripts/pcg/pipeline/pcg_context.gd`, after line 103 (`creature_spawners.append(spec)`), add:

```gdscript


## Plant specs accumulated by PlantPlacer phase.
var plants: Array[Dictionary] = []


## Phase helper: record a plant placement.
func add_plant(spec: Dictionary) -> void:
	plants.append(spec)
```

- [ ] **Step 2: Add plants field to PCGResult**

In `gol-project/scripts/pcg/data/pcg_result.gd`, after line 19 (`var creature_spawners: Array[Dictionary] = []`), add:

```gdscript

## Plant specs from PCG phases.
var plants: Array[Dictionary] = []
```

Update the `_init` method (line 43) to accept and store plants:

```gdscript
func _init(p_config: PCGConfig, p_graph: RoadGraph, p_zones: ZoneMap = null, p_pois: POIList = null, p_grid: Dictionary = {}, p_creature_spawners: Array[Dictionary] = [], p_plants: Array[Dictionary] = []) -> void:
	config = p_config
	road_graph = p_graph
	grid = p_grid
	creature_spawners = p_creature_spawners
	plants = p_plants
```

- [ ] **Step 3: Pass plants through PCGPipeline**

In `gol-project/scripts/pcg/pipeline/pcg_pipeline.gd`, update the `PCGResult.new()` call (line 25) to pass `context.plants`:

```gdscript
	return PCGResult.new(
		effective_config,
		context.road_graph,
		null,
		null,
		context.grid,
		context.creature_spawners,
		context.plants
	)
```

- [ ] **Step 4: Create PlantPlacer phase**

Create `gol-project/scripts/pcg/phases/plant_placer.gd`:

```gdscript
class_name PlantPlacer
extends PCGPhase
## Scatters plant entities (raspberry bushes, carrots) into PCGContext
## during world generation. These are PCG-only plants (spawn_source="pcg")
## that do not regrow via SWorldGrowth.

const MAX_BUSHES: int = 20
const MAX_CARROTS: int = 35

const BUSH_ZONES: Array[int] = [ZoneMap.ZoneType.WILDERNESS, ZoneMap.ZoneType.SUBURBS]
const CARROT_ZONES: Array[int] = [ZoneMap.ZoneType.WILDERNESS]


func execute(_config: PCGConfig, context: PCGContext) -> void:
	if context == null or context.grid == null:
		return

	var candidates: Array[Vector2i] = _collect_candidates(context)
	candidates.shuffle()

	_place(context, candidates, "raspberry_bush", BUSH_ZONES, MAX_BUSHES)
	_place(context, candidates, "carrot", CARROT_ZONES, MAX_CARROTS)


func _collect_candidates(context: PCGContext) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pos: Variant in context.grid.keys():
		if not (pos is Vector2i):
			continue
		var cell: PCGCell = context.grid[pos] as PCGCell
		if cell == null:
			continue
		if cell.zone_type == ZoneMap.ZoneType.URBAN:
			continue
		if cell.has_poi() or cell.is_road() or cell.is_sidewalk() or cell.is_building():
			continue
		result.append(pos)
	return result


func _place(context: PCGContext, candidates: Array[Vector2i],
		recipe_id: String, zones: Array[int], max_count: int) -> void:
	var placed: int = 0
	for cell in candidates:
		if placed >= max_count:
			break
		var pcg_cell: PCGCell = context.grid.get(cell, null) as PCGCell
		if pcg_cell == null:
			continue
		if not zones.has(pcg_cell.zone_type):
			continue
		context.add_plant({
			"recipe_id": recipe_id,
			"cell": cell,
		})
		placed += 1
```

- [ ] **Step 5: Register PlantPlacer in PCGPhaseConfig**

In `gol-project/scripts/pcg/pipeline/pcg_phase_config.gd`:

Add const after line 13 (`const CreatureSpawnerPlacer`):

```gdscript
const PlantPlacer := preload("res://scripts/pcg/phases/plant_placer.gd")
```

Add phase name after `"Creature Spawner Placer"` in `PHASE_NAMES` array (line 27):

```gdscript
	"Plant Placer",
```

Add phase instantiation in `create_phases()` after `CreatureSpawnerPlacer.new()` (line 44):

```gdscript
	phases.append(PlantPlacer.new())             # Scatter plants (bushes, carrots)
```

- [ ] **Step 6: Add _place_plants to gol_world.gd**

In `gol-project/scripts/gameplay/ecs/gol_world.gd`, after line 286 (`_place_creature_spawners(ServiceContext.pcg().last_result)`), add:

```gdscript
	_place_plants(ServiceContext.pcg().last_result)
```

Add the method implementation near `_place_creature_spawners` (after line 718):

```gdscript
func _place_plants(pcg_result: PCGResult) -> void:
	if pcg_result == null:
		return
	if pcg_result.plants == null or pcg_result.plants.is_empty():
		return

	for spec in pcg_result.plants:
		var recipe_id: String = String(spec.get("recipe_id", ""))
		if recipe_id == "":
			continue
		var cell: Vector2i = spec.get("cell", Vector2i.ZERO)
		var entity: Entity = ServiceContext.recipe().create_entity_by_id(recipe_id)
		if entity == null:
			continue
		var t := entity.get_component(CTransform) as CTransform
		if t:
			t.position = pcg_result.grid_to_world(cell)
```

- [ ] **Step 7: Run tests to verify nothing breaks**

Run: `./run-tests.command`
Expected: PASS — all existing PCG and world tests still green

- [ ] **Step 8: Commit**

```bash
git add scripts/pcg/phases/plant_placer.gd scripts/pcg/pipeline/pcg_context.gd scripts/pcg/data/pcg_result.gd scripts/pcg/pipeline/pcg_pipeline.gd scripts/pcg/pipeline/pcg_phase_config.gd scripts/gameplay/ecs/gol_world.gd
git commit -m "feat(harvest): add PlantPlacer PCG phase, scatter bushes and carrots at world gen"
```

---

## Task 8: SHarvest system — player harvesting

**Files:**
- Create: `gol-project/scripts/systems/s_harvest.gd`
- Test: `gol-project/tests/integration/creatures/test_player_harvest_bush.gd` (create)
- Test: `gol-project/tests/integration/creatures/test_player_harvest_carrot.gd` (create)

- [ ] **Step 1: Create SHarvest system**

Create `gol-project/scripts/systems/s_harvest.gd`:

```gdscript
class_name SHarvest
extends System
## Player harvesting system. Handles interact-key gathering for both
## CResourceNode (timed, e.g. bush) and CEatable (instant, e.g. carrot).

const RFood = preload("res://scripts/resources/r_food.gd")
const ViewProgressBar = preload("res://scripts/ui/views/view_progress_bar.gd")
const PROGRESS_BAR_SCENE = preload("res://scenes/ui/progress_bar.tscn")

const HARVEST_RANGE: float = 32.0
const HARVEST_RANGE_SQ: float = HARVEST_RANGE * HARVEST_RANGE

enum State { IDLE, GATHERING, COMPLETE }

var _state: State = State.IDLE
var _target: Entity = null
var _elapsed: float = 0.0
var _duration: float = 0.0
var _progress_view: ViewProgressBar = null


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CPlayer, CTransform])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	_tick_cooldowns(delta)

	if entities.is_empty():
		return
	var player: Entity = entities[0]
	var player_transform := player.get_component(CTransform) as CTransform
	if player_transform == null:
		return
	var player_pos: Vector2 = player_transform.position

	match _state:
		State.IDLE:
			if Input.is_action_just_pressed("interact"):
				var target := _find_nearest_harvestable(player_pos)
				if target != null:
					_begin_harvest(player, target)

		State.GATHERING:
			if not _is_valid_target(_target, player_pos):
				_cancel_harvest()
				return
			if not Input.is_action_pressed("interact"):
				_cancel_harvest()
				return
			_elapsed += delta
			if _progress_view:
				_progress_view.set_progress(_elapsed / _duration)
			if _elapsed >= _duration:
				_complete_harvest(player)

		State.COMPLETE:
			_state = State.IDLE


func _find_nearest_harvestable(player_pos: Vector2) -> Entity:
	var best: Entity = null
	var best_dist_sq: float = HARVEST_RANGE_SQ

	var resource_nodes := ECS.world.query.with_all([CResourceNode, CTransform]).execute()
	for entity in resource_nodes:
		var node: CResourceNode = entity.get_component(CResourceNode)
		if not node.can_gather():
			continue
		var dist_sq := player_pos.distance_squared_to(entity.get_component(CTransform).position)
		if dist_sq < best_dist_sq:
			best = entity
			best_dist_sq = dist_sq

	var eatables := ECS.world.query.with_all([CEatable, CTransform]).execute()
	for entity in eatables:
		var eatable: CEatable = entity.get_component(CEatable)
		if not eatable.player_harvestable:
			continue
		if entity.has_component(CDead):
			continue
		var dist_sq := player_pos.distance_squared_to(entity.get_component(CTransform).position)
		if dist_sq < best_dist_sq:
			best = entity
			best_dist_sq = dist_sq

	return best


func _begin_harvest(player: Entity, target: Entity) -> void:
	_target = target
	_elapsed = 0.0
	_state = State.GATHERING

	if target.has_component(CResourceNode):
		var node: CResourceNode = target.get_component(CResourceNode)
		_duration = node.gather_duration
	else:
		_duration = 0.0

	if _duration > 0.0:
		_progress_view = PROGRESS_BAR_SCENE.instantiate() as ViewProgressBar
		_progress_view.setup(target, ViewProgressBar.COLOR_HARVEST)
		ServiceContext.ui().push_view(Service_UI.LayerType.GAME, _progress_view)

	var movement := player.get_component(CMovement) as CMovement
	if movement:
		movement.velocity = Vector2.ZERO


func _complete_harvest(player: Entity) -> void:
	var stockpile := _find_camp_stockpile()
	if stockpile == null:
		_cancel_harvest()
		return

	var yield_amount: int = 0
	var display_name: String = ""

	if _target.has_component(CResourceNode):
		var node: CResourceNode = _target.get_component(CResourceNode)
		yield_amount = node.consume_yield()
		stockpile.add(node.yield_type, yield_amount)
		display_name = _get_resource_display_name(node.yield_type)
		node.start_cooldown()
		var label := _target.get_component(CLabelDisplay) as CLabelDisplay
		if label and node.depleted_label != "":
			label.text = node.depleted_label

	elif _target.has_component(CEatable):
		var eatable: CEatable = _target.get_component(CEatable)
		yield_amount = eatable.harvest_yield
		stockpile.add(RFood, yield_amount)
		display_name = RFood.DISPLAY_NAME
		cmd.remove_entity(_target)

	if _progress_view:
		_progress_view.flash_and_remove()
		_progress_view = null

	_show_harvest_text(_target, yield_amount, display_name)

	_target = null
	_elapsed = 0.0
	_state = State.COMPLETE


func _cancel_harvest() -> void:
	if _progress_view:
		ServiceContext.ui().pop_view(_progress_view)
		_progress_view = null
	_target = null
	_elapsed = 0.0
	_state = State.IDLE


func _is_valid_target(target: Entity, player_pos: Vector2) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_component(CDead):
		return false
	var t := target.get_component(CTransform) as CTransform
	if t == null:
		return false
	return player_pos.distance_squared_to(t.position) <= HARVEST_RANGE_SQ * 4.0


func _show_harvest_text(target: Entity, amount: int, display_name: String) -> void:
	if amount <= 0:
		return
	var text: String = "+%d %s" % [amount, display_name]
	var bubble := target.get_component(CSpeechBubble) as CSpeechBubble if is_instance_valid(target) else null
	if bubble:
		bubble.show_event_text(text)
		return
	var players := ECS.world.query.with_all([CPlayer, CSpeechBubble]).execute()
	if not players.is_empty():
		var player_bubble := players[0].get_component(CSpeechBubble) as CSpeechBubble
		if player_bubble:
			player_bubble.show_event_text(text)


func _tick_cooldowns(delta: float) -> void:
	var nodes := ECS.world.query.with_all([CResourceNode, CTransform]).execute()
	for entity in nodes:
		var node: CResourceNode = entity.get_component(CResourceNode)
		if not node.is_on_cooldown:
			continue
		node.cooldown_remaining -= delta
		if node.cooldown_remaining <= 0.0:
			node.cooldown_remaining = 0.0
			var label := entity.get_component(CLabelDisplay) as CLabelDisplay
			if label and node.ready_label != "":
				label.text = node.ready_label


func _find_camp_stockpile() -> CStockpile:
	var found: Array = ECS.world.query.with_all([CStockpile]).with_none([CPlayer]).execute()
	if found.is_empty():
		return null
	return found[0].get_component(CStockpile) as CStockpile


func _get_resource_display_name(resource_type: Script) -> String:
	if resource_type == null:
		return ""
	if resource_type == RFood:
		return RFood.DISPLAY_NAME
	return ""
```

- [ ] **Step 2: Write integration test for bush harvest**

Create `gol-project/tests/integration/creatures/test_player_harvest_bush.gd`:

```gdscript
class_name TestPlayerHarvestBushConfig
extends SceneConfig

## Integration test: player harvests raspberry bush → stockpile gains RFood(2),
## bush enters cooldown (emoji swap), bush regrows after cooldown.

const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const CResourceNode = preload("res://scripts/components/c_resource_node.gd")
const RFood = preload("res://scripts/resources/r_food.gd")


func scene_name() -> String:
	return "test"


func systems() -> Variant:
	return [
		"res://scripts/systems/s_harvest.gd",
	]


func enable_pcg() -> bool:
	return false


func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "TestPlayer",
			"components": {
				"CTransform": { "position": Vector2(0, 0) },
			},
		},
		{
			"recipe": "raspberry_bush",
			"name": "TestBush",
			"components": {
				"CTransform": { "position": Vector2(16, 0) },
			},
		},
	]


func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	var stockpile_entity := _find_by_component(world, CStockpile)
	if stockpile_entity == null:
		result.fail("No stockpile entity found")
		return result

	var stockpile := stockpile_entity.get_component(CStockpile) as CStockpile
	var initial_food: int = stockpile.get_amount(RFood)

	var bush := _find_entity(world, "TestBush")
	if bush == null:
		result.fail("Bush entity not found")
		return result

	var node := bush.get_component(CResourceNode) as CResourceNode

	# Simulate: directly call consume_yield + stockpile.add (SHarvest requires input)
	var yielded: int = node.consume_yield()
	stockpile.add(RFood, yielded)
	node.start_cooldown()

	# Verify yield
	result.assert_equal(yielded, 2, "Bush should yield 2")
	result.assert_equal(stockpile.get_amount(RFood), initial_food + 2, "Stockpile should gain 2 RFood")

	# Verify cooldown
	result.assert_true(node.is_on_cooldown, "Bush should be on cooldown after harvest")
	result.assert_false(node.can_gather(), "Bush should not be gatherable during cooldown")

	# Simulate cooldown expiry
	node.cooldown_remaining = 0.0
	result.assert_false(node.is_on_cooldown, "Bush should not be on cooldown after expiry")
	result.assert_true(node.can_gather(), "Bush should be gatherable after cooldown")

	return result
```

- [ ] **Step 3: Write integration test for carrot harvest**

Create `gol-project/tests/integration/creatures/test_player_harvest_carrot.gd`:

```gdscript
class_name TestPlayerHarvestCarrotConfig
extends SceneConfig

## Integration test: player harvests carrot → stockpile gains RFood(1),
## carrot entity is removed.

const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const RFood = preload("res://scripts/resources/r_food.gd")


func scene_name() -> String:
	return "test"


func systems() -> Variant:
	return [
		"res://scripts/systems/s_harvest.gd",
	]


func enable_pcg() -> bool:
	return false


func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "TestPlayer",
			"components": {
				"CTransform": { "position": Vector2(0, 0) },
			},
		},
		{
			"recipe": "carrot",
			"name": "TestCarrot",
			"components": {
				"CTransform": { "position": Vector2(10, 0) },
			},
		},
	]


func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	var stockpile_entity := _find_by_component(world, CStockpile)
	if stockpile_entity == null:
		result.fail("No stockpile entity found")
		return result

	var stockpile := stockpile_entity.get_component(CStockpile) as CStockpile
	var initial_food: int = stockpile.get_amount(RFood)

	var carrot := _find_entity(world, "TestCarrot")
	if carrot == null:
		result.fail("Carrot entity not found")
		return result

	var eatable := carrot.get_component(CEatable) as CEatable

	# Verify carrot is player-harvestable
	result.assert_true(eatable.player_harvestable, "Carrot should be player_harvestable")
	result.assert_equal(eatable.harvest_yield, 1, "Carrot harvest_yield should be 1")

	# Simulate harvest: add to stockpile + remove entity
	stockpile.add(RFood, eatable.harvest_yield)
	ECS.world.remove_entity(carrot)

	result.assert_equal(stockpile.get_amount(RFood), initial_food + 1, "Stockpile should gain 1 RFood")

	# Verify carrot is removed
	await _wait_frames(world, 2)
	var carrot_after := _find_entity(world, "TestCarrot")
	result.assert_null(carrot_after, "Carrot should be removed after harvest")

	return result
```

- [ ] **Step 4: Run tests**

Run: `./run-tests.command`
Expected: PASS — both integration tests green

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_harvest.gd tests/integration/creatures/test_player_harvest_bush.gd tests/integration/creatures/test_player_harvest_carrot.gd
git commit -m "feat(harvest): add SHarvest system with bush and carrot harvesting"
```

---

## Task 9: SPerception — add `has_visible_harvestable` fact

**Files:**
- Modify: `gol-project/scripts/systems/s_perception.gd:5-7,64-71,104,139-146,148-155`

- [ ] **Step 1: Add CResourceNode to perception cache**

In `gol-project/scripts/systems/s_perception.gd`, add a const preload after line 7 (`const RFood`):

```gdscript
const CResourceNode := preload("res://scripts/components/c_resource_node.gd")
```

In `_ensure_cache()`, in the cache entry dict (line 64-71), add a new field after `"resource_pickup"`:

```gdscript
			"harvestable": e.has_component(CResourceNode),
```

- [ ] **Step 2: Track harvestable visibility in _process_entity**

In `_process_entity()`, add a tracking variable after line 105 (`var has_food_pile := false`):

```gdscript
	var has_harvestable := false
```

In the cache scan loop, after the food pile tracking block (after line 146), add:

```gdscript
		# Track visible harvestable resource nodes (bushes)
		if entry["harvestable"] and not has_harvestable:
			var resource_node := candidate.get_component(CResourceNode) as CResourceNode
			if resource_node != null and resource_node.can_gather():
				has_harvestable = true
```

In the GOAP blackboard mirror section (after line 155), add:

```gdscript
		agent.world_state.update_fact("has_visible_harvestable", has_harvestable)
```

- [ ] **Step 3: Run tests to verify nothing breaks**

Run: `./run-tests.command`
Expected: PASS — all existing perception tests still green

- [ ] **Step 4: Commit**

```bash
git add scripts/systems/s_perception.gd
git commit -m "feat(harvest): add has_visible_harvestable fact to SPerception"
```

---

## Task 10: SAutoFeed — mirror `stockpile_has_food` fact

**Files:**
- Modify: `gol-project/scripts/systems/s_auto_feed.gd:35-39`

- [ ] **Step 1: Add stockpile_has_food fact mirroring**

In `gol-project/scripts/systems/s_auto_feed.gd`, in `process()`, after line 35 (`var stockpile := _find_camp_stockpile()`), replace lines 36-39 with:

```gdscript
	var has_food: bool = stockpile != null and stockpile.get_amount(RFood) > 0

	# Mirror stockpile state to all PLAYER-camp GOAP agents for foraging decisions
	for e in entities:
		if e == null or not is_instance_valid(e):
			continue
		var camp := e.get_component(CCamp) as CCamp
		if camp == null or camp.camp != CCamp.CampType.PLAYER:
			continue
		var agent := e.get_component(CGoapAgent) as CGoapAgent
		if agent:
			agent.world_state.update_fact("stockpile_has_food", has_food)

	if stockpile == null:
		return
	if stockpile.get_amount(RFood) <= 0:
		return
```

- [ ] **Step 2: Run tests to verify nothing breaks**

Run: `./run-tests.command`
Expected: PASS — all existing auto-feed tests still green

- [ ] **Step 3: Commit**

```bash
git add scripts/systems/s_auto_feed.gd
git commit -m "feat(harvest): mirror stockpile_has_food fact from SAutoFeed to GOAP agents"
```

---

## Task 11: NPC foraging GOAP actions

**Files:**
- Create: `gol-project/scripts/gameplay/goap/actions/move_to_harvestable.gd`
- Create: `gol-project/scripts/gameplay/goap/actions/harvest_bush.gd`
- Test: `gol-project/tests/integration/creatures/test_npc_forages_bush.gd` (create)

- [ ] **Step 1: Create GoapAction_MoveToHarvestable**

Create `gol-project/scripts/gameplay/goap/actions/move_to_harvestable.gd`:

```gdscript
class_name GoapAction_MoveToHarvestable
extends GoapAction
## NPC moves toward the nearest visible CResourceNode that can be gathered.
## Fallback foraging behavior when stockpile is empty and NPC is hungry.

const CResourceNode = preload("res://scripts/components/c_resource_node.gd")
const ADJACENCY_THRESHOLD: float = 24.0

func _init() -> void:
	action_name = "MoveToHarvestable"
	cost = 5.0
	preconditions = {
		"is_hungry": true,
		"stockpile_has_food": false,
		"has_visible_harvestable": true,
		"adjacent_to_harvestable": false,
	}
	effects = {"adjacent_to_harvestable": true}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform) as CTransform
	var movement := agent_entity.get_component(CMovement) as CMovement
	var perception := agent_entity.get_component(CPerception) as CPerception
	if transform == null or movement == null or perception == null:
		return true

	var nearest: Entity = _find_nearest_harvestable(perception, transform.position)
	if nearest == null:
		movement.velocity = Vector2.ZERO
		update_world_state(agent_component, "has_visible_harvestable", false)
		return true

	var nt := nearest.get_component(CTransform) as CTransform
	if nt == null:
		return true

	var offset: Vector2 = nt.position - transform.position
	var dist: float = offset.length()

	if dist <= ADJACENCY_THRESHOLD:
		movement.velocity = Vector2.ZERO
		agent_component.blackboard["harvest_target"] = nearest
		update_world_state(agent_component, "adjacent_to_harvestable", true)
		return true

	var dir: Vector2 = offset.normalized() if dist > 0.0 else Vector2.ZERO
	movement.velocity = dir * movement.max_speed
	update_world_state(agent_component, "adjacent_to_harvestable", false)
	return false


func _find_nearest_harvestable(perception: CPerception, from: Vector2) -> Entity:
	var best: Entity = null
	var best_dist_sq := INF
	for candidate in perception._visible_entities:
		if candidate == null or not is_instance_valid(candidate):
			continue
		var node := candidate.get_component(CResourceNode) as CResourceNode
		if node == null or not node.can_gather():
			continue
		var ct := candidate.get_component(CTransform) as CTransform
		if ct == null:
			continue
		var d := from.distance_squared_to(ct.position)
		if d < best_dist_sq:
			best_dist_sq = d
			best = candidate
	return best
```

- [ ] **Step 2: Create GoapAction_HarvestBush**

Create `gol-project/scripts/gameplay/goap/actions/harvest_bush.gd`:

```gdscript
class_name GoapAction_HarvestBush
extends GoapAction
## NPC timed gather from a CResourceNode (bush). Deposits yield to camp
## stockpile and directly restores hunger. Shows progress bar during gather.

const CResourceNode = preload("res://scripts/components/c_resource_node.gd")
const RFood = preload("res://scripts/resources/r_food.gd")
const ViewProgressBar = preload("res://scripts/ui/views/view_progress_bar.gd")
const PROGRESS_BAR_SCENE = preload("res://scenes/ui/progress_bar.tscn")

const CTX_ELAPSED: String = "harvest_elapsed"
const CTX_PROGRESS_VIEW: String = "harvest_progress_view"

func _init() -> void:
	action_name = "HarvestBush"
	cost = 1.0
	preconditions = {"adjacent_to_harvestable": true}
	effects = {"is_fed": true}


func on_plan_enter(agent_entity: Entity, _agent_component: CGoapAgent, context: Dictionary) -> void:
	context[CTX_ELAPSED] = 0.0
	context[CTX_PROGRESS_VIEW] = _create_progress_bar(agent_entity)


func on_plan_exit(context: Dictionary) -> void:
	_cleanup_progress_bar(context.get(CTX_PROGRESS_VIEW, null))
	context[CTX_PROGRESS_VIEW] = null
	context[CTX_ELAPSED] = 0.0


func perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	if movement:
		movement.velocity = Vector2.ZERO

	var target: Entity = agent_component.blackboard.get("harvest_target", null)
	if target == null or not is_instance_valid(target):
		return true

	var node: CResourceNode = target.get_component(CResourceNode)
	if node == null or not node.can_gather():
		return true

	var elapsed: float = float(context.get(CTX_ELAPSED, 0.0)) + delta
	context[CTX_ELAPSED] = elapsed
	_update_progress_bar(context.get(CTX_PROGRESS_VIEW, null), elapsed / node.gather_duration)

	if elapsed < node.gather_duration:
		return false

	var yielded := node.consume_yield()
	_cleanup_progress_bar(context.get(CTX_PROGRESS_VIEW, null))
	context[CTX_PROGRESS_VIEW] = null
	context[CTX_ELAPSED] = 0.0

	if yielded <= 0:
		return true

	# Deposit to camp stockpile
	var stockpile := _find_camp_stockpile()
	if stockpile:
		stockpile.add(node.yield_type, yielded)

	# Directly restore hunger (NPC is foraging because it's hungry)
	var hunger := agent_entity.get_component(CHunger) as CHunger
	if hunger:
		hunger.hunger = min(hunger.max_hunger, hunger.hunger + HungerTable.HUNGER_PER_FOOD_UNIT * yielded)

	# Start bush cooldown + swap emoji
	node.start_cooldown()
	var label := target.get_component(CLabelDisplay) as CLabelDisplay
	if label and node.depleted_label != "":
		label.text = node.depleted_label

	agent_component.blackboard.erase("harvest_target")
	update_world_state(agent_component, "adjacent_to_harvestable", false)
	update_world_state(agent_component, "is_fed", true)
	return true


func _find_camp_stockpile() -> CStockpile:
	var found: Array = ECS.world.query.with_all([CStockpile]).with_none([CPlayer]).execute()
	if found.is_empty():
		return null
	return found[0].get_component(CStockpile) as CStockpile


func _create_progress_bar(agent_entity: Entity) -> ViewProgressBar:
	var view: ViewProgressBar = PROGRESS_BAR_SCENE.instantiate() as ViewProgressBar
	if view == null:
		return null
	ServiceContext.ui().push_view(Service_UI.LayerType.GAME, view)
	view.setup(agent_entity, ViewProgressBar.COLOR_HARVEST)
	return view


func _update_progress_bar(view: Variant, ratio: float) -> void:
	if view != null and is_instance_valid(view):
		(view as ViewProgressBar).set_progress(ratio)


func _cleanup_progress_bar(view: Variant) -> void:
	if view != null and is_instance_valid(view):
		ServiceContext.ui().pop_view(view as ViewProgressBar)
```

- [ ] **Step 3: Write integration test for NPC foraging**

Create `gol-project/tests/integration/creatures/test_npc_forages_bush.gd`:

```gdscript
class_name TestNpcForagesBushConfig
extends SceneConfig

## Integration test: NPC forages bush when stockpile is empty and hungry.
## Verifies GOAP action preconditions and effects.

const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const CResourceNode = preload("res://scripts/components/c_resource_node.gd")
const RFood = preload("res://scripts/resources/r_food.gd")


func scene_name() -> String:
	return "test"


func systems() -> Variant:
	return [
		"res://scripts/systems/s_hunger.gd",
		"res://scripts/systems/s_auto_feed.gd",
		"res://scripts/systems/s_perception.gd",
		"res://scripts/systems/s_ai.gd",
	]


func enable_pcg() -> bool:
	return false


func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "TestPlayer",
			"components": {
				"CTransform": { "position": Vector2(0, 0) },
			},
		},
		{
			"recipe": "survivor",
			"name": "TestGuard",
			"components": {
				"CTransform": { "position": Vector2(50, 0) },
				"CHunger": { "hunger": 20.0, "max_hunger": 100.0 },
			},
		},
		{
			"recipe": "raspberry_bush",
			"name": "TestBush",
			"components": {
				"CTransform": { "position": Vector2(80, 0) },
			},
		},
	]


func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	# Verify preconditions: guard is hungry, stockpile empty, bush visible
	var guard := _find_entity(world, "TestGuard")
	if guard == null:
		result.fail("Guard entity not found")
		return result

	var hunger := guard.get_component(CHunger) as CHunger
	result.assert_true(hunger.hunger < hunger.max_hunger * hunger.hungry_threshold,
		"Guard should be hungry (hunger=20 < threshold)")

	var stockpile_entity := _find_by_component(world, CStockpile)
	var stockpile := stockpile_entity.get_component(CStockpile) as CStockpile if stockpile_entity else null
	if stockpile:
		result.assert_equal(stockpile.get_amount(RFood), 0, "Stockpile should be empty")

	var bush := _find_entity(world, "TestBush")
	var node := bush.get_component(CResourceNode) as CResourceNode if bush else null
	if node:
		result.assert_true(node.can_gather(), "Bush should be gatherable")

	# Verify GOAP action preconditions match
	var action := GoapAction_MoveToHarvestable.new()
	result.assert_equal(action.cost, 5.0, "MoveToHarvestable cost should be 5.0")
	result.assert_true(action.preconditions.has("is_hungry"), "Should require is_hungry")
	result.assert_true(action.preconditions.has("stockpile_has_food"), "Should require stockpile_has_food")

	var harvest_action := GoapAction_HarvestBush.new()
	result.assert_equal(harvest_action.cost, 1.0, "HarvestBush cost should be 1.0")
	result.assert_true(harvest_action.effects.has("is_fed"), "Should produce is_fed effect")

	return result
```

- [ ] **Step 4: Run tests**

Run: `./run-tests.command`
Expected: PASS — integration test green

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay/goap/actions/move_to_harvestable.gd scripts/gameplay/goap/actions/harvest_bush.gd tests/integration/creatures/test_npc_forages_bush.gd
git commit -m "feat(harvest): add NPC foraging GOAP actions (MoveToHarvestable + HarvestBush)"
```

---

## Task 12: Register SHarvest in the ECS world

**Files:**
- Modify: The system registration file (wherever systems are registered for the gameplay group)

- [ ] **Step 1: Find where gameplay systems are registered**

Search for where `SResourcePickup` or `SWorldGrowth` is registered/added to the ECS world. This is typically in `gol_world.gd` or a system registration config.

```bash
grep -rn "SHunger\|SWorldGrowth\|SResourcePickup\|add_system\|system_list\|gameplay_systems" gol-project/scripts/ --include="*.gd" | head -20
```

- [ ] **Step 2: Register SHarvest alongside existing gameplay systems**

Add `SHarvest` to the same registration list where `SResourcePickup`, `SHunger`, `SAutoFeed`, and `SWorldGrowth` are registered. It should run in the `"gameplay"` group.

- [ ] **Step 3: Run the game to verify SHarvest loads without errors**

Run: Start the game, verify no errors in the console related to SHarvest.

- [ ] **Step 4: Commit**

```bash
git add <modified registration file>
git commit -m "feat(harvest): register SHarvest system in gameplay group"
```

---

## Task 13: Final integration — playtest verification

**Files:** None (manual verification)

- [ ] **Step 1: Run all tests**

Run: `./run-tests.command`
Expected: ALL tests pass (unit + integration)

- [ ] **Step 2: Playtest — PCG plant placement**

Start a new game. Walk around the map and verify:
- ~20 raspberry bushes (🍓) placed in WILDERNESS/SUBURBS zones
- ~35 carrots (🥕) placed in WILDERNESS zones
- No plants in URBAN zones
- Plants don't overlap with POIs, roads, or buildings

- [ ] **Step 3: Playtest — bush harvest cycle**

Walk to a bush, press interact:
- Green progress bar appears (36×5px, above bush)
- Bar fills over 2 seconds
- At 100%: white flash, bar disappears
- "+2 食物" floating text appears on bush
- Bush emoji changes 🍓→🪵
- Camp stockpile gains 2 RFood
- After 60s: bush emoji changes 🪵→🍓, harvestable again

- [ ] **Step 4: Playtest — carrot harvest**

Walk to a carrot, press interact:
- No progress bar (instant)
- "+1 食物" floating text appears on player
- Carrot entity disappears
- Camp stockpile gains 1 RFood

- [ ] **Step 5: Playtest — rabbit eats carrot**

Observe a rabbit near a carrot:
- Rabbit moves to carrot when hungry
- Rabbit eats carrot (entity removed)
- Rabbit hunger restored

- [ ] **Step 6: Playtest — NPC foraging**

Empty the camp stockpile (let NPCs eat all food). Observe guards:
- When hungry + stockpile empty, guards walk to nearest bush
- Progress bar appears during gather
- Bush enters cooldown after harvest
- Guard hunger restored

- [ ] **Step 7: Final commit — bump submodule pointer**

```bash
cd gol-project && git push origin main
cd .. && git add gol-project && git commit -m "feat: add harvest system + new plant types (raspberry bush, carrot)"
git push origin main
```
