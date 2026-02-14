# tests/pcg/test_zone_smoother.gd
extends GdUnitTestSuite
## TDD (RED): Contract tests for ZoneSmoother PCG phase.
## Defines expected behavior:
## - Extends PCGPhase
## - execute(config, context) reads/modifies zone_type in unified grid cells IN PLACE
## - Reads road cells from unified grid (logic_type == ROAD) to preserve roads
## - Cellular automata smoothing using Moore neighborhood (8 neighbors, incl diagonals)
## - Majority rule: cell becomes the neighbor-majority zone type (if different)
## - Road preservation: cells in context.road_cells NEVER change and must remain URBAN
## - Iterations: configurable via config.zone_smoothing_iterations (int, >= 0)
## - Boundary handling: edges use only available in-bounds neighbors

# NOTE: This preload is intentional for RED phase.
# The referenced script may not exist yet and will be implemented next.
const ZoneSmoother := preload("res://scripts/pcg/phases/zone_smoother.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")

const PCGPhase := preload("res://scripts/pcg/pipeline/pcg_phase.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")

const _GRID_SIZE: int = 100


# Local test config to drive iteration count without modifying PCGConfig yet.
class PCGConfigWithSmoothingIterations extends PCGConfig:
	var zone_smoothing_iterations: int = 1


func test_zone_smoother_extends_pcg_phase() -> void:
	var phase := ZoneSmoother.new()
	assert_object(phase).is_not_null()
	assert_bool(phase is PCGPhase).is_true()

	assert_bool(phase.has_method("execute")).is_true()
	assert_int(Callable(phase, "execute").get_argument_count()).is_equal(2)


func test_execute_modifies_context_zone_map_in_place() -> void:
	var config := PCGConfigWithSmoothingIterations.new()
	config.zone_smoothing_iterations = 1

	var context := _context_with_filled_grid(ZoneMap.ZoneType.WILDERNESS)

	# Make a change that must be smoothed (prove mutation happened).
	var center := Vector2i(0, 0)
	context.get_or_create_cell(center).zone_type = ZoneMap.ZoneType.URBAN

	var phase := ZoneSmoother.new()
	phase.execute(config, context)

	# With all neighbors wilderness, the isolated URBAN must flip to WILDERNESS.
	assert_bool(context.grid.has(center)).is_true()
	assert_int(context.grid[center].zone_type).is_equal(ZoneMap.ZoneType.WILDERNESS)


func test_isolated_urban_cell_in_wilderness_becomes_wilderness() -> void:
	# Single URBAN cell surrounded by 8 WILDERNESS cells
	# After smoothing -> becomes WILDERNESS (majority rule)
	var config := PCGConfigWithSmoothingIterations.new()
	config.zone_smoothing_iterations = 1

	var context := _context_with_filled_grid(ZoneMap.ZoneType.WILDERNESS)
	var center := Vector2i(0, 0)
	context.get_or_create_cell(center).zone_type = ZoneMap.ZoneType.URBAN

	var phase := ZoneSmoother.new()
	phase.execute(config, context)

	assert_bool(context.grid.has(center)).is_true()
	assert_int(context.grid[center].zone_type).is_equal(ZoneMap.ZoneType.WILDERNESS)


func test_isolated_wilderness_cell_in_urban_becomes_urban() -> void:
	# Single WILDERNESS cell surrounded by 8 URBAN cells
	# After smoothing -> becomes URBAN
	var config := PCGConfigWithSmoothingIterations.new()
	config.zone_smoothing_iterations = 1

	var context := _context_with_filled_grid(ZoneMap.ZoneType.URBAN)
	var center := Vector2i(0, 0)
	context.get_or_create_cell(center).zone_type = ZoneMap.ZoneType.WILDERNESS

	var phase := ZoneSmoother.new()
	phase.execute(config, context)

	assert_bool(context.grid.has(center)).is_true()
	assert_int(context.grid[center].zone_type).is_equal(ZoneMap.ZoneType.URBAN)


