extends GdUnitTestSuite


func test_attack_melee_effects() -> void:
	var action := GoapAction_AttackMelee.new()
	assert_bool(action.effects.has("has_threat")).is_true()
	assert_bool(action.effects["has_threat"]).is_false()


func test_attack_melee_continues_while_in_range() -> void:
	var agent_entity := _create_melee_agent()
	auto_free(agent_entity)
	var perception := agent_entity.get_component(CPerception) as CPerception
	var agent := agent_entity.get_component(CGoapAgent) as CGoapAgent
	var movement := agent_entity.get_component(CMovement) as CMovement

	var target := _create_target(Vector2(20.0, 0.0))
	auto_free(target)
	perception.nearest_enemy = target

	var action := GoapAction_AttackMelee.new()
	var completed := action.perform(agent_entity, agent, 0.0, {})

	assert_bool(completed).is_false()
	assert_that(movement.velocity).is_equal(Vector2.ZERO)


func test_attack_melee_stops_when_out_of_range() -> void:
	var agent_entity := _create_melee_agent()
	auto_free(agent_entity)
	var perception := agent_entity.get_component(CPerception) as CPerception
	var agent := agent_entity.get_component(CGoapAgent) as CGoapAgent

	var target := _create_target(Vector2(50.0, 0.0))
	auto_free(target)
	perception.nearest_enemy = target

	var action := GoapAction_AttackMelee.new()
	var completed := action.perform(agent_entity, agent, 0.0, {})

	assert_bool(completed).is_true()
	assert_bool(agent.world_state.get_fact("ready_melee_attack", true)).is_false()


func test_attack_melee_stops_when_no_target() -> void:
	var agent_entity := _create_melee_agent()
	auto_free(agent_entity)
	var perception := agent_entity.get_component(CPerception) as CPerception
	var agent := agent_entity.get_component(CGoapAgent) as CGoapAgent
	perception.nearest_enemy = null

	var action := GoapAction_AttackMelee.new()
	var completed := action.perform(agent_entity, agent, 0.0, {})

	assert_bool(completed).is_true()


func _create_melee_agent() -> Entity:
	var entity := Entity.new()
	var transform := CTransform.new()
	var movement := CMovement.new()
	var agent := CGoapAgent.new()
	var perception := CPerception.new()
	var melee := CMelee.new()
	entity.add_components([transform, movement, agent, perception, melee])
	perception.owner_entity = entity
	return entity


func _create_target(position: Vector2) -> Entity:
	var entity := Entity.new()
	var transform := CTransform.new()
	transform.position = position
	entity.add_component(transform)
	return entity
