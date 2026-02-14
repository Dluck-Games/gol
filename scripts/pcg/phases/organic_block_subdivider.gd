# scripts/pcg/phases/organic_block_subdivider.gd
# OrganicBlockSubdivider
#
# Identifies rectangular blocks bounded by arterial roads and recursively
# subdivides them with local streets using randomized offset splits.
# Creates organic, lived-in feel with T-junctions where streets don't align.

class_name OrganicBlockSubdivider
extends PCGPhase

const RoadGraph := preload("res://scripts/pcg/data/road_graph.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")
const RoadRasterizer := preload("res://scripts/pcg/phases/road_rasterizer.gd")

func execute(config: PCGConfig, context: PCGContext) -> void:
    # Do not clear existing graph - we must add local streets to existing arterials
    var graph: RoadGraph = context.road_graph

    # Build node_by_position from existing graph for deduplication
    var node_by_position: Dictionary[Vector2, RoadGraph.RoadNode] = {}
    for node in graph.nodes:
        node_by_position[node.position] = node

    # Track initial edge count to identify new edges for incremental rasterization
    var initial_edge_count: int = graph.edges.size()

    # Shortcuts
    var spacing: int = config.grid_arterial_spacing
    var half: int = int(config.grid_size / 2)
    var limit: int = int(floor(float(half) - 4.0))

    # Iterate blocks between arterial lines
    for block_min_x in range(-limit, limit, spacing):
        for block_min_y in range(-limit, limit, spacing):
            var block_max_x: int = block_min_x + spacing
            var block_max_y: int = block_min_y + spacing

            var center = Vector2i(int((block_min_x + block_max_x) / 2), int((block_min_y + block_max_y) / 2))
            var cell = context.get_cell(center)
            var zone_type: int = cell.zone_type if cell != null else ZoneMap.ZoneType.WILDERNESS

            var depth: int = 0
            match zone_type:
                ZoneMap.ZoneType.URBAN:
                    depth = config.grid_local_subdivision_urban
                ZoneMap.ZoneType.SUBURBS:
                    depth = config.grid_local_subdivision_suburbs
                ZoneMap.ZoneType.WILDERNESS:
                    depth = config.grid_local_subdivision_wilderness

            if depth > 0:
                _subdivide_block(graph, node_by_position, block_min_x, block_min_y, block_max_x, block_max_y, depth, config, context)

    # Incrementally rasterize only the new local street edges (added after initial_edge_count)
    # This avoids re-rasterizing all arterial roads that were already processed
    var new_edges: Array[RoadGraph.RoadEdge] = []
    for i in range(initial_edge_count, graph.edges.size()):
        new_edges.append(graph.edges[i])

    if not new_edges.is_empty():
        var rasterizer := RoadRasterizer.new()
        rasterizer.rasterize_edges(new_edges, context)


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


func _add_edge_between_positions(
    graph: RoadGraph,
    node_by_position: Dictionary[Vector2, RoadGraph.RoadNode],
    a: Vector2,
    b: Vector2,
    width: float,
    road_type: String
) -> void:
    # Ensure nodes exist at endpoints and add edge
    var na: RoadGraph.RoadNode = _get_or_create_node(graph, node_by_position, a, width, road_type)
    var nb: RoadGraph.RoadNode = _get_or_create_node(graph, node_by_position, b, width, road_type)
    graph.add_edge(RoadGraph.RoadEdge.new(na, nb))


func _subdivide_block(
    graph: RoadGraph,
    node_by_position: Dictionary[Vector2, RoadGraph.RoadNode],
    min_x: int,
    min_y: int,
    max_x: int,
    max_y: int,
    depth: int,
    config: PCGConfig,
    context: PCGContext
) -> void:
    if depth <= 0:
        return

    var width_x: float = float(max_x - min_x)
    var width_y: float = float(max_y - min_y)

    if width_x > width_y:
        # Vertical split along longest dimension with random ratio
        var ratio: float = context.rng.randf_range(config.local_split_ratio_min, config.local_split_ratio_max)
        var mid_x: float = float(min_x) + width_x * ratio
        var from_pos: Vector2 = Vector2(mid_x, float(min_y))
        var to_pos: Vector2 = Vector2(mid_x, float(max_y))

        _add_edge_between_positions(graph, node_by_position, from_pos, to_pos, config.road_width_local, RoadGraph.ROAD_TYPE_LOCAL)

        # Recurse on left and right halves
        _subdivide_block(graph, node_by_position, min_x, min_y, int(mid_x), max_y, depth - 1, config, context)
        _subdivide_block(graph, node_by_position, int(mid_x), min_y, max_x, max_y, depth - 1, config, context)
    else:
        # Horizontal split along longest dimension with random ratio
        var ratio: float = context.rng.randf_range(config.local_split_ratio_min, config.local_split_ratio_max)
        var mid_y: float = float(min_y) + width_y * ratio
        var from_pos: Vector2 = Vector2(float(min_x), mid_y)
        var to_pos: Vector2 = Vector2(float(max_x), mid_y)

        _add_edge_between_positions(graph, node_by_position, from_pos, to_pos, config.road_width_local, RoadGraph.ROAD_TYPE_LOCAL)

        # Recurse on top and bottom halves
        _subdivide_block(graph, node_by_position, min_x, min_y, max_x, int(mid_y), depth - 1, config, context)
        _subdivide_block(graph, node_by_position, min_x, int(mid_y), max_x, max_y, depth - 1, config, context)