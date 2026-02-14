class_name GoapAction
extends RefCounted

var action_name: String = "UnnamedAction"
var cost: float = 1.0
var preconditions: Dictionary[String, bool] = {}
var effects: Dictionary[String, bool] = {}

func are_preconditions_met(world_state: Dictionary[String, bool]) -> bool:
	for key in preconditions.keys():
		if not world_state.has(key):
			return false
		if world_state[key] != preconditions[key]:
			return false
	return true

func simulate(world_state: Dictionary[String, bool]) -> Dictionary[String, bool]:
	var simulated_state := world_state.duplicate(true)
	apply_effects_in_place(simulated_state)
	return simulated_state

func apply_effects_in_place(world_state: Dictionary[String, bool]) -> void:
	for key in effects.keys():
		world_state[key] = effects[key]

func on_plan_enter(_agent_entity: Entity, _agent_component: CGoapAgent, _context: Dictionary) -> void:
	pass

func on_plan_exit(_context: Dictionary) -> void:
	pass

@warning_ignore("unused_parameter")
func perform(_agent_entity: Entity, _agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	return true

func fail_plan(agent_component: CGoapAgent, reason: String = "") -> void:
	agent_component.plan_invalidated = true
	agent_component.plan_invalidated_reason = reason

func update_world_state(agent_component: CGoapAgent, key: String, value: bool) -> void:
	agent_component.world_state.update_fact(key, value)

func set_blackboard(agent_component: CGoapAgent, key: String, value) -> void:
	agent_component.blackboard[key] = value

func get_blackboard(agent_component: CGoapAgent, key: String, default_value = null):
	return agent_component.blackboard.get(key, default_value)

func erase_blackboard(agent_component: CGoapAgent, key: String) -> void:
	agent_component.blackboard.erase(key)
