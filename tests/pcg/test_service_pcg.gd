# tests/pcg/test_service_pcg.gd
extends GdUnitTestSuite
## TDD (RED): Contract tests for Service_PCG (PCG service integration).
## Defines expected behavior:
## - Full pipeline execution (all phases run in sequence)
## - Determinism by seed
## - ServiceContext registration contract

# NOTE: Preloads are intentional for RED phase (service may not exist yet).
const Service_PCG := preload("res://scripts/services/impl/service_pcg.gd")
const ServiceContext := preload("res://scripts/services/service_context.gd")

const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const PCGResult := preload("res://scripts/pcg/data/pcg_result.gd")
const RoadGraph := preload("res://scripts/pcg/data/road_graph.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")
const POIList := preload("res://scripts/pcg/data/poi_list.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")


class _TestConfig extends PCGConfig:
	## Contract: Service_PCG consumes a .pcg_seed (duck-typed like pipeline tests).

	func _init(p_seed: int = 0) -> void:
		pcg_seed = p_seed


func test_service_generates_full_result() -> void:
	var service := Service_PCG.new()
	var config := _make_config(1337)

	var result: PCGResult = service.generate(config)

	_assert_pcg_result_complete(result, config)
	# Contract: service registration via ServiceContext (pattern-based).
	assert_array(ServiceContext._defined_services()).contains(["pcg"])
	# has_method is an instance method; use the singleton instance()
	assert_bool(ServiceContext.instance().has_method("pcg")).is_true()


func test_seed_determinism() -> void:
	var service := Service_PCG.new()

	var config_a := _make_config(4242)
	var config_b := _make_config(4242)

	var result_a: PCGResult = service.generate(config_a)
	var result_b: PCGResult = service.generate(config_b)

	_assert_pcg_result_complete(result_a, config_a)
	_assert_pcg_result_complete(result_b, config_b)

	# Road graph determinism (still directly stored, not grid-derived)
	_assert_road_graphs_equal(result_a.road_graph, result_b.road_graph)

	# Unified grid determinism: grid content must match across runs
	assert_int(result_a.grid.size()).is_equal(result_b.grid.size())
	for pos: Vector2i in result_a.grid.keys():
		assert_bool(result_b.grid.has(pos)).is_true()
		var cell_a: PCGCell = result_a.grid[pos]
		var cell_b: PCGCell = result_b.grid[pos]
		assert_int(cell_a.zone_type).is_equal(cell_b.zone_type)
		assert_bool(cell_a.logic_type == TileAssetResolver.LogicType.ROAD).is_equal(cell_b.logic_type == TileAssetResolver.LogicType.ROAD)
		assert_int(cell_a.poi_type).is_equal(cell_b.poi_type)


# --------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------
func _make_config(seed: int) -> _TestConfig:
	var config := _TestConfig.new(seed)

	# Keep config small/fast but non-trivial; service is expected to validate/use these.
	config.zone_threshold_suburbs = 0.35
	config.zone_threshold_urban = 0.7

	return config


func _assert_pcg_result_complete(result: PCGResult, config: _TestConfig) -> void:
	assert_object(result).is_not_null()
	assert_bool(result is PCGResult).is_true()

	# Contract: result contains the exact config instance.
	assert_object(result.config).is_equal(config)

	# Contract: road_graph still exists directly (not grid-derived).
	assert_object(result.road_graph).is_not_null()
	assert_bool(result.road_graph is RoadGraph).is_true()
	assert_int(result.road_graph.nodes.size()).is_greater(0)

	# Contract: unified grid is present and non-empty (contains zone + poi data).
	assert_bool(result.grid is Dictionary).is_true()
	assert_int(result.grid.size()).is_greater(0)

	# Contract: grid contains zone data (at least some cells have non-default zone_type).
	var has_zone_data: bool = false
	var has_poi_data: bool = false
	for pos: Vector2i in result.grid.keys():
		var cell: PCGCell = result.grid[pos]
		if cell.zone_type != ZoneMap.ZoneType.WILDERNESS:
			has_zone_data = true
		if cell.poi_type >= 0:
			has_poi_data = true
		if has_zone_data and has_poi_data:
			break
	assert_bool(has_zone_data).is_true()
	assert_bool(has_poi_data).is_true()


func _assert_road_graphs_equal(a: RoadGraph, b: RoadGraph) -> void:
	assert_int(a.nodes.size()).is_equal(b.nodes.size())
	for i: int in a.nodes.size():
		assert_vector(a.nodes[i].position).is_equal(b.nodes[i].position)
		assert_float(a.nodes[i].width).is_equal(b.nodes[i].width)
		assert_str(a.nodes[i].type).is_equal(b.nodes[i].type)

	assert_int(a.edges.size()).is_equal(b.edges.size())
	for i: int in a.edges.size():
		assert_vector(a.edges[i].from_node.position).is_equal(b.edges[i].from_node.position)
		assert_vector(a.edges[i].to_node.position).is_equal(b.edges[i].to_node.position)
