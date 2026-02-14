# tests/pcg/test_tile_set_builder.gd
extends GdUnitTestSuite
## Unit tests for TileSetBuilder.
## Verifies extracted tileset building logic matches original behavior.

const TileSetBuilder := preload("res://scripts/pcg/tile_set_builder.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")


# -------------------------
# build_tileset() Tests
# -------------------------

func test_build_tileset_returns_valid_tileset() -> void:
	## build_tileset() returns a non-null TileSet
	var builder := TileSetBuilder.new()
	
	var tileset := builder.build_tileset()
	
	assert_object(tileset).is_not_null()
	assert_object(tileset).is_instanceof(TileSet)


func test_build_tileset_configures_isometric_settings() -> void:
	## TileSet has correct isometric configuration
	var builder := TileSetBuilder.new()
	
	var tileset := builder.build_tileset()
	
	assert_int(tileset.tile_shape).is_equal(TileSet.TILE_SHAPE_ISOMETRIC)
	assert_int(tileset.tile_layout).is_equal(TileSet.TILE_LAYOUT_DIAMOND_DOWN)
	assert_object(tileset.tile_size).is_equal(Vector2i(64, 32))


func test_build_tileset_registers_35_variant_sources() -> void:
	## Builds tileset with correct number of sources (35)
	var builder := TileSetBuilder.new()
	
	builder.build_tileset()
	
	# Should have 35 variant sources registered
	assert_int(builder.get_variant_sources().size()).is_equal(35)


func test_build_tileset_clears_previous_state() -> void:
	## Calling build_tileset() multiple times resets state
	var builder := TileSetBuilder.new()
	
	builder.build_tileset()
	var first_sources := builder.get_variant_sources().duplicate()
	
	builder.build_tileset()
	var second_sources := builder.get_variant_sources()
	
	# Should have same sources after rebuild
	assert_int(second_sources.size()).is_equal(first_sources.size())


func test_variant_sources_has_all_expected_keys() -> void:
	## All 35 expected variant source keys are present
	var builder := TileSetBuilder.new()
	builder.build_tileset()
	var sources := builder.get_variant_sources()
	
	# Road variants (6) + sidewalk (1) = 7
	assert_bool(sources.has("road_urban")).is_true()
	assert_bool(sources.has("road_urban_center")).is_true()
	assert_bool(sources.has("road_urban_center_h")).is_true()
	assert_bool(sources.has("crosswalk_urban")).is_true()
	assert_bool(sources.has("crosswalk_urban_center")).is_true()
	assert_bool(sources.has("crosswalk_urban_road")).is_true()
	assert_bool(sources.has("sidewalk_urban")).is_true()
	
	# Grassground variants (4)
	assert_bool(sources.has("sidewalk_urban_grassground_1")).is_true()
	assert_bool(sources.has("sidewalk_urban_grassground_2")).is_true()
	assert_bool(sources.has("sidewalk_urban_grassground_3")).is_true()
	assert_bool(sources.has("sidewalk_urban_grassground_4")).is_true()
	
	# Corner variants - road (4)
	assert_bool(sources.has("sidewalk_urban_corner_n")).is_true()
	assert_bool(sources.has("sidewalk_urban_corner_s")).is_true()
	assert_bool(sources.has("sidewalk_urban_corner_e")).is_true()
	assert_bool(sources.has("sidewalk_urban_corner_w")).is_true()
	
	# Corner variants - grassground (4)
	assert_bool(sources.has("sidewalk_urban_corner_grassground_n")).is_true()
	assert_bool(sources.has("sidewalk_urban_corner_grassground_s")).is_true()
	assert_bool(sources.has("sidewalk_urban_corner_grassground_e")).is_true()
	assert_bool(sources.has("sidewalk_urban_corner_grassground_w")).is_true()
	
	# Outcorner variants (4)
	assert_bool(sources.has("sidewalk_urban_outcorner_n")).is_true()
	assert_bool(sources.has("sidewalk_urban_outcorner_s")).is_true()
	assert_bool(sources.has("sidewalk_urban_outcorner_e")).is_true()
	assert_bool(sources.has("sidewalk_urban_outcorner_w")).is_true()
	
	# Crosswalk edge variants (4)
	assert_bool(sources.has("sidewalk_urban_edge_ne_crosswalk")).is_true()
	assert_bool(sources.has("sidewalk_urban_edge_nw_crosswalk")).is_true()
	assert_bool(sources.has("sidewalk_urban_edge_se_crosswalk")).is_true()
	assert_bool(sources.has("sidewalk_urban_edge_sw_crosswalk")).is_true()
	
	# Edge variants - road (4)
	assert_bool(sources.has("sidewalk_urban_edge_ne")).is_true()
	assert_bool(sources.has("sidewalk_urban_edge_nw")).is_true()
	assert_bool(sources.has("sidewalk_urban_edge_se")).is_true()
	assert_bool(sources.has("sidewalk_urban_edge_sw")).is_true()
	
	# Edge variants - grassground (4)
	assert_bool(sources.has("sidewalk_urban_edge_grassground_ne")).is_true()
	assert_bool(sources.has("sidewalk_urban_edge_grassground_nw")).is_true()
	assert_bool(sources.has("sidewalk_urban_edge_grassground_se")).is_true()
	assert_bool(sources.has("sidewalk_urban_edge_grassground_sw")).is_true()


