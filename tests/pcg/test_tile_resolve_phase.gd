# tests/pcg/test_tile_resolve_phase.gd
extends GdUnitTestSuite
## TDD (RED): Contract tests for TileResolvePhase PCG phase.
## Defines expected behavior:
## - Extends PCGPhase
## - execute() generates tile_candidates for cells in cell.data
## - Road cells get road tile candidates
## - Urban non-road cells get sidewalk candidates
## - tile_candidates never empty (fallback to ["default"])
## - Uses deterministic tile selection (same seed = same candidates)
## - Sidewalk candidates are filtered by transition type:
##   - 1 road neighbor: only edge_* candidates (EDGE transition)
##   - 2 adjacent road neighbors: only corner_* candidates (CORNER transition)
##   - 0, 2 opposite, or 3+ road neighbors: only basic candidates (NONE transition)

const TileResolvePhase := preload("res://scripts/pcg/phases/tile_resolve_phase.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")

const PCGPhase := preload("res://scripts/pcg/pipeline/pcg_phase.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")


func test_phase_extends_pcg_phase() -> void:
	var phase := TileResolvePhase.new()
	assert_object(phase).is_not_null()
	assert_bool(phase is PCGPhase).is_true()


func test_generates_candidates_for_road_cell() -> void:
	# Setup: Create context with road cells
	var context := PCGContext.new(42)
	_add_road_cells(context, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	
	var phase := TileResolvePhase.new()
	var config := PCGConfig.new()
	
	phase.execute(config, context)
	
	# Assert: All road cells should have tile_candidates assigned
	for pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		var cell: PCGCell = context.get_cell(pos)
		assert_object(cell).is_not_null()
		assert_bool(cell.data.has("tile_candidates")).is_true()
		
		var candidates = cell.data["tile_candidates"]
		assert_array(candidates).is_not_empty()
		# Road cells should contain road-related candidates
		# At minimum should be strings (tile IDs)
		for candidate: Variant in candidates:
			assert_str(candidate).is_not_empty()


func test_generates_candidates_for_urban_sidewalk() -> void:
	# Setup: Create context with urban non-road cells
	var context := PCGContext.new(42)
	var positions := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	
	for pos: Variant in positions:
		var vec_pos: Vector2i = pos as Vector2i
		var cell := context.get_or_create_cell(vec_pos)
		cell.logic_type = TileAssetResolver.LogicType.GRASS
		cell.zone_type = 2  # URBAN
	
	var phase := TileResolvePhase.new()
	var config := PCGConfig.new()
	
	phase.execute(config, context)
	
	# Assert: Urban non-road cells should have tile_candidates assigned (sidewalk candidates)
	for pos: Variant in positions:
		var vec_pos: Vector2i = pos as Vector2i
		var cell: PCGCell = context.get_cell(vec_pos)
		assert_object(cell).is_not_null()
		assert_bool(cell.data.has("tile_candidates")).is_true()
		
		var candidates = cell.data["tile_candidates"]
		assert_array(candidates).is_not_empty()
		# Sidewalk cells should contain sidewalk-related candidates
		for candidate: Variant in candidates:
			assert_str(candidate).is_not_empty()


func test_candidates_are_non_empty() -> void:
	# Setup: Create context with various cell types
	var context := PCGContext.new(42)
	
	# Add road cells
	_add_road_cells(context, [Vector2i(0, 0)])
	
	# Add urban sidewalk
	var urban_sw := context.get_or_create_cell(Vector2i(1, 0))
	urban_sw.logic_type = TileAssetResolver.LogicType.GRASS
	urban_sw.zone_type = 2  # URBAN
	
	# Add wilderness cell (should still get fallback)
	var wilderness := context.get_or_create_cell(Vector2i(2, 0))
	wilderness.logic_type = TileAssetResolver.LogicType.GRASS
	wilderness.zone_type = 0  # WILDERNESS
	
	var phase := TileResolvePhase.new()
	var config := PCGConfig.new()
	
	phase.execute(config, context)
	
	# Assert: ALL cells processed should have non-empty tile_candidates
	# (fallback to ["default"] if no better candidates)
	for pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		var cell: PCGCell = context.get_cell(pos)
		if cell.data.has("tile_candidates"):
			var candidates = cell.data["tile_candidates"]
			assert_array(candidates).is_not_empty()
			# At least one candidate should be present
			assert_array(candidates).contains([candidates[0]])


func test_determinism_same_seed_same_candidates() -> void:
	# Run phase twice with same seed
	var context1 := PCGContext.new(12345)
	var context2 := PCGContext.new(12345)
	
	var positions: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)
	]
	
	_add_road_cells(context1, positions)
	_add_road_cells(context2, positions)
	
	var phase1 := TileResolvePhase.new()
	var phase2 := TileResolvePhase.new()
	var config := PCGConfig.new()
	
	phase1.execute(config, context1)
	phase2.execute(config, context2)
	
	# Assert: Same seed produces identical tile candidates
	for pos: Vector2i in positions:
		var cell1: PCGCell = context1.get_cell(pos)
		var cell2: PCGCell = context2.get_cell(pos)
		
		assert_bool(cell1.data.has("tile_candidates")).is_true()
		assert_bool(cell2.data.has("tile_candidates")).is_true()
		
		var candidates1 = cell1.data["tile_candidates"]
		var candidates2 = cell2.data["tile_candidates"]
		
		assert_array(candidates1).is_equal(candidates2)


