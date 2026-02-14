extends GdUnitTestSuite
## Unit tests for SMapRender system

const PCGCellScript := preload("res://scripts/pcg/data/pcg_cell.gd")
const SMapRenderScript := preload("res://scripts/systems/s_map_render.gd")
const TileSetBuilderScript := preload("res://scripts/pcg/tile_set_builder.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")

## --- Test Helpers ---

func _create_mock_pcg_result(cells: Dictionary = {}) -> PCGResult:
	var config := PCGConfig.new()
	var road_graph := RoadGraph.new()
	return PCGResult.new(config, road_graph, null, null, cells)


func _create_road_cell(variant: String = "basic") -> PCGCellScript:
	var cell := PCGCellScript.new()
	cell.logic_type = TileAssetResolver.LogicType.ROAD
	cell.zone_type = 2  # URBAN
	cell.data["tile_variant"] = variant
	return cell


func _create_sidewalk_cell(variant: String = "basic") -> PCGCellScript:
	var cell := PCGCellScript.new()
	cell.logic_type = TileAssetResolver.LogicType.GRASS
	cell.zone_type = 2  # URBAN
	cell.data["tile_variant"] = variant
	return cell


## --- System Configuration Tests ---

func test_system_has_render_group() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	# _ready() sets the group
	assert_str(system.group).is_equal("render")
	
	system.queue_free()


func test_system_creates_tile_layer() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	# System should have created internal TileMapLayer
	assert_object(system.get_tile_layer()).is_not_null()
	assert_object(system.get_tile_layer()).is_instanceof(TileMapLayer)
	
	system.queue_free()


func test_system_creates_tileset_via_builder() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	assert_object(tile_layer.tile_set).is_not_null()
	
	# TileSetBuilder creates 35 texture sources
	var source_count := 0
	for i in range(50):
		if tile_layer.tile_set.has_source(i):
			source_count += 1
	assert_int(source_count).is_equal(35)
	
	system.queue_free()


func test_tileset_is_isometric() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	var tileset: TileSet = tile_layer.tile_set
	
	assert_int(tileset.tile_shape).is_equal(TileSet.TILE_SHAPE_ISOMETRIC)
	assert_int(tileset.tile_layout).is_equal(TileSet.TILE_LAYOUT_DIAMOND_DOWN)
	assert_object(tileset.tile_size).is_equal(Vector2i(64, 32))
	
	system.queue_free()


## --- Query Tests ---

func test_system_queries_for_cmapdata() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	# Note: In unit test context without full ECS, the query builder 'q' is null.
	# This test verifies the system instantiates correctly; full query testing
	# requires ECS integration tests.
	# The query() method is tested implicitly via ECS integration when process() runs.
	assert_object(system).is_not_null()
	
	system.queue_free()


## --- Render Tests ---

func test_render_map_with_empty_result() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var pcg_result := _create_mock_pcg_result({})
	system.render_map(pcg_result)
	
	# Should not crash, tile layer should still be empty/valid
	var tile_layer: TileMapLayer = system.get_tile_layer()
	assert_object(tile_layer).is_not_null()
	
	system.queue_free()


func test_render_map_with_null_result() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	# Should not crash with null
	system.render_map(null)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	assert_object(tile_layer).is_not_null()
	
	system.queue_free()


func test_render_single_road_cell() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var cells := {
		Vector2i(0, 0): _create_road_cell("center_v")
	}
	var pcg_result := _create_mock_pcg_result(cells)
	system.render_map(pcg_result)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	var source_id: int = tile_layer.get_cell_source_id(Vector2i(0, 0))
	
	# Should have a valid source ID (road_urban_center = source 2)
	assert_int(source_id).is_greater(-1)
	
	system.queue_free()


func test_render_single_sidewalk_cell() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var cells := {
		Vector2i(0, 0): _create_sidewalk_cell("basic")
	}
	var pcg_result := _create_mock_pcg_result(cells)
	system.render_map(pcg_result)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	var source_id: int = tile_layer.get_cell_source_id(Vector2i(0, 0))
	
	# Should have valid source ID for sidewalk_urban
	assert_int(source_id).is_greater(-1)
	
	system.queue_free()


func test_render_multiple_cells() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var cells := {
		Vector2i(0, 0): _create_road_cell("center_v"),
		Vector2i(1, 0): _create_sidewalk_cell("edge_road_ne"),
		Vector2i(2, 0): _create_sidewalk_cell("basic"),
		Vector2i(0, 1): _create_road_cell("crosswalk"),
	}
	var pcg_result := _create_mock_pcg_result(cells)
	system.render_map(pcg_result)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	
	# All cells should have valid source IDs
	assert_int(tile_layer.get_cell_source_id(Vector2i(0, 0))).is_greater(-1)
	assert_int(tile_layer.get_cell_source_id(Vector2i(1, 0))).is_greater(-1)
	assert_int(tile_layer.get_cell_source_id(Vector2i(2, 0))).is_greater(-1)
	assert_int(tile_layer.get_cell_source_id(Vector2i(0, 1))).is_greater(-1)
	
	system.queue_free()


func test_render_uses_fallback_for_default_variant() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var cell := PCGCellScript.new()
	cell.logic_type = TileAssetResolver.LogicType.GRASS
	cell.zone_type = 2
	cell.data["tile_variant"] = "default"  # Uses zone-colored fallback
	
	var cells := {Vector2i(5, 5): cell}
	var pcg_result := _create_mock_pcg_result(cells)
	system.render_map(pcg_result)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	# Cell with "default" variant should get zone-colored fallback tile (source_id >= 100)
	assert_int(tile_layer.get_cell_source_id(Vector2i(5, 5))).is_greater_equal(100)
	
	system.queue_free()


