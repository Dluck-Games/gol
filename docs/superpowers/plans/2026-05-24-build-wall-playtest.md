# Build Wall Playtest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an automated playtest that verifies the end-to-end building construction flow — a worker picks up wood from a stockpile, delivers it to a Wall BuildSite, and completes construction.

**Architecture:** Follow the existing night raid playtest pattern — extend `AutomationPlayTestSuite`, use sequential checkpoints to validate the worker BuildTask FSM at each stage. Direct entity spawning via `ServiceContext.recipe()` and `CTaskQueue.get_or_create()`.

**Tech Stack:** GDScript, Godot 4.6, GECS (ECS addon), AutomationPlayTestSuite

---

### Task 1: Create playtest file with constants, entity setup, and BuildSite spawning

**Files:**
- Create: `gol-project/tests/playtest/playtest_build_wall.gd`

- [ ] **Step 1: Create the playtest file with full setup code**

```gdscript
class_name PlaytestBuildWall
extends AutomationPlayTestSuite

const RWood := preload("res://scripts/resources/r_wood.gd")

const GRID_SIZE: int = 20
const PLAYER_CELL := Vector2i(10, 10)
const STOCKPILE_CELL := Vector2i(11, 10)
const WORKER_CELL := Vector2i(9, 10)
const BUILD_SITE_CELL := Vector2i(12, 10)
const SETUP_DELAY: float = 3.0
const COMPLETION_DELAY: float = 3.0

const CHECKPOINTS: Array[String] = [
	"build_site_created",
	"worker_assigned",
	"worker_moving_to_stockpile",
	"material_picked_up",
	"worker_moving_to_site",
	"material_delivered",
	"construction_started",
	"building_completed",
]

var _build_site_entity: Entity = null
var _build_site_spawned: bool = false
var _completion_delay_start: float = -1.0


func suite_name() -> String:
	return "build_wall"


func timeout_seconds() -> float:
	return 90.0


func scene_name() -> String:
	return "test"


func enable_pcg() -> bool:
	return true


func pcg_config() -> PCGConfig:
	var config := super.pcg_config()
	config.preset = PCGConfig.Preset.FLAT_GRASS
	config.preset_grid_size = GRID_SIZE
	return config


func initial_campfire_position() -> Vector2:
	return _grid_to_world(PLAYER_CELL)


func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "Player",
			"components": {
				"CTransform": {"position": _grid_to_world(PLAYER_CELL)},
			},
		},
		{
			"recipe": "camp_stockpile",
			"name": "TestStockpile",
			"components": {
				"CTransform": {"position": _grid_to_world(STOCKPILE_CELL)},
				"CStockpile": {"contents": {RWood: 3}},
			},
		},
		{
			"recipe": "npc_worker",
			"name": "TestWorker",
			"components": {
				"CTransform": {"position": _grid_to_world(WORKER_CELL)},
			},
		},
	]


func after_entities_spawned(world: GOLWorld) -> void:
	super.after_entities_spawned(world)
	_build_site_entity = null
	_build_site_spawned = false
	_completion_delay_start = -1.0
	if GOL != null and GOL.Game != null:
		GOL.Game.campfire_position = initial_campfire_position()


func setup_checkpoints() -> void:
	for checkpoint in CHECKPOINTS:
		register_checkpoint(checkpoint)


func check_next_checkpoint(world: GOLWorld) -> bool:
	if not _build_site_spawned:
		if _elapsed_seconds() < SETUP_DELAY:
			return false
		_spawn_build_site()
		_build_site_spawned = true

	match current_checkpoint_name():
		"build_site_created":
			return _check_build_site_created()
		"worker_assigned":
			return _check_worker_assigned(world)
		"worker_moving_to_stockpile":
			return _check_worker_state(world, BuildTask.State.MOVING_TO_STOCKPILE)
		"material_picked_up":
			return _check_material_picked_up(world)
		"worker_moving_to_site":
			return _check_worker_state(world, BuildTask.State.MOVING_TO_SITE)
		"material_delivered":
			return _check_material_delivered()
		"construction_started":
			return _check_worker_state(world, BuildTask.State.CONSTRUCTING)
		"building_completed":
			return _check_building_completed(world)
	return false


func test_run(world: GOLWorld) -> Variant:
	if _start_msec <= 0:
		_start_msec = Time.get_ticks_msec()
	if _checkpoints.is_empty():
		_mark_error("No checkpoints registered")
		_finish(world)
		return _to_test_result()

	while not all_checkpoints_passed():
		if _elapsed_seconds() > timeout_seconds():
			_mark_error("Timed out waiting for checkpoint: %s" % current_checkpoint_name())
			break
		if check_next_checkpoint(world):
			var checkpoint_name := current_checkpoint_name()
			if not checkpoint_name.is_empty():
				pass_checkpoint(checkpoint_name)
		await _wait_frames(world, 1)

	if all_checkpoints_passed():
		_status = Status.PASSED
		_status_detail = ""
		_completion_delay_start = _elapsed_seconds()
		while _elapsed_seconds() - _completion_delay_start < COMPLETION_DELAY:
			await _wait_frames(world, 1)
	elif _status == Status.RUNNING:
		_status = Status.FAILED
		_status_detail = "Checkpoint failed: %s" % current_checkpoint_name()

	_finish(world)
	return _to_test_result()
```

