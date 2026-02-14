class_name CGuard
extends Component

## Guard component: Defines guard behavior parameters and patrol state
## Used by Survivors to manage patrol, leash distances, and guard post detection

## Patrol radius around camp - how far to wander when patrolling
@export var patrol_radius: float = 150.0

## Maximum distance from camp before returning - leash distance
@export var camp_leash_distance: float = 500.0

## Distance threshold for determining if waypoint is reached
@export var waypoint_reach_threshold: float = 10.0

## Distance threshold for determining if at guard post
@export var guard_post_threshold: float = 50.0

## Additional buffer distance before marking guard as "away" once it already
## considered itself at the post. Prevents thrashing at the boundary.
@export var guard_post_hysteresis: float = 600.0

## Whether guard semantic translation is enabled
@export var enabled: bool = true

## The entity being guarded (e.g., campfire)
var guard_target: Entity = null

## Current patrol waypoint (null if none assigned)
var patrol_waypoint: Variant = null  # Vector2 or null

## Internal state: tracks previous at_guard_post value for hysteresis
@warning_ignore("unused_private_class_variable")
var _at_post_prev: bool = true
