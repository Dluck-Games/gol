# ObservableProperty.gd
class_name ObservableProperty
extends RefCounted


# Accessor for convenience use of inner value
var value: Variant:
	get:
		return get_value()
	set(new_value):
		set_value(new_value)


signal _changed(new_value)

var _value: Variant
var _bound_other: ObservableProperty
var _bound_callable: Callable
var _subscriber_callbacks: Array[Callable] = []

func _init(initial_value: Variant = null) -> void:
	_value = initial_value
	_bound_callable = Callable(self, "set_value")

func teardown() -> void:
	_disconnect_all_subscribers()
	if is_bound():
		unbind()

func set_value(new_value: Variant) -> void:
	if typeof(_value) == typeof(new_value) and _value == new_value:
		return
	_value = new_value
	_changed.emit(new_value)

func get_value() -> Variant:
	return _value

func is_bound() -> bool:
	return _bound_other != null

func bind_component(entity: Entity, component: Script, property_name: String, custom_setter: Callable = set_value) -> bool:
	var component_instance := entity.get_component(component)
	if component_instance:
		var other_property: ObservableProperty = component_instance.get(property_name + "_observable")
		if other_property and other_property is ObservableProperty:
			bind_observable(other_property, custom_setter)
			return true
		else:
			print("Warning: Property '%s' is not an ObservableProperty on component '%s'." % [property_name, component])
	else:
		print("Warning: Entity does not have component '%s'." % component)
	return false

func bind_observable(other: ObservableProperty, custom_setter: Callable = set_value) -> void:
	if other == null:
		push_warning("Cannot bind to null ObservableProperty.")
		return
	if _bound_other == other:
		print("Warning: Attempted to bind to an ObservableProperty that is already bound.")
		return
	if is_bound():
		unbind()

	_bound_callable = custom_setter
	if _bound_callable.is_null():
		_bound_callable = Callable(self, "set_value")
	_bound_callable.call(other.get_value())
	_bound_other = other
	if not _bound_other._changed.is_connected(_bound_callable):
		_bound_other._changed.connect(_bound_callable)
	
func unbind() -> void:
	if _bound_other:
		if not _bound_callable.is_null() and _bound_other._changed.is_connected(_bound_callable):
			_bound_other._changed.disconnect(_bound_callable)
	_bound_other = null
	_bound_callable = Callable(self, "set_value")

func subscribe(callback: Callable) -> void:
	if callback.is_null():
		return
	callback.call(_value)
	if _changed.is_connected(callback):
		return
	_changed.connect(callback)
	_subscriber_callbacks.append(callback)

func unsubscribe(callback: Callable) -> void:
	if callback.is_null():
		return
	if _changed.is_connected(callback):
		_changed.disconnect(callback)
	_subscriber_callbacks.erase(callback)

func _disconnect_all_subscribers() -> void:
	for callback in _subscriber_callbacks:
		if _changed.is_connected(callback):
			_changed.disconnect(callback)
	_subscriber_callbacks.clear()
