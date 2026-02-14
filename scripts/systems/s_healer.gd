class_name SHealer
extends System

func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CHealer])
	
func process(entity: Entity, delta: float) -> void:
	var healer: CHealer = entity.get_component(CHealer)

	for target_entity in ECS.world.query.with_all([CHP]).execute():
		var hp: CHP = target_entity.get_component(CHP)
		hp.hp = clamp(hp.hp + healer.heal_pro_sec * delta, 0, hp.max_hp)
