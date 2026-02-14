# tests/pcg/test_pipeline_base.gd
extends GdUnitTestSuite
## TDD (RED): Contract tests for PCG pipeline base classes.
## These tests define the intended API/behavior for PCGPhase and PCGContext.


# NOTE: These preloads are intentional for RED phase.
# The referenced scripts may not exist yet and will be implemented next.
const PCGPhase := preload("res://scripts/pcg/pipeline/pcg_phase.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")

const RoadGraph := preload("res://scripts/pcg/data/road_graph.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")
const POIList := preload("res://scripts/pcg/data/poi_list.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")


class _TestPhaseOverride extends PCGPhase:
	var executed: bool = false
	var received_config: PCGConfig
	var received_context: PCGContext

	func execute(config: PCGConfig, context: PCGContext) -> void:
		executed = true
		received_config = config
		received_context = context
		# Demonstrate phase-driven mutation of context.
		context.road_graph = RoadGraph.new()
		# zone_map/poi_list are now computed views from grid; mutate grid instead.
		var cell := PCGCell.new()
		cell.zone_type = ZoneMap.ZoneType.URBAN
		cell.poi_type = POIList.POIType.BUILDING
		context.grid[Vector2i(0, 0)] = cell


func test_pcg_phase_extends_ref_counted() -> void:
	var phase := PCGPhase.new()
	assert_object(phase).is_not_null()
	assert_bool(phase is RefCounted).is_true()


func test_pcg_phase_has_virtual_execute_method_with_two_arguments() -> void:
	var phase := PCGPhase.new()
	assert_bool(phase.has_method("execute")).is_true()
	# Contract: PCGPhase.execute(config, context)
	assert_int(Callable(phase, "execute").get_argument_count()).is_equal(2)


func test_pcg_phase_can_be_subclassed_and_execute_overridden() -> void:
	var phase := _TestPhaseOverride.new()
	var config := PCGConfig.new()
	var context := PCGContext.new(123)

	phase.execute(config, context)

	assert_bool(phase.executed).is_true()
	assert_object(phase.received_config).is_equal(config)
	assert_object(phase.received_context).is_equal(context)
	assert_bool(phase is PCGPhase).is_true()


func test_pcg_context_extends_ref_counted() -> void:
	var context := PCGContext.new(1)
	assert_object(context).is_not_null()
	assert_bool(context is RefCounted).is_true()


func test_pcg_context_exposes_mutable_pipeline_state_properties() -> void:
	var context := PCGContext.new(1)
	assert_object(context).is_not_null()

	# Contract: these properties exist and are accessible.
	assert_object(context.road_graph).is_not_null()
	assert_object(context.grid).is_not_null()
	assert_int(context.grid.size()).is_equal(0)
	assert_object(context.rng).is_not_null()

	# road_graph and grid are directly mutable
	var graph := RoadGraph.new()
	var grid := {}
	context.road_graph = graph
	context.grid = grid

	assert_object(context.road_graph).is_equal(graph)
	assert_object(context.grid).is_equal(grid)

	# Populate grid and verify data is accessible
	var cell := PCGCell.new()
	cell.zone_type = ZoneMap.ZoneType.URBAN
	cell.poi_type = POIList.POIType.BUILDING
	context.grid[Vector2i(0, 0)] = cell
	assert_int(context.grid.size()).is_equal(1)
	assert_int(context.grid[Vector2i(0, 0)].zone_type).is_equal(ZoneMap.ZoneType.URBAN)


func test_pcg_context_rng_is_seeded_deterministically() -> void:
	var seed := 424242
	var a := PCGContext.new(seed)
	var b := PCGContext.new(seed)

	# Contract: rng seed is set from constructor seed.
	assert_int(a.rng.seed).is_equal(seed)
	assert_int(b.rng.seed).is_equal(seed)

	# Contract: seeded contexts produce identical sequences.
	assert_int(a.rng.randi()).is_equal(b.rng.randi())
	assert_int(a.rng.randi()).is_equal(b.rng.randi())
	assert_int(a.rng.randi()).is_equal(b.rng.randi())


func test_pcg_context_provides_seeded_random_helper_methods() -> void:
	var context := PCGContext.new(1337)

	# Contract: helper methods exist for deterministic random access.
	assert_bool(context.has_method("randi")).is_true()
	assert_bool(context.has_method("randf")).is_true()
	assert_bool(context.has_method("randi_range")).is_true()
	assert_bool(context.has_method("randf_range")).is_true()

	assert_int(Callable(context, "randi").get_argument_count()).is_equal(0)
	assert_int(Callable(context, "randf").get_argument_count()).is_equal(0)
	assert_int(Callable(context, "randi_range").get_argument_count()).is_equal(2)
	assert_int(Callable(context, "randf_range").get_argument_count()).is_equal(2)

	var i: int = context.randi()
	var f: float = context.randf()
	var ir: int = context.randi_range(10, 12)
	var fr: float = context.randf_range(-1.0, 1.0)

	# Basic sanity ranges.
	assert_bool(i is int).is_true()
	assert_float(f).is_greater_equal(0.0)
	assert_float(f).is_less(1.0)
	assert_int(ir).is_greater_equal(10)
	assert_int(ir).is_less_equal(12)
	assert_float(fr).is_greater_equal(-1.0)
	assert_float(fr).is_less_equal(1.0)


func test_pcg_context_can_be_mutated_by_phase_execution() -> void:
	var phase := _TestPhaseOverride.new()
	var config := PCGConfig.new()
	var context := PCGContext.new(7)

	# Precondition: objects start non-null but grid is empty.
	assert_object(context.road_graph).is_not_null()
	assert_object(context.grid).is_not_null()
	assert_int(context.grid.size()).is_equal(0)

	phase.execute(config, context)

	# Postcondition: phase mutated the grid (added a cell).
	assert_object(context.road_graph).is_not_null()
	assert_object(context.grid).is_not_null()
	assert_int(context.grid.size()).is_greater(0)
	# Verify grid cell content directly
	var cell: PCGCell = context.grid[Vector2i(0, 0)]
	assert_object(cell).is_not_null()
	assert_int(cell.zone_type).is_equal(ZoneMap.ZoneType.URBAN)
	assert_int(cell.poi_type).is_equal(POIList.POIType.BUILDING)
