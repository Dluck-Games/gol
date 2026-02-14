## EntityBoundView - 与实体强绑定的视图基类
## 当绑定的实体被移除、必需组件被移除、或 CDead 组件被添加时，自动销毁自身
##
## 使用方式：
##   var view = EntityBoundView.create_from_scene(my_scene, entity)
##   if view:
##       ServiceContext.ui().push_view(layer, view)
class_name EntityBoundView
extends ViewBase


## 绑定的实体
var _entity: Entity

## 追踪绑定的 ObservableProperty，用于统一解绑
var _bound_observables: Array[ObservableProperty] = []


## 静态工厂方法：从 PackedScene 创建并绑定实体
## 如果实体无效或缺少必需组件，返回 null
static func create_from_scene(scene: PackedScene, entity: Entity) -> EntityBoundView:
	if entity == null or not is_instance_valid(entity):
		return null
	
	var view: EntityBoundView = scene.instantiate() as EntityBoundView
	if view == null:
		return null
	
	# 检查必需组件
	for comp_class in view._get_required_components():
		if not entity.has_component(comp_class):
			view.queue_free()
			return null
	
	view._entity = entity
	return view


## 子类必须重写：返回此视图依赖的组件类型数组
## 当这些组件中的任何一个被移除时，视图会自动销毁
func _get_required_components() -> Array:
	return []


## 获取绑定的实体
func get_entity() -> Entity:
	return _entity


## 检查实体是否有效
func is_entity_valid() -> bool:
	return _entity != null and is_instance_valid(_entity)


## 绑定 ObservableProperty 到控件属性，自动追踪用于统一解绑
func bind_observable(control: Control, property_name: String, observable: ObservableProperty) -> void:
	_bound_observables.append(observable)
	var on_updated = func(new_value):
		if is_instance_valid(control):
			control.set(property_name, new_value)
	observable.subscribe(on_updated)


## ViewBase 生命周期：_ready 时调用
func setup() -> void:
	if not is_entity_valid():
		push_error("%s: Entity not bound" % get_class())
		queue_free()
		return
	_connect_entity_signals()


## 子类重写：数据绑定逻辑
func bind() -> void:
	pass


## 销毁视图
func teardown() -> void:
	_unbind_all_observables()
	_disconnect_entity_signals()
	_entity = null


#region 内部方法

func _connect_entity_signals() -> void:
	if ECS.world and not ECS.world.entity_removed.is_connected(_on_entity_removed):
		ECS.world.entity_removed.connect(_on_entity_removed)
	
	if _entity and is_instance_valid(_entity):
		if not _entity.component_removed.is_connected(_on_component_removed):
			_entity.component_removed.connect(_on_component_removed)
		if not _entity.component_added.is_connected(_on_component_added):
			_entity.component_added.connect(_on_component_added)


func _disconnect_entity_signals() -> void:
	if ECS.world and ECS.world.entity_removed.is_connected(_on_entity_removed):
		ECS.world.entity_removed.disconnect(_on_entity_removed)
	
	if _entity != null and is_instance_valid(_entity):
		if _entity.component_removed.is_connected(_on_component_removed):
			_entity.component_removed.disconnect(_on_component_removed)
		if _entity.component_added.is_connected(_on_component_added):
			_entity.component_added.disconnect(_on_component_added)


func _unbind_all_observables() -> void:
	for observable in _bound_observables:
		if observable != null:
			observable.teardown()
	_bound_observables.clear()


func _on_entity_removed(entity: Entity) -> void:
	if entity == _entity:
		_destroy_self()


func _on_component_removed(_entity_ref: Entity, component: Variant) -> void:
	for comp_class in _get_required_components():
		if is_instance_of(component, comp_class):
			_destroy_self()
			return


func _on_component_added(_entity_ref: Entity, component: Variant) -> void:
	if component is CDead:
		_destroy_self()


func _destroy_self() -> void:
	ServiceContext.ui().pop_view(self)

#endregion