- [ ] **Step 2: Commit the skeleton**

```bash
cd gol-project
git add tests/playtest/playtest_build_wall.gd
git commit -m "feat(playtest): add build_wall playtest skeleton"
```

---

### Task 2: Implement checkpoint check methods

**Files:**
- Modify: `gol-project/tests/playtest/playtest_build_wall.gd` — append helper methods

> **2026-05-24 errata:** The direct `ghost_building` construction below was the wrong pattern. The implemented playtest should reuse the production `SBuildOperation._place_ghost()` path instead: get the system from the real world, set `_selected_building_id = "wall"`, call `_place_ghost(_grid_to_world(BUILD_SITE_CELL))`, then discover the created build site for checkpoint tracking. This preserves BuildingTable lookup, `CSprite` texture/offset initialization, placeholder texture fallback, `PLACED_GHOST_MODULATE`, and `BuildTask` submission. Do not copy the manual `CBuildSite` setup except for a test that explicitly validates recipe construction.

- [ ] **Step 1: Add all checkpoint check methods and helpers**

Append these methods to the `PlaytestBuildWall` class:

```gdscript
func _spawn_build_site() -> void:
	var ghost: Entity = ServiceContext.recipe().create_entity_by_id("ghost_building")
	if ghost == null:
		push_error("PlaytestBuildWall: failed to create ghost_building entity")
		return
	var transform := ghost.get_component(CTransform) as CTransform
	if transform != null:
		transform.position = _grid_to_world(BUILD_SITE_CELL)
	var site := ghost.get_component(CBuildSite) as CBuildSite
	if site != null:
		site.building_id = "wall"
		site.required_materials = {RWood: 3}
		site.build_duration = 4.0
	ghost.name = "TestBuildSite"
	_build_site_entity = ghost
	if site == null:
		return
	var queue := CTaskQueue.get_or_create()
	if queue != null:
		var task := BuildTask.new(ghost)
		task.needed_material = RWood
		queue.submit(task)
		site.build_task_submitted = true


func _check_build_site_created() -> bool:
	if _build_site_entity == null or not is_instance_valid(_build_site_entity):
		return false
	var site := _build_site_entity.get_component(CBuildSite) as CBuildSite
	return site != null and site.building_id == "wall"


func _check_worker_assigned(world: GOLWorld) -> bool:
	var worker := _find_entity(world, "TestWorker")
	if worker == null:
		return false
	var worker_task := worker.get_component(CWorkerTask) as CWorkerTask
	if worker_task == null or worker_task.current_task == null:
		return false
	var task := worker_task.current_task as BuildTask
	return task != null and task.target_entity == _build_site_entity


func _check_worker_state(world: GOLWorld, expected_state: BuildTask.State) -> bool:
	var worker := _find_entity(world, "TestWorker")
	if worker == null:
		return false
	var worker_task := worker.get_component(CWorkerTask) as CWorkerTask
	if worker_task == null or worker_task.current_task == null:
		return false
	var task := worker_task.current_task as BuildTask
	return task != null and task.state == expected_state


func _check_material_picked_up(world: GOLWorld) -> bool:
	var worker := _find_entity(world, "TestWorker")
	if worker == null:
		return false
	var worker_task := worker.get_component(CWorkerTask) as CWorkerTask
	if worker_task == null or worker_task.current_task == null:
		return false
	var task := worker_task.current_task as BuildTask
	if task == null:
		return false
	return task.state >= BuildTask.State.MOVING_TO_SITE


func _check_material_delivered() -> bool:
	if _build_site_entity == null or not is_instance_valid(_build_site_entity):
		return false
	var site := _build_site_entity.get_component(CBuildSite) as CBuildSite
	if site == null:
		return false
	return site.materials_complete


func _check_building_completed(world: GOLWorld) -> bool:
	if _build_site_entity != null and is_instance_valid(_build_site_entity):
		return false
	var build_pos := _grid_to_world(BUILD_SITE_CELL)
	for entity: Entity in world.entities:
		if entity == null or not is_instance_valid(entity):
			continue
		if not entity.has_component(CBuilding):
			continue
		var transform := entity.get_component(CTransform) as CTransform
		if transform == null:
			continue
		if transform.position.distance_to(build_pos) < 1.0:
			var building := entity.get_component(CBuilding) as CBuilding
			return building != null and building.building_id == "wall"
	return false


func _find_entity(world: GOLWorld, entity_name: String) -> Entity:
	if world == null:
		return null
	for entity: Entity in world.entities:
		if entity != null and is_instance_valid(entity) and entity.name == entity_name:
			return entity
	return null


func _grid_to_world(cell: Vector2i) -> Vector2:
	var map := ServiceContext.map()
	if map != null:
		return map.grid_to_world(cell)
	var half_w := float(Service_Map.TILE_WIDTH) * 0.5
	var half_h := float(Service_Map.TILE_HEIGHT) * 0.5
	return Vector2((float(cell.x) - float(cell.y)) * half_w + half_w, (float(cell.x) + float(cell.y)) * half_h + half_h)
```

