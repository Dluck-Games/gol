class_name SAI
extends System

# Shared planner instance (stateless, can be reused across all agents)
var _planner: GoapPlanner = GoapPlanner.new()

func _ready() -> void:
	group = "gameplay"

func query() -> QueryBuilder:
	return q.with_all([CGoapAgent, CMovement, CTransform])

func process(entity: Entity, delta: float) -> void:
	var agent: CGoapAgent = entity.get_component(CGoapAgent)
	var world_state := agent.world_state

	var active_goal := _select_active_goal(agent, world_state)
	if active_goal == null:
		if agent.plan != null or agent.running_action != null:
			_reset_agent(agent)
		return

	var replan_reason := _needs_replan(agent, active_goal, world_state)
	if replan_reason != "":
		if agent.running_action != null:
			_finish_current_action(agent)
		if not _try_build_plan(agent, world_state):
			_reset_agent(agent)
			return

	if agent.plan == null:
		_reset_agent(agent)
		return

	if agent.plan.is_empty() and agent.running_action == null:
		_reset_agent(agent)
		return

	if agent.running_action == null:
		if not _are_next_action_preconditions_met(agent, world_state):
			agent.plan_invalidated = true
			agent.plan_invalidated_reason = "Next action preconditions unmet"
			return
		_start_next_action(agent, entity, agent.plan)
		if agent.running_action == null:
			_reset_agent(agent)
			return

	var action_completed := agent.running_action.perform(entity, agent, delta, agent.running_context)

	if agent.plan_invalidated:
		_reset_agent(agent)
		return

	if action_completed:
		_finish_current_action(agent)
		if agent.plan == null or agent.plan.is_empty():
			_reset_agent(agent)
			return
		else:
			if not _are_next_action_preconditions_met(agent, world_state):
				agent.plan_invalidated = true
				agent.plan_invalidated_reason = "Next action preconditions unmet"
				return
			_start_next_action(agent, entity, agent.plan)
			if agent.running_action == null:
				_reset_agent(agent)
				return

func _start_next_action(agent: CGoapAgent, entity: Entity, plan: GoapPlan) -> void:
	var next_step := plan.pop_step()
	if next_step == null:
		return
	agent.running_action = next_step.action
	agent.running_context = next_step.context.duplicate(true)
	agent.running_action.on_plan_enter(entity, agent, agent.running_context)

func _finish_current_action(agent: CGoapAgent) -> void:
	if agent.running_action != null:
		agent.running_action.on_plan_exit(agent.running_context)
		agent.running_action = null
		agent.running_context.clear()

func _reset_agent(agent: CGoapAgent) -> void:
	if agent.running_action != null:
		_finish_current_action(agent)
	agent.plan = null
	agent.running_action = null
	agent.running_context.clear()
	agent.blackboard.clear()
	agent.plan_invalidated = false
	agent.plan_invalidated_reason = ""

func _set_plan(agent: CGoapAgent, new_plan: GoapPlan) -> void:
	agent.plan = new_plan
	if agent.plan != null:
		agent.plan.reset()

func _needs_replan(agent: CGoapAgent, active_goal: GoapGoal, world_state: GoapWorldState) -> String:
	if agent.plan == null:
		return "No plan"
	if agent.plan.goal == null:
		return "Higher priority goal activated"
	if agent.plan.goal != active_goal:
		return "Higher priority goal activated"
	if agent.plan.goal.is_satisfied(world_state.facts):
		return "Goal already satisfied"
	if agent.plan_invalidated:
		return agent.plan_invalidated_reason if agent.plan_invalidated_reason != "" else "Plan invalidated"
	if not _is_current_plan_valid(agent, world_state):
		return "Plan preconditions invalid"
	return ""

func _is_current_plan_valid(agent: CGoapAgent, world_state: GoapWorldState) -> bool:
	if agent.plan == null:
		return false
	if agent.running_action != null:
		return agent.running_action.are_preconditions_met(world_state.facts)
	return _are_next_action_preconditions_met(agent, world_state)

func _are_next_action_preconditions_met(agent: CGoapAgent, world_state: GoapWorldState) -> bool:
	if agent.plan == null:
		return false
	var next_step := agent.plan.next_step()
	if next_step == null or next_step.action == null:
		return false
	return next_step.action.are_preconditions_met(world_state.facts)

func _try_build_plan(agent: CGoapAgent, world_state: GoapWorldState) -> bool:
	var new_plan := _planner.build_plan(world_state.facts, agent.goals)
	if new_plan == null:
		return false
	_set_plan(agent, new_plan)
	agent.plan_invalidated = false
	agent.plan_invalidated_reason = ""
	return true

func _select_active_goal(agent: CGoapAgent, world_state: GoapWorldState) -> GoapGoal:
	var sorted_goals := agent.goals.duplicate()
	sorted_goals.sort_custom(func(a: GoapGoal, b: GoapGoal):
		return a.priority > b.priority
	)
	for goal in sorted_goals:
		if goal == null:
			continue
		if not goal.is_satisfied(world_state.facts):
			return goal
	return null
