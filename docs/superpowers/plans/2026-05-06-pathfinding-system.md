# Pathfinding System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tile-based A* pathfinding to GOL via Service_Map extension, enabling NPCs to navigate around obstacles and players to be blocked by walls.

**Architecture:** Service_Map becomes the single source of truth for map data (refactored from current PCG dependency). PathSolver implements A* over the 200×200 isometric grid with 3-layer cost model. GOAP actions use path-following instead of straight-line movement. SMove adds wall-blocking with axis-sliding for all entities.

**Tech Stack:** Godot 4.x, GDScript, GECS 8.0.0, gdUnit4 (unit tests), SceneConfig (integration tests)

---

## File Structure

### New Files

| File | Responsibility |
|---|---|
| `gol-project/scripts/navigation/navigation_context.gd` | Request context (faction, permissions, tolerances) |
| `gol-project/scripts/navigation/path_result.gd` | Path result data (waypoints, cost, validity, version) |
| `gol-project/scripts/navigation/path_solver.gd` | A* algorithm + line-of-sight + Bresenham |
| `gol-project/tests/unit/navigation/test_path_solver.gd` | Unit tests for PathSolver |
| `gol-project/tests/unit/service/test_service_map_navigation.gd` | Unit tests for Service_Map navigation API |
| `gol-project/tests/integration/pathfinding/test_npc_pathfinds_around_wall.gd` | T1 |
| `gol-project/tests/integration/pathfinding/test_npc_direct_path_no_wall.gd` | T2 |
| `gol-project/tests/integration/pathfinding/test_npc_unreachable_target.gd` | T3 |
| `gol-project/tests/integration/pathfinding/test_player_blocked_by_wall.gd` | T4 |
| `gol-project/tests/integration/pathfinding/test_player_slides_along_wall.gd` | T5 |
| `gol-project/tests/integration/pathfinding/test_player_passes_open_door.gd` | T6-T7 |
| `gol-project/tests/integration/pathfinding/test_door_permissions.gd` | T8-T10 |
| `gol-project/tests/integration/pathfinding/test_danger_zone_avoidance.gd` | T11-T13 |
| `gol-project/tests/integration/pathfinding/test_dynamic_obstacle_response.gd` | T14-T16 |
| `gol-project/tests/integration/pathfinding/test_special_entities.gd` | T17-T20 |
| `gol-project/tests/integration/pathfinding/test_stuck_detection.gd` | T21 |

### Modified Files

| File | Change |
|---|---|
| `gol-project/scripts/services/impl/service_map.gd` | Major rewrite: accept_pcg_result, dynamic obstacles, pathfinding API |
| `gol-project/scripts/services/impl/service_pcg.gd` | Remove 3 query methods |
| `gol-project/scripts/gol.gd` | Add `map().accept_pcg_result(result)` after PCG generation |
| `gol-project/scripts/tests/test_main.gd` | Same as gol.gd |
| `gol-project/scripts/tests/goap_eval/goap_eval_main.gd` | Same as gol.gd |
| `gol-project/scripts/gameplay/ecs/gol_world.gd` | Replace `pcg_result.grid_to_world()` with `ServiceContext.map().grid_to_world()` |
| `gol-project/scripts/systems/s_world_growth.gd` | Replace PCG service calls with map service |
| `gol-project/scripts/systems/s_build_operation.gd` | Remove `_grid_to_world()`, use map service |
| `gol-project/scripts/systems/s_build_site_complete.gd` | Add `mark_blocked()` on building completion |
| `gol-project/scripts/systems/s_move.gd` | Add blocking + sliding logic |
| `gol-project/scripts/gameplay/goap/actions/move_to.gd` | Path-following + stuck detection |
| `gol-project/scripts/gameplay/goap/actions/chase_target.gd` | Path-following with drift threshold |
| `gol-project/scripts/gameplay/goap/actions/wander.gd` | Use find_path for wander targets |

---

## Task 1: NavigationContext and PathResult Data Classes

**Files:**
- Create: `gol-project/scripts/navigation/navigation_context.gd`
- Create: `gol-project/scripts/navigation/path_result.gd`

- [ ] **Step 1: Create navigation_context.gd**

```gdscript
# gol-project/scripts/navigation/navigation_context.gd
class_name NavigationContext
extends RefCounted

## Faction ID (-1 = unaffiliated). Used for door permission checks.
var faction: int = -1

## Whether this agent can break through closed doors it doesn't own.
var can_break_doors: bool = false

## Multiplier for danger zone costs. 0.0 = ignore danger, 1.0 = full avoidance.
var danger_tolerance: float = 1.0


static func create(p_faction: int = -1, p_can_break: bool = false, p_danger_tol: float = 1.0) -> NavigationContext:
	var ctx := NavigationContext.new()
	ctx.faction = p_faction
	ctx.can_break_doors = p_can_break
	ctx.danger_tolerance = p_danger_tol
	return ctx
```

- [ ] **Step 2: Create path_result.gd**

```gdscript
# gol-project/scripts/navigation/path_result.gd
class_name PathResult
extends RefCounted

## Ordered list of grid positions from start to end (inclusive).
var waypoints: Array[Vector2i] = []

## Sum of movement costs along the path.
var total_cost: float = 0.0

## false if no path could be found (target unreachable).
var is_valid: bool = false

## Grid version at the time this path was computed. Used for invalidation.
var grid_version: int = 0


static func invalid() -> PathResult:
	var r := PathResult.new()
	r.is_valid = false
	return r


static func direct(from: Vector2i, to: Vector2i, cost: float, version: int) -> PathResult:
	var r := PathResult.new()
	r.waypoints = [from, to]
	r.total_cost = cost
	r.is_valid = true
	r.grid_version = version
	return r
```

- [ ] **Step 3: Verify files load without errors**

Run: `godot --headless --path gol-project --quit-after 2 2>&1 | grep -i "error\|SCRIPT ERROR"`
Expected: No errors referencing navigation_context or path_result.

- [ ] **Step 4: Commit**

```bash
git add gol-project/scripts/navigation/
git commit -m "feat(nav): add NavigationContext and PathResult data classes"
```

---

## Task 2: PathSolver — A* Algorithm

**Files:**
- Create: `gol-project/scripts/navigation/path_solver.gd`
- Create: `gol-project/tests/unit/navigation/test_path_solver.gd`

- [ ] **Step 1: Write unit tests for PathSolver**

