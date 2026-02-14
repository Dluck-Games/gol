class_name PCGResult
extends RefCounted

## Integration container for PCG pipeline outputs (no Node dependencies).
## Unified grid (PCGCell) is the single source of truth.
## Legacy zone_map, poi_list are generated on-demand from grid via getters.

## Tile dimensions for isometric rendering (must match TileSetBuilder)
const TILE_WIDTH: int = 64
const TILE_HEIGHT: int = 32

var config: PCGConfig
var road_graph: RoadGraph

## Unified grid: Dictionary[Vector2i, PCGCell] - single source of truth
var grid: Dictionary = {}

## Legacy zone_map - generated on demand from unified grid
var zone_map: ZoneMap:
	get:
		return _build_zone_map_from_grid()
	set(value):
		pass  # Read-only from grid

## Legacy poi_list - generated on demand from unified grid
var poi_list: POIList:
	get:
		return _build_poi_list_from_grid()
	set(value):
		pass  # Read-only from grid

## Road cells - generated on demand from unified grid
var road_cells: Dictionary[Vector2i, bool]:
	get:
		return _build_road_cells_from_grid()
	set(value):
		pass  # Read-only from grid


func _init(p_config: PCGConfig, p_graph: RoadGraph, p_zones: ZoneMap = null, p_pois: POIList = null, p_grid: Dictionary = {}) -> void:
	config = p_config
	road_graph = p_graph
	# Unified grid is the single source of truth
	grid = p_grid


## Builds a ZoneMap from the unified grid.
func _build_zone_map_from_grid() -> ZoneMap:
	var zone_map_data := ZoneMap.new()
	
	if grid == null or grid.is_empty():
		return zone_map_data
	
	# Determine grid size from config or use default
	var grid_size: int = 100
	if config != null and config.has_method("get"):
		var gs: Variant = config.get("grid_size")
		if gs != null and gs is int:
			grid_size = gs
	
	var half_size: int = int(grid_size / 2)
	var start: int = -half_size
	var end: int = grid_size - half_size
	
	for y: int in range(start, end):
		for x: int in range(start, end):
			var pos := Vector2i(x, y)
			if grid.has(pos):
				var cell = grid[pos]
				if cell is PCGCell:
					zone_map_data.set_zone(pos, cell.zone_type)
				else:
					zone_map_data.set_zone(pos, ZoneMap.ZoneType.WILDERNESS)
			else:
				zone_map_data.set_zone(pos, ZoneMap.ZoneType.WILDERNESS)
	
	return zone_map_data


## Builds a POIList from the unified grid.
func _build_poi_list_from_grid() -> POIList:
	var poi_list_data := POIList.new()
	
	if grid == null or grid.is_empty():
		return poi_list_data
	
	for pos: Variant in grid.keys():
		if pos is Vector2i:
			var cell = grid[pos]
			if cell is PCGCell and cell.poi_type >= 0:
				# Use isometric coordinate conversion to match TileMapLayer.map_to_local()
				# This ensures POI world positions align with rendered tiles
				var world_pos := _grid_to_world(pos)
				var metadata := {}
				if cell.zone_type >= 0:
					metadata["zone"] = cell.zone_type
				poi_list_data.add_poi(POIList.POI.new(world_pos, cell.poi_type, metadata))
	
	return poi_list_data


## Converts grid coordinates to world coordinates using isometric transformation.
## Matches TileMapLayer.map_to_local() for TILE_LAYOUT_DIAMOND_DOWN.
func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	# Formula for TILE_LAYOUT_DIAMOND_DOWN isometric tiles:
	# world_x = (grid_x - grid_y) * (tile_width / 2) + (tile_width / 2)
	# world_y = (grid_x + grid_y) * (tile_height / 2) + (tile_height / 2)
	var world_x: float = (float(grid_pos.x) - float(grid_pos.y)) * (float(TILE_WIDTH) / 2.0) + (float(TILE_WIDTH) / 2.0)
	var world_y: float = (float(grid_pos.x) + float(grid_pos.y)) * (float(TILE_HEIGHT) / 2.0) + (float(TILE_HEIGHT) / 2.0)
	return Vector2(world_x, world_y)


## Builds road_cells Dictionary from the unified grid.
func _build_road_cells_from_grid() -> Dictionary[Vector2i, bool]:
	var rc: Dictionary[Vector2i, bool] = {}
	
	for pos: Variant in grid.keys():
		if pos is Vector2i:
			var cell = grid[pos]
			if cell is PCGCell and cell.is_road():
				rc[pos] = true
	
	return rc


## Validates that the PCG result has valid data.
func is_valid() -> bool:
	return config != null and road_graph != null and not grid.is_empty()
