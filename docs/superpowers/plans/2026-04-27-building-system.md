# Building System v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement RTS-style building system — player places ghosts, worker NPCs deliver materials and construct buildings.

**Architecture:** Dual-component staged approach. `CBuildSite` on ghost entities tracks material delivery and construction progress. On completion, ghost is destroyed and a new building entity is created via `EntityRecipe`. `BuildingTable` in `GOL.Tables` holds build costs/durations. Four new GOAP actions drive worker NPC behavior.

**Tech Stack:** Godot 4.x + GECS v8.0.0 ECS framework, GDScript, GOAP AI planner

**Spec:** `docs/superpowers/specs/2026-04-27-building-system-design.md`

---

## File Structure

```
NEW FILES:
scripts/resources/r_stone.gd                              # Stone resource type (camp recipe needs it)
scripts/components/c_build_site.gd                         # Ghost entity component — tracks materials + construction
scripts/components/c_building.gd                           # Completed building marker component
scripts/gameplay/tables/building_table.gd                  # Building data table (GOL.Tables.building())
scripts/systems/s_build_site_complete.gd                   # Detects construction completion, replaces ghost with building
scripts/systems/s_build_operation.gd                       # Player interaction: menu, placement preview, ghost spawn, cancel
scripts/gameplay/goap/goals/goap_goal_build.gd             # Build goal script
scripts/gameplay/goap/actions/goap_action_find_build_site.gd
scripts/gameplay/goap/actions/goap_action_move_to_build_site.gd
scripts/gameplay/goap/actions/goap_action_move_to_stockpile_for_build.gd
scripts/gameplay/goap/actions/goap_action_pickup_build_material.gd
scripts/gameplay/goap/actions/goap_action_deliver_build_material.gd
scripts/gameplay/goap/actions/goap_action_construct_building.gd
resources/goals/build.tres                                 # Build goal .tres for npc_worker
resources/recipes/ghost_building.tres                      # Generic ghost template recipe
resources/recipes/camp.tres                                # Camp building entity recipe
tests/integration/flow/test_flow_build_site_complete.gd    # Test: ghost → building replacement
tests/integration/flow/test_flow_worker_build.gd           # Test: full worker build cycle

MODIFIED FILES:
scripts/gameplay/game_tables.gd                            # Add _building + building() accessor
resources/recipes/campfire.tres                            # Add CBuilding component
resources/recipes/npc_worker.tres                          # Add build goal to CGoapAgent.goals[]
project.godot                                              # Add "build_menu" input action (B key)
```

---

## Task 1: RStone Resource Type

**Files:**
- Create: `gol-project/scripts/resources/r_stone.gd`

- [ ] **Step 1: Create RStone resource**

```gdscript
# scripts/resources/r_stone.gd
class_name RStone
extends Resource

const DISPLAY_NAME: String = "石材"
const ICON_PATH: String = "res://assets/icons/resources/stone.png"
const MAX_STACK: int = 999
```

- [ ] **Step 2: Verify Godot recognizes the class**

Run: `cd gol-project && grep -r "RStone" scripts/resources/r_stone.gd`
Expected: Shows the class definition.

- [ ] **Step 3: Commit**

```bash
git add gol-project/scripts/resources/r_stone.gd
git commit -m "feat(building): add RStone resource type"
```

---

## Task 2: CBuilding Component

**Files:**
- Create: `gol-project/scripts/components/c_building.gd`

- [ ] **Step 1: Create CBuilding component**

```gdscript
class_name CBuilding
extends Component

@export var building_id: String = ""
```

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/components/c_building.gd
git commit -m "feat(building): add CBuilding marker component"
```

---

## Task 3: CBuildSite Component

**Files:**
- Create: `gol-project/scripts/components/c_build_site.gd`

- [ ] **Step 1: Create CBuildSite component**

```gdscript
class_name CBuildSite
extends Component

## Key into BuildingTable (GOL.Tables.building())
@export var building_id: String = ""

## {Script → int} — total materials required. Copied from BuildingTable on spawn.
@export var required_materials: Dictionary = {}

## {Script → int} — materials delivered so far. Updated at runtime by NPC actions.
@export var deposited_materials: Dictionary = {}

## Seconds of construction work needed after all materials arrive.
@export var build_duration: float = 3.0

## Seconds of construction work completed so far.
@export var build_progress: float = 0.0

## Set to true when deposited_materials meets or exceeds required_materials for every type.
@export var materials_complete: bool = false

## Observable for UI binding (emits build_progress / build_duration ratio).
var progress_observable: ObservableProperty = ObservableProperty.new(0.0)


## Check whether all required materials have been delivered.
func check_materials_complete() -> bool:
	for res_type in required_materials:
		var needed: int = int(required_materials[res_type])
		var have: int = int(deposited_materials.get(res_type, 0))
		if have < needed:
			return false
	materials_complete = true
	return true


## Deposit a material. Returns the amount actually accepted (capped at remaining need).
func deposit(resource_type: Script, amount: int) -> int:
	var needed: int = int(required_materials.get(resource_type, 0))
	var have: int = int(deposited_materials.get(resource_type, 0))
	var remaining: int = needed - have
	if remaining <= 0:
		return 0
	var accepted: int = mini(amount, remaining)
	deposited_materials[resource_type] = have + accepted
	check_materials_complete()
	return accepted


## Overall material progress as a ratio 0.0–1.0.
func material_progress() -> float:
	var total_needed: int = 0
	var total_have: int = 0
	for res_type in required_materials:
		total_needed += int(required_materials[res_type])
		total_have += int(deposited_materials.get(res_type, 0))
	if total_needed == 0:
		return 1.0
	return float(total_have) / float(total_needed)
```

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/components/c_build_site.gd
git commit -m "feat(building): add CBuildSite component with deposit/progress logic"
```

---

## Task 4: BuildingTable + GameTables Integration

**Files:**
- Create: `gol-project/scripts/gameplay/tables/building_table.gd`
- Modify: `gol-project/scripts/gameplay/game_tables.gd`

