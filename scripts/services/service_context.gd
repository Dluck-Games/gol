# ServiceContext.gd
class_name ServiceContext
extends Object

# ---------------------
# Service Accessors
# ---------------------

static func scene() -> Service_Scene:
	return instance()._registry.get_service("scene") as Service_Scene

static func ui() -> Service_UI:
	return instance()._registry.get_service("ui") as Service_UI

static func savedata() -> Service_SaveData:
	return instance()._registry.get_service("savedata") as Service_SaveData

static func recipe() -> Service_Recipe:
	return instance()._registry.get_service("recipe") as Service_Recipe

static func console() -> Service_Console:
	return instance()._registry.get_service("console") as Service_Console

static func input() -> Service_Input:
	return instance()._registry.get_service("input") as Service_Input

static func pcg() -> Service_PCG:
	return instance()._registry.get_service("pcg") as Service_PCG

static func _defined_services() -> Array[String]:
	return ["ui", "scene", "savedata", "recipe", "console", "input", "pcg"]

# ---------------------
# Singleton
# ---------------------
static var _instance: ServiceContext

static func instance() -> ServiceContext:
	if _instance == null:
		_instance = ServiceContext.new()
	return _instance


# ---------------------
# Service Registry
# ---------------------
var _registry: ServiceRegistry
var _service_setup_order: Array[String] = []

# ---------------------
# Implementation
# ---------------------

# Bootloader Node, used for services to access the scene tree
static var root_node: Node

static func static_setup(passed_root : Node) -> void:
	root_node = passed_root
	instance().setup()

static func static_teardown() -> void:
	if _instance:
		_instance.teardown()
		_instance.free()
		_instance = null
	root_node = null

func setup() -> void:
	_dispose_registry()
	_registry = ServiceRegistry.new()
	_service_setup_order = _defined_services().duplicate()
	for service_name in _service_setup_order:
		var service_instance := _find_and_create_service(service_name)
		_registry.register_service(service_name, service_instance)
		service_instance.setup()
		print("Service setup: " + service_name)

func teardown() -> void:
	print("ServiceContext teardown starting...")
	var teardown_order := _service_setup_order.duplicate()
	teardown_order.reverse()
	for service_name in teardown_order:
		var service := _registry.get_service(service_name)
		if service:
			service.teardown()
			_registry.unregister_service(service_name)
			service.free()
	_service_setup_order.clear()
	_dispose_registry()
	print("ServiceContext teardown completed.")
		
func _dispose_registry() -> void:
	if _registry:
		_registry.services.clear()
		_registry.free()
		_registry = null

func _find_and_create_service(service_name: String) -> ServiceBase:
	var service_path := "res://scripts/services/impl/service_" + service_name + ".gd"
	var service_class = load(service_path)
	if not service_class:
		push_error("Service not found: " + service_name)
	return service_class.new()
