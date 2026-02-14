class_name SPickup
extends System


func _ready() -> void:
	group = "gameplay"


func setup() -> void:
	pass

func teardown() -> void:
	pass

func query() -> QueryBuilder:
	return q.with_all([CPickup, CTransform])

func process(entity: Entity, _delta: float) -> void:
	var pickup: CPickup = entity.get_component(CPickup)
	_look_box(entity, pickup)
	
	var collision: CCollision = entity.get_component(CCollision)
	if not collision:
		return
	
	for overlapped_entity in collision.get_all_overlapped_entities():
		var container: CContainer = overlapped_entity.get_component(CContainer)
		
		if not container:
			continue
			
		if container.required_component:
			var comp_to_lose = entity.get_component(container.required_component.get_script())
			if not _is_valid_component_to_lose(comp_to_lose):
				continue
			entity.remove_component(comp_to_lose.get_script())
			print("LogPickup: Entity ", entity.name, " lost component: ", comp_to_lose)
			
		_open_box(entity, overlapped_entity, pickup)

func _is_valid_component_to_lose(comp: Component) -> bool:
	return comp and not ECSUtils.is_base_component(comp)

func _look_box(entity: Entity, pickup: CPickup) -> void:
	var transform: CTransform = entity.get_component(CTransform)
	
	var closest_entity: Entity = _find_closest_container(entity, transform.position, pickup.look_distance)
	pickup.focused_box.set_value(closest_entity)
	
	if closest_entity:
		_create_hint_view_if_needed(entity, pickup)
	else:
		_remove_hint_view(pickup)

func _find_closest_container(entity: Entity, center: Vector2, radius: float) -> Entity:
	var space_state := get_tree().root.world_2d.direct_space_state
	var shape_query := PhysicsShapeQueryParameters2D.new()
	var circle_shape := CircleShape2D.new()
	
	circle_shape.radius = radius
	shape_query.shape = circle_shape
	shape_query.transform = Transform2D(0, center)
	shape_query.collide_with_areas = true
	
	var results: Array = space_state.intersect_shape(shape_query)
	var closest_entity: Entity = null
	var min_dist_sq: float = INF
	
	for result in results:
		var overlapped_collider = result.get("collider")
		if not overlapped_collider:
			continue
		
		var overlapped_entity: Entity = overlapped_collider.get_parent()
		if not (overlapped_entity is Entity and overlapped_entity != entity):
			continue
		
		if not overlapped_entity.has_component(CContainer):
			continue
		
		if not overlapped_entity.has_component(CTransform):
			continue
		
		var view_box: CTransform = overlapped_entity.get_component(CTransform)
		var dist_sq: float = center.distance_squared_to(view_box.position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest_entity = overlapped_entity
	
	return closest_entity

func _open_box(entity, overlapped_entity, pickup: CPickup) -> void:
	var container: CContainer = overlapped_entity.get_component(CContainer)
	if not container:
		return
	
	print("[SPickup] LogPickup: Opening box for entity: ", entity.name, " with overlapped entity: ", overlapped_entity.name)
	
	# Create entity from recipe
	if container.stored_recipe_id.is_empty():
		push_error("SPickup: No stored_recipe_id specified in container")
		return
	
	var stored_entity: Entity = ServiceContext.recipe().create_entity_by_id(container.stored_recipe_id)
	if not stored_entity:
		push_error("SPickup: Failed to create stored entity from recipe")
		return
	
	ECS.world.remove_entity(overlapped_entity)
	ECS.world.merge_entity(stored_entity, entity)
	
	pickup.focused_box.set_value(null)


func _create_hint_view_if_needed(player_entity: Entity, pickup: CPickup) -> void:
	if pickup.box_hint_view:
		return
	
	var box_hint_scene: PackedScene = preload("res://scenes/ui/box_hint.tscn")
	var view: View_BoxHint = box_hint_scene.instantiate() as View_BoxHint
	if view == null:
		return
	
	view.set_player_entity(player_entity)
	pickup.box_hint_view = view
	ServiceContext.ui().push_view(Service_UI.LayerType.GAME, view)

func _remove_hint_view(pickup: CPickup) -> void:
	if not pickup.box_hint_view:
		return
	
	ServiceContext.ui().pop_view(pickup.box_hint_view)
	pickup.box_hint_view = null
