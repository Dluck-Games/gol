extends GdUnitTestSuite


func test_chase_stops_when_in_ranged_range() -> void:
	var agent_entity := _create_chase_agent_with_weapon()
	auto_free(agent_entity)
	var perception := agent_entity.get_component(CPerception) as CPerception
	var agent := agent_entity.get_component(CGoapAgent) as CGoapAgent

	var target := _create_target(Vector2(175.0, 0.0))
	auto_free(target)
	perception.nearest_enemy = target

	var action := GoapAction_ChaseTarget.new()
	var result := action.perform(agent_entity, agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(agent.world_state.get_fact("is_threat_in_attack_range", false)).is_true()
	assert_bool(agent.world_state.get_fact("ready_melee_attack", true)).is_false()


func test_chase_stops_when_in_melee_range() -> void:
	var agent_entity := _create_chase_agent_with_melee(40.0)
	auto_free(agent_entity)
	var perception := agent_entity.get_component(CPerception) as CPerception
	var agent := agent_entity.get_component(CGoapAgent) as CGoapAgent

	var target := _create_target(Vector2(30.0, 0.0))
	auto_free(target)
	perception.nearest_enemy = target

	var action := GoapAction_ChaseTarget.new()
	var result := action.perform(agent_entity, agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(agent.world_state.get_fact("ready_melee_attack", false)).is_true()


func test_chase_moves_when_far() -> void:
	var agent_entity := _create_chase_agent_with_weapon()
	auto_free(agent_entity)
	var perception := agent_entity.get_component(CPerception) as CPerception
	var agent := agent_entity.get_component(CGoapAgent) as CGoapAgent
	var movement := agent_entity.get_component(CMovement) as CMovement

	var target := _create_target(Vector2(500.0, 0.0))
	auto_free(target)
	perception.nearest_enemy = target

	var action := GoapAction_ChaseTarget.new()
	var result := action.perform(agent_entity, agent, 0.0, {})

	assert_bool(result).is_false()
	assert_float(movement.velocity.length()).is_equal(movement.max_speed)


func test_chase_stops_when_no_target() -> void:
	var agent_entity := _create_chase_agent_with_weapon()
	auto_free(agent_entity)
	var perception := agent_entity.get_component(CPerception) as CPerception
	var agent := agent_entity.get_component(CGoapAgent) as CGoapAgent
	perception.nearest_enemy = null

	var action := GoapAction_ChaseTarget.new()
	var result := action.perform(agent_entity, agent, 0.0, {})

	assert_bool(result).is_true()
	assert_bool(agent.blackboard.has("threat_entity")).is_false()


func _create_chase_agent_with_weapon() -> Entity:
	var entity := Entity.new()
	var transform := CTransform.new()
	var movement := CMovement.new()
	var agent := CGoapAgent.new()
	var perception := CPerception.new()
	var weapon := CWeapon.new()
	weapon.attack_range = 140.0
	entity.add_components([transform, movement, agent, perception, weapon])
	perception.owner_entity = entity
	return entity


func _create_chase_agent_with_melee(ready_range: float) -> Entity:
	var entity := Entity.new()
	var transform := CTransform.new()
	var movement := CMovement.new()
	var agent := CGoapAgent.new()
	var perception := CPerception.new()
	var melee := CMelee.new()
	melee.ready_range = ready_range
	entity.add_components([transform, movement, agent, perception, melee])
	perception.owner_entity = entity
	return entity


func _create_target(position: Vector2) -> Entity:
	var entity := Entity.new()
	var transform := CTransform.new()
	transform.position = position
	entity.add_component(transform)
	return entity
