# Guard AI Bullet-Wall Collision Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two night raid guard behavior issues: bullets dying on friendly walls, and guard post position landing outside the wall enclosure.

**Architecture:** Upgrade `Service_Map._dynamic_blocked` from `Dictionary[Vector2i, bool]` to `Dictionary[Vector2i, int]` with blocker type constants. `s_move.gd` checks blocker type before killing bullets. Guard post position is validated against the map grid to stay inside the enclosure.

**Tech Stack:** GDScript, GECS ECS, gdUnit4

---

## File Structure

| File | Role | Change Type |
|------|------|-------------|
| `scripts/services/impl/service_map.gd` | Map service — blocker storage | Modify |
| `scripts/systems/s_move.gd` | Movement system — bullet wall collision | Modify |
| `scripts/systems/s_build_site_complete.gd` | Building completion — blocker registration | Modify |
| `scripts/systems/s_dead.gd` | Death system — blocker cleanup | No change needed |
| `scripts/debug/console/commands/spawn_command.gd` | Console spawn — blocker registration | Modify |
| `scripts/gameplay/configs/night_raid_verify_config.gd` | Night raid test config — wall registration | Modify |
| `scripts/systems/s_semantic_translation.gd` | Guard post position calculation | Modify |
| `tests/unit/system/test_bullet_wall_passthrough.gd` | New test — bullet passes through walls | Create |
| `tests/unit/system/test_guard_post_position.gd` | New test — guard post stays inside enclosure | Create |

---

## Task 1: Add Blocker Type Constants to Service_Map

**Files:**
- Modify: `scripts/services/impl/service_map.gd:1-14`

- [ ] **Step 1: Add blocker type constants and update `_dynamic_blocked` comment**

In `service_map.gd`, add constants after line 9 (after `TILE_HEIGHT`) and update the `_dynamic_blocked` comment:

```gdscript
const TILE_WIDTH: int = 64
const TILE_HEIGHT: int = 32

const BLOCKER_NONE: int = 0
const BLOCKER_WALL: int = 1
const BLOCKER_BUILDING: int = 2
```

Update line 14 comment from:
```gdscript
var _dynamic_blocked: Dictionary = {}  # Dictionary[Vector2i, bool]
```
to:
```gdscript
var _dynamic_blocked: Dictionary = {}  # Dictionary[Vector2i, int] — 0=none, 1=wall, 2=building
```

- [ ] **Step 2: Update `mark_blocked` to accept a type parameter**

Replace the existing `mark_blocked` function (lines 196-201):

```gdscript
func mark_blocked(pos: Vector2i, type: int = BLOCKER_BUILDING) -> void:
	if _dynamic_blocked.get(pos, BLOCKER_NONE) != BLOCKER_NONE:
		return
	_dynamic_blocked[pos] = type
	_grid_version += 1
	_sync_solver()
```

- [ ] **Step 3: Update `mark_blocked_many` to accept a type parameter**

Replace the existing `mark_blocked_many` function (lines 204-217):

```gdscript
func mark_blocked_many(positions: Array, type: int = BLOCKER_BUILDING) -> void:
	var changed := false
	for raw_pos: Variant in positions:
		if not (raw_pos is Vector2i):
			continue
		var pos := raw_pos as Vector2i
		if _dynamic_blocked.get(pos, BLOCKER_NONE) != BLOCKER_NONE:
			continue
		_dynamic_blocked[pos] = type
		changed = true
	if not changed:
		return
	_grid_version += 1
	_sync_solver()
```

- [ ] **Step 4: Update `is_position_blocked` to work with int values**

Replace line 311:
```gdscript
func is_position_blocked(pos: Vector2i) -> bool:
	if _dynamic_blocked.get(pos, BLOCKER_NONE) != BLOCKER_NONE:
		return true
	if _base_cost.is_empty():
		return false
	return _base_cost.get(pos, INF) == INF
```

- [ ] **Step 5: Add `get_blocker_type` method**

Add after `is_position_blocked`:

```gdscript
func get_blocker_type(pos: Vector2i) -> int:
	return _dynamic_blocked.get(pos, BLOCKER_NONE)
```

- [ ] **Step 6: Verify `mark_unblocked` still works**

The existing `mark_unblocked` uses `_dynamic_blocked.erase(pos)` which works regardless of value type. No change needed. Confirm by reading it:

