extends GdUnitTestSuite
## Isolated test to verify recipe loading doesn't cause memory leak

# Test loading all goals from file - should have no leaks after fix
func test_load_all_goals_no_leak() -> void:
	var goal1 = load("res://resources/goals/survive.tres")
	var goal2 = load("res://resources/goals/guard_duty.tres")
	var goal3 = load("res://resources/goals/eliminate_threat.tres")
	var goal4 = load("res://resources/goals/patrol_camp.tres")
	assert_object(goal1).is_not_null()
	assert_object(goal2).is_not_null()
	assert_object(goal3).is_not_null()
	assert_object(goal4).is_not_null()
	print("Loaded 4 goals without memory leak")


# Test loading survivor recipe with goals - should have no leaks
func test_load_survivor_recipe_no_leak() -> void:
	var recipe: EntityRecipe = load("res://resources/recipes/survivor.tres") as EntityRecipe
	assert_object(recipe).is_not_null()
	assert_int(recipe.components.size()).is_greater(0)
	print("Loaded survivor recipe with %d components" % recipe.components.size())
