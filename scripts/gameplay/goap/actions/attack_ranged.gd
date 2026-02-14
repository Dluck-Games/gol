class_name GoapAction_AttackRanged
extends GoapAction

## Execute ranged attack: Enable weapon firing

func _init() -> void:
	action_name = "AttackRanged"
	cost = 1.0
	preconditions = {
		"has_shooter_weapon": true,
		"ready_ranged_attack": true
	}
	effects = {
		"has_threat": false,
		"is_safe": true
	}

func on_plan_enter(agent_entity: Entity, _agent_component: CGoapAgent, context: Dictionary) -> void:
	context["agent_entity"] = agent_entity

func on_plan_exit(context: Dictionary) -> void:
	var agent_entity: Entity = context.get("agent_entity", null)
	if agent_entity != null and is_instance_valid(agent_entity):
		var weapon := agent_entity.get_component(CWeapon)
		if weapon != null:
			weapon.can_fire = false

func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform) as CTransform
	var movement := agent_entity.get_component(CMovement) as CMovement
	var weapon := agent_entity.get_component(CWeapon) as CWeapon
	var perception := agent_entity.get_component(CPerception) as CPerception
	
	if transform == null or movement == null or weapon == null or perception == null:
		return true

	var target_entity := perception.nearest_enemy
	if target_entity == null:
		_stop_attacking(agent_component, movement, weapon)
		return true

	var target_transform: CTransform = target_entity.get_component(CTransform) as CTransform
	if target_transform == null:
		_stop_attacking(agent_component, movement, weapon)
		return true
	
	var distance_to_target := transform.position.distance_to(target_transform.position)
	var min_range := weapon.get_comfortable_range_min()
	var max_range := weapon.get_comfortable_range_max()
	
	if distance_to_target > max_range or distance_to_target < min_range:
		# Target out of optimal range: stop firing and signal replanning
		_stop_attacking(agent_component, movement, weapon)
		return true
	
	# Stop and fire
	movement.velocity = Vector2.ZERO
	weapon.can_fire = true
	update_world_state(agent_component, "ready_ranged_attack", true)
	
	# Continue attacking
	return false

func _stop_attacking(agent_component: CGoapAgent, movement: CMovement, weapon: CWeapon) -> void:
	movement.velocity = Vector2.ZERO
	weapon.can_fire = false
	update_world_state(agent_component, "ready_ranged_attack", false)

