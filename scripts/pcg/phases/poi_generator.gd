
class_name POIGenerator
extends PCGPhase


func execute(config: PCGConfig, context: PCGContext) -> void:
	# Unified grid is now the single source of truth for POI data.

	var tile_size: int = _get_int(config, "tile_size", 32)
	var attempts_per_poi: int = _get_int(config, "placement_attempts_per_poi", 200)
	var min_spacing_map: Dictionary = _get_min_spacing_map(config)
	var cross_spacing_map: Dictionary = _get_cross_spacing_map(config)
	var grid_size: int = config.grid_size

	# Precompute candidate cells per zone (deterministic, no RNG).
	# Read zone info from the unified grid via context.get_cell.
	var urban_cells: Array[Vector2i] = _cells_for_zone_type(context, ZoneMap.ZoneType.URBAN, grid_size)
	var suburbs_cells: Array[Vector2i] = _cells_for_zone_type(context, ZoneMap.ZoneType.SUBURBS, grid_size)
	var wilderness_cells: Array[Vector2i] = _cells_for_zone_type(context, ZoneMap.ZoneType.WILDERNESS, grid_size)

	# BUILDING in URBAN then SUBURBS (ordering matters for determinism).
	_place_pois(
		context,
		tile_size,
		attempts_per_poi,
		min_spacing_map,
		cross_spacing_map,
		POIList.POIType.BUILDING,
		urban_cells,
		_get_int(config, "building_count_urban", 0)
	)
	_place_pois(
		context,
		tile_size,
		attempts_per_poi,
		min_spacing_map,
		cross_spacing_map,
		POIList.POIType.BUILDING,
		suburbs_cells,
		_get_int(config, "building_count_suburbs", 0)
	)

	# VILLAGE in SUBURBS.
	_place_pois(
		context,
		tile_size,
		attempts_per_poi,
		min_spacing_map,
		cross_spacing_map,
		POIList.POIType.VILLAGE,
		suburbs_cells,
		_get_int(config, "village_count_suburbs", 0)
	)

	# ENEMY_SPAWN in WILDERNESS.
	_place_pois(
		context,
		tile_size,
		attempts_per_poi,
		min_spacing_map,
		cross_spacing_map,
		POIList.POIType.ENEMY_SPAWN,
		wilderness_cells,
		_get_int(config, "enemy_spawn_count_wilderness", 0)
	)


func _place_pois(
	context: PCGContext,
	tile_size: int,
	attempts_per_poi: int,
	min_spacing_map: Dictionary,
	cross_spacing_map: Dictionary,
	poi_type: int,
	candidates: Array[Vector2i],
	target_count: int
) -> void:
	if target_count <= 0:
		return
	if candidates.is_empty():
		return

	var min_cells: int = int(min_spacing_map.get(poi_type, 0))

	# Build existing POIs list from unified grid for spacing checks (grid coordinates).
	var existing_same_type: Array[Vector2i] = _get_poi_positions_by_type_from_grid(context, poi_type)
	var placed_positions: Array[Vector2i] = []

	# Get cross-type spacing constraints for this POI type
	var cross_type_constraints: Dictionary = _get_cross_type_constraints(cross_spacing_map, poi_type)
	var existing_cross_types: Dictionary = {}
	for other_type: int in cross_type_constraints.keys():
		existing_cross_types[other_type] = _get_poi_positions_by_type_from_grid(context, other_type)

	var max_attempts: int = target_count * max(1, attempts_per_poi)
	var placed: int = 0

	for _attempt: int in range(max_attempts):
		if placed >= target_count:
			break

		var cell: Vector2i = candidates[context.rng.randi_range(0, candidates.size() - 1)]

		# Constraint: never place on road cells. Check unified grid.
		var grid_cell = context.get_cell(cell)
		if grid_cell != null:
			if grid_cell.is_road():
				continue

		# Constraint: minimum spacing against same-type POIs (using grid coordinates).
		if min_cells > 0 and (_is_too_close_grid(cell, existing_same_type, min_cells) or _is_too_close_grid(cell, placed_positions, min_cells)):
			continue

		# Constraint: minimum spacing against cross-type POIs (e.g., VILLAGE vs ENEMY_SPAWN)
		var cross_type_violated: bool = false
		for other_type: int in cross_type_constraints.keys():
			var cross_min_cells: int = cross_type_constraints[other_type]
			var cross_positions: Array[Vector2i] = existing_cross_types.get(other_type, [])
			if cross_positions.size() > 0 and _is_too_close_grid(cell, cross_positions, cross_min_cells):
				cross_type_violated = true
				break
		if cross_type_violated:
			continue

		# Write POI data to unified grid only - legacy view generated on demand.
		var target_cell = context.get_or_create_cell(cell)
		if target_cell != null:
			target_cell.poi_type = poi_type
			# Zone type should already be set in grid from previous phases

		existing_same_type.append(cell)
		placed_positions.append(cell)
		placed += 1


