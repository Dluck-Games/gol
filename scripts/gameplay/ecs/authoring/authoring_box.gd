@tool
class_name AuthoringBox
extends AuthoringNode2D


## Recipe ID for stored item
@export var stored_recipe_id: String = ""

@export var required_component: Component

var _texture: Texture2D = preload("res://assets/sprite_sheets/boxes/box.png")
@export var texture: Texture2D:
	set(value):
		_texture = value
		if Engine.is_editor_hint():
			_update_preview_texture(_texture)
	get:
		return _texture

@export var collision_shape: Shape2D


func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		# On first load, _texture has the default value, but the inspector
		# property 'texture' is not set.
		# Calling the setter populates the inspector and updates the preview.
		self.texture = _texture
	_ensure_collision_shape()


func bake(entity: Entity) -> void:
	super.bake(entity)

	_bake_view(entity)
	_bake_container(entity)
	_bake_collision(entity)


func _bake_view(entity: Entity) -> void:
	var render_comp: CSprite = get_or_add_component(entity, CSprite)
	if texture:
		render_comp.texture = texture


func _bake_container(entity: Entity) -> void:
	var container_comp: CContainer = get_or_add_component(entity, CContainer)
	container_comp.stored_recipe_id = stored_recipe_id
	container_comp.required_component = required_component


func _bake_collision(entity: Entity) -> void:
	var collision_comp: CCollision = get_or_add_component(entity, CCollision)
	_ensure_collision_shape()
	if collision_shape:
		collision_comp.collision_shape = collision_shape.duplicate(true)


func _ensure_collision_shape() -> void:
	if collision_shape:
		return
	collision_shape = AuthoringNode2D.create_default_collision_shape()
