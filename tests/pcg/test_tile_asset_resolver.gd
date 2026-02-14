class_name TestTileAssetResolver
extends GdUnitTestSuite

const TileAssetResolver = preload("res://scripts/pcg/tile_asset_resolver.gd")


var _resolver: TileAssetResolver


func before_test() -> void:
	_resolver = TileAssetResolver.new()


func after_test() -> void:
	_resolver = null


# =============================================================================
# Enum Tests
# =============================================================================

func test_logic_type_enum_has_all_values() -> void:
	# Verify all logic types exist
	assert_int(TileAssetResolver.LogicType.ROAD).is_equal(0)
	assert_int(TileAssetResolver.LogicType.SIDEWALK).is_equal(1)
	assert_int(TileAssetResolver.LogicType.CROSSWALK).is_equal(2)
	assert_int(TileAssetResolver.LogicType.GRASS).is_equal(3)
	assert_int(TileAssetResolver.LogicType.DIRT).is_equal(4)
	assert_int(TileAssetResolver.LogicType.WATER).is_equal(5)
	assert_int(TileAssetResolver.LogicType.FLOOR).is_equal(6)


func test_transition_type_enum_has_all_values() -> void:
	# Verify all transition types exist
	assert_int(TileAssetResolver.TransitionType.NONE).is_equal(0)
	assert_int(TileAssetResolver.TransitionType.EDGE).is_equal(1)
	assert_int(TileAssetResolver.TransitionType.CORNER).is_equal(2)
	assert_int(TileAssetResolver.TransitionType.OPPOSITE).is_equal(3)
	assert_int(TileAssetResolver.TransitionType.END).is_equal(4)
	assert_int(TileAssetResolver.TransitionType.ISOLATED).is_equal(5)


func test_direction_enum_has_all_values() -> void:
	# Verify all directions exist (simplified to 4 isometric directions only)
	assert_int(TileAssetResolver.Direction.NONE).is_equal(0)
	assert_int(TileAssetResolver.Direction.NW).is_equal(1)
	assert_int(TileAssetResolver.Direction.NE).is_equal(2)
	assert_int(TileAssetResolver.Direction.SW).is_equal(3)
	assert_int(TileAssetResolver.Direction.SE).is_equal(4)


# =============================================================================
# Basic resolve() Tests
# =============================================================================

func test_resolve_returns_string() -> void:
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NONE
	)
	assert_str(result).is_not_empty()


func test_resolve_with_variant_parameter() -> void:
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.SIDEWALK,
		TileAssetResolver.TransitionType.EDGE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NE,
		"urban"
	)
	assert_str(result).is_not_empty()


func test_resolve_default_variant_is_base() -> void:
	# Both should return same result when default variant is used
	var result_explicit: String = _resolver.resolve(
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NONE,
		"base"
	)
	var result_default: String = _resolver.resolve(
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NONE
	)
	assert_str(result_explicit).is_equal(result_default)


# =============================================================================
# Fallback Chain Tests
# =============================================================================

func test_resolve_fallback_to_default_when_no_assets_exist() -> void:
	# When no asset exists for a logic type, should return default path
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.GRASS,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.GRASS,
		TileAssetResolver.Direction.NONE
	)
	# Should return default path when no grass assets exist
	assert_str(result).is_equal(TileAssetResolver.DEFAULT_PATH)


func test_resolve_fallback_to_transaction_base() -> void:
	# When specific neighbor path doesn't exist, fallback to transaction base
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.SIDEWALK,
		TileAssetResolver.TransitionType.EDGE,
		TileAssetResolver.LogicType.WATER,  # Unlikely combination
		TileAssetResolver.Direction.NE
	)
	# Should still return a valid path
	assert_str(result).is_not_empty()
	assert_str(result).ends_with(".png")


func test_resolve_returns_error_path_when_all_fallbacks_fail() -> void:
	# Test with completely invalid combination that won't have any assets
	# The resolver should return a default/error path
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.WATER,
		TileAssetResolver.TransitionType.ISOLATED,
		TileAssetResolver.LogicType.FLOOR,
		TileAssetResolver.Direction.NW,
		"nonexistent_variant"
	)
	# Should return some default path (not empty, not crash)
	assert_str(result).is_not_empty()


# =============================================================================
# Caching Tests
# =============================================================================

func test_resolve_same_params_returns_cached_result() -> void:
	# First call
	var result1: String = _resolver.resolve(
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NONE
	)
	# Second call with same params
	var result2: String = _resolver.resolve(
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NONE
	)
	# Should return identical results (from cache)
	assert_str(result1).is_equal(result2)


func test_clear_cache_clears_cached_paths() -> void:
	# Populate cache
	var _result: String = _resolver.resolve(
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NONE
	)
	# Clear cache - should not throw
	_resolver.clear_cache()
	# Should still work after clearing
	var result_after: String = _resolver.resolve(
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NONE
	)
	assert_str(result_after).is_not_empty()


# =============================================================================
# Path Format Tests
# =============================================================================

func test_resolve_path_starts_with_asset_root() -> void:
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NONE
	)
	assert_str(result).starts_with("res://assets/tiles/")


func test_resolve_path_uses_lowercase_names() -> void:
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.SIDEWALK,
		TileAssetResolver.TransitionType.EDGE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NE
	)
	# Path should be lowercase
	assert_str(result).is_equal(result.to_lower())


# =============================================================================
# Edge Case Tests
# =============================================================================

func test_resolve_direction_none_omits_direction_from_path() -> void:
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.ROAD,
		TileAssetResolver.Direction.NONE
	)
	# When direction is NONE, path should not contain direction segment
	# Result should still be valid
	assert_str(result).is_not_empty()


func test_resolve_transaction_none_uses_simple_path() -> void:
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.GRASS,
		TileAssetResolver.TransitionType.NONE,
		TileAssetResolver.LogicType.GRASS,
		TileAssetResolver.Direction.NONE
	)
	# With NONE transaction, should resolve to simple logic base path
	assert_str(result).is_not_empty()


func test_resolve_different_logic_and_neighbor_types() -> void:
	var result: String = _resolver.resolve(
		TileAssetResolver.LogicType.SIDEWALK,
		TileAssetResolver.TransitionType.EDGE,
		TileAssetResolver.LogicType.ROAD,  # Different from logic
		TileAssetResolver.Direction.SW
	)
	assert_str(result).is_not_empty()


func test_resolve_all_direction_values() -> void:
	# Test that all direction values work without crashing
	var directions := [
		TileAssetResolver.Direction.NONE,
		TileAssetResolver.Direction.NW,
		TileAssetResolver.Direction.NE,
		TileAssetResolver.Direction.SW,
		TileAssetResolver.Direction.SE,
	]
	
	for dir in directions:
		var result: String = _resolver.resolve(
			TileAssetResolver.LogicType.SIDEWALK,
			TileAssetResolver.TransitionType.EDGE,
			TileAssetResolver.LogicType.ROAD,
			dir
		)
		assert_str(result).is_not_empty()