- [ ] **Step 2: Commit checkpoint implementation**

```bash
cd gol-project
git add tests/playtest/playtest_build_wall.gd
git commit -m "feat(playtest): implement build_wall checkpoint checks"
```

---

### Task 3: Run the playtest and verify

- [ ] **Step 1: Run the playtest**

```bash
gol test playtest --suite build_wall
```

Expected: All 8 checkpoints pass, status PASSED, test completes within 90 seconds.

- [ ] **Step 2: Run with recording for visual verification**

```bash
gol test playtest --suite build_wall --record
```

Expected: Recording shows 3-second empty ground, then BuildSite appears, worker moves to stockpile, picks up wood, delivers to site, constructs wall, 3-second freeze on completed wall.

- [ ] **Step 3: Fix any issues found during test run**

If any checkpoint fails or times out, investigate the worker FSM state machine and adjust checkpoint conditions. Common issues:
- Worker GOAP not picking up the task → check if GOAP agent goals include "work"
- Material type mismatch → verify RWood script path matches what BuildTask expects
- BuildSite not being detected as complete → verify CBuildSite.deposit() is called correctly by SBuildWorker

---

### Task 4: Final commit and submodule update

- [ ] **Step 1: Push gol-project changes**

```bash
cd gol-project
git push origin main
```

- [ ] **Step 2: Update management repo submodule pointer**

```bash
cd /Users/dluck/Documents/GitHub/gol
git add gol-project
git commit -m "chore: update gol-project submodule (add build_wall playtest)"
git push origin main
```
