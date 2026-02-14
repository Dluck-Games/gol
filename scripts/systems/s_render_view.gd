class_name SRenderView
extends System

var _data: Dictionary = {}

func _ready() -> void:
	group = "render"

func query() -> QueryBuilder:
	return q.with_all([CTransform, CSprite]).with_none([CAnimation])
	
func process(entity: Entity, _delta: float) -> void:
	var transform: CTransform = entity.get_component(CTransform)
	var render: CSprite = entity.get_component(CSprite)
	var view_id: int = entity.get_instance_id()
	_create_sprite(entity, view_id)
	_sync_sprite(transform, render, _data[view_id])

func _sync_sprite(transform: CTransform, render: CSprite, view_sprite: Sprite2D) -> void:
	view_sprite.global_position = transform.position
	view_sprite.rotation = transform.rotation
	view_sprite.scale = transform.scale
	view_sprite.texture = render.texture

func _create_sprite(entity: Entity, view_id: int) -> void:
	if not _data.has(view_id):
		var sprite: Sprite2D = Sprite2D.new()
		_data[view_id] = sprite
		entity.add_child(sprite)
		entity.component_removed.connect(_on_component_removed)

func _on_component_removed(entity: Entity, component) -> void:
	if component == CSprite or component == CTransform:
		var view_id: int = entity.get_instance_id()
		if _data.has(view_id):
			var sprite = _data[view_id]
			entity.remove_child(sprite)
			sprite.queue_free()
			_data.erase(view_id)
			print("Removed Sprite2D for entity with ID %s." % view_id)
		else:
			print("[SRenderView] Warning: Entity with ID %s does not have a sprite to remove." % view_id)	
