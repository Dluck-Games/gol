extends GdUnitTestSuite
## Pure GOAP planning path tests for enemy AI

const ENEMY_RECIPE := preload("res://resources/recipes/enemy_basic.tres")

func _create_enemy_agent() -> CGoapAgent:
	var agent := CGoapAgent.new()
	var recipe_agent: CGoapAgent = ENEMY_RECIPE.get_component(CGoapAgent)
	if recipe_agent:
		agent.goals = recipe_agent.goals.duplicate()
	return agent

## Core: Enemy plans attack chain when threat detected
func test_plan_attack_when_threat_detected() -> void:
	var agent := _create_enemy_agent()
	agent.world_state.update_fact("has_threat", true)

	var planner := GoapPlanner.new()
	var plan := planner.build_plan(agent.world_state.facts, agent.goals)

	# ClearThreat goal (priority 10) should produce a plan
	assert_object(plan).is_not_null()
	if plan == null:
		return
	assert_int(plan.steps.size()).is_greater(0)

## Core: Enemy plans action when no threat (e.g., wander to find threat)
func test_plan_action_when_no_threat() -> void:
	var agent := _create_enemy_agent()
	agent.world_state.update_fact("has_threat", false)

	var planner := GoapPlanner.new()
	var plan := planner.build_plan(agent.world_state.facts, agent.goals)

	assert_object(plan).is_not_null()
	if plan == null:
		return
	assert_int(plan.steps.size()).is_greater(0)
