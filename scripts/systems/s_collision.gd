class_name SCollision
extends System

var _data: Dictionary = {}

func _ready() -> void:
	group = "physics"

func query() -> QueryBuilder:
	return q.with_all([CCollision])

func process(entity: Entity, _delta: float) -> void:
	var collision_comp = entity.get_component(CCollision)

	if not entity.has_component((CTransform)):
		entity.remove_component(CCollision)
		return

	if collision_comp.collision_shape == null:
		collision_comp.collision_shape = CircleShape2D.new()
	
	if collision_comp.area == null:
		collision_comp.area = Area2D.new()
		entity.add_child(collision_comp.area)
		_data[entity.get_instance_id()] = collision_comp.area
		entity.component_removed.connect(_on_component_removed)

		var collision_shape = CollisionShape2D.new()
		collision_shape.shape = collision_comp.collision_shape
		collision_comp.area.add_child(collision_shape)
		
	_update_area_position(entity, collision_comp)

func _on_component_removed(entity: Entity, component) -> void:
	if component == CCollision:
		var area = _data[entity.get_instance_id()]
		entity.remove_child(area)
		area.queue_free()
		_data.erase(entity.get_instance_id())
		print("[SCollision] Removed CCollision.area for entity with ID %s." % entity.get_instance_id())
		
func _update_area_position(entity: Entity, component: CCollision) -> void:
	component.area.position = entity.get_component(CTransform).position
		
