class_name SFireBullet
extends System

const SPAWN_OFFSET: float = 16.0


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CWeapon])


func process(entity: Entity, delta: float) -> void:
	var weapon: CWeapon = entity.get_component(CWeapon)
	var player: CPlayer = entity.get_component(CPlayer)
	
	# 始终累加射击冷却时间
	weapon.time_amount_before_last_fire += delta
	
	# 确定是否可以开火
	var wants_to_fire: bool = false
	
	if player:
		# 玩家: 从输入服务检查射击状态（持续按住）
		if player.is_enabled:
			var input_service := ServiceContext.input()
			if input_service:
				wants_to_fire = input_service.is_action_held("player_fire")
	else:
		# AI: 检查武器标志
		wants_to_fire = weapon.can_fire
	
	if not wants_to_fire:
		return

	if weapon.time_amount_before_last_fire < weapon.interval:
		return

	# Reset to zero instead of subtracting to prevent burst fire on first shot
	# (accumulated time before first fire could cause multiple bullets)
	weapon.time_amount_before_last_fire = 0.0
	_fire_bullet(entity, weapon)


func _fire_bullet(entity: Entity, weapon: CWeapon) -> void:
	var self_transform: CTransform = entity.get_component(CTransform)
	if not self_transform:
		return

	var fire_direction := _get_fire_direction(entity, weapon, self_transform.position)
	weapon.last_fire_direction = fire_direction

	_create_bullet(entity, weapon, self_transform.position, fire_direction)


func _get_fire_direction(entity: Entity, weapon: CWeapon, position: Vector2) -> Vector2:
	# Priority 0: Use CAim component (唯一的瞄准方向来源)
	# CAim 由 SCrosshair（鼠标）或 STrackLocation（自动追踪）更新
	var aim: CAim = entity.get_component(CAim)
	if aim:
		var viewport := entity.get_viewport()
		if viewport:
			# Convert screen position to world position using canvas transform
			var canvas_transform := viewport.get_canvas_transform()
			var world_aim := canvas_transform.affine_inverse() * aim.aim_position
			var direction := (world_aim - position).normalized()
			if direction.length_squared() > 0.01:
				return direction

	# Priority 1: Use last fire direction if valid (not zero) 
	# This prevents shooting backwards when retreating
	if weapon.last_fire_direction.length_squared() > 0.01:
		return weapon.last_fire_direction

	# Priority 2: Use movement direction as last resort
	var movement: CMovement = entity.get_component(CMovement)
	if movement and movement.velocity.length_squared() > 0:
		return movement.velocity.normalized()

	# Fallback: default forward direction
	return Vector2.RIGHT


func _create_bullet(shooter: Entity, weapon: CWeapon, origin_position: Vector2, direction: Vector2) -> void:
	var bullet: Entity = null
	
	if not weapon.bullet_recipe_id.is_empty():
		bullet = ServiceContext.recipe().create_entity_by_id(weapon.bullet_recipe_id)
	else:
		push_warning("SFireBullet: No bullet recipe specified")
		return
	
	# Get components
	var bullet_movement: CMovement = bullet.get_component(CMovement)
	var bullet_transform: CTransform = bullet.get_component(CTransform)
	var bullet_comp: CBullet = bullet.get_component(CBullet)
	
	# Apply runtime properties
	if bullet_movement:
		bullet_movement.velocity = direction * weapon.bullet_speed
	if bullet_transform:
		bullet_transform.position = origin_position + direction * SPAWN_OFFSET
	if bullet_comp:
		bullet_comp.owner_entity = shooter
