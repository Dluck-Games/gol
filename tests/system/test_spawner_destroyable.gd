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
	entity.add_component(hp)
	
	var camp := CCamp.new()
	camp.camp = CCamp.CampType.ENEMY
	entity.add_component(camp)
	
	var collision := CCollision.new()
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
