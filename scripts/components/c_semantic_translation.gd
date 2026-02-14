class_name CSemanticTranslation
extends Component

## Semantic Translation component: Configures how perception data is translated to world_state
## This is a pure data container for translation configuration

## Distance threshold for determining safety
## If no hostile entities are within this distance, the entity is considered safe
@export var safe_distance: float = CWeapon.DEFAULT_MELEE_RANGE * CWeapon.RANGE_RATIO_SAFE

## Whether this entity should translate perception into world_state facts
@export var enabled: bool = true
