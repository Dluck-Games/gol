# scripts/pcg/phases/road_rasterizer.gd
class_name RoadRasterizer
extends PCGPhase

const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")
const ZoneMap := preload("res://scripts/pcg/data/zone_map.gd")


@warning_ignore("unused_parameter")
func execute(config: PCGConfig, context: PCGContext) -> void:
	# Overwrite any previous phase output - unified grid is now the source of truth.
	var graph: RoadGraph = context.road_graph
	if graph == null:
		return

	rasterize_edges(graph.edges, context)


## Rasterize only the provided edges (for incremental updates after local street generation).
## This avoids re-rasterizing arterial roads that were already processed.
func rasterize_edges(edges: Array[RoadGraph.RoadEdge], context: PCGContext) -> void:
	"""Rasterize only the provided edges (for incremental updates)."""
	for edge: RoadGraph.RoadEdge in edges:
		_rasterize_edge(edge, context)


func _rasterize_edge(edge: RoadGraph.RoadEdge, context: PCGContext) -> void:
	if edge == null or edge.from_node == null or edge.to_node == null:
		return

	var from_pos: Vector2i = _to_grid(edge.from_node.position)
	var to_pos: Vector2i = _to_grid(edge.to_node.position)

	var width: int = _edge_width_cells(edge)
	var perp: Vector2i = _perpendicular_step(from_pos, to_pos)
	var half: int = int(floor(float(width - 1) / 2.0))
	# Actual width after the formula (e.g., width=4 -> half=1 -> actual=3)
	var actual_width: int = 2 * half + 1

	for p: Vector2i in _bresenham(from_pos, to_pos):
		# Expand width perpendicular to the segment direction.
		for o: int in range(-half, half + 1):
			var pos: Vector2i = p + (perp * o)
			# Unified grid is now the single source of truth for road data.
			var cell = context.get_or_create_cell(pos)
			if cell != null:
				cell.logic_type = TileAssetResolver.LogicType.ROAD
				# Roads are always URBAN zone
				cell.zone_type = ZoneMap.ZoneType.URBAN
				# Apply lane marking rules based on width
				var should_have_lane: bool = _should_have_lane(actual_width, o)
				cell.has_lane = should_have_lane
				# Set tile_id based on lane and orientation
				cell.data["tile_id"] = _get_tile_id(should_have_lane, perp)


## Determines if a cell at the given perpendicular offset should have lane markings.
## Rules:
## - Width 1-2: No lanes
## - Width 3: Only center cell (offset 0)
## - Width 5+: Every other cell from center (offsets where |offset| is even)
func _should_have_lane(actual_width: int, offset: int) -> bool:
	if actual_width <= 2:
		return false
	if actual_width == 3:
		return offset == 0
	# Width >= 5 (odd): alternating pattern from center
	# Offset 0 has lane, then offset ±2, ±4, etc.
	return (absi(offset) % 2) == 0


## Returns the appropriate tile_id based on lane status and road orientation.
## perp=(0,1) means horizontal road -> use vertical lane markings (road_urban_center)
## perp=(1,0) means vertical road -> use horizontal lane markings (road_urban_center_h)
func _get_tile_id(has_lane: bool, perp: Vector2i) -> String:
	if not has_lane:
		return "road_urban"
	# perp=(0,1) -> horizontal road -> vertical lane markings
	if perp == Vector2i(0, 1):
		return "road_urban_center"
	# perp=(1,0) -> vertical road -> horizontal lane markings
	return "road_urban_center_h"


func _to_grid(pos: Vector2) -> Vector2i:
	# RoadGraph uses Vector2 positions; rasterizer operates on integer grid cells.
	return Vector2i(int(round(pos.x)), int(round(pos.y)))


func _edge_width_cells(edge: RoadGraph.RoadEdge) -> int:
	# Use the average node width (tests set both ends equally).
	var w: float = (edge.from_node.width + edge.to_node.width) * 0.5
	return maxi(1, int(round(w)))


func _perpendicular_step(from_pos: Vector2i, to_pos: Vector2i) -> Vector2i:
	var dx: int = to_pos.x - from_pos.x
	var dy: int = to_pos.y - from_pos.y

	# Contract: horizontal expands in Y; vertical expands in X.
	# For non-axis-aligned segments, choose the perpendicular of the dominant axis.
	if absi(dx) >= absi(dy):
		return Vector2i(0, 1)
	return Vector2i(1, 0)


func _bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	# Classic Bresenham line algorithm (inclusive endpoints).
	var points: Array[Vector2i] = []

	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y

	var dx: int = absi(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -absi(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy

	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break

		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

	return points
