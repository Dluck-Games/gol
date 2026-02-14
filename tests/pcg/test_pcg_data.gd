extends GdUnitTestSuite
## TDD (RED): Contract tests for PCG data classes.
## These tests define the intended API/behavior for upcoming PCG data structures.


# NOTE: These preloads are intentional for RED phase.
# The referenced scripts do not exist yet and will be implemented next.
const RoadGraph := preload("res://scripts/pcg/data/road_graph.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")
const POIList := preload("res://scripts/pcg/data/poi_list.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const PCGResult := preload("res://scripts/pcg/data/pcg_result.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")


func test_road_node_creation_has_position_width_type_fields() -> void:
	var pos := Vector2(12.5, -4.0)
	var width := 3.25
	var road_type := "PRIMARY"

	var node := RoadGraph.RoadNode.new(pos, width, road_type)
	assert_object(node).is_not_null()
	assert_vector(node.position).is_equal(pos)
	assert_float(node.width).is_equal(width)
	assert_str(node.type).is_equal(road_type)


func test_road_edge_creation_references_from_and_to_nodes() -> void:
	var a := RoadGraph.RoadNode.new(Vector2(0, 0), 2.0, "LOCAL")
	var b := RoadGraph.RoadNode.new(Vector2(10, 0), 2.0, "LOCAL")

	var edge := RoadGraph.RoadEdge.new(a, b)
	assert_object(edge).is_not_null()
	assert_object(edge.from_node).is_not_null()
	assert_object(edge.to_node).is_not_null()
	assert_vector(edge.from_node.position).is_equal(Vector2(0, 0))
	assert_vector(edge.to_node.position).is_equal(Vector2(10, 0))


func test_road_graph_add_node_stores_node() -> void:
	var graph := RoadGraph.new()
	var node := RoadGraph.RoadNode.new(Vector2(1, 2), 1.5, "LOCAL")

	graph.add_node(node)
	assert_int(graph.nodes.size()).is_equal(1)
	assert_object(graph.nodes[0]).is_equal(node)


func test_road_graph_add_edge_stores_edge() -> void:
	var graph := RoadGraph.new()
	var a := RoadGraph.RoadNode.new(Vector2(0, 0), 2.0, "LOCAL")
	var b := RoadGraph.RoadNode.new(Vector2(10, 0), 2.0, "LOCAL")

	graph.add_node(a)
	graph.add_node(b)

	var edge := RoadGraph.RoadEdge.new(a, b)
	graph.add_edge(edge)

	assert_int(graph.edges.size()).is_equal(1)
	assert_object(graph.edges[0]).is_equal(edge)
	assert_object(graph.edges[0].from_node).is_equal(a)
	assert_object(graph.edges[0].to_node).is_equal(b)


func test_road_graph_get_nodes_near_filters_by_radius() -> void:
	var graph := RoadGraph.new()
	var n0 := RoadGraph.RoadNode.new(Vector2(0, 0), 2.0, "LOCAL")
	var n1 := RoadGraph.RoadNode.new(Vector2(5, 0), 2.0, "LOCAL")
	var n_far := RoadGraph.RoadNode.new(Vector2(100, 100), 2.0, "LOCAL")
	graph.add_node(n0)
	graph.add_node(n1)
	graph.add_node(n_far)

	var center := Vector2.ZERO
	var radius := 6.0
	var found: Array = graph.get_nodes_near(center, radius)

	assert_object(found).is_not_null()
	assert_int(found.size()).is_equal(2)
	for n in found:
		assert_float(n.position.distance_to(center)).is_less_equal(radius)
	assert_int(_count_nodes_at(found, Vector2(100, 100))).is_equal(0)


func test_zone_type_enum_values() -> void:
	assert_int(ZoneMap.ZoneType.WILDERNESS).is_equal(0)
	assert_int(ZoneMap.ZoneType.SUBURBS).is_equal(1)
	assert_int(ZoneMap.ZoneType.URBAN).is_equal(2)


func test_zone_map_set_zone_and_get_zone() -> void:
	var map := ZoneMap.new()
	map.set_zone(Vector2i(1, 2), ZoneMap.ZoneType.SUBURBS)

	assert_int(map.get_zone(Vector2i(1, 2))).is_equal(ZoneMap.ZoneType.SUBURBS)
	# Unset zones should default to WILDERNESS.
	assert_int(map.get_zone(Vector2i(99, 99))).is_equal(ZoneMap.ZoneType.WILDERNESS)


func test_zone_map_get_zones_in_rect_returns_only_entries_in_rect() -> void:
	var map := ZoneMap.new()
	map.set_zone(Vector2i(1, 1), ZoneMap.ZoneType.URBAN)
	map.set_zone(Vector2i(2, 2), ZoneMap.ZoneType.SUBURBS)
	map.set_zone(Vector2i(10, 10), ZoneMap.ZoneType.URBAN)

	var rect := Rect2i(Vector2i(0, 0), Vector2i(4, 4))
	var zones: Dictionary = map.get_zones_in_rect(rect)

	assert_object(zones).is_not_null()
	assert_int(zones.size()).is_equal(2)
	assert_int(zones[Vector2i(1, 1)]).is_equal(ZoneMap.ZoneType.URBAN)
	assert_int(zones[Vector2i(2, 2)]).is_equal(ZoneMap.ZoneType.SUBURBS)
	assert_int(int(zones.has(Vector2i(10, 10)))).is_equal(0)


func test_poi_type_enum_values() -> void:
	assert_int(POIList.POIType.BUILDING).is_equal(0)
	assert_int(POIList.POIType.VILLAGE).is_equal(1)
	assert_int(POIList.POIType.ENEMY_SPAWN).is_equal(2)
	assert_int(POIList.POIType.LOOT_SPAWN).is_equal(3)


func test_poi_creation_has_position_type_and_metadata() -> void:
	var meta := {"name": "hut", "level": 1}
	var poi := POIList.POI.new(Vector2(3, 4), POIList.POIType.BUILDING, meta)
	assert_object(poi).is_not_null()
	assert_vector(poi.position).is_equal(Vector2(3, 4))
	assert_int(poi.type).is_equal(POIList.POIType.BUILDING)
	assert_str(poi.metadata["name"]).is_equal("hut")
	assert_int(poi.metadata["level"]).is_equal(1)


func test_poi_list_add_poi_stores_poi() -> void:
	var list := POIList.new()
	var poi := POIList.POI.new(Vector2(1, 1), POIList.POIType.VILLAGE, {})

	list.add_poi(poi)
	assert_int(list.pois.size()).is_equal(1)
	assert_object(list.pois[0]).is_equal(poi)


func test_poi_list_get_pois_by_type_filters_correctly() -> void:
	var list := POIList.new()
	list.add_poi(POIList.POI.new(Vector2(0, 0), POIList.POIType.BUILDING, {"id": "b1"}))
	list.add_poi(POIList.POI.new(Vector2(10, 0), POIList.POIType.VILLAGE, {"id": "v1"}))
	list.add_poi(POIList.POI.new(Vector2(20, 0), POIList.POIType.BUILDING, {"id": "b2"}))

	var buildings: Array = list.get_pois_by_type(POIList.POIType.BUILDING)
	assert_object(buildings).is_not_null()
	assert_int(buildings.size()).is_equal(2)
	assert_int(_count_pois_at(buildings, Vector2(0, 0))).is_equal(1)
	assert_int(_count_pois_at(buildings, Vector2(20, 0))).is_equal(1)
	assert_int(_count_pois_at(buildings, Vector2(10, 0))).is_equal(0)


func test_poi_list_get_pois_in_range_filters_by_distance() -> void:
	var list := POIList.new()
	list.add_poi(POIList.POI.new(Vector2(0, 0), POIList.POIType.LOOT_SPAWN, {}))
	list.add_poi(POIList.POI.new(Vector2(3, 4), POIList.POIType.LOOT_SPAWN, {})) # dist 5
	list.add_poi(POIList.POI.new(Vector2(100, 0), POIList.POIType.LOOT_SPAWN, {}))

	var center := Vector2.ZERO
	var radius := 5.0
	var in_range: Array = list.get_pois_in_range(center, radius)

	assert_object(in_range).is_not_null()
	assert_int(in_range.size()).is_equal(2)
	for poi in in_range:
		assert_float(poi.position.distance_to(center)).is_less_equal(radius)
	assert_int(_count_pois_at(in_range, Vector2(100, 0))).is_equal(0)


func test_pcg_config_has_thresholds() -> void:
	var config := PCGConfig.new()
	assert_object(config).is_not_null()

	# Threshold parameters (normalized 0..1)
	assert_float(config.zone_threshold_suburbs).is_greater_equal(0.0)
	assert_float(config.zone_threshold_suburbs).is_less_equal(1.0)
	assert_float(config.zone_threshold_urban).is_greater_equal(0.0)
	assert_float(config.zone_threshold_urban).is_less_equal(1.0)


func test_pcg_config_validate_returns_no_errors_on_defaults() -> void:
	var config := PCGConfig.new()
	var errors: Array = config.validate()
	assert_object(errors).is_not_null()
	assert_int(errors.size()).is_equal(0)


func test_pcg_config_validate_rejects_invalid_threshold_ranges() -> void:
	var config := PCGConfig.new()
	config.zone_threshold_suburbs = -0.1
	config.zone_threshold_urban = 1.5

	var errors: Array = config.validate()
	assert_int(errors.size()).is_greater(0)
	assert_str(str(errors)).contains("zone_threshold")


func test_pcg_config_validate_rejects_urban_threshold_not_greater_than_suburbs() -> void:
	var config := PCGConfig.new()
	config.zone_threshold_suburbs = 0.7
	config.zone_threshold_urban = 0.6

	var errors: Array = config.validate()
	assert_int(errors.size()).is_greater(0)
	assert_str(str(errors)).contains("zone_threshold_urban")


func test_pcg_result_integrates_all_data_structures() -> void:
	var config := PCGConfig.new()
	var graph := RoadGraph.new()

	# Build a small grid with zone + poi data to verify computed views
	var test_grid: Dictionary = {}
	var cell_urban := PCGCell.new()
	cell_urban.zone_type = ZoneMap.ZoneType.URBAN
	cell_urban.poi_type = POIList.POIType.BUILDING
	test_grid[Vector2i(0, 0)] = cell_urban

	var result := PCGResult.new(config, graph, null, null, test_grid)  # zones/pois params ignored; grid is source of truth
	assert_object(result).is_not_null()
	assert_object(result.config).is_equal(config)
	assert_object(result.road_graph).is_equal(graph)
	# Unified grid is the source of truth
	assert_object(result.grid).is_not_null()
	assert_int(result.grid.size()).is_equal(1)
	# Verify grid cell data directly instead of through computed views
	var cell: PCGCell = result.grid[Vector2i(0, 0)]
	assert_object(cell).is_not_null()
	assert_int(cell.zone_type).is_equal(ZoneMap.ZoneType.URBAN)
	assert_int(cell.poi_type).is_equal(POIList.POIType.BUILDING)


func _count_nodes_at(nodes: Array, at: Vector2) -> int:
	var count := 0
	for n in nodes:
		if n.position == at:
			count += 1
	return count


func _count_pois_at(pois: Array, at: Vector2) -> int:
	var count := 0
	for poi in pois:
		if poi.position == at:
			count += 1
	return count


# -- PCGCell tests ---------------------------------------------------------
func test_pcg_cell_defaults() -> void:
	var cell := PCGCell.new()
	assert_object(cell).is_not_null()
	assert_bool(cell.logic_type == TileAssetResolver.LogicType.ROAD).is_equal(false)
	assert_int(cell.zone_type).is_equal(0)
	assert_int(cell.poi_type).is_equal(-1)


func test_pcg_cell_helpers() -> void:
	var cell := PCGCell.new()
	# defaults
	assert_bool(cell.has_poi()).is_equal(false)
	assert_bool(cell.is_wilderness()).is_equal(true)
	assert_bool(cell.is_urban()).is_equal(false)

	# change to urban with poi
	cell.zone_type = ZoneMap.ZoneType.URBAN
	cell.poi_type = POIList.POIType.BUILDING
	assert_bool(cell.has_poi()).is_equal(true)
	assert_bool(cell.is_wilderness()).is_equal(false)
	assert_bool(cell.is_urban()).is_equal(true)


# -- PCGContext grid access tests -----------------------------------------
func test_pcg_context_grid_access() -> void:
	var ctx := PCGContext.new(12345)
	var pos := Vector2i(2, 3)

	# Initially no cell
	assert_bool(ctx.has_cell(pos)).is_equal(false)
	assert_object(ctx.get_cell(pos)).is_null()

	# get_or_create should create and return a PCGCell
	var created := ctx.get_or_create_cell(pos)
	assert_object(created).is_not_null()
	assert_bool(created is PCGCell).is_true()
	assert_bool(ctx.has_cell(pos)).is_equal(true)
	assert_object(ctx.get_cell(pos)).is_equal(created)

	# set_cell should replace
	var replacement := PCGCell.new()
	replacement.logic_type = TileAssetResolver.LogicType.ROAD
	ctx.set_cell(pos, replacement)
	var fetched := ctx.get_cell(pos)
	assert_object(fetched).is_equal(replacement)
	assert_bool(fetched.logic_type == TileAssetResolver.LogicType.ROAD).is_equal(true)
