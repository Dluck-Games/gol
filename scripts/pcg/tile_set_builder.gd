class_name TileSetBuilder
extends RefCounted
## Builds and configures TileSet for PCG map rendering.
## Extracts tileset building logic from PCGPhaseDebugController.

const TileAssetResolverScript := preload("res://scripts/pcg/tile_asset_resolver.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")

## Tile dimensions for isometric rendering
const TILE_WIDTH: int = 64
const TILE_HEIGHT: int = 32

## Dictionary mapping variant names to source IDs
var _variant_sources: Dictionary = {}

## Dictionary mapping color keys to source IDs (for zone rendering)
var _color_sources: Dictionary = {}

## Next available source ID for dynamic color sources (starts at 100)
var _next_source_id: int = 100

## The tileset being built
var _tileset: TileSet


## Builds and returns a configured TileSet with all registered tile sources.
## Initializes isometric tileset and registers all texture sources via TileAssetResolver.
func build_tileset() -> TileSet:
	# Setup isometric tileset for terrain/road rendering
	_tileset = TileSet.new()
	_tileset.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	_tileset.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	_tileset.tile_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	
	_variant_sources.clear()
	_color_sources.clear()
	_next_source_id = 100
	
	var resolver = TileAssetResolverScript.new()
	var R = TileAssetResolverScript
	
	# Map legacy names to resolver calls
	var mappings := [
		# Road tiles
		{"name": "road_urban", "args": [R.LogicType.ROAD, R.TransitionType.NONE, R.LogicType.ROAD, R.Direction.NONE]},
		{"name": "road_urban_center", "args": [R.LogicType.ROAD, R.TransitionType.NONE, R.LogicType.ROAD, R.Direction.NONE, "center_v"]},
		{"name": "road_urban_center_h", "args": [R.LogicType.ROAD, R.TransitionType.NONE, R.LogicType.ROAD, R.Direction.NONE, "center_h"]},
		
		# Crosswalk tiles (flat structure: road/crosswalk.png, road/crosswalk_center.png, road/crosswalk_road.png)
		{"name": "crosswalk_urban", "args": [R.LogicType.ROAD, R.TransitionType.NONE, R.LogicType.ROAD, R.Direction.NONE, "crosswalk"]},
		{"name": "crosswalk_urban_center", "args": [R.LogicType.ROAD, R.TransitionType.NONE, R.LogicType.ROAD, R.Direction.NONE, "crosswalk_center"]},
		{"name": "crosswalk_urban_road", "args": [R.LogicType.ROAD, R.TransitionType.NONE, R.LogicType.ROAD, R.Direction.NONE, "crosswalk_road"]},
		
		# Sidewalk tiles
		{"name": "sidewalk_urban", "args": [R.LogicType.SIDEWALK, R.TransitionType.NONE, R.LogicType.ROAD, R.Direction.NONE]},
		
		# Grassground tiles (plain sidewalk alternatives)
		{"name": "sidewalk_urban_grassground_1", "args": [R.LogicType.SIDEWALK, R.TransitionType.NONE, R.LogicType.GRASS, R.Direction.NONE, "grassground_1"]},
		{"name": "sidewalk_urban_grassground_2", "args": [R.LogicType.SIDEWALK, R.TransitionType.NONE, R.LogicType.GRASS, R.Direction.NONE, "grassground_2"]},
		{"name": "sidewalk_urban_grassground_3", "args": [R.LogicType.SIDEWALK, R.TransitionType.NONE, R.LogicType.GRASS, R.Direction.NONE, "grassground_3"]},
		{"name": "sidewalk_urban_grassground_4", "args": [R.LogicType.SIDEWALK, R.TransitionType.NONE, R.LogicType.GRASS, R.Direction.NONE, "grassground_4"]},
		
		# Sidewalk Corners - cardinal naming (corner points in cardinal direction)
		# corner_n: points North, has roads at NW and NE
		# corner_s: points South, has roads at SW and SE
		# corner_e: points East, has roads at NE and SE
		# corner_w: points West, has roads at NW and SW
		{"name": "sidewalk_urban_corner_n", "args": [R.LogicType.SIDEWALK, R.TransitionType.CORNER, R.LogicType.ROAD, R.Direction.N]},
		{"name": "sidewalk_urban_corner_s", "args": [R.LogicType.SIDEWALK, R.TransitionType.CORNER, R.LogicType.ROAD, R.Direction.S]},
		{"name": "sidewalk_urban_corner_e", "args": [R.LogicType.SIDEWALK, R.TransitionType.CORNER, R.LogicType.ROAD, R.Direction.E]},
		{"name": "sidewalk_urban_corner_w", "args": [R.LogicType.SIDEWALK, R.TransitionType.CORNER, R.LogicType.ROAD, R.Direction.W]},
		
		# Sidewalk Corners bordering grassground
		{"name": "sidewalk_urban_corner_grassground_n", "args": [R.LogicType.SIDEWALK, R.TransitionType.CORNER, R.LogicType.GRASS, R.Direction.N]},
		{"name": "sidewalk_urban_corner_grassground_s", "args": [R.LogicType.SIDEWALK, R.TransitionType.CORNER, R.LogicType.GRASS, R.Direction.S]},
		{"name": "sidewalk_urban_corner_grassground_e", "args": [R.LogicType.SIDEWALK, R.TransitionType.CORNER, R.LogicType.GRASS, R.Direction.E]},
		{"name": "sidewalk_urban_corner_grassground_w", "args": [R.LogicType.SIDEWALK, R.TransitionType.CORNER, R.LogicType.GRASS, R.Direction.W]},
		
		# Sidewalk Outcorners (sidewalk protrudes into road) - cardinal naming
		{"name": "sidewalk_urban_outcorner_n", "args": [R.LogicType.SIDEWALK, R.TransitionType.END, R.LogicType.ROAD, R.Direction.N]},
		{"name": "sidewalk_urban_outcorner_s", "args": [R.LogicType.SIDEWALK, R.TransitionType.END, R.LogicType.ROAD, R.Direction.S]},
		{"name": "sidewalk_urban_outcorner_e", "args": [R.LogicType.SIDEWALK, R.TransitionType.END, R.LogicType.ROAD, R.Direction.E]},
		{"name": "sidewalk_urban_outcorner_w", "args": [R.LogicType.SIDEWALK, R.TransitionType.END, R.LogicType.ROAD, R.Direction.W]},
		
		# Sidewalk Crosswalks (edge variants with crosswalk pattern when adjacent to crosswalk road)
		{"name": "sidewalk_urban_edge_ne_crosswalk", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.ROAD, R.Direction.NE, "crosswalk"]},
		{"name": "sidewalk_urban_edge_nw_crosswalk", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.ROAD, R.Direction.NW, "crosswalk"]},
		{"name": "sidewalk_urban_edge_se_crosswalk", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.ROAD, R.Direction.SE, "crosswalk"]},
		{"name": "sidewalk_urban_edge_sw_crosswalk", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.ROAD, R.Direction.SW, "crosswalk"]},
		
		# Sidewalk Edges bordering road
		{"name": "sidewalk_urban_edge_ne", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.ROAD, R.Direction.NE]},
		{"name": "sidewalk_urban_edge_nw", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.ROAD, R.Direction.NW]},
		{"name": "sidewalk_urban_edge_se", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.ROAD, R.Direction.SE]},
		{"name": "sidewalk_urban_edge_sw", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.ROAD, R.Direction.SW]},
		
		# Sidewalk Edges bordering grassground
		{"name": "sidewalk_urban_edge_grassground_ne", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.GRASS, R.Direction.NE]},
		{"name": "sidewalk_urban_edge_grassground_nw", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.GRASS, R.Direction.NW]},
		{"name": "sidewalk_urban_edge_grassground_se", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.GRASS, R.Direction.SE]},
		{"name": "sidewalk_urban_edge_grassground_sw", "args": [R.LogicType.SIDEWALK, R.TransitionType.EDGE, R.LogicType.GRASS, R.Direction.SW]},
	]
	
	var source_id := 1
	for m in mappings:
		var args: Array = m["args"]
		var path: String
		if args.size() == 4:
			path = resolver.resolve(args[0], args[1], args[2], args[3])
		else:
			path = resolver.resolve(args[0], args[1], args[2], args[3], args[4])
			
		if _add_texture_source(path, source_id):
			_variant_sources[m["name"]] = source_id
			source_id += 1
	
	return _tileset


