class_name SAnimation
extends System

func _ready() -> void:
	group = "render"

func query() -> QueryBuilder:
	return q.with_all([CAnimation, CTransform])
	
func process(entity: Entity, _delta: float) -> void:
	var animation: CAnimation = entity.get_component(CAnimation)
	var transform: CTransform = entity.get_component(CTransform)
	
	# Initialize sprite node reference if needed
	if not animation.animated_sprite_node:
		_initialize_sprite_node(entity, animation)
	
	if not animation.animated_sprite_node:
		return
	
	# Sync transform with view
	var sprite := animation.animated_sprite_node
	sprite.position = transform.position
	sprite.rotation = transform.rotation
	sprite.scale = transform.scale
	
	# Update animation based on movement
	_update_animation(entity, animation)

func _initialize_sprite_node(entity: Entity, anim_comp: CAnimation) -> void:
	if anim_comp.frames:
		var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
		sprite.sprite_frames = anim_comp.frames
		if anim_comp.current_animation:
			sprite.animation = anim_comp.current_animation
		# 应用染色和缩放
		sprite.modulate = anim_comp.modulate
		sprite.scale = anim_comp.visual_scale
		entity.add_child(sprite)
		anim_comp.animated_sprite_node = sprite

func _update_animation(entity: Entity, anim_comp: CAnimation) -> void:
	var movement: CMovement = entity.get_component(CMovement)
	var sprite: AnimatedSprite2D = anim_comp.animated_sprite_node
	if not sprite:
		return
	
	if not movement:
		return
	
	# Skip animation update during death sequence to avoid interrupting death animation
	if entity.has_component(CDead):
		return
	
	if movement.forbidden_move:
		sprite.pause()
		return
	
	var next_animation: StringName = anim_comp.current_animation
	var flip_h := sprite.flip_h
	
	if movement.velocity != Vector2.ZERO:
		next_animation = "walk"
		var player: CPlayer = entity.get_component(CPlayer)
		if player:
			# 从输入服务获取移动方向来决定翻转
			var input_service := ServiceContext.input()
			if input_service:
				var move_dir := input_service.get_move_direction()
				flip_h = move_dir.x < 0
		else:
			flip_h = movement.velocity.x < 0
	else:
		next_animation = "idle"
	
	# Check if animation exists in frames
	if anim_comp.frames and anim_comp.frames.has_animation(next_animation):
		if sprite.animation != next_animation:
			sprite.play(next_animation)
	
	sprite.flip_h = flip_h
	anim_comp.current_animation = next_animation
