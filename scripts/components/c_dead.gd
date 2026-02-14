class_name CDead
extends Component

## Dead component - marks entity for death
## Adding this component triggers death sequence via Tween animation

# Configuration
@export var duration: float = 1.0

# Runtime state (set by SDamage/SLife when adding component)
var knockback_direction: Vector2 = Vector2.ZERO

# Internal state (managed by SDead)
@warning_ignore("unused_private_class_variable")
var _initialized: bool = false
@warning_ignore("unused_private_class_variable")
var _tween: Tween = null
