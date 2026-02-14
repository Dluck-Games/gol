class_name SCamera
extends System

func _ready() -> void:
	group = "gameplay"

func query() -> QueryBuilder:
	return q.with_all([CCamera, CCamp])

func process(entity: Entity, _delta: float) -> void:
	var camera: CCamera = entity.get_component(CCamera)
	
	if camera.camera == null:
		_on_component_created(entity, camera)
	
	var transform = entity.get_component(CTransform)
	if transform:
		camera.camera.position = transform.position
	
	
func _on_component_created(entity: Entity, camera: CCamera) -> void:
	camera.camera = Camera2D.new()
	entity.add_child(camera.camera)
	camera.camera.make_current()
	camera.camera.set_position_smoothing_enabled(true)
	entity.component_removed.connect(_on_component_removed)
		
func _on_component_removed(_entity: Entity, component: Variant) -> void:
	if component is CCamera and component.camera:
		component.camera.queue_free()
