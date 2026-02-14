class_name GoapGoal
extends Resource

@export var goal_name: String = ""
@export var priority: int = 0

## Note: Using untyped Dictionary to avoid Godot 4.x StringName leak bug
## when deserializing typed dictionaries from .tres files
@export var desired_state: Dictionary = {}

func is_satisfied(world_state: Dictionary) -> bool:
	for key in desired_state.keys():
		if not world_state.has(key):
			return false
		if world_state[key] != desired_state[key]:
			return false
	return true

## Static factory method for creating goals with less boilerplate
static func create(p_goal_name: String, p_priority: int, p_desired_state: Dictionary) -> GoapGoal:
	var goal := GoapGoal.new()
	goal.goal_name = p_goal_name
	goal.priority = p_priority
	goal.desired_state = p_desired_state
	return goal

