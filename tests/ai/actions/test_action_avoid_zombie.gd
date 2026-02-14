extends GdUnitTestSuite

const Utils = preload("res://tests/ai/actions/goap_action_test_utils.gd")

func test_flee_completes_when_no_threats() -> void:
	var setup := Utils.build_agent({"perception": true, "camp": CCamp.CampType.PLAYER})
	auto_free(setup.entity)
	setup.perception.nearest_enemy = null

	var action := GoapAction_Flee.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(setup.agent.world_state.get_fact("is_safe", false)).is_true()

func test_flee_moves_away_from_close_enemy() -> void:
	var setup := Utils.build_agent({"perception": true, "camp": CCamp.CampType.PLAYER})
	auto_free(setup.entity)
	var threat: Entity = auto_free(Utils.create_target(Vector2(10.0, 0.0), CCamp.CampType.ENEMY))
	setup.perception.nearest_enemy = threat

	var action := GoapAction_Flee.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_false()
	assert_float(setup.movement.velocity.x).is_less(0.0)

func test_flee_stops_at_safe_distance() -> void:
	var setup := Utils.build_agent({"perception": true, "camp": CCamp.CampType.PLAYER})
	auto_free(setup.entity)
	var threat: Entity = auto_free(Utils.create_target(Vector2(74.0, 0.0), CCamp.CampType.ENEMY))
	setup.perception.nearest_enemy = threat

	var action := GoapAction_Flee.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(setup.agent.world_state.get_fact("is_safe", false)).is_true()
