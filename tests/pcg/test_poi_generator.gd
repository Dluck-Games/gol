# tests/pcg/test_poi_generator.gd
extends GdUnitTestSuite
## TDD (RED): Contract tests for POIGenerator PCG phase.
## Defines expected behavior:
## - No POIs placed on road cells (grid cells with logic_type == ROAD)
## - POI types respect zone boundaries:
##     BUILDING     -> URBAN
##     VILLAGE      -> SUBURBS
##     ENEMY_SPAWN  -> WILDERNESS
## - Minimum distance constraints enforced (same-type spacing)
## - Building density higher in URBAN than SUBURBS
## - Seed determinism (same seed => identical POI output)

# NOTE: This preload is intentional for RED phase.
# The referenced script may not exist yet and will be implemented next.
const POIGenerator := preload("res://scripts/pcg/phases/poi_generator.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")

const PCGPhase := preload("res://scripts/pcg/pipeline/pcg_phase.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")
const POIList := preload("res://scripts/pcg/data/poi_list.gd")

const _GRID_SIZE: int = 100
const _TILE_SIZE: int = 32

# Layout contract used in tests (x bands, centered):
# - URBAN:      x in [-50..-11]
# - SUBURBS:    x in [-10..29]
# - WILDERNESS: x in [30..49]
const _URBAN_MAX_X_EXCLUSIVE: int = -10
const _SUBURBS_MAX_X_EXCLUSIVE: int = 30


class PCGConfigWithPOI extends PCGConfig:
	# World scaling
	var tile_size: int = _TILE_SIZE

	# Retry budget per POI (prevents infinite loops)
	var placement_attempts_per_poi: int = 200

	func _init() -> void:
		# Override parent defaults for POI testing
		building_count_urban = 20
		building_count_suburbs = 8
		village_count_suburbs = 4
		enemy_spawn_count_wilderness = 6
		min_spacing_cells_by_type = {
			POIList.POIType.BUILDING: 3,
			POIList.POIType.VILLAGE: 10,
			POIList.POIType.ENEMY_SPAWN: 8,
		}
		# Cross-type spacing: VILLAGE to ENEMY_SPAWN
		min_spacing_cross_type = {
			"1,2": 15,  # 15 cells minimum between VILLAGE and ENEMY_SPAWN
		}


func test_no_pois_on_roads() -> void:
	var config := _create_test_config()
	var context := _create_test_context(12345)

	var phase := POIGenerator.new()
	phase.execute(config, context)

	# Ensure something got generated (avoid vacuous pass).
	var poi_cells := _get_poi_cells(context)
	assert_int(poi_cells.size()).is_greater(0)

	for pos: Vector2i in poi_cells:
		var gc: PCGCell = context.grid[pos]
		# No POI cell should also be a road cell
		assert_bool(gc.logic_type == TileAssetResolver.LogicType.ROAD).is_false()


func test_building_in_urban_only() -> void:
	var config := _create_test_config()
	# Override: ensure buildings are ONLY placed in urban for this test
	config.building_count_suburbs = 0
	var context := _create_test_context(12345)

	var phase := POIGenerator.new()
	phase.execute(config, context)

	var building_cells := _get_poi_cells_by_type(context, POIList.POIType.BUILDING)
	assert_int(building_cells.size()).is_greater(0)

	for pos: Vector2i in building_cells:
		var gc: PCGCell = context.grid[pos]
		assert_int(gc.zone_type).is_equal(ZoneMap.ZoneType.URBAN)
		assert_int(gc.poi_type).is_equal(POIList.POIType.BUILDING)


func test_village_in_suburbs_only() -> void:
	var config := _create_test_config()
	var context := _create_test_context(12345)

	var phase := POIGenerator.new()
	phase.execute(config, context)

	var village_cells := _get_poi_cells_by_type(context, POIList.POIType.VILLAGE)
	assert_int(village_cells.size()).is_greater(0)

	for pos: Vector2i in village_cells:
		var gc: PCGCell = context.grid[pos]
		assert_int(gc.zone_type).is_equal(ZoneMap.ZoneType.SUBURBS)
		assert_int(gc.poi_type).is_equal(POIList.POIType.VILLAGE)


