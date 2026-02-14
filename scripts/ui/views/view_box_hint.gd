class_name View_BoxHint
extends ViewBase


var vm: ViewModel_BoxHint
var _player_entity: Entity


@onready var _label: Label = $Background/Label


func set_player_entity(entity: Entity) -> void:
	_player_entity = entity


func setup() -> void:
	if not _player_entity or not is_instance_valid(_player_entity):
		push_error("View_BoxHint: Player entity not set")
		queue_free()
		return
	
	vm = ServiceContext.ui().acquire_view_model(ViewModel_BoxHint)
	vm.bind_to_entity(_player_entity)


func bind() -> void:
	if not vm:
		return
	
	vm.position.subscribe(func(v): position = v)
	vm.visible.subscribe(func(v): visible = v)
	vm.text.subscribe(func(v): _label.text = v)


func teardown() -> void:
	if vm:
		if _player_entity and is_instance_valid(_player_entity):
			vm.unbind_to_entity(_player_entity)
		ServiceContext.ui().release_view_model(vm)
		vm = null
	_player_entity = null
