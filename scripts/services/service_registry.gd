class_name ServiceRegistry
extends Object


var services: Dictionary= {}


func register_service(name: String, service: ServiceBase) -> void:
	services[name] = service
	
func get_service(name: String) -> ServiceBase:
	return services.get(name, null)
	
func unregister_service(name: String) -> void:
	if services.has(name):
		services.erase(name)
	
func get_service_by_class(service_class: Variant) -> ServiceBase:
	for service in services.values():
		if service.get_script() == service_class:
			return service
	return null
	
func get_all_services() -> Array[ServiceBase]:
	var result: Array[ServiceBase] = []
	result.assign(services.values())
	return result
