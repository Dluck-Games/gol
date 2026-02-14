class_name PCGPhaseDebugController
extends Node2D
## PCG Phase Debug Controller
## Manages step-by-step execution and visualization of PCG pipeline phases
## Uses SMapRender system for tile rendering (via CMapData component)

# Signals
signal phase_changed(phase_index: int, phase_name: String)
signal context_updated(ctx: PCGContext)

# Phase names for display (from centralized config)
const PHASE_NAMES: Array[String] = PCGPhaseConfig.PHASE_NAMES

# Phase instances (manually instantiated, not from PCGPipeline)
var phases: Array[PCGPhase] = []

# State tracking
var current_phase_index: int = 0  # 0 = empty, 1-7 = after each phase
var current_seed: int = 0
var grid_size: int = 100

# PCG data
var context: PCGContext
var config: PCGConfig

# Rendering nodes (managed by SMapRender system, NOT by this controller)
var _poi_markers: Node2D  # Container for POI markers

# ECS integration
var _map_entity: Entity  # Entity holding CMapData component
var _map_data: CMapData  # Reference to CMapData component
var _map_render_system: SMapRender  # Reference to SMapRender system

const TILE_WIDTH: int = 64
const TILE_HEIGHT: int = 32

# Camera and input
var _camera: Camera2D
const CAMERA_SPEED: float = 500.0
const ZOOM_SPEED: float = 1.1

# Inspector integration
var inspector  # PCGPhaseInspector - untyped to avoid circular dependency

# Tile highlighting
var _highlighted_tile: Vector2i = Vector2i(-999999, -999999)
var _highlight_overlay: TileMapLayer
var _highlight_source_id: int = -1
var _highlight_tileset: TileSet


func _ready() -> void:
	# Try to find an existing camera
	_camera = get_viewport().get_camera_2d()
	
	# Fallback to searching nearby nodes if no active camera
	if not _camera:
		_camera = get_node_or_null("../Camera2D")
	if not _camera:
		_camera = get_node_or_null("Camera2D")
	
	# Create one if absolutely nothing found
	if not _camera:
		_camera = Camera2D.new()
		_camera.name = "Camera2D"
		add_child(_camera)
		_camera.make_current()
	
	# Initialize rendering nodes
	_setup_rendering()
	
	# Instantiate phases using centralized configuration
	phases = PCGPhaseConfig.create_phases()
	
	# Initialize with defaults
	current_seed = 0
	grid_size = 100
	reset()
	
	# Connect signals for rendering
	phase_changed.connect(_on_phase_changed)
	context_updated.connect(_on_context_updated)
	
	# Initialize inspector
	var inspector_script := load("res://scripts/debug/pcg_phase_inspector.gd")
	inspector = inspector_script.new()
	inspector.set_controller(self)


func reset() -> void:
	# Reset to empty state (phase 0)
	current_phase_index = 0
	_create_fresh_context()
	_create_fresh_config()
	phase_changed.emit(current_phase_index, PHASE_NAMES[current_phase_index])
	context_updated.emit(context)


func regenerate(seed: int) -> void:
	# Regenerate with new seed
	current_seed = seed
	reset()


func set_grid_size(size: int) -> void:
	# Update grid size and reset
	grid_size = size
	reset()


func step_next() -> void:
	# Execute next phase and increment index
	if current_phase_index >= phases.size():
		push_warning("PCGPhaseDebugController: Already at final phase")
		return
	
	# Execute phase at current_phase_index (phase 0->1 executes phases[0])
	_execute_phase(current_phase_index)
	
	current_phase_index += 1
	phase_changed.emit(current_phase_index, PHASE_NAMES[current_phase_index])
	context_updated.emit(context)


func step_previous() -> void:
	# Step back one phase by re-executing from start
	if current_phase_index <= 0:
		push_warning("PCGPhaseDebugController: Already at empty state")
		return
	
	jump_to_phase(current_phase_index - 1)