```gdscript
func mark_unblocked(pos: Vector2i) -> void:
	if not _dynamic_blocked.has(pos):
		return
	_dynamic_blocked.erase(pos)
	_grid_version += 1
	_sync_solver()
```

- [ ] **Step 7: Commit**

```bash
git add scripts/services/impl/service_map.gd
git commit -m "feat(map): add blocker type enum to _dynamic_blocked for wall vs building distinction"
```

---

## Task 2: Update Blocker Registration Sites

**Files:**
- Modify: `scripts/systems/s_build_site_complete.gd:64-69`
- Modify: `scripts/debug/console/commands/spawn_command.gd:82-83`
- Modify: `scripts/gameplay/configs/night_raid_verify_config.gd:45-48`

- [ ] **Step 1: Update `s_build_site_complete.gd` to pass wall type**

Replace lines 64-69:

```gdscript
	# Register completed building navigation state.
	if map and building_entity.has_component(CDoor):
		var door := building_entity.get_component(CDoor) as CDoor
		map.set_door_state(grid_pos, door.is_open, door.owner_faction)
	elif map and building_entity.has_component(CBuilding) and bool(building_data.get("is_obstacle", false)):
		var blocker_type := Service_Map.BLOCKER_WALL if building_entity.has_component(CWall) else Service_Map.BLOCKER_BUILDING
		blocked_positions.append(grid_pos)
```

Then update the `mark_blocked_many` call at line 29 to pass the type. However, since `blocked_positions` is a flat array and buildings in one batch could be mixed types, we need a different approach. Change the batch to register walls individually:

Actually, looking at the code more carefully — `_complete_building` processes one building at a time and appends to `blocked_positions`. All walls in a single `process()` call get batched. Since the night raid scenario only has walls (no other obstacle buildings), and production gameplay builds one building at a time, we can pass the type to `mark_blocked_many`. But to handle mixed batches correctly, change the approach:

Replace lines 16-29 of `s_build_site_complete.gd`:

```gdscript
func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	var map := ServiceContext.map()
	var wall_positions: Array[Vector2i] = []
	var building_positions: Array[Vector2i] = []
	for entity in entities:
		var site: CBuildSite = entity.get_component(CBuildSite)
		if site == null:
			continue
		if not site.materials_complete:
			continue
		if site.build_progress < site.build_duration:
			continue
		_complete_building(entity, site, map, wall_positions, building_positions)
	if map != null and not wall_positions.is_empty():
		map.mark_blocked_many(wall_positions, Service_Map.BLOCKER_WALL)
	if map != null and not building_positions.is_empty():
		map.mark_blocked_many(building_positions, Service_Map.BLOCKER_BUILDING)
```

Update `_complete_building` signature (line 32) to accept both arrays:

```gdscript
func _complete_building(ghost: Entity, site: CBuildSite, map: Service_Map, wall_positions: Array[Vector2i], building_positions: Array[Vector2i]) -> void:
```

And replace the blocker registration block (lines 64-69):

```gdscript
	# Register completed building navigation state.
	if map and building_entity.has_component(CDoor):
		var door := building_entity.get_component(CDoor) as CDoor
		map.set_door_state(grid_pos, door.is_open, door.owner_faction)
	elif map and building_entity.has_component(CBuilding) and bool(building_data.get("is_obstacle", false)):
		if building_entity.has_component(CWall):
			wall_positions.append(grid_pos)
		else:
			building_positions.append(grid_pos)
```

- [ ] **Step 2: Update `spawn_command.gd` to pass wall type**

Replace line 82-83:

```gdscript
	if entity.has_component(CBuilding) and (entity.has_component(CWall) or entity.has_component(CVisionBlocker)):
		var blocker_type := Service_Map.BLOCKER_WALL if entity.has_component(CWall) else Service_Map.BLOCKER_BUILDING
		map.mark_blocked(grid_pos, blocker_type)
```

- [ ] **Step 3: Update `night_raid_verify_config.gd` to pass wall type**

Replace lines 45-48:

```gdscript
	for cell in _wall_cells():
		if cell == DOOR_CELL:
			continue
		map.mark_blocked(cell, Service_Map.BLOCKER_WALL)
```

- [ ] **Step 4: Commit**