- [ ] **Step 1: Create BuildingTable**

```gdscript
# scripts/gameplay/tables/building_table.gd
class_name BuildingTable
extends Resource
## Building construction data. Keyed by building_id.
## Each entry:
##   display_name:       String
##   required_materials: Dictionary {Script → int}
##   build_duration:     float (seconds of construction after materials delivered)
##   entity_recipe_id:   String (EntityRecipe to spawn on completion)

const RWood = preload("res://scripts/resources/r_wood.gd")
const RStone = preload("res://scripts/resources/r_stone.gd")

const TABLES: Dictionary = {
	"campfire": {
		display_name = "篝火",
		required_materials = {RWood: 5},
		build_duration = 3.0,
		entity_recipe_id = "campfire",
	},
	"camp": {
		display_name = "营帐",
		required_materials = {RWood: 8, RStone: 3},
		build_duration = 5.0,
		entity_recipe_id = "camp",
	},
}


## Get building data by id, or empty dict if unknown.
func get_building(building_id: String) -> Dictionary:
	return TABLES.get(building_id, {})


## All building data.
func all() -> Dictionary:
	return TABLES


## All valid building ids.
func get_all_ids() -> Array:
	return TABLES.keys()
```

- [ ] **Step 2: Register in GameTables**

In `gol-project/scripts/gameplay/game_tables.gd`, add the building table alongside existing tables.

Add field and init after `_hunger`:
```gdscript
var _building: BuildingTable = null
```

In `_init()`, add after `_hunger = HungerTable.new()`:
```gdscript
	_building = BuildingTable.new()
```

Add accessor after `hunger()`:
```gdscript
func building() -> BuildingTable:
	return _building
```

- [ ] **Step 3: Verify access pattern compiles**

The access pattern is `GOL.Tables.building().get_building("campfire")`. This will be exercised in the integration test (Task 8).

- [ ] **Step 4: Commit**

```bash
git add gol-project/scripts/gameplay/tables/building_table.gd gol-project/scripts/gameplay/game_tables.gd
git commit -m "feat(building): add BuildingTable and register in GOL.Tables"
```

---

## Task 5: EntityRecipes — Ghost, Campfire Update, Camp

**Files:**
- Create: `gol-project/resources/recipes/ghost_building.tres`
- Modify: `gol-project/resources/recipes/campfire.tres`
- Create: `gol-project/resources/recipes/camp.tres`

- [ ] **Step 1: Create ghost_building.tres**

This is the generic ghost template recipe. `SBuildOperation` will populate `CBuildSite` fields and `CSprite` texture from `BuildingTable` after spawning.

```tres
[gd_resource type="Resource" script_class="EntityRecipe" load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/gameplay/ecs/recipes/entity_recipe.gd" id="1"]
[ext_resource type="Script" path="res://addons/gecs/component.gd" id="1_component"]
[ext_resource type="Script" path="res://scripts/components/c_transform.gd" id="2_transform"]
[ext_resource type="Script" path="res://scripts/components/c_sprite.gd" id="3_sprite"]
[ext_resource type="Script" path="res://scripts/components/c_build_site.gd" id="4_build_site"]

[sub_resource type="Resource" id="transform"]
script = ExtResource("2_transform")

[sub_resource type="Resource" id="sprite"]
script = ExtResource("3_sprite")
modulate = Color(1, 1, 1, 0.5)

[sub_resource type="Resource" id="build_site"]
script = ExtResource("4_build_site")

[resource]
script = ExtResource("1")
recipe_id = "ghost_building"
display_name = "Ghost Building"
components = Array[ExtResource("1_component")]([SubResource("transform"), SubResource("sprite"), SubResource("build_site")])
```

- [ ] **Step 2: Add CBuilding to campfire.tres**

Open `gol-project/resources/recipes/campfire.tres`. Add a new `ext_resource` for the CBuilding script and a new `sub_resource` for the CBuilding component, then append it to the `components` array.

Add ext_resource:
```
[ext_resource type="Script" path="res://scripts/components/c_building.gd" id="8_building"]
```

Add sub_resource:
```
[sub_resource type="Resource" id="building"]
script = ExtResource("8_building")
building_id = "campfire"
```

Append `SubResource("building")` to the `components` array.

Update `load_steps` to account for the new resources.

- [ ] **Step 3: Create camp.tres**

```tres
[gd_resource type="Resource" script_class="EntityRecipe" load_steps=9 format=3]

[ext_resource type="Script" path="res://scripts/gameplay/ecs/recipes/entity_recipe.gd" id="1"]
[ext_resource type="Script" path="res://addons/gecs/component.gd" id="1_component"]
[ext_resource type="Script" path="res://scripts/components/c_transform.gd" id="2_transform"]
[ext_resource type="Script" path="res://scripts/components/c_sprite.gd" id="3_sprite"]
[ext_resource type="Script" path="res://scripts/components/c_camp.gd" id="4_camp"]
[ext_resource type="Script" path="res://scripts/components/c_collision.gd" id="5_collision"]
[ext_resource type="Script" path="res://scripts/components/c_building.gd" id="6_building"]
[ext_resource type="Script" path="res://scripts/components/c_hp.gd" id="7_hp"]

[sub_resource type="Resource" id="transform"]
script = ExtResource("2_transform")

[sub_resource type="Resource" id="sprite"]
script = ExtResource("3_sprite")

[sub_resource type="Resource" id="camp"]
script = ExtResource("4_camp")
camp = 0

[sub_resource type="CircleShape2D" id="CircleShape2D_camp"]
radius = 20.0

[sub_resource type="Resource" id="collision"]
script = ExtResource("5_collision")
collision_shape = SubResource("CircleShape2D_camp")

[sub_resource type="Resource" id="building"]
script = ExtResource("6_building")
building_id = "camp"

[sub_resource type="Resource" id="hp"]
script = ExtResource("7_hp")
max_hp = 300.0
hp = 300.0

[resource]
script = ExtResource("1")
recipe_id = "camp"
display_name = "营帐"
components = Array[ExtResource("1_component")]([SubResource("transform"), SubResource("sprite"), SubResource("camp"), SubResource("collision"), SubResource("building"), SubResource("hp")])
```

