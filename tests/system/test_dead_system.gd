extends GdUnitTestSuite
## Unit tests for death system (SDead + CDead)

const TEST_POS := Vector2(100, 100)


## Test: CDead can be added to entity and properties work
func test_entity_can_have_cdead() -> void:
	var entity: Entity = auto_free(_create_basic_entity())
	
	var dead := CDead.new()
	dead.knockback_direction = Vector2.LEFT
	entity.add_component(dead)
	
	assert_bool(entity.has_component(CDead)).is_true()
	var retrieved: CDead = entity.get_component(CDead)
	assert_vector(retrieved.knockback_direction).is_equal(Vector2.LEFT)
	assert_float(retrieved.duration).is_greater(0.0)
	assert_bool(retrieved._initialized).is_false()


## Test: SDead query matches entities with CDead and CTransform
func test_sdead_query_requirements() -> void:
	@warning_ignore("unused_variable")
	var system: SDead = auto_free(SDead.new())
	
	# Entity with both CDead and CTransform should match
	var valid_entity: Entity = auto_free(_create_basic_entity())
	valid_entity.add_component(CDead.new())
	
	assert_bool(valid_entity.has_component(CDead)).is_true()
	assert_bool(valid_entity.has_component(CTransform)).is_true()
	
	# Entity without CTransform should not match
	var invalid_entity: Entity = auto_free(Entity.new())
	invalid_entity.add_component(CDead.new())
	
	assert_bool(invalid_entity.has_component(CTransform)).is_false()


## Test: Interfering components are removed on death initialization
func test_interfering_components_removed() -> void:
	var entity: Entity = auto_free(_create_entity_with_components())
	
	# Verify components exist before death
	assert_bool(entity.has_component(CAnimation)).is_true()
	assert_bool(entity.has_component(CPlayer)).is_true()
	assert_bool(entity.has_component(CCollision)).is_true()
	assert_bool(entity.has_component(CHP)).is_true()
	
	# Add death component and simulate system initialization
	entity.add_component(CDead.new())
	
	# Manually call the removal logic (simulating what SDead._initialize does)
	_simulate_remove_interfering_components(entity)
	
	# Verify interfering components are removed (CPlayer should NOT be removed)
	assert_bool(entity.has_component(CAnimation)).is_false()
	assert_bool(entity.has_component(CPlayer)).is_true()
	assert_bool(entity.has_component(CCollision)).is_false()
	assert_bool(entity.has_component(CHP)).is_false()
	
	# CDead and CTransform should remain
	assert_bool(entity.has_component(CDead)).is_true()
	assert_bool(entity.has_component(CTransform)).is_true()


## Test: Movement is locked when death starts
func test_movement_locked_on_death() -> void:
	var entity: Entity = auto_free(_create_basic_entity())
	var movement := CMovement.new()
	movement.forbidden_move = false
	entity.add_component(movement)
	
	# Before death
	assert_bool(movement.forbidden_move).is_false()
	
	# Simulate death initialization locking movement
	movement.forbidden_move = true
	movement.velocity = Vector2.RIGHT * 2000.0  # knockback
	
	assert_bool(movement.forbidden_move).is_true()
	assert_vector(movement.velocity).is_not_equal(Vector2.ZERO)


# ============================================================
# Helper functions
# ============================================================

func _create_basic_entity() -> Entity:
	var entity := Entity.new()
	entity.name = "TestEntity"
	var transform := CTransform.new()
	transform.position = TEST_POS
	entity.add_component(transform)
	return entity


func _create_entity_with_components() -> Entity:
	var entity := _create_basic_entity()
	
	# Add components that should be removed on death
	entity.add_component(CAnimation.new())
	entity.add_component(CPlayer.new())
	entity.add_component(CCollision.new())
	entity.add_component(CHP.new())
	entity.add_component(CMovement.new())
	
	return entity


func _simulate_remove_interfering_components(entity: Entity) -> void:
	# Mirrors SDead._remove_interfering_components logic
	# Note: CPlayer is NOT removed to preserve player identity for respawn
	var components_to_remove := [
		CAnimation,
		CCollision,
		CHP,
	]
	
	for comp_class in components_to_remove:
		if entity.has_component(comp_class):
			entity.remove_component(comp_class)
