class_name SDamage
extends System

# ============================================================
# Hit Effect Parameters - Adjust these for combat feel tuning
# ============================================================
# Visual Effects
const FLASH_RISE_TIME: float = 0.05         # Time to reach full flash
const FLASH_FADE_TIME: float = 0.15         # Time to fade flash
const DISSOLVE_PEAK: float = 0.3            # Maximum dissolve amount (0-1)
const DISSOLVE_TIME: float = 0.1            # Time for dissolve effect

# Knockback
const KNOCKBACK_FORCE: float = 2000.0       # Knockback impulse strength
# ============================================================

var _hit_flash_material: ShaderMaterial = preload("res://resources/hit_flash.tres")

func _ready() -> void:
	group = "gameplay"


func _process_pending_damage(target_entity: Entity) -> void:
	var damage: CDamage = target_entity.get_component(CDamage)
	if not damage:
		return
	
	_take_damage(target_entity, damage.amount, damage.knockback_direction)
	target_entity.remove_component(CDamage)


func query() -> QueryBuilder:
	return q.with_any([CBullet, CDamage])


func process(entity: Entity, _delta: float) -> void:
	if entity.has_component(CDamage):
		_process_pending_damage(entity)
	
	if entity.has_component(CBullet) and entity.has_component(CCollision):
		_process_bullet_collision(entity)


func _process_bullet_collision(bullet_entity: Entity) -> void:
	var collision: CCollision = bullet_entity.get_component(CCollision)
	var overlapped_entities: Array = collision.get_all_overlapped_entities()
	if overlapped_entities.is_empty():
		return

	# Get bullet's owner to prevent self-hit
	var bullet: CBullet = bullet_entity.get_component(CBullet)
	var owner_entity: Entity = bullet.owner_entity if bullet else null
	
	# Filter out the bullet owner (prevent self-hit)
	var valid_targets: Array = []
	for entity in overlapped_entities:
		if entity != owner_entity:
			valid_targets.append(entity)
	
	if valid_targets.is_empty():
		return

	var bullet_transform: CTransform = bullet_entity.get_component(CTransform)
	var closest_entity: Entity = _find_closest_entity(bullet_transform.position, valid_targets)
	
	if not closest_entity:
		return

	# Calculate knockback direction based on bullet's flying direction
	var knockback_dir: Vector2 = Vector2.ZERO
	var bullet_movement: CMovement = bullet_entity.get_component(CMovement)
	if bullet_movement and bullet_movement.velocity.length_squared() > 0.01:
		# Use bullet's velocity direction for knockback
		knockback_dir = bullet_movement.velocity.normalized()
	else:
		# Fallback: use direction from bullet to target
		var bullet_pos: Vector2 = bullet_transform.position
		var target_transform: CTransform = closest_entity.get_component(CTransform)
		if target_transform:
			knockback_dir = (target_transform.position - bullet_pos).normalized()
	
	_take_damage(closest_entity, 10, knockback_dir)
	_apply_bullet_effects(bullet_entity, closest_entity)
	
	ECS.world.remove_entity(bullet_entity)


func _apply_bullet_effects(bullet_entity: Entity, target_entity: Entity) -> void:
	var bullet: CBullet = bullet_entity.get_component(CBullet)
	if bullet.type == CBullet.BulletType.SNOWBALL:
		var movement: CMovement = target_entity.get_component(CMovement)
		if movement:
			movement.forbidden_move = true
			movement.velocity = Vector2.ZERO