func _cells_for_zone_type(context: PCGContext, zone_type: int, grid_size: int) -> Array[Vector2i]:
	"""Get all cells of a specific zone type from the unified grid."""
	var result: Array[Vector2i] = []
	if context == null or context.grid == null:
		return result

	var half_size: int = int(grid_size / 2)
	var start: int = -half_size
	var end: int = grid_size - half_size

	for y: int in range(start, end):
		for x: int in range(start, end):
			var cell := Vector2i(x, y)
			var c = context.get_cell(cell)
			if c != null and c.zone_type == zone_type:
				result.append(cell)

	return result


func _get_poi_positions_by_type_from_grid(context: PCGContext, poi_type: int) -> Array[Vector2i]:
	"""Build list of POI grid positions from unified grid for spacing checks."""
	var result: Array[Vector2i] = []
	if context == null or context.grid == null:
		return result
	
	for pos: Variant in context.grid.keys():
		if pos is Vector2i:
			var grid_cell = context.grid[pos]
			if grid_cell is PCGCell and grid_cell.poi_type == poi_type:
				result.append(pos)
	
	return result


func _get_min_spacing_map(config: PCGConfig) -> Dictionary:
	var v: Variant = config.get("min_spacing_cells_by_type")
	if v is Dictionary:
		return v as Dictionary
	return {}


func _get_cross_spacing_map(config: PCGConfig) -> Dictionary:
	var v: Variant = config.get("min_spacing_cross_type")
	if v is Dictionary:
		return v as Dictionary
	return {}


func _get_cross_type_constraints(cross_spacing_map: Dictionary, poi_type: int) -> Dictionary:
	"""Get cross-type spacing constraints for a given POI type.
	Returns a dictionary mapping other POI types to their minimum spacing."""
	var result: Dictionary = {}
	for key: Variant in cross_spacing_map.keys():
		var key_str: String = str(key)
		var parts: PackedStringArray = key_str.split(",")
		if parts.size() != 2:
			continue
		var type_a: int = parts[0].to_int()
		var type_b: int = parts[1].to_int()
		var spacing: int = int(cross_spacing_map[key])
		
		# Check if this POI type is part of the constraint pair
		if type_a == poi_type:
			result[type_b] = spacing
		elif type_b == poi_type:
			result[type_a] = spacing
	
	return result


func _is_too_close_grid(new_pos: Vector2i, existing: Array[Vector2i], min_cells: int) -> bool:
	"""Check if new position is too close to any existing position (grid coordinates)."""
	for pos in existing:
		if pos.distance_to(new_pos) < float(min_cells):
			return true
	return false


func _is_too_close(new_pos: Vector2, existing: Array, min_world_dist: float) -> bool:
	for v in existing:
		# Support both legacy POI objects and plain Vector2 positions used in tests.
		if v is POIList.POI:
			var poi = v as POIList.POI
			if poi.position.distance_to(new_pos) < min_world_dist:
				return true
		elif v is Vector2:
			var pos := v as Vector2
			if pos.distance_to(new_pos) < min_world_dist:
				return true
	return false


func _get_int(obj: Object, property_name: String, default_value: int) -> int:
	if obj == null:
		return default_value
	var v: Variant = obj.get(property_name)
	if v == null:
		return default_value
	if v is int:
		return int(v)
	return default_value
