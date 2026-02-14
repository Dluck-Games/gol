class_name View_HPBar
extends EntityBoundView


var vm: ViewModel_HPBar


@onready var _danger_label: Label = $DangerLabel
@onready var _progress_bar: ProgressBar = $ProgressBar


func _get_required_components() -> Array:
	return [CHP, CTransform]


func setup() -> void:
	super.setup()
	if not is_entity_valid():
		return
	
	vm = ServiceContext.ui().acquire_view_model(ViewModel_HPBar)
	vm.bind_to_entity(_entity)

	_danger_label.text = "危"
	_danger_label.add_theme_color_override("font_color", Color.RED)
	_danger_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_danger_label.add_theme_constant_override("outline_size", 4)
	_danger_label.add_theme_font_size_override("font_size", 24)


func bind() -> void:
	if not is_entity_valid():
		return
	
	bind_observable(self, "position", vm.position[_entity])
	bind_observable(_progress_bar, "max_value", vm.hp_max[_entity])
	bind_observable(_progress_bar, "value", vm.hp[_entity])
	
	vm.hp[_entity].subscribe(_on_hp_changed)


func _on_hp_changed(new_hp: float) -> void:
	if not is_entity_valid():
		return
	
	var is_in_danger: bool = (new_hp == 0)
	_progress_bar.visible = not is_in_danger
	_danger_label.visible = is_in_danger


func teardown() -> void:
	if is_entity_valid() and vm != null:
		vm.unbind_to_entity(_entity)
	
	if vm != null:
		ServiceContext.ui().release_view_model(vm)
		vm = null
	
	super.teardown()
