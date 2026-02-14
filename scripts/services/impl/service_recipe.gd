## Service_Recipe
##
## Service for managing and instantiating entity recipes.
## Provides centralized access to recipe resources and entity creation.
class_name Service_Recipe
extends ServiceBase


## Dictionary mapping recipe_id to EntityRecipe resources
var _recipes: Dictionary[String, EntityRecipe] = {}


## Setup the recipe service
func setup() -> void:
	_load_all_recipes()

## Teardown the recipe service
func teardown() -> void:
	_recipes.clear()

## Load all recipe resources from the recipes directory
func _load_all_recipes() -> void:
	_recipes.clear()
	
	var recipe_dir: String = "res://resources/recipes/"
	var files: PackedStringArray = ResourceLoader.list_directory(recipe_dir)
	
	for file_name in files:
		# Handle .remap files in exported builds
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		
		if file_name.ends_with(".tres"):
			_try_load_recipe(recipe_dir + file_name)
	
	if _recipes.is_empty():
		push_error("Service_Recipe: No recipes found! Check export_presets.cfg include_filter.")
	else:
		print("Service_Recipe: Loaded %d recipes" % _recipes.size())


## Try to load a recipe from path
func _try_load_recipe(recipe_path: String) -> void:
	if not ResourceLoader.exists(recipe_path):
		return
	
	var recipe: EntityRecipe = load(recipe_path) as EntityRecipe
	if recipe:
		if recipe.recipe_id.is_empty():
			push_warning("Service_Recipe: Recipe at '%s' has no recipe_id, skipping" % recipe_path)
		elif recipe.validate():
			register_recipe(recipe)
		else:
			push_error("Service_Recipe: Recipe at '%s' failed validation" % recipe_path)


## Register a recipe manually
func register_recipe(recipe: EntityRecipe) -> void:
	if not recipe:
		push_error("Service_Recipe: Cannot register null recipe")
		return
	
	if recipe.recipe_id.is_empty():
		push_error("Service_Recipe: Cannot register recipe with empty recipe_id")
		return
	
	if _recipes.has(recipe.recipe_id):
		push_warning("Service_Recipe: Overwriting existing recipe '%s'" % recipe.recipe_id)
	
	_recipes[recipe.recipe_id] = recipe


## Get a recipe by ID
func get_recipe(recipe_id: String) -> EntityRecipe:
	if recipe_id.is_empty():
		push_error("Service_Recipe: recipe_id cannot be empty")
		return null
	
	if not _recipes.has(recipe_id):
		push_error("Service_Recipe: Recipe '%s' not found" % recipe_id)
		return null
	
	return _recipes[recipe_id]


## Check if a recipe exists
func has_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id)


## Create an entity from a recipe resource
func create_entity(recipe: EntityRecipe) -> Entity:
	if not recipe:
		push_error("Service_Recipe: Cannot create entity from null recipe")
		return null
	
	if not recipe.validate():
		push_error("Service_Recipe: Recipe '%s' failed validation" % recipe.recipe_id)
		return null
	
	return _instantiate_entity(recipe)


## Create an entity from a recipe ID
func create_entity_by_id(recipe_id: String) -> Entity:
	var recipe: EntityRecipe = get_recipe(recipe_id)
	if not recipe:
		return null
	
	return create_entity(recipe)


## Internal method to instantiate an entity from a recipe
func _instantiate_entity(recipe: EntityRecipe) -> Entity:
	# Create new entity
	var entity: Entity = Entity.new()
	
	# Get merged components (includes inheritance)
	var merged_components: Dictionary = recipe.get_merged_components()
	
	# Add all components to the entity
	for comp_path in merged_components.keys():
		var comp_template = merged_components[comp_path]
		if comp_template:
			# Duplicate component to avoid shared state
			var comp_instance = comp_template.duplicate(true)
			entity.add_component(comp_instance)
	
	# Add entity to world
	ECS.world.add_entity(entity)
	
	# Set name AFTER adding to tree (add_child may rename on conflict)
	entity.name = StringName("%s@%d" % [recipe.recipe_id, entity.get_instance_id()])
	
	return entity


## Get all registered recipe IDs
func get_all_recipe_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_recipes.keys())
	return ids


## Reload all recipes from disk
func reload_recipes() -> void:
	print("Service_Recipe: Reloading all recipes...")
	_load_all_recipes()


## Debug: Print all registered recipes
func debug_print_recipes() -> void:
	print("=== Registered Recipes ===")
	for recipe_id in _recipes.keys():
		var recipe: EntityRecipe = _recipes[recipe_id]
		print("  - %s" % recipe)
	print("=========================")
