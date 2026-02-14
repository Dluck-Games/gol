class_name GoapActionTestUtils
extends RefCounted

static func build_agent(options: Dictionary = {}) -> Dictionary:
	var position: Vector2 = options.get("position", Vector2.ZERO)
	var camp_type: CCamp.CampType = options.get("camp", CCamp.CampType.ENEMY)
	var include_weapon: bool = options.get("weapon", false)
	var include_perception: bool = options.get("perception", false)
	var include_guard: bool = options.get("guard", false)
	var include_tracker: bool = options.get("tracker", false)
	var include_melee: bool = options.get("melee", false)

	var entity := Entity.new()
	var transform := CTransform.new()
	transform.position = position
	var movement := CMovement.new()
	var camp := CCamp.new()
	camp.camp = camp_type
	var agent := CGoapAgent.new()

	entity.add_components([transform, movement, camp, agent])

	var weapon: CWeapon = null
	if include_weapon:
		weapon = CWeapon.new()
		weapon.attack_range = options.get("weapon_range", 140.0)
		entity.add_component(weapon)

	var perception: CPerception = null
	if include_perception:
		perception = CPerception.new()
		entity.add_component(perception)
		perception.owner_entity = entity

	var melee: CMelee = null
	if include_melee:
		melee = CMelee.new()
		melee.attack_range = options.get("melee_attack_range", 24.0)
		melee.ready_range = options.get("melee_ready_range", 20.0)
		entity.add_component(melee)

	var guard_component: CGuard = null
	if include_guard:
		guard_component = CGuard.new()
		guard_component.patrol_radius = Config.GOAP_PATROL_RADIUS
		guard_component.camp_leash_distance = Config.GOAP_MAX_DISTANCE_FROM_CAMP
		entity.add_component(guard_component)

	var tracker: CTracker = null
	if include_tracker:
		tracker = CTracker.new()
		entity.add_component(tracker)

	return {
		"entity": entity,
		"agent": agent,
		"transform": transform,
		"movement": movement,
		"weapon": weapon,
		"perception": perception,
		"melee": melee,
		"guard": guard_component,
		"tracker": tracker
	}

static func create_target(position: Vector2, camp_type: CCamp.CampType = CCamp.CampType.PLAYER, hp_value: float = 100.0) -> Entity:
	var entity := Entity.new()
	var transform := CTransform.new()
	transform.position = position
	var camp := CCamp.new()
	camp.camp = camp_type
	var hp := CHP.new()
	hp.max_hp = hp_value
	hp.hp = hp_value
	entity.add_components([transform, camp, hp])
	return entity