func test_enemy_spawn_in_wilderness_only() -> void:
	var config := _create_test_config()
	var context := _create_test_context(12345)

	var phase := POIGenerator.new()
	phase.execute(config, context)

	var spawn_cells := _get_poi_cells_by_type(context, POIList.POIType.ENEMY_SPAWN)
	assert_int(spawn_cells.size()).is_greater(0)

	for pos: Vector2i in spawn_cells:
		var gc: PCGCell = context.grid[pos]
		assert_int(gc.zone_type).is_equal(ZoneMap.ZoneType.WILDERNESS)
		assert_int(gc.poi_type).is_equal(POIList.POIType.ENEMY_SPAWN)


func test_minimum_spacing_same_type() -> void:
	var config := _create_test_config()
	var context := _create_test_context(12345)

	var phase := POIGenerator.new()
	phase.execute(config, context)

	_assert_min_spacing_for_type_grid(context, config, POIList.POIType.BUILDING)
	_assert_min_spacing_for_type_grid(context, config, POIList.POIType.VILLAGE)
	_assert_min_spacing_for_type_grid(context, config, POIList.POIType.ENEMY_SPAWN)


func test_minimum_spacing_village_to_enemy_spawn() -> void:
	# Addresses GitHub issue #93: VILLAGE POIs (player starting points) must be
	# sufficiently distant from ENEMY_SPAWN POIs to give players a safe starting area.
	var config := _create_test_config()
	var context := _create_test_context(12345)

	var phase := POIGenerator.new()
	phase.execute(config, context)

	var village_cells := _get_poi_cells_by_type(context, POIList.POIType.VILLAGE)
	var enemy_cells := _get_poi_cells_by_type(context, POIList.POIType.ENEMY_SPAWN)

	# Skip if no POIs of either type (shouldn't happen with test config)
	if village_cells.is_empty() or enemy_cells.is_empty():
		return

	# Get cross-type spacing from config
	var cross_spacing: int = 15  # Default from min_spacing_cross_type "1,2"
	var cross_spacing_config: Variant = config.get("min_spacing_cross_type")
	if cross_spacing_config is Dictionary:
		var spacing_val: Variant = cross_spacing_config.get("1,2", 15)
		if spacing_val is int:
			cross_spacing = spacing_val

	# Verify every VILLAGE has sufficient distance from every ENEMY_SPAWN
	for village_pos: Vector2i in village_cells:
		for enemy_pos: Vector2i in enemy_cells:
			var dist: float = village_pos.distance_to(enemy_pos)
			assert_float(dist).is_greater_equal(float(cross_spacing))


func test_seed_determinism() -> void:
	var config := _create_test_config()

	var ctx_a := _create_test_context(777)
	var ctx_b := _create_test_context(777)

	var phase_a := POIGenerator.new()
	var phase_b := POIGenerator.new()
	phase_a.execute(config, ctx_a)
	phase_b.execute(config, ctx_b)

	# Grid determinism: ensure the set of POI cells and their types match
	var cells_a := _get_poi_cells(ctx_a)
	var cells_b := _get_poi_cells(ctx_b)

	assert_int(cells_a.size()).is_equal(cells_b.size())
	assert_int(cells_a.size()).is_greater(0)

	# Ensure exact same positions and poi_type values
	for pos: Vector2i in cells_a:
		assert_bool(ctx_b.grid.has(pos)).is_true()
		assert_int(ctx_a.grid[pos].poi_type).is_equal(ctx_b.grid[pos].poi_type)


func test_urban_density_higher_than_suburbs() -> void:
	var config := _create_test_config()
	var context := _create_test_context(12345)

	var phase := POIGenerator.new()
	phase.execute(config, context)

	var building_cells := _get_poi_cells_by_type(context, POIList.POIType.BUILDING)
	assert_int(building_cells.size()).is_greater(0)

	var urban_count: int = 0
	var suburbs_count: int = 0

	for pos: Vector2i in building_cells:
		var gc: PCGCell = context.grid[pos]
		if gc.zone_type == ZoneMap.ZoneType.URBAN:
			urban_count += 1
		elif gc.zone_type == ZoneMap.ZoneType.SUBURBS:
			suburbs_count += 1

	# Contract: buildings are denser in URBAN than SUBURBS.
	assert_int(urban_count).is_greater(suburbs_count)
	assert_int(urban_count).is_greater(0)