func test_road_cells_never_change() -> void:
	# Road cells (marked in unified grid as ROAD) must stay URBAN
	# Even if surrounded by WILDERNESS
	var config := PCGConfigWithSmoothingIterations.new()
	config.zone_smoothing_iterations = 3

	var context := _context_with_filled_grid(ZoneMap.ZoneType.WILDERNESS)
	var road_cell := Vector2i(0, 0)
	var cell := context.get_or_create_cell(road_cell)
	cell.zone_type = ZoneMap.ZoneType.URBAN
	cell.logic_type = TileAssetResolver.LogicType.ROAD

	var phase := ZoneSmoother.new()
	phase.execute(config, context)

	# Road cell must remain URBAN and preserve its road flag
	assert_bool(context.grid.has(road_cell)).is_true()
	assert_int(context.grid[road_cell].zone_type).is_equal(ZoneMap.ZoneType.URBAN)
	assert_bool(context.grid[road_cell].logic_type == TileAssetResolver.LogicType.ROAD).is_true()


func test_multiple_iterations_increase_smoothing() -> void:
	# 1 iteration vs 3 iterations
	# More iterations = more smoothing (small urban "island" is removed more aggressively)
	var center := Vector2i(0, 0)

	# Run with 1 iteration
	var config_1 := PCGConfigWithSmoothingIterations.new()
	config_1.zone_smoothing_iterations = 1

	var context_1 := _context_with_filled_grid(ZoneMap.ZoneType.WILDERNESS)
	_set_rect_grid(context_1, Rect2i(center - Vector2i(1, 1), Vector2i(3, 3)), ZoneMap.ZoneType.URBAN)

	var phase := ZoneSmoother.new()
	phase.execute(config_1, context_1)

	# After 1 iteration, the 3x3 block must have its corners smoothed away (5-cell plus remains).
	var expected_urban_after_1: Array[Vector2i] = [
		center,
		center + Vector2i(0, -1),
		center + Vector2i(0, 1),
		center + Vector2i(-1, 0),
		center + Vector2i(1, 0),
	]
	for cell: Vector2i in expected_urban_after_1:
		assert_bool(context_1.grid.has(cell)).is_true()
		assert_int(context_1.grid[cell].zone_type).is_equal(ZoneMap.ZoneType.URBAN)

	var expected_wilderness_after_1: Array[Vector2i] = [
		center + Vector2i(-1, -1),
		center + Vector2i(1, -1),
		center + Vector2i(-1, 1),
		center + Vector2i(1, 1),
	]
	for cell: Vector2i in expected_wilderness_after_1:
		assert_bool(context_1.grid.has(cell)).is_true()
		assert_int(context_1.grid[cell].zone_type).is_equal(ZoneMap.ZoneType.WILDERNESS)

	# Run with 3 iterations
	var config_3 := PCGConfigWithSmoothingIterations.new()
	config_3.zone_smoothing_iterations = 3

	var context_3 := _context_with_filled_grid(ZoneMap.ZoneType.WILDERNESS)
	_set_rect_grid(context_3, Rect2i(center - Vector2i(1, 1), Vector2i(3, 3)), ZoneMap.ZoneType.URBAN)

	phase.execute(config_3, context_3)

	# After 3 iterations, the entire original 3x3 area must be smoothed back to WILDERNESS.
	var rect_3x3 := Rect2i(center - Vector2i(1, 1), Vector2i(3, 3))
	for y: int in range(rect_3x3.position.y, rect_3x3.position.y + rect_3x3.size.y):
		for x: int in range(rect_3x3.position.x, rect_3x3.position.x + rect_3x3.size.x):
			var pos: Vector2i = Vector2i(x, y)
			assert_bool(context_3.grid.has(pos)).is_true()
			assert_int(context_3.grid[pos].zone_type).is_equal(ZoneMap.ZoneType.WILDERNESS)