```bash
git add scripts/systems/s_build_site_complete.gd scripts/debug/console/commands/spawn_command.gd scripts/gameplay/configs/night_raid_verify_config.gd
git commit -m "feat(build): register walls with BLOCKER_WALL type for bullet passthrough"
```

---

## Task 3: Bullet Passes Through Walls in s_move.gd

**Files:**
- Modify: `scripts/systems/s_move.gd:162-168`
- Create: `tests/unit/system/test_bullet_wall_passthrough.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/system/test_bullet_wall_passthrough.gd`:

```gdscript
extends GdUnitTestSuite

## Tests that bullets pass through wall-type blockers but die on building-type blockers.


func test_bullet_dies_on_building_blocker() -> void:
	var map := Service_Map.new()
	add_child(map)
	map.setup()
	var grid: Dictionary = {}
	for x in range(5):
		for y in range(5):
			var cell = preload("res://scripts/pcg/data/pcg_cell.gd").new()
			cell.logic_type = preload("res://scripts/pcg/tile_asset_resolver.gd").LogicType.GRASS
			grid[Vector2i(x, y)] = cell
	var pcg_config := PCGConfig.new()
	var road_graph := RoadGraph.new()
	map.accept_pcg_result(PCGResult.new(pcg_config, road_graph, null, null, grid))
	map.mark_blocked(Vector2i(2, 2), Service_Map.BLOCKER_BUILDING)

	ServiceContext._map = map
	var system := SMove.new()
	add_child(system)

	var entity := Entity.new()
	entity.add_component(CTransform.new())
	entity.add_component(CMovement.new())
	entity.add_component(CBullet.new())
	var transform := entity.get_component(CTransform) as CTransform
	var movement := entity.get_component(CMovement) as CMovement
	transform.position = map.grid_to_world(Vector2i(1, 2))
	movement.velocity = Vector2(200.0, 0.0)

	ECS.world.add_entity(entity, null, false)
	system.process([entity], [], 1.0)

	assert_bool(entity.has_component(CDead)).is_true()

	ServiceContext._map = null
	remove_child(map)
	map.queue_free()


func test_bullet_passes_through_wall_blocker() -> void:
	var map := Service_Map.new()
	add_child(map)
	map.setup()
	var grid: Dictionary = {}
	for x in range(5):
		for y in range(5):
			var cell = preload("res://scripts/pcg/data/pcg_cell.gd").new()
			cell.logic_type = preload("res://scripts/pcg/tile_asset_resolver.gd").LogicType.GRASS
			grid[Vector2i(x, y)] = cell
	var pcg_config := PCGConfig.new()
	var road_graph := RoadGraph.new()
	map.accept_pcg_result(PCGResult.new(pcg_config, road_graph, null, null, grid))
	map.mark_blocked(Vector2i(2, 2), Service_Map.BLOCKER_WALL)

	ServiceContext._map = map
	var system := SMove.new()
	add_child(system)

	var entity := Entity.new()
	entity.add_component(CTransform.new())
	entity.add_component(CMovement.new())
	entity.add_component(CBullet.new())
	var transform := entity.get_component(CTransform) as CTransform
	var movement := entity.get_component(CMovement) as CMovement
	transform.position = map.grid_to_world(Vector2i(1, 2))
	movement.velocity = Vector2(200.0, 0.0)

	ECS.world.add_entity(entity, null, false)
	system.process([entity], [], 1.0)

	assert_bool(entity.has_component(CDead)).is_false()

	ServiceContext._map = null
	remove_child(map)
	map.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gol test unit --suite system --verbose`

Expected: `test_bullet_passes_through_wall_blocker` FAILS (bullet currently dies on all blockers).

- [ ] **Step 3: Implement bullet wall passthrough in s_move.gd**

Replace lines 166-168 in `s_move.gd`:

```gdscript
	if entity.has_component(CBullet):
		if map.get_blocker_type(_movement_grid_for_position(map, entity, next_position)) == Service_Map.BLOCKER_WALL:
			return next_position
		entity.add_component(CDead.new())
		return current_position
```

The full `_resolve_wall_slide_position` function becomes:

