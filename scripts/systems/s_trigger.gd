class_name STrigger
extends System

func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CTrigger, CCollision])
	
func process(entity: Entity, _delta: float) -> void:
	var trigger: CTrigger = entity.get_component(CTrigger)
	var collision: CCollision = entity.get_component(CCollision)
	
	if collision.get_first_overlapped_entity():
		var causer = collision.get_first_overlapped_entity()
		trigger.action.execute(causer)