## Returns the TileSet (must call build_tileset() first).
func get_tileset() -> TileSet:
	return _tileset


## Returns the source ID for a given cell type and variant.
## Maps cell type + variant to the correct tileset source.
func get_source_for_variant(cell: PCGCell, variant: String) -> int:
	# Map cell type + variant to the correct tileset source
	# Road cells
	if cell.is_road():
		match variant:
			"center_v":
				return _variant_sources.get("road_urban_center", -1)
			"center_h":
				return _variant_sources.get("road_urban_center_h", -1)
			"crosswalk":
				return _variant_sources.get("crosswalk_urban", -1)
			"basic":
				return _variant_sources.get("road_urban", -1)
			_:
				return _variant_sources.get("road_urban", -1)
	
	# Sidewalk cells (urban zone, not road)
	match variant:
		# Basic sidewalk variants
		"basic":
			return _variant_sources.get("sidewalk_urban", -1)
		
		# Grassground variants
		"grassground_1":
			return _variant_sources.get("sidewalk_urban_grassground_1", -1)
		"grassground_2":
			return _variant_sources.get("sidewalk_urban_grassground_2", -1)
		"grassground_3":
			return _variant_sources.get("sidewalk_urban_grassground_3", -1)
		"grassground_4":
			return _variant_sources.get("sidewalk_urban_grassground_4", -1)
		
		# Edge tiles bordering road
		"edge_road_se":
			return _variant_sources.get("sidewalk_urban_edge_se", -1)
		"edge_road_nw":
			return _variant_sources.get("sidewalk_urban_edge_nw", -1)
		"edge_road_ne":
			return _variant_sources.get("sidewalk_urban_edge_ne", -1)
		"edge_road_sw":
			return _variant_sources.get("sidewalk_urban_edge_sw", -1)
		
		# Edge tiles bordering grassground
		"edge_grassground_se":
			return _variant_sources.get("sidewalk_urban_edge_grassground_se", -1)
		"edge_grassground_nw":
			return _variant_sources.get("sidewalk_urban_edge_grassground_nw", -1)
		"edge_grassground_ne":
			return _variant_sources.get("sidewalk_urban_edge_grassground_ne", -1)
		"edge_grassground_sw":
			return _variant_sources.get("sidewalk_urban_edge_grassground_sw", -1)
		
		# Crosswalk edge variants
		"edge_road_ne_crosswalk":
			return _variant_sources.get("sidewalk_urban_edge_ne_crosswalk", -1)
		"edge_road_nw_crosswalk":
			return _variant_sources.get("sidewalk_urban_edge_nw_crosswalk", -1)
		"edge_road_se_crosswalk":
			return _variant_sources.get("sidewalk_urban_edge_se_crosswalk", -1)
		"edge_road_sw_crosswalk":
			return _variant_sources.get("sidewalk_urban_edge_sw_crosswalk", -1)
		
		# Corner tiles bordering road - cardinal naming (n, s, e, w)
		"corner_road_n":
			return _variant_sources.get("sidewalk_urban_corner_n", -1)
		"corner_road_s":
			return _variant_sources.get("sidewalk_urban_corner_s", -1)
		"corner_road_e":
			return _variant_sources.get("sidewalk_urban_corner_e", -1)
		"corner_road_w":
			return _variant_sources.get("sidewalk_urban_corner_w", -1)
		
		# Corner tiles bordering grassground - cardinal naming
		"corner_grassground_n":
			return _variant_sources.get("sidewalk_urban_corner_grassground_n", -1)
		"corner_grassground_s":
			return _variant_sources.get("sidewalk_urban_corner_grassground_s", -1)
		"corner_grassground_e":
			return _variant_sources.get("sidewalk_urban_corner_grassground_e", -1)
		"corner_grassground_w":
			return _variant_sources.get("sidewalk_urban_corner_grassground_w", -1)
		
		# Outcorner tiles (sidewalk protrudes into road) - cardinal naming
		"outcorner_road_n":
			return _variant_sources.get("sidewalk_urban_outcorner_n", -1)
		"outcorner_road_s":
			return _variant_sources.get("sidewalk_urban_outcorner_s", -1)
		"outcorner_road_e":
			return _variant_sources.get("sidewalk_urban_outcorner_e", -1)
		"outcorner_road_w":
			return _variant_sources.get("sidewalk_urban_outcorner_w", -1)
		
		_:
			return _variant_sources.get("sidewalk_urban", -1)


