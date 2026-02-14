extends GdUnitTestSuite

const Utils = preload("res://tests/ai/actions/goap_action_test_utils.gd")

func test_wander_stores_threat_when_enemy_visible() -> void:
	var setup := Utils.build_agent({"perception": true, "camp": CCamp.CampType.ENEMY})
	auto_free(setup.entity)
	var hostile: Entity = auto_free(Utils.create_target(Vector2(40.0, 0.0), CCamp.CampType.PLAYER))
	setup.perception.nearest_enemy = hostile

	var action := GoapAction_Wander.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(setup.agent.blackboard.has("threat_entity")).is_true()

func test_wander_moves_when_no_enemy() -> void:
	var setup := Utils.build_agent({"perception": true, "camp": CCamp.CampType.ENEMY})
	auto_free(setup.entity)
	setup.perception.nearest_enemy = null
	setup.agent.blackboard["wander_target"] = Vector2(100.0, 0.0)
	setup.agent.blackboard["wander_next_time"] = 1_000_000.0

	var action := GoapAction_Wander.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_false()
	assert_float(setup.movement.velocity.length()).is_equal(setup.movement.get_wander_speed())