func test_boundary_cells_use_available_neighbors_only() -> void:
	# Cells at grid edges have fewer neighbors
	# Smoothing must use ONLY in-bounds neighbors (not treat out-of-bounds as WILDERNESS)
	#
	# Corner (-50,-50) has only 3 neighbors: (-49,-50), (-50,-49), (-49,-49).
	# If those 3 are URBAN and the cell is WILDERNESS, it must flip to URBAN.
	var config := PCGConfigWithSmoothingIterations.new()
	config.zone_smoothing_iterations = 1

	var context := _context_with_filled_grid(ZoneMap.ZoneType.WILDERNESS)
	context.get_or_create_cell(Vector2i(-49, -50)).zone_type = ZoneMap.ZoneType.URBAN
	context.get_or_create_cell(Vector2i(-50, -49)).zone_type = ZoneMap.ZoneType.URBAN
	context.get_or_create_cell(Vector2i(-49, -49)).zone_type = ZoneMap.ZoneType.URBAN
	# (-50, -50) stays WILDERNESS from _context_with_filled_grid

	var phase := ZoneSmoother.new()
	phase.execute(config, context)

	assert_bool(context.grid.has(Vector2i(-50, -50))).is_true()
	assert_int(context.grid[Vector2i(-50, -50)].zone_type).is_equal(ZoneMap.ZoneType.URBAN)


func test_smoothing_uses_moore_neighborhood_including_diagonals() -> void:
	# Verifies diagonals are counted (Moore neighborhood), not just 4-neighbor.
	#
	# Center starts WILDERNESS.
	# Orthogonal neighbors: 3 WILDERNESS + 1 URBAN
	# Diagonal neighbors: 4 URBAN
	# Moore counts => URBAN=5, WILDERNESS=3 => center must become URBAN
	# 4-neighbor counts would be URBAN=1, WILDERNESS=3 => would stay WILDERNESS
	var config := PCGConfigWithSmoothingIterations.new()
	config.zone_smoothing_iterations = 1

	var context := _context_with_filled_grid(ZoneMap.ZoneType.WILDERNESS)
	var c := Vector2i(0, 0)
	context.get_or_create_cell(c).zone_type = ZoneMap.ZoneType.WILDERNESS

	# Orthogonal (make exactly 1 URBAN, 3 WILDERNESS)
	context.get_or_create_cell(c + Vector2i(1, 0)).zone_type = ZoneMap.ZoneType.URBAN
	context.get_or_create_cell(c + Vector2i(-1, 0)).zone_type = ZoneMap.ZoneType.WILDERNESS
	context.get_or_create_cell(c + Vector2i(0, 1)).zone_type = ZoneMap.ZoneType.WILDERNESS
	context.get_or_create_cell(c + Vector2i(0, -1)).zone_type = ZoneMap.ZoneType.WILDERNESS

	# Diagonals (4 URBAN)
	context.get_or_create_cell(c + Vector2i(1, 1)).zone_type = ZoneMap.ZoneType.URBAN
	context.get_or_create_cell(c + Vector2i(1, -1)).zone_type = ZoneMap.ZoneType.URBAN
	context.get_or_create_cell(c + Vector2i(-1, 1)).zone_type = ZoneMap.ZoneType.URBAN
	context.get_or_create_cell(c + Vector2i(-1, -1)).zone_type = ZoneMap.ZoneType.URBAN

	var phase := ZoneSmoother.new()
	phase.execute(config, context)

	assert_bool(context.grid.has(c)).is_true()
	assert_int(context.grid[c].zone_type).is_equal(ZoneMap.ZoneType.URBAN)


# -------------------------
# Helpers
# -------------------------

## Creates a PCGContext with a fully-populated 100x100 grid centered at (0,0).
func _context_with_filled_grid(default_zone: int) -> PCGContext:
	var context := PCGContext.new(1)
	var half_size: int = _GRID_SIZE / 2
	var start: int = -half_size
	var end: int = _GRID_SIZE - half_size

	for y: int in range(start, end):
		for x: int in range(start, end):
			context.get_or_create_cell(Vector2i(x, y)).zone_type = default_zone
	return context


## Sets zone_type for all cells in a rectangle within the grid.
func _set_rect_grid(context: PCGContext, rect: Rect2i, zone_type: int) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			context.get_or_create_cell(Vector2i(x, y)).zone_type = zone_type
