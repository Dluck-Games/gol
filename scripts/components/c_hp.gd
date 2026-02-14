class_name CHP
extends Component

@export var max_hp: float = 100.0:
	set(value):
		max_hp = value
		max_hp_observable.value = value
var max_hp_observable: ObservableProperty = ObservableProperty.new(max_hp)

@export var hp: float = max_hp:
	set(value):
		hp = value
		hp_observable.value = value
var hp_observable: ObservableProperty = ObservableProperty.new(hp)

var invincible_time: float = 0.0

var bound_hp_bar: View_HPBar
