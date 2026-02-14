class_name Service_Scene
extends ServiceBase


var _current_scene: String = ""
var _pending_scene: String = ""

func teardown() -> void:
	print("Service_Scene: Cleaning up current scene")
	_pop_ui_layers()
	if ECS.world:
		var world := ECS.world
		ECS.world = null
		world.purge()
		if world.tree_exited.is_connected(_on_world_unloaded):
			world.tree_exited.disconnect(_on_world_unloaded)
		world.queue_free()
	_current_scene = ""
	_pending_scene = ""


func switch_scene(scene_name: String) -> void:
	if _current_scene == scene_name:
		return
		
	if not scene_exist(scene_name):
		push_error("Scene does not exist: " + scene_name)

	if _current_scene != "":
		_pending_scene = scene_name
		_unload()
	else:
		_load(scene_name)

	
func scene_exist(scene_name: String) -> bool:
	var scene_path := "res://scenes/maps/l_%s.tscn" % scene_name
	return ResourceLoader.exists(scene_path)

func at_scene(scene_name) -> bool:
	return scene_name == _current_scene


### private methods ###

func _load(scene_name: String) -> void:
	if not scene_exist(scene_name):
		push_error("Service_Scene: Scene does not exist in config: " + scene_name)
		return
	
	var scene_path: String = "res://scenes/maps/l_%s.tscn" % scene_name
	_load_from_path(scene_path, scene_name)


func _load_from_path(scene_path: String, scene_name: String) -> void:
	print("Load scene: %s (path: %s)" % [scene_name, scene_path])
	
	var scene = load(scene_path).instantiate()
	
	ECS.world = scene
	_current_scene = scene_name
	_pending_scene = ""
	
func _unload() -> void:
	print("Unload scene: " + _current_scene)
	
	if ECS.world:
		_pop_ui_layers()
		var old_world: World = ECS.world
		ECS.world = null
		old_world.purge()
		if old_world.tree_exited.is_connected(_on_world_unloaded):
			old_world.tree_exited.disconnect(_on_world_unloaded)
		old_world.tree_exited.connect(_on_world_unloaded, Object.CONNECT_ONE_SHOT)
		old_world.queue_free()
	else:
		push_error("Scene not loaded: " + _current_scene)

func _on_world_unloaded():
	_current_scene = ""
	if _pending_scene != "":
		_load(_pending_scene)
	else:
		_pending_scene = ""

func _pop_ui_layers() -> void:
	var ui_service := ServiceContext.ui()
	if ui_service:
		ui_service.pop_views_by_layer(Service_UI.LayerType.HUD)
		ui_service.pop_views_by_layer(Service_UI.LayerType.GAME)
