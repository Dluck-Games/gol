class_name SDead
extends System

## Death system - handles death flow when CDead is added
## Uses Tween for all visual effects, removes interfering components

const KNOCKBACK_VELOCITY: float = 2000.0
const FLASH_DURATION: float = 0.1
const COLLAPSE_DURATION: float = 0.25
const PLAYER_RESPAWN_DELAY: float = 3.0

var _hit_flash_material: ShaderMaterial = preload("res://resources/hit_flash.tres")

func _ready() -> void:
	group = "gameplay"

func query() -> QueryBuilder:
	return q.with_all([CDead, CTransform])

func process(entity: Entity, _delta: float) -> void:
	var dead: CDead = entity.get_component(CDead)
	
	if not dead._initialized:
		_initialize(entity, dead)


func _initialize(entity: Entity, dead: CDead) -> void:
	dead._initialized = true
	
	# Remove all interfering components
	_remove_interfering_components(entity)
	
	# Find sprite
	var sprite: CanvasItem = _find_sprite(entity)
	if not sprite:
		_complete_death(entity, dead)
		return
	
	# Player has special death animation
	if entity.has_component(CPlayer) and not entity.has_component(CCampfire):
		_initialize_player_death(entity, dead, sprite)
		return
	
	# Building death (spawner) - flash + dissolve, no rotation collapse
	if entity.has_component(CSpawner):
		_initialize_building_death(entity, dead, sprite)
		return
	
	# Non-player death: flash + collapse
	_initialize_generic_death(entity, dead, sprite)


func _initialize_building_death(entity: Entity, dead: CDead, sprite: CanvasItem) -> void:
	# Setup shader
	if not sprite.material or not sprite.material is ShaderMaterial:
		sprite.material = _hit_flash_material.duplicate()
	var mat := sprite.material as ShaderMaterial
	
	# Create death tween sequence
	dead._tween = entity.create_tween()
	dead._tween.set_parallel(false)
	
	# Phase 1: Flash red
	dead._tween.tween_method(
		func(v: float): mat.set_shader_parameter("flash_intensity", v),
		0.0, 0.9, FLASH_DURATION * 0.5
	)
	dead._tween.tween_method(
		func(v: float): mat.set_shader_parameter("flash_intensity", v),
		0.9, 0.0, FLASH_DURATION * 0.5
	)
	
	# Phase 2: Dissolve (no rotation!)
	dead._tween.tween_method(
		func(v: float): mat.set_shader_parameter("dissolve_amount", v),
		0.0, 1.0, 0.5
	)
	
	# Spawn debris
	_spawn_debris(entity)
	
	# On complete
	dead._tween.chain()
	dead._tween.tween_callback(_complete_death.bind(entity, dead))


func _initialize_player_death(entity: Entity, dead: CDead, sprite: CanvasItem) -> void:
	# Lock movement
	var movement: CMovement = entity.get_component(CMovement)
	if movement:
		movement.velocity = Vector2.ZERO
		movement.forbidden_move = true
	
	# Play death animation
	if sprite is AnimatedSprite2D:
		var anim_sprite := sprite as AnimatedSprite2D
		if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("death"):
			anim_sprite.animation_finished.connect(_on_player_death_animation_finished.bind(entity, dead, anim_sprite), CONNECT_ONE_SHOT)
			anim_sprite.play("death")
			# Stop at last frame when animation ends (set frame to last before it loops)
			anim_sprite.set_frame_and_progress(0, 0.0)
			return
	
	# Fallback if no death animation
	_complete_death(entity, dead)


func _on_player_death_animation_finished(entity: Entity, dead: CDead, anim_sprite: AnimatedSprite2D) -> void:
	# Ensure stopped on last frame
	var frame_count := anim_sprite.sprite_frames.get_frame_count("death")
	anim_sprite.set_frame_and_progress(frame_count - 1, 0.0)
	anim_sprite.pause()
	
	# Wait 3 seconds then respawn
	dead._tween = entity.create_tween()
	dead._tween.tween_interval(PLAYER_RESPAWN_DELAY)
	dead._tween.tween_callback(_complete_death.bind(entity, dead))


func _initialize_generic_death(entity: Entity, dead: CDead, sprite: CanvasItem) -> void:
	
	# Setup shader
	if not sprite.material or not sprite.material is ShaderMaterial:
		sprite.material = _hit_flash_material.duplicate()
	var mat := sprite.material as ShaderMaterial
	
	# Play death animation if available
	if sprite is AnimatedSprite2D:
		var anim_sprite := sprite as AnimatedSprite2D
		if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("death"):
			anim_sprite.play("death")
	
	# Apply initial knockback
	var movement: CMovement = entity.get_component(CMovement)
	if movement and dead.knockback_direction.length_squared() > 0.01:
		movement.velocity = dead.knockback_direction * KNOCKBACK_VELOCITY
		movement.forbidden_move = true
	
	# Create death tween sequence
	dead._tween = entity.create_tween()
	dead._tween.set_parallel(false)
	
	# Phase 1: Flash red (0.15s)
	dead._tween.tween_method(
		func(v: float): mat.set_shader_parameter("flash_intensity", v),
		0.0, 0.9, FLASH_DURATION * 0.5
	)
	dead._tween.tween_method(
		func(v: float): mat.set_shader_parameter("flash_intensity", v),
		0.9, 0.0, FLASH_DURATION * 0.5
	)
	
	# Phase 2: Collapse - rotation only (0.5s)
	dead._tween.tween_property(sprite, "rotation", PI * 0.5, COLLAPSE_DURATION).set_ease(Tween.EASE_IN)
	
	# Spawn debris particles
	_spawn_debris(entity)
	
	# On complete
	dead._tween.chain()
	dead._tween.tween_callback(_complete_death.bind(entity, dead))


func _remove_interfering_components(entity: Entity) -> void:
	# Remove components that would interfere with death sequence
	# List defined in Config.DEATH_REMOVE_COMPONENTS
	for comp_class in Config.DEATH_REMOVE_COMPONENTS:
		if entity.has_component(comp_class):
			entity.remove_component(comp_class)


func _find_sprite(entity: Entity) -> CanvasItem:
	for child in entity.get_children():
		if child is AnimatedSprite2D or child is Sprite2D:
			return child
	return null


func _spawn_debris(entity: Entity) -> void:
	var transform: CTransform = entity.get_component(CTransform)
	if not transform:
		return
	
	var particles := CPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 8
	particles.lifetime = 0.5
	particles.position = transform.position
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 120.0
	particles.gravity = Vector2(0, 200)
	particles.color = Color(0.6, 0.6, 0.6, 0.8)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 3.0
	particles.finished.connect(particles.queue_free)
	
	ECS.world.add_child(particles)


func _complete_death(entity: Entity, dead: CDead) -> void:
	# Kill tween if still running
	if dead._tween and dead._tween.is_valid():
		dead._tween.kill()
	
	# Handle based on entity type
	if entity.has_component(CCampfire):
		if GOL and GOL.Game:
			GOL.Game.handle_campfire_destroyed()
	elif entity.has_component(CPlayer):
		if GOL and GOL.Game:
			GOL.Game.handle_player_down()
	
	# Remove entity (including player)
	ECSUtils.remove_entity(entity)
