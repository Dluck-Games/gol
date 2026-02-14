# scripts/pcg/phases/tile_decide_phase.gd
class_name TileDecidePhase
extends PCGPhase
## Selects tile variants from pre-set candidates using Wave Function Collapse.
##
## Uses TileConstraints for WFC rules instead of hardcoded constraints.
## The key insight: constraints define what tiles can be adjacent, and WFC
## naturally selects valid configurations.
##
## INPUT: Assumes cell.data["tile_candidates"] is already set by TileResolvePhase.
## OUTPUT: Sets cell.data["tile_variant"] based on WFC constraint satisfaction.
## PRESERVES: tile_logic, tile_transition, tile_neighbor, tile_direction.
##
## Special handling:
## - Junction positions are detected for crosswalk placement
## - tile_id from RoadRasterizer provides initial orientation hints

const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const _TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")
const _WFCSolver := preload("res://scripts/pcg/wfc/wfc_solver.gd")
const _WFCRules := preload("res://scripts/pcg/wfc/wfc_rules.gd")
const _WFCTypes := preload("res://scripts/pcg/wfc/wfc_types.gd")
const _TileConstraints := preload("res://scripts/pcg/wfc/tile_constraints.gd")

## Direction offsets for TILE_LAYOUT_DIAMOND_DOWN
## In this layout: X axis goes down-right (SE), Y axis goes down-left (SW)
const ISO_NE := Vector2i(0, -1)   # Grid Y- = up-right = NE
const ISO_SW := Vector2i(0, 1)    # Grid Y+ = down-left = SW
const ISO_NW := Vector2i(-1, 0)   # Grid X- = up-left = NW
const ISO_SE := Vector2i(1, 0)    # Grid X+ = down-right = SE

## Junction node positions (grid coordinates) - populated during execute()
var _junction_positions: Array[Vector2i] = []


func execute(config: PCGConfig, context: PCGContext) -> void:
	# Pre-compute junction positions from road graph
	_compute_junction_positions(context)
	
	# Separate road and non-road cells for processing
	var road_cells: Array[Vector2i] = []
	var ground_cells: Array[Vector2i] = []
	
	for pos: Vector2i in context.grid.keys():
		var cell: PCGCell = context.get_cell(pos)
		if cell == null or not cell.data.has("tile_candidates"):
			continue
		
		if cell.is_road():
			road_cells.append(pos)
		else:
			ground_cells.append(pos)
	
	# Process road cells with WFC
	_process_road_cells_wfc(road_cells, context)
	
	# Process ground cells (sidewalks) - roads must be done first for crosswalk detection
	_process_ground_cells_wfc(ground_cells, context)


func _compute_junction_positions(context: PCGContext) -> void:
	## Find all junction nodes (nodes where 3+ edges meet) and store their grid positions.
	_junction_positions.clear()
	
	if context.road_graph == null:
		return
	
	var graph := context.road_graph
	
	# Count edges per node
	var node_edge_count: Dictionary = {}
	for edge: RoadGraph.RoadEdge in graph.edges:
		if not node_edge_count.has(edge.from_node):
			node_edge_count[edge.from_node] = 0
		if not node_edge_count.has(edge.to_node):
			node_edge_count[edge.to_node] = 0
		node_edge_count[edge.from_node] += 1
		node_edge_count[edge.to_node] += 1
	
	# Find junction nodes (3+ edges = intersection)
	for node: RoadGraph.RoadNode in node_edge_count.keys():
		var edge_count: int = node_edge_count[node]
		if edge_count >= 3:
			var grid_pos := Vector2i(roundi(node.position.x), roundi(node.position.y))
			_junction_positions.append(grid_pos)


func _process_road_cells_wfc(road_cells: Array[Vector2i], context: PCGContext) -> void:
	## Process road cells using WFC with TileConstraints rules.
	
	if road_cells.is_empty():
		return
	
	# Build WFC rules from TileConstraints
	var rules := _TileConstraints.build_road_rules()
	
	# Register any additional candidates not in default rules
	for pos in road_cells:
		var cell: PCGCell = context.get_cell(pos)
		for c: Variant in cell.data["tile_candidates"]:
			var candidate := str(c)
			if candidate not in rules.get_all_tiles():
				rules.register_tile(candidate)
				# Basic compatibility: can connect to anything
				for tile in rules.get_all_tiles():
					rules.add_all_directions(candidate, tile)
	
	# Create solver with context's RNG for determinism
	var solver := _WFCSolver.new(rules, context.rng)
	solver.backtracking_enabled = true
	
	# Initialize cells and apply preconditions
	for pos in road_cells:
		var cell: PCGCell = context.get_cell(pos)
		var candidates: Array[String] = []
		for c: Variant in cell.data["tile_candidates"]:
			candidates.append(str(c))
		
		solver.initialize_cell(pos, candidates)
		_apply_road_preconditions(pos, cell, solver, context)
	
	# Solve
	solver.solve()
	
	# Apply results
	for pos in road_cells:
		var result := solver.get_result(pos)
		var cell: PCGCell = context.get_cell(pos)
		
		if result.is_empty():
			var candidates = cell.data["tile_candidates"]
			result = candidates[0] if not candidates.is_empty() else "default"
		
		cell.data["tile_variant"] = result


