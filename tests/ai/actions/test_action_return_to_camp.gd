extends GdUnitTestSuite

const Utils = preload("res://tests/ai/actions/goap_action_test_utils.gd")

func _make_guard_anchor(position: Vector2) -> Entity:
	var anchor := Entity.new()
	var transform := CTransform.new()
	transform.position = position
	anchor.add_component(transform)
	auto_free(anchor)
	return anchor

func test_return_to_camp_completes_when_close() -> void:
	var setup := Utils.build_agent({"guard": true, "position": Vector2(10.0, 0.0)})
	auto_free(setup.entity)
	setup.guard.guard_target = _make_guard_anchor(Vector2.ZERO)

	var action := GoapAction_ReturnToCamp.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(setup.agent.world_state.get_fact("at_guard_post", false)).is_true()

func test_return_to_camp_moves_when_far() -> void:
	var setup := Utils.build_agent({"guard": true, "position": Vector2(400.0, 0.0)})
	auto_free(setup.entity)
	setup.guard.guard_target = _make_guard_anchor(Vector2.ZERO)

	var action := GoapAction_ReturnToCamp.new()
	var result := action.perform(setup.entity, setup.agent, 0.0, {})

	assert_bool(result).is_false()
	assert_float(setup.movement.velocity.length()).is_equal(setup.movement.max_speed)
