class_name CPickup
extends Component


var look_distance: float = 32.0 * 4
var focused_box: ObservableProperty = ObservableProperty.new(null)
var box_hint_view: ViewBase = null