- [ ] **Step 4: Commit**

```bash
git add gol-project/resources/recipes/ghost_building.tres gol-project/resources/recipes/campfire.tres gol-project/resources/recipes/camp.tres
git commit -m "feat(building): add ghost_building + camp recipes, add CBuilding to campfire"
```

---

## Task 6: SBuildSiteComplete System

**Files:**
- Create: `gol-project/scripts/systems/s_build_site_complete.gd`

- [ ] **Step 1: Create the system**

```gdscript
class_name SBuildSiteComplete
extends System
## Monitors all CBuildSite entities. When materials are complete AND
## build_progress >= build_duration, destroys the ghost and spawns
## the finished building entity via EntityRecipe.


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CBuildSite, CTransform])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var site: CBuildSite = entity.get_component(CBuildSite)
		if site == null:
			continue
		if not site.materials_complete:
			continue
		if site.build_progress < site.build_duration:
			continue
		_complete_building(entity, site)


func _complete_building(ghost: Entity, site: CBuildSite) -> void:
	var ghost_transform := ghost.get_component(CTransform) as CTransform
	if ghost_transform == null:
		cmd.remove_entity(ghost)
		return

	var building_data: Dictionary = GOL.Tables.building().get_building(site.building_id)
	var recipe_id: String = String(building_data.get("entity_recipe_id", ""))
	if recipe_id == "":
		push_warning("[SBuildSiteComplete] No entity_recipe_id for building '%s'" % site.building_id)
		cmd.remove_entity(ghost)
		return

	var spawn_pos: Vector2 = ghost_transform.position

	# Remove ghost first to free the tile
	cmd.remove_entity(ghost)

	# Spawn the completed building
	var building_entity: Entity = ServiceContext.recipe().create_entity_by_id(recipe_id)
	if building_entity == null:
		push_warning("[SBuildSiteComplete] Failed to create entity for recipe '%s'" % recipe_id)
		return

	var building_transform := building_entity.get_component(CTransform) as CTransform
	if building_transform:
		building_transform.position = spawn_pos
```

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/systems/s_build_site_complete.gd
git commit -m "feat(building): add SBuildSiteComplete system — ghost to building replacement"
```

---

## Task 7: Integration Test — Build Site Completion

**Files:**
- Create: `gol-project/tests/integration/flow/test_flow_build_site_complete.gd`

- [ ] **Step 1: Write the test**

This test verifies that when a ghost entity has `materials_complete = true` and `build_progress >= build_duration`, `SBuildSiteComplete` destroys the ghost and spawns the building.

```gdscript
class_name TestFlowBuildSiteCompleteConfig
extends SceneConfig

const CBuildSite = preload("res://scripts/components/c_build_site.gd")
const CBuilding = preload("res://scripts/components/c_building.gd")
const RWood = preload("res://scripts/resources/r_wood.gd")


func scene_name() -> String:
	return "test"


func systems() -> Variant:
	return [
		"res://scripts/systems/s_build_site_complete.gd",
	]


func enable_pcg() -> bool:
	return false


func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "TestPlayer",
			"components": {
				"CTransform": { "position": Vector2(500, 500) },
			},
		},
		{
			"recipe": "ghost_building",
			"name": "TestGhost",
			"components": {
				"CTransform": { "position": Vector2(100, 100) },
				"CBuildSite": {
					"building_id": "campfire",
					"required_materials": {RWood: 5},
					"deposited_materials": {RWood: 5},
					"build_duration": 1.0,
					"build_progress": 1.0,
					"materials_complete": true,
				},
			},
		},
	]


func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	var ghost: Entity = _find_entity(world, "TestGhost")
	result.assert_true(ghost != null, "Ghost entity spawned")
	if ghost == null:
		return result

	var site: CBuildSite = ghost.get_component(CBuildSite)
	result.assert_true(site != null, "Ghost has CBuildSite component")
	result.assert_true(site.materials_complete, "Ghost materials_complete is true")
	result.assert_true(site.build_progress >= site.build_duration, "Ghost build_progress >= build_duration")

	# Let SBuildSiteComplete process one frame
	await _wait_frames(world, 2)

	# Ghost should be gone
	var ghost_after: Entity = _find_entity(world, "TestGhost")
	result.assert_true(ghost_after == null or not is_instance_valid(ghost_after), "Ghost entity removed after completion")

	# A building entity with CBuilding should now exist near (100, 100)
	var buildings: Array = ECS.world.query.with_all([CBuilding, CTransform]).execute()
	result.assert_true(buildings.size() >= 1, "At least one CBuilding entity exists after completion")
	if buildings.size() >= 1:
		var b: Entity = buildings[0]
		var bt: CTransform = b.get_component(CTransform)
		result.assert_true(bt.position.distance_to(Vector2(100, 100)) < 1.0, "Building spawned at ghost position")
		var bc: CBuilding = b.get_component(CBuilding)
		result.assert_equal(bc.building_id, "campfire", "Building has correct building_id")

	return result
