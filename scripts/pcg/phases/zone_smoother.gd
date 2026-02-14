class_name ZoneSmoother
extends PCGPhase

const _MOORE_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


func execute(config: PCGConfig, context: PCGContext) -> void:
	if context == null or context.grid == null:
		return

	var iterations: int = _get_iterations(config)
	if iterations <= 0:
		return
	
	var grid_size: int = config.grid_size

	var half_size: int = int(grid_size / 2)
	var start: int = -half_size
	var end: int = grid_size - half_size

	# Build road_cells view from unified grid
	var road_cells: Dictionary[Vector2i, bool] = _build_road_cells_from_grid(context)

	for _i: int in range(iterations):
		_smooth_once(context, road_cells, grid_size, start, end)


func _build_road_cells_from_grid(context: PCGContext) -> Dictionary[Vector2i, bool]:
	"""Build road_cells dictionary from unified grid."""
	var road_cells: Dictionary[Vector2i, bool] = {}
	if context == null or context.grid == null:
		return road_cells
	
	for pos: Variant in context.grid.keys():
		if pos is Vector2i:
			var grid_cell = context.grid[pos]
			if grid_cell is PCGCell and grid_cell.is_road():
				road_cells[pos] = true
	
	return road_cells


func _smooth_once(context: PCGContext, road_cells: Dictionary[Vector2i, bool], grid_size: int, start: int, end: int) -> void:
	if road_cells == null:
		road_cells = {}

	# Enforce road preservation: roads are always URBAN.
	for road_cell: Vector2i in road_cells.keys():
		if _in_bounds(road_cell, grid_size):
			context.get_or_create_cell(road_cell).zone_type = ZoneMap.ZoneType.URBAN

	var new_zones: Dictionary[Vector2i, int] = {}

	for y: int in range(start, end):
		for x: int in range(start, end):
			var cell := Vector2i(x, y)

			# Road cells never change.
			if (context.has_cell(cell) and context.get_cell(cell).is_road()) or road_cells.has(cell):
				continue

			var counts: Dictionary[int, int] = _count_neighbors(context, cell, grid_size)
			var majority: int = _find_majority(counts)

			# Read current zone from unified grid.
			var current: int = ZoneMap.ZoneType.WILDERNESS
			var ccell := context.get_cell(cell)
			if ccell != null:
				current = int(ccell.zone_type)

			if majority != current:
				new_zones[cell] = majority

	for cell: Vector2i in new_zones.keys():
		# Write to unified grid only - legacy view generated on demand.
		context.get_or_create_cell(cell).zone_type = int(new_zones[cell])


func _count_neighbors(context: PCGContext, cell: Vector2i, grid_size: int) -> Dictionary[int, int]:
	var counts: Dictionary[int, int] = {
		ZoneMap.ZoneType.WILDERNESS: 0,
		ZoneMap.ZoneType.SUBURBS: 0,
		ZoneMap.ZoneType.URBAN: 0,
	}

	for off: Vector2i in _MOORE_8:
		var n: Vector2i = cell + off
		if not _in_bounds(n, grid_size):
			continue

		# Read from unified grid.
		var z: int = ZoneMap.ZoneType.WILDERNESS
		var ccell := context.get_cell(n)
		if ccell != null:
			z = int(ccell.zone_type)

		counts[z] = int(counts.get(z, 0)) + 1

	return counts


func _find_majority(counts: Dictionary[int, int]) -> int:
	# Deterministic tie-break: WILDERNESS, then SUBURBS, then URBAN.
	var best_zone: int = ZoneMap.ZoneType.WILDERNESS
	var best_count: int = -1

	var order: Array[int] = [
		ZoneMap.ZoneType.WILDERNESS,
		ZoneMap.ZoneType.SUBURBS,
		ZoneMap.ZoneType.URBAN,
	]

	for z: int in order:
		var c: int = int(counts.get(z, 0))
		if c > best_count:
			best_count = c
			best_zone = z

	return best_zone


func _in_bounds(cell: Vector2i, grid_size: int) -> bool:
	var half_size: int = int(grid_size / 2)
	var start: int = -half_size
	var end: int = grid_size - half_size
	
	return (
		cell.x >= start and cell.x < end
		and cell.y >= start and cell.y < end
	)


func _get_iterations(config: PCGConfig) -> int:
	if config == null:
		return 1

	var has_prop: bool = false
	for p: Dictionary in config.get_property_list():
		if String(p.get("name", "")) == "zone_smoothing_iterations":
			has_prop = true
			break

	if not has_prop:
		return 1

	var v: Variant = config.get("zone_smoothing_iterations")
	if typeof(v) == TYPE_NIL:
		return 1

	return maxi(0, int(v))