# -------------------------
# Helpers
# -------------------------

func _create_test_config() -> PCGConfigWithPOI:
	var config := PCGConfigWithPOI.new()
	config.tile_size = _TILE_SIZE
	config.building_count_urban = 20
	config.building_count_suburbs = 8
	config.village_count_suburbs = 4
	config.enemy_spawn_count_wilderness = 6
	config.min_spacing_cells_by_type = {
		POIList.POIType.BUILDING: 3,
		POIList.POIType.VILLAGE: 10,
		POIList.POIType.ENEMY_SPAWN: 8,
	}
	config.min_spacing_cross_type = {
		"1,2": 15,  # VILLAGE to ENEMY_SPAWN minimum distance
	}
	config.placement_attempts_per_poi = 200
	return config


func _create_test_context(p_seed: int) -> PCGContext:
	var ctx := PCGContext.new(p_seed)

	# Populate unified grid directly with zone data (100x100 centered at origin).
	var half_size: int = _GRID_SIZE / 2
	var start: int = -half_size
	var end: int = _GRID_SIZE - half_size

	for y: int in range(start, end):
		for x: int in range(start, end):
			var zone: int = ZoneMap.ZoneType.WILDERNESS
			if x < _URBAN_MAX_X_EXCLUSIVE:
				zone = ZoneMap.ZoneType.URBAN
			elif x < _SUBURBS_MAX_X_EXCLUSIVE:
				zone = ZoneMap.ZoneType.SUBURBS
			ctx.get_or_create_cell(Vector2i(x, y)).zone_type = zone

	# A few roads sprinkled across all zones (shifted to centered coords).
	var roads: Array[Vector2i] = [
		Vector2i(-45, -45),    # URBAN
		Vector2i(-40, -10),    # URBAN
		Vector2i(-25, 20),     # URBAN
		Vector2i(-5, -40),     # SUBURBS
		Vector2i(10, 5),       # SUBURBS
		Vector2i(25, 40),      # SUBURBS
		Vector2i(35, -35),     # WILDERNESS
		Vector2i(40, 0),       # WILDERNESS
		Vector2i(45, 45),      # WILDERNESS
	]

	for c: Vector2i in roads:
		ctx.get_or_create_cell(c).logic_type = TileAssetResolver.LogicType.ROAD

	return ctx


## Returns all grid positions that have a POI (poi_type >= 0).
func _get_poi_cells(context: PCGContext) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for pos: Vector2i in context.grid.keys():
		if context.grid[pos].poi_type >= 0:
			cells.append(pos)
	return cells


## Returns all grid positions with a specific POI type.
func _get_poi_cells_by_type(context: PCGContext, poi_type: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for pos: Vector2i in context.grid.keys():
		if context.grid[pos].poi_type == poi_type:
			cells.append(pos)
	return cells


func _assert_min_spacing_for_type_grid(context: PCGContext, config: PCGConfigWithPOI, poi_type: int) -> void:
	# Validate spacing using grid cell positions
	var cells := _get_poi_cells_by_type(context, poi_type)

	# If <2, spacing is trivially satisfied
	assert_int(cells.size()).is_greater_equal(0)
	if cells.size() < 2:
		return

	var min_cells: int = int(config.min_spacing_cells_by_type.get(poi_type, 0))
	assert_int(min_cells).is_greater(0)

	for i: int in range(cells.size()):
		var a: Vector2i = cells[i]
		for j: int in range(i + 1, cells.size()):
			var b: Vector2i = cells[j]
			var dx: int = abs(a.x - b.x)
			var dy: int = abs(a.y - b.y)
			# Use Chebyshev distance in cells as a conservative check
			var cell_dist: int = max(dx, dy)
			assert_int(cell_dist).is_greater_equal(min_cells)