# -------------------------
# get_source_for_variant() Tests - Road Variants
# -------------------------

func test_get_source_for_variant_road_center_v() -> void:
	## Road "center_v" variant returns correct source ID
	var builder := _create_builder_with_sources()
	var road_cell := _create_road_cell()
	
	var source_id := builder.get_source_for_variant(road_cell, "center_v")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("road_urban_center", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_road_center_h() -> void:
	## Road "center_h" variant returns correct source ID
	var builder := _create_builder_with_sources()
	var road_cell := _create_road_cell()
	
	var source_id := builder.get_source_for_variant(road_cell, "center_h")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("road_urban_center_h", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_road_crosswalk() -> void:
	## Road "crosswalk" variant returns correct source ID
	var builder := _create_builder_with_sources()
	var road_cell := _create_road_cell()
	
	var source_id := builder.get_source_for_variant(road_cell, "crosswalk")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("crosswalk_urban", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_road_basic() -> void:
	## Road "basic" variant returns correct source ID
	var builder := _create_builder_with_sources()
	var road_cell := _create_road_cell()
	
	var source_id := builder.get_source_for_variant(road_cell, "basic")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("road_urban", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_road_unknown_fallback() -> void:
	## Unknown road variant falls back to "road_urban"
	var builder := _create_builder_with_sources()
	var road_cell := _create_road_cell()
	
	var source_id := builder.get_source_for_variant(road_cell, "unknown_variant")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("road_urban", -999))
	assert_int(source_id).is_not_equal(-1)


# -------------------------
# get_source_for_variant() Tests - Sidewalk Basic Variants
# -------------------------

func test_get_source_for_variant_sidewalk_basic() -> void:
	## Sidewalk "basic" variant returns correct source ID
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "basic")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban", -999))
	assert_int(source_id).is_not_equal(-1)


# -------------------------
# get_source_for_variant() Tests - Grassground Variants
# -------------------------

func test_get_source_for_variant_grassground_1() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "grassground_1")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_grassground_1", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_grassground_2() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "grassground_2")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_grassground_2", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_grassground_3() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "grassground_3")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_grassground_3", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_grassground_4() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "grassground_4")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_grassground_4", -999))
	assert_int(source_id).is_not_equal(-1)


# -------------------------
# get_source_for_variant() Tests - Edge Road Variants
# -------------------------

func test_get_source_for_variant_edge_road_ne() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_road_ne")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_ne", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_edge_road_nw() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_road_nw")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_nw", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_edge_road_se() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_road_se")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_se", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_edge_road_sw() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_road_sw")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_sw", -999))
	assert_int(source_id).is_not_equal(-1)


# -------------------------
# get_source_for_variant() Tests - Edge Grassground Variants
# -------------------------

func test_get_source_for_variant_edge_grassground_ne() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_grassground_ne")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_grassground_ne", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_edge_grassground_nw() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_grassground_nw")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_grassground_nw", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_edge_grassground_se() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_grassground_se")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_grassground_se", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_edge_grassground_sw() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_grassground_sw")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_grassground_sw", -999))
	assert_int(source_id).is_not_equal(-1)


# -------------------------
# get_source_for_variant() Tests - Crosswalk Edge Variants
# -------------------------

func test_get_source_for_variant_edge_road_ne_crosswalk() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_road_ne_crosswalk")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_ne_crosswalk", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_edge_road_nw_crosswalk() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_road_nw_crosswalk")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_nw_crosswalk", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_edge_road_se_crosswalk() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_road_se_crosswalk")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_se_crosswalk", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_edge_road_sw_crosswalk() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "edge_road_sw_crosswalk")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_edge_sw_crosswalk", -999))
	assert_int(source_id).is_not_equal(-1)


# -------------------------
# get_source_for_variant() Tests - Corner Road Variants
# -------------------------

func test_get_source_for_variant_corner_road_n() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "corner_road_n")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_corner_n", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_corner_road_s() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "corner_road_s")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_corner_s", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_corner_road_e() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "corner_road_e")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_corner_e", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_corner_road_w() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "corner_road_w")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_corner_w", -999))
	assert_int(source_id).is_not_equal(-1)


# -------------------------
# get_source_for_variant() Tests - Corner Grassground Variants
# -------------------------

func test_get_source_for_variant_corner_grassground_n() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "corner_grassground_n")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_corner_grassground_n", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_corner_grassground_s() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "corner_grassground_s")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_corner_grassground_s", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_corner_grassground_e() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "corner_grassground_e")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_corner_grassground_e", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_corner_grassground_w() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "corner_grassground_w")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_corner_grassground_w", -999))
	assert_int(source_id).is_not_equal(-1)


# -------------------------
# get_source_for_variant() Tests - Outcorner Road Variants
# -------------------------