```gdscript
# gol-project/tests/unit/navigation/test_path_solver.gd
extends GdUnitTestSuite

const PathSolverScript = preload("res://scripts/navigation/path_solver.gd")
const PathResultScript = preload("res://scripts/navigation/path_result.gd")
const NavigationContextScript = preload("res://scripts/navigation/navigation_context.gd")


func _create_solver(blocked: Array[Vector2i] = [], danger: Dictionary = {}) -> PathSolver:
	var solver := auto_free(PathSolver.new())
	# Build a 10x10 grid of cost 1.0
	var base_cost: Dictionary = {}
	for x in range(10):
		for y in range(10):
			base_cost[Vector2i(x, y)] = 1.0
	for pos in blocked:
		base_cost[pos] = INF
	solver.initialize(base_cost, {}, danger, 0)
	return solver


func test_direct_path_no_obstacles() -> void:
	var solver := _create_solver()
	var ctx := NavigationContext.create()
	var result := solver.solve(Vector2i(0, 0), Vector2i(3, 0), ctx)
	assert_bool(result.is_valid).is_true()
	assert_int(result.waypoints.size()).is_greater(1)
	assert_object(result.waypoints[0]).is_equal(Vector2i(0, 0))
	assert_object(result.waypoints[-1]).is_equal(Vector2i(3, 0))


func test_path_around_wall() -> void:
	# Wall blocks row y=1, x=1..3. Path must go around.
	var blocked: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	var solver := _create_solver(blocked)
	var ctx := NavigationContext.create()
	var result := solver.solve(Vector2i(2, 0), Vector2i(2, 2), ctx)
	assert_bool(result.is_valid).is_true()
	# Path should not contain any blocked tile
	for wp in result.waypoints:
		assert_bool(blocked.has(wp)).is_false()


func test_unreachable_target() -> void:
	# Surround target (5,5) completely
	var blocked: Array[Vector2i] = [
		Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 4), Vector2i(5, 6)
	]
	var solver := _create_solver(blocked)
	var ctx := NavigationContext.create()
	var result := solver.solve(Vector2i(0, 0), Vector2i(5, 5), ctx)
	assert_bool(result.is_valid).is_false()


func test_danger_zone_increases_cost() -> void:
	# No physical blockers, but danger at (1,0) with cost 10
	var danger: Dictionary = {Vector2i(1, 0): 10.0}
	var solver := _create_solver([], danger)
	var ctx := NavigationContext.create(-1, false, 1.0)
	var result_normal := solver.solve(Vector2i(0, 0), Vector2i(2, 0), ctx)
	# With danger_tolerance=0, should go straight through
	var ctx_immune := NavigationContext.create(-1, false, 0.0)
	var result_immune := solver.solve(Vector2i(0, 0), Vector2i(2, 0), ctx_immune)
	# Immune path should be cheaper (straight line)
	assert_float(result_immune.total_cost).is_less(result_normal.total_cost)


func test_start_equals_end() -> void:
	var solver := _create_solver()
	var ctx := NavigationContext.create()
	var result := solver.solve(Vector2i(3, 3), Vector2i(3, 3), ctx)
	assert_bool(result.is_valid).is_true()
	assert_int(result.waypoints.size()).is_equal(1)


func test_line_of_sight_shortcut() -> void:
	var solver := _create_solver()
	var ctx := NavigationContext.create()
	# Straight line from (0,0) to (5,0) — no obstacles
	var result := solver.solve(Vector2i(0, 0), Vector2i(5, 0), ctx)
	assert_bool(result.is_valid).is_true()
	# Line of sight should produce a 2-waypoint direct path
	assert_int(result.waypoints.size()).is_equal(2)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/unit/navigation/test_path_solver.gd 2>&1 | tail -20`
Expected: FAIL — PathSolver class not found.

- [ ] **Step 3: Implement PathSolver**

```gdscript
# gol-project/scripts/navigation/path_solver.gd
class_name PathSolver
extends RefCounted

## A* pathfinder over a 2D isometric grid with 4-directional connectivity.

const NEIGHBORS: Array[Vector2i] = [
	Vector2i(0, -1),  # N
	Vector2i(1, 0),   # E
	Vector2i(0, 1),   # S
	Vector2i(-1, 0),  # W
]

var _base_cost: Dictionary = {}       # Dictionary[Vector2i, float]
var _doors: Dictionary = {}           # Dictionary[Vector2i, Dictionary] — {is_open, owner_faction}
var _danger_cost: Dictionary = {}     # Dictionary[Vector2i, float]
var _grid_version: int = 0


func initialize(base_cost: Dictionary, doors: Dictionary, danger_cost: Dictionary, grid_version: int) -> void:
	_base_cost = base_cost
	_doors = doors
	_danger_cost = danger_cost
	_grid_version = grid_version


func solve(from: Vector2i, to: Vector2i, context: NavigationContext) -> PathResult:
	if from == to:
		var r := PathResult.new()
		r.waypoints = [from]
		r.total_cost = 0.0
		r.is_valid = true
		r.grid_version = _grid_version
		return r

	# Defense 1: line of sight — skip A* if straight line is clear
	if _line_of_sight(from, to):
		var cost := _heuristic(from, to) * _get_cost(from, context)
		return PathResult.direct(from, to, cost, _grid_version)

	# Full A*
	return _astar(from, to, context)


func is_blocked(pos: Vector2i) -> bool:
	if not _base_cost.has(pos):
		return true  # Out of grid = blocked
	return _base_cost[pos] == INF


func _astar(from: Vector2i, to: Vector2i, context: NavigationContext) -> PathResult:
	# Open set as array (simplicity over perf for 200x200 grid)
	# Each entry: [f_score, g_score, position]
	var open_set: Array = []
	var came_from: Dictionary = {}   # Dictionary[Vector2i, Vector2i]
	var g_score: Dictionary = {}     # Dictionary[Vector2i, float]

	g_score[from] = 0.0
	open_set.append([_heuristic(from, to), 0.0, from])

	while not open_set.is_empty():
		# Find lowest f_score (linear scan — fine for typical path lengths)
		var best_idx: int = 0
		var best_f: float = open_set[0][0]
		for i in range(1, open_set.size()):
			if open_set[i][0] < best_f:
				best_f = open_set[i][0]
				best_idx = i

		var current_entry: Array = open_set[best_idx]
		var current: Vector2i = current_entry[2]
		var current_g: float = current_entry[1]
		open_set.remove_at(best_idx)

		if current == to:
			return _reconstruct(came_from, to, current_g)

		# Skip if we already found a better path to this node
		if current_g > g_score.get(current, INF):
			continue

		for dir in NEIGHBORS:
			var neighbor: Vector2i = current + dir
			var move_cost: float = _get_cost(neighbor, context)

			if move_cost == INF:
				continue

			var tentative_g: float = current_g + move_cost
			if tentative_g < g_score.get(neighbor, INF):
				g_score[neighbor] = tentative_g
				came_from[neighbor] = current
				var f: float = tentative_g + _heuristic(neighbor, to)
				open_set.append([f, tentative_g, neighbor])

	return PathResult.invalid()


func _reconstruct(came_from: Dictionary, to: Vector2i, total_cost: float) -> PathResult:
	var path: Array[Vector2i] = []
	var current := to
	while came_from.has(current):
		path.append(current)
		current = came_from[current]
	path.append(current)  # Start node
	path.reverse()

	var r := PathResult.new()
	r.waypoints = path
	r.total_cost = total_cost
	r.is_valid = true
	r.grid_version = _grid_version
	return r


func _get_cost(pos: Vector2i, context: NavigationContext) -> float:
	if not _base_cost.has(pos):
		return INF  # Out of bounds

	var base: float = _base_cost[pos]
	if base == INF:
		return INF

	# Door cost
	var door_cost: float = _get_door_cost(pos, context)
	if door_cost == INF:
		return INF

	# Danger cost
	var danger: float = _danger_cost.get(pos, 0.0) * context.danger_tolerance

	return base + door_cost + danger


func _get_door_cost(pos: Vector2i, context: NavigationContext) -> float:
	if not _doors.has(pos):
		return 0.0
	var door: Dictionary = _doors[pos]
	if door.get("is_open", false):
		return 0.0
	if door.get("owner_faction", -1) == context.faction:
		return 2.0
	elif context.can_break_doors:
		return 20.0
	else:
		return INF


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y))


func _line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	for pos in _bresenham_line(from, to):
		if is_blocked(pos):
			return false
	return true


func _bresenham_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y

	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

	return points
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/unit/navigation/test_path_solver.gd 2>&1 | tail -20`
Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add gol-project/scripts/navigation/path_solver.gd gol-project/tests/unit/navigation/
git commit -m "feat(nav): implement PathSolver with A*, line-of-sight, Bresenham"
```

---

## Task 3: Service_Map — Rewrite with Navigation API

**Files:**
- Modify: `gol-project/scripts/services/impl/service_map.gd` (full rewrite)
- Create: `gol-project/tests/unit/service/test_service_map_navigation.gd`

- [ ] **Step 1: Write unit tests for the new Service_Map navigation methods**

```gdscript
# gol-project/tests/unit/service/test_service_map_navigation.gd
extends GdUnitTestSuite

