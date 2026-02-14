class_name SLife
extends System

func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CLifeTime])
	
func process(entity: Entity, delta: float) -> void:
	var lifetime: CLifeTime = entity.get_component(CLifeTime)
	
	lifetime.lifetime -= delta
	
	if lifetime.lifetime <= 0:
		_handle_lifetime_expired(entity)


func _handle_lifetime_expired(entity) -> void:
	# Check if death already in progress
	if entity.has_component(CDead):
		return
	
	if entity.has_component(CBullet):
		ECS.world.remove_entity(entity)
	elif entity.has_component(CCamp):
		var pawn: CCamp = entity.get_component(CCamp)
		if pawn.camp == CCamp.CampType.PLAYER:
			var movement: CMovement = entity.get_component(CMovement)
			var last_direction := movement.velocity.normalized() if movement else Vector2.ZERO
			_start_death(entity, last_direction)
			return


func _start_death(target_entity: Entity, knockback_dir: Vector2) -> void:
	"""Add CDead component to trigger death sequence"""
	var dead := CDead.new()
	dead.knockback_direction = knockback_dir
	target_entity.add_component(dead)
