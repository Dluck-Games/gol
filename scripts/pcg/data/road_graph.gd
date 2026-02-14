class_name RoadGraph
extends RefCounted

const ROAD_TYPE_ARTERIAL: String = "ARTERIAL"
const ROAD_TYPE_LOCAL: String = "LOCAL"

## Minimal PCG road graph data structures.


class RoadNode extends RefCounted:
	var position: Vector2
	var width: float
	var type: String

	func _init(pos: Vector2, w: float, t: String) -> void:
		position = pos
		width = w
		type = t


class RoadEdge extends RefCounted:
	var from_node: RoadNode
	var to_node: RoadNode

	func _init(from: RoadNode, to: RoadNode) -> void:
		from_node = from
		to_node = to


var nodes: Array[RoadNode] = []
var edges: Array[RoadEdge] = []


func add_node(node: RoadNode) -> void:
	nodes.append(node)


func add_edge(edge: RoadEdge) -> void:
	edges.append(edge)


func get_nodes_near(center: Vector2, radius: float) -> Array[RoadNode]:
	var found: Array[RoadNode] = []
	for node: RoadNode in nodes:
		if node.position.distance_to(center) <= radius:
			found.append(node)
	return found
