class_name TileResolvePhase
extends PCGPhase
## Scans tile directories and generates candidate tile IDs for PCG cells.
## Filters sidewalk candidates by transition type (EDGE/CORNER/BASIC) based on
## road neighbor analysis.
##
## Tile ID generation algorithm:
## - Road (flat structure): filename without .png extension, "base" -> "basic"
## - Sidewalk (nested structure): builds ID from path components
##   - base.png (root) -> "basic"
##   - edge/road/{dir}/base.png -> "edge_{dir}"
##   - edge/road/{dir}/{variant}.png -> "edge_{dir}_{variant}"
##   - corner/road/{dir}/base.png -> "corner_{dir}"
##
## Transition type filtering:
## - 0 roads or 3+ roads: basic candidates only
## - 1 road: edge candidates only (EDGE transition)
## - 2 adjacent roads: corner candidates only (CORNER transition)
## - 2 opposite roads: basic candidates only (OPPOSITE transition)

const _TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")

const TILES_PATH := "res://assets/tiles/"
const ZONE_URBAN := 2

## Direction offsets for TILE_LAYOUT_DIAMOND_DOWN
## In this layout: X axis goes down-right (SE), Y axis goes down-left (SW)
const ISO_NE := Vector2i(0, -1)   # Grid Y- = up-right = NE
const ISO_SW := Vector2i(0, 1)    # Grid Y+ = down-left = SW
const ISO_NW := Vector2i(-1, 0)   # Grid X- = up-left = NW
const ISO_SE := Vector2i(1, 0)    # Grid X+ = down-right = SE

## LogicType -> Array[String] - Cached tile candidates per logic type
var _tile_map: Dictionary = {}

func _init() -> void:
	_scan_tile_directory()


func _scan_tile_directory() -> void:
	## Scan tile directories and populate _tile_map with available tile IDs.
	var logic_types := {
		_TileAssetResolver.LogicType.ROAD: "road",
		_TileAssetResolver.LogicType.SIDEWALK: "sidewalk",
	}
	
	for logic_type: int in logic_types:
		var dir_name: String = logic_types[logic_type]
		var candidates := _scan_logic_type_directory(dir_name)
		candidates.sort()
		_tile_map[logic_type] = candidates


func _scan_logic_type_directory(logic_name: String) -> Array[String]:
	## Recursively scan a logic type directory and extract tile IDs from file paths.
	var candidates: Array[String] = []
	var base_path := TILES_PATH.path_join(logic_name)
	
	_scan_directory_recursive(base_path, base_path, logic_name, candidates)
	return candidates