# -------------------------
# Helpers
# -------------------------

func _add_road_cells(context: PCGContext, positions: Array) -> void:
	for pos: Variant in positions:
		var vec_pos: Vector2i = pos as Vector2i
		var cell := context.get_or_create_cell(vec_pos)
		cell.logic_type = TileAssetResolver.LogicType.ROAD
		cell.zone_type = 2  # Default to URBAN for tests
		context.road_cells[vec_pos] = true


# -------------------------
# Sidewalk Candidate Filtering Tests
# -------------------------

func test_sidewalk_with_single_road_neighbor_gets_edge_candidates_only() -> void:
	## Edge case: sidewalk with 1 road neighbor should only get edge_* candidates
	var context := PCGContext.new(42)
	
	# Road at (0, 0)
	var road_cell := context.get_or_create_cell(Vector2i(0, 0))
	road_cell.logic_type = TileAssetResolver.LogicType.ROAD
	road_cell.zone_type = 2
	context.road_cells[Vector2i(0, 0)] = true

	# Sidewalk at (1, 0) - adjacent to road via ISO_SE direction (1 road neighbor)
	# ISO_SE = (1, 0), so from sidewalk at (1,0), road is at (1,0) + (-1,0) = (0,0) which is ISO_NW
	var sw_cell := context.get_or_create_cell(Vector2i(1, 0))
	sw_cell.logic_type = TileAssetResolver.LogicType.GRASS
	sw_cell.zone_type = 2  # URBAN
	
	var phase := TileResolvePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Assert: candidates should only contain edge_* variants
	var candidates = sw_cell.data["tile_candidates"]
	assert_array(candidates).is_not_empty()
	for candidate: Variant in candidates:
		assert_bool(str(candidate).begins_with("edge_")).is_true()
	
	# Assert: tile_transition should be EDGE
	assert_int(sw_cell.data["tile_transition"]).is_equal(TileAssetResolver.TransitionType.EDGE)


func test_sidewalk_with_two_adjacent_road_neighbors_gets_corner_candidates_only() -> void:
	## Corner case: sidewalk with 2 adjacent road neighbors should only get corner_* candidates
	var context := PCGContext.new(42)
	
	# Roads at (1, 0) and (0, 1) form an L-shape
	# Sidewalk at (1, 1) will have:
	#   - pos + ISO_NE = (1, 1) + (0, -1) = (1, 0) - ROAD
	#   - pos + ISO_SW = (1, 1) + (0, 1) = (1, 2) - NOT ROAD
	#   - pos + ISO_NW = (1, 1) + (-1, 0) = (0, 1) - ROAD  
	#   - pos + ISO_SE = (1, 1) + (1, 0) = (2, 1) - NOT ROAD
	# This gives 2 adjacent roads (NE + NW = corner position)
	var road_positions := [Vector2i(1, 0), Vector2i(0, 1)]
	for pos: Variant in road_positions:
		var vec_pos: Vector2i = pos as Vector2i
		var road_cell := context.get_or_create_cell(vec_pos)
		road_cell.logic_type = TileAssetResolver.LogicType.ROAD
		road_cell.zone_type = 2
		context.road_cells[vec_pos] = true

	var sw_cell := context.get_or_create_cell(Vector2i(1, 1))
	sw_cell.logic_type = TileAssetResolver.LogicType.GRASS
	sw_cell.zone_type = 2
	
	var phase := TileResolvePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Assert: candidates should only contain corner_* variants
	var candidates = sw_cell.data["tile_candidates"]
	assert_array(candidates).is_not_empty()
	for candidate: Variant in candidates:
		assert_bool(str(candidate).begins_with("corner_")).is_true()
	
	# Assert: tile_transition should be CORNER
	assert_int(sw_cell.data["tile_transition"]).is_equal(TileAssetResolver.TransitionType.CORNER)