func _find_closest_entity(origin_position: Vector2, entities: Array) -> Entity:
	var closest_entity: Entity = null
	var min_dist_sq: float = INF

	for entity_to_check in entities:
		var transform: CTransform = entity_to_check.get_component(CTransform)
		if not transform:
			continue
		
		var dist_sq: float = origin_position.distance_squared_to(transform.position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest_entity = entity_to_check
			
	return closest_entity


func _take_damage(target_entity: Entity, amount: float, knockback_direction: Vector2 = Vector2.ZERO) -> void:
	var hp: CHP = target_entity.get_component(CHP)
	if not hp:
		return
	
	hp.hp = max(0, hp.hp - amount)
	
	# Play hit blink effect
	_play_hit_blink(target_entity)
	
	# Apply knockback (except for player)
	_apply_knockback(target_entity, knockback_direction)
	
	if hp.hp == 0:
		_on_no_hp(target_entity)


func _on_no_hp(target_entity: Entity) -> void:
	# Check if death already in progress
	if target_entity.has_component(CDead):
		return
	
	# Campfire death or component loss system
	if target_entity.has_component(CCampfire):
		_start_death(target_entity, Vector2.ZERO)
		return
	
	# Try to lose a component first
	var comps_to_lose: Component = _get_random_component(target_entity)
	if comps_to_lose:
		print("Lose Component: ", target_entity, ' -> ', comps_to_lose.get_script().resource_path)
		target_entity.remove_component(comps_to_lose.get_script())
	else:
		# No components left to lose - trigger death
		var movement: CMovement = target_entity.get_component(CMovement)
		var last_knockback := movement.velocity.normalized() if movement else Vector2.ZERO
		_start_death(target_entity, last_knockback)


func _get_random_component(entity: Entity) -> Component:
	var comps_can_be_lost: Array[Variant] = []
	for comp in entity.components.values():
		if !ECSUtils.is_base_component(comp):
			comps_can_be_lost.append(comp)
	if comps_can_be_lost.is_empty():
		return null
	return comps_can_be_lost.pick_random()


func _play_hit_blink(target_entity: Entity) -> void:
	# Find the sprite node (either Sprite2D or AnimatedSprite2D)
	var sprite_node: CanvasItem = null
	
	for child in target_entity.get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			sprite_node = child
			break
	
	if not sprite_node:
		return
	
	# Apply shader material if not already set
	if not sprite_node.material or not sprite_node.material is ShaderMaterial:
		sprite_node.material = _hit_flash_material.duplicate()
	
	var mat: ShaderMaterial = sprite_node.material as ShaderMaterial
	
	# Create shader-based flash effect with dissolve
	var tween := create_tween()
	tween.set_parallel(true)
	
	# Flash intensity: quick flash then fade
	tween.tween_method(
		func(value: float): mat.set_shader_parameter("flash_intensity", value),
		0.0, 1.0, FLASH_RISE_TIME
	)
	tween.tween_method(
		func(value: float): mat.set_shader_parameter("flash_intensity", value),
		1.0, 0.0, FLASH_FADE_TIME
	).set_delay(FLASH_RISE_TIME)
	
	# Dissolve effect for extra impact
	tween.tween_method(
		func(value: float): mat.set_shader_parameter("dissolve_amount", value),
		0.0, DISSOLVE_PEAK, DISSOLVE_TIME
	)
	tween.tween_method(
		func(value: float): mat.set_shader_parameter("dissolve_amount", value),
		DISSOLVE_PEAK, 0.0, DISSOLVE_TIME
	).set_delay(DISSOLVE_TIME)


func _apply_knockback(target_entity: Entity, direction: Vector2) -> void:
	# Don't apply knockback to player or if no direction
	var camp: CCamp = target_entity.get_component(CCamp)
	if camp and camp.camp == CCamp.CampType.PLAYER:
		return
	
	if direction.length_squared() < 0.01:
		return
	
	var movement: CMovement = target_entity.get_component(CMovement)
	if not movement:
		return
	
	# Apply knockback as velocity impulse
	# The large impulse will naturally overcome AI/player input for a moment
	# Then friction and acceleration will bring it back to normal
	movement.velocity += direction * KNOCKBACK_FORCE


func _kill_entity(target_entity: Entity) -> void:
	var pawn: CCamp = target_entity.get_component(CCamp)
	var is_player_faction := pawn and pawn.camp == CCamp.CampType.PLAYER

	if is_player_faction:
		if target_entity.has_component(CCampfire):
			print("[SDamage] Campfire destroyed -> game over")
			if GOL and GOL.Game:
				GOL.Game.handle_campfire_destroyed()
			else:
				push_warning("[SDamage] GOL.Game not available for campfire destruction!")
		else:
			if GOL and GOL.Game:
				GOL.Game.handle_player_down()
			else:
				push_warning("[SDamage] GOL.Game not available for respawn!")
			return

	print("[SDamage] Kill Entity: ", target_entity)
	ECSUtils.remove_entity(target_entity)


func _start_death(target_entity: Entity, knockback_dir: Vector2) -> void:
	"""Add CDead component to trigger death sequence"""
	var dead := CDead.new()
	dead.knockback_direction = knockback_dir
	target_entity.add_component(dead)
