# tests/pcg/test_rasterizer.gd
extends GdUnitTestSuite
## TDD (RED): Contract tests for RoadRasterizer PCG phase.
## Defines expected behavior:
## - Extends PCGPhase
## - execute() reads context.road_graph edges
## - Writes to context.road_cells: Dictionary[Vector2i, bool]
## - Uses Bresenham rasterization for line segments (inclusive endpoints)
## - Width expansion perpendicular to segment direction (width=1, width=3)
## - Intersections handled via Dictionary uniqueness

# NOTE: This preload is intentional for RED phase.
# The referenced script may not exist yet and will be implemented next.
const RoadRasterizer := preload("res://scripts/pcg/phases/road_rasterizer.gd")

const PCGPhase := preload("res://scripts/pcg/pipeline/pcg_phase.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const RoadGraph := preload("res://scripts/pcg/data/road_graph.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")


func test_road_rasterizer_extends_pcg_phase() -> void:
	var phase := RoadRasterizer.new()
	assert_object(phase).is_not_null()
	assert_bool(phase is PCGPhase).is_true()


func test_execute_initializes_context_road_cells_dictionary() -> void:
	var graph := RoadGraph.new()
	var context := _run_phase(graph)

	# Contract: PCGContext must expose a unified grid (Dictionary of PCGCell)
	_assert_context_has_property(context, "grid")
	var grid: Dictionary = context.grid
	assert_bool(grid is Dictionary).is_true()
	# If any cells exist in the grid, they must be PCGCell instances.
	for k: Variant in grid.keys():
		assert_bool(k is Vector2i).is_true()
		var v: Variant = grid[k]
		assert_bool(v is PCGCell).is_true()

	# Road cells extracted from grid must satisfy the dictionary contract
	var road_cells := _road_cells_from_grid(context)
	_assert_road_cells_dictionary_contract(road_cells)


func test_execute_with_empty_graph_results_in_empty_road_cells() -> void:
	var graph := RoadGraph.new()
	var context := _run_phase(graph)

	# Unified grid should contain no road cells
	var road_cells := _road_cells_from_grid(context)
	assert_int(road_cells.size()).is_equal(0)

	# Ensure grid contains no road cells (empty or no road flagged)
	var grid: Dictionary = context.grid
	if grid.size() > 0:
		for k: Variant in grid.keys():
			var cell: PCGCell = grid[k]
			assert_bool(cell is PCGCell).is_true()
			assert_bool(cell.logic_type == TileAssetResolver.LogicType.ROAD).is_false()


func test_execute_overwrites_existing_context_road_cells() -> void:
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(2, 0), 1)

	var phase := RoadRasterizer.new()
	var config := PCGConfig.new()
	var context := PCGContext.new(1)
	context.road_graph = graph

	# Pretend previous phase populated grid with old data
	var old_cell := PCGCell.new()
	context.set_cell(Vector2i(999, 999), old_cell)

	phase.execute(config, context)

	# Extract road cells directly from grid
	var road_cells := _road_cells_from_grid(context)
	assert_bool(road_cells.has(Vector2i(999, 999))).is_false()
	assert_bool(road_cells.has(Vector2i(0, 0))).is_true()

	# Grid should reflect the new road cells and not contain the old placeholder as road
	assert_bool(context.grid.has(Vector2i(999, 999))).is_true()  # Old cell still exists but isn't a road
	assert_bool(context.grid.has(Vector2i(0, 0))).is_true()
	var cell: PCGCell = context.grid[Vector2i(0, 0)]
	assert_bool(cell is PCGCell).is_true()
	assert_bool(cell.logic_type == TileAssetResolver.LogicType.ROAD).is_true()


func test_horizontal_segment_width_1_rasterizes_bresenham_inclusive_endpoints() -> void:
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(5, 0), 1)
	var cells := _road_cells_from_graph(graph)

	var expected := _expected_line_horizontal(Vector2i(0, 0), 5)
	_assert_cells_exact(cells, expected)