func _scan_directory_recursive(
	current_path: String,
	base_path: String,
	logic_name: String,
	candidates: Array[String]
) -> void:
	## Recursively scan directory and collect tile IDs.
	var dir := DirAccess.open(current_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
		
		var full_path := current_path.path_join(file_name)
		
		if dir.current_is_dir():
			# Recurse into subdirectory
			_scan_directory_recursive(full_path, base_path, logic_name, candidates)
		elif file_name.ends_with(".png") and not file_name.ends_with(".import"):
			# Extract tile ID from path
			var relative_path := full_path.substr(base_path.length() + 1)  # +1 for trailing /
			var tile_id := _path_to_tile_id(relative_path, logic_name)
			if tile_id != "" and tile_id not in candidates:
				candidates.append(tile_id)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()


func _path_to_tile_id(relative_path: String, logic_name: String) -> String:
	## Convert a relative file path to a tile ID.
	## 
	## Road (flat/nested structure):
	##   base.png -> "basic"
	##   h/crosswalk.png -> "h_crosswalk" (horizontal lane variants)
	##   v/crosswalk.png -> "v_crosswalk" (vertical lane variants)
	##
	## Sidewalk (nested structure) - path format:
	##   base.png -> "basic"
	##   grassground_1.png -> "grassground_1" (grassground variants)
	##   edge/road/ne/base.png -> "edge_road_ne"
	##   edge/road/ne/crosswalk.png -> "edge_road_ne_crosswalk"
	##   edge/grassground/ne/base.png -> "edge_grassground_ne"
	##   corner/road/ne/base.png -> "corner_road_ne"
	##   corner/grassground/ne/base.png -> "corner_grassground_ne"
	##   outcorner/road/ne/base.png -> "outcorner_road_ne"
	
	# Remove .png extension
	var path_no_ext := relative_path.get_basename()
	var parts := path_no_ext.split("/")
	
	if logic_name == "road":
		if parts.size() == 1:
			# Root level: base.png -> "basic"
			var filename := parts[0]
			return "basic" if filename == "base" else filename
		elif parts.size() == 2:
			# Lane variants: h/crosswalk.png -> "h_crosswalk", v/dashed_line.png -> "v_dashed_line"
			var orientation := parts[0]  # "h" or "v"
			var variant := parts[1]      # "crosswalk", "dashed_line_thick", etc.
			return orientation + "_" + variant
		return ""
	
	elif logic_name == "sidewalk":
		if parts.size() == 1:
			# Root level: base.png -> "basic", grassground_1.png -> "grassground_1"
			var filename := parts[0]
			return "basic" if filename == "base" else filename
		
		# Nested structure: {transition}/{neighbor}/{direction}/{variant_or_base}.png
		var transition := parts[0]  # "edge", "corner", or "outcorner"
		var filename := parts[-1]   # "base" or variant name
		
		if transition == "edge" or transition == "corner" or transition == "outcorner":
			# Path: {transition}/{neighbor}/{direction}/base.png
			# parts: ["edge", "road", "ne", "base"] or ["edge", "grassground", "ne", "base"]
			if parts.size() >= 4:
				var neighbor := parts[1]    # "road" or "grassground"
				var direction := parts[2]   # "ne", "nw", "se", "sw"
				
					# Include neighbor type in ID: edge_road_ne, edge_grassground_ne, corner_road_ne
				var base_id: String = transition + "_" + neighbor + "_" + direction
				
				if filename == "base":
					return base_id
				else:
					return base_id + "_" + filename
	
	return ""

func execute(config: PCGConfig, context: PCGContext) -> void:
	for pos: Vector2i in context.grid.keys():
		var cell: PCGCell = context.get_cell(pos)
		if cell == null:
			continue
		
		var candidates: Array[String] = _get_candidates_for_cell(cell, pos, context)
		cell.data["tile_candidates"] = candidates

func _get_candidates_for_cell(cell: PCGCell, pos: Vector2i, context: PCGContext) -> Array[String]:
	var logic_type: int = -1
	
	if cell.is_road():
		logic_type = _TileAssetResolver.LogicType.ROAD
	elif cell.zone_type == ZONE_URBAN:
		logic_type = _TileAssetResolver.LogicType.SIDEWALK
	
	if logic_type != -1 and _tile_map.has(logic_type):
		var candidates: Array[String] = _tile_map[logic_type].duplicate()
		
		# Filter sidewalk candidates by transition type based on road neighbors
		if logic_type == _TileAssetResolver.LogicType.SIDEWALK:
			var neighbors := _analyze_road_neighbors(pos, context)
			var transition := _determine_transition_type(neighbors)
			candidates = _filter_candidates_by_type(candidates, transition)
			cell.data["tile_transition"] = transition
		
		if not candidates.is_empty():
			return candidates
	
	return ["default"]


## Analyze road neighbors in all 4 isometric directions
func _analyze_road_neighbors(pos: Vector2i, context: PCGContext) -> Dictionary:
	var road_nw: bool = _is_road(pos + ISO_NW, context)
	var road_se: bool = _is_road(pos + ISO_SE, context)
	var road_sw: bool = _is_road(pos + ISO_SW, context)
	var road_ne: bool = _is_road(pos + ISO_NE, context)
	
	var road_count: int = 0
	if road_nw: road_count += 1
	if road_se: road_count += 1
	if road_sw: road_count += 1
	if road_ne: road_count += 1
	
	return {
		"nw": road_nw,
		"se": road_se,
		"sw": road_sw,
		"ne": road_ne,
		"count": road_count,
		"opposite": (road_nw and road_se) or (road_sw and road_ne),
	}


## Determine transition type based on road neighbor configuration
func _determine_transition_type(neighbors: Dictionary) -> int:
	var count: int = neighbors["count"]
	
	# 0 roads: NONE (no special transition)
	if count == 0:
		return _TileAssetResolver.TransitionType.NONE
	
	# 1 road: EDGE
	if count == 1:
		return _TileAssetResolver.TransitionType.EDGE
	
	# 2 roads: check if opposite (OPPOSITE) or adjacent (CORNER)
	if count == 2:
		if neighbors["opposite"]:
			return _TileAssetResolver.TransitionType.OPPOSITE
		else:
			return _TileAssetResolver.TransitionType.CORNER
	
	# 3 roads: END
	if count == 3:
		return _TileAssetResolver.TransitionType.END
	
	# 4 roads: ISOLATED
	return _TileAssetResolver.TransitionType.ISOLATED


## Filter candidates by transition type
func _filter_candidates_by_type(candidates: Array[String], transition: int) -> Array[String]:
	var filtered: Array[String] = []
	
	for candidate: String in candidates:
		match transition:
			_TileAssetResolver.TransitionType.EDGE:
				if candidate.begins_with("edge_"):
					filtered.append(candidate)
			_TileAssetResolver.TransitionType.CORNER:
				if candidate.begins_with("corner_"):
					filtered.append(candidate)
			_TileAssetResolver.TransitionType.OPPOSITE, \
			_TileAssetResolver.TransitionType.END, \
			_TileAssetResolver.TransitionType.ISOLATED, \
			_:  # NONE/BASIC
				if not candidate.begins_with("edge_") and not candidate.begins_with("corner_"):
					filtered.append(candidate)
	
	# Fallback to "basic" if no filtered candidates
	if filtered.is_empty():
		filtered.append("basic")
	
	return filtered


## Check if position is a road cell
func _is_road(pos: Vector2i, context: PCGContext) -> bool:
	var cell: PCGCell = context.get_cell(pos)
	if cell == null:
		return false
	return cell.is_road()
