class_name CrosshairViewModel
extends ViewModelBase

## 准心 ViewModel - 监听玩家的 CAim 组件

var aim_position: ObservableProperty
var _bound_entity: Entity = null


func setup() -> void:
	aim_position = ObservableProperty.new(Vector2.ZERO)


func teardown() -> void:
	aim_position.teardown()
	_bound_entity = null


func bind_to_entity(entity: Entity) -> void:
	_bound_entity = entity
	aim_position.bind_component(entity, CAim, "aim_position")


func unbind() -> void:
	aim_position.unbind()
	_bound_entity = null
