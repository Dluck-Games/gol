class_name GoapPlan
extends RefCounted

var goal: GoapGoal
var steps: Array[GoapPlanStep] = []
var current_step_index: int = 0

func is_empty() -> bool:
	if steps.is_empty():
		return true
	if current_step_index >= steps.size():
		return true
	return false

func next_step() -> GoapPlanStep:
	if steps.is_empty():
		return null
	if current_step_index >= steps.size():
		return null
	return steps[current_step_index]

func pop_step() -> GoapPlanStep:
	if steps.is_empty():
		return null
	if current_step_index >= steps.size():
		return null
	var step := steps[current_step_index]
	current_step_index += 1
	return step

func remaining_steps() -> int:
	return max(steps.size() - current_step_index, 0)

func reset() -> void:
	current_step_index = 0