func test_get_source_for_variant_outcorner_road_n() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "outcorner_road_n")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_outcorner_n", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_outcorner_road_s() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "outcorner_road_s")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_outcorner_s", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_outcorner_road_e() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "outcorner_road_e")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_outcorner_e", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_outcorner_road_w() -> void:
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "outcorner_road_w")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban_outcorner_w", -999))
	assert_int(source_id).is_not_equal(-1)


# -------------------------
# get_source_for_variant() Tests - Fallback Behavior
# -------------------------

func test_get_source_for_variant_sidewalk_unknown_fallback() -> void:
	## Unknown sidewalk variant falls back to "sidewalk_urban"
	var builder := _create_builder_with_sources()
	var sidewalk_cell := _create_sidewalk_cell()
	
	var source_id := builder.get_source_for_variant(sidewalk_cell, "unknown_variant")
	
	assert_int(source_id).is_equal(builder.get_variant_sources().get("sidewalk_urban", -999))
	assert_int(source_id).is_not_equal(-1)


func test_get_source_for_variant_returns_negative_one_when_source_not_registered() -> void:
	## Returns -1 when variant source not in dictionary
	var builder := TileSetBuilder.new()
	# Don't call build_tileset() - sources are empty
	
	var sidewalk_cell := _create_sidewalk_cell()
	var source_id := builder.get_source_for_variant(sidewalk_cell, "basic")
	
	assert_int(source_id).is_equal(-1)


func test_get_source_for_variant_road_returns_negative_one_when_source_not_registered() -> void:
	## Returns -1 when road variant source not in dictionary
	var builder := TileSetBuilder.new()
	# Don't call build_tileset() - sources are empty
	
	var road_cell := _create_road_cell()
	var source_id := builder.get_source_for_variant(road_cell, "basic")
	
	assert_int(source_id).is_equal(-1)


# -------------------------
# get_or_create_color_source() Tests
# -------------------------

func test_get_or_create_color_source_returns_valid_source_id() -> void:
	## Creates a valid source ID for a color
	var builder := TileSetBuilder.new()
	builder.build_tileset()
	
	var source_id := builder.get_or_create_color_source(Color.RED)
	
	# Source IDs for colors start at 100
	assert_bool(source_id >= 100).is_true()


func test_get_or_create_color_source_returns_same_id_for_same_color() -> void:
	## Same color returns the same source ID (caching)
	var builder := TileSetBuilder.new()
	builder.build_tileset()
	
	var source_id1 := builder.get_or_create_color_source(Color.RED)
	var source_id2 := builder.get_or_create_color_source(Color.RED)
	
	assert_int(source_id1).is_equal(source_id2)


func test_get_or_create_color_source_returns_different_ids_for_different_colors() -> void:
	## Different colors get different source IDs
	var builder := TileSetBuilder.new()
	builder.build_tileset()
	
	var source_id_red := builder.get_or_create_color_source(Color.RED)
	var source_id_blue := builder.get_or_create_color_source(Color.BLUE)
	
	assert_int(source_id_red).is_not_equal(source_id_blue)


func test_get_or_create_color_source_quantizes_similar_colors() -> void:
	## Similar colors (within quantization step) get same source ID
	var builder := TileSetBuilder.new()
	builder.build_tileset()
	
	var color1 := Color(0.5, 0.5, 0.5)
	var color2 := Color(0.51, 0.51, 0.51)  # Within 0.04 step
	
	var source_id1 := builder.get_or_create_color_source(color1)
	var source_id2 := builder.get_or_create_color_source(color2)
	
	assert_int(source_id1).is_equal(source_id2)


func test_get_or_create_color_source_adds_to_tileset() -> void:
	## Color source is added to the tileset
	var builder := TileSetBuilder.new()
	var tileset := builder.build_tileset()
	var initial_sources := tileset.get_source_count()
	
	builder.get_or_create_color_source(Color.YELLOW)
	
	assert_int(tileset.get_source_count()).is_equal(initial_sources + 1)


# -------------------------
# get_tileset() Tests
# -------------------------

func test_get_tileset_returns_null_before_build() -> void:
	## get_tileset() returns null before build_tileset() is called
	var builder := TileSetBuilder.new()
	
	assert_object(builder.get_tileset()).is_null()


func test_get_tileset_returns_same_tileset() -> void:
	## get_tileset() returns the same tileset that build_tileset() returned
	var builder := TileSetBuilder.new()
	var built_tileset := builder.build_tileset()
	
	assert_object(builder.get_tileset()).is_same(built_tileset)


# -------------------------
# Helper Methods
# -------------------------

func _create_builder_with_sources() -> TileSetBuilder:
	## Creates a TileSetBuilder with populated variant sources
	var builder := TileSetBuilder.new()
	builder.build_tileset()
	return builder


func _create_road_cell() -> PCGCell:
	var cell := PCGCell.new()
	cell.logic_type = TileAssetResolver.LogicType.ROAD
	cell.zone_type = 2  # URBAN
	return cell


func _create_sidewalk_cell() -> PCGCell:
	var cell := PCGCell.new()
	cell.logic_type = TileAssetResolver.LogicType.GRASS
	cell.zone_type = 2  # URBAN
	return cell
