class_name GoapAction_Patrol
extends GoapAction

## Patrol action: Continuous patrol behavior for guards
## Reads/writes patrol waypoint from CGuard component
## Never completes - continuously patrols until interrupted by higher priority goal

func _init() -> void:
	action_name = "Patrol"
	cost = 1.0
	
	preconditions = {
		"is_guard": true,
		"at_guard_post": true,
	}
	
	# Unreachable effect - patrol never truly "completes"
	# Similar to Wander's "has_threat: true"
	effects = {
		"is_patrolling": true
	}

func on_plan_exit(context: Dictionary) -> void:
	# Clear patrol data when plan exits (e.g., threat detected)
	var agent_entity: Entity = context.get("agent_entity")
	if agent_entity == null:
		return
	
	var guard: CGuard = agent_entity.get_component(CGuard)
	if guard != null:
		guard.patrol_waypoint = null

func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform)
	var movement := agent_entity.get_component(CMovement)
	var guard := agent_entity.get_component(CGuard)
	
	if transform == null or movement == null or guard == null:
		return true
	
	var guard_pos := _get_guard_post_position(guard, transform)
	
	# Get or assign waypoint from CGuard
	if not guard.patrol_waypoint is Vector2:
		guard.patrol_waypoint = _generate_patrol_waypoint(guard_pos, guard)
	
	var waypoint: Vector2 = guard.patrol_waypoint as Vector2
	var distance_to_waypoint: float = transform.position.distance_to(waypoint)
	
	# Check if reached waypoint
	if distance_to_waypoint <= guard.waypoint_reach_threshold:
		# Waypoint reached - assign new one immediately
		guard.patrol_waypoint = _generate_patrol_waypoint(guard_pos, guard)
		waypoint = guard.patrol_waypoint as Vector2
	
	# Move toward waypoint
	var direction: Vector2 = (waypoint - transform.position).normalized()
	movement.velocity = direction * movement.get_patrol_speed()
	return false  # Never completes

func _get_guard_post_position(guard: CGuard, fallback_transform: CTransform) -> Vector2:
	if guard.guard_target != null and is_instance_valid(guard.guard_target):
		var target_transform: CTransform = guard.guard_target.get_component(CTransform)
		if target_transform != null:
			return target_transform.position
	return fallback_transform.position

func _generate_patrol_waypoint(guard_pos: Vector2, guard: CGuard) -> Vector2:
	var random_angle := randf() * TAU
	var random_dist := randf() * guard.patrol_radius
	var offset := Vector2(cos(random_angle), sin(random_angle)) * random_dist
	var new_waypoint := guard_pos + offset
	
	# Clamp to leash distance
	var distance_from_camp := guard_pos.distance_to(new_waypoint)
	if distance_from_camp > guard.camp_leash_distance:
		new_waypoint = guard_pos + (new_waypoint - guard_pos).normalized() * guard.camp_leash_distance * 0.8
	
	return new_waypoint
