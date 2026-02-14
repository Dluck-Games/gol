# tests/pcg/test_pipeline.gd
extends GdUnitTestSuite
## TDD (RED): Contract tests for PCG pipeline coordinator.
## These tests define the intended API/behavior for PCGPipeline (no Node dependencies).

# NOTE: These preloads are intentional for RED phase.
# The referenced script may not exist yet and will be implemented next.
const PCGPipeline := preload("res://scripts/pcg/pipeline/pcg_pipeline.gd")

const PCGPhase := preload("res://scripts/pcg/pipeline/pcg_phase.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")

const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const PCGResult := preload("res://scripts/pcg/data/pcg_result.gd")
const RoadGraph := preload("res://scripts/pcg/data/road_graph.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")
const POIList := preload("res://scripts/pcg/data/poi_list.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")
const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")


class _TestConfig extends PCGConfig:
	## Contract for PCGPipeline: config exposes a seed used to seed PCGContext RNG.

	func _init(p_seed: int = 0) -> void:
		pcg_seed = p_seed


class _PhaseRecordOrder extends PCGPhase:
	var id: String
	var log: Array[String]

	func _init(p_id: String, p_log: Array[String]) -> void:
		id = p_id
		log = p_log

	func execute(config: PCGConfig, context: PCGContext) -> void:
		log.append(id)


class _PhaseCaptureArgs extends PCGPhase:
	var received_config: PCGConfig
	var received_context: PCGContext

	func execute(config: PCGConfig, context: PCGContext) -> void:
		received_config = config
		received_context = context


class _PhaseSeededRoadGraph extends PCGPhase:
	## Writes deterministic nodes using context RNG
	var node_count: int

	func _init(p_node_count: int) -> void:
		node_count = p_node_count

	func execute(config: PCGConfig, context: PCGContext) -> void:
		for i in node_count:
			var x := context.randi_range(-1000, 1000)
			var y := context.randi_range(-1000, 1000)
			context.road_graph.add_node(RoadGraph.RoadNode.new(Vector2(x, y), 1.0, "TEST"))
			# Mirror road existence into unified grid at integer cell
			var pos_i: Vector2i = Vector2i(x, y)
			context.get_or_create_cell(pos_i).logic_type = TileAssetResolver.LogicType.ROAD


class _PhaseReadRoadNodeCount extends PCGPhase:
	var road_node_count: int = -1

	func execute(config: PCGConfig, context: PCGContext) -> void:
		road_node_count = context.road_graph.nodes.size()


class _PhaseWriteZoneFromRoadNodeCount extends PCGPhase:
	func execute(config: PCGConfig, context: PCGContext) -> void:
		var zone := ZoneMap.ZoneType.WILDERNESS
		if context.road_graph.nodes.size() > 0:
			zone = ZoneMap.ZoneType.SUBURBS
		# Write zone into unified grid (zone_map is a computed view)
		context.get_or_create_cell(Vector2i(0, 0)).zone_type = zone


class _PhaseWritePoiFromZone extends PCGPhase:
	func execute(config: PCGConfig, context: PCGContext) -> void:
		var cell := context.get_cell(Vector2i(0, 0))
		var zone: int = cell.zone_type if cell != null else ZoneMap.ZoneType.WILDERNESS
		# Write POI into unified grid (poi_list is a computed view)
		context.get_or_create_cell(Vector2i(0, 0)).poi_type = POIList.POIType.BUILDING
		context.get_or_create_cell(Vector2i(0, 0)).data["zone"] = zone


func test_pipeline_can_add_phases_with_add_phase_and_appends_to_phases_array() -> void:
	var pipeline := PCGPipeline.new()
	assert_object(pipeline).is_not_null()

	# Contract: pipeline exposes a phases array.
	assert_object(pipeline.phases).is_not_null()
	var before := pipeline.phases.size()

	var phase := _PhaseCaptureArgs.new()
	pipeline.add_phase(phase)

	assert_int(pipeline.phases.size()).is_equal(before + 1)
	assert_object(pipeline.phases[pipeline.phases.size() - 1]).is_equal(phase)


func test_pipeline_generate_returns_pcg_result_with_config_and_all_data_structures() -> void:
	var pipeline := PCGPipeline.new()
	var config := _TestConfig.new(1)
	# Note: Pipeline has no phases, so grid will be empty
	var result := pipeline.generate(config)

	assert_object(result).is_not_null()
	assert_bool(result is PCGResult).is_true()

	# Contract: result contains the exact config instance.
	assert_object(result.config).is_equal(config)

	# Contract: result.road_graph exists (still directly stored, not grid-derived).
	assert_object(result.road_graph).is_not_null()
	assert_bool(result.road_graph is RoadGraph).is_true()

	# Contract: result.grid (unified) is present (may be empty if no phases write to it).
	# zone_map and poi_list are computed views from grid.
	assert_object(result.grid).is_not_null()
	assert_bool(result.grid is Dictionary).is_true()
	assert_int(result.grid.size()).is_greater_equal(0)  # Empty pipeline = empty grid