```

- [ ] **Step 2: Run the test**

Run: `cd gol-project && godot --headless --scene-config tests/integration/flow/test_flow_build_site_complete.gd`

Expected: All assertions PASS. Ghost is removed, building entity with CBuilding + CTransform at (100,100) is created.

- [ ] **Step 3: Commit**

```bash
git add gol-project/tests/integration/flow/test_flow_build_site_complete.gd
git commit -m "test(building): add integration test for build site completion"
```

---

## Task 8: GOAP Goal — Build

**Files:**
- Create: `gol-project/scripts/gameplay/goap/goals/goap_goal_build.gd`
- Create: `gol-project/resources/goals/build.tres`

- [ ] **Step 1: Create the goal script**

The goal script is only needed if we want a custom `is_satisfied()` override. For the build goal, the base `GoapGoal` class works — `desired_state = { "build_materials_delivered": true }`. We still create a script file for consistency with other goals.

```gdscript
class_name GoapGoal_Build
extends GoapGoal
## Build goal — worker seeks construction tasks when ghosts exist.
## Satisfied when build_materials_delivered == true.
## Priority: 15 (below Work at 20, below FeedSelf at 50, below Survive at 100).
```

- [ ] **Step 2: Create build.tres**

```tres
[gd_resource type="Resource" script_class="GoapGoal" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/gameplay/goap/goals/goap_goal_build.gd" id="1"]

[resource]
script = ExtResource("1")
goal_name = "Build"
priority = 15
desired_state = {
"build_materials_delivered": true
}
```

- [ ] **Step 3: Add build goal to npc_worker.tres**

Open `gol-project/resources/recipes/npc_worker.tres`. In the `CGoapAgent` component's `goals` array, add a reference to `resources/goals/build.tres`. Add the ext_resource and sub_resource entries, then append the goal to the goals array alongside the existing survive, feed_self, and work goals.

- [ ] **Step 4: Commit**

```bash
git add gol-project/scripts/gameplay/goap/goals/goap_goal_build.gd gol-project/resources/goals/build.tres gol-project/resources/recipes/npc_worker.tres
git commit -m "feat(building): add Build GOAP goal, assign to npc_worker"
```

---

## Task 9: GOAP Action — FindBuildSite

**Files:**
- Create: `gol-project/scripts/gameplay/goap/actions/goap_action_find_build_site.gd`

- [ ] **Step 1: Create the action**

```gdscript
class_name GoapAction_FindBuildSite
extends GoapAction

const CBuildSite = preload("res://scripts/components/c_build_site.gd")


func _init() -> void:
	action_name = "FindBuildSite"
	cost = 1.0
	preconditions = {"has_build_target": false}
	effects = {"has_build_target": true}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	var agent_transform := agent_entity.get_component(CTransform)
	if agent_transform == null:
		if movement:
			movement.velocity = Vector2.ZERO
		return true

	var candidates: Array = ECS.world.query.with_all([CBuildSite, CTransform]).execute()
	if candidates.is_empty():
		if movement:
			movement.velocity = Vector2.ZERO
		return true

	var nearest: Entity = null
	var nearest_dist_sq: float = INF
	var search_radius_sq: float = Config.WORKER_SEARCH_RADIUS * Config.WORKER_SEARCH_RADIUS

	for cand in candidates:
		if cand == null or not is_instance_valid(cand):
			continue
		var site: CBuildSite = cand.get_component(CBuildSite)
		if site == null:
			continue
		# Skip sites that are already fully constructed (pending SBuildSiteComplete)
		if site.materials_complete and site.build_progress >= site.build_duration:
			continue
		var cand_transform: CTransform = cand.get_component(CTransform)
		var dist_sq: float = agent_transform.position.distance_squared_to(cand_transform.position)
		if dist_sq > search_radius_sq:
			continue
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = cand

	if nearest == null:
		if movement:
			movement.velocity = Vector2.ZERO
		return true

	var site: CBuildSite = nearest.get_component(CBuildSite)
	set_blackboard(agent_component, "build_target_entity", nearest)
	set_blackboard(agent_component, "build_target_pos", nearest.get_component(CTransform).position)

	# Determine what material is still needed
	var needed_material: Script = _find_needed_material(site)
	set_blackboard(agent_component, "build_needed_material", needed_material)

	update_world_state(agent_component, "has_build_target", true)
	return true


func _find_needed_material(site: CBuildSite) -> Script:
	for res_type in site.required_materials:
		var needed: int = int(site.required_materials[res_type])
		var have: int = int(site.deposited_materials.get(res_type, 0))
		if have < needed:
			return res_type
	return null
```

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/gameplay/goap/actions/goap_action_find_build_site.gd
git commit -m "feat(building): add GoapAction_FindBuildSite — perceive nearest ghost"
```

---

## Task 10: GOAP Action — MoveToBuildSite

**Files:**
- Create: `gol-project/scripts/gameplay/goap/actions/goap_action_move_to_build_site.gd`

- [ ] **Step 1: Create the action**

Follows the same pattern as `GoapAction_MoveToStockpile` — extends `GoapAction_MoveTo`, sets target from blackboard.

```gdscript
class_name GoapAction_MoveToBuildSite
extends GoapAction_MoveTo

const CBuildSite = preload("res://scripts/components/c_build_site.gd")


func _init() -> void:
	super._init()
	action_name = "MoveToBuildSite"
	target_key = "build_target_pos"
	cost = 1.0
	preconditions = {"has_build_target": true, "reached_build_target": false}
	effects = {"reached_build_target": true}


func perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, context: Dictionary) -> bool:
	var target_entity: Entity = get_blackboard(agent_component, "build_target_entity", null) as Entity
	if target_entity == null or not is_instance_valid(target_entity):
		var movement := agent_entity.get_component(CMovement)
		if movement:
			movement.velocity = Vector2.ZERO
		fail_plan(agent_component, "Build target entity no longer valid")
		return true

	# Update target position in case the entity moved (shouldn't for ghosts, but safe)
	var target_transform := target_entity.get_component(CTransform)
	if target_transform:
		set_blackboard(agent_component, target_key, target_transform.position)

	var done := super.perform(agent_entity, agent_component, delta, context)
	if done:
		var agent_transform := agent_entity.get_component(CTransform)
		if agent_transform and target_transform:
			if agent_transform.position.distance_to(target_transform.position) <= reach_threshold:
				update_world_state(agent_component, "reached_build_target", true)

	return done
```

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/gameplay/goap/actions/goap_action_move_to_build_site.gd
git commit -m "feat(building): add GoapAction_MoveToBuildSite — walk to ghost position"
```

---

## Task 11: GOAP Action — MoveToStockpileForBuild

**Files:**
- Create: `gol-project/scripts/gameplay/goap/actions/goap_action_move_to_stockpile_for_build.gd`

- [ ] **Step 1: Create the action**

The existing `MoveToStockpile` has precondition `is_carrying: true` (used after gathering). The build chain needs to move to stockpile *before* picking up, when `is_carrying: false` and `has_build_target: true`. This action fills that gap.

```gdscript
class_name GoapAction_MoveToStockpileForBuild
extends GoapAction_MoveTo

const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const CWorker = preload("res://scripts/components/c_worker.gd")


func _init() -> void:
	super._init()
	action_name = "MoveToStockpileForBuild"
	target_key = "stockpile_target_pos"
	cost = 1.0
	preconditions = {"has_build_target": true, "is_carrying": false, "reached_stockpile": false}
	effects = {"reached_stockpile": true}


func perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	var stockpile_entity: Entity = get_blackboard(agent_component, "stockpile_target_entity", null) as Entity

	if stockpile_entity == null or not is_instance_valid(stockpile_entity):
		stockpile_entity = _find_any_stockpile(agent_entity)
		if stockpile_entity == null:
			if movement:
				movement.velocity = Vector2.ZERO
			fail_plan(agent_component, "No stockpile found")
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
			var dist: float = agent_transform.position.distance_to(target_transform.position)
			if dist <= reach_threshold:
				update_world_state(agent_component, "reached_stockpile", true)

	return done


func _find_any_stockpile(worker: Entity) -> Entity:
	var worker_transform := worker.get_component(CTransform)
	if worker_transform == null:
		return null

	var best: Entity = null
	var best_dist_sq: float = INF
	var candidates: Array = ECS.world.query.with_all([CStockpile, CTransform]).execute()

	for cand in candidates:
		if cand == worker or not is_instance_valid(cand):
			continue
		if cand.has_component(CWorker):
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

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/gameplay/goap/actions/goap_action_move_to_stockpile_for_build.gd
git commit -m "feat(building): add GoapAction_MoveToStockpileForBuild — walk to stockpile for build material"
```

---

## Task 12: GOAP Action — PickupBuildMaterial (was Task 11)

**Files:**
- Create: `gol-project/scripts/gameplay/goap/actions/goap_action_pickup_build_material.gd`

- [ ] **Step 1: Create the action**

```gdscript
class_name GoapAction_PickupBuildMaterial
extends GoapAction

const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const CCarrying = preload("res://scripts/components/c_carrying.gd")
const CWorker = preload("res://scripts/components/c_worker.gd")


func _init() -> void:
	action_name = "PickupBuildMaterial"
	cost = 1.0
	preconditions = {"has_build_target": true, "reached_stockpile": true, "is_carrying": false}
	effects = {"has_build_material": true, "is_carrying": true, "reached_stockpile": false}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	if movement:
		movement.velocity = Vector2.ZERO

	var needed_material: Script = get_blackboard(agent_component, "build_needed_material", null) as Script
	if needed_material == null:
		fail_plan(agent_component, "No build_needed_material in blackboard")
		return true

	var stockpile_entity: Entity = get_blackboard(agent_component, "stockpile_target_entity", null) as Entity
	if stockpile_entity == null or not is_instance_valid(stockpile_entity):
		# Try to find a stockpile
		stockpile_entity = _find_stockpile_with_material(agent_entity, needed_material)
		if stockpile_entity == null:
			fail_plan(agent_component, "No stockpile with needed material")
			return true

	var stockpile: CStockpile = stockpile_entity.get_component(CStockpile)
	if stockpile == null or not stockpile.withdraw(needed_material, 1):
		fail_plan(agent_component, "Cannot withdraw material from stockpile")
		return true

	var carrying := CCarrying.new()
	carrying.resource_type = needed_material
	carrying.amount = 1
	agent_entity.add_component(carrying)

	update_world_state(agent_component, "has_build_material", true)
	update_world_state(agent_component, "is_carrying", true)
	update_world_state(agent_component, "reached_stockpile", false)
	set_blackboard(agent_component, "stockpile_target_entity", null)
	return true


func _find_stockpile_with_material(worker: Entity, material: Script) -> Entity:
	var worker_transform := worker.get_component(CTransform)
	if worker_transform == null:
		return null

	var best: Entity = null
	var best_dist_sq: float = INF
	var candidates: Array = ECS.world.query.with_all([CStockpile, CTransform]).execute()

	for cand in candidates:
		if cand == worker or not is_instance_valid(cand):
			continue
		if cand.has_component(CWorker):
			continue
		var sp: CStockpile = cand.get_component(CStockpile)
		if sp == null or sp.get_amount(material) <= 0:
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

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/gameplay/goap/actions/goap_action_pickup_build_material.gd
git commit -m "feat(building): add GoapAction_PickupBuildMaterial — withdraw from stockpile"
```

---

## Task 13: GOAP Action — DeliverBuildMaterial (was Task 12)

**Files:**
- Create: `gol-project/scripts/gameplay/goap/actions/goap_action_deliver_build_material.gd`

- [ ] **Step 1: Create the action**

```gdscript
class_name GoapAction_DeliverBuildMaterial
extends GoapAction

const CBuildSite = preload("res://scripts/components/c_build_site.gd")
const CCarrying = preload("res://scripts/components/c_carrying.gd")


func _init() -> void:
	action_name = "DeliverBuildMaterial"
	cost = 1.0
	preconditions = {"has_build_material": true, "reached_build_target": true, "is_carrying": true}
	effects = {"build_materials_delivered": true, "is_carrying": false, "has_build_material": false, "has_build_target": false, "reached_build_target": false}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	if movement:
		movement.velocity = Vector2.ZERO

	var carrying: CCarrying = agent_entity.get_component(CCarrying)
	if carrying == null:
		fail_plan(agent_component, "No CCarrying component on agent")
		return true

	var target: Entity = get_blackboard(agent_component, "build_target_entity", null) as Entity
	if target == null or not is_instance_valid(target):
		fail_plan(agent_component, "Build target entity no longer valid")
		return true

	var site: CBuildSite = target.get_component(CBuildSite)
	if site == null:
		fail_plan(agent_component, "Target has no CBuildSite component")
		return true

	var accepted: int = site.deposit(carrying.resource_type, carrying.amount)
	if accepted <= 0:
		# Material not needed (maybe another NPC already delivered it)
		# Don't fail — just clean up and let re-planning handle it
		pass

	agent_entity.remove_component(CCarrying)

	update_world_state(agent_component, "build_materials_delivered", true)
	update_world_state(agent_component, "is_carrying", false)
	update_world_state(agent_component, "has_build_material", false)
	update_world_state(agent_component, "has_build_target", false)
	update_world_state(agent_component, "reached_build_target", false)
	set_blackboard(agent_component, "build_target_entity", null)
	set_blackboard(agent_component, "build_target_pos", null)
	set_blackboard(agent_component, "build_needed_material", null)
	return true
```

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/gameplay/goap/actions/goap_action_deliver_build_material.gd
git commit -m "feat(building): add GoapAction_DeliverBuildMaterial — deposit to ghost"
```

---

## Task 14: GOAP Action — ConstructBuilding (was Task 13)

**Files:**
- Create: `gol-project/scripts/gameplay/goap/actions/goap_action_construct_building.gd`

- [ ] **Step 1: Create the action**

```gdscript
class_name GoapAction_ConstructBuilding
extends GoapAction

const CBuildSite = preload("res://scripts/components/c_build_site.gd")


func _init() -> void:
	action_name = "ConstructBuilding"
	cost = 1.0
	preconditions = {"has_build_target": true, "reached_build_target": true}
	effects = {"build_materials_delivered": true, "has_build_target": false, "reached_build_target": false}


func perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, _context: Dictionary) -> bool:
	var movement := agent_entity.get_component(CMovement)
	if movement:
		movement.velocity = Vector2.ZERO

	var target: Entity = get_blackboard(agent_component, "build_target_entity", null) as Entity
	if target == null or not is_instance_valid(target):
		fail_plan(agent_component, "Build target entity no longer valid")
		return true

	var site: CBuildSite = target.get_component(CBuildSite)
	if site == null:
		fail_plan(agent_component, "Target has no CBuildSite component")
		return true

	# Only construct if materials are complete
	if not site.materials_complete:
		fail_plan(agent_component, "Materials not yet complete")
		return true

	site.build_progress += delta
	site.progress_observable.set_value(site.build_progress / site.build_duration)

	if site.build_progress >= site.build_duration:
		# Construction done — SBuildSiteComplete will handle replacement
		update_world_state(agent_component, "build_materials_delivered", true)
		update_world_state(agent_component, "has_build_target", false)
		update_world_state(agent_component, "reached_build_target", false)
		set_blackboard(agent_component, "build_target_entity", null)
		set_blackboard(agent_component, "build_target_pos", null)
		return true

	return false
```

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/gameplay/goap/actions/goap_action_construct_building.gd
git commit -m "feat(building): add GoapAction_ConstructBuilding — advance build progress"
```

---

## Task 15: Integration Test — Full Worker Build Cycle (was Task 14)

**Files:**
- Create: `gol-project/tests/integration/flow/test_flow_worker_build.gd`

- [ ] **Step 1: Write the test**

End-to-end test: Worker NPC finds ghost, fetches material from stockpile, delivers it, then constructs. Verifies the ghost is replaced by a building entity.

```gdscript
class_name TestFlowWorkerBuildConfig
extends SceneConfig

const CStockpile = preload("res://scripts/components/c_stockpile.gd")
const CBuildSite = preload("res://scripts/components/c_build_site.gd")
const CBuilding = preload("res://scripts/components/c_building.gd")
const CWorker = preload("res://scripts/components/c_worker.gd")
const RWood = preload("res://scripts/resources/r_wood.gd")


func scene_name() -> String:
	return "test"


func systems() -> Variant:
	return [
		"res://scripts/systems/s_perception.gd",
		"res://scripts/systems/s_semantic_translation.gd",
		"res://scripts/systems/s_ai.gd",
		"res://scripts/systems/s_move.gd",
		"res://scripts/systems/s_build_site_complete.gd",
	]


func enable_pcg() -> bool:
	return false


func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "TestPlayer",
			"components": {
				"CTransform": { "position": Vector2(500, 500) },
			},
		},
		{
			"recipe": "camp_stockpile",
			"name": "CampStockpile",
			"components": {
				"CTransform": { "position": Vector2(0, 0) },
				"CStockpile": { "contents": {RWood: 10} },
			},
		},
		{
			"recipe": "npc_worker",
			"name": "TestWorker",
			"components": {
				"CTransform": { "position": Vector2(0, 0) },
				"CSemanticTranslation": {},
			},
		},
		{
			"recipe": "ghost_building",
			"name": "TestGhost",
			"components": {
				"CTransform": { "position": Vector2(50, 0) },
				"CBuildSite": {
					"building_id": "campfire",
					"required_materials": {RWood: 2},
					"build_duration": 0.5,
				},
			},
		},
	]