func test_vertical_segment_width_1_rasterizes_bresenham_inclusive_endpoints() -> void:
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(0, 5), 1)
	var cells := _road_cells_from_graph(graph)

	var expected := _expected_line_vertical(Vector2i(0, 0), 5)
	_assert_cells_exact(cells, expected)


func test_diagonal_segment_width_1_rasterizes_bresenham_45_degrees() -> void:
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(5, 5), 1)
	var cells := _road_cells_from_graph(graph)

	var expected: Dictionary[Vector2i, bool] = {}
	for i: int in range(0, 6):
		expected[Vector2i(i, i)] = true

	_assert_cells_exact(cells, expected)


func test_rasterizer_populates_grid_is_road() -> void:
	# Verify rasterizer sets PCGContext.grid cells with is_road == true
	var graph := _graph_with_edge(Vector2i(1, 1), Vector2i(3, 1), 1)
	var context := _run_phase(graph)

	var road_cells := _road_cells_from_grid(context)
	assert_int(road_cells.size()).is_equal(3)

	# Expected positions: (1,1),(2,1),(3,1)
	for x in range(1, 4):
		var pos := Vector2i(x, 1)
		assert_bool(road_cells.has(pos)).is_true()

		var cell: PCGCell = context.get_cell(pos)
		assert_object(cell).is_not_null()
		assert_bool(cell is PCGCell).is_true()
		assert_bool(cell.logic_type == TileAssetResolver.LogicType.ROAD).is_true()



func test_diagonal_segment_width_1_rasterizes_bresenham_shallow_slope() -> void:
	# Contract reference: Bresenham from (0,0) to (5,2) should yield:
	# (0,0),(1,0),(2,1),(3,1),(4,2),(5,2)
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(5, 2), 1)
	var cells := _road_cells_from_graph(graph)

	var expected: Dictionary[Vector2i, bool] = {
		Vector2i(0, 0): true,
		Vector2i(1, 0): true,
		Vector2i(2, 1): true,
		Vector2i(3, 1): true,
		Vector2i(4, 2): true,
		Vector2i(5, 2): true,
	}

	_assert_cells_exact(cells, expected)


func test_horizontal_segment_width_3_expands_perpendicular_in_y() -> void:
	# Width expansion contract (horizontal): expand in +/-Y around the centerline.
	# Segment (0,0)->(5,0), width=3 => y in {-1,0,1} for each x in [0..5]
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(5, 0), 3)
	var cells := _road_cells_from_graph(graph)

	var expected: Dictionary[Vector2i, bool] = {}
	for x: int in range(0, 6):
		expected[Vector2i(x, -1)] = true
		expected[Vector2i(x, 0)] = true
		expected[Vector2i(x, 1)] = true

	_assert_cells_exact(cells, expected)


func test_vertical_segment_width_3_expands_perpendicular_in_x() -> void:
	# Width expansion contract (vertical): expand in +/-X around the centerline.
	# Segment (0,0)->(0,5), width=3 => x in {-1,0,1} for each y in [0..5]
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(0, 5), 3)
	var cells := _road_cells_from_graph(graph)

	var expected: Dictionary[Vector2i, bool] = {}
	for y: int in range(0, 6):
		expected[Vector2i(-1, y)] = true
		expected[Vector2i(0, y)] = true
		expected[Vector2i(1, y)] = true

	_assert_cells_exact(cells, expected)


func test_intersection_crossing_segments_are_merged_via_dictionary_uniqueness() -> void:
	# Horizontal: (0,2)->(4,2) => 5 cells
	# Vertical:   (2,0)->(2,4) => 5 cells
	# Intersection at (2,2) counted once => 9 unique cells
	var graph := RoadGraph.new()

	var a0 := _node(Vector2i(0, 2), 1)
	var a1 := _node(Vector2i(4, 2), 1)
	var b0 := _node(Vector2i(2, 0), 1)
	var b1 := _node(Vector2i(2, 4), 1)

	graph.add_node(a0)
	graph.add_node(a1)
	graph.add_node(b0)
	graph.add_node(b1)
	graph.add_edge(RoadGraph.RoadEdge.new(a0, a1))
	graph.add_edge(RoadGraph.RoadEdge.new(b0, b1))

	var context := _run_phase(graph)
	var cells := _road_cells_from_grid(context)

	assert_bool(cells.has(Vector2i(2, 2))).is_true()
	assert_int(cells.size()).is_equal(9)

	# Contract: values are true (not counts, not tile IDs).
	assert_bool(bool(cells[Vector2i(2, 2)])).is_true()


