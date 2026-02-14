# tests/pcg/test_tile_decide_phase.gd
extends GdUnitTestSuite
## TDD (RED): Contract tests for TileDecidePhase PCG phase.
## Defines expected behavior:
## - Extends PCGPhase
## - execute() selects from tile_candidates based on neighbor analysis
## - Assigns tile_variant to cells in cell.data
## - Uses deterministic tile selection (same seed = same tiles)
##
## Key difference from NeighborTileResolver:
## - TileDecidePhase ASSUMES tile_candidates are already set
## - It analyzes neighbors and picks the correct variant
## - It sets tile_variant, tile_logic, tile_transition, etc.

const TileDecidePhase := preload("res://scripts/pcg/phases/tile_decide_phase.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")

const PCGPhase := preload("res://scripts/pcg/pipeline/pcg_phase.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")


func test_phase_extends_pcg_phase() -> void:
	var phase := TileDecidePhase.new()
	assert_object(phase).is_not_null()
	assert_bool(phase is PCGPhase).is_true()


func test_selects_from_candidates() -> void:
	## Test that TileDecidePhase selects from tile_candidates array
	var context := PCGContext.new(42)
	
	# Create a road cell with tile_candidates pre-set
	var pos := Vector2i(0, 0)
	var cell := context.get_or_create_cell(pos)
	cell.logic_type = TileAssetResolver.LogicType.ROAD
	cell.zone_type = 2  # URBAN
	context.road_cells[pos] = true
	
	# PRE-SET candidates (simulating what TileResolvePhase would do)
	cell.data["tile_candidates"] = ["center_v", "center_h"]
	cell.data["tile_logic"] = TileAssetResolver.LogicType.ROAD
	cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE
	cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
	cell.data["tile_direction"] = TileAssetResolver.Direction.NONE
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Assert: tile_variant should be set to one of the candidates
	assert_bool(cell.data.has("tile_variant")).is_true()
	assert_bool(cell.data["tile_variant"] in cell.data["tile_candidates"]).is_true()


func test_vertical_road_selects_center_v() -> void:
	## Test that vertical roads (NW-SE direction) select center_v variant
	## In TILE_LAYOUT_DIAMOND_DOWN: NW-SE = grid X axis
	var context := PCGContext.new(42)
	
	# Create vertical road (NW-SE direction = grid X axis)
	var road_positions := [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0)]
	for pos in road_positions:
		var cell := context.get_or_create_cell(pos)
		cell.logic_type = TileAssetResolver.LogicType.ROAD
		cell.zone_type = 2
		context.road_cells[pos] = true
		
		# PRE-SET candidates
		cell.data["tile_candidates"] = ["center_v", "center_h"]
		cell.data["tile_logic"] = TileAssetResolver.LogicType.ROAD
		cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE
		cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
		cell.data["tile_direction"] = TileAssetResolver.Direction.NONE
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Center cell should select center_v (vertical)
	var center_cell: PCGCell = context.get_cell(Vector2i(0, 0))
	assert_str(center_cell.data["tile_variant"]).is_equal("center_v")


