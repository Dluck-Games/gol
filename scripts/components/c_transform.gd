class_name CTransform
extends Component


@export var position : Vector2 = Vector2.ZERO:
	set(value):
		position = value
		position_observable.value = value
var position_observable : ObservableProperty = ObservableProperty.new(position)

@export var rotation : float = 0.0
@export var scale : Vector2 = Vector2.ONE
