extends GdUnitTestSuite

const Utils = preload("res://tests/ai/actions/goap_action_test_utils.gd")

func test_attack_ranged_stops_when_too_close() -> void:
	var setup := Utils.build_agent({"weapon": true, "perception": true})
	auto_free(setup.entity)
	var target: Entity = auto_free(Utils.create_target(Vector2(40.0, 0.0)))
	setup.perception.nearest_enemy = target

	var action := GoapAction_AttackRanged.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(setup.weapon.can_fire).is_false()

func test_attack_ranged_stops_when_too_far() -> void:
	var setup := Utils.build_agent({"weapon": true, "perception": true})
	auto_free(setup.entity)
	var target: Entity = auto_free(Utils.create_target(Vector2(270.0, 0.0)))
	setup.perception.nearest_enemy = target

	var action := GoapAction_AttackRanged.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(setup.weapon.can_fire).is_false()
