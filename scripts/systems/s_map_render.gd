class_name SMapRender
extends System

## ECS System for rendering PCG map tiles.
## Queries entities with CMapData component and renders their PCGResult to a TileMapLayer.
##
## Pattern: Follows SDaynightLighting for global layer systems.
## - Creates TileMapLayer in _ready()
## - Adds layer to ECS.world via call_deferred
## - Uses TileSetBuilder for tileset creation and variant resolution
## - Falls back to zone-colored tiles when texture assets are missing

const TileSetBuilderScript := preload("res://scripts/pcg/tile_set_builder.gd")
const PCGCellScript := preload("res://scripts/pcg/data/pcg_cell.gd")
const CMapDataScript := preload("res://scripts/components/c_map_data.gd")

## Zone colors for fallback rendering when tile assets are missing
const COLOR_WILDERNESS := Color(0.30, 0.42, 0.20)
const COLOR_SUBURBS := Color(0.40, 0.50, 0.32)
const COLOR_URBAN := Color(0.45, 0.47, 0.50)
const COLOR_ROAD := Color(0.25, 0.25, 0.28)

## The TileMapLayer used for rendering
var _tile_layer: TileMapLayer

## TileSetBuilder instance for tileset creation and variant resolution
var _tile_set_builder: TileSetBuilderScript

## Track whether we've already rendered (to avoid re-rendering every frame)
var _current_pcg_result: PCGResult = null

## Track connected CMapData signals to avoid duplicate connections
var _connected_map_data: Array = []


func _ready() -> void:
	group = "render"
	_setup_tile_layer()


func query() -> QueryBuilder:
	return q.with_all([CMapDataScript])


func process(entity: Entity, _delta: float) -> void:
	var map_data: CMapDataScript = entity.get_component(CMapDataScript)
	if map_data == null:
		return
	
	# Connect to map_changed signal if not already connected
	if not _connected_map_data.has(map_data):
		if not map_data.map_changed.is_connected(_on_map_changed.bind(map_data)):
			map_data.map_changed.connect(_on_map_changed.bind(map_data))
		_connected_map_data.append(map_data)
	
	# Get PCGResult from map_data
	var pcg_result: PCGResult = map_data.pcg_result
	
	# Only render if we have new data
	if pcg_result != null and pcg_result != _current_pcg_result:
		render_map(pcg_result)
		_current_pcg_result = pcg_result


## Sets up the TileMapLayer with TileSet from TileSetBuilder.
func _setup_tile_layer() -> void:
	# Create TileSetBuilder and build tileset
	_tile_set_builder = TileSetBuilderScript.new()
	var tileset := _tile_set_builder.build_tileset()
	
	# Create TileMapLayer
	_tile_layer = TileMapLayer.new()
	_tile_layer.name = "MapRenderLayer"
	_tile_layer.tile_set = tileset
	
	# Set negative z_index to ensure tile layer renders behind all entities
	# This provides a stable rendering order regardless of tree position or spawn timing
	# Entities and their visuals use default z_index=0, so z_index=-10 ensures tiles render behind
	_tile_layer.z_index = -10
	
	# Add to ECS.world's Entities container via call_deferred
	# This makes TileMapLayer a sibling of all entity nodes
	if ECS.world and ECS.world.entity_nodes_root:
		_add_tile_layer_deferred.call_deferred()
	else:
		add_child.call_deferred(_tile_layer)


## Deferred helper to add tile layer to Entities container at index 0
## Uses z_index for stable ordering rather than relying solely on tree position
func _add_tile_layer_deferred() -> void:
	var entities_container: Node = ECS.world.get_node(ECS.world.entity_nodes_root)
	entities_container.add_child(_tile_layer)
	# Move to front of Entities container for organizational clarity
	entities_container.move_child(_tile_layer, 0)


## Renders the PCGResult grid to the TileMapLayer.
## Uses two-pass rendering: first zone colors as base, then textures on top.
func render_map(pcg_result: PCGResult) -> void:
	if _tile_layer == null:
		return
	
	# Clear existing cells
	_tile_layer.clear()
	
	if pcg_result == null or pcg_result.grid == null:
		return
	
	# PASS 1: Render zone-colored fallback tiles for ALL cells
	# This ensures every cell has a visible tile, even if texture is missing
	for key in pcg_result.grid.keys():
		var cell: PCGCellScript = pcg_result.grid[key]
		if cell == null:
			continue
		
		var source_id := _get_fallback_color_source(cell)
		if source_id != -1:
			_tile_layer.set_cell(key, source_id, Vector2i(0, 0))
	
	# PASS 2: Overlay texture tiles on top of zone colors
	# Only cells with valid tile_variant get texture tiles
	for key in pcg_result.grid.keys():
		var cell: PCGCellScript = pcg_result.grid[key]
		if cell == null:
			continue
		
		var tile_variant: String = ""
		
		# Check for tile_variant (set by TileDecidePhase)
		if cell.data.has("tile_variant"):
			tile_variant = cell.data["tile_variant"]
		# Fallback to legacy tile_id if present
		elif cell.data.has("tile_id"):
			tile_variant = cell.data["tile_id"]
		
		# Skip empty or default variants - they keep zone color from pass 1
		if tile_variant == "" or tile_variant == "default":
			continue
		
		# Map variant name to tileset source
		var source_id := _tile_set_builder.get_source_for_variant(cell, tile_variant)
		
		# Only overwrite if we have a valid texture tile
		if source_id != -1:
			_tile_layer.set_cell(key, source_id, Vector2i(0, 0))


## Called when CMapData.map_changed signal is emitted.
func _on_map_changed(map_data: CMapDataScript) -> void:
	var pcg_result: PCGResult = map_data.pcg_result
	if pcg_result != null:
		render_map(pcg_result)
		_current_pcg_result = pcg_result


## Gets a fallback color tile source based on cell's zone type.
## Used when texture assets are missing for a tile variant.
func _get_fallback_color_source(cell: PCGCellScript) -> int:
	var color: Color
	
	if cell.is_road():
		color = COLOR_ROAD
	else:
		# Use zone type to determine color
		match cell.zone_type:
			2:  # ZoneMap.ZoneType.URBAN
				color = COLOR_URBAN
			1:  # ZoneMap.ZoneType.SUBURBS
				color = COLOR_SUBURBS
			_:  # ZoneMap.ZoneType.WILDERNESS or unknown
				color = COLOR_WILDERNESS
	
	return _tile_set_builder.get_or_create_color_source(color)


## Returns the TileMapLayer (for testing/debugging).
func get_tile_layer() -> TileMapLayer:
	return _tile_layer


## Returns the TileSetBuilder instance (for testing/debugging).
func get_tile_set_builder() -> TileSetBuilderScript:
	return _tile_set_builder


func _exit_tree() -> void:
	# Disconnect from map_changed signals
	for map_data in _connected_map_data:
		if is_instance_valid(map_data) and map_data.map_changed.is_connected(_on_map_changed.bind(map_data)):
			map_data.map_changed.disconnect(_on_map_changed.bind(map_data))
	_connected_map_data.clear()
	
	# Clean up tile layer
	if _tile_layer and is_instance_valid(_tile_layer):
		_tile_layer.queue_free()
