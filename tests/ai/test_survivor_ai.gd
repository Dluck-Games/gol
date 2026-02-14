extends GdUnitTestSuite
## Pure GOAP planning path tests - no entity creation, just planner logic validation

const SURVIVOR_RECIPE := preload("res://resources/recipes/survivor.tres")

#region Test Helpers

func _create_guard_agent() -> CGoapAgent:
	var agent := CGoapAgent.new()
	var recipe_agent: CGoapAgent = SURVIVOR_RECIPE.get_component(CGoapAgent)
	if recipe_agent:
		agent.goals = recipe_agent.goals.duplicate()
	return agent

#endregion

#region Planning Path Tests

func test_plan_attack_ranged_when_threat_detected_and_safe() -> void:
	# Scenario: Guard is safe, at post, has threat - should plan attack chain
	var agent := _create_guard_agent()
	agent.world_state.update_fact("is_guard", true)
	agent.world_state.update_fact("is_safe", true)
	agent.world_state.update_fact("at_guard_post", true)
	agent.world_state.update_fact("has_shooter_weapon", true)
	agent.world_state.update_fact("has_threat", true)

	var planner := GoapPlanner.new()
	var plan := planner.build_plan(agent.world_state.facts, agent.goals)

	# Expected chain: ChaseTarget -> AdjustShootPosition -> AttackRanged
	assert_object(plan).is_not_null()
	if plan == null:
		return
	assert_int(plan.steps.size()).is_greater(0)
	var last_action := plan.steps[plan.steps.size() - 1].action
	assert_str(last_action.action_name).is_equal("AttackRanged")

func test_plan_return_to_camp_when_away_from_post() -> void:
	# Scenario: Guard is away from camp, safe, no threat - should return to camp
	var agent := _create_guard_agent()
	agent.world_state.update_fact("is_guard", true)
	agent.world_state.update_fact("at_guard_post", false)  # Away from camp
	agent.world_state.update_fact("is_safe", true)
	agent.world_state.update_fact("has_threat", false)  # No threat - EliminateThreat satisfied

	var planner := GoapPlanner.new()
	var plan := planner.build_plan(agent.world_state.facts, agent.goals)

	# Should plan ReturnToCamp to satisfy GuardDuty goal
	assert_object(plan).is_not_null()
	if plan == null:
		return
	assert_bool(plan.steps.any(func(s): return s.action.action_name == "ReturnToCamp")).is_true()

func test_plan_patrol_when_at_camp_and_safe() -> void:
	# Scenario: Guard at camp, safe, no threat, waypoint not visited - should patrol
	var agent := _create_guard_agent()
	agent.world_state.update_fact("is_guard", true)
	agent.world_state.update_fact("at_guard_post", true)
	agent.world_state.update_fact("is_safe", true)
	agent.world_state.update_fact("has_threat", false)  # No threat - EliminateThreat satisfied

	var planner := GoapPlanner.new()
	var plan := planner.build_plan(agent.world_state.facts, agent.goals)

	# Should plan Patrol (not Wander) to satisfy PatrolCamp goal
	assert_object(plan).is_not_null()
	if plan == null:
		return
	assert_int(plan.steps.size()).is_greater(0)
	assert_bool(plan.steps.any(func(s): return s.action.action_name == "Patrol")).is_true()
	assert_bool(plan.steps.any(func(s): return s.action.action_name == "Wander")).is_false()

func test_plan_flee_when_unsafe() -> void:
	# Scenario: Guard is not safe - should flee (highest priority Survive goal)
	var agent := _create_guard_agent()
	agent.world_state.update_fact("is_safe", false)  # Unsafe!

	var planner := GoapPlanner.new()
	var plan := planner.build_plan(agent.world_state.facts, agent.goals)

	# Should plan Flee to satisfy Survive goal (priority 100)
	assert_object(plan).is_not_null()
	if plan == null:
		return
	assert_bool(plan.steps.any(func(s): return s.action.action_name == "Flee")).is_true()

#endregion
