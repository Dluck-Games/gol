class_name CCollision
extends Component

# The Shape2D used for collision detection
@export var collision_shape: Shape2D


var area: Area2D = null


func get_first_overlapped_entity() -> Entity:
	var entities = get_all_overlapped_entities()
	if entities.size() > 0:
		return entities[0]
	else:
		return null
	
func get_all_overlapped_entities() -> Array:
	if not area:
		return []
	var overlapped_entities = []
	for overlapped_area in area.get_overlapping_areas():
		if overlapped_area.get_parent():
			var overlapped_entity = overlapped_area.get_parent()
			overlapped_entities.append(overlapped_entity)
	return overlapped_entities