func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	await world.get_tree().process_frame

	var stockpile_entity: Entity = _find_entity(world, "CampStockpile")
	var worker: Entity = _find_entity(world, "TestWorker")
	var ghost: Entity = _find_entity(world, "TestGhost")

	result.assert_true(stockpile_entity != null, "Stockpile entity exists")
	result.assert_true(worker != null, "Worker entity exists")
	result.assert_true(ghost != null, "Ghost entity exists")
	if stockpile_entity == null or worker == null or ghost == null:
		return result

	var stockpile: CStockpile = stockpile_entity.get_component(CStockpile)
	result.assert_equal(stockpile.get_amount(RWood), 10, "Initial: stockpile has 10 wood")

	var site: CBuildSite = ghost.get_component(CBuildSite)
	result.assert_true(site != null, "Ghost has CBuildSite")
	result.assert_equal(site.building_id, "campfire", "Ghost building_id is campfire")

	# Let GOAP worker run — delivery trips + construction
	# With 2 wood needed, short distances, and 0.5s build duration,
	# 30 seconds (1800 frames) should be more than enough
	await _wait_frames(world, 1800)

	# Ghost should be gone, building should exist
	var ghost_after: Entity = _find_entity(world, "TestGhost")
	result.assert_true(ghost_after == null or not is_instance_valid(ghost_after), "Ghost removed after build complete")

	var buildings: Array = ECS.world.query.with_all([CBuilding, CTransform]).execute()
	result.assert_true(buildings.size() >= 1, "At least one building entity exists")

	# Stockpile should have lost 2 wood (from 10 to 8)
	var wood_remaining: int = stockpile.get_amount(RWood)
	result.assert_true(wood_remaining <= 8, "Stockpile wood decreased (got %d, expected <= 8)" % wood_remaining)

	return result