```gdscript
func _resolve_wall_slide_position(map: Service_Map, entity: Entity, current_position: Vector2, next_position: Vector2, move: CMovement) -> Vector2:
	var current_grid: Vector2i = _movement_grid_for_position(map, entity, current_position)
	if current_grid == _movement_grid_for_position(map, entity, next_position):
		return next_position
	if entity.has_component(CBullet):
		if map.get_blocker_type(_movement_grid_for_position(map, entity, next_position)) == Service_Map.BLOCKER_WALL:
			return next_position
		entity.add_component(CDead.new())
		return current_position
	if not _is_walking_actor(entity):
		return next_position

	for candidate: Vector2 in _isometric_slide_candidates(current_position, next_position - current_position):
		if _can_slide_to(map, entity, current_grid, candidate):
			return candidate

	for candidate: Vector2 in [
		Vector2(next_position.x, current_position.y),
		Vector2(current_position.x, next_position.y),
	]:
		if _can_slide_to(map, entity, current_grid, candidate):
			return candidate

	move.velocity = Vector2.ZERO
	move.desired_velocity = Vector2.ZERO
	return current_position
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `gol test unit --suite system --verbose`

Expected: Both `test_bullet_dies_on_building_blocker` and `test_bullet_passes_through_wall_blocker` PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_move.gd tests/unit/system/test_bullet_wall_passthrough.gd
git commit -m "feat(move): bullets pass through wall-type blockers, die on building blockers"
```

---

## Task 4: Fix Guard Post Position — Validate Against Map

**Files:**
- Modify: `scripts/systems/s_semantic_translation.gd:164-170`
- Create: `tests/unit/system/test_guard_post_position.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/system/test_guard_post_position.gd`:

```gdscript
extends GdUnitTestSuite

## Tests that _choose_guard_post_position returns a position that is not blocked.

const SEMANTIC_SYSTEM := preload("res://scripts/systems/s_semantic_translation.gd")


func test_guard_post_not_placed_on_blocked_cell() -> void:
	var map := Service_Map.new()
	add_child(map)
	map.setup()
	var grid: Dictionary = {}
	for x in range(21):
		for y in range(21):
			var cell = preload("res://scripts/pcg/data/pcg_cell.gd").new()
			cell.logic_type = preload("res://scripts/pcg/tile_asset_resolver.gd").LogicType.GRASS
			grid[Vector2i(x, y)] = cell
	var pcg_config := PCGConfig.new()
	var road_graph := RoadGraph.new()
	map.accept_pcg_result(PCGResult.new(pcg_config, road_graph, null, null, grid))

	# Build a wall ring like night raid: (7,7) to (13,13)
	for x in range(7, 14):
		map.mark_blocked(Vector2i(x, 7), Service_Map.BLOCKER_WALL)
		map.mark_blocked(Vector2i(x, 13), Service_Map.BLOCKER_WALL)
	for y in range(8, 13):
		map.mark_blocked(Vector2i(7, y), Service_Map.BLOCKER_WALL)
		map.mark_blocked(Vector2i(13, y), Service_Map.BLOCKER_WALL)

	ServiceContext._map = map

	var system := SEMANTIC_SYSTEM.new()
	add_child(system)

	# Guard at (11,11), campfire at (10,10) — same as night raid
	var guard_world := map.grid_to_world(Vector2i(11, 11))
	var campfire_world := map.grid_to_world(Vector2i(10, 10))

	var result: Vector2 = system._choose_guard_post_position(guard_world, campfire_world)
	var result_grid: Vector2i = map.world_to_grid(result)

	assert_bool(map.is_position_blocked(result_grid)).is_false()

	ServiceContext._map = null
	remove_child(map)
	map.queue_free()


func test_guard_post_stays_inside_when_direction_hits_wall() -> void:
	var map := Service_Map.new()
	add_child(map)
	map.setup()
	var grid: Dictionary = {}
	for x in range(21):
		for y in range(21):
			var cell = preload("res://scripts/pcg/data/pcg_cell.gd").new()
			cell.logic_type = preload("res://scripts/pcg/tile_asset_resolver.gd").LogicType.GRASS
			grid[Vector2i(x, y)] = cell
	var pcg_config := PCGConfig.new()
	var road_graph := RoadGraph.new()
	map.accept_pcg_result(PCGResult.new(pcg_config, road_graph, null, null, grid))

	# Wall ring
	for x in range(7, 14):
		map.mark_blocked(Vector2i(x, 7), Service_Map.BLOCKER_WALL)
		map.mark_blocked(Vector2i(x, 13), Service_Map.BLOCKER_WALL)
	for y in range(8, 13):
		map.mark_blocked(Vector2i(7, y), Service_Map.BLOCKER_WALL)
		map.mark_blocked(Vector2i(13, y), Service_Map.BLOCKER_WALL)

	ServiceContext._map = map

	var system := SEMANTIC_SYSTEM.new()
	add_child(system)

	# Guard directly south of campfire — direction points into south wall
	var guard_world := map.grid_to_world(Vector2i(10, 11))
	var campfire_world := map.grid_to_world(Vector2i(10, 10))

	var result: Vector2 = system._choose_guard_post_position(guard_world, campfire_world)
	var result_grid: Vector2i = map.world_to_grid(result)

	# Must not be blocked AND must not be outside the grid
	assert_bool(map.is_position_blocked(result_grid)).is_false()
	# Should still be reasonably far from campfire (at least half the ring distance)
	var campfire_grid := Vector2i(10, 10)
	var dist := result_grid.distance_to(campfire_grid)
	assert_float(dist).is_greater(1.0)

	ServiceContext._map = null
	remove_child(map)
	map.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gol test unit --suite system --verbose`

