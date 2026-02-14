@tool
class_name AuthoringNode2D
extends Node2D


const PREVIEW_NODE_NAME := "_AuthoringPreviewSprite"
const PREVIEW_ICON: Texture2D = preload("res://addons/gecs/assets/entity.svg")
const DEFAULT_COLLISION_RADIUS := 16.0

var _preview_texture: Texture2D = PREVIEW_ICON

## Optional recipe ID to use as base configuration for this entity.
## Subclasses can override _get_default_recipe_id() to provide a default.
@export var recipe_id: String = ""


## Helper to fetch or create a component for subclasses.
func get_or_add_component(entity: Entity, component_class) -> Component:
	return _get_or_add_component(entity, component_class)


static func _get_or_add_component(entity: Entity, component_class) -> Component:
	var comp = entity.get_component(component_class)
	if not comp:
		comp = component_class.new()
		entity.add_component(comp)
	return comp


## Override this in subclasses to provide a default recipe ID.
## Returns the recipe ID to use (export value takes priority over default).
func _get_default_recipe_id() -> String:
	return ""


## Get the effective recipe ID (export value takes priority over default).
func _get_effective_recipe_id() -> String:
	return recipe_id if not recipe_id.is_empty() else _get_default_recipe_id()


## Get the recipe from Service_Recipe by ID.
func _get_recipe() -> EntityRecipe:
	var effective_id := _get_effective_recipe_id()
	if effective_id.is_empty():
		return null
	return ServiceContext.recipe().get_recipe(effective_id)


## Base class for authoring an entity with a 2D spatial representation.
## This class bakes the node's transform properties into a [CTransform] component.
## Subclasses can extend this to add more specific view data, such as a texture.

## Converts this authoring node into ECS components and adds them to the [param entity].
## Flow: 1) Apply recipe (if any) -> 2) Bake transform -> 3) Subclass overrides
func bake(entity: Entity) -> void:
	# Step 1: Apply recipe as base configuration
	var active_recipe := _get_recipe()
	if active_recipe:
		_apply_recipe(entity, active_recipe)
	
	# Step 2: Bake transform from node position
	var transform_comp: CTransform = get_or_add_component(entity, CTransform)
	transform_comp.position = self.position
	transform_comp.rotation = self.rotation
	transform_comp.scale = self.scale
	
	# Only bake CSprite if entity doesn't have CAnimation
	# This ensures animation takes priority over static sprite
	if not entity.has_component(CAnimation):
		get_or_add_component(entity, CSprite)


## Apply recipe components to entity.
## Existing components are updated with recipe values, new components are added.
func _apply_recipe(entity: Entity, target_recipe: EntityRecipe) -> void:
	var merged := target_recipe.get_merged_components()
	for comp_path in merged:
		var comp: Component = merged[comp_path]
		var existing := entity.get_component(comp.get_script())
		if existing:
			# Copy properties from recipe to existing component
			for prop in comp.get_property_list():
				if prop.usage & PROPERTY_USAGE_STORAGE:
					existing.set(prop.name, comp.get(prop.name))
		else:
			entity.add_component(comp.duplicate(true))




## Private methods

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_update_preview_texture(null)


func _ensure_preview_sprite() -> Sprite2D:
	var preview_sprite := get_node_or_null(PREVIEW_NODE_NAME) as Sprite2D
	if preview_sprite:
		return preview_sprite

	preview_sprite = Sprite2D.new()
	preview_sprite.name = PREVIEW_NODE_NAME
	preview_sprite.owner = null
	preview_sprite.visible = true
	preview_sprite.centered = true
	add_child(preview_sprite, false, Node.INTERNAL_MODE_FRONT)
	return preview_sprite


func _update_preview_texture(custom_texture: Texture2D) -> void:
	if not Engine.is_editor_hint():
		return
	
	_preview_texture = custom_texture if custom_texture else PREVIEW_ICON
	var preview_sprite := _ensure_preview_sprite()
	preview_sprite.texture = _preview_texture
	preview_sprite.position = Vector2.ZERO
	preview_sprite.scale = Vector2.ONE
	preview_sprite.offset = Vector2.ZERO


## Creates a default circular collision shape if none is set.
## This method can be used by subclasses to ensure they have a valid collision shape.
static func create_default_collision_shape() -> CircleShape2D:
	var default_shape := CircleShape2D.new()
	default_shape.radius = DEFAULT_COLLISION_RADIUS
	return default_shape
