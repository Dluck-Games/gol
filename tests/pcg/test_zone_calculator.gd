# tests/pcg/test_zone_calculator.gd
extends GdUnitTestSuite
## TDD (RED): Contract tests for ZoneCalculator PCG phase.
## Defines expected behavior:
## - Extends PCGPhase
## - execute(config, context) reads road cells from unified grid
## - Writes zone classifications into unified grid cells (zone_type field)
## - Computes Manhattan (4-neighbor) BFS distance to nearest road cell
## - Normalizes: norm_dist = float(distance) / float(max_distance) in [0.0, 1.0]
## - Assigns zones by thresholds (strictly '<'):
##     norm_dist < config.zone_threshold_suburbs -> URBAN
##     norm_dist < config.zone_threshold_urban   -> SUBURBS
##     else                                      -> WILDERNESS
##
## Map bounds contract for this phase:
## - ZoneCalculator classifies a fixed 100x100 grid centered at (0,0):
## - x,y in [-50..49] inclusive.

# NOTE: This preload is intentional for RED phase.
# The referenced script may not exist yet and will be implemented next.
const ZoneCalculator := preload("res://scripts/pcg/phases/zone_calculator.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")

const PCGPhase := preload("res://scripts/pcg/pipeline/pcg_phase.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")

const _GRID_SIZE: int = 100


func test_zone_calculator_extends_pcg_phase() -> void:
	var phase := ZoneCalculator.new()
	assert_object(phase).is_not_null()
	assert_bool(phase is PCGPhase).is_true()

	assert_bool(phase.has_method("execute")).is_true()
	assert_int(Callable(phase, "execute").get_argument_count()).is_equal(2)


func test_execute_populates_context_zone_map() -> void:
	var config := PCGConfig.new()
	var context := _context_with_roads([Vector2i(5, 5)])

	var phase := ZoneCalculator.new()
	phase.execute(config, context)

	# Contract: grid is populated with zone data for all cells in the 100x100 grid.
	assert_int(context.grid.size()).is_greater(0)

	# Contract: road cell itself is classified from distance=0 => URBAN (0 < suburbs threshold).
	var pos0: Vector2i = Vector2i(5, 5)
	assert_bool(context.grid.has(pos0)).is_true()
	assert_int(context.grid[pos0].zone_type).is_equal(ZoneMap.ZoneType.URBAN)


func test_cells_adjacent_to_roads_are_urban() -> void:
	# Given road at (5,5)
	# Expect (4,5), (6,5), (5,4), (5,6) are URBAN
	var config := PCGConfig.new()
	var context := _context_with_roads([Vector2i(5, 5)])

	var phase := ZoneCalculator.new()
	phase.execute(config, context)

	var expected_urban: Array[Vector2i] = [
		Vector2i(4, 5),
		Vector2i(6, 5),
		Vector2i(5, 4),
		Vector2i(5, 6),
	]

	for cell: Vector2i in expected_urban:
		# Primary: unified grid zone_type
		assert_bool(context.grid.has(cell)).is_true()
		assert_int(context.grid[cell].zone_type).is_equal(ZoneMap.ZoneType.URBAN)


func test_cells_far_from_roads_are_wilderness() -> void:
	# Given road at (0,0)
	# Expect cell at (-50,-50) is WILDERNESS
	var config := PCGConfig.new()
	var context := _context_with_roads([Vector2i(0, 0)])

	var phase := ZoneCalculator.new()
	phase.execute(config, context)

	var far := Vector2i(-50, -50)
	# Primary: unified grid zone_type for far cells
	assert_bool(context.grid.has(far)).is_true()
	assert_int(context.grid[far].zone_type).is_equal(ZoneMap.ZoneType.WILDERNESS)


func test_threshold_boundaries_respected() -> void:
	# Test exact threshold boundaries (strictly '<').
	# Uses road at (0,0) with known max_distance = 100 (to (-50,-50)).
	var config := PCGConfig.new()
	var max_distance: int = _max_distance_for_single_road_in_fixed_grid(Vector2i(0, 0))
	assert_int(max_distance).is_equal(100)

	var d_suburbs_boundary: int = 10
	var d_urban_boundary: int = 20

	# Choose thresholds that align exactly with integer distances (avoid float rounding in tests).
	config.zone_threshold_suburbs = float(d_suburbs_boundary) / float(max_distance)
	config.zone_threshold_urban = float(d_urban_boundary) / float(max_distance)

	var context := _context_with_roads([Vector2i(0, 0)])

	var phase := ZoneCalculator.new()
	phase.execute(config, context)

	# distance 9 => norm < suburbs_threshold => URBAN
	assert_bool(context.grid.has(Vector2i(9, 0))).is_true()
	assert_int(context.grid[Vector2i(9, 0)].zone_type).is_equal(ZoneMap.ZoneType.URBAN)

	# distance 10 => norm == suburbs_threshold => NOT URBAN => SUBURBS (since urban_threshold > suburbs_threshold)
	assert_bool(context.grid.has(Vector2i(10, 0))).is_true()
	assert_int(context.grid[Vector2i(10, 0)].zone_type).is_equal(ZoneMap.ZoneType.SUBURBS)

	# distance 19 => still < urban_threshold => SUBURBS
	assert_bool(context.grid.has(Vector2i(19, 0))).is_true()
	assert_int(context.grid[Vector2i(19, 0)].zone_type).is_equal(ZoneMap.ZoneType.SUBURBS)

	# distance 20 => norm == urban_threshold => NOT SUBURBS => WILDERNESS
	assert_bool(context.grid.has(Vector2i(20, 0))).is_true()
	assert_int(context.grid[Vector2i(20, 0)].zone_type).is_equal(ZoneMap.ZoneType.WILDERNESS)