```

- [ ] **Step 2: Run the test**

Run: `cd gol-project && godot --headless --scene-config tests/integration/flow/test_flow_worker_build.gd`

Expected: All assertions PASS. Ghost is removed, building entity created, stockpile decreased by 2 wood.

- [ ] **Step 3: Commit**

```bash
git add gol-project/tests/integration/flow/test_flow_worker_build.gd
git commit -m "test(building): add full worker build cycle integration test"
```

---

## Task 16: Input Action + SBuildOperation System (was Task 15)

**Files:**
- Modify: `gol-project/project.godot` — add "build_menu" input action
- Create: `gol-project/scripts/systems/s_build_operation.gd`

- [ ] **Step 1: Add input action**

In `gol-project/project.godot`, under the `[input]` section, add:

```
build_menu={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":66,"key_label":0,"unicode":98,"location":0,"echo":false,"script":null)
]
}
```

(physical_keycode=66 is KEY_B, unicode=98 is 'b')

- [ ] **Step 2: Create SBuildOperation system**

```gdscript
class_name SBuildOperation
extends System
## Player building interaction system.
## State machine: IDLE → MENU → PLACING
## Handles: building quickbar toggle, ghost preview, ghost placement, ghost cancel.

const CBuildSite = preload("res://scripts/components/c_build_site.gd")
const CBuilding = preload("res://scripts/components/c_building.gd")

