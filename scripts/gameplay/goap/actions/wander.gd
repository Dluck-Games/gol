class_name GoapAction_Wander
extends GoapAction

func _init() -> void:
	action_name = "Wander"
	cost = 10.0
	preconditions = {}
	effects = {
		"has_threat": true
	}

func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform)
	var movement := agent_entity.get_component(CMovement)
	if transform == null or movement == null:
		return true

	var perception := agent_entity.get_component(CPerception)
	var target_entity: Entity = perception.nearest_enemy if perception else null
	
	if target_entity != null:
		_store_target(agent_component, target_entity)
		movement.velocity = Vector2.ZERO
		return true

	_clear_target(agent_component)
	_perform_wander(agent_component, transform, movement)
	return false

func _perform_wander(agent_component: CGoapAgent, transform: CTransform, movement: CMovement) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var next_time: float = get_blackboard(agent_component, "wander_next_time", 0.0)
	var current_target: Vector2 = get_blackboard(agent_component, "wander_target", transform.position)

	if now >= next_time:
		var random_direction := Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0)
		if random_direction == Vector2.ZERO:
			random_direction = Vector2.ONE
		random_direction = random_direction.normalized()
		current_target = transform.position + random_direction * Config.GOAP_WANDER_RADIUS
		set_blackboard(agent_component, "wander_target", current_target)
		set_blackboard(agent_component, "wander_next_time", now + Config.GOAP_WANDER_INTERVAL)

	var direction: Vector2 = current_target - transform.position
	if direction.length() < 4.0:
		movement.velocity = Vector2.ZERO
		return

	movement.velocity = direction.normalized() * movement.get_wander_speed()

func _store_target(agent_component: CGoapAgent, target_entity: Entity) -> void:
	agent_component.blackboard["threat_entity"] = weakref(target_entity)

func _clear_target(agent_component: CGoapAgent) -> void:
	agent_component.blackboard.erase("threat_entity")
