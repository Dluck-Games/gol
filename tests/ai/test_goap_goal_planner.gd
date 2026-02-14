extends GdUnitTestSuite

func _create_goal(goal_name: String, priority: int, desired_state: Dictionary[String, bool]) -> GoapGoal:
	return GoapGoal.create(goal_name, priority, desired_state)

func _available_actions() -> Array[GoapAction]:
	return [
		GoapAction_Wander.new(),
		GoapAction_Flee.new(),
		GoapAction_ReturnToCamp.new(),
		GoapAction_ChaseTarget.new(),
		GoapAction_AdjustShootPosition.new(),
		GoapAction_AttackRanged.new(),
		GoapAction_AttackMelee.new(),
		GoapAction_Patrol.new()
	]

func _ranged_vs_melee_actions() -> Array[GoapAction]:
	return [
		GoapAction_ChaseTarget.new(),
		GoapAction_AdjustShootPosition.new(),
		GoapAction_AttackRanged.new(),
		GoapAction_AttackMelee.new()
	]

func test_survive_goal_has_plan() -> void:
	var planner := GoapPlanner.new()
	var survive_goal_state: Dictionary[String, bool] = {
		"is_safe": true
	}
	var goal := _create_goal("Survive", 100, survive_goal_state)
	var world_state: Dictionary[String, bool] = {
		"is_safe": false
	}
	var plan := planner.build_plan_with_actions(world_state, [goal], _available_actions())

	assert_object(plan).is_not_null()
	assert_int(plan.steps.size()).is_equal(1)
	assert_str(plan.steps[0].action.action_name).is_equal("Flee")

func test_guard_goal_has_plan() -> void:
	var planner := GoapPlanner.new()
	var guard_goal_state: Dictionary[String, bool] = {
		"at_guard_post": true
	}
	var goal := _create_goal("GuardDuty", 60, guard_goal_state)
	var world_state: Dictionary[String, bool] = {
		"is_guard": true,
		"at_guard_post": false
	}
	var plan := planner.build_plan_with_actions(world_state, [goal], _available_actions())

	assert_object(plan).is_not_null()
	assert_str(plan.steps[0].action.action_name).is_equal("ReturnToCamp")

func test_combat_goal_has_plan() -> void:
	var planner := GoapPlanner.new()
	var combat_goal_state: Dictionary[String, bool] = {
		"has_threat": false
	}
	var goal := _create_goal("EliminateThreat", 30, combat_goal_state)
	var world_state: Dictionary[String, bool] = {
		"has_threat": true,
		"is_safe": true,
		"has_shooter_weapon": true,
		"is_threat_in_attack_range": false,
		"ready_melee_attack": false,
		"ready_ranged_attack": false
	}
	var plan := planner.build_plan_with_actions(world_state, [goal], _available_actions())

	assert_object(plan).is_not_null()
	assert_bool(plan.steps.size() >= 2).is_true()
	assert_str(plan.steps[0].action.action_name).is_equal("ChaseTarget")
	# Last action should be either AttackMelee or AttackRanged depending on weapon
	var last_action_name := plan.steps[-1].action.action_name
	assert_bool(last_action_name == "AttackMelee" or last_action_name == "AttackRanged").is_true()

func test_planner_prefers_lower_cost_longer_path() -> void:
	var planner := GoapPlanner.new()
	var goal := _create_goal("ClearThreat", 50, {"has_threat": false})
	var world_state: Dictionary[String, bool] = {
		"has_threat": true,
		"has_shooter_weapon": true,
		"is_threat_in_attack_range": false,
		"ready_melee_attack": false,
		"ready_ranged_attack": false
	}
	var plan := planner.build_plan_with_actions(world_state, [goal], _ranged_vs_melee_actions())

	assert_object(plan).is_not_null()
	assert_int(plan.steps.size()).is_equal(3)
	assert_str(plan.steps[0].action.action_name).is_equal("ChaseTarget")
	assert_str(plan.steps[1].action.action_name).is_equal("AdjustShootPosition")
	assert_str(plan.steps[2].action.action_name).is_equal("AttackRanged")
	var total_cost := 0.0
	for step in plan.steps:
		total_cost += step.action.cost
	assert_float(total_cost).is_equal(3.0)

func test_guard_maintains_ranged_strategy_at_mid_distance() -> void:
	var planner := GoapPlanner.new()
	var goal := _create_goal("ClearThreat", 50, {"has_threat": false})
	var world_state: Dictionary[String, bool] = {
		"has_threat": true,
		"has_shooter_weapon": true,
		"is_threat_in_attack_range": false,
		"ready_melee_attack": false,
		"ready_ranged_attack": false
	}
	var plan := planner.build_plan_with_actions(world_state, [goal], _ranged_vs_melee_actions())
	
	assert_object(plan).is_not_null()
	assert_int(plan.steps.size()).is_greater_equal(2)
	var has_ranged := false
	var has_adjust := false
	for step in plan.steps:
		if step.action.action_name == "AttackRanged":
			has_ranged = true
		if step.action.action_name == "AdjustShootPosition":
			has_adjust = true
	assert_bool(has_ranged).is_true()
	assert_bool(has_adjust).is_true()

func test_patrol_goal_has_plan() -> void:
	var planner := GoapPlanner.new()
	var patrol_goal_state: Dictionary[String, bool] = {
		"is_patrolling": true
	}
	var goal := _create_goal("PatrolGuard", 1, patrol_goal_state)
	var world_state: Dictionary[String, bool] = {
		"is_guard": true,
		"at_guard_post": true,
		"is_safe": true,
		"is_patrolling": false
	}
	var plan := planner.build_plan_with_actions(world_state, [goal], _available_actions())

	assert_object(plan).is_not_null()
	assert_str(plan.steps[0].action.action_name).is_equal("Patrol")
