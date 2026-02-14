# scripts/services/impl/service_pcg.gd
class_name Service_PCG
extends ServiceBase
## Service wrapper for PCG pipeline.

var last_result: PCGResult


func generate(config: PCGConfig) -> PCGResult:
	var effective_config: PCGConfig = config
	if effective_config == null:
		effective_config = PCGConfig.new()

	var pipeline := PCGPipeline.new()
	# Add phases using centralized configuration
	for phase: PCGPhase in PCGPhaseConfig.create_phases():
		pipeline.add_phase(phase)

	var result: PCGResult = pipeline.generate(effective_config)

	_ensure_minimum_pois(result)

	last_result = result

	return result


func get_zone_map() -> ZoneMap:
	if last_result == null:
		return null
	return last_result.zone_map


func get_road_cells() -> Dictionary:
	if last_result == null:
		return {}
	return last_result.road_cells


func find_nearest_village_poi(center: Vector2 = Vector2.ZERO) -> Vector2:
	if last_result == null:
		push_warning("[Service_PCG] No PCG result available, using default position")
		return Vector2(500, 500)

	var poi_list := last_result.poi_list
	var village_pois := poi_list.get_pois_by_type(POIList.POIType.VILLAGE)

	if village_pois.is_empty():
		push_warning("[Service_PCG] No VILLAGE POIs found, using default position")
		return Vector2(500, 500)

	var closest_poi: POIList.POI = null
	var closest_dist := INF

	for poi: POIList.POI in village_pois:
		var dist := poi.position.distance_to(center)
		if dist < closest_dist:
			closest_dist = dist
			closest_poi = poi

	return closest_poi.position


# --------------------------------------------------------------------
# Internals
# --------------------------------------------------------------------
func _ensure_minimum_pois(result: PCGResult) -> void:
	if result == null:
		return

	# Check if we have any POIs in the grid
	var has_pois := false
	if result.grid != null and result.grid is Dictionary:
		for pos in result.grid.keys():
			var cell = result.grid[pos]
			if cell is PCGCell and cell.has_poi():
				has_pois = true
				break

	# Also check legacy poi_list if grid has no POIs
	if not has_pois and result.poi_list != null and not result.poi_list.pois.is_empty():
		return

	if has_pois:
		return

	# Deterministic: derive from seed if available, else fixed fallback.
	var seed_value: int = 0
	if result.config != null:
		seed_value = result.config.pcg_seed

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Choose a stable grid cell and place one BUILDING POI.
	var grid_size: int = 100
	if result.config != null:
		var gs: Variant = result.config.get("grid_size")
		if gs != null:
			grid_size = int(gs)

	var half_size: int = int(grid_size / 2)
	var start: int = -half_size
	var end: int = grid_size - half_size - 1

	var x: int = rng.randi_range(start, end)
	var y: int = rng.randi_range(start, end)
	var pos := Vector2i(x, y)

	# Write POI to grid cell
	if result.grid != null and result.grid is Dictionary:
		var cell: PCGCell
		if result.grid.has(pos):
			cell = result.grid[pos]
		if cell == null:
			cell = PCGCell.new()
			result.grid[pos] = cell
		cell.poi_type = POIList.POIType.BUILDING
		cell.logic_type = TileAssetResolver.LogicType.BUILDING