# -------------------------
# Helpers
# -------------------------

func _run_phase(graph: RoadGraph) -> PCGContext:
	var phase := RoadRasterizer.new()
	var config := PCGConfig.new()
	var context := PCGContext.new(1)
	context.road_graph = graph

	phase.execute(config, context)
	return context


func _road_cells_from_graph(graph: RoadGraph) -> Dictionary:
	var context := _run_phase(graph)

	# Extract road cells directly from unified grid
	var cells := _road_cells_from_grid(context)
	_assert_road_cells_dictionary_contract(cells)

	# Validate unified grid consistency: each road cell position must have
	# a PCGCell in context.grid with is_road == true.
	_assert_context_has_property(context, "grid")
	assert_bool(context.grid is Dictionary).is_true()

	for pos: Variant in cells.keys():
		var pc: PCGCell = context.get_cell(pos as Vector2i)
		assert_object(pc).is_not_null()
		assert_bool(pc is PCGCell).is_true()
		assert_bool(pc.logic_type == TileAssetResolver.LogicType.ROAD).is_true()

	return cells


## Extracts road cells from the unified grid as Dictionary[Vector2i, bool].
func _road_cells_from_grid(context: PCGContext) -> Dictionary[Vector2i, bool]:
	var road_cells: Dictionary[Vector2i, bool] = {}
	for pos: Variant in context.grid.keys():
		if pos is Vector2i:
			var cell: PCGCell = context.grid[pos]
			if cell.logic_type == TileAssetResolver.LogicType.ROAD:
				road_cells[pos] = true
	return road_cells


func _assert_context_has_property(context: PCGContext, property_name: String) -> void:
	var props: Array[Dictionary] = context.get_property_list()
	for p: Dictionary in props:
		if String(p.get("name", "")) == property_name:
			return
	assert_bool(false).is_true() # fail: property not found


func _assert_road_cells_dictionary_contract(cells: Dictionary) -> void:
	# Contract: Dictionary[Vector2i, bool], values are true.
	for k: Variant in cells.keys():
		assert_bool(k is Vector2i).is_true()
		var v: Variant = cells[k]
		assert_bool(v is bool).is_true()
		assert_bool(bool(v)).is_true()


func _assert_cells_exact(actual: Dictionary, expected: Dictionary[Vector2i, bool]) -> void:
	# Exact match: same size, and every expected cell exists (no extras).
	assert_int(actual.size()).is_equal(expected.size())

	for pos: Vector2i in expected.keys():
		assert_bool(actual.has(pos)).is_true()
		assert_bool(bool(actual[pos])).is_true()

	for k: Variant in actual.keys():
		assert_bool(expected.has(k as Vector2i)).is_true()


func _graph_with_edge(from: Vector2i, to: Vector2i, width: int) -> RoadGraph:
	var graph := RoadGraph.new()
	var n0 := _node(from, width)
	var n1 := _node(to, width)
	graph.add_node(n0)
	graph.add_node(n1)
	graph.add_edge(RoadGraph.RoadEdge.new(n0, n1))
	return graph


func _node(pos: Vector2i, width: int) -> RoadGraph.RoadNode:
	# RoadRasterizer contract: uses node width to determine raster width.
	return RoadGraph.RoadNode.new(Vector2(float(pos.x), float(pos.y)), float(width), "MAIN")


func _expected_line_horizontal(start: Vector2i, length_inclusive: int) -> Dictionary[Vector2i, bool]:
	# start + (length_inclusive) steps along +X, inclusive of endpoints
	var expected: Dictionary[Vector2i, bool] = {}
	for x: int in range(start.x, start.x + length_inclusive + 1):
		expected[Vector2i(x, start.y)] = true
	return expected


