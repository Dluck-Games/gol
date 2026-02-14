class_name View_HUD
extends ViewBase

var vm: ViewModel_HUD
@onready var clock_pin: TextureRect = $TextureRect_Clock/TextureRect_Pin

func setup() -> void:
	vm = ServiceContext.ui().acquire_view_model(ViewModel_HUD)

func teardown() -> void:
	if vm != null:
		ServiceContext.ui().release_view_model(vm)
		vm = null
	
func bind() -> void:
	
	vm.current_time.subscribe(_on_current_time_update)

func _on_current_time_update(_new_time : float) -> void:
	var current_time = vm.current_time.value
	var duration = vm.duration.value

	# 时钟角度映射：
	# time=0 → 3 点钟 (右, rotation=0)
	# time=6 → 6 点钟 (下, rotation=PI/2)
	# time=12 → 9 点钟 (左, rotation=PI)
	# time=18 → 0 点钟 (上, rotation=-PI/2)
	var current_rad : float = (current_time / duration) * TAU + PI / 2.0
	clock_pin.rotation = current_rad
