extends GdUnitTestSuite

const CAMP_POS := Vector2.ZERO

func before() -> void:
	GOL.setup()

func after() -> void:
	GOL.teardown()

func test_campfire_destruction_triggers_game_over() -> void:
	# 1. Arrange: Create Campfire entity with 1 HP
	var campfire_entity = auto_free(_create_campfire(CAMP_POS, 1))
	
	# 2. Act: Reduce HP to 0 and trigger game over
	_apply_damage(campfire_entity, 1)
	
	# 3. Assert: Game Over is triggered
	assert_bool(GOL.Game.is_game_over).is_true()

func _create_campfire(position: Vector2, hp_value: int) -> Entity:
	var entity := Entity.new()
	entity.name = "Campfire"
	
	var transform := CTransform.new()
	transform.position = position
	
	var campfire := CCampfire.new()
	
	var hp := CHP.new()
	hp.max_hp = hp_value
	hp.hp = hp_value
	
	entity.add_components([transform, campfire, hp])
	
	return entity

func _apply_damage(target_entity: Entity, amount: float) -> void:
	# Simulate damage logic
	var hp = target_entity.get_component(CHP)
	hp.hp = max(hp.hp - amount, 0)
	
	# Trigger game over when campfire is destroyed
	if hp.hp <= 0 and target_entity.has_component(CCampfire):
		GOL.Game.handle_campfire_destroyed()
