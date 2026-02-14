class_name CWeapon
extends Component

# Distance range multipliers (based on attack_range)
const RANGE_RATIO_LOWER: float = 0.4         # Lower bound for comfortable shooting (40% of range)
const RANGE_RATIO_UPPER: float = 1.0         # Upper bound (100% of range)
const RANGE_RATIO_SAFE: float = 2.0          # Safe distance from danger (2x of range)

const DEFAULT_MELEE_RANGE: float = 32.0      # Default melee attack range

@export var interval: float = 2.0
@export var bullet_speed: float = 1400.0
@export var attack_range: float = 320.0

## Recipe ID for bullet (use ServiceContext.recipe().get_recipe() to resolve)
@export var bullet_recipe_id: String = ""

var last_fire_direction: Vector2 = Vector2.UP
var time_amount_before_last_fire: float = 0.0

## Manual fire control - set by AI to control when weapon can fire
@export var can_fire: bool = true

## Helper methods for AI distance calculation
## Get the danger range (enemy's attack range, or default melee range if no weapon)
func get_danger_range() -> float:
	return max(attack_range, DEFAULT_MELEE_RANGE)

## Get safe distance (2x of danger range)
func get_safe_distance() -> float:
	return get_danger_range() * RANGE_RATIO_SAFE

## Get comfortable shooting range lower bound
func get_comfortable_range_min() -> float:
	return attack_range * RANGE_RATIO_LOWER

## Get comfortable shooting range upper bound
func get_comfortable_range_max() -> float:
	return attack_range * RANGE_RATIO_UPPER

## Check if distance is within comfortable shooting range
func is_in_comfortable_range(distance: float) -> bool:
	return distance >= get_comfortable_range_min() and distance <= get_comfortable_range_max()


## Called when merging another CWeapon component into this one
## Updates weapon properties from the incoming weapon (e.g., picking up a new weapon)
func on_merge(other: CWeapon) -> void:
	interval = other.interval
	bullet_speed = other.bullet_speed
	attack_range = other.attack_range
	bullet_recipe_id = other.bullet_recipe_id
	# Reset runtime state for the new weapon
	last_fire_direction = Vector2.UP
	time_amount_before_last_fire = 0.0
	can_fire = true
