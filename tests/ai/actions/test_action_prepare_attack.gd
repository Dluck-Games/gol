extends GdUnitTestSuite

const Utils = preload("res://tests/ai/actions/goap_action_test_utils.gd")

func test_adjust_backpedals_when_too_close() -> void:
	var setup := Utils.build_agent({"weapon": true, "perception": true})
	auto_free(setup.entity)
	var target: Entity = auto_free(Utils.create_target(Vector2(10.0, 0.0)))
	setup.perception.nearest_enemy = target

	var action := GoapAction_AdjustShootPosition.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_false()
	assert_float(setup.movement.velocity.x).is_less(0.0)

func test_adjust_advances_when_too_far() -> void:
	var setup := Utils.build_agent({"weapon": true, "perception": true})
	auto_free(setup.entity)
	var target: Entity = auto_free(Utils.create_target(Vector2(280.0, 0.0)))
	setup.perception.nearest_enemy = target

	var action := GoapAction_AdjustShootPosition.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_false()
	assert_float(setup.movement.velocity.x).is_greater(0.0)

func test_adjust_holds_at_optimal_range() -> void:
	var setup := Utils.build_agent({"weapon": true, "perception": true})
	auto_free(setup.entity)
	var target: Entity = auto_free(Utils.create_target(Vector2(setup.weapon.attack_range, 0.0)))
	setup.perception.nearest_enemy = target

	var action := GoapAction_AdjustShootPosition.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(setup.weapon.can_fire).is_true()
