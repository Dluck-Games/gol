class_name CMapData
extends Component

## Component that holds a reference to PCGResult for map rendering.
## Emits map_changed signal when the map data is updated.

signal map_changed

## Reference to the PCGResult containing generated map data
@export var pcg_result = null:
	set(value):
		pcg_result = value
		pcg_result_observable.value = value
		map_changed.emit()
var pcg_result_observable: ObservableProperty = ObservableProperty.new(null)

## Optional reference to PCGContext for pipeline flexibility
@export var pcg_context = null:
	set(value):
		pcg_context = value
		pcg_context_observable.value = value
		map_changed.emit()
var pcg_context_observable: ObservableProperty = ObservableProperty.new(null)