const ServiceMapScript = preload("res://scripts/services/impl/service_map.gd")
const PCGCellScript = preload("res://scripts/pcg/data/pcg_cell.gd")
const PCGResultScript = preload("res://scripts/pcg/data/pcg_result.gd")
const TileAssetResolverScript = preload("res://scripts/pcg/tile_asset_resolver.gd")
const NavigationContextScript = preload("res://scripts/navigation/navigation_context.gd")


func _create_map_with_grid(size: int = 10) -> Service_Map:
	var svc := auto_free(Service_Map.new())
	var result := auto_free(PCGResult.new())
	result.grid = {}
	for x in range(size):
		for y in range(size):
			var cell := PCGCell.new()
			cell.logic_type = TileAssetResolver.LogicType.GRASS
			result.grid[Vector2i(x, y)] = cell
	svc.accept_pcg_result(result)
	return svc


func test_accept_pcg_result_builds_base_cost() -> void:
	var svc := _create_map_with_grid(5)
	assert_bool(svc.is_walkable(Vector2i(0, 0))).is_true()
	assert_bool(svc.is_position_blocked(Vector2i(0, 0))).is_false()


func test_mark_blocked_and_unblocked() -> void:
	var svc := _create_map_with_grid(5)
	svc.mark_blocked(Vector2i(2, 2))
	assert_bool(svc.is_position_blocked(Vector2i(2, 2))).is_true()
	svc.mark_unblocked(Vector2i(2, 2))
	assert_bool(svc.is_position_blocked(Vector2i(2, 2))).is_false()


func test_grid_version_increments() -> void:
	var svc := _create_map_with_grid(5)
	var v0 := svc.get_grid_version()
	svc.mark_blocked(Vector2i(1, 1))
	assert_int(svc.get_grid_version()).is_greater(v0)


func test_door_state_affects_cost() -> void:
	var svc := _create_map_with_grid(5)
	svc.set_door_state(Vector2i(2, 0), false, 0)  # closed, owned by faction 0
	var ctx_owner := NavigationContext.create(0)  # same faction
	var ctx_enemy := NavigationContext.create(1)  # different faction
	var cost_owner := svc.get_movement_cost(Vector2i(2, 0), ctx_owner)
	var cost_enemy := svc.get_movement_cost(Vector2i(2, 0), ctx_enemy)
	assert_float(cost_owner).is_less(100.0)  # passable (base + 2.0)
	assert_float(cost_enemy).is_equal(INF)   # blocked (no break ability)


func test_find_path_around_blocked() -> void:
	var svc := _create_map_with_grid(10)
	# Block a column at x=5, y=0..8 (leave y=9 open)
	for y in range(9):
		svc.mark_blocked(Vector2i(5, y))
	var ctx := NavigationContext.create()
	var path := svc.find_path(Vector2i(3, 4), Vector2i(7, 4), ctx)
	assert_bool(path.is_valid).is_true()
	# Path must go around (through y=9)
	for wp in path.waypoints:
		assert_bool(svc.is_position_blocked(wp)).is_false()


func test_is_path_still_valid_detects_blocked_waypoint() -> void:
	var svc := _create_map_with_grid(10)
	var ctx := NavigationContext.create()
	var path := svc.find_path(Vector2i(0, 0), Vector2i(5, 0), ctx)
	assert_bool(path.is_valid).is_true()
	# Now block a waypoint on the path
	svc.mark_blocked(path.waypoints[2])
	assert_bool(svc.is_path_still_valid(path)).is_false()


func test_danger_zone_set_and_clear() -> void:
	var svc := _create_map_with_grid(10)
	svc.set_danger_zone(Vector2i(5, 5), 2, 10.0)
	var ctx := NavigationContext.create(-1, false, 1.0)
	var cost_center := svc.get_movement_cost(Vector2i(5, 5), ctx)
	var cost_edge := svc.get_movement_cost(Vector2i(5, 3), ctx)  # dist=2, at edge
	assert_float(cost_center).is_greater(5.0)  # base(1.0) + danger(~10.0)
	svc.clear_danger_zone(Vector2i(5, 5), 2)
	var cost_after := svc.get_movement_cost(Vector2i(5, 5), ctx)
	assert_float(cost_after).is_less(2.0)  # just base cost
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/unit/service/test_service_map_navigation.gd 2>&1 | tail -20`
Expected: FAIL — methods don't exist yet.

- [ ] **Step 3: Rewrite service_map.gd**

```gdscript
# gol-project/scripts/services/impl/service_map.gd
class_name Service_Map
extends ServiceBase

## Single source of truth for map data: terrain, obstacles, doors, danger, pathfinding.
## Replaces the previous lazy-load pattern that depended on Service_PCG at runtime.

const TILE_WIDTH: int = 64
const TILE_HEIGHT: int = 32

# ─── Internal state ───────────────────────────────────────────────────────────
var _pcg_result: PCGResult = null
var _base_cost: Dictionary = {}        # Dictionary[Vector2i, float]
var _dynamic_blocked: Dictionary = {}  # Dictionary[Vector2i, bool]
var _doors: Dictionary = {}            # Dictionary[Vector2i, Dictionary{is_open,owner_faction}]
var _danger_cost: Dictionary = {}      # Dictionary[Vector2i, float]
var _grid_version: int = 0
var _path_solver: PathSolver = null

# Caches
var _zone_positions_cache: Dictionary = {}
var _cached_poi_by_type: Dictionary = {}


# ═══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func setup() -> void:
	_path_solver = PathSolver.new()


func teardown() -> void:
	_pcg_result = null
	_base_cost.clear()
	_dynamic_blocked.clear()
	_doors.clear()
	_danger_cost.clear()
	_zone_positions_cache.clear()
	_cached_poi_by_type.clear()
	_path_solver = null


func accept_pcg_result(result: PCGResult) -> void:
	_pcg_result = result
	_base_cost.clear()
	_dynamic_blocked.clear()
	_doors.clear()
	_danger_cost.clear()
	_grid_version = 0
	_invalidate_caches()

	if result == null or result.grid.is_empty():
		return

	for pos: Variant in result.grid.keys():
		if pos is Vector2i:
			var cell := result.grid[pos] as PCGCell
			if cell:
				_base_cost[pos] = _logic_type_to_cost(cell.logic_type)

	_sync_solver()


# ═══════════════════════════════════════════════════════════════════════════════
# COORDINATE CONVERSION
# ═══════════════════════════════════════════════════════════════════════════════

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	var half_w: float = float(TILE_WIDTH) / 2.0
	var half_h: float = float(TILE_HEIGHT) / 2.0
	var world_x: float = (float(grid_pos.x) - float(grid_pos.y)) * half_w + half_w
	var world_y: float = (float(grid_pos.x) + float(grid_pos.y)) * half_h + half_h
	return Vector2(world_x, world_y)


func world_to_grid(world_pos: Vector2) -> Vector2i:
	var half_w: float = float(TILE_WIDTH) / 2.0
	var half_h: float = float(TILE_HEIGHT) / 2.0
	var offset_x: float = (world_pos.x - half_w) / half_w
	var offset_y: float = (world_pos.y - half_h) / half_h
	var grid_x: float = (offset_x + offset_y) / 2.0
	var grid_y: float = (offset_y - offset_x) / 2.0
	return Vector2i(roundi(grid_x), roundi(grid_y))


# ═══════════════════════════════════════════════════════════════════════════════
# TERRAIN QUERIES
# ═══════════════════════════════════════════════════════════════════════════════

func get_grid() -> Dictionary:
	return _pcg_result.grid if _pcg_result else {}


func get_cell(pos: Vector2i) -> Variant:
	if _pcg_result == null:
		return null
	return _pcg_result.grid.get(pos, null)


