extends GdUnitTestSuite

const Utils = preload("res://tests/ai/actions/goap_action_test_utils.gd")

func test_patrol_reaches_target() -> void:
	var setup := Utils.build_agent({"guard": true})
	auto_free(setup.entity)
	setup.guard.patrol_waypoint = Vector2(30.0, 0.0)

	var action := GoapAction_Patrol.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_false()
	assert_float(setup.movement.velocity.length()).is_equal(setup.movement.get_patrol_speed())

func test_patrol_assigns_new_waypoint_when_reached() -> void:
	var setup := Utils.build_agent({"guard": true})
	auto_free(setup.entity)
	setup.guard.patrol_waypoint = Vector2(5.0, 0.0)

	var action := GoapAction_Patrol.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_false()
	assert_bool(setup.guard.patrol_waypoint is Vector2).is_true()

func test_patrol_clears_waypoint_on_exit() -> void:
	var setup := Utils.build_agent({"guard": true})
	auto_free(setup.entity)
	setup.guard.patrol_waypoint = Vector2(100.0, 50.0)
	
	var action := GoapAction_Patrol.new()
	var context := {"agent_entity": setup.entity}
	action.on_plan_exit(context)
	
	assert_bool(setup.guard.patrol_waypoint == null).is_true()
