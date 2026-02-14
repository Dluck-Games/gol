class_name ZoneCalculator
extends PCGPhase

const _DIRS_4: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]


func execute(config: PCGConfig, context: PCGContext) -> void:
	# Unified grid is now the single source of truth for zone data.
	var grid_size: int = config.grid_size

	var half_size: int = int(grid_size / 2)
	var start: int = -half_size
	var end: int = grid_size - half_size

	# Build road_cells view from unified grid for BFS calculation
	var road_cells: Dictionary[Vector2i, bool] = _build_road_cells_from_grid(context)
	if road_cells.is_empty():
		# No roads: define everything as wilderness (avoid div-by-zero normalization).
		for y: int in range(start, end):
			for x: int in range(start, end):
				var pos := Vector2i(x, y)
				context.get_or_create_cell(pos).zone_type = ZoneMap.ZoneType.WILDERNESS
		return

	var distances: Dictionary[Vector2i, int] = _bfs_distance_field(road_cells, grid_size)
	var max_distance: int = 0
	for cell: Vector2i in distances.keys():
		var d: int = int(distances[cell])
		if d > max_distance:
			max_distance = d

	if max_distance <= 0:
		# Roads exist but only cover the whole grid? (or single-cell grid)
		# Treat as fully urban.
		for y: int in range(start, end):
			for x: int in range(start, end):
				var pos := Vector2i(x, y)
				context.get_or_create_cell(pos).zone_type = ZoneMap.ZoneType.URBAN
		return

	for y: int in range(start, end):
		for x: int in range(start, end):
			var cell := Vector2i(x, y)
			var dist: int = int(distances.get(cell, max_distance))
			var norm_dist: float = float(dist) / float(max_distance)
			norm_dist = clampf(norm_dist, 0.0, 1.0)

			var zone_type: int = _assign_zone(norm_dist, config)
			# Write to unified grid only - legacy view generated on demand.
			context.get_or_create_cell(cell).zone_type = zone_type


func _build_road_cells_from_grid(context: PCGContext) -> Dictionary[Vector2i, bool]:
	"""Build road_cells dictionary from unified grid for BFS calculation."""
	var road_cells: Dictionary[Vector2i, bool] = {}
	if context == null or context.grid == null:
		return road_cells
	
	for pos: Variant in context.grid.keys():
		if pos is Vector2i:
			var cell = context.grid[pos]
			if cell is PCGCell and cell.is_road():
				road_cells[pos] = true
	
	return road_cells


func _bfs_distance_field(road_cells: Dictionary[Vector2i, bool], grid_size: int) -> Dictionary[Vector2i, int]:
	var distances: Dictionary[Vector2i, int] = {}
	var queue: Array[Vector2i] = []
	var head: int = 0

	for cell: Vector2i in road_cells.keys():
		if not _in_bounds(cell, grid_size):
			continue
		if distances.has(cell):
			continue
		distances[cell] = 0
		queue.append(cell)

	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1

		var current_dist: int = int(distances[current])
		for dir: Vector2i in _DIRS_4:
			var n: Vector2i = current + dir
			if not _in_bounds(n, grid_size):
				continue
			if distances.has(n):
				continue
			distances[n] = current_dist + 1
			queue.append(n)

	return distances


func _assign_zone(norm_dist: float, config: PCGConfig) -> int:
	# Contract: strictly '<' for thresholds
	if norm_dist < config.zone_threshold_suburbs:
		return ZoneMap.ZoneType.URBAN
	if norm_dist < config.zone_threshold_urban:
		return ZoneMap.ZoneType.SUBURBS
	return ZoneMap.ZoneType.WILDERNESS


func _in_bounds(cell: Vector2i, grid_size: int) -> bool:
	var half_size: int = int(grid_size / 2)
	var start: int = -half_size
	var end: int = grid_size - half_size
	
	return (
		cell.x >= start and cell.x < end
		and cell.y >= start and cell.y < end
	)
