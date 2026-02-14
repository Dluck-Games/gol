class_name PCGPhaseInspector
extends RefCounted
## PCG Phase Inspector
## ImGui-based inspector panel for viewing PCG phase metadata and state

var _controller  # PCGPhaseDebugController

# UI state
var _seed_input: Array = [0]
var _grid_size_index: int = 2  # Default to 100
const GRID_SIZES: Array[int] = [25, 50, 100, 200]
const GRID_SIZE_NAMES: Array[String] = ["25", "50", "100", "200"]

# Tile hover state
var _hovered_tile: Vector2i = Vector2i(-999999, -999999)


func set_controller(controller) -> void:  # controller: PCGPhaseDebugController
	_controller = controller
	if _controller:
		_seed_input[0] = _controller.current_seed


func set_hovered_tile(tile_pos: Vector2i) -> void:
	_hovered_tile = tile_pos


func draw() -> void:
	if not _controller:
		ImGui.TextDisabled("(No controller set)")
		return
	
	_draw_phase_list()
	ImGui.Separator()
	
	_draw_phase_info()
	ImGui.Separator()

	_draw_hovered_tile_info()
	ImGui.Separator()

	_draw_controls()


func _draw_phase_list() -> void:
	if ImGui.CollapsingHeader("Phases", true):
		for i in range(_controller.PHASE_NAMES.size()):
			var name: String = _controller.PHASE_NAMES[i]
			var is_selected: bool = (i == _controller.current_phase_index)
			
			var prefix := "* " if is_selected else "  "
			if ImGui.Selectable(prefix + "%d. %s" % [i, name]):
				_controller.jump_to_phase(i)
	

func _draw_phase_info() -> void:
	# Display current phase name and index
	ImGui.Text("Current Phase: %s (index %d)" % [
		_controller.PHASE_NAMES[_controller.current_phase_index],
		_controller.current_phase_index
	])
	ImGui.Text("Seed: %d" % _controller.current_seed)
	ImGui.Text("Grid Size: %d" % _controller.grid_size)


func _draw_hovered_tile_info() -> void:
	# Display information about the currently hovered tile
	ImGui.Text("Hovered Tile Info")
	ImGui.Separator()

	if not _controller:
		ImGui.TextDisabled("(No controller)")
		return

	# Check if we have a valid hovered tile
	if _hovered_tile.x < -100000:
		ImGui.TextDisabled("(Hover over a tile to see info)")
		return

	# Get tile info from controller
	var tile_info: Dictionary = _controller.get_tile_info(_hovered_tile)

	ImGui.Text("Position: (%d, %d)" % [_hovered_tile.x, _hovered_tile.y])

	if not tile_info["has_data"]:
		ImGui.TextDisabled("(Empty tile)")
		return

	# Display road info
	if tile_info["is_road"]:
		ImGui.TextColored(Color.YELLOW, "Type: Road")
	else:
		ImGui.Text("Type: Terrain")

	# Display zone info
	var zone_type: int = tile_info["zone_type"]
	if zone_type != -1:
		var zone_str := _zone_type_to_string(zone_type)
		var zone_color := Color.WHITE
		match zone_type:
			ZoneMap.ZoneType.WILDERNESS:
				zone_color = Color(0.30, 0.42, 0.20)
			ZoneMap.ZoneType.SUBURBS:
				zone_color = Color(0.40, 0.50, 0.32)
			ZoneMap.ZoneType.URBAN:
				zone_color = Color(0.45, 0.47, 0.50)
		ImGui.TextColored(zone_color, "Zone: %s" % zone_str)

	# Display POI info
	var poi_type: int = tile_info["poi_type"]
	if poi_type != -1:
		var poi_str := _poi_type_to_string(poi_type)
		var poi_color := Color.WHITE
		match poi_type:
			POIList.POIType.BUILDING:
				poi_color = Color.YELLOW
			POIList.POIType.VILLAGE:
				poi_color = Color.BLUE
			POIList.POIType.ENEMY_SPAWN:
				poi_color = Color.RED
			POIList.POIType.LOOT_SPAWN:
				poi_color = Color.GREEN
		ImGui.TextColored(poi_color, "POI: %s" % poi_str)

	# Display tile ID (Neighbor Tile Resolver)
	var tile_id: String = tile_info["tile_id"]
	if not tile_id.is_empty():
		ImGui.Text("Tile ID: %s" % tile_id)

	# Display tile variant (TileDecidePhase)
	var tile_variant: String = tile_info.get("tile_variant", "")
	if not tile_variant.is_empty():
		ImGui.TextColored(Color.CYAN, "Tile Variant: %s" % tile_variant)

	# Display tile candidates (TileResolvePhase)
	var tile_candidates: Array = tile_info.get("tile_candidates", [])
	if not tile_candidates.is_empty():
		ImGui.Text("Candidates (%d):" % tile_candidates.size())
		for candidate in tile_candidates:
			ImGui.BulletText(str(candidate))


func _draw_controls() -> void:
	# Draw control buttons
	# Phase navigation
	if ImGui.Button("Previous"):
		_controller.step_previous()

	ImGui.SameLine()

	if ImGui.Button("Next"):
		_controller.step_next()

	ImGui.SameLine()

	if ImGui.Button("Reset"):
		_controller.reset()

	ImGui.SameLine()

	# Run all phases button - highlighted for quick access
	ImGui.PushStyleColor(ImGui.Col_Button, Color(0.2, 0.6, 0.2))
	ImGui.PushStyleColor(ImGui.Col_ButtonHovered, Color(0.3, 0.7, 0.3))
	ImGui.PushStyleColor(ImGui.Col_ButtonActive, Color(0.25, 0.65, 0.25))
	if ImGui.Button("JDI"):
		_controller.run_all_phases()
	ImGui.PopStyleColor()
	ImGui.PopStyleColor()
	ImGui.PopStyleColor()

	ImGui.Separator()

	# Seed control
	ImGui.Text("Seed:")
	ImGui.SameLine()
	ImGui.SetNextItemWidth(150)
	if ImGui.InputInt("##seed", _seed_input):
		pass  # Value updated in array

	ImGui.SameLine()

	if ImGui.Button("Regenerate"):
		_controller.regenerate(_seed_input[0])

	ImGui.Separator()

	# Grid size control
	ImGui.Text("Grid Size:")
	ImGui.SameLine()

	for i in range(GRID_SIZES.size()):
		if i > 0:
			ImGui.SameLine()
		var label := "[%s]" % GRID_SIZE_NAMES[i] if _grid_size_index == i else GRID_SIZE_NAMES[i]
		if ImGui.SmallButton(label):
			_grid_size_index = i
			_controller.set_grid_size(GRID_SIZES[i])


func _zone_type_to_string(zone_type: ZoneMap.ZoneType) -> String:
	match zone_type:
		ZoneMap.ZoneType.WILDERNESS:
			return "WILDERNESS"
		ZoneMap.ZoneType.SUBURBS:
			return "SUBURBS"
		ZoneMap.ZoneType.URBAN:
			return "URBAN"
		_:
			return "UNKNOWN"


func _poi_type_to_string(poi_type: POIList.POIType) -> String:
	match poi_type:
		POIList.POIType.BUILDING:
			return "BUILDING"
		POIList.POIType.VILLAGE:
			return "VILLAGE"
		POIList.POIType.ENEMY_SPAWN:
			return "ENEMY_SPAWN"
		POIList.POIType.LOOT_SPAWN:
			return "LOOT_SPAWN"
		_:
			return "UNKNOWN"
