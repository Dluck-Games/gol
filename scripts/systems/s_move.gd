class_name SMove
extends System


func _ready() -> void:
	group = "gameplay"

func query() -> QueryBuilder:
	return q.with_all([CMovement, CTransform])
	

func process(entity: Entity, delta: float) -> void:
	var move: CMovement = entity.get_component(CMovement)
	var transform: CTransform = entity.get_component(CTransform)
	
	if move.forbidden_move:
		return
	
	# 计算有效最大速度 (敌方夜间增强)
	var effective_max_speed := move.max_speed
	if ECSUtils.is_enemy(entity) and ECSUtils.is_night():
		effective_max_speed *= move.night_speed_multiplier
	
	# Process player input (if has CPlayer)
	_process_player_move(entity, delta, effective_max_speed)
	
	# Process AI desired velocity (if enabled)
	_process_desired_velocity(move, delta)
	
	# Clamp velocity to effective max speed
	if move.velocity.length() > effective_max_speed:
		move.velocity = move.velocity.normalized() * effective_max_speed
	
	# Apply friction to slow down
	_apply_friction(move, delta)
	
	# Update position based on velocity
	transform.position += move.velocity * delta
	
func _process_player_move(entity: Entity, delta: float, effective_max_speed: float) -> void:
	var move: CMovement = entity.get_component(CMovement)
	var player: CPlayer = entity.get_component(CPlayer)
	
	if player == null or not player.is_enabled:
		return
	
	# 从输入服务获取移动方向
	var input_service := ServiceContext.input()
	if not input_service:
		return
	
	var input_dir := input_service.get_move_direction()
	
	if input_dir != Vector2.ZERO:
		# Normalize and apply acceleration towards desired speed
		input_dir = input_dir.normalized()
		var target_velocity: Vector2 = input_dir * effective_max_speed
		
		# Accelerate towards target velocity
		move.velocity = move.velocity.move_toward(target_velocity, move.acceleration * delta)
	# If no input, friction will handle slowing down


func _process_desired_velocity(move: CMovement, delta: float) -> void:
	# For AI entities that want smooth movement
	if move.use_desired_velocity:
		move.velocity = move.velocity.move_toward(move.desired_velocity, move.acceleration * delta)


func _apply_friction(move: CMovement, delta: float) -> void:
	# Don't apply friction if using desired_velocity system
	if move.use_desired_velocity and move.desired_velocity.length_squared() > 0.1:
		return
	
	# Apply friction only if velocity is not zero
	if move.velocity.length_squared() > 0.1:
		var friction_force := move.friction * delta
		var speed := move.velocity.length()
		
		if speed > friction_force:
			# Slow down by friction
			move.velocity = move.velocity.move_toward(Vector2.ZERO, friction_force)
		else:
			# Stop completely if speed is very low
			move.velocity = Vector2.ZERO
