class_name GoapAction_AttackMelee
extends GoapAction

## Execute melee attack: Set attack_direction on CMelee component for SMeleeAttack system
## Requires CMelee component on the agent entity


func _init() -> void:
	action_name = "AttackMelee"
	cost = 10.0
	preconditions = {
		"ready_melee_attack": true
	}
	effects = {
		"has_threat": false,
		"is_safe": true
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform) as CTransform
	var movement := agent_entity.get_component(CMovement) as CMovement
	
	if transform == null or movement == null:
		return true

	var melee := agent_entity.get_component(CMelee) as CMelee
	if melee == null:
		return true
	
	var perception := agent_entity.get_component(CPerception) as CPerception
	var target_entity: Entity = perception.nearest_enemy if perception else null

	if target_entity == null:
		_handle_target_gone(agent_component, movement)
		return true

	var target_transform: CTransform = target_entity.get_component(CTransform) as CTransform
	if target_transform == null:
		_handle_target_gone(agent_component, movement)
		return true
	
	var distance_to_target := transform.position.distance_to(target_transform.position)
	if distance_to_target > melee.attack_range:
		_handle_target_out_of_range(agent_component, movement)
		return true
	
	# Stop moving during attack
	movement.velocity = Vector2.ZERO
	
	# Request attack when cooldown ready and no pending attack
	if melee.cooldown_remaining <= 0.0 and not melee.attack_pending:
		melee.attack_direction = (target_transform.position - transform.position)
		melee.attack_pending = true
	
	# Continue attacking
	return false

func _clear_target(agent_component: CGoapAgent, movement: CMovement) -> void:
	movement.velocity = Vector2.ZERO
	_reset_attack_flags(agent_component)

func _handle_target_gone(agent_component: CGoapAgent, movement: CMovement) -> void:
	_clear_target(agent_component, movement)

func _handle_target_out_of_range(agent_component: CGoapAgent, movement: CMovement) -> void:
	movement.velocity = Vector2.ZERO
	_reset_attack_flags(agent_component)
	fail_plan(agent_component, "Target left melee range")

func _reset_attack_flags(agent_component: CGoapAgent) -> void:
	update_world_state(agent_component, "is_threat_in_attack_range", false)
	update_world_state(agent_component, "ready_melee_attack", false)