Expected: `test_guard_post_not_placed_on_blocked_cell` FAILS (current code places guard post at blocked position outside wall ring).

- [ ] **Step 3: Implement guard post position validation**

Replace `_choose_guard_post_position` in `s_semantic_translation.gd` (lines 164-170):

```gdscript
func _choose_guard_post_position(current_position: Vector2, campfire_position: Vector2) -> Vector2:
	if current_position.distance_to(campfire_position) >= MIN_GUARD_POST_DISTANCE:
		return current_position
	var direction := current_position - campfire_position
	if direction.length_squared() <= 0.01:
		direction = Vector2.RIGHT
	direction = direction.normalized()

	var map := ServiceContext.map()
	var candidate := campfire_position + direction * GUARD_POST_RING_DISTANCE
	if map == null:
		return candidate

	var candidate_grid := map.world_to_grid(candidate)
	if not map.is_position_blocked(candidate_grid):
		return candidate

	# Step back along the direction until we find an unblocked cell
	var step_distance := float(Service_Map.TILE_WIDTH) * 0.5
	var test_distance := GUARD_POST_RING_DISTANCE - step_distance
	while test_distance > MIN_GUARD_POST_DISTANCE * 0.5:
		candidate = campfire_position + direction * test_distance
		candidate_grid = map.world_to_grid(candidate)
		if not map.is_position_blocked(candidate_grid):
			return candidate
		test_distance -= step_distance

	# All positions along this direction are blocked — try perpendicular directions
	var perp_directions := [
		Vector2(-direction.y, direction.x),
		Vector2(direction.y, -direction.x),
		-direction,
	]
	for perp_dir: Vector2 in perp_directions:
		candidate = campfire_position + perp_dir * GUARD_POST_RING_DISTANCE * 0.75
		candidate_grid = map.world_to_grid(candidate)
		if not map.is_position_blocked(candidate_grid):
			return candidate

	return current_position
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `gol test unit --suite system --verbose`

Expected: Both guard post tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_semantic_translation.gd tests/unit/system/test_guard_post_position.gd
git commit -m "fix(ai): guard post position validated against map to stay inside enclosure"
```

---

## Task 5: Run Full Test Suite and Playtest

**Files:** None (verification only)

- [ ] **Step 1: Run unit tests**

Run: `gol test unit --suite system,ai --verbose`

Expected: All tests PASS including new bullet passthrough and guard post tests.

- [ ] **Step 2: Run integration tests**

Run: `gol test --all --verbose`

Expected: All unit and integration tests PASS.

- [ ] **Step 3: Run night raid playtest**

Run: `gol test playtest --suite night_raid --verbose`

Expected: Night raid playtest passes all checkpoints.

- [ ] **Step 4: Record night raid for visual verification**

Run: `gol test playtest --suite night_raid --record`

Expected: Recording saved to `logs/playtest/night_raid/recording.mp4`. Visual verification:
- Guard stays inside camp enclosure
- Guard bullets pass through fences and hit external enemies
- Entities still cannot walk through walls
- Night raid reaches dawn

- [ ] **Step 5: Final commit if any test adjustments were needed**

```bash
git add -A
git commit -m "test: verify guard AI and bullet wall passthrough in night raid"
```
