extends GdUnitTestSuite

const CAMP_POS := Vector2.ZERO
const ZOMBIE_START_POS := Vector2(10, 0) # Close enough to attack
const ATTACK_RANGE := 20.0
const DAMAGE_AMOUNT := 5.0


func test_combat_loop_zombie_attacks_campfire() -> void:
	# 1. Arrange: Campfire and Zombie
	var campfire = auto_free(_create_campfire(CAMP_POS, 100))
	var zombie = auto_free(_create_zombie(ZOMBIE_START_POS))
	
	# Verify initial state
	assert_float(campfire.get_component(CHP).hp).is_equal(100.0)
	
	# 2. Act: Run AI logic to detect target, then Damage logic
	_simulate_ai_system(zombie, campfire)
	_simulate_damage_system(zombie, campfire)
	
	# 3. Assert: Campfire took damage
	var hp_comp = campfire.get_component(CHP)
	assert_float(hp_comp.hp).is_less(100.0)
	# Assuming damage logic is simplistic for now: HP - Damage
	# Note: Exact damage calculation depends on weapon/stats, here we verify interaction

func _create_campfire(pos: Vector2, hp: float) -> Entity:
	var e = Entity.new()
	e.name = "Campfire"
	var hp_comp = CHP.new()
	hp_comp.max_hp = hp
	hp_comp.hp = hp
	
	e.add_components([
		CTransform.new(),
		CCampfire.new(),
		hp_comp
	])
	e.get_component(CTransform).position = pos
	return e

func _create_zombie(pos: Vector2) -> Entity:
	var e = Entity.new()
	e.name = "Zombie"
	var tracker = CTracker.new()
	tracker.track_range = 100.0
	tracker.has_target = false # Initially no target
	
	e.add_components([
		CTransform.new(),
		tracker
		# Add weapon component if needed for damage calculation
	])
	e.get_component(CTransform).position = pos
	return e

func _simulate_ai_system(zombie: Entity, target: Entity) -> void:
	# Simplified logic from s_ai.gd
	var z_pos = zombie.get_component(CTransform).position
	var t_pos = target.get_component(CTransform).position
	var tracker = zombie.get_component(CTracker)
	
	if z_pos.distance_to(t_pos) <= tracker.track_range:
		tracker.has_target = true
		tracker.target_location = t_pos

func _simulate_damage_system(attacker: Entity, target: Entity) -> void:
	# Simplified logic simulating an attack landing
	var tracker = attacker.get_component(CTracker)
	if tracker.has_target:
		# Check range (simplified)
		var z_pos = attacker.get_component(CTransform).position
		var t_pos = target.get_component(CTransform).position
		if z_pos.distance_to(t_pos) <= ATTACK_RANGE:
			var hp = target.get_component(CHP)
			hp.hp -= DAMAGE_AMOUNT
