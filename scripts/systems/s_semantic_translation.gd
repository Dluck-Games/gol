class_name SSemanticTranslation
extends System

## Semantic Translation System: Translates perception data into world_state facts
## This system runs BEFORE the AI system to prepare world_state for planning

func _ready() -> void:
	group = "gameplay"

func query() -> QueryBuilder:
	return q.with_all([CSemanticTranslation, CPerception, CTransform, CGoapAgent])

func process(entity: Entity, _delta: float) -> void:
	var semantic: CSemanticTranslation = entity.get_component(CSemanticTranslation)
	var perception: CPerception = entity.get_component(CPerception)
	var transform: CTransform = entity.get_component(CTransform)
	var agent: CGoapAgent = entity.get_component(CGoapAgent)
	
	if not semantic.enabled:
		return
	
	# Translate perception data into world_state facts
	_translate_safety(entity, perception, transform, agent, semantic)
	_translate_threat_presence(entity, perception, transform, agent)
	_translate_weapon_state(entity, agent)
	_translate_enemy_in_range(entity, perception, transform, agent)
	
	# Handle guard-specific translations
	if entity.has_component(CGuard):
		_translate_guard_state(entity, transform, agent)

## Translate safety state: is_safe
## Safe if nearest enemy is beyond safe_distance (or no enemy at all)
func _translate_safety(_entity: Entity, perception: CPerception, transform: CTransform, agent: CGoapAgent, semantic: CSemanticTranslation) -> void:
	if perception.nearest_enemy != null:
		var enemy_transform: CTransform = perception.nearest_enemy.get_component(CTransform)
		if enemy_transform != null:
			var distance := transform.position.distance_to(enemy_transform.position)
			agent.world_state.update_fact("is_safe", distance > semantic.safe_distance)
			return
			
	agent.world_state.update_fact("is_safe", true)

## Translate threat presence: has_threat
## has_threat is true if ANY hostile entities are visible
func _translate_threat_presence(_entity: Entity, perception: CPerception, _transform: CTransform, agent: CGoapAgent) -> void:
	# Simply check if there's a nearest enemy
	var has_threat := perception.nearest_enemy != null
	agent.world_state.update_fact("has_threat", has_threat)

## Translate weapon state: has_shooter_weapon
## has_shooter_weapon is true if entity has a CWeapon component
func _translate_weapon_state(entity: Entity, agent: CGoapAgent) -> void:
	var weapon: CWeapon = entity.get_component(CWeapon)
	agent.world_state.update_fact("has_shooter_weapon", weapon != null)
	
func _translate_enemy_in_range(entity: Entity, perception: CPerception, transform: CTransform, agent: CGoapAgent) -> void:
	var weapon: CWeapon = entity.get_component(CWeapon)
	if weapon == null:
		return
	
	if perception.nearest_enemy != null:
		var enemy_transform: CTransform = perception.nearest_enemy.get_component(CTransform)
		if enemy_transform != null:
			var distance := transform.position.distance_to(enemy_transform.position)
			agent.world_state.update_fact("is_threat_in_attack_range", distance <= weapon.attack_range)
			return

	agent.world_state.update_fact("is_threat_in_attack_range", false)

## Translate guard state: at_guard_post, is_guard, is_patrolling
func _translate_guard_state(entity: Entity, transform: CTransform, agent: CGoapAgent) -> void:
	var guard: CGuard = entity.get_component(CGuard)
	
	if guard == null or not guard.enabled:
		return
	
	# Initialize guard_target if not set (find nearest campfire)
	if guard.guard_target == null or not is_instance_valid(guard.guard_target):
		_assign_guard_target(guard, transform)
	
	# Always set is_guard to true for entities with guard component
	agent.world_state.update_fact("is_guard", true)
	
	# Calculate distance to guard post
	var guard_pos := _get_guard_post_position(guard, transform)
	var distance_to_post := transform.position.distance_to(guard_pos)
	
	# Apply hysteresis so small oscillations around the threshold do not
	# constantly flip GuardDuty on/off. Only mark as "away" once the entity
	# exceeded threshold + buffer; mark as "at post" once back inside threshold.
	var hysteresis: float = max(guard.guard_post_hysteresis, 0.0)
	var leave_threshold: float = guard.guard_post_threshold + hysteresis
	var at_post := guard._at_post_prev
	if guard._at_post_prev:
		if distance_to_post > leave_threshold:
			at_post = false
	else:
		if distance_to_post <= guard.guard_post_threshold:
			at_post = true
	guard._at_post_prev = at_post
	agent.world_state.update_fact("at_guard_post", at_post)

## Get guard post position (from guard target or current position)
func _get_guard_post_position(guard: CGuard, fallback_transform: CTransform) -> Vector2:
	if guard.guard_target != null and is_instance_valid(guard.guard_target):
		var target_transform: CTransform = guard.guard_target.get_component(CTransform)
		if target_transform != null:
			return target_transform.position
	return fallback_transform.position

## Assign guard target by finding the nearest campfire
func _assign_guard_target(guard: CGuard, transform: CTransform) -> void:
	var campfires := ECS.world.query.with_all([CCampfire, CTransform]).execute()
	if campfires.is_empty():
		return
	
	# Find nearest campfire
	var closest_campfire: Entity = null
	var closest_dist := INF
	
	for campfire in campfires:
		var campfire_transform: CTransform = campfire.get_component(CTransform)
		if campfire_transform == null:
			continue
		
		var dist := transform.position.distance_to(campfire_transform.position)
		if dist < closest_dist:
			closest_dist = dist
			closest_campfire = campfire
	
	if closest_campfire != null:
		guard.guard_target = closest_campfire
		print("[SSemanticTranslation] Auto-assigned guard target (campfire) at distance: ", closest_dist)
