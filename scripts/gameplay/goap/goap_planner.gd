class_name GoapPlanner
extends RefCounted

const ACTIONS_PATH := "res://scripts/gameplay/goap/actions/"

static var _cached_action_scripts: Array[GDScript] = []

static func get_all_actions() -> Array[GoapAction]:
	if _cached_action_scripts.is_empty():
		_cached_action_scripts = _load_all_action_scripts()
	var actions: Array[GoapAction] = []
	for script in _cached_action_scripts:
		actions.append(script.new())
	return actions


static func _load_all_action_scripts() -> Array[GDScript]:
	var scripts: Array[GDScript] = []
	var files: PackedStringArray = ResourceLoader.list_directory(ACTIONS_PATH)
	
	for file_name in files:
		# Handle .remap files in exported builds
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		
		if file_name.ends_with(".gd"):
			var script: GDScript = load(ACTIONS_PATH + file_name)
			if script and _is_concrete_goap_action(script):
				scripts.append(script)
	
	if scripts.is_empty():
		push_error("GoapPlanner: No action scripts found in: %s" % ACTIONS_PATH)
	
	return scripts


## Check if script inherits from GoapAction (directly or indirectly) and is not abstract
static func _is_concrete_goap_action(script: GDScript) -> bool:
	# Skip abstract base classes (convention: class names ending with base action types)
	var class_name_str: String = script.get_global_name()
	if class_name_str == &"GoapAction_MoveTo":
		return false  # Abstract base for movement actions
	
	# Check inheritance chain
	var current: GDScript = script.get_base_script()
	while current != null:
		if current.get_global_name() == &"GoapAction":
			return true
		current = current.get_base_script()
	return false


## Build a plan using all available actions (auto-loaded from actions directory)
func build_plan(world_state: Dictionary[String, bool], goals: Array[GoapGoal]) -> GoapPlan:
	return build_plan_with_actions(world_state, goals, get_all_actions())


## Build a plan with custom actions (for testing specific action sets)
func build_plan_with_actions(world_state: Dictionary[String, bool], goals: Array[GoapGoal], actions: Array[GoapAction]) -> GoapPlan:
	var available_goals := []
	for goal in goals:
		if goal == null:
			continue
		available_goals.append(goal)

	available_goals.sort_custom(func(a: GoapGoal, b: GoapGoal):
		return a.priority > b.priority
	)

	var available_actions: Array[GoapAction] = []
	for action in actions:
		if action == null:
			continue
		available_actions.append(action)

	for goal in available_goals:
		if goal.is_satisfied(world_state):
			continue

		var plan_steps: Array[GoapPlanStep] = _plan_for_goal(world_state, goal, available_actions)
		if plan_steps.size() > 0:
			var plan := GoapPlan.new()
			plan.goal = goal
			plan.steps = plan_steps
			plan.reset()
			return plan

	return null

func _plan_for_goal(world_state: Dictionary[String, bool], goal: GoapGoal, actions: Array[GoapAction]) -> Array[GoapPlanStep]:
	var open_list: Array = []
	var best_state_costs: Dictionary = {}

	var start_state := world_state.duplicate(true)
	var start_path: Array[GoapPlanStep] = []
	var start_h := _calculate_heuristic(goal, start_state)
	open_list.append({
		"state": start_state,
		"path": start_path,
		"g_cost": 0.0,
		"h_cost": start_h,
		"f_cost": start_h
	})

	var max_iterations := 1024
	while not open_list.is_empty() and max_iterations > 0:
		max_iterations -= 1
		
		var best_idx := 0
		var best_f_cost: float = open_list[0].f_cost
		var best_h_cost: float = open_list[0].h_cost
		for i in range(1, open_list.size()):
			var candidate = open_list[i]
			if candidate.f_cost < best_f_cost or (candidate.f_cost == best_f_cost and candidate.h_cost < best_h_cost):
				best_idx = i
				best_f_cost = candidate.f_cost
				best_h_cost = candidate.h_cost

		var current = open_list.pop_at(best_idx)
		var current_state: Dictionary[String, bool] = current.state
		var current_path: Array[GoapPlanStep] = current.path
		var current_g: float = current.g_cost

		if goal.is_satisfied(current_state):
			return current_path

		var state_key := _state_to_key(current_state)
		if best_state_costs.has(state_key) and best_state_costs[state_key] <= current_g:
			continue
		best_state_costs[state_key] = current_g

		for action in actions:
			if action == null:
				continue
			if not action.are_preconditions_met(current_state):
				continue

			var new_state := action.simulate(current_state)
			var new_state_key := _state_to_key(new_state)
			var new_g := current_g + action.cost
			if best_state_costs.has(new_state_key) and best_state_costs[new_state_key] <= new_g:
				continue

			var new_path: Array[GoapPlanStep] = current_path.duplicate()
			var plan_step := GoapPlanStep.new()
			plan_step.action = action
			new_path.append(plan_step)

			var h_cost := _calculate_heuristic(goal, new_state)
			open_list.append({
				"state": new_state,
				"path": new_path,
				"g_cost": new_g,
				"h_cost": h_cost,
				"f_cost": new_g + h_cost
			})

	return []

func _calculate_heuristic(goal: GoapGoal, state: Dictionary[String, bool]) -> float:
	var unsatisfied := 0.0
	for key in goal.desired_state.keys():
		if not state.has(key):
			unsatisfied += 1.0
			continue
		if state[key] != goal.desired_state[key]:
			unsatisfied += 1.0
	return unsatisfied

func _state_to_key(state: Dictionary[String, bool]) -> String:
	var keys := state.keys()
	keys.sort()
	var key_parts: Array[String] = []
	for k in keys:
		key_parts.append(k + "=" + str(state[k]))
	return ",".join(key_parts)
