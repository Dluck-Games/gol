@tool
class_name AuthoringSurvivor
extends AuthoringPawn

const DEFAULT_RECIPE_ID := "survivor"

## Survivor specific settings (override recipe defaults)
@export var patrol_radius: float = 150.0
@export var max_distance_from_camp: float = 800.0


func _get_default_recipe_id() -> String:
	return DEFAULT_RECIPE_ID


func bake(entity: Entity) -> void:
	super.bake(entity)
	
	# Override with custom settings
	var guard: CGuard = entity.get_component(CGuard)
	if guard:
		guard.patrol_radius = patrol_radius
		guard.camp_leash_distance = max_distance_from_camp
		guard.guard_post_threshold = patrol_radius