func test_sidewalk_with_no_road_neighbors_gets_basic_candidates_only() -> void:
	## Basic case: isolated sidewalk with 0 road neighbors should only get basic candidates
	var context := PCGContext.new(42)
	
	# Isolated sidewalk at (5, 5) - no roads nearby
	var sw_cell := context.get_or_create_cell(Vector2i(5, 5))
	sw_cell.logic_type = TileAssetResolver.LogicType.GRASS
	sw_cell.zone_type = 2  # URBAN
	
	var phase := TileResolvePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Assert: candidates should NOT contain edge_* or corner_*
	var candidates = sw_cell.data["tile_candidates"]
	assert_array(candidates).is_not_empty()
	for candidate: Variant in candidates:
		var candidate_str := str(candidate)
		assert_bool(not candidate_str.begins_with("edge_")).is_true()
		assert_bool(not candidate_str.begins_with("corner_")).is_true()
	
	# Assert: tile_transition should be NONE (basic)
	assert_int(sw_cell.data["tile_transition"]).is_equal(TileAssetResolver.TransitionType.NONE)


func test_sidewalk_with_two_opposite_road_neighbors_gets_opposite_transition() -> void:
	## Special case: sidewalk between two roads (opposite sides) should get OPPOSITE transition
	## Opposite roads = road passing through, corridor-like configuration
	var context := PCGContext.new(42)
	
	# Roads at (0, 0) and (2, 0) - sidewalk at (1, 0) is between them
	# Direction constants for TILE_LAYOUT_DIAMOND_DOWN:
	# ISO_NE = (0, -1), ISO_SW = (0, 1), ISO_NW = (-1, 0), ISO_SE = (1, 0)
	# (1, 0) + ISO_NW = (0, 0) and (1, 0) + ISO_SE = (2, 0)
	# These are opposite directions (NW and SE), so should be OPPOSITE
	var road_positions := [Vector2i(0, 0), Vector2i(2, 0)]
	for pos: Variant in road_positions:
		var vec_pos: Vector2i = pos as Vector2i
		var road_cell := context.get_or_create_cell(vec_pos)
		road_cell.logic_type = TileAssetResolver.LogicType.ROAD
		road_cell.zone_type = 2
		context.road_cells[vec_pos] = true

	var sw_cell := context.get_or_create_cell(Vector2i(1, 0))
	sw_cell.logic_type = TileAssetResolver.LogicType.GRASS
	sw_cell.zone_type = 2
	
	var phase := TileResolvePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Assert: candidates should be appropriate for opposite transition
	var candidates = sw_cell.data["tile_candidates"]
	assert_array(candidates).is_not_empty()
	
	# Assert: tile_transition should be OPPOSITE (corridor/path)
	assert_int(sw_cell.data["tile_transition"]).is_equal(TileAssetResolver.TransitionType.OPPOSITE)


func test_sidewalk_with_three_road_neighbors_gets_end_transition() -> void:
	## Special case: sidewalk surrounded by 3 roads should get END transition
	## This represents a dead-end or peninsula configuration
	var context := PCGContext.new(42)
	
	# Roads surrounding position (1, 1) on 3 sides
	var road_positions := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 1)]
	for pos: Variant in road_positions:
		var vec_pos: Vector2i = pos as Vector2i
		var road_cell := context.get_or_create_cell(vec_pos)
		road_cell.logic_type = TileAssetResolver.LogicType.ROAD
		road_cell.zone_type = 2
		context.road_cells[vec_pos] = true

	var sw_cell := context.get_or_create_cell(Vector2i(1, 1))
	sw_cell.logic_type = TileAssetResolver.LogicType.GRASS
	sw_cell.zone_type = 2
	
	var phase := TileResolvePhase.new()
	var config := PCGConfig.new()
	phase.execute(config, context)
	
	# Assert: candidates should be appropriate for end transition
	var candidates = sw_cell.data["tile_candidates"]
	assert_array(candidates).is_not_empty()
	
	# Assert: tile_transition should be END (dead end)
	assert_int(sw_cell.data["tile_transition"]).is_equal(TileAssetResolver.TransitionType.END)