func is_walkable(pos: Vector2i) -> bool:
	return _base_cost.get(pos, INF) < INF


# ═══════════════════════════════════════════════════════════════════════════════
# ZONE / POI QUERIES (migrated from Service_PCG)
# ═══════════════════════════════════════════════════════════════════════════════

func get_zone_map() -> ZoneMap:
	if _pcg_result == null:
		return null
	return _pcg_result.zone_map


func get_road_cells() -> Dictionary:
	if _pcg_result == null:
		return {}
	return _pcg_result.road_cells


func get_pois_by_type(poi_type: int) -> Array:
	_rebuild_cached_pois_if_needed()
	return _cached_poi_by_type.get(poi_type, []).duplicate()


func find_nearest_poi(world_pos: Vector2, excluded_types: Array = []) -> Variant:
	if _pcg_result == null or _pcg_result.poi_list.pois.is_empty():
		return null
	var closest: Variant = null
	var closest_dist := INF
	for poi: POIList.POI in _pcg_result.poi_list.pois:
		if excluded_types.has(poi.poi_type):
			continue
		var dist := poi.position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = poi
	return closest


func find_nearest_poi_of_type(world_pos: Vector2, poi_type: int) -> Variant:
	var pois := get_pois_by_type(poi_type)
	if pois.is_empty():
		return null
	var closest: Variant = null
	var closest_dist := INF
	for poi: POIList.POI in pois:
		var dist := poi.position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = poi
	return closest


func find_nearest_village_poi(center: Vector2 = Vector2.ZERO) -> Vector2:
	if _pcg_result == null:
		push_warning("[Service_Map] No PCG result available, using default position")
		return Vector2(500, 500)
	var poi_list := _pcg_result.poi_list
	var village_pois := poi_list.get_pois_by_type(POIList.POIType.VILLAGE)
	if village_pois.is_empty():
		push_warning("[Service_Map] No VILLAGE POIs found, using default position")
		return Vector2(500, 500)
	var closest_poi: POIList.POI = null
	var closest_dist := INF
	for poi: POIList.POI in village_pois:
		var dist := poi.position.distance_to(center)
		if dist < closest_dist:
			closest_dist = dist
			closest_poi = poi
	return closest_poi.position


func get_positions_by_zone(zone_type: int) -> Array[Vector2i]:
	_rebuild_zone_cache_if_needed()
	var cached := _zone_positions_cache.get(zone_type, [])
	return cached.duplicate() if cached else []


# ═══════════════════════════════════════════════════════════════════════════════
# DYNAMIC OBSTACLES
# ═══════════════════════════════════════════════════════════════════════════════

func mark_blocked(pos: Vector2i) -> void:
	_dynamic_blocked[pos] = true
	_grid_version += 1
	_sync_solver()


func mark_unblocked(pos: Vector2i) -> void:
	_dynamic_blocked.erase(pos)
	_grid_version += 1
	_sync_solver()


func set_door_state(pos: Vector2i, open: bool, owner_faction: int) -> void:
	_doors[pos] = {"is_open": open, "owner_faction": owner_faction}
	_grid_version += 1
	_sync_solver()


func set_danger_zone(center: Vector2i, radius: int, peak_cost: float) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos := center + Vector2i(dx, dy)
			var dist: int = abs(dx) + abs(dy)
			if dist <= radius:
				var cost: float = peak_cost * (1.0 - float(dist) / float(radius + 1))
				_danger_cost[pos] = maxf(_danger_cost.get(pos, 0.0), cost)
	_grid_version += 1
	_sync_solver()


