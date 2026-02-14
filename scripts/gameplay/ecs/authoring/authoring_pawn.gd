@tool
class_name AuthoringPawn
extends AuthoringNode2D


const PREVIEW_ANIM_NODE_NAME := "_AuthoringPreviewAnimSprite"

@export var animation_frames: SpriteFrames:
	set(value):
		animation_frames = value
		if Engine.is_editor_hint():
			_update_preview_animation(animation_frames)
	get:
		return animation_frames
@export var move_speed: float = 140.0
@export var collision_shape: Shape2D
var _max_hp: float = 100.0
var _hp: float = 100.0
@export var max_hp: float = 100.0:
	set(value):
		_max_hp = max(value, 1.0)
		_hp = clamp(_hp, 0.0, _max_hp)
	get:
		return _max_hp
@export var hp: float = 100.0:
	set(value):
		_hp = clamp(value, 0.0, max_hp)
	get:
		return _hp
@export var camp: CCamp.CampType = CCamp.CampType.PLAYER


func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		_update_preview_animation(animation_frames)
	_ensure_collision_shape()
	# Ensure hp is valid after all properties are loaded
	_hp = clamp(_hp, 0.0, _max_hp)


func bake(entity: Entity) -> void:
	super.bake(entity)
	
	_bake_movement(entity)
	_bake_collision(entity)
	_bake_hp(entity)
	_bake_pawn(entity)
	_bake_animation(entity)


func _bake_movement(entity: Entity) -> void:
	var movement_comp: CMovement = get_or_add_component(entity, CMovement)
	movement_comp.velocity = Vector2.ZERO
	movement_comp.max_speed = move_speed  # Set max_speed for both player and AI


func _bake_collision(entity: Entity) -> void:
	var collision_comp: CCollision = get_or_add_component(entity, CCollision)
	_ensure_collision_shape()
	if collision_shape:
		collision_comp.collision_shape = collision_shape.duplicate(true)


func _bake_hp(entity: Entity) -> void:
	var hp_comp: CHP = get_or_add_component(entity, CHP)
	hp_comp.max_hp = max_hp
	hp_comp.hp = hp


func _bake_pawn(entity: Entity) -> void:
	var pawn_comp: CCamp = get_or_add_component(entity, CCamp)
	pawn_comp.camp = camp


func _bake_animation(entity: Entity) -> void:
	if not animation_frames:
		return
	
	var animation_comp: CAnimation = get_or_add_component(entity, CAnimation)
	animation_comp.frames = animation_frames


func _ensure_collision_shape() -> void:
	if collision_shape:
		return
	collision_shape = AuthoringNode2D.create_default_collision_shape()


## Update preview with animation frames
func _update_preview_animation(frames: SpriteFrames) -> void:
	if not Engine.is_editor_hint():
		return
	
	# Remove static preview if exists
	var static_preview := get_node_or_null(PREVIEW_NODE_NAME) as Sprite2D
	if static_preview:
		static_preview.queue_free()
	
	if not frames:
		_update_preview_texture(null)
		return
	
	var preview_anim := _ensure_preview_anim_sprite()
	preview_anim.sprite_frames = frames
	
	# Use first animation in the frames
	var anim_names := frames.get_animation_names()
	if anim_names.size() > 0:
		preview_anim.animation = anim_names[0]
		preview_anim.play()
	
	preview_anim.position = Vector2.ZERO
	preview_anim.scale = Vector2.ONE


func _ensure_preview_anim_sprite() -> AnimatedSprite2D:
	var preview_anim := get_node_or_null(PREVIEW_ANIM_NODE_NAME) as AnimatedSprite2D
	if preview_anim:
		return preview_anim
	
	preview_anim = AnimatedSprite2D.new()
	preview_anim.name = PREVIEW_ANIM_NODE_NAME
	preview_anim.owner = null
	preview_anim.visible = true
	preview_anim.centered = true
	add_child(preview_anim, false, Node.INTERNAL_MODE_FRONT)
	return preview_anim
