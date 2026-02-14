class_name GoapAction_MoveTo
extends GoapAction

## Generic move to target action: Move toward a blackboard position
## Subclasses can override to customize behavior and effects

## Blackboard key for target position
var target_key: String = "move_target"

## Distance threshold to consider target reached
var reach_threshold: float = 10.0

func _init() -> void:
	action_name = "MoveTo"
	cost = 1.0
	preconditions = {}
	effects = {
		"reached_move_target": true
	}

func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform)
	var movement := agent_entity.get_component(CMovement)
	
	if transform == null or movement == null:
		return true
	
	# Get target position from blackboard
	var target_pos: Variant = get_blackboard(agent_component, target_key, null)
	
	if not target_pos is Vector2:
		# No valid target, action fails
		movement.velocity = Vector2.ZERO
		return true
	
	# Calculate direction and distance to target
	var direction: Vector2 = target_pos - transform.position
	var distance: float = direction.length()
	
	# Check if reached
	if distance <= reach_threshold:
		movement.velocity = Vector2.ZERO
		return true
	
	# Move toward target
	var normalized_direction: Vector2 = direction.normalized() if distance > 0.0 else Vector2.ZERO
	movement.velocity = normalized_direction * _get_move_speed(movement)
	
	return false

## Override this to customize movement speed
func _get_move_speed(movement: CMovement) -> float:
	return movement.get_patrol_speed()
