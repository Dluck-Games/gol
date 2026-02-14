class_name GoapAction_Flee
extends GoapAction

## Flee action: Escape from the nearest threat
## Pure survival instinct - run away to reach safety

func _init() -> void:
	action_name = "Flee"
	cost = 1.0
	preconditions = {}
	effects = {
		"is_safe": true  # Reach safety by fleeing
	}

func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform)
	var movement := agent_entity.get_component(CMovement)
	var perception := agent_entity.get_component(CPerception)
	var weapon := agent_entity.get_component(CWeapon)
	
	if transform == null or movement == null or perception == null:
		return true
	
	# Get nearest enemy from perception
	var threat_entity: Entity = perception.nearest_enemy
	
	if threat_entity == null or not is_instance_valid(threat_entity):
		# No threat, we're safe
		movement.velocity = Vector2.ZERO
		update_world_state(agent_component, "is_safe", true)
		return true
	
	var threat_transform: CTransform = threat_entity.get_component(CTransform)
	if threat_transform == null:
		movement.velocity = Vector2.ZERO
		update_world_state(agent_component, "is_safe", true)
		return true
	
	var direction_to_threat: Vector2 = (threat_transform.position - transform.position)
	var distance_to_threat: float = direction_to_threat.length()
	var safe_distance := _get_safe_distance(weapon)
	
	if distance_to_threat >= safe_distance:
		movement.velocity = Vector2.ZERO
		update_world_state(agent_component, "is_safe", true)
		return true
	
	# FLEE! Run away from threat (using full speed for escape)
	var flee_direction := Vector2.ZERO if distance_to_threat == 0.0 else -direction_to_threat.normalized()
	movement.velocity = flee_direction * movement.max_speed
	update_world_state(agent_component, "is_safe", false)
	
	return false  # Keep fleeing

func _get_safe_distance(weapon: CWeapon) -> float:
	if weapon != null:
		return weapon.get_safe_distance()
	return CWeapon.DEFAULT_MELEE_RANGE * CWeapon.RANGE_RATIO_SAFE