func test_render_uses_fallback_for_empty_variant() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var cell := PCGCellScript.new()
	cell.logic_type = TileAssetResolver.LogicType.GRASS
	cell.zone_type = 2
	cell.data["tile_variant"] = ""  # Uses zone-colored fallback
	
	var cells := {Vector2i(3, 3): cell}
	var pcg_result := _create_mock_pcg_result(cells)
	system.render_map(pcg_result)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	# Cell with empty variant should get zone-colored fallback tile (source_id >= 100)
	assert_int(tile_layer.get_cell_source_id(Vector2i(3, 3))).is_greater_equal(100)
	
	system.queue_free()


func test_render_uses_tile_id_fallback() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	# Cell with tile_id instead of tile_variant (legacy fallback)
	var cell := PCGCellScript.new()
	cell.logic_type = TileAssetResolver.LogicType.ROAD
	cell.zone_type = 2
	cell.data["tile_id"] = "center_v"  # Legacy field
	
	var cells := {Vector2i(0, 0): cell}
	var pcg_result := _create_mock_pcg_result(cells)
	system.render_map(pcg_result)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	var source_id: int = tile_layer.get_cell_source_id(Vector2i(0, 0))
	
	# Should use tile_id as fallback
	assert_int(source_id).is_greater(-1)
	
	system.queue_free()


func test_render_clears_previous_cells() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	# First render
	var cells1 := {
		Vector2i(0, 0): _create_road_cell("center_v"),
		Vector2i(1, 1): _create_sidewalk_cell("basic")
	}
	system.render_map(_create_mock_pcg_result(cells1))
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	assert_int(tile_layer.get_cell_source_id(Vector2i(0, 0))).is_greater(-1)
	assert_int(tile_layer.get_cell_source_id(Vector2i(1, 1))).is_greater(-1)
	
	# Second render with different cells
	var cells2 := {
		Vector2i(5, 5): _create_road_cell("basic")
	}
	system.render_map(_create_mock_pcg_result(cells2))
	
	# Old cells should be cleared
	assert_int(tile_layer.get_cell_source_id(Vector2i(0, 0))).is_equal(-1)
	assert_int(tile_layer.get_cell_source_id(Vector2i(1, 1))).is_equal(-1)
	# New cell should be set
	assert_int(tile_layer.get_cell_source_id(Vector2i(5, 5))).is_greater(-1)
	
	system.queue_free()


## --- Variant Mapping Tests ---

func test_road_variants_map_correctly() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var builder: TileSetBuilderScript = system.get_tile_set_builder()
	var road_cell := _create_road_cell()
	
	# Test all road variants
	assert_int(builder.get_source_for_variant(road_cell, "center_v")).is_greater(-1)
	assert_int(builder.get_source_for_variant(road_cell, "center_h")).is_greater(-1)
	assert_int(builder.get_source_for_variant(road_cell, "crosswalk")).is_greater(-1)
	assert_int(builder.get_source_for_variant(road_cell, "basic")).is_greater(-1)
	
	system.queue_free()


func test_sidewalk_edge_variants_map_correctly() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var builder: TileSetBuilderScript = system.get_tile_set_builder()
	var sidewalk_cell := _create_sidewalk_cell()
	
	# Test edge variants
	assert_int(builder.get_source_for_variant(sidewalk_cell, "edge_road_ne")).is_greater(-1)
	assert_int(builder.get_source_for_variant(sidewalk_cell, "edge_road_nw")).is_greater(-1)
	assert_int(builder.get_source_for_variant(sidewalk_cell, "edge_road_se")).is_greater(-1)
	assert_int(builder.get_source_for_variant(sidewalk_cell, "edge_road_sw")).is_greater(-1)
	
	system.queue_free()


func test_sidewalk_corner_variants_map_correctly() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var builder: TileSetBuilderScript = system.get_tile_set_builder()
	var sidewalk_cell := _create_sidewalk_cell()
	
	# Test corner variants
	assert_int(builder.get_source_for_variant(sidewalk_cell, "corner_road_n")).is_greater(-1)
	assert_int(builder.get_source_for_variant(sidewalk_cell, "corner_road_s")).is_greater(-1)
	assert_int(builder.get_source_for_variant(sidewalk_cell, "corner_road_e")).is_greater(-1)
	assert_int(builder.get_source_for_variant(sidewalk_cell, "corner_road_w")).is_greater(-1)
	
	system.queue_free()


func test_grassground_variants_map_correctly() -> void:
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var builder: TileSetBuilderScript = system.get_tile_set_builder()
	var sidewalk_cell := _create_sidewalk_cell()
	
	# Test grassground variants
	assert_int(builder.get_source_for_variant(sidewalk_cell, "grassground_1")).is_greater(-1)
	assert_int(builder.get_source_for_variant(sidewalk_cell, "grassground_2")).is_greater(-1)
	assert_int(builder.get_source_for_variant(sidewalk_cell, "grassground_3")).is_greater(-1)
	assert_int(builder.get_source_for_variant(sidewalk_cell, "grassground_4")).is_greater(-1)
	
	system.queue_free()


## --- Process Integration Tests ---

func test_process_renders_from_cmapdata() -> void:
	# This test would require full ECS integration
	# For now, test the render_map method directly
	var system: SMapRenderScript = SMapRenderScript.new()
	add_child(system)
	
	var cells := {Vector2i(0, 0): _create_road_cell("basic")}
	var pcg_result := _create_mock_pcg_result(cells)
	
	# Simulate what process() would do
	system.render_map(pcg_result)
	
	var tile_layer: TileMapLayer = system.get_tile_layer()
	assert_int(tile_layer.get_cell_source_id(Vector2i(0, 0))).is_greater(-1)
	
	system.queue_free()
