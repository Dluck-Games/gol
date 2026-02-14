class_name SMeleeAttack
extends System

## Melee attack system - handles cooldown update, physics overlap detection and damage application
## Data-driven: reads attack_direction from CMelee component to trigger attacks


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CMelee])


func process(entity: Entity, delta: float) -> void:
	var melee := entity.get_component(CMelee) as CMelee
	if not melee:
		return
	
	# Update cooldown
	if melee.cooldown_remaining > 0.0:
		melee.cooldown_remaining -= delta
	
	# Process attack request
	if melee.attack_pending and melee.cooldown_remaining <= 0.0:
		_perform_attack(entity, melee)


func _perform_attack(attacker: Entity, melee: CMelee) -> void:
	var attack_dir := melee.attack_direction.normalized() if melee.attack_direction != Vector2.ZERO else Vector2.RIGHT
	
	# Consume attack request
	melee.attack_pending = false
	
	var transform: CTransform = attacker.get_component(CTransform)
	if not transform:
		return
	
	var attacker_pos: Vector2 = transform.position
	
	var viewport := attacker.get_viewport()
	if not viewport:
		return
	
	var world_2d: World2D = viewport.world_2d
	if not world_2d:
		return
	
	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	if not space_state:
		return
	
	# Create circle shape for melee detection
	var shape := CircleShape2D.new()
	shape.radius = melee.attack_range
	
	var shape_query := PhysicsShapeQueryParameters2D.new()
	shape_query.shape = shape
	shape_query.transform = Transform2D(0, attacker_pos)
	shape_query.collide_with_areas = true
	shape_query.collide_with_bodies = false
	
	var results: Array[Dictionary] = space_state.intersect_shape(shape_query)
	
	# Get attacker's camp to filter targets
	var attacker_camp := attacker.get_component(CCamp) as CCamp
	if not attacker_camp:
		return
		
	for result in results:
		var collider = result.get("collider")
		if not collider:
			continue
		
		# Get the entity from the Area2D's parent
		var target: Entity = null
		if collider is Area2D and collider.get_parent() is Entity:
			target = collider.get_parent() as Entity
		
		if not target or target == attacker:
			continue
		
		# Check if target is enemy
		var target_camp := target.get_component(CCamp) as CCamp
		if not target_camp or target_camp.camp == attacker_camp.camp:
			continue
		
		# Check if target has HP
		if not target.has_component(CHP):
			continue
		
		# Apply damage via CDamage component
		if not target.has_component(CDamage):
			var damage := CDamage.new()
			damage.amount = melee.damage
			damage.knockback_direction = attack_dir
			target.add_component(damage)
	
	# Reset cooldown after attack (敌方夜间攻速提升)
	var cooldown := melee.attack_interval
	if ECSUtils.is_enemy(attacker) and ECSUtils.is_night():
		cooldown /= melee.night_attack_speed_multiplier
	melee.cooldown_remaining = cooldown
	
	# Play swing animation
	_play_swing_effect(attacker, attack_dir, melee.swing_angle, melee.swing_duration)


func _play_swing_effect(entity: Entity, direction: Vector2, swing_angle: float, swing_duration: float) -> void:
	var sprite: CanvasItem = null
	for child in entity.get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			sprite = child
			break
	
	if not sprite:
		return
	
	# Determine swing direction based on attack direction
	var swing_dir := 1.0 if direction.x >= 0 else -1.0
	var swing_rad := deg_to_rad(swing_angle) * swing_dir
	
	var tween := entity.create_tween()
	tween.tween_property(sprite, "rotation", swing_rad, swing_duration * 0.3)
	tween.tween_property(sprite, "rotation", -swing_rad * 0.5, swing_duration * 0.4)
	tween.tween_property(sprite, "rotation", 0.0, swing_duration * 0.3)
