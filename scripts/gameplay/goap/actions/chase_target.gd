class_name GoapAction_ChaseTarget
extends GoapAction

## Chase target: Move toward blackboard target_entity until within desired range

func _init() -> void:
	action_name = "ChaseTarget"
	cost = 1.0
	preconditions = {
		"has_threat": true
	}
	effects = {
		"is_threat_in_attack_range": true,
		"ready_melee_attack": true
	}

func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform)
	var movement := agent_entity.get_component(CMovement)
	var weapon := agent_entity.get_component(CWeapon)

	if transform == null or movement == null:
		return true

	var target_entity := _acquire_target_from_perception(agent_entity)
	if target_entity == null:
		movement.velocity = Vector2.ZERO
		erase_blackboard(agent_component, "threat_entity")
		_set_chase_effects(agent_component, false, false)
		return true

	if not is_instance_valid(target_entity) or target_entity.is_queued_for_deletion():
		movement.velocity = Vector2.ZERO
		erase_blackboard(agent_component, "threat_entity")
		_set_chase_effects(agent_component, false, false)
		return true

	var target_transform: CTransform = target_entity.get_component(CTransform)
	if target_transform == null:
		movement.velocity = Vector2.ZERO
		erase_blackboard(agent_component, "threat_entity")
		_set_chase_effects(agent_component, false, false)
		return true

	set_blackboard(agent_component, "threat_entity", target_entity)

	var direction: Vector2 = target_transform.position - transform.position
	var distance_to_target: float = direction.length()
	var normalized_direction: Vector2 = Vector2.ZERO
	if distance_to_target > 0.0:
		normalized_direction = direction.normalized()

	# Check melee readiness (only if has CMelee component)
	var melee := agent_entity.get_component(CMelee) as CMelee
	var melee_ready: bool = melee != null and distance_to_target <= melee.ready_range
	
	# Check ranged readiness
	var ranged_ready: bool = false
	if weapon != null:
		var ranged_activation_distance: float = weapon.get_comfortable_range_max() + 40.0
		ranged_ready = distance_to_target <= ranged_activation_distance

	if melee_ready or ranged_ready:
		movement.velocity = Vector2.ZERO
		agent_component.blackboard["entity_to_attack"] = agent_component.blackboard.get("threat_entity", null)
		_set_chase_effects(agent_component, ranged_ready, melee_ready)
		return true

	movement.velocity = normalized_direction * movement.max_speed
	_set_chase_effects(agent_component, false, false)
	return false

func _acquire_target_from_perception(agent_entity: Entity) -> Entity:
	var perception := agent_entity.get_component(CPerception)
	if perception == null:
		return null
	
	# Simply use the nearest enemy from perception
	return perception.nearest_enemy

func _set_chase_effects(agent_component: CGoapAgent, ranged_ready: bool, melee_ready: bool) -> void:
	update_world_state(agent_component, "is_threat_in_attack_range", ranged_ready or melee_ready)
	update_world_state(agent_component, "ready_melee_attack", melee_ready)
