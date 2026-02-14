# tests/pcg/test_village_zone_placement.gd
extends GdUnitTestSuite
## Integration test to verify that VILLAGE POIs are placed in SUBURBS zone.
## This test addresses GitHub issue #91: campfires spawning in urban area instead of suburbs.

const Service_PCG := preload("res://scripts/services/impl/service_pcg.gd")
const PCGConfig := preload("res://scripts/pcg/data/pcg_config.gd")
const PCGResult := preload("res://scripts/pcg/data/pcg_result.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")
const POIList := preload("res://scripts/pcg/data/poi_list.gd")
const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")


func test_village_pois_have_suburbs_zone_metadata() -> void:
	# Run the full PCG pipeline
	var service := Service_PCG.new()
	var config := PCGConfig.new()
	config.pcg_seed = 12345
	
	var result: PCGResult = service.generate(config)
	
	# Get all VILLAGE POIs
	var village_pois: Array = result.poi_list.get_pois_by_type(POIList.POIType.VILLAGE)
	
	assert_int(village_pois.size()).is_greater(0)
	
	# Verify each VILLAGE POI has SUBURBS zone in metadata
	for poi: POIList.POI in village_pois:
		# Check zone from metadata (set during POI creation)
		assert_bool(poi.metadata.has("zone")).is_true()
		var zone_from_metadata: int = int(poi.metadata["zone"])
		assert_int(zone_from_metadata).is_equal(ZoneMap.ZoneType.SUBURBS)


func test_village_pois_not_in_urban_zone() -> void:
	# Run the full PCG pipeline with different seeds
	var service := Service_PCG.new()
	
	for seed_val: int in [0, 123, 456, 789, 12345]:
		var config := PCGConfig.new()
		config.pcg_seed = seed_val
		
		var result: PCGResult = service.generate(config)
		var village_pois: Array = result.poi_list.get_pois_by_type(POIList.POIType.VILLAGE)
		
		for poi: POIList.POI in village_pois:
			# Check zone from metadata (set during POI creation)
			assert_bool(poi.metadata.has("zone")).is_true()
			var zone_from_metadata: int = int(poi.metadata["zone"])
			# VILLAGE should NOT be in URBAN zone
			assert_int(zone_from_metadata).is_not_equal(ZoneMap.ZoneType.URBAN)
