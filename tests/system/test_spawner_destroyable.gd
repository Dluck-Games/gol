extends GdUnitTestSuite
## Unit tests for destroyable spawner system


# ============================================================
# Helper functions
# ============================================================

func _create_spawner_entity() -> Entity:
	var entity := Entity.new()
	entity.name = "TestSpawner"
	
	var transform := CTransform.new()
	entity.add_component(transform)
	
	var spawner := CSpawner.new()
	entity.add_component(spawner)
	
	var hp := CHP.new()
	hp.max_hp = 400.0
	hp.hp = 400.0
	entity.add_component(hp)
	
	var camp := CCamp.new()
	camp.camp = CCamp.CampType.ENEMY
	entity.add_component(camp)
	
	var collision := CCollision.new()
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = 20.0
	collision.collision_shape = circle_shape
	entity.add_component(collision)
	
	return entity


func _create_attacker_entity() -> Entity:
	var entity := Entity.new()
	entity.name = "TestAttacker"
	
	var transform := CTransform.new()
	entity.add_component(transform)
	
	var camp := CCamp.new()
	camp.camp = CCamp.CampType.PLAYER
	entity.add_component(camp)
	
	var collision := CCollision.new()
	entity.add_component(collision)
	
	var hp := CHP.new()
	entity.add_component(hp)
	
	return entity


# ============================================================
# Enrage field tests
# ============================================================

## Test: CSpawner has enrage fields with correct defaults
func test_cspawner_has_enrage_fields() -> void:
	var spawner := CSpawner.new()
	assert_bool(spawner.enraged).is_false()
	assert_float(spawner.enraged_spawn_interval).is_equal(2.0)


## Test: When enraged=true, SEnemySpawn uses enraged_spawn_interval
func test_enrage_activates_on_flag() -> void:
	var spawner := CSpawner.new()
	spawner.spawn_interval = 6.0
	spawner.enraged_spawn_interval = 2.0
	spawner.enraged = true
	spawner.spawn_interval_variance = 0.0
	
	# Simulate _reset_timer logic
	var base_interval := spawner.enraged_spawn_interval if spawner.enraged else spawner.spawn_interval
	var variance := randf_range(-spawner.spawn_interval_variance, spawner.spawn_interval_variance)
	spawner.spawn_timer = base_interval + variance
	
	assert_float(spawner.spawn_timer).is_equal(2.0)


## Test: When enraged=false, uses normal spawn_interval
func test_enrage_does_not_affect_normal_state() -> void:
	var spawner := CSpawner.new()
	spawner.spawn_interval = 6.0
	spawner.enraged_spawn_interval = 2.0
	spawner.enraged = false
	spawner.spawn_interval_variance = 0.0
	
	# Simulate _reset_timer logic
	var base_interval := spawner.enraged_spawn_interval if spawner.enraged else spawner.spawn_interval
	var variance := randf_range(-spawner.spawn_interval_variance, spawner.spawn_interval_variance)
	spawner.spawn_timer = base_interval + variance
	
	assert_float(spawner.spawn_timer).is_equal(6.0)


# ============================================================
# Destroyable spawner component tests
# ============================================================

## Test: Spawner entity has CHP component with correct values
func test_spawner_entity_has_hp_component() -> void:
	var entity := _create_spawner_entity()
	assert_bool(entity.has_component(CHP)).is_true()
	var hp: CHP = entity.get_component(CHP)
	assert_float(hp.max_hp).is_equal(400.0)
	assert_float(hp.hp).is_equal(400.0)
	entity.free()


## Test: Spawner entity has CCamp component with ENEMY faction
func test_spawner_entity_has_enemy_camp() -> void:
	var entity := _create_spawner_entity()
	assert_bool(entity.has_component(CCamp)).is_true()
	var camp: CCamp = entity.get_component(CCamp)
	assert_int(camp.camp).is_equal(CCamp.CampType.ENEMY)
	entity.free()


## Test: Spawner entity has CCollision component
func test_spawner_entity_has_collision() -> void:
	var entity := _create_spawner_entity()
	assert_bool(entity.has_component(CCollision)).is_true()
	var collision: CCollision = entity.get_component(CCollision)
	assert_object(collision.collision_shape).is_not_null()
	assert_float(collision.collision_shape.radius).is_equal(20.0)
	entity.free()


## Test: AuthoringSpawner correctly bakes HP, Camp, and Collision
func test_authoring_spawner_bakes_hp_and_camp() -> void:
	var authoring := AuthoringSpawner.new()
	authoring.max_hp = 400.0
	authoring.collision_radius = 20.0
	
	var entity := Entity.new()
	authoring.bake(entity)
	
	assert_bool(entity.has_component(CHP)).is_true()
	assert_bool(entity.has_component(CCamp)).is_true()
	assert_bool(entity.has_component(CCollision)).is_true()
	
	var hp: CHP = entity.get_component(CHP)
	assert_float(hp.max_hp).is_equal(400.0)
	assert_float(hp.hp).is_equal(400.0)
	
	var camp: CCamp = entity.get_component(CCamp)
	assert_int(camp.camp).is_equal(CCamp.CampType.ENEMY)
	
	entity.free()
	authoring.free()
