class_name SUI_Hpbar
extends System


const hp_bar_class: PackedScene = preload("res://scenes/ui/hp_bar.tscn")


var _entity_to_hp_bar_map: Dictionary = {}

func _ready() -> void:
	group = "ui"

func setup() -> void:
	if ECS.world and not ECS.world.entity_removed.is_connected(_on_entity_removed):
		ECS.world.entity_removed.connect(_on_entity_removed)
	
func teardown() -> void:
	if ECS.world and ECS.world.entity_removed.is_connected(_on_entity_removed):
		ECS.world.entity_removed.disconnect(_on_entity_removed)
	
	# View_HPBar 会自动监听 entity_removed 销毁自身，这里只需清理 map
	for hp_bar in _entity_to_hp_bar_map.values():
		if is_instance_valid(hp_bar):
			hp_bar.queue_free()
	_entity_to_hp_bar_map.clear()

func query() -> QueryBuilder:
	return q.with_all([CTransform, CHP])

func process(entity: Entity, _delta: float) -> void:
	var hp: CHP = entity.get_component(CHP)
	if hp.bound_hp_bar:
		return
	
	var view := EntityBoundView.create_from_scene(hp_bar_class, entity) as View_HPBar
	if view == null:
		return
	
	hp.bound_hp_bar = view
	_entity_to_hp_bar_map[entity] = view
	ServiceContext.ui().push_view(Service_UI.LayerType.GAME, view)
	
func _on_entity_removed(entity: Entity) -> void:
	var hp: CHP = entity.get_component(CHP)
	if not hp:
		return
	
	var hp_bar: View_HPBar = hp.bound_hp_bar
	if is_instance_valid(hp_bar):
		hp_bar.queue_free()
	if _entity_to_hp_bar_map.has(entity):
		_entity_to_hp_bar_map.erase(entity)
