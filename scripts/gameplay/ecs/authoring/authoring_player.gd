@tool
class_name AuthoringPlayer
extends AuthoringPawn

const DEFAULT_RECIPE_ID := "player"

## Player specific settings (override recipe defaults)
@export var pickup_look_distance: float = 128.0
@export var lifetime: float = 600.0


func _get_default_recipe_id() -> String:
	return DEFAULT_RECIPE_ID


func bake(entity: Entity) -> void:
	super.bake(entity)
	
	# Override with custom settings
	var pickup: CPickup = entity.get_component(CPickup)
	if pickup:
		pickup.look_distance = pickup_look_distance
	
	# Add lifetime component (not in recipe)
	var lifetime_comp: CLifeTime = get_or_add_component(entity, CLifeTime)
	lifetime_comp.lifetime = lifetime
	
	# Add aim component for UI binding
	get_or_add_component(entity, CAim)