func _expected_line_vertical(start: Vector2i, length_inclusive: int) -> Dictionary[Vector2i, bool]:
	# start + (length_inclusive) steps along +Y, inclusive of endpoints
	var expected: Dictionary[Vector2i, bool] = {}
	for y: int in range(start.y, start.y + length_inclusive + 1):
		expected[Vector2i(start.x, y)] = true
	return expected


# -------------------------
# Lane Marking Tests
# -------------------------

func test_width_1_road_has_no_lane_cells() -> void:
	# Width 1 roads should have no lane markings per design rule
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(5, 0), 1)
	var context := _run_phase(graph)

	# All cells should have has_lane == false
	for x in range(0, 6):
		var cell: PCGCell = context.get_cell(Vector2i(x, 0))
		assert_object(cell).is_not_null()
		assert_bool(cell.has_lane).is_false()


func test_width_2_road_has_no_lane_cells() -> void:
	# Width 2 roads (which produce 1 cell due to formula) should have no lane markings
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(5, 0), 2)
	var context := _run_phase(graph)

	# Width=2 -> half=0 -> actual_width=1, so only center cells exist
	for x in range(0, 6):
		var cell: PCGCell = context.get_cell(Vector2i(x, 0))
		assert_object(cell).is_not_null()
		assert_bool(cell.has_lane).is_false()


func test_width_3_road_has_lane_only_on_center_cell() -> void:
	# Width 3 roads should have lane marking ONLY on the center cell (offset 0)
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(5, 0), 3)
	var context := _run_phase(graph)

	# For horizontal road (0,0)->(5,0) with width=3, cells are at y=-1, 0, +1
	for x in range(0, 6):
		# Center row (offset 0) should have lane
		var center_cell: PCGCell = context.get_cell(Vector2i(x, 0))
		assert_object(center_cell).is_not_null()
		assert_bool(center_cell.has_lane).is_true()

		# Edge rows (offset -1, +1) should NOT have lane
		var top_cell: PCGCell = context.get_cell(Vector2i(x, -1))
		assert_object(top_cell).is_not_null()
		assert_bool(top_cell.has_lane).is_false()

		var bottom_cell: PCGCell = context.get_cell(Vector2i(x, 1))
		assert_object(bottom_cell).is_not_null()
		assert_bool(bottom_cell.has_lane).is_false()


func test_width_5_road_has_alternating_lane_pattern() -> void:
	# Width 5 roads should have alternating lanes: offsets -2, 0, +2 have lanes
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(3, 0), 5)
	var context := _run_phase(graph)

	# For horizontal road with width=5, cells are at y=-2,-1,0,+1,+2
	for x in range(0, 4):
		# Offsets 0, ±2 should have lane (even absolute offset)
		var center_cell: PCGCell = context.get_cell(Vector2i(x, 0))
		assert_object(center_cell).is_not_null()
		assert_bool(center_cell.has_lane).is_true()

		var top_outer_cell: PCGCell = context.get_cell(Vector2i(x, -2))
		assert_object(top_outer_cell).is_not_null()
		assert_bool(top_outer_cell.has_lane).is_true()

		var bottom_outer_cell: PCGCell = context.get_cell(Vector2i(x, 2))
		assert_object(bottom_outer_cell).is_not_null()
		assert_bool(bottom_outer_cell.has_lane).is_true()

		# Offsets ±1 should NOT have lane (odd absolute offset)
		var top_inner_cell: PCGCell = context.get_cell(Vector2i(x, -1))
		assert_object(top_inner_cell).is_not_null()
		assert_bool(top_inner_cell.has_lane).is_false()

		var bottom_inner_cell: PCGCell = context.get_cell(Vector2i(x, 1))
		assert_object(bottom_inner_cell).is_not_null()
		assert_bool(bottom_inner_cell.has_lane).is_false()