func jump_to_phase(target_index: int) -> void:
	# Jump to a specific phase index (re-executing from start if needed)
	if target_index < 0 or target_index > phases.size():
		push_error("PCGPhaseDebugController: Invalid target phase index %d" % target_index)
		return

	if target_index == current_phase_index:
		return

	# Optimisation: If moving forward, just execute next phases
	if target_index > current_phase_index:
		while current_phase_index < target_index:
			_execute_phase(current_phase_index)
			current_phase_index += 1
	else:
		# If moving backward, must reset and re-execute
		current_phase_index = target_index

		# Re-execute all phases up to target index
		_create_fresh_context()
		_create_fresh_config()

		for i in range(current_phase_index):
			_execute_phase(i)

	phase_changed.emit(current_phase_index, PHASE_NAMES[current_phase_index])
	context_updated.emit(context)


func run_all_phases() -> void:
	# Execute all phases from start to finish
	reset()
	while current_phase_index < phases.size():
		_execute_phase(current_phase_index)
		current_phase_index += 1
	phase_changed.emit(current_phase_index, PHASE_NAMES[current_phase_index])
	context_updated.emit(context)


func _execute_phase(index: int) -> void:
	# Execute a single phase
	if index < 0 or index >= phases.size():
		push_error("PCGPhaseDebugController: Invalid phase index %d" % index)
		return
	
	phases[index].execute(config, context)


func _create_fresh_context() -> void:
	# Create fresh PCGContext with current seed
	context = PCGContext.new(current_seed)


func _create_fresh_config() -> void:
	# Create fresh PCGConfig with current settings
	config = PCGConfig.new()
	config.pcg_seed = current_seed
	config.grid_size = grid_size
	# Grid size would be used for map bounds if phases needed it
	# Currently PCG phases don't use explicit grid_size from config


func _input(event: InputEvent) -> void:
	# Handle keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT, KEY_N:
				step_next()
			KEY_LEFT, KEY_P:
				step_previous()
			KEY_R:
				reset()
			KEY_G:
				regenerate(randi())
			KEY_EQUAL, KEY_KP_ADD:
				if _camera:
					_camera.zoom *= ZOOM_SPEED
			KEY_MINUS, KEY_KP_SUBTRACT:
				if _camera:
					_camera.zoom /= ZOOM_SPEED
	
	if event is InputEventMouseButton and _camera:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom *= ZOOM_SPEED
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom /= ZOOM_SPEED


func _process(delta: float) -> void:
	# Handle camera movement
	if _camera:
		_handle_camera_movement(delta)
	
	# Update tile highlight based on mouse position
	_update_tile_highlight()
	
	# Draw ImGui inspector window
	if ClassDB.class_exists("ImGuiController"):
		# Set default window position (left side, vertically centered)
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var default_size := Vector2(viewport_size.x * 0.3, viewport_size.y * 0.7)
		var default_pos := Vector2(10, (viewport_size.y - default_size.y) / 2)
		
		ImGui.SetNextWindowPos(default_pos, ImGui.Cond_FirstUseEver)
		ImGui.SetNextWindowSize(default_size, ImGui.Cond_FirstUseEver)
		
		if ImGui.Begin("PCG Phase Inspector", [true]):
			if inspector:
				inspector.set_hovered_tile(_highlighted_tile)
				inspector.draw()
			else:
				ImGui.TextDisabled("(Inspector not initialized)")
		ImGui.End()


func _handle_camera_movement(delta: float) -> void:
	# Handle WASD camera movement
	if not _camera:
		return
	
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_key_pressed(KEY_S): dir.y += 1
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
	
	if dir != Vector2.ZERO:
		_camera.position += dir.normalized() * CAMERA_SPEED * delta / _camera.zoom.x


# ============================================================================
# RENDERING
# ============================================================================

func _setup_rendering() -> void:
	# Initialize rendering via ECS (SMapRender system)
	# Create CMapData component and entity for SMapRender to render
	_map_data = CMapData.new()
	_map_entity = Entity.new()
	_map_entity.add_component(_map_data)
	
	# Add entity to ECS world (SMapRender will pick it up via query)
	if ECS.world:
		ECS.world.add_entity(_map_entity)
	
	# Create SMapRender system if not already present
	_map_render_system = SMapRender.new()
	_map_render_system.name = "SMapRender_Debug"
	if ECS.world:
		ECS.world.add_system(_map_render_system)
	else:
		# Fallback for debug scene without ECS world - add as child directly
		add_child(_map_render_system)
	
	# Highlight overlay layer (on top) - this stays in the debug controller
	# because it's debug-specific functionality
	_setup_highlight_overlay()
	
	# POI markers container
	_poi_markers = Node2D.new()
	add_child(_poi_markers)


