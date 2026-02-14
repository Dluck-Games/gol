@tool
class_name AuthoringTrigger2D
extends AuthoringNode2D


@export var action: Action
@export var texture: Texture2D:
	set = set_texture


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_update_preview_texture(texture)


func set_texture(new_texture: Texture2D) -> void:
	texture = new_texture
	
	if Engine.is_editor_hint():
		_update_preview_texture(texture if texture else null)


func bake(entity: Entity) -> void:
	super.bake(entity)
	
	var render_comp: CSprite = get_or_add_component(entity, CSprite)
	render_comp.texture = texture
	
	var collision_comp: CCollision = get_or_add_component(entity, CCollision)
	var shape := RectangleShape2D.new()
	
	if texture:
		shape.size = texture.get_size()
	
	collision_comp.collision_shape = shape
	
	var trigger_comp: CTrigger = get_or_add_component(entity, CTrigger)
	if action:
		trigger_comp.action = action
	else:
		push_warning("AuthoringTrigger2D: 'action' is not set for entity. Trigger may not function correctly.")
