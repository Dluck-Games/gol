class_name Service_UI
extends ServiceBase


var ui_base: Node
var hud_layer: CanvasLayer
var game_layer: Control


enum LayerType {
	HUD,
	GAME
}


var _view_models: Dictionary = {}
var _view_model_ref_counts: Dictionary = {}
var _pushed_views: Array[ViewBase] = []
var _ui_order_connected := false

func setup() -> void:
	ui_base = Node.new()
	ui_base.name = "UI"
	
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUD_Layer"
	game_layer = Control.new()
	game_layer.name = "Game_Layer"
	
	ui_base.add_child(hud_layer)
	ui_base.add_child(game_layer)
	_pushed_views.clear()
	_view_models.clear()
	_view_model_ref_counts.clear()
	
	# Wait root to be ready, or add child will fail.
	root_node().add_child.call_deferred(ui_base)
	
	# Ensure UI is always on top by moving it to the end of the scene tree
	if root_node() and not root_node().child_order_changed.is_connected(_ensure_ui_on_top):
		root_node().child_order_changed.connect(_ensure_ui_on_top)
		_ui_order_connected = true
	
func teardown() -> void:
	_pop_all_views()
	_release_all_view_models()
	_disconnect_ui_on_top_signal()
	_free_ui_tree()

func create_view(layout: PackedScene) -> ViewBase:
	return layout.instantiate() as ViewBase

func push_view(layer: LayerType, ui_node: ViewBase) -> void:
	if ui_node == null:
		push_error("UI node is null.")
		return
	if _pushed_views.has(ui_node):
		push_error("UI node of type " + str(ui_node.get_script()) + " is already pushed.")
		return
	
	var parent_layer := _get_layer_node(layer)
	if parent_layer == null:
		return
	
	parent_layer.add_child(ui_node)
	_pushed_views.append(ui_node)
	print("Pushed UI view: " + str(ui_node.name))

func pop_view(ui_node: ViewBase) -> void:
	if not is_instance_valid(ui_node):
		push_error("UI node is null or freed.")
		return
	
	var tracked := _pushed_views.has(ui_node)
	if tracked:
		_pushed_views.erase(ui_node)
		print("Popped UI view: " + ui_node.name)
	
	ui_node.teardown()
	if ui_node.is_inside_tree():
		ui_node.queue_free()
	else:
		ui_node.free()

func pop_views_by_layer(layer: LayerType) -> void:
	var parent_layer := _get_layer_node(layer)
	if parent_layer == null:
		return
	
	for child in parent_layer.get_children().duplicate():
		if child is ViewBase:
			pop_view(child as ViewBase)

func create_and_push_view(layer: LayerType, layout: PackedScene):
	var view_instance := create_view(layout)
	push_view(layer, view_instance)

func acquire_view_model(view_model_class: Script) -> ViewModelBase:
	var vm: ViewModelBase = _view_models.get(view_model_class, null)
	if vm == null:
		vm = view_model_class.new() as ViewModelBase
		vm.setup()
		_view_models[view_model_class] = vm
		_view_model_ref_counts[view_model_class] = 0
	_view_model_ref_counts[view_model_class] = _view_model_ref_counts.get(view_model_class, 0) + 1
	return vm

func release_view_model(vm: ViewModelBase) -> void:
	if vm == null:
		return
	var key := vm.get_script() as Script
	if not _view_model_ref_counts.has(key):
		return
	
	_view_model_ref_counts[key] -= 1
	if _view_model_ref_counts[key] <= 0:
		_view_model_ref_counts.erase(key)
		if _view_models.has(key):
			_view_models.erase(key)
		vm.teardown()

func _ensure_ui_on_top() -> void:
	if ui_base and ui_base.is_inside_tree():
		root_node().move_child.call_deferred(ui_base, -1)

func _get_layer_node(layer: LayerType) -> Node:
	match layer:
		LayerType.HUD:
			return hud_layer
		LayerType.GAME:
			return game_layer
		_:
			push_error("Unknown layer type: " + str(layer))
			return null

func _pop_all_views() -> void:
	for view in _pushed_views.duplicate():
		if is_instance_valid(view):
			pop_view(view)
	_pushed_views.clear()

func _release_all_view_models() -> void:
	for vm in _view_models.values():
		vm.teardown()
	_view_models.clear()
	_view_model_ref_counts.clear()

func _disconnect_ui_on_top_signal() -> void:
	if _ui_order_connected and root_node() and root_node().child_order_changed.is_connected(_ensure_ui_on_top):
		root_node().child_order_changed.disconnect(_ensure_ui_on_top)
	_ui_order_connected = false

func _free_ui_tree() -> void:
	if ui_base:
		if ui_base.is_inside_tree():
			ui_base.queue_free()
		else:
			ui_base.free.call_deferred()
	ui_base = null
	hud_layer = null
	game_layer = null