func test_pipeline_executes_phases_in_order() -> void:
	var pipeline := PCGPipeline.new()
	var config := _TestConfig.new(2)

	var log: Array[String] = []
	pipeline.add_phase(_PhaseRecordOrder.new("A", log))
	pipeline.add_phase(_PhaseRecordOrder.new("B", log))
	pipeline.add_phase(_PhaseRecordOrder.new("C", log))

	pipeline.generate(config)

	assert_int(log.size()).is_equal(3)
	assert_str(log[0]).is_equal("A")
	assert_str(log[1]).is_equal("B")
	assert_str(log[2]).is_equal("C")


func test_pipeline_propagates_same_context_instance_and_mutations_through_phases() -> void:
	var pipeline := PCGPipeline.new()
	var config := _TestConfig.new(3)

	var capture_a := _PhaseCaptureArgs.new()
	var capture_b := _PhaseCaptureArgs.new()
	var read_count := _PhaseReadRoadNodeCount.new()

	# Phase 1 captures (config, context).
	pipeline.add_phase(capture_a)
	# Phase 2 mutates road_graph deterministically.
	pipeline.add_phase(_PhaseSeededRoadGraph.new(4))
	# Phase 3 reads phase 2 mutation.
	pipeline.add_phase(read_count)
	# Phase 4 mutates zone_map based on road_graph contents.
	pipeline.add_phase(_PhaseWriteZoneFromRoadNodeCount.new())
	# Phase 5 mutates poi_list based on zone_map.
	pipeline.add_phase(_PhaseWritePoiFromZone.new())
	# Phase 6 captures again to verify same context instance used throughout.
	pipeline.add_phase(capture_b)

	var result := pipeline.generate(config)

	# Contract: pipeline uses a single PCGContext instance for the whole run.
	assert_object(capture_a.received_context).is_not_null()
	assert_object(capture_b.received_context).is_not_null()
	assert_object(capture_a.received_context).is_equal(capture_b.received_context)

	# Contract: config is forwarded unchanged.
	assert_object(capture_a.received_config).is_equal(config)
	assert_object(capture_b.received_config).is_equal(config)

	# Contract: mutations are visible to later phases and reflected in result.
	assert_int(read_count.road_node_count).is_equal(4)
	assert_int(result.road_graph.nodes.size()).is_equal(4)

	# Primary: unified grid must reflect zone/poi mutations at (0,0)
	assert_bool(result.grid.has(Vector2i(0, 0))).is_true()
	var cell00: PCGCell = result.grid[Vector2i(0, 0)]
	assert_int(cell00.zone_type).is_equal(ZoneMap.ZoneType.SUBURBS)
	assert_int(cell00.poi_type).is_equal(POIList.POIType.BUILDING)
	assert_int(cell00.data["zone"]).is_equal(ZoneMap.ZoneType.SUBURBS)


func test_pipeline_is_deterministic_for_same_seed_and_varies_for_different_seed() -> void:
	var pipeline := PCGPipeline.new()
	pipeline.add_phase(_PhaseSeededRoadGraph.new(5))

	var result_a := pipeline.generate(_TestConfig.new(4242))
	var result_b := pipeline.generate(_TestConfig.new(4242))
	var result_c := pipeline.generate(_TestConfig.new(9001))

	_assert_road_graphs_equal(result_a.road_graph, result_b.road_graph)
	_assert_road_graphs_not_equal(result_a.road_graph, result_c.road_graph)

	# Grid determinism: unified grid must be identical for same seed
	assert_int(result_a.grid.size()).is_equal(result_b.grid.size())
	for pos: Vector2i in result_a.grid.keys():
		assert_bool(result_b.grid.has(pos)).is_true()
		var cell_a: PCGCell = result_a.grid[pos]
		var cell_b: PCGCell = result_b.grid[pos]
		assert_int(cell_a.zone_type).is_equal(cell_b.zone_type)
		assert_bool(cell_a.logic_type == TileAssetResolver.LogicType.ROAD).is_equal(cell_b.logic_type == TileAssetResolver.LogicType.ROAD)
		assert_int(cell_a.poi_type).is_equal(cell_b.poi_type)


func _assert_road_graphs_equal(a: RoadGraph, b: RoadGraph) -> void:
	assert_int(a.nodes.size()).is_equal(b.nodes.size())
	for i in a.nodes.size():
		assert_vector(a.nodes[i].position).is_equal(b.nodes[i].position)
		assert_float(a.nodes[i].width).is_equal(b.nodes[i].width)
		assert_str(a.nodes[i].type).is_equal(b.nodes[i].type)


func _assert_road_graphs_not_equal(a: RoadGraph, b: RoadGraph) -> void:
	# Minimal contract: different seeds should yield some difference in deterministic outputs.
	if a.nodes.size() != b.nodes.size():
		assert_bool(true).is_true()
		return

	if a.nodes.size() == 0:
		fail("Expected road graph to contain nodes")
		return

	assert_bool(a.nodes[0].position != b.nodes[0].position).is_true()