func _apply_road_preconditions(pos: Vector2i, cell: PCGCell, solver: _WFCSolver, context: PCGContext) -> void:
	## Apply preconditions for road tiles based on context.
	
	var candidates: Array = cell.data["tile_candidates"]
	
	# Priority 1: Junction detection - crosswalk at junction approaches
	if _is_crosswalk_position_near_junction(pos, context):
		if "crosswalk" in candidates:
			solver.set_precondition(pos, "crosswalk")
			return
	
	# Priority 2: Use tile_id from RoadRasterizer if available
	if cell.data.has("tile_id"):
		var tile_id: String = cell.data["tile_id"]
		var variant := _map_tile_id_to_variant(tile_id)
		if variant != "" and variant in candidates:
			solver.set_precondition(pos, variant)
			return
	
	# Priority 3: Use neighbor analysis for orientation
	var preferred := _get_preferred_road_variant(pos, context, candidates)
	if preferred != "":
		solver.set_precondition(pos, preferred)


func _is_crosswalk_position_near_junction(pos: Vector2i, context: PCGContext) -> bool:
	## Check if position is at a crosswalk position near a junction.
	
	if _junction_positions.is_empty():
		return _is_intersection_by_neighbors(pos, context)
	
	var radius: int = 2
	if context.road_graph != null:
		var nearby_nodes := context.road_graph.get_nodes_near(Vector2(pos.x, pos.y), 10.0)
		for node: RoadGraph.RoadNode in nearby_nodes:
			radius = maxi(radius, ceili(node.width / 2.0))
	
	for junction_pos: Vector2i in _junction_positions:
		if _is_crosswalk_position(pos, junction_pos, radius):
			return true
	
	return false


func _is_crosswalk_position(pos: Vector2i, junction_pos: Vector2i, radius: int) -> bool:
	## Determine if a position is a valid crosswalk location.
	var dx := pos.x - junction_pos.x
	var dy := pos.y - junction_pos.y
	var abs_dx := absi(dx)
	var abs_dy := absi(dy)
	
	var half_width := maxi(1, radius / 2)
	var min_edge := maxi(1, radius - 1)
	var max_edge := radius
	
	var on_vertical_approach := (abs_dy >= min_edge and abs_dy <= max_edge) and (abs_dx <= half_width)
	var on_horizontal_approach := (abs_dx >= min_edge and abs_dx <= max_edge) and (abs_dy <= half_width)
	
	if abs_dx == 0 and abs_dy == 0:
		return false
	
	if on_vertical_approach and abs_dx == 0:
		return true
	if on_horizontal_approach and abs_dy == 0:
		return true
	
	return false


func _is_intersection_by_neighbors(pos: Vector2i, context: PCGContext) -> bool:
	## Fallback: detect intersections by checking road neighbors on both axes.
	var has_nw: bool = _is_road(pos + ISO_NW, context)
	var has_se: bool = _is_road(pos + ISO_SE, context)
	var has_sw: bool = _is_road(pos + ISO_SW, context)
	var has_ne: bool = _is_road(pos + ISO_NE, context)
	
	var has_vertical: bool = has_nw or has_se
	var has_horizontal: bool = has_sw or has_ne
	
	if not (has_vertical and has_horizontal):
		return false
	
	var road_count: int = 0
	if has_nw: road_count += 1
	if has_se: road_count += 1
	if has_sw: road_count += 1
	if has_ne: road_count += 1
	
	return road_count >= 3


func _map_tile_id_to_variant(tile_id: String) -> String:
	## Map RoadRasterizer tile_id to tile variant name.
	match tile_id:
		"road_urban_center":
			return "center_v"
		"road_urban_center_h":
			return "center_h"
		"road_urban":
			return "basic"
	return ""


func _get_preferred_road_variant(pos: Vector2i, context: PCGContext, candidates: Array) -> String:
	## Determine preferred road variant based on neighbor analysis.
	var has_nw: bool = _is_road(pos + ISO_NW, context)
	var has_se: bool = _is_road(pos + ISO_SE, context)
	var has_sw: bool = _is_road(pos + ISO_SW, context)
	var has_ne: bool = _is_road(pos + ISO_NE, context)
	
	var has_vertical: bool = has_nw or has_se
	var has_horizontal: bool = has_sw or has_ne
	
	var preferred_variant: String = ""
	if has_vertical and not has_horizontal:
		preferred_variant = "center_v"
	elif has_horizontal and not has_vertical:
		preferred_variant = "center_h"
	
	if preferred_variant != "" and preferred_variant in candidates:
		return preferred_variant
	
	return ""