const TILE_SIZE: float = 32.0
const CANCEL_RANGE: float = 48.0
const CANCEL_RANGE_SQ: float = CANCEL_RANGE * CANCEL_RANGE
const VALID_COLOR: Color = Color(0.5, 1.0, 0.5, 0.4)
const INVALID_COLOR: Color = Color(1.0, 0.5, 0.5, 0.4)
const GHOST_MODULATE: Color = Color(1, 1, 1, 0.5)

enum State { IDLE, MENU, PLACING }

var _state: State = State.IDLE
var _selected_building_id: String = ""
var _preview_sprite: Sprite2D = null


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CPlayer, CTransform])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		return
	var player: Entity = entities[0]
	var player_transform := player.get_component(CTransform) as CTransform
	if player_transform == null:
		return

	match _state:
		State.IDLE:
			_process_idle(player, player_transform)
		State.MENU:
			_process_menu()
		State.PLACING:
			_process_placing(player_transform)


func _process_idle(player: Entity, player_transform: CTransform) -> void:
	if Input.is_action_just_pressed("build_menu"):
		_state = State.MENU
		return

	# Cancel ghost: interact near a ghost entity
	if Input.is_action_just_pressed("interact"):
		var nearest_ghost := _find_nearest_ghost(player_transform.position, CANCEL_RANGE_SQ)
		if nearest_ghost != null:
			_cancel_ghost(nearest_ghost)


func _process_menu() -> void:
	# Building selection via direct key events (no input map actions for number keys)
	var building_ids: Array = GOL.Tables.building().get_all_ids()
	if Input.is_physical_key_pressed(KEY_1) and building_ids.size() >= 1:
		_selected_building_id = building_ids[0]
		_state = State.PLACING
		return
	if Input.is_physical_key_pressed(KEY_2) and building_ids.size() >= 2:
		_selected_building_id = building_ids[1]
		_state = State.PLACING
		return

	if Input.is_action_just_pressed("build_menu") or Input.is_action_just_pressed("pause"):
		_state = State.IDLE
		_cleanup_preview()


func _process_placing(player_transform: CTransform) -> void:
	var grid_pos: Vector2 = _snap_to_grid(player_transform.position)

	# Update preview visual
	_update_preview(grid_pos)

	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("player_fire"):
		if _is_valid_placement(grid_pos):
			_place_ghost(grid_pos)
			_state = State.IDLE
			_cleanup_preview()
			return

	if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("build_menu"):
		_state = State.IDLE
		_cleanup_preview()


func _place_ghost(position: Vector2) -> void:
	var building_data: Dictionary = GOL.Tables.building().get_building(_selected_building_id)
	if building_data.is_empty():
		return

	var ghost: Entity = ServiceContext.recipe().create_entity_by_id("ghost_building")
	if ghost == null:
		return

	# Set position
	var ghost_transform := ghost.get_component(CTransform) as CTransform
	if ghost_transform:
		ghost_transform.position = position

	# Populate CBuildSite from BuildingTable
	var site: CBuildSite = ghost.get_component(CBuildSite)
	if site:
		site.building_id = _selected_building_id
		site.required_materials = building_data.get("required_materials", {}).duplicate()
		site.build_duration = float(building_data.get("build_duration", 3.0))

	# Set ghost sprite texture
	var sprite := ghost.get_component(CSprite) as CSprite
	if sprite:
		sprite.modulate = GHOST_MODULATE


