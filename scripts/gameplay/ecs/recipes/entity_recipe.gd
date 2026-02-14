## EntityRecipe Resource
##
## A data-driven resource that defines an entity's components and their initial values.
## Supports inheritance to allow child recipes to override parent component data.
@tool
@icon("res://addons/gecs/assets/entity.svg")
class_name EntityRecipe
extends Resource


## Unique identifier for this recipe (auto-generated from filename)
@export var recipe_id: String = "":
	get = get_recipe_id

## Display name for editor/debugging
@export var display_name: String = ""

## Optional base recipe to inherit from
@export var base_recipe: EntityRecipe = null

## Component data stored as an array
@export var components: Array[Component] = []


## Auto-generate recipe_id from filename
func get_recipe_id() -> String:
	if recipe_id.is_empty() and not resource_path.is_empty():
		return resource_path.get_file().get_basename()
	return recipe_id


## Get all components including inherited ones
## Returns a dictionary with merged component data (child overrides parent)
func get_merged_components() -> Dictionary:
	var merged: Dictionary = {}
	
	# First, get base recipe components (recursive)
	if base_recipe:
		merged = base_recipe.get_merged_components()
	
	# Then override with our own components
	for comp in components:
		if comp:
			var comp_path = comp.get_script().resource_path
			# Duplicate to avoid modifying the original resource
			merged[comp_path] = comp.duplicate(true)
	
	return merged


## Add a component to this recipe
func add_component(component: Component) -> void:
	if not component:
		push_error("EntityRecipe: Cannot add null component")
		return
	
	components.append(component)


## Remove a component from this recipe
func remove_component(component_script: Script) -> void:
	for i in range(components.size() - 1, -1, -1):
		if components[i].get_script() == component_script:
			components.remove_at(i)


## Check if this recipe has a specific component (including inherited)
func has_component(component_script: Script) -> bool:
	# Check local first
	for comp in components:
		if comp.get_script() == component_script:
			return true
	
	# Check base recipe
	if base_recipe:
		return base_recipe.has_component(component_script)
	
	return false


## Get a component from this recipe (including inherited)
func get_component(component_script: Script) -> Component:
	# Check local first
	for comp in components:
		if comp.get_script() == component_script:
			return comp
	
	# Check base recipe
	if base_recipe:
		return base_recipe.get_component(component_script)
	
	return null


## Validate this recipe
func validate() -> bool:
	if recipe_id.is_empty():
		push_error("EntityRecipe: recipe_id cannot be empty")
		return false
	
	# Check for circular inheritance
	if _has_circular_inheritance():
		push_error("EntityRecipe: Circular inheritance detected for '%s'" % recipe_id)
		return false
	
	return true


## Check for circular inheritance
func _has_circular_inheritance(visited: Array = []) -> bool:
	if self in visited:
		return true
	
	if not base_recipe:
		return false
	
	visited.append(self)
	return base_recipe._has_circular_inheritance(visited)


## Debug string representation
func _to_string() -> String:
	var base_info = ""
	if base_recipe:
		base_info = " (base: %s)" % base_recipe.recipe_id
	
	return "EntityRecipe[%s]%s with %d components" % [recipe_id, base_info, components.size()]