func _process_ground_cells_wfc(ground_cells: Array[Vector2i], context: PCGContext) -> void:
	## Process ground cells (sidewalks) using TileConstraints rules.
	
	if ground_cells.is_empty():
		return
	
	# Build WFC rules from TileConstraints
	var rules := _TileConstraints.build_sidewalk_rules()
	
	# Register any additional candidates not in default rules
	for pos in ground_cells:
		var cell: PCGCell = context.get_cell(pos)
		for c: Variant in cell.data["tile_candidates"]:
			var candidate := str(c)
			if candidate not in rules.get_all_tiles():
				rules.register_tile(candidate)
				# Basic compatibility for unknown tiles
				for tile in rules.get_all_tiles():
					if tile == "basic" or tile.begins_with("edge_") or tile.begins_with("corner_"):
						rules.add_all_directions(candidate, tile)
	
	var solver := _WFCSolver.new(rules, context.rng)
	solver.backtracking_enabled = true
	
	# Initialize cells and apply direction-based preconditions
	for pos in ground_cells:
		var cell: PCGCell = context.get_cell(pos)
		var candidates: Array[String] = []
		for c: Variant in cell.data["tile_candidates"]:
			candidates.append(str(c))
		
		solver.initialize_cell(pos, candidates)
		_apply_ground_preconditions(pos, cell, solver, context)
	
	solver.solve()
	
	# Apply results
	for pos in ground_cells:
		var result := solver.get_result(pos)
		var cell: PCGCell = context.get_cell(pos)
		
		if result.is_empty():
			var candidates = cell.data["tile_candidates"]
			result = candidates[0] if not candidates.is_empty() else "default"
		
		cell.data["tile_variant"] = result


func _apply_ground_preconditions(pos: Vector2i, cell: PCGCell, solver: _WFCSolver, context: PCGContext) -> void:
	## Apply preconditions for ground tiles based on transition type and direction.
	
	var candidates: Array = cell.data["tile_candidates"]
	var transition: int = cell.data.get("tile_transition", _TileAssetResolver.TransitionType.NONE)
	
	# Determine variant based on transition type and road neighbor direction
	var variant := _get_variant_from_neighbors(pos, transition, context, candidates)
	
	if variant != "" and variant in candidates:
		# Check for crosswalk variant if neighbor road is crosswalk
		if transition == _TileAssetResolver.TransitionType.EDGE:
			var crosswalk_variant := variant + "_crosswalk"
			if crosswalk_variant in candidates and _has_crosswalk_neighbor_at(pos, context):
				solver.set_precondition(pos, crosswalk_variant)
				return
		
		solver.set_precondition(pos, variant)
		return
	
	# Fallback: use first candidate
	if not candidates.is_empty():
		solver.set_precondition(pos, str(candidates[0]))


func _get_variant_from_neighbors(pos: Vector2i, transition: int, context: PCGContext, candidates: Array) -> String:
	## Determine tile variant based on transition type and road neighbor positions.
	var Trans := _TileAssetResolver.TransitionType
	
	# Analyze road neighbors
	var road_nw: bool = _is_road(pos + ISO_NW, context)
	var road_ne: bool = _is_road(pos + ISO_NE, context)
	var road_sw: bool = _is_road(pos + ISO_SW, context)
	var road_se: bool = _is_road(pos + ISO_SE, context)
	
	match transition:
		Trans.EDGE:
			# Direction points to the single road neighbor
			if road_nw: return "edge_road_nw"
			if road_ne: return "edge_road_ne"
			if road_sw: return "edge_road_sw"
			if road_se: return "edge_road_se"
		
		Trans.CORNER:
			# Corner naming: corner points in cardinal direction (n, s, e, w)
			# corner_road_n: points North, has roads at NW and NE
			# corner_road_s: points South, has roads at SW and SE
			# corner_road_e: points East, has roads at NE and SE
			# corner_road_w: points West, has roads at NW and SW
			if road_nw and road_ne: return "corner_road_n"   # Roads at NW+NE = North corner
			if road_sw and road_se: return "corner_road_s"   # Roads at SW+SE = South corner
			if road_ne and road_se: return "corner_road_e"   # Roads at NE+SE = East corner
			if road_nw and road_sw: return "corner_road_w"   # Roads at NW+SW = West corner
		
		Trans.OPPOSITE, Trans.END, Trans.ISOLATED, Trans.NONE:
			# These use basic tiles
			return "basic" if "basic" in candidates else ""
	
	return ""


func _has_crosswalk_neighbor_at(pos: Vector2i, context: PCGContext) -> bool:
	## Check if any adjacent road is a crosswalk.
	for offset in [ISO_NW, ISO_NE, ISO_SW, ISO_SE]:
		if _is_crosswalk_at(pos + offset, context):
			return true
	return false


func _is_road(pos: Vector2i, context: PCGContext) -> bool:
	var cell: PCGCell = context.get_cell(pos)
	if cell == null:
		return false
	return cell.is_road()


func _is_crosswalk_at(pos: Vector2i, context: PCGContext) -> bool:
	## Check if road at position is a crosswalk.
	var cell: PCGCell = context.get_cell(pos)
	if cell == null or not cell.is_road():
		return false
	
	if cell.data.has("tile_variant") and cell.data["tile_variant"] == "crosswalk":
		return true
	
	return _is_crosswalk_position_near_junction(pos, context)