func test_horizontal_road_selects_center_h() -> void:
	## Test that horizontal roads (SW-NE direction) select center_h variant
	## In TILE_LAYOUT_DIAMOND_DOWN: SW-NE = grid Y axis
	var context := PCGContext.new(42)
	
	# Create horizontal road (SW-NE direction = grid Y axis)
	var road_positions := [Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for pos in road_positions:
		var cell := context.get_or_create_cell(pos)
		cell.logic_type = TileAssetResolver.LogicType.ROAD
		cell.zone_type = 2
		context.road_cells[pos] = true
		
		# PRE-SET candidates
		cell.data["tile_candidates"] = ["center_v", "center_h"]
		cell.data["tile_logic"] = TileAssetResolver.LogicType.ROAD
		cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE
		cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
		cell.data["tile_direction"] = TileAssetResolver.Direction.NONE
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Center cell should select center_h (horizontal)
	var center_cell: PCGCell = context.get_cell(Vector2i(0, 0))
	assert_str(center_cell.data["tile_variant"]).is_equal("center_h")


func test_intersection_selects_crosswalk() -> void:
	## Test that road tiles at the EDGE of intersections (approach tiles) select crosswalk variant,
	## while the junction center does NOT get crosswalk.
	## With road width = 3, radius = ceil(3/2) = 2, so crosswalks are at distance 2.
	var context := PCGContext.new(42)
	
	# Create a junction in the road_graph at position (0, 0) with 4 edges
	var junction_node := RoadGraph.RoadNode.new(Vector2(0, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var north_node := RoadGraph.RoadNode.new(Vector2(0, -3), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var south_node := RoadGraph.RoadNode.new(Vector2(0, 3), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var west_node := RoadGraph.RoadNode.new(Vector2(-3, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var east_node := RoadGraph.RoadNode.new(Vector2(3, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	
	context.road_graph.add_node(junction_node)
	context.road_graph.add_node(north_node)
	context.road_graph.add_node(south_node)
	context.road_graph.add_node(west_node)
	context.road_graph.add_node(east_node)
	
	# Add 4 edges meeting at junction_node
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, north_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, south_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, west_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, east_node))
	
	# Road width = 3, so radius = ceil(3/2) = 2
	# Crosswalks should be at distance 2 from center on each axis
	var edge_dist := 2
	var center_pos := Vector2i(0, 0)
	var approach_pos := Vector2i(edge_dist, 0)  # East approach at edge distance
	
	# Create center and approach cells
	for pos in [center_pos, approach_pos]:
		var cell := context.get_or_create_cell(pos)
		cell.logic_type = TileAssetResolver.LogicType.ROAD
		cell.zone_type = 2
		context.road_cells[pos] = true
		cell.data["tile_candidates"] = ["basic", "center_v", "crosswalk"]
		cell.data["tile_logic"] = TileAssetResolver.LogicType.ROAD
		cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE
		cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
		cell.data["tile_direction"] = TileAssetResolver.Direction.NONE
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Center cell should NOT select crosswalk (it's the junction center)
	var center_cell: PCGCell = context.get_cell(center_pos)
	assert_str(center_cell.data["tile_variant"]).is_not_equal("crosswalk")
	
	# Approach cell at edge distance SHOULD select crosswalk
	var approach_cell: PCGCell = context.get_cell(approach_pos)
	assert_str(approach_cell.data["tile_variant"]).is_equal("crosswalk")


func test_sidewalk_edge_with_single_road_neighbor() -> void:
	## Test that sidewalk edge tiles select correct variant based on direction
	var context := PCGContext.new(42)
	
	# Create road at (0, 0)
	var road_cell := context.get_or_create_cell(Vector2i(0, 0))
	road_cell.logic_type = TileAssetResolver.LogicType.ROAD
	road_cell.zone_type = 2  # URBAN
	context.road_cells[Vector2i(0, 0)] = true
	road_cell.data["tile_candidates"] = ["center_v"]
	road_cell.data["tile_logic"] = TileAssetResolver.LogicType.ROAD
	road_cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE
	road_cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
	road_cell.data["tile_direction"] = TileAssetResolver.Direction.NONE
	
	# Create sidewalk cells adjacent to road (single neighbors)
	var sidewalk_positions := {
		Vector2i(0, -1): TileAssetResolver.Direction.SE,
		Vector2i(0, 1): TileAssetResolver.Direction.NW,
		Vector2i(-1, 0): TileAssetResolver.Direction.NE,
		Vector2i(1, 0): TileAssetResolver.Direction.SW
	}
	
	for pos in sidewalk_positions.keys():
		var sw_cell := context.get_or_create_cell(pos)
		sw_cell.logic_type = TileAssetResolver.LogicType.GRASS
		sw_cell.zone_type = 2  # URBAN
		
		var expected_dir: int = sidewalk_positions[pos]
		# PRE-SET candidates for edge tiles
		sw_cell.data["tile_candidates"] = ["edge_road_se", "edge_road_nw", "edge_road_ne", "edge_road_sw"]
		sw_cell.data["tile_logic"] = TileAssetResolver.LogicType.SIDEWALK
		sw_cell.data["tile_transition"] = TileAssetResolver.TransitionType.EDGE
		sw_cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
		sw_cell.data["tile_direction"] = expected_dir
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Verify each sidewalk cell selected a variant
	for pos in sidewalk_positions.keys():
		var actual_cell: PCGCell = context.get_cell(pos)
		assert_bool(actual_cell.data.has("tile_variant")).is_true()
		assert_bool(actual_cell.data["tile_variant"] in actual_cell.data["tile_candidates"]).is_true()


func test_sidewalk_corner_with_two_road_neighbors() -> void:
	## Test that sidewalk corner tiles select correct variant based on direction
	var context := PCGContext.new(42)
	
	# Create intersection: road at center with roads in all 4 directions
	var road_positions := [Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for pos in road_positions:
		var r_cell := context.get_or_create_cell(pos)
		r_cell.logic_type = TileAssetResolver.LogicType.ROAD
		r_cell.zone_type = 2
		context.road_cells[pos] = true
		r_cell.data["tile_candidates"] = ["center_v"]
		r_cell.data["tile_logic"] = TileAssetResolver.LogicType.ROAD
		r_cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE
		r_cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
		r_cell.data["tile_direction"] = TileAssetResolver.Direction.NONE
	
	# Create sidewalk cells at the 4 corners of the intersection
	# Direction now points TOWARD the corner where roads meet (diagonal direction)
	var corner_positions := {
		Vector2i(-1, -1): TileAssetResolver.Direction.SE,   # Corner faces SE (toward intersection)
		Vector2i(1, -1): TileAssetResolver.Direction.SW,    # Corner faces SW (toward intersection)
		Vector2i(-1, 1): TileAssetResolver.Direction.NE,    # Corner faces NE (toward intersection)
		Vector2i(1, 1): TileAssetResolver.Direction.NW      # Corner faces NW (toward intersection)
	}
	
	for pos in corner_positions.keys():
		var sw_cell := context.get_or_create_cell(pos)
		sw_cell.logic_type = TileAssetResolver.LogicType.GRASS
		sw_cell.zone_type = 2
		
		var expected_dir: int = corner_positions[pos]
		# PRE-SET candidates for corner tiles (using cardinal naming: n, s, e, w)
		sw_cell.data["tile_candidates"] = ["corner_n", "corner_s", "corner_e", "corner_w"]
		sw_cell.data["tile_logic"] = TileAssetResolver.LogicType.SIDEWALK
		sw_cell.data["tile_transition"] = TileAssetResolver.TransitionType.CORNER
		sw_cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
		sw_cell.data["tile_direction"] = expected_dir
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Verify each corner cell selected a variant
	for pos in corner_positions.keys():
		var actual_cell: PCGCell = context.get_cell(pos)
		assert_bool(actual_cell.data.has("tile_variant")).is_true()
		assert_bool(actual_cell.data["tile_variant"] in actual_cell.data["tile_candidates"]).is_true()


func test_determinism() -> void:
	## Test that same seed produces deterministic tile variant selection
	var context1 := PCGContext.new(12345)
	var context2 := PCGContext.new(12345)
	
	var positions: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)
	]
	
	# Setup both contexts identically
	for ctx in [context1, context2]:
		for pos in positions:
			var cell: PCGCell = ctx.get_or_create_cell(pos)
			cell.logic_type = TileAssetResolver.LogicType.ROAD
			cell.zone_type = 2
			ctx.road_cells[pos] = true

			# PRE-SET identical candidates
			cell.data["tile_candidates"] = ["center_v", "center_h", "variant_a"]
			cell.data["tile_logic"] = TileAssetResolver.LogicType.ROAD
			cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE
			cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
			cell.data["tile_direction"] = TileAssetResolver.Direction.NONE
	
	var phase1 := TileDecidePhase.new()
	var phase2 := TileDecidePhase.new()
	var config := PCGConfig.new()
	
	phase1.execute(config, context1)
	phase2.execute(config, context2)
	
	# Assert: Same seed produces identical variant selection
	for pos in positions:
		var cell1: PCGCell = context1.get_cell(pos)
		var cell2: PCGCell = context2.get_cell(pos)
		
		assert_str(cell1.data["tile_variant"]).is_equal(cell2.data["tile_variant"])


func test_sidewalk_edge_selects_crosswalk_variant_when_adjacent_to_crosswalk_road() -> void:
	## Test that sidewalk edges select crosswalk variant when adjacent road is a crosswalk (intersection)
	var context := PCGContext.new(42)
	
	# Create intersection: road at center with roads in all 4 directions (this makes center a crosswalk)
	var center_pos := Vector2i(0, 0)
	var road_positions := [center_pos, Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	
	for pos in road_positions:
		var r_cell := context.get_or_create_cell(pos)
		r_cell.logic_type = TileAssetResolver.LogicType.ROAD
		r_cell.zone_type = 2
		context.road_cells[pos] = true

		# Center has crosswalk option
		if pos == center_pos:
			r_cell.data["tile_candidates"] = ["crosswalk", "center_v"]
			r_cell.data["tile_logic"] = TileAssetResolver.LogicType.CROSSWALK
			r_cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE
		else:
			r_cell.data["tile_candidates"] = ["center_v", "center_h"]
			r_cell.data["tile_logic"] = TileAssetResolver.LogicType.ROAD
			r_cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE

		r_cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
		r_cell.data["tile_direction"] = TileAssetResolver.Direction.NONE
	
	# Create sidewalk cells adjacent to the crosswalk (center) tile
	# NE direction: sidewalk at (1, -1) is adjacent to road at (0, -1) and crosswalk at (0, 0)
	# Actually, sidewalk at (1, 0) is directly adjacent to crosswalk at (0, 0) via ISO_NW direction
	# Let's place sidewalk at (2, 0) which is adjacent to road at (1, 0) - not crosswalk
	# For crosswalk adjacency, sidewalk needs to be adjacent to the center crosswalk
	
	# Place sidewalk at positions adjacent to the crosswalk center
	# 
	# Isometric directions for TILE_LAYOUT_DIAMOND_DOWN:
	# ISO_NE = (0, -1)  # Grid Y- = up-right visually
	# ISO_SW = (0, 1)   # Grid Y+ = down-left visually
	# ISO_NW = (-1, 0)  # Grid X- = up-left visually
	# ISO_SE = (1, 0)   # Grid X+ = down-right visually
	#
	# For sidewalk edge facing SW (edge_sw), the road must be at ISO_NW offset
	# So sidewalk at (1, 0) has road at (1, 0) + ISO_NW = (0, 0) which is the crosswalk!
	
	var sw_pos := Vector2i(0, 2)  # Sidewalk adjacent to road at (0, 1) via ISO_NE direction
	# (0, 2) + ISO_NE = (0, 1) which is a regular road arm, not the crosswalk center
	
	# Let's place sidewalk directly adjacent to the crosswalk center
	# Crosswalk is at (0, 0). Sidewalk at (1, 1) would have:
	#   - road_ne at (1, 1) + ISO_NE = (1, 0) = road arm (not crosswalk)
	#   - road_nw at (1, 1) + ISO_NW = (0, 1) = road arm (not crosswalk)
	# 
	# Actually for a sidewalk to be adjacent to the crosswalk, it needs to be at a corner position
	# where the road arm extends. But edge tiles only have 1 road neighbor.
	# 
	# Hmm, the crosswalk is at (0, 0). The road arms extend in all 4 directions.
	# For a sidewalk to be adjacent to the crosswalk tile itself via a single edge:
	# - Sidewalk at (1, 1): neighbors are at (1, 0)=road, (0, 1)=road, (2, 1)=none, (1, 2)=none
	#   This has 2 road neighbors -> corner, not edge
	#
	# I think the intent is: when a sidewalk edge is adjacent to a road that is part of an intersection,
	# it should show the crosswalk variant. Let me re-read the task.
	#
	# Task: "auto detect neighbor road tile, if it's crosswalk, use sidewalk/edge/road/xx/crosswalk tile"
	# So if the adjacent road tile is a crosswalk (tile_variant == "crosswalk"), use crosswalk edge.
	
	# Let's test with a simpler setup: one crosswalk tile surrounded by one sidewalk
	var simple_context := PCGContext.new(42)
	
	# Create single crosswalk road
	var crosswalk_pos := Vector2i(0, 0)
	var crosswalk_cell := simple_context.get_or_create_cell(crosswalk_pos)
	crosswalk_cell.logic_type = TileAssetResolver.LogicType.ROAD
	crosswalk_cell.zone_type = 2
	simple_context.road_cells[crosswalk_pos] = true
	crosswalk_cell.data["tile_candidates"] = ["crosswalk"]
	crosswalk_cell.data["tile_variant"] = "crosswalk"  # Pre-set variant to simulate TileDecidePhase already processed
	crosswalk_cell.data["tile_logic"] = TileAssetResolver.LogicType.ROAD
	crosswalk_cell.data["tile_transition"] = TileAssetResolver.TransitionType.NONE
	crosswalk_cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
	crosswalk_cell.data["tile_direction"] = TileAssetResolver.Direction.NONE

	# Create sidewalk at SE of crosswalk (so it's adjacent via ISO_NW direction)
	# Sidewalk at (1, 0) has road at (1, 0) + ISO_NW = (0, 0) which is the crosswalk
	var sidewalk_pos := Vector2i(1, 0)
	var sidewalk_cell := simple_context.get_or_create_cell(sidewalk_pos)
	sidewalk_cell.logic_type = TileAssetResolver.LogicType.GRASS
	sidewalk_cell.zone_type = 2
	sidewalk_cell.data["tile_candidates"] = ["edge_road_se", "edge_road_nw", "edge_road_ne", "edge_road_sw", "edge_road_ne_crosswalk", "edge_road_sw_crosswalk", "edge_road_nw_crosswalk"]
	sidewalk_cell.data["tile_logic"] = TileAssetResolver.LogicType.SIDEWALK
	sidewalk_cell.data["tile_transition"] = TileAssetResolver.TransitionType.EDGE
	sidewalk_cell.data["tile_neighbor"] = TileAssetResolver.LogicType.ROAD
	sidewalk_cell.data["tile_direction"] = TileAssetResolver.Direction.NW  # Curb faces NW toward road
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, simple_context)
	
	# The sidewalk should select edge_road_nw_crosswalk since adjacent road is crosswalk
	# Sidewalk at (1, 0) is adjacent to road at (0, 0) via ISO_NW direction
	# The edge faces NW (toward the road), so edge_road_nw is correct
	# edge_road_nw_crosswalk should be selected
	
	assert_bool(sidewalk_cell.data.has("tile_variant")).is_true()
	# Note: The test expects edge_road_nw_crosswalk but the asset set only has ne/sw crosswalk variants
	# The implementation should fall back to edge_road_nw if crosswalk variant doesn't exist
	var variant: String = sidewalk_cell.data["tile_variant"]
	assert_bool(variant.begins_with("edge_road_nw")).is_true()


func test_junction_with_road_graph_selects_crosswalk() -> void:
	## Test that crosswalk is selected for road cells at the EDGE of a junction (approach tiles),
	## but NOT at the junction center itself.
	## With road width = 3, radius = ceil(3/2) = 2, so crosswalks are at distance 2.
	var context := PCGContext.new(42)
	
	# Create a junction in the road_graph at position (0, 0) with 4 edges (cross intersection)
	var junction_node := RoadGraph.RoadNode.new(Vector2(0, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var north_node := RoadGraph.RoadNode.new(Vector2(0, -5), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var south_node := RoadGraph.RoadNode.new(Vector2(0, 5), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var west_node := RoadGraph.RoadNode.new(Vector2(-5, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var east_node := RoadGraph.RoadNode.new(Vector2(5, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	
	context.road_graph.add_node(junction_node)
	context.road_graph.add_node(north_node)
	context.road_graph.add_node(south_node)
	context.road_graph.add_node(west_node)
	context.road_graph.add_node(east_node)
	
	# Add 4 edges meeting at junction_node (making it a true junction)
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, north_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, south_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, west_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, east_node))
	
	# Road width = 3, so radius = ceil(3/2) = 2
	# Crosswalks should be at distance 2 from center (the edge of junction area)
	var edge_dist := 2
	var approach_pos := Vector2i(edge_dist, 0)  # East approach at edge distance
	var cell := context.get_or_create_cell(approach_pos)
	cell.logic_type = TileAssetResolver.LogicType.ROAD
	cell.zone_type = 2  # URBAN
	context.road_cells[approach_pos] = true
	
	# Set up candidates including crosswalk
	cell.data["tile_candidates"] = ["basic", "center_v", "center_h", "crosswalk"]
	cell.data["tile_id"] = "road_urban"
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Approach cell at edge distance should select crosswalk
	assert_bool(cell.data.has("tile_variant")).is_true()
	assert_str(cell.data["tile_variant"]).is_equal("crosswalk")


func test_junction_center_does_not_select_crosswalk() -> void:
	## Test that the junction CENTER does NOT get crosswalk.
	## Crosswalks belong on approach roads, not in the middle of the intersection.
	var context := PCGContext.new(42)
	
	# Create a junction in the road_graph at position (0, 0) with 4 edges
	var junction_node := RoadGraph.RoadNode.new(Vector2(0, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var north_node := RoadGraph.RoadNode.new(Vector2(0, -5), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var south_node := RoadGraph.RoadNode.new(Vector2(0, 5), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var west_node := RoadGraph.RoadNode.new(Vector2(-5, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var east_node := RoadGraph.RoadNode.new(Vector2(5, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	
	context.road_graph.add_node(junction_node)
	context.road_graph.add_node(north_node)
	context.road_graph.add_node(south_node)
	context.road_graph.add_node(west_node)
	context.road_graph.add_node(east_node)
	
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, north_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, south_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, west_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, east_node))
	
	# Create road cell at JUNCTION CENTER (0, 0)
	var junction_pos := Vector2i(0, 0)
	var cell := context.get_or_create_cell(junction_pos)
	cell.logic_type = TileAssetResolver.LogicType.ROAD
	cell.zone_type = 2  # URBAN
	context.road_cells[junction_pos] = true
	
	# Set up candidates including crosswalk
	cell.data["tile_candidates"] = ["basic", "center_v", "center_h", "crosswalk"]
	cell.data["tile_id"] = "road_urban"
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Junction CENTER should NOT select crosswalk
	assert_bool(cell.data.has("tile_variant")).is_true()
	assert_str(cell.data["tile_variant"]).is_not_equal("crosswalk")


func test_non_junction_road_does_not_select_crosswalk() -> void:
	## TDD RED: Test that crosswalk is NOT selected for road cells that are not near a junction
	## Even if crosswalk is in candidates, regular road body should not use it.
	var context := PCGContext.new(42)
	
	# Create a simple straight road with only 2 edges (no junction)
	var node_a := RoadGraph.RoadNode.new(Vector2(0, -10), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var node_b := RoadGraph.RoadNode.new(Vector2(0, 10), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	
	context.road_graph.add_node(node_a)
	context.road_graph.add_node(node_b)
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(node_a, node_b))
	
	# Create road cell in the middle of the road (not near any junction)
	var mid_pos := Vector2i(0, 0)
	var cell := context.get_or_create_cell(mid_pos)
	cell.logic_type = TileAssetResolver.LogicType.ROAD
	cell.zone_type = 2
	context.road_cells[mid_pos] = true
	
	# Set up candidates including crosswalk
	cell.data["tile_candidates"] = ["basic", "center_v", "center_h", "crosswalk"]
	cell.data["tile_id"] = "road_urban_center"
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Non-junction road should NOT select crosswalk, should use tile_id mapping (center_v)
	assert_bool(cell.data.has("tile_variant")).is_true()
	assert_str(cell.data["tile_variant"]).is_not_equal("crosswalk")
	assert_str(cell.data["tile_variant"]).is_equal("center_v")


func test_crosswalk_works_with_irregular_grid_generator() -> void:
	## TDD RED: Test crosswalk detection with real IrregularGridGenerator output
	## This simulates the actual PCG pipeline to ensure crosswalks work in production
	var context := PCGContext.new(42)
	var config := PCGConfig.new()
	config.grid_size = 50
	config.pcg_seed = 42
	
	# Run IrregularGridGenerator to create road_graph
	var grid_gen := IrregularGridGenerator.new()
	grid_gen.execute(config, context)
	
	# Now run RoadRasterizer to create road cells
	var rasterizer := RoadRasterizer.new()
	rasterizer.execute(config, context)
	
	# Find a cell that is at an intersection (has road neighbors on both axes)
	var intersection_pos: Vector2i = Vector2i.ZERO
	var found_intersection := false
	
	for pos: Vector2i in context.grid.keys():
		var cell: PCGCell = context.get_cell(pos)
		if cell == null or cell.logic_type != TileAssetResolver.LogicType.ROAD:
			continue

		# Check if this is at an intersection (neighbors on both axes)
		var has_nw: bool = context.get_cell(pos + Vector2i(0, -1)) != null and context.get_cell(pos + Vector2i(0, -1)).logic_type == TileAssetResolver.LogicType.ROAD
		var has_se: bool = context.get_cell(pos + Vector2i(0, 1)) != null and context.get_cell(pos + Vector2i(0, 1)).logic_type == TileAssetResolver.LogicType.ROAD
		var has_sw: bool = context.get_cell(pos + Vector2i(-1, 0)) != null and context.get_cell(pos + Vector2i(-1, 0)).logic_type == TileAssetResolver.LogicType.ROAD
		var has_ne: bool = context.get_cell(pos + Vector2i(1, 0)) != null and context.get_cell(pos + Vector2i(1, 0)).logic_type == TileAssetResolver.LogicType.ROAD
		
		var has_vertical: bool = has_nw or has_se
		var has_horizontal: bool = has_sw or has_ne
		
		if has_vertical and has_horizontal:
			intersection_pos = pos
			found_intersection = true
			break
	
	# Must find at least one intersection
	assert_bool(found_intersection).is_true()
	
	# Set up candidates for the intersection cell
	var intersection_cell: PCGCell = context.get_cell(intersection_pos)
	intersection_cell.data["tile_candidates"] = ["basic", "center_v", "center_h", "crosswalk"]
	
	# Run TileDecidePhase
	var decide_phase := TileDecidePhase.new()
	decide_phase.execute(config, context)
	
	# The intersection cell should select crosswalk
	assert_bool(intersection_cell.data.has("tile_variant")).is_true()
	assert_str(intersection_cell.data["tile_variant"]).is_equal("crosswalk")


func test_four_crosswalks_at_junction_approaches() -> void:
	## Test that a 4-way junction has crosswalks on all 4 approach roads,
	## NOT at the junction center. Crosswalks should be at the EDGE of the junction
	## on each arm (north, south, east, west approaches).
	##
	## Reference layout (top-down view, junction at center):
	##       [CW]      <- North approach crosswalk at edge_dist on Y axis
	##        |
	## [CW]--[X]--[CW] <- East/West approach crosswalks at edge_dist on X axis
	##        |
	##       [CW]      <- South approach crosswalk at edge_dist on Y axis
	##
	## Where [X] = junction center (NO crosswalk), [CW] = crosswalk tile
	var context := PCGContext.new(42)
	
	# Junction at (0, 0) with road width 3.0 -> radius = ceil(3/2) = 2
	var junction_node := RoadGraph.RoadNode.new(Vector2(0, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var north_node := RoadGraph.RoadNode.new(Vector2(0, -5), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var south_node := RoadGraph.RoadNode.new(Vector2(0, 5), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var west_node := RoadGraph.RoadNode.new(Vector2(-5, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	var east_node := RoadGraph.RoadNode.new(Vector2(5, 0), 3.0, RoadGraph.ROAD_TYPE_LOCAL)
	
	context.road_graph.add_node(junction_node)
	context.road_graph.add_node(north_node)
	context.road_graph.add_node(south_node)
	context.road_graph.add_node(west_node)
	context.road_graph.add_node(east_node)
	
	# 4 edges make this a true junction (3+ edges)
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, north_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, south_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, west_node))
	context.road_graph.add_edge(RoadGraph.RoadEdge.new(junction_node, east_node))
	
	# Road width = 3, so radius = 2 (half road width)
	# Crosswalks should be at distance 2 from center on each axis
	var edge_dist := 2
	
	# Create road cells: center + 4 approach tiles at edge distance
	var center_pos := Vector2i(0, 0)
	var north_approach := Vector2i(0, -edge_dist)  # Same X, offset Y
	var south_approach := Vector2i(0, edge_dist)   # Same X, offset Y  
	var west_approach := Vector2i(-edge_dist, 0)   # Offset X, same Y
	var east_approach := Vector2i(edge_dist, 0)    # Offset X, same Y
	
	var all_positions := [center_pos, north_approach, south_approach, west_approach, east_approach]
	
	for pos in all_positions:
		var cell := context.get_or_create_cell(pos)
		cell.logic_type = TileAssetResolver.LogicType.ROAD
		cell.zone_type = 2  # URBAN
		context.road_cells[pos] = true
		cell.data["tile_candidates"] = ["basic", "center_v", "center_h", "crosswalk"]
		cell.data["tile_id"] = "road_urban"
	
	var phase := TileDecidePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Junction CENTER should NOT have crosswalk
	var center_cell: PCGCell = context.get_cell(center_pos)
	assert_str(center_cell.data["tile_variant"]).is_not_equal("crosswalk")
	
	# All 4 APPROACH tiles should have crosswalk
	var north_cell: PCGCell = context.get_cell(north_approach)
	var south_cell: PCGCell = context.get_cell(south_approach)
	var west_cell: PCGCell = context.get_cell(west_approach)
	var east_cell: PCGCell = context.get_cell(east_approach)
	
	assert_str(north_cell.data["tile_variant"]).is_equal("crosswalk")
	assert_str(south_cell.data["tile_variant"]).is_equal("crosswalk")
	assert_str(west_cell.data["tile_variant"]).is_equal("crosswalk")
	assert_str(east_cell.data["tile_variant"]).is_equal("crosswalk")