func _setup_highlight_overlay() -> void:
	# Create a separate tileset for the highlight overlay
	_highlight_tileset = TileSet.new()
	_highlight_tileset.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	_highlight_tileset.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	_highlight_tileset.tile_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	
	_highlight_overlay = TileMapLayer.new()
	_highlight_overlay.z_index = 100  # Ensure it's on top
	_highlight_overlay.tile_set = _highlight_tileset
	add_child(_highlight_overlay)
	
	# Create highlight source
	_highlight_source_id = _create_highlight_source()


func _on_phase_changed(_phase_index: int, _phase_name: String) -> void:
	# Signal handler for phase changes
	_render_current_phase()


func _on_context_updated(_ctx: PCGContext) -> void:
	# Signal handler for context updates
	_render_current_phase()


func _render_current_phase() -> void:
	# Render visualization for current phase
	# Clear POI markers
	_clear_poi_markers()
	
	# Build PCGResult from current context and update CMapData
	# In debug mode, we call render_map() directly since ECS.process() isn't called
	var pcg_result := _build_pcg_result()
	if _map_data:
		_map_data.pcg_result = pcg_result
	
	# Directly trigger render since debug scene doesn't use GOLWorld's ECS.process()
	if _map_render_system and pcg_result:
		_map_render_system.render_map(pcg_result)
	
	# Render POIs (debug-specific visualization)
	if current_phase_index >= 7:  # POI Generator phase or later
		_render_pois()


func _build_pcg_result() -> PCGResult:
	# Build a PCGResult from current context state
	# Reads all data from unified grid (PCGCell)
	if context == null:
		return null
	
	return PCGResult.new(
		config,
		context.road_graph,
		null,  # zone_map - generated on-demand from grid
		null,  # poi_list - generated on-demand from grid
		context.grid if context.grid else {}
	)


func _draw() -> void:
	# Draw road graph as distinct segments
	if context == null or context.road_graph == null:
		return
	
	var graph := context.road_graph
	for edge: RoadGraph.RoadEdge in graph.edges:
		var from_node: RoadGraph.RoadNode = edge.from_node
		var to_node: RoadGraph.RoadNode = edge.to_node
		
		# Convert positions to isometric screen coordinates
		var from_iso := _world_to_iso(from_node.position)
		var to_iso := _world_to_iso(to_node.position)
		
		# Draw line segment
		draw_line(from_iso, to_iso, Color.WHITE, 2.0)


func _render_pois() -> void:
	# Render POI markers - reads directly from unified grid
	if context == null:
		return

	if context.grid == null or context.grid.is_empty():
		return

	# Iterate grid and collect POIs where poi_type != -1
	for key: Variant in context.grid.keys():
		var cell: PCGCell = context.grid[key]
		if cell == null or cell.poi_type == -1:
			continue

		# Create marker at grid position
		var marker := ColorRect.new()
		marker.size = Vector2(8, 8)
		marker.position = _world_to_iso(Vector2(key.x, key.y)) - marker.size / 2

		# Color by type
		match cell.poi_type:
			POIList.POIType.BUILDING:
				marker.color = Color.YELLOW
			POIList.POIType.VILLAGE:
				marker.color = Color.BLUE
			POIList.POIType.ENEMY_SPAWN:
				marker.color = Color.RED
			POIList.POIType.LOOT_SPAWN:
				marker.color = Color.GREEN
			_:
				marker.color = Color.WHITE

		_poi_markers.add_child(marker)


func _clear_poi_markers() -> void:
	# Clear all POI marker nodes
	for child in _poi_markers.get_children():
		child.queue_free()


func _world_to_iso(world_pos: Vector2) -> Vector2:
	# Convert world coordinates to isometric screen coordinates
	var iso_x := (world_pos.x - world_pos.y) * (TILE_WIDTH / 2.0)
	var iso_y := (world_pos.x + world_pos.y) * (TILE_HEIGHT / 2.0)
	return Vector2(iso_x, iso_y)


