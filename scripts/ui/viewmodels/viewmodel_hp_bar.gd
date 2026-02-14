class_name ViewModel_HPBar
extends ViewModelBase


var position : Dictionary[Entity, ObservableProperty] = {}
var hp : Dictionary[Entity, ObservableProperty] = {}
var hp_max : Dictionary[Entity, ObservableProperty] = {}


func setup() -> void:
	pass

func teardown() -> void:
	pass

func bind_to_entity(entity: Entity) -> void:
	position[entity] = ObservableProperty.new()
	position[entity].bind_component(entity, CTransform, "position")
	hp[entity] = ObservableProperty.new()
	hp[entity].bind_component(entity, CHP, "hp")
	hp_max[entity] = ObservableProperty.new()
	hp_max[entity].bind_component(entity, CHP, "max_hp")

func unbind_to_entity(entity: Entity) -> void:
	position[entity].teardown()
	position.erase(entity)
	
	hp[entity].teardown()
	hp.erase(entity)
	
	hp_max[entity].teardown()
	hp_max.erase(entity)
