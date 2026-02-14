class_name CLifeTime
extends Component


@export var lifetime: float = 10.0:
	set(value):
		lifetime_observable.value = value
		lifetime = value

var lifetime_observable: ObservableProperty = ObservableProperty.new(lifetime)
