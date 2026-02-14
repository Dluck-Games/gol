class_name GoapAction_ReturnToCamp
extends GoapAction

## Guard duty: Return to camp when too far away
## Priority: Guard duty > Chasing enemies

func _init() -> void:
	action_name = "ReturnToCamp"
	cost = 1.0
	preconditions = {
		"is_guard": true
	}
	effects = {
		"at_guard_post": true  # Back to guard post
	}

func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform)
	var movement := agent_entity.get_component(CMovement)
	var guard: CGuard = agent_entity.get_component(CGuard)
	
	if transform == null or movement == null or guard == null:
		return true
	
	var camp_pos := _get_camp_position(guard, transform)
	var direction_to_camp: Vector2 = (camp_pos - transform.position)
	var distance_to_camp: float = direction_to_camp.length()
	
	# Check if we're back at guard post (use guard_post_threshold for consistency with SSemanticTranslation)
	if distance_to_camp <= guard.guard_post_threshold:
		movement.velocity = Vector2.ZERO
		update_world_state(agent_component, "at_guard_post", true)
		return true  # Back home!
	
	# Move towards camp
	movement.velocity = direction_to_camp.normalized() * movement.max_speed
	update_world_state(agent_component, "at_guard_post", false)
	
	return false  # Keep returning

func _get_camp_position(guard: CGuard, transform: CTransform) -> Vector2:
	# Try to get camp position from guard target entity
	if guard != null and guard.guard_target != null and is_instance_valid(guard.guard_target):
		var target_transform: CTransform = guard.guard_target.get_component(CTransform)
		if target_transform != null:
			return target_transform.position
			
	return transform.position