func _cancel_ghost(ghost: Entity) -> void:
	var site: CBuildSite = ghost.get_component(CBuildSite)
	if site:
		# Drop deposited materials as pickup entities
		var ghost_transform := ghost.get_component(CTransform) as CTransform
		var drop_pos: Vector2 = ghost_transform.position if ghost_transform else Vector2.ZERO
		_drop_materials(site.deposited_materials, drop_pos)

	cmd.remove_entity(ghost)


func _drop_materials(materials: Dictionary, position: Vector2) -> void:
	# Spawn resource pickup entities for each deposited material type
	for res_type in materials:
		var amount: int = int(materials[res_type])
		if amount <= 0:
			continue
		# Use existing resource pickup entity spawning pattern
		# For now, log a warning — full pickup spawning requires knowing
		# which recipe_id maps to which resource type (e.g., "wood_pile" for RWood)
		push_warning("[SBuildOperation] TODO: spawn %d x %s pickup at %s" % [amount, str(res_type), str(position)])


func _find_nearest_ghost(position: Vector2, range_sq: float) -> Entity:
	var candidates: Array = ECS.world.query.with_all([CBuildSite, CTransform]).execute()
	var nearest: Entity = null
	var nearest_dist_sq: float = range_sq

	for cand in candidates:
		if cand == null or not is_instance_valid(cand):
			continue
		var cand_transform: CTransform = cand.get_component(CTransform)
		var dist_sq: float = position.distance_squared_to(cand_transform.position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = cand

	return nearest


func _snap_to_grid(position: Vector2) -> Vector2:
	return Vector2(
		roundf(position.x / TILE_SIZE) * TILE_SIZE,
		roundf(position.y / TILE_SIZE) * TILE_SIZE,
	)


func _is_valid_placement(position: Vector2) -> bool:
	# Check no existing building or ghost at this grid cell
	var check_range_sq: float = (TILE_SIZE * 0.5) * (TILE_SIZE * 0.5)
	var buildings: Array = ECS.world.query.with_all([CBuilding, CTransform]).execute()
	for b in buildings:
		var bt: CTransform = b.get_component(CTransform)
		if bt and bt.position.distance_squared_to(position) < check_range_sq:
			return false

	var ghosts: Array = ECS.world.query.with_all([CBuildSite, CTransform]).execute()
	for g in ghosts:
		var gt: CTransform = g.get_component(CTransform)
		if gt and gt.position.distance_squared_to(position) < check_range_sq:
			return false

	return true


func _update_preview(_position: Vector2) -> void:
	# Placement preview visual — to be implemented with UI layer
	# For now, the ghost is placed directly without a preview sprite
	pass


func _cleanup_preview() -> void:
	if _preview_sprite and is_instance_valid(_preview_sprite):
		_preview_sprite.queue_free()
		_preview_sprite = null
	_selected_building_id = ""
```

- [ ] **Step 3: Commit**

```bash
git add gol-project/project.godot gol-project/scripts/systems/s_build_operation.gd
git commit -m "feat(building): add SBuildOperation system + build_menu input action (B key)"
```

---

## Task 17: Polish & Edge Cases (was Task 16)

**Files:**
- Modify: `gol-project/scripts/systems/s_build_operation.gd` (if _drop_materials TODO needs resolution)
- Review all new files for consistency

- [ ] **Step 1: Review _drop_materials**

The `_drop_materials` function in `SBuildOperation` has a TODO for spawning pickup entities. Check how existing pickup drops work (e.g., `CLootDrop` in `SDead`) and implement. If the project doesn't have a simple "spawn pickup by resource type" utility yet, leave the `push_warning` for now — this is a v1 edge case (player cancels ghost with partially delivered materials) that can be addressed in a fast follow-up.

- [ ] **Step 2: Run all existing tests**

Run: `cd gol-project && godot --headless --run-tests`

Expected: All existing tests still pass. No regressions from new components/systems.

- [ ] **Step 3: Run building-specific tests**

Run: `cd gol-project && godot --headless --scene-config tests/integration/flow/test_flow_build_site_complete.gd`
Run: `cd gol-project && godot --headless --scene-config tests/integration/flow/test_flow_worker_build.gd`

Expected: Both tests PASS.

- [ ] **Step 4: Final commit if any polish changes were made**

```bash
git add -A
git commit -m "fix(building): polish edge cases and fix test issues"
```

---

## Dependency Graph

```
Task 1 (RStone) ──────────────────────────┐
Task 2 (CBuilding) ──────────┐            │
Task 3 (CBuildSite) ─────────┤            │
                              ├─ Task 4 (BuildingTable) ─── Task 5 (Recipes) ─┐
                              │                                                │
                              │                                                ├─ Task 6 (SBuildSiteComplete)
                              │                                                │         │
                              │                                                │         └─ Task 7 (Test: completion)
                              │                                                │
                              └─ Task 8 (GOAP Goal) ──────────────────────────┤
                                                                               │
Task 9  (FindBuildSite) ──────────────────────────────────────────────────────┤
Task 10 (MoveToBuildSite) ────────────────────────────────────────────────────┤
Task 11 (MoveToStockpileForBuild) ────────────────────────────────────────────┤
Task 12 (PickupBuildMaterial) ────────────────────────────────────────────────┤
Task 13 (DeliverBuildMaterial) ───────────────────────────────────────────────┤
Task 14 (ConstructBuilding) ──────────────────────────────────────────────────┤
                                                                               │
                                                                               ├─ Task 15 (Test: full cycle)
                                                                               │
                                                                               └─ Task 16 (SBuildOperation + input)
                                                                                         │
                                                                                         └─ Task 17 (Polish)
```

**Parallelizable groups:**
- Tasks 1, 2, 3 can be done in parallel (no dependencies)
- Tasks 9, 10, 11, 12, 13, 14 can be done in parallel (all independent GOAP actions)
- Task 4 depends on 1+2+3; Task 5 depends on 4; Task 6 depends on 5
- Task 7 depends on 6; Task 15 depends on 6+8+9+10+11+12+13+14
- Task 16 depends on 5+4; Task 17 depends on everything
