extends GdUnitTestSuite
## Unit tests for spawner system

## Core: AuthoringSpawner correctly bakes recipe_id to CSpawner component
func test_authoring_spawner_bakes_recipe_id() -> void:
	var authoring := AuthoringSpawner.new()
	authoring.spawn_recipe_id = "enemy_basic"
	authoring.spawn_interval = 3.0
	authoring.max_spawn_count = 5
	
	var entity := Entity.new()
	authoring.bake(entity)
	
	var spawner: CSpawner = entity.get_component(CSpawner)
	assert_object(spawner).is_not_null()
	assert_str(spawner.spawn_recipe_id).is_equal("enemy_basic")
	assert_float(spawner.spawn_interval).is_equal(3.0)
	assert_int(spawner.max_spawn_count).is_equal(5)
	
	entity.free()
	authoring.free()

## Core: Empty recipe_id should not cause issues
func test_spawner_with_empty_recipe_id() -> void:
	var authoring := AuthoringSpawner.new()
	
	var entity := Entity.new()
	authoring.bake(entity)
	
	var spawner: CSpawner = entity.get_component(CSpawner)
	assert_object(spawner).is_not_null()
	assert_str(spawner.spawn_recipe_id).is_equal("")
	
	entity.free()
	authoring.free()