func _update_tile_highlight() -> void:
	# Update the highlighted tile based on mouse position
	# Use TileMapLayer's built-in local_to_map for accurate coordinate conversion
	var local_mouse_pos := _highlight_overlay.get_local_mouse_position()
	var tile_pos := _highlight_overlay.local_to_map(local_mouse_pos)
	
	var new_highlight := Vector2i(tile_pos)
	
	# Only update if changed
	if new_highlight != _highlighted_tile:
		_highlighted_tile = new_highlight
		_update_highlight_overlay()


func _update_highlight_overlay() -> void:
	# Clear previous highlight
	_highlight_overlay.clear()

	# Only show highlight if we have a valid tile and context
	if _highlighted_tile.x < -100000:  # Invalid marker
		return

	# Check if the tile exists in unified grid only
	var has_tile := false
	if context and context.grid and context.grid.has(_highlighted_tile):
		has_tile = true

	if has_tile and _highlight_source_id != -1:
		_highlight_overlay.set_cell(_highlighted_tile, _highlight_source_id, Vector2i(0, 0))


func _create_highlight_source() -> int:
	# Create a semi-transparent highlight tile source
	var image := Image.create(TILE_WIDTH, TILE_HEIGHT, false, Image.FORMAT_RGBA8)
	
	var center_x := TILE_WIDTH / 2.0
	var center_y := TILE_HEIGHT / 2.0
	var half_w := TILE_WIDTH / 2.0
	var half_h := TILE_HEIGHT / 2.0
	
	var highlight_color := Color(1.0, 1.0, 0.0, 0.5)  # Yellow semi-transparent
	
	for y in range(TILE_HEIGHT):
		for x in range(TILE_WIDTH):
			var px: float = float(x) + 0.5
			var py: float = float(y) + 0.5
			var nx: float = abs(px - center_x) / half_w
			var ny: float = abs(py - center_y) / half_h
			
			if nx + ny <= 1.0:
				image.set_pixel(x, y, highlight_color)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var texture := ImageTexture.create_from_image(image)
	
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	source.create_tile(Vector2i(0, 0))
	
	var id := 999  # Use a high ID for highlight
	_highlight_tileset.add_source(source, id)
	return id


func _iso_to_world(iso_pos: Vector2) -> Vector2:
	# Convert isometric screen coordinates to world/grid coordinates
	# iso_pos is already in world space (get_global_mouse_position() accounts for camera)
	# We just need to convert from isometric world coordinates to grid coordinates
	
	var x := (iso_pos.x / (TILE_WIDTH / 2.0) + iso_pos.y / (TILE_HEIGHT / 2.0)) / 2.0
	var y := (iso_pos.y / (TILE_HEIGHT / 2.0) - iso_pos.x / (TILE_WIDTH / 2.0)) / 2.0
	
	return Vector2(x, y)


func get_tile_info(tile_pos: Vector2i) -> Dictionary:
	# Get information about a specific tile - reads directly from unified grid
	var info := {
		"position": tile_pos,
		"has_data": false,
		"is_road": false,
		"zone_type": -1,
		"poi_type": -1,
		"tile_id": "",
		"tile_variant": "",
		"tile_candidates": []
	}

	if not context:
		return info

	# Read all data from unified grid only
	if context.grid and context.grid.has(tile_pos):
		var cell: PCGCell = context.grid[tile_pos]
		if cell:
			info["has_data"] = true
			info["is_road"] = cell.is_road()
			info["zone_type"] = cell.zone_type
			info["poi_type"] = cell.poi_type
			if cell.data.has("tile_id"):
				info["tile_id"] = cell.data["tile_id"]
			if cell.data.has("tile_variant"):
				info["tile_variant"] = cell.data["tile_variant"]
			if cell.data.has("tile_candidates"):
				info["tile_candidates"] = cell.data["tile_candidates"]

	return info


func _exit_tree() -> void:
	# Clean up ECS resources
	if _map_entity and is_instance_valid(_map_entity) and ECS.world:
		ECS.world.remove_entity(_map_entity)
	
	if _map_render_system and is_instance_valid(_map_render_system):
		if ECS.world:
			ECS.world.remove_system(_map_render_system)
		else:
			# Fallback cleanup for debug scene without ECS world
			_map_render_system.queue_free()
