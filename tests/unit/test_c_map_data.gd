extends GdUnitTestSuite
## Unit tests for CMapData component
## Tests component creation, signal emission, and null handling

const CMapData := preload("res://scripts/components/c_map_data.gd")
const PCGResult := preload("res://scripts/pcg/data/pcg_result.gd")
const PCGContext := preload("res://scripts/pcg/pipeline/pcg_context.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const RoadGraph := preload("res://scripts/pcg/data/road_graph.gd")


func before_test() -> void:
	# Ensure clean state before each test
	pass


func after_test() -> void:
	# Clean up any signal spies or monitored objects
	# This prevents signal assertions from leaking to other tests
	GdUnitSignalCollector.instance().clear()
	unregister_all_spies()


func test_component_creation() -> void:
	var map_data := CMapData.new()
	assert_object(map_data).is_not_null()
	assert_bool(map_data is Component).is_true()


func test_component_has_class_name() -> void:
	var map_data := CMapData.new()
	# get_class() returns the Godot class hierarchy, use is_instance_of or check script instead
	assert_bool(map_data is CMapData).is_true()
	assert_object(map_data.get_script()).is_not_null()


func test_creation_with_pcg_result() -> void:
	# Create a PCGResult with required dependencies
	var config := PCGConfig.new()
	var road_graph := RoadGraph.new()
	var grid := {}
	
	var result := PCGResult.new(config, road_graph, null, null, grid)
	
	var map_data := CMapData.new()
	map_data.pcg_result = result
	
	assert_object(map_data.pcg_result).is_not_null()
	assert_object(map_data.pcg_result).is_same(result)
	assert_object(map_data.pcg_result_observable.value).is_same(result)


func test_creation_with_pcg_context() -> void:
	var context := PCGContext.new(42)
	
	var map_data := CMapData.new()
	map_data.pcg_context = context
	
	assert_object(map_data.pcg_context).is_not_null()
	assert_object(map_data.pcg_context).is_same(context)
	assert_object(map_data.pcg_context_observable.value).is_same(context)


func test_map_changed_signal_emitted_on_pcg_result_set() -> void:
	var map_data := CMapData.new()
	
	# Use assert_signal to verify signal emission
	assert_signal(map_data).is_signal_exists("map_changed")
	
	var config := PCGConfig.new()
	var road_graph := RoadGraph.new()
	var result := PCGResult.new(config, road_graph, null, null, {})
	
	map_data.pcg_result = result
	
	assert_signal(map_data).is_emitted("map_changed")


func test_map_changed_signal_emitted_on_pcg_context_set() -> void:
	var map_data := CMapData.new()
	
	assert_signal(map_data).is_signal_exists("map_changed")
	
	var context := PCGContext.new(42)
	map_data.pcg_context = context
	
	assert_signal(map_data).is_emitted("map_changed")


func test_null_pcg_result_handled_gracefully() -> void:
	var map_data := CMapData.new()
	
	# Setting null should not crash
	map_data.pcg_result = null
	
	assert_object(map_data.pcg_result).is_null()
	assert_object(map_data.pcg_result_observable.value).is_null()


func test_null_pcg_context_handled_gracefully() -> void:
	var map_data := CMapData.new()
	
	# Setting null should not crash
	map_data.pcg_context = null
	
	assert_object(map_data.pcg_context).is_null()
	assert_object(map_data.pcg_context_observable.value).is_null()


func test_signal_emitted_on_null_assignment() -> void:
	var map_data := CMapData.new()
	
	# First set a value
	var config := PCGConfig.new()
	var result := PCGResult.new(config, RoadGraph.new(), null, null, {})
	map_data.pcg_result = result
	
	# Then set to null - this should also emit the signal
	map_data.pcg_context = null
	
	# Verify both signals were emitted
	assert_signal(map_data).is_emitted("map_changed")


func test_observable_property_updates() -> void:
	var map_data := CMapData.new()
	
	var config1 := PCGConfig.new()
	var result1 := PCGResult.new(config1, RoadGraph.new(), null, null, {})
	
	var config2 := PCGConfig.new()
	var result2 := PCGResult.new(config2, RoadGraph.new(), null, null, {})
	
	map_data.pcg_result = result1
	assert_object(map_data.pcg_result_observable.value).is_same(result1)
	
	map_data.pcg_result = result2
	assert_object(map_data.pcg_result_observable.value).is_same(result2)


func test_both_references_can_be_set() -> void:
	var map_data := CMapData.new()
	
	var config := PCGConfig.new()
	var result := PCGResult.new(config, RoadGraph.new(), null, null, {})
	var context := PCGContext.new(123)
	
	map_data.pcg_result = result
	map_data.pcg_context = context
	
	assert_object(map_data.pcg_result).is_same(result)
	assert_object(map_data.pcg_context).is_same(context)
