class_name ViewModel_HUD
extends ViewModelBase


var current_time : ObservableProperty = ObservableProperty.new(0.0)
var duration : ObservableProperty = ObservableProperty.new(0.0)


func setup() -> void:
	_bind_current_time()

func teardown() -> void:
	current_time.teardown()
	duration.teardown()

func _bind_current_time() -> void:
	var entities := ECS.world.query.with_all([CDayNightCycle]).execute()
	if entities.is_empty():
		return
	current_time.bind_component(entities[0], CDayNightCycle, "current_time")
	duration.bind_component(entities[0], CDayNightCycle, "duration")
