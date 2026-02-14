class_name GoapAction_AdjustShootPosition
extends GoapAction

## Adjust position for optimal ranged shooting: maintain comfortable range and avoid friendly fire

func _init() -> void:
	action_name = "AdjustShootPosition"
	cost = 1.0
	preconditions = {
		"has_shooter_weapon": true,
		"has_threat": true,
		"is_threat_in_attack_range": true
	}
	effects = {
		"ready_ranged_attack": true
	}

func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform) as CTransform
	var movement := agent_entity.get_component(CMovement) as CMovement
	var weapon := agent_entity.get_component(CWeapon) as CWeapon
	var perception := agent_entity.get_component(CPerception) as CPerception
	
	if transform == null or movement == null or weapon == null or perception == null:
		return true

	var target_entity := perception.nearest_enemy
	if target_entity == null:
		_halt_adjustment(agent_component, movement, weapon)
		return true

	var target_transform: CTransform = target_entity.get_component(CTransform)
	if target_transform == null:
		_halt_adjustment(agent_component, movement, weapon)
		return true

	var direction_to_target := target_transform.position - transform.position
	var distance_to_target := direction_to_target.length()
	var normalized_direction := direction_to_target.normalized() if distance_to_target > 0.0 else Vector2.ZERO

	var lower_bound := weapon.get_comfortable_range_min()
	var upper_bound := weapon.get_comfortable_range_max()
	
	# Too close, back away
	if distance_to_target < lower_bound:
		movement.velocity = -normalized_direction * movement.get_adjust_speed()
		weapon.can_fire = false
		return false
	
	# Too far, move closer
	if distance_to_target > upper_bound:
		movement.velocity = normalized_direction * movement.get_adjust_speed()
		weapon.can_fire = false
		return false

	# In comfortable range, check line of fire for friendlies
	if _has_friendly_in_line_of_fire(agent_entity, normalized_direction, distance_to_target):
		# Friendly fire risk! Move perpendicular to find better angle
		var perpendicular := Vector2(-normalized_direction.y, normalized_direction.x)
		movement.velocity = perpendicular * movement.get_adjust_speed()
		weapon.can_fire = false
		return false
	
	# Safe to fire: In comfortable range and no friendlies in line of fire
	movement.velocity = Vector2.ZERO
	weapon.can_fire = true
	update_world_state(agent_component, "ready_ranged_attack", true)
	return true

func _halt_adjustment(agent_component: CGoapAgent, movement: CMovement, weapon: CWeapon) -> void:
	movement.velocity = Vector2.ZERO
	weapon.can_fire = false
	update_world_state(agent_component, "ready_ranged_attack", false)

## Check if there are friendly units in the line of fire
## Returns true if shooting would risk hitting a friendly
func _has_friendly_in_line_of_fire(agent_entity: Entity, fire_direction: Vector2, target_distance: float) -> bool:
	var perception := agent_entity.get_component(CPerception) as CPerception
	if perception == null:
		return false
	
	var agent_transform := agent_entity.get_component(CTransform) as CTransform
	if agent_transform == null:
		return false
	
	# Check each visible friendly for line of fire collision
	for candidate in perception.get_visible_friendlies():
		var candidate_transform := candidate.get_component(CTransform) as CTransform
		if candidate_transform == null:
			continue
		
		var to_candidate := candidate_transform.position - agent_transform.position
		var candidate_distance := to_candidate.length()
		
		# Only check entities between us and the target
		if candidate_distance >= target_distance:
			continue
		
		# Check if candidate is in our line of fire (dot product for alignment)
		var candidate_direction := to_candidate.normalized()
		var alignment := candidate_direction.dot(fire_direction)
		
		# If alignment > 0.9 (~25 degrees cone), candidate is in line of fire
		if alignment > 0.9:
			# Calculate perpendicular distance from fire line
			var perpendicular_distance: float = abs(to_candidate.x * fire_direction.y - to_candidate.y * fire_direction.x)
			# If within 50 units of the fire line, it's a risk
			if perpendicular_distance < 50.0:
				return true
	
	return false
