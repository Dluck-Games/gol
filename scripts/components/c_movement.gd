class_name CMovement
extends Component

# ============================================================
# Movement Feel Parameters - Adjust these for game feel tuning
# ============================================================
const DEFAULT_ACCELERATION: float = 1200.0   # How fast entity speeds up
const DEFAULT_FRICTION: float = 800.0        # How fast entity slows down
const DEFAULT_MAX_SPEED: float = 140.0       # Unified maximum speed (player & AI default)

# AI Movement Speed Multipliers (based on max_speed)
const SPEED_RATE_PATROL: float = 0.3         # 30% speed when patrolling
const SPEED_RATE_WANDER: float = 0.2         # 20% speed when wandering
const SPEED_RATE_ADJUST: float = 0.9         # 90% speed when adjusting position
# ============================================================

@export var velocity: Vector2 = Vector2.ZERO

var forbidden_move: bool = false

# Physics parameters
var acceleration: float = DEFAULT_ACCELERATION
var friction: float = DEFAULT_FRICTION
@export var max_speed: float = DEFAULT_MAX_SPEED  # Expose for external adjustment

## 夜间速度倍率 (仅对敌方生效)
@export var night_speed_multiplier: float = 1.15

# AI can set this to smoothly accelerate towards a target velocity
var desired_velocity: Vector2 = Vector2.ZERO
var use_desired_velocity: bool = false  # Set to true for AI smooth movement

## Helper methods for AI speed calculation
func get_patrol_speed() -> float:
	return max_speed * SPEED_RATE_PATROL

func get_wander_speed() -> float:
	return max_speed * SPEED_RATE_WANDER

func get_adjust_speed() -> float:
	return max_speed * SPEED_RATE_ADJUST