func clear_danger_zone(center: Vector2i, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var pos := center + Vector2i(dx, dy)
			if abs(dx) + abs(dy) <= radius:
				_danger_cost.erase(pos)
	_grid_version += 1
	_sync_solver()


# ═══════════════════════════════════════════════════════════════════════════════
# PATHFINDING
# ═══════════════════════════════════════════════════════════════════════════════

func find_path(from: Vector2i, to: Vector2i, context: NavigationContext) -> PathResult:
	if _path_solver == null:
		return PathResult.invalid()
	return _path_solver.solve(from, to, context)


func is_path_still_valid(path: PathResult) -> bool:
	if path == null or path.waypoints.is_empty():
		return false
	if path.grid_version == _grid_version:
		return true
	for waypoint in path.waypoints:
		if is_position_blocked(waypoint):
			return false
	return true


func is_reachable(from: Vector2i, to: Vector2i) -> bool:
	var ctx := NavigationContext.create()
	var result := find_path(from, to, ctx)
	return result.is_valid


func is_position_blocked(pos: Vector2i) -> bool:
	if _dynamic_blocked.get(pos, false):
		return true
	return _base_cost.get(pos, INF) == INF


func get_movement_cost(pos: Vector2i, context: NavigationContext) -> float:
	if is_position_blocked(pos):
		return INF
	var base: float = _base_cost.get(pos, INF)
	var door_cost: float = _get_door_cost(pos, context)
	if door_cost == INF:
		return INF
	var danger: float = _danger_cost.get(pos, 0.0) * context.danger_tolerance
	return base + door_cost + danger


func get_grid_version() -> int:
	return _grid_version


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNALS
# ═══════════════════════════════════════════════════════════════════════════════

func _sync_solver() -> void:
	if _path_solver == null:
		return
	# Merge base_cost with dynamic_blocked for the solver's base layer
	var merged_cost: Dictionary = _base_cost.duplicate()
	for pos in _dynamic_blocked:
		merged_cost[pos] = INF
	_path_solver.initialize(merged_cost, _doors, _danger_cost, _grid_version)


func _get_door_cost(pos: Vector2i, context: NavigationContext) -> float:
	if not _doors.has(pos):
		return 0.0
	var door: Dictionary = _doors[pos]
	if door.get("is_open", false):
		return 0.0
	if door.get("owner_faction", -1) == context.faction:
		return 2.0
	elif context.can_break_doors:
		return 20.0
	else:
		return INF


func _logic_type_to_cost(logic_type: int) -> float:
	match logic_type:
		TileAssetResolver.LogicType.GRASS, TileAssetResolver.LogicType.DIRT:
			return 1.0
		TileAssetResolver.LogicType.ROAD, TileAssetResolver.LogicType.SIDEWALK, \
		TileAssetResolver.LogicType.CROSSWALK:
			return 0.8
		TileAssetResolver.LogicType.WATER, TileAssetResolver.LogicType.BUILDING:
			return INF
		_:
			return 1.0


func _invalidate_caches() -> void:
	_zone_positions_cache.clear()
	_cached_poi_by_type.clear()


func _rebuild_zone_cache_if_needed() -> void:
	if _pcg_result == null or _pcg_result.grid.is_empty():
		_zone_positions_cache.clear()
		return
	if not _zone_positions_cache.is_empty():
		return
	for pos: Variant in _pcg_result.grid.keys():
		if pos is Vector2i:
			var cell := _pcg_result.grid[pos] as PCGCell
			if cell:
				var zone_type: int = cell.zone_type
				if not _zone_positions_cache.has(zone_type):
					_zone_positions_cache[zone_type] = []
				_zone_positions_cache[zone_type].append(pos)


func _rebuild_cached_pois_if_needed() -> void:
	if _pcg_result == null or _pcg_result.poi_list == null or _pcg_result.poi_list.pois.is_empty():
		_cached_poi_by_type.clear()
		return
	if not _cached_poi_by_type.is_empty():
		return
	for poi: POIList.POI in _pcg_result.poi_list.pois:
		if not _cached_poi_by_type.has(poi.poi_type):
			_cached_poi_by_type[poi.poi_type] = []
		_cached_poi_by_type[poi.poi_type].append(poi)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/unit/service/test_service_map_navigation.gd 2>&1 | tail -20`
Expected: All 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add gol-project/scripts/services/impl/service_map.gd gol-project/tests/unit/service/test_service_map_navigation.gd
git commit -m "feat(nav): rewrite Service_Map with navigation API, dynamic obstacles, pathfinding"
```

---

## Task 4: Service_PCG Refactor + Caller Migration

**Files:**
- Modify: `gol-project/scripts/services/impl/service_pcg.gd`
- Modify: `gol-project/scripts/gol.gd`
- Modify: `gol-project/scripts/tests/test_main.gd`
- Modify: `gol-project/scripts/tests/goap_eval/goap_eval_main.gd`
- Modify: `gol-project/scripts/gameplay/ecs/gol_world.gd`
- Modify: `gol-project/scripts/systems/s_world_growth.gd`
- Modify: `gol-project/scripts/systems/s_build_operation.gd`

- [ ] **Step 1: Strip Service_PCG down to pure generator**

Replace `gol-project/scripts/services/impl/service_pcg.gd` with:

```gdscript
# scripts/services/impl/service_pcg.gd
class_name Service_PCG
extends ServiceBase
## Service wrapper for PCG pipeline. Generates maps. Query methods live in Service_Map.

var last_result: PCGResult


func generate(config: PCGConfig) -> PCGResult:
	var effective_config: PCGConfig = config
	if effective_config == null:
		effective_config = PCGConfig.new()

	var pipeline := PCGPipeline.new()
	for phase: PCGPhase in PCGPhaseConfig.create_phases():
		pipeline.add_phase(phase)

	var result: PCGResult = pipeline.generate(effective_config)
	_ensure_minimum_pois(result)
	last_result = result
	return result


func _ensure_minimum_pois(result: PCGResult) -> void:
	if result == null:
		return
	var has_pois := false
	if result.grid != null and result.grid is Dictionary:
		for pos in result.grid.keys():
			var cell = result.grid[pos]
			if cell is PCGCell and cell.has_poi():
				has_pois = true
				break
	if not has_pois and result.poi_list != null and not result.poi_list.pois.is_empty():
		return
	if has_pois:
		return
	var seed_value: int = 0
	if result.config != null:
		seed_value = result.config.pcg_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid_size: int = 100
	if result.config != null:
		var gs: Variant = result.config.get("grid_size")
		if gs != null:
			grid_size = int(gs)
	var half_size: int = int(grid_size / 2)
	var start: int = -half_size
	var end: int = grid_size - half_size - 1
	var x: int = rng.randi_range(start, end)
	var y: int = rng.randi_range(start, end)
	var pos := Vector2i(x, y)
	if result.grid != null and result.grid is Dictionary:
		var cell: PCGCell
		if result.grid.has(pos):
			cell = result.grid[pos]
		if cell == null:
			cell = PCGCell.new()
			result.grid[pos] = cell
		cell.poi_type = POIList.POIType.BUILDING
		cell.logic_type = TileAssetResolver.LogicType.BUILDING
```

- [ ] **Step 2: Update gol.gd — add accept_pcg_result and migrate find_nearest_village_poi**

In `gol-project/scripts/gol.gd`, replace `start_game()`:

```gdscript
func start_game() -> void:
	var config := ProceduralConfig.new()
	config.pcg_config().pcg_seed = randi()
	var result := ServiceContext.pcg().generate(config.pcg_config())
	if result == null or not result.is_valid():
		push_error("PCG generation failed - aborting game start")
		return

	ServiceContext.map().accept_pcg_result(result)
	Game.campfire_position = ServiceContext.map().find_nearest_village_poi()

	ServiceContext.scene().switch_scene(config)
```

- [ ] **Step 3: Update test_main.gd**

Find the PCG generation block and add `ServiceContext.map().accept_pcg_result(pcg_result)` after generation, and change `ServiceContext.pcg().find_nearest_village_poi()` to `ServiceContext.map().find_nearest_village_poi()`.

- [ ] **Step 4: Update goap_eval_main.gd**

Same pattern: after `ServiceContext.pcg().generate(...)`, add `ServiceContext.map().accept_pcg_result(result)` and change village POI call.

- [ ] **Step 5: Update gol_world.gd**

Replace all `ServiceContext.pcg().last_result` usages with `ServiceContext.map()` equivalents:
- `pcg_result.grid_to_world(pos)` → `ServiceContext.map().grid_to_world(pos)`
- `ServiceContext.pcg().last_result` → `ServiceContext.map().get_grid()` (for grid access)
- Keep `var pcg_result` as local for reading `.creature_spawners` and `.plants` (those stay on PCGResult)

- [ ] **Step 6: Update s_world_growth.gd**

Replace `ServiceContext.pcg()` usage with `ServiceContext.map()`.

- [ ] **Step 7: Update s_build_operation.gd**

Delete the local `_grid_to_world()` method. Replace all calls with `ServiceContext.map().grid_to_world()`. Replace `_world_to_grid()` with `ServiceContext.map().world_to_grid()`.

- [ ] **Step 8: Run full test suite to verify nothing is broken**

Run: `godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/ 2>&1 | grep -E "PASS|FAIL|ERROR"`
Expected: All existing tests still pass.

- [ ] **Step 9: Commit**

```bash
git add gol-project/scripts/services/impl/service_pcg.gd gol-project/scripts/gol.gd gol-project/scripts/tests/ gol-project/scripts/gameplay/ecs/gol_world.gd gol-project/scripts/systems/s_world_growth.gd gol-project/scripts/systems/s_build_operation.gd
git commit -m "refactor: strip Service_PCG to pure generator, migrate queries to Service_Map"
```

---

## Task 5: SMove — Blocking and Sliding

**Files:**
- Modify: `gol-project/scripts/systems/s_move.gd`
- Test: `gol-project/tests/integration/pathfinding/test_player_blocked_by_wall.gd`
- Test: `gol-project/tests/integration/pathfinding/test_player_slides_along_wall.gd`

- [ ] **Step 1: Write integration tests T4 and T5**

```gdscript
# gol-project/tests/integration/pathfinding/test_player_blocked_by_wall.gd
class_name TestPlayerBlockedByWallConfig
extends SceneConfig

## T4: Player moves toward a wall and is blocked (does not pass through).

func scene_name() -> String:
	return "test"

func systems() -> Variant:
	return ["res://scripts/systems/s_move.gd"]

func enable_pcg() -> bool:
	return false

func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "TestPlayer",
			"components": {
				"CTransform": {"position": Vector2(0, 0)},
			},
		},
	]

func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()
	var player: Entity = _find_entity(world, "TestPlayer")
	result.assert_true(player != null, "Player spawned")
	if player == null:
		return result

	# Setup: place a wall at grid (3, 0) → world pos via map service
	var map := ServiceContext.map()
	# Initialize a minimal grid around origin for the test
	_init_test_grid(map)
	var wall_grid := Vector2i(3, 0)
	map.mark_blocked(wall_grid)
	var wall_world := map.grid_to_world(wall_grid)

	# Set player velocity toward the wall
	var movement := player.get_component(CMovement)
	var transform := player.get_component(CTransform)
	movement.velocity = Vector2(140, 0)  # Moving right

	# Simulate 300 frames (5 seconds)
	await _wait_frames(world, 300)

	# Player should NOT have crossed the wall tile
	var player_grid := map.world_to_grid(transform.position)
	result.assert_true(
		player_grid.x < wall_grid.x,
		"Player did not pass through wall (player at grid.x=%d, wall at grid.x=%d)" % [player_grid.x, wall_grid.x]
	)

	return result

func _init_test_grid(map: Service_Map) -> void:
	var result := PCGResult.new()
	result.grid = {}
	for x in range(-5, 10):
		for y in range(-5, 10):
			var cell := PCGCell.new()
			cell.logic_type = TileAssetResolver.LogicType.GRASS
			result.grid[Vector2i(x, y)] = cell
	map.accept_pcg_result(result)
```

```gdscript
# gol-project/tests/integration/pathfinding/test_player_slides_along_wall.gd
class_name TestPlayerSlidesAlongWallConfig
extends SceneConfig

## T5: Player moves diagonally into a wall and slides along it.

func scene_name() -> String:
	return "test"

func systems() -> Variant:
	return ["res://scripts/systems/s_move.gd"]

func enable_pcg() -> bool:
	return false

func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "TestPlayer",
			"components": {
				"CTransform": {"position": Vector2(0, 0)},
			},
		},
	]

func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()
	var player: Entity = _find_entity(world, "TestPlayer")
	result.assert_true(player != null, "Player spawned")
	if player == null:
		return result

	var map := ServiceContext.map()
	_init_test_grid(map)
	# Block a row of tiles at y offset to create a wall along one axis
	var wall_grid := Vector2i(3, 0)
	map.mark_blocked(wall_grid)

	var movement := player.get_component(CMovement)
	var transform := player.get_component(CTransform)
	var initial_pos := transform.position

	# Diagonal velocity toward the wall
	movement.velocity = Vector2(100, 70)

	await _wait_frames(world, 60)

	# Player should have moved (not stuck) due to sliding on the unblocked axis
	var moved_dist := transform.position.distance_to(initial_pos)
	result.assert_true(
		moved_dist > 10.0,
		"Player slid along wall (moved %.1f pixels, expected > 10)" % moved_dist
	)

	# But should not have crossed the blocked tile
	var player_grid := map.world_to_grid(transform.position)
	result.assert_true(
		player_grid.x < wall_grid.x or player_grid != wall_grid,
		"Player did not enter blocked tile"
	)

	return result

func _init_test_grid(map: Service_Map) -> void:
	var result := PCGResult.new()
	result.grid = {}
	for x in range(-5, 10):
		for y in range(-5, 10):
			var cell := PCGCell.new()
			cell.logic_type = TileAssetResolver.LogicType.GRASS
			result.grid[Vector2i(x, y)] = cell
	map.accept_pcg_result(result)
```

- [ ] **Step 2: Modify SMove to add blocking + sliding**

In `gol-project/scripts/systems/s_move.gd`, replace line 54 (`transform.position += move.velocity * delta`) with blocking logic:

```gdscript
	# Update position based on velocity — with blocking + sliding
	_apply_movement(entity, move, transform, delta)


func _apply_movement(_entity: Entity, move: CMovement, transform: CTransform, delta: float) -> void:
	if move.velocity.length_squared() < 0.01:
		return

	var map := ServiceContext.map()
	if map == null:
		# Fallback: no map service, move freely (graceful degrade)
		transform.position += move.velocity * delta
		return

	var new_pos: Vector2 = transform.position + move.velocity * delta
	var new_grid: Vector2i = map.world_to_grid(new_pos)

	# If target tile is free, move normally
	if not map.is_position_blocked(new_grid):
		transform.position = new_pos
		return

	# Axis-separated sliding
	var slide_x := Vector2(new_pos.x, transform.position.y)
	if not map.is_position_blocked(map.world_to_grid(slide_x)):
		transform.position = slide_x
		return

	var slide_y := Vector2(transform.position.x, new_pos.y)
	if not map.is_position_blocked(map.world_to_grid(slide_y)):
		transform.position = slide_y
		return

	# Both axes blocked — don't move (velocity preserved for next frame)
```

- [ ] **Step 3: Run tests T4 and T5**

Run: `godot --headless --path gol-project --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/pathfinding/test_player_blocked_by_wall.gd`
Expected: PASS

Run: `godot --headless --path gol-project --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/pathfinding/test_player_slides_along_wall.gd`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add gol-project/scripts/systems/s_move.gd gol-project/tests/integration/pathfinding/test_player_blocked_by_wall.gd gol-project/tests/integration/pathfinding/test_player_slides_along_wall.gd
git commit -m "feat(nav): add blocking + sliding to SMove"
```

---

## Task 6: GOAP MoveTo — Path Following + Stuck Detection

**Files:**
- Modify: `gol-project/scripts/gameplay/goap/actions/move_to.gd`
- Test: `gol-project/tests/integration/pathfinding/test_npc_pathfinds_around_wall.gd`
- Test: `gol-project/tests/integration/pathfinding/test_npc_direct_path_no_wall.gd`
- Test: `gol-project/tests/integration/pathfinding/test_npc_unreachable_target.gd`

- [ ] **Step 1: Write integration tests T1, T2, T3**

```gdscript
# gol-project/tests/integration/pathfinding/test_npc_pathfinds_around_wall.gd
class_name TestNpcPathfindsAroundWallConfig
extends SceneConfig

## T1: NPC navigates around a wall to reach target.

func scene_name() -> String:
	return "test"

func systems() -> Variant:
	return [
		"res://scripts/systems/s_perception.gd",
		"res://scripts/systems/s_ai.gd",
		"res://scripts/systems/s_move.gd",
	]

func enable_pcg() -> bool:
	return false

func entities() -> Variant:
	return [
		{
			"recipe": "survivor",
			"name": "TestNPC",
			"components": {
				"CTransform": {"position": Vector2(0, 0)},
			},
		},
	]

func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()
	var npc: Entity = _find_entity(world, "TestNPC")
	result.assert_true(npc != null, "NPC spawned")
	if npc == null:
		return result

	var map := ServiceContext.map()
	_init_test_grid(map)

	# Place wall row at x=5, y=0..8, leaving gap at y=9
	for y in range(9):
		map.mark_blocked(Vector2i(5, y))

	# Set patrol/move target to the other side of the wall
	var target_pos := map.grid_to_world(Vector2i(8, 4))
	var agent := npc.get_component(CGoapAgent)
	if agent:
		agent.blackboard["move_target"] = target_pos

	await _wait_frames(world, 900)  # 15 seconds

	var transform := npc.get_component(CTransform)
	var final_grid := map.world_to_grid(transform.position)
	result.assert_true(
		final_grid.x >= 7,
		"NPC reached other side of wall (grid.x=%d, expected >= 7)" % final_grid.x
	)
	return result

func _init_test_grid(map: Service_Map) -> void:
	var r := PCGResult.new()
	r.grid = {}
	for x in range(15):
		for y in range(15):
			var cell := PCGCell.new()
			cell.logic_type = TileAssetResolver.LogicType.GRASS
			r.grid[Vector2i(x, y)] = cell
	map.accept_pcg_result(r)
```

```gdscript
# gol-project/tests/integration/pathfinding/test_npc_direct_path_no_wall.gd
class_name TestNpcDirectPathNoWallConfig
extends SceneConfig

## T2: NPC moves directly to target with no obstacles (line-of-sight shortcut).

func scene_name() -> String:
	return "test"

func systems() -> Variant:
	return [
		"res://scripts/systems/s_perception.gd",
		"res://scripts/systems/s_ai.gd",
		"res://scripts/systems/s_move.gd",
	]

func enable_pcg() -> bool:
	return false

func entities() -> Variant:
	return [
		{
			"recipe": "survivor",
			"name": "TestNPC",
			"components": {
				"CTransform": {"position": Vector2(0, 0)},
			},
		},
	]

func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()
	var npc: Entity = _find_entity(world, "TestNPC")
	result.assert_true(npc != null, "NPC spawned")
	if npc == null:
		return result

	var map := ServiceContext.map()
	_init_test_grid(map)

	var target_pos := map.grid_to_world(Vector2i(5, 0))
	var agent := npc.get_component(CGoapAgent)
	if agent:
		agent.blackboard["move_target"] = target_pos

	await _wait_frames(world, 300)  # 5 seconds

	var transform := npc.get_component(CTransform)
	var dist := transform.position.distance_to(target_pos)
	result.assert_true(
		dist < 20.0,
		"NPC reached target directly (distance=%.1f, expected < 20)" % dist
	)
	return result

func _init_test_grid(map: Service_Map) -> void:
	var r := PCGResult.new()
	r.grid = {}
	for x in range(10):
		for y in range(10):
			var cell := PCGCell.new()
			cell.logic_type = TileAssetResolver.LogicType.GRASS
			r.grid[Vector2i(x, y)] = cell
	map.accept_pcg_result(r)
```

```gdscript
# gol-project/tests/integration/pathfinding/test_npc_unreachable_target.gd
class_name TestNpcUnreachableTargetConfig
extends SceneConfig

## T3: NPC fails plan when target is completely surrounded by walls.

func scene_name() -> String:
	return "test"

func systems() -> Variant:
	return [
		"res://scripts/systems/s_perception.gd",
		"res://scripts/systems/s_ai.gd",
		"res://scripts/systems/s_move.gd",
	]

func enable_pcg() -> bool:
	return false

func entities() -> Variant:
	return [
		{
			"recipe": "survivor",
			"name": "TestNPC",
			"components": {
				"CTransform": {"position": Vector2(0, 0)},
			},
		},
	]

func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()
	var npc: Entity = _find_entity(world, "TestNPC")
	result.assert_true(npc != null, "NPC spawned")
	if npc == null:
		return result

	var map := ServiceContext.map()
	_init_test_grid(map)

	# Surround target at (7,7) completely
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			map.mark_blocked(Vector2i(7 + dx, 7 + dy))
	# Also block the 4 cardinal neighbors (rhombus grid)
	map.mark_blocked(Vector2i(6, 7))
	map.mark_blocked(Vector2i(8, 7))
	map.mark_blocked(Vector2i(7, 6))
	map.mark_blocked(Vector2i(7, 8))

	var target_pos := map.grid_to_world(Vector2i(7, 7))
	var agent := npc.get_component(CGoapAgent)
	if agent:
		agent.blackboard["move_target"] = target_pos

	await _wait_frames(world, 300)  # 5 seconds

	# NPC should not be stuck — it should have replanned
	var transform := npc.get_component(CTransform)
	result.assert_true(
		is_instance_valid(npc) and not npc.has_component(CDead),
		"NPC is still alive and not stuck-crashed"
	)
	# Verify the NPC's plan was invalidated (fail_plan was called)
	result.assert_true(
		agent.plan_invalidated or agent.blackboard.get("_path_unreachable", false),
		"NPC detected unreachable target"
	)
	return result

func _init_test_grid(map: Service_Map) -> void:
	var r := PCGResult.new()
	r.grid = {}
	for x in range(15):
		for y in range(15):
			var cell := PCGCell.new()
			cell.logic_type = TileAssetResolver.LogicType.GRASS
			r.grid[Vector2i(x, y)] = cell
	map.accept_pcg_result(r)
```

- [ ] **Step 2: Rewrite move_to.gd with path following**

```gdscript
# gol-project/scripts/gameplay/goap/actions/move_to.gd
class_name GoapAction_MoveTo
extends GoapAction

## Move toward a blackboard position using pathfinding.
## Subclasses inherit path-following + stuck detection automatically.

var target_key: String = "move_target"
var reach_threshold: float = 10.0

const WAYPOINT_REACH_THRESHOLD: float = 12.0
const STUCK_TIMEOUT: float = 3.0

var _path: PathResult = null
var _current_waypoint_index: int = 0
var _last_target_grid: Vector2i = Vector2i(-99999, -99999)
var _last_position: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0


func _init() -> void:
	action_name = "MoveTo"
	cost = 1.0
	preconditions = {}
	effects = {
		"reached_move_target": true
	}


func on_plan_enter(_agent_entity: Entity, _agent_component: CGoapAgent, _context: Dictionary) -> void:
	_path = null
	_current_waypoint_index = 0
	_last_target_grid = Vector2i(-99999, -99999)
	_stuck_timer = 0.0


func perform(agent_entity: Entity, agent_component: CGoapAgent, delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform)
	var movement := agent_entity.get_component(CMovement)

	if transform == null or movement == null:
		return true

	var target_pos: Variant = get_blackboard(agent_component, target_key, null)
	if not target_pos is Vector2:
		movement.velocity = Vector2.ZERO
		return true

	# Check if already at destination
	var distance_to_target: float = transform.position.distance_to(target_pos)
	if distance_to_target <= reach_threshold:
		movement.velocity = Vector2.ZERO
		return true

	var map := ServiceContext.map()
	if map == null:
		# Fallback: no map, direct movement (graceful degrade)
		return _move_direct(transform, movement, target_pos)

	var agent_grid: Vector2i = map.world_to_grid(transform.position)
	var target_grid: Vector2i = map.world_to_grid(target_pos)

	# Path acquisition
	if _needs_new_path(agent_grid, target_grid, map):
		var context := _build_nav_context(agent_entity)
		_path = map.find_path(agent_grid, target_grid, context)
		_current_waypoint_index = 0
		if not _path.is_valid:
			movement.velocity = Vector2.ZERO
			fail_plan(agent_component, "path_unreachable")
			return false

	# Stuck detection
	if _check_stuck(transform.position, delta):
		movement.velocity = Vector2.ZERO
		_path = null
		fail_plan(agent_component, "stuck")
		return false

	# Follow waypoints
	if _path == null or _path.waypoints.is_empty():
		return _move_direct(transform, movement, target_pos)

	if _current_waypoint_index >= _path.waypoints.size():
		movement.velocity = Vector2.ZERO
		return true

	var wp_world: Vector2 = map.grid_to_world(_path.waypoints[_current_waypoint_index])
	var dir: Vector2 = (wp_world - transform.position)
	var dist_to_wp: float = dir.length()

	if dist_to_wp <= WAYPOINT_REACH_THRESHOLD:
		_current_waypoint_index += 1
		if _current_waypoint_index >= _path.waypoints.size():
			movement.velocity = Vector2.ZERO
			return true
		wp_world = map.grid_to_world(_path.waypoints[_current_waypoint_index])
		dir = wp_world - transform.position

	if dir.length() > 0.0:
		movement.velocity = dir.normalized() * _get_move_speed(movement)
	else:
		movement.velocity = Vector2.ZERO

	return false


func _needs_new_path(agent_grid: Vector2i, target_grid: Vector2i, map: Service_Map) -> bool:
	if _path == null:
		return true
	if target_grid != _last_target_grid:
		_last_target_grid = target_grid
		return true
	if not map.is_path_still_valid(_path):
		return true
	return false


func _check_stuck(current_pos: Vector2, delta: float) -> bool:
	if current_pos.distance_to(_last_position) < 2.0:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
		_last_position = current_pos
	return _stuck_timer >= STUCK_TIMEOUT


func _build_nav_context(agent_entity: Entity) -> NavigationContext:
	var camp := agent_entity.get_component(CCamp)
	var faction: int = camp.camp if camp else -1
	return NavigationContext.create(faction, false, 1.0)


func _move_direct(transform: CTransform, movement: CMovement, target_pos: Vector2) -> bool:
	var direction: Vector2 = target_pos - transform.position
	var distance: float = direction.length()
	if distance <= reach_threshold:
		movement.velocity = Vector2.ZERO
		return true
	movement.velocity = direction.normalized() * _get_move_speed(movement)
	return false


func _get_move_speed(movement: CMovement) -> float:
	return movement.get_patrol_speed()
```

- [ ] **Step 3: Run integration tests T1, T2, T3**

Run each test config via the test runner and verify PASS.

- [ ] **Step 4: Commit**

```bash
git add gol-project/scripts/gameplay/goap/actions/move_to.gd gol-project/tests/integration/pathfinding/test_npc_pathfinds_around_wall.gd gol-project/tests/integration/pathfinding/test_npc_direct_path_no_wall.gd gol-project/tests/integration/pathfinding/test_npc_unreachable_target.gd
git commit -m "feat(nav): rewrite GOAP MoveTo with path-following and stuck detection"
```

---

## Task 7: ChaseTarget + Wander — Path Following Variants

**Files:**
- Modify: `gol-project/scripts/gameplay/goap/actions/chase_target.gd`
- Modify: `gol-project/scripts/gameplay/goap/actions/wander.gd`

- [ ] **Step 1: Update chase_target.gd with pathfinding + drift threshold**

Replace the direct velocity assignment in `chase_target.gd`. The key change: instead of `movement.velocity = normalized_direction * movement.max_speed`, use path following with a 3-tile drift threshold before repath.

Add these fields and methods to the class:

```gdscript
# Add after class declaration, before _init:
const CHASE_REPATH_DRIFT: int = 3
const CHASE_WAYPOINT_REACH: float = 12.0
const CHASE_STUCK_TIMEOUT: float = 3.0

var _path: PathResult = null
var _current_waypoint_index: int = 0
var _last_target_grid: Vector2i = Vector2i(-99999, -99999)
var _last_position: Vector2 = Vector2.ZERO
var _stuck_timer: float = 0.0
```

In `perform()`, replace the velocity assignment block (line `movement.velocity = normalized_direction * movement.max_speed`) with path-following that calls `ServiceContext.map().find_path()`. The enemy-specific `_build_nav_context()` should use faction=ENEMY and check entity for can_break_doors (Raider).

- [ ] **Step 2: Update wander.gd to use find_path**

In `_perform_wander()`, after computing `current_target`, convert to grid and call `find_path()`. If path invalid, pick a new random target. Follow waypoints instead of direct vector.

- [ ] **Step 3: Run existing GOAP tests to verify no regression**

Run: `godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/unit/ai/ 2>&1 | grep -E "PASS|FAIL"`
Expected: All existing AI tests still pass.

- [ ] **Step 4: Commit**

```bash
git add gol-project/scripts/gameplay/goap/actions/chase_target.gd gol-project/scripts/gameplay/goap/actions/wander.gd
git commit -m "feat(nav): add pathfinding to ChaseTarget (drift threshold) and Wander"
```

---

## Task 8: SBuildSiteComplete — mark_blocked on Build

**Files:**
- Modify: `gol-project/scripts/systems/s_build_site_complete.gd`

- [ ] **Step 1: Add mark_blocked call after building spawn**

In `_complete_building()`, after the building entity is spawned and positioned (after line 53 `building_transform.position = spawn_pos`), add:

```gdscript
	# Register building as navigation obstacle
	var map := ServiceContext.map()
	if map and building_entity.has_component(CBuilding):
		var grid_pos: Vector2i = map.world_to_grid(spawn_pos)
		map.mark_blocked(grid_pos)
```

- [ ] **Step 2: Verify build system still works (run existing integration tests)**

Run any existing build-related tests.

- [ ] **Step 3: Commit**

```bash
git add gol-project/scripts/systems/s_build_site_complete.gd
git commit -m "feat(nav): mark_blocked on building completion"
```

---

## Task 9: Remaining Integration Tests (T6-T21)

**Files:**
- Create: `gol-project/tests/integration/pathfinding/test_player_passes_open_door.gd` (T6-T7)
- Create: `gol-project/tests/integration/pathfinding/test_door_permissions.gd` (T8-T10)
- Create: `gol-project/tests/integration/pathfinding/test_danger_zone_avoidance.gd` (T11-T13)
- Create: `gol-project/tests/integration/pathfinding/test_dynamic_obstacle_response.gd` (T14-T16)
- Create: `gol-project/tests/integration/pathfinding/test_special_entities.gd` (T17-T20)
- Create: `gol-project/tests/integration/pathfinding/test_stuck_detection.gd` (T21)

- [ ] **Step 1: Write T6-T7 (door pass/block for player)**

Tests verify player passes through open door tile, and is blocked by closed door tile. Pattern: set door state via `map.set_door_state()`, give player velocity toward door, assert position after N frames.

- [ ] **Step 2: Write T8-T10 (door permissions for NPCs)**

Tests verify: friendly NPC paths through own closed door (cost=2), enemy routes around player door (cost=INF), raider routes through player door (cost=20 < detour).

- [ ] **Step 3: Write T11-T13 (danger zone avoidance)**

Tests verify: normal NPC detours around danger zone when alternative exists, crosses when forced, poison enemy ignores danger.

- [ ] **Step 4: Write T14-T16 (dynamic obstacle response)**

Tests verify: path invalidation when wall placed mid-route, path update when door opens, path update when wall removed.

- [ ] **Step 5: Write T17-T20 (special entities)**

Tests verify: bullet destroyed at wall, worker pathfinds around wall for full cycle, rabbit flees around wall, raider marches around obstacles toward campfire.

- [ ] **Step 6: Write T21 (stuck detection)**

Test verifies: NPC surrounded by dynamically placed walls triggers fail_plan within 3 seconds.

- [ ] **Step 7: Run all integration tests**

Run all tests in `tests/integration/pathfinding/` directory.
Expected: All PASS.

- [ ] **Step 8: Commit**

```bash
git add gol-project/tests/integration/pathfinding/
git commit -m "test(nav): add complete integration test suite (T6-T21)"
```

---

## Task 10: Bullet Wall Destruction in SMove

**Files:**
- Modify: `gol-project/scripts/systems/s_move.gd`

- [ ] **Step 1: Add bullet destruction on wall contact**

In `_apply_movement()`, when `is_position_blocked(new_grid)` is true and the entity has `CBullet`, destroy it instead of sliding:

```gdscript
func _apply_movement(entity: Entity, move: CMovement, transform: CTransform, delta: float) -> void:
	if move.velocity.length_squared() < 0.01:
		return

	var map := ServiceContext.map()
	if map == null:
		transform.position += move.velocity * delta
		return

	var new_pos: Vector2 = transform.position + move.velocity * delta
	var new_grid: Vector2i = map.world_to_grid(new_pos)

	if not map.is_position_blocked(new_grid):
		transform.position = new_pos
		return

	# Bullets are destroyed on wall contact
	if entity.has_component(CBullet):
		entity.add_component(CDead.new())
		return

	# Axis-separated sliding for non-bullets
	var slide_x := Vector2(new_pos.x, transform.position.y)
	if not map.is_position_blocked(map.world_to_grid(slide_x)):
		transform.position = slide_x
		return

	var slide_y := Vector2(transform.position.x, new_pos.y)
	if not map.is_position_blocked(map.world_to_grid(slide_y)):
		transform.position = slide_y
		return
```

- [ ] **Step 2: Run T17 bullet test**

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add gol-project/scripts/systems/s_move.gd
git commit -m "feat(nav): destroy bullets on wall contact in SMove"
```

---

## Task 11: Final Verification — Full Test Suite

- [ ] **Step 1: Run all unit tests**

Run: `godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/ 2>&1 | grep -E "PASS|FAIL|ERROR"`
Expected: All pass, no regressions.

- [ ] **Step 2: Run all integration tests**

Run each SceneConfig test in `tests/integration/pathfinding/` via test_main.tscn.
Expected: All 21 tests PASS.

- [ ] **Step 3: Run GOAP eval suite**

Run: `godot --headless --path gol-project --scene scenes/tests/goap_eval_main.tscn`
Expected: No crashes, planning metrics within normal ranges.

- [ ] **Step 4: Final commit (if any fixups needed)**

```bash
git commit -m "fix(nav): address test failures from full suite run"
```
