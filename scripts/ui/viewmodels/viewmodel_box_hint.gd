class_name ViewModel_BoxHint
extends ViewModelBase


var position: ObservableProperty
var visible: ObservableProperty
var text: ObservableProperty
var focused_box_binder: ObservableProperty
var bound_entity: Entity = null

func setup() -> void:
	position = ObservableProperty.new(Vector2.ZERO)
	visible = ObservableProperty.new(false)
	text = ObservableProperty.new("")
	focused_box_binder = ObservableProperty.new(null)

func teardown() -> void:
	position.teardown()
	visible.teardown()
	text.teardown()
	focused_box_binder.teardown()
	bound_entity = null

func bind_to_entity(entity: Entity) -> void:
	bound_entity = entity
	
	# 绑定到 CPickup 的 focused_box
	var pickup: CPickup = entity.get_component(CPickup)
	if pickup and pickup.focused_box:
		focused_box_binder.bind_observable(pickup.focused_box)
		focused_box_binder.subscribe(func(box_entity): _on_focused_box_changed(box_entity))

func unbind_to_entity(entity: Entity) -> void:
	if entity == bound_entity:
		focused_box_binder.unbind()
		bound_entity = null

func _on_focused_box_changed(box_entity: Entity) -> void:
	if box_entity:
		var container_box: CContainer = box_entity.get_component(CContainer)
		var transform_box: CTransform = box_entity.get_component(CTransform)
		
		if container_box and transform_box:
			# 计算位置
			var box_position: Vector2 = transform_box.position + Vector2(0, -32)
			
			# 获取存储物品的名称 (use recipe_id directly or look up display_name)
			var box_name: String = "Unknown"
			if not container_box.stored_recipe_id.is_empty():
				var recipe := ServiceContext.recipe().get_recipe(container_box.stored_recipe_id)
				if recipe:
					box_name = recipe.display_name if not recipe.display_name.is_empty() else recipe.get_recipe_id()
				else:
					box_name = container_box.stored_recipe_id
			
			var component_name: String = ""
			
			# 获取组件名称
			if container_box.required_component:
				var required_component_script: Script = container_box.required_component.get_script()
				component_name = required_component_script.get_path().get_file().get_basename()
			
			# 设置显示文本
			var display_text: String = box_name
			if not component_name.is_empty():
				display_text += " (Exchange: %s)" % component_name
			
			# 更新可观察变量
			position.set_value(box_position)
			visible.set_value(true)
			text.set_value(display_text)
	else:
		# 没有聚焦目标时隐藏提示
		visible.set_value(false)
