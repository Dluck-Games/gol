# scripts/pcg/phases/irregular_grid_generator.gd
# IrregularGridGenerator
#
# Generates arterial roads using recursive binary splitting (BSP-like).
# Creates randomized but orthogonal cuts instead of perfect grid.

class_name IrregularGridGenerator
extends PCGPhase


func execute(config: PCGConfig, context: PCGContext) -> void:
	# Fresh graph for this phase execution.
	context.road_graph = RoadGraph.new()
	var graph: RoadGraph = context.road_graph

	# Bounds
	var half_size: float = float(config.grid_size) / 2.0
	var margin: int = 4
	var limit: int = int(floor(half_size - margin))

	# Node cache to deduplicate nodes at identical positions
	var node_by_position: Dictionary[Vector2, RoadGraph.RoadNode] = {}

	# Queue for BFS splitting
	var queue: Array[Dictionary] = []
	var initial_rect: Rect2i = Rect2i(-limit, -limit, limit * 2, limit * 2)
	queue.append({"rect": initial_rect, "depth": 0})

	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		var rect: Rect2i = item["rect"]
		var depth: int = item["depth"]

		# Stop conditions
		if depth >= config.arterial_split_max_depth:
			continue
		if rect.size.x < config.arterial_min_spacing or rect.size.y < config.arterial_min_spacing:
			continue

		# Determine split axis
		var split_vertical: bool = rect.size.x > rect.size.y

		# Split position
		var split_pos: int
		if split_vertical:
			var center: int = rect.position.x + rect.size.x / 2
			var jitter_range: int = int(float(rect.size.x) * config.arterial_split_jitter)
			split_pos = center + context.randi_range(-jitter_range, jitter_range)
			# Clamp to min_spacing from edges
			split_pos = clamp(split_pos, rect.position.x + config.arterial_min_spacing, rect.end.x - config.arterial_min_spacing)
		else:
			var center: int = rect.position.y + rect.size.y / 2
			var jitter_range: int = int(float(rect.size.y) * config.arterial_split_jitter)
			split_pos = center + context.randi_range(-jitter_range, jitter_range)
			# Clamp to min_spacing from edges
			split_pos = clamp(split_pos, rect.position.y + config.arterial_min_spacing, rect.end.y - config.arterial_min_spacing)

		# Draw road along the split line
		if split_vertical:
			# Vertical road: x = split_pos, y from rect.top to rect.bottom
			var start_pos: Vector2 = Vector2(float(split_pos), float(rect.position.y))
			var end_pos: Vector2 = Vector2(float(split_pos), float(rect.end.y))
			var start_node: RoadGraph.RoadNode = _get_or_create_node(
				graph,
				node_by_position,
				start_pos,
				config.road_width_arterial,
				RoadGraph.ROAD_TYPE_ARTERIAL
			)
			var end_node: RoadGraph.RoadNode = _get_or_create_node(
				graph,
				node_by_position,
				end_pos,
				config.road_width_arterial,
				RoadGraph.ROAD_TYPE_ARTERIAL
			)
			graph.add_edge(RoadGraph.RoadEdge.new(start_node, end_node))
		else:
			# Horizontal road: y = split_pos, x from rect.left to rect.right
			var start_pos: Vector2 = Vector2(float(rect.position.x), float(split_pos))
			var end_pos: Vector2 = Vector2(float(rect.end.x), float(split_pos))
			var start_node: RoadGraph.RoadNode = _get_or_create_node(
				graph,
				node_by_position,
				start_pos,
				config.road_width_arterial,
				RoadGraph.ROAD_TYPE_ARTERIAL
			)
			var end_node: RoadGraph.RoadNode = _get_or_create_node(
				graph,
				node_by_position,
				end_pos,
				config.road_width_arterial,
				RoadGraph.ROAD_TYPE_ARTERIAL
			)
			graph.add_edge(RoadGraph.RoadEdge.new(start_node, end_node))

		# Add sub-rects to queue
		if split_vertical:
			var left_rect: Rect2i = Rect2i(rect.position.x, rect.position.y, split_pos - rect.position.x, rect.size.y)
			var right_rect: Rect2i = Rect2i(split_pos, rect.position.y, rect.end.x - split_pos, rect.size.y)
			queue.append({"rect": left_rect, "depth": depth + 1})
			queue.append({"rect": right_rect, "depth": depth + 1})
		else:
			var top_rect: Rect2i = Rect2i(rect.position.x, rect.position.y, rect.size.x, split_pos - rect.position.y)
			var bottom_rect: Rect2i = Rect2i(rect.position.x, split_pos, rect.size.x, rect.end.y - split_pos)
			queue.append({"rect": top_rect, "depth": depth + 1})
			queue.append({"rect": bottom_rect, "depth": depth + 1})


func _get_or_create_node(
	graph: RoadGraph,
	node_by_position: Dictionary[Vector2, RoadGraph.RoadNode],
	pos: Vector2,
	width: float,
	road_type: String
) -> RoadGraph.RoadNode:
	if node_by_position.has(pos):
		return node_by_position[pos]

	var node := RoadGraph.RoadNode.new(pos, width, road_type)
	node_by_position[pos] = node
	graph.add_node(node)
	return node