## Gets or creates a tile source for a solid color (used for zone rendering).
## Colors are quantized to reduce the number of unique sources.
func get_or_create_color_source(color: Color) -> int:
	# Get or create a tile source for a solid color
	var step := 0.04
	var qr := int(color.r / step) * step
	var qg := int(color.g / step) * step
	var qb := int(color.b / step) * step
	var key := "%d_%d_%d" % [int(qr * 1000), int(qg * 1000), int(qb * 1000)]
	
	if _color_sources.has(key):
		return _color_sources[key]
	
	var quantized := Color(qr, qg, qb, 1.0)
	var texture := _generate_diamond_texture(quantized)
	
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	source.create_tile(Vector2i(0, 0))
	
	_tileset.add_source(source, _next_source_id)
	_color_sources[key] = _next_source_id
	
	var result := _next_source_id
	_next_source_id += 1
	return result


## Returns the variant_sources dictionary (for testing/debugging).
func get_variant_sources() -> Dictionary:
	return _variant_sources


## Returns the color_sources dictionary (for testing/debugging).
func get_color_sources() -> Dictionary:
	return _color_sources


## Adds a texture source to the tileset.
## Returns true if successful, false if texture could not be loaded.
func _add_texture_source(path: String, source_id: int) -> bool:
	# Add a texture source to the tileset
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Failed to load: %s" % path)
		return false
	
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_WIDTH, TILE_HEIGHT)
	source.create_tile(Vector2i(0, 0))
	
	_tileset.add_source(source, source_id)
	return true


## Generates an isometric diamond tile texture filled with the given color.
func _generate_diamond_texture(color: Color) -> ImageTexture:
	# Generate isometric diamond tile texture
	var image := Image.create(TILE_WIDTH, TILE_HEIGHT, false, Image.FORMAT_RGBA8)
	
	var center_x := TILE_WIDTH / 2.0
	var center_y := TILE_HEIGHT / 2.0
	var half_w := TILE_WIDTH / 2.0
	var half_h := TILE_HEIGHT / 2.0
	
	for y in range(TILE_HEIGHT):
		for x in range(TILE_WIDTH):
			var px: float = float(x) + 0.5
			var py: float = float(y) + 0.5
			var nx: float = abs(px - center_x) / half_w
			var ny: float = abs(py - center_y) / half_h
			
			if nx + ny <= 1.0:
				var shade := 1.0 + (randf() - 0.5) * 0.05
				var final_color := Color(
					clampf(color.r * shade, 0.0, 1.0),
					clampf(color.g * shade, 0.0, 1.0),
					clampf(color.b * shade, 0.0, 1.0),
					1.0
				)
				image.set_pixel(x, y, final_color)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	return ImageTexture.create_from_image(image)