func test_horizontal_road_gets_vertical_lane_tile_id() -> void:
	# Horizontal road should use "road_urban_center" for lane cells (vertical lane markings)
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(3, 0), 3)
	var context := _run_phase(graph)

	# Check center cell (which has lane) has correct tile_id
	var center_cell: PCGCell = context.get_cell(Vector2i(1, 0))
	assert_object(center_cell).is_not_null()
	assert_bool(center_cell.has_lane).is_true()
	assert_str(center_cell.data.get("tile_id", "")).is_equal("road_urban_center")


func test_vertical_road_gets_horizontal_lane_tile_id() -> void:
	# Vertical road should use "road_urban_center_h" for lane cells (horizontal lane markings)
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(0, 3), 3)
	var context := _run_phase(graph)

	# Check center cell (which has lane) has correct tile_id
	var center_cell: PCGCell = context.get_cell(Vector2i(0, 1))
	assert_object(center_cell).is_not_null()
	assert_bool(center_cell.has_lane).is_true()
	assert_str(center_cell.data.get("tile_id", "")).is_equal("road_urban_center_h")


func test_non_lane_cells_get_road_urban_tile_id() -> void:
	# Non-lane road cells should have "road_urban" tile_id
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(3, 0), 3)
	var context := _run_phase(graph)

	# Check edge cells (which don't have lanes) have correct tile_id
	var top_cell: PCGCell = context.get_cell(Vector2i(1, -1))
	assert_object(top_cell).is_not_null()
	assert_bool(top_cell.has_lane).is_false()
	assert_str(top_cell.data.get("tile_id", "")).is_equal("road_urban")

	var bottom_cell: PCGCell = context.get_cell(Vector2i(1, 1))
	assert_object(bottom_cell).is_not_null()
	assert_bool(bottom_cell.has_lane).is_false()
	assert_str(bottom_cell.data.get("tile_id", "")).is_equal("road_urban")


# -------------------------
# Zone Type Tests (GitHub Issue #91)
# -------------------------

const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")


func test_road_cells_have_urban_zone_type() -> void:
	# Road cells should always have URBAN zone_type
	# This is important for incremental rasterization after OrganicBlockSubdivider
	var graph := _graph_with_edge(Vector2i(0, 0), Vector2i(5, 0), 3)
	var context := _run_phase(graph)

	# All road cells should have URBAN zone_type
	for x in range(0, 6):
		for y in range(-1, 2):
			var cell: PCGCell = context.get_cell(Vector2i(x, y))
			assert_object(cell).is_not_null()
			assert_int(cell.zone_type).is_equal(ZoneMap.ZoneType.URBAN)


func test_road_cells_urban_zone_preserved_after_incremental_rasterization() -> void:
	# Simulate incremental rasterization like OrganicBlockSubdivider does
	# First, create initial roads
	var graph := RoadGraph.new()
	var n1 := RoadGraph.RoadNode.new(Vector2(0, 0), 1.0, "ARTERIAL")
	var n2 := RoadGraph.RoadNode.new(Vector2(5, 0), 1.0, "ARTERIAL")
	graph.add_node(n1)
	graph.add_node(n2)
	graph.add_edge(RoadGraph.RoadEdge.new(n1, n2))

	var context := _run_phase(graph)

	# Now add more roads (simulating local streets)
	var n3 := RoadGraph.RoadNode.new(Vector2(0, 5), 1.0, "LOCAL")
	var n4 := RoadGraph.RoadNode.new(Vector2(5, 5), 1.0, "LOCAL")
	graph.add_node(n3)
	graph.add_node(n4)
	var new_edge := RoadGraph.RoadEdge.new(n3, n4)
	graph.add_edge(new_edge)

	# Incrementally rasterize the new edge
	var rasterizer := RoadRasterizer.new()
	rasterizer.rasterize_edges([new_edge], context)

	# New road cells should also have URBAN zone_type
	for x in range(0, 6):
		var cell: PCGCell = context.get_cell(Vector2i(x, 5))
		assert_object(cell).is_not_null()
		assert_int(cell.zone_type).is_equal(ZoneMap.ZoneType.URBAN)