func test_normalized_distance_increases_with_manhattan_distance() -> void:
	# Verifies BFS Manhattan distances drive a monotonic "less urban" classification.
	# Make thresholds very small so nearby/medium/far land in different zones.
	var config := PCGConfig.new()
	var max_distance: int = _max_distance_for_single_road_in_fixed_grid(Vector2i(0, 0))
	assert_int(max_distance).is_equal(100)

	# Contract mapping:
	# norm < suburbs_threshold => URBAN
	# norm < urban_threshold   => SUBURBS
	# else                    => WILDERNESS
	config.zone_threshold_suburbs = 2.0 / float(max_distance) # dist 0..1 => URBAN; dist 2 => SUBURBS
	config.zone_threshold_urban = 4.0 / float(max_distance)   # dist 2..3 => SUBURBS; dist 4 => WILDERNESS

	var context := _context_with_roads([Vector2i(0, 0)])
	var phase := ZoneCalculator.new()
	phase.execute(config, context)

	var pos1: Vector2i = Vector2i(1, 0)
	var pos2: Vector2i = Vector2i(2, 0)
	var pos4: Vector2i = Vector2i(4, 0)

	# Primary: read zone_type from unified grid
	assert_bool(context.grid.has(pos1)).is_true()
	assert_bool(context.grid.has(pos2)).is_true()
	assert_bool(context.grid.has(pos4)).is_true()
	var zone_d1: int = context.grid[pos1].zone_type  # dist=1
	var zone_d2: int = context.grid[pos2].zone_type  # dist=2
	var zone_d4: int = context.grid[pos4].zone_type  # dist=4

	assert_int(zone_d1).is_equal(ZoneMap.ZoneType.URBAN)
	assert_int(zone_d2).is_equal(ZoneMap.ZoneType.SUBURBS)
	assert_int(zone_d4).is_equal(ZoneMap.ZoneType.WILDERNESS)

	# Monotonic contract: farther cells must not be more urban.
	assert_bool(zone_d1 > zone_d2).is_true()
	assert_bool(zone_d2 > zone_d4).is_true()


func test_bfs_is_manhattan_not_diagonal_distance() -> void:
	# Ensures 4-neighbor BFS is used (diagonal costs 2, not 1).
	# With road at (5,5):
	# - (6,5) is distance 1
	# - (6,6) is distance 2 (not 1)
	var config := PCGConfig.new()
	var max_distance: int = _max_distance_for_single_road_in_fixed_grid(Vector2i(5, 5))
	assert_int(max_distance).is_equal(110)

	# Make distance=1 be URBAN, distance=2 be SUBURBS.
	config.zone_threshold_suburbs = 2.0 / float(max_distance) # dist=1 => URBAN; dist=2 => SUBURBS (equality)
	config.zone_threshold_urban = 1.0 # keep everything else at least SUBURBS for this test

	var context := _context_with_roads([Vector2i(5, 5)])
	var phase := ZoneCalculator.new()
	phase.execute(config, context)

	assert_int(context.grid[Vector2i(6, 5)].zone_type).is_equal(ZoneMap.ZoneType.URBAN)
	assert_bool(context.grid.has(Vector2i(6, 6))).is_true()
	assert_int(context.grid[Vector2i(6, 6)].zone_type).is_equal(ZoneMap.ZoneType.SUBURBS)


# -------------------------
# Helpers
# -------------------------

func _context_with_roads(roads: Array[Vector2i]) -> PCGContext:
	var context := PCGContext.new(1)

	# Contract: ZoneCalculator reads from unified grid via road_cells view
	# Populate unified grid with road cells
	for cell: Vector2i in roads:
		var pcg_cell := context.get_or_create_cell(cell)
		pcg_cell.logic_type = TileAssetResolver.LogicType.ROAD

	# zone_map is now a computed view from unified grid - don't set it directly
	return context


func _max_distance_for_single_road_in_fixed_grid(road: Vector2i) -> int:
	# Contract helper for fixed 100x100 grid centered at (0,0).
	# Range [-50, 49] inclusive.
	var half_size: int = _GRID_SIZE / 2
	var start: int = -half_size
	var end: int = _GRID_SIZE - half_size - 1

	var corners: Array[Vector2i] = [
		Vector2i(start, start),
		Vector2i(end, start),
		Vector2i(start, end),
		Vector2i(end, end),
	]

	var max_d: int = 0
	for c: Vector2i in corners:
		var d: int = abs(c.x - road.x) + abs(c.y - road.y)
		if d > max_d:
			max_d = d
	return max_d
