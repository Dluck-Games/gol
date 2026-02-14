class_name GOLWorld
extends World

## Path to the systems directory (relative to res://)
const SYSTEMS_DIR := "res://scripts/systems"

## Default spawner configuration for ENEMY_SPAWN POIs
const DEFAULT_SPAWN_RECIPE_ID: String = "enemy_basic"
const DEFAULT_SPAWN_INTERVAL: float = 6.0
const DEFAULT_SPAWN_INTERVAL_VARIANCE: float = 0.5
const DEFAULT_SPAWN_COUNT: int = 1
const DEFAULT_SPAWN_RADIUS: float = 0.0
const DEFAULT_MAX_SPAWN_COUNT: int = 6
const DEFAULT_ACTIVE_CONDITION: int = 0  # CSpawner.ActiveCondition.ALWAYS

## Loot box configuration for BUILDING POIs
const LOOT_BOX_TEXTURE_PATH: String = "res://assets/sprite_sheets/boxes/box_re_texture.png"
const LOOT_WEAPON_RECIPES: Array[String] = ["weapon_rifle", "weapon_pistol", "tracker"]

## Guard spawn configuration
const GUARD_SPAWN_COUNT: int = 3
const GUARD_SPAWN_MIN_RADIUS: float = 50.0
const GUARD_SPAWN_MAX_RADIUS: float = 100.0

func _process(delta) -> void:
	if is_queued_for_deletion():
		return
	
	# Process only systems in the "gameplay" group
	ECS.process(delta, "gameplay")
	ECS.process(delta, "ui")
	ECS.process(delta, "render")
	
func _physics_process(delta) -> void:
	if is_queued_for_deletion():
		return
	
	# Process only systems in the "physics" group
	ECS.process(delta, "physics")

func initialize():
	super.initialize()
	_load_all_systems()
	EntityBaker.bake_world(self)
	
	var pcg_result := ServiceContext.pcg().last_result
	if pcg_result != null:
		var map_entity := Entity.new()
		map_entity.add_component(CMapData.new())
		add_entity(map_entity)
		map_entity.name = "ProceduralMap"
		map_entity.get_component(CMapData).pcg_result = pcg_result
	
	# Spawn player at campfire position
	_spawn_player()

	# Spawn campfire at PCG-determined VILLAGE POI position
	_spawn_campfire()

	# Spawn guards near the VILLAGE POI/campfire
	_spawn_guards_at_campfire()

	# Spawn enemy spawners at ENEMY_SPAWN POI positions
	_spawn_enemy_spawners_at_pois()

	# Spawn loot boxes at BUILDING POI positions
	_spawn_loot_boxes_at_building_pois()


## Spawn player entity at the campfire position
func _spawn_player() -> void:
	var spawn_pos: Vector2 = GOL.Game.campfire_position
	var player: Entity = ServiceContext.recipe().create_entity_by_id("player")
	if not player:
		push_error("GOLWorld: Failed to create player entity from recipe")
		return
	
	var transform: CTransform = player.get_component(CTransform)
	if transform:
		transform.position = spawn_pos
	
	player.name = "Player"
	print("[GOLWorld] Spawned player at campfire position: ", spawn_pos)


## Spawn campfire entity at the PCG-determined position
func _spawn_campfire() -> void:
	var campfire_pos: Vector2 = GOL.Game.campfire_position
	var campfire: Entity = ServiceContext.recipe().create_entity_by_id("campfire")
	if not campfire:
		push_error("GOLWorld: Failed to create campfire entity from recipe")
		return

	var transform: CTransform = campfire.get_component(CTransform)
	if transform:
		transform.position = campfire_pos

	campfire.name = "Campfire"
	print("[GOLWorld] Spawned campfire at VILLAGE POI: ", campfire_pos)


## Spawn guard NPCs near the campfire/VILLAGE POI
func _spawn_guards_at_campfire() -> void:
	var campfire_pos: Vector2 = GOL.Game.campfire_position

	print("[GOLWorld] Spawning %d guards at VILLAGE POI: " % GUARD_SPAWN_COUNT, campfire_pos)

	for i: int in range(GUARD_SPAWN_COUNT):
		_spawn_guard_at_position(campfire_pos, i)


## Spawn a single guard entity at a random offset from the campfire position
func _spawn_guard_at_position(campfire_pos: Vector2, index: int) -> void:
	# Create entity from survivor recipe
	var guard: Entity = ServiceContext.recipe().create_entity_by_id("survivor")
	if not guard:
		push_error("GOLWorld: Failed to create guard entity from recipe")
		return

	# Calculate random position around campfire
	var random_angle: float = randf() * TAU  # Random angle 0-2π
	var random_radius: float = GUARD_SPAWN_MIN_RADIUS + randf() * (GUARD_SPAWN_MAX_RADIUS - GUARD_SPAWN_MIN_RADIUS)
	var offset: Vector2 = Vector2(cos(random_angle), sin(random_angle)) * random_radius
	var spawn_pos: Vector2 = campfire_pos + offset

	# Set position
	var transform: CTransform = guard.get_component(CTransform)
	if transform:
		transform.position = spawn_pos

	guard.name = "Guard_%d" % index
	print("[GOLWorld] Spawned guard %d at position: " % index, spawn_pos)


## Spawn enemy spawners at ENEMY_SPAWN POI positions from PCG
func _spawn_enemy_spawners_at_pois() -> void:
	var pcg_result := ServiceContext.pcg().last_result
	if pcg_result == null:
		push_warning("[GOLWorld] No PCG result available, skipping enemy spawner generation")
		return

	if pcg_result.poi_list == null:
		push_warning("[GOLWorld] No POI list in PCG result, skipping enemy spawner generation")
		return

	var enemy_spawn_pois: Array = pcg_result.poi_list.get_pois_by_type(POIList.POIType.ENEMY_SPAWN)
	if enemy_spawn_pois.is_empty():
		push_warning("[GOLWorld] No ENEMY_SPAWN POIs found in PCG result")
		return

	print("[GOLWorld] Spawning enemy spawners at %d ENEMY_SPAWN POI positions" % enemy_spawn_pois.size())

	for i: int in range(enemy_spawn_pois.size()):
		var poi: POIList.POI = enemy_spawn_pois[i] as POIList.POI
		if poi == null:
			continue

		_spawn_enemy_spawner_at_position(poi.position, i)


## Spawn a single enemy spawner entity at the specified position
func _spawn_enemy_spawner_at_position(pos: Vector2, index: int) -> void:
	# Create entity for the spawner
	var spawner_entity := Entity.new()
	spawner_entity.name = "EnemySpawner_POI_%d" % index

	# Add transform component with position
	var transform := CTransform.new()
	transform.position = pos
	spawner_entity.add_component(transform)

	# Add spawner component with default configuration
	var spawner_comp := CSpawner.new()
	spawner_comp.spawn_recipe_id = DEFAULT_SPAWN_RECIPE_ID
	spawner_comp.spawn_interval = DEFAULT_SPAWN_INTERVAL
	spawner_comp.spawn_interval_variance = DEFAULT_SPAWN_INTERVAL_VARIANCE
	spawner_comp.spawn_count = DEFAULT_SPAWN_COUNT
	spawner_comp.spawn_radius = DEFAULT_SPAWN_RADIUS
	spawner_comp.max_spawn_count = DEFAULT_MAX_SPAWN_COUNT
	spawner_comp.active_condition = DEFAULT_ACTIVE_CONDITION
	spawner_entity.add_component(spawner_comp)

	# Add sprite component for visual representation
	var sprite := CSprite.new()
	# Use default texture or load the spawner texture
	var texture := load("res://assets/sprites/items/zombie_basement_01.png") as Texture2D
	if texture:
		sprite.texture = texture
	spawner_entity.add_component(sprite)

	# Add HP component
	var hp_comp := CHP.new()
	hp_comp.max_hp = 400.0
	hp_comp.hp = 400.0
	spawner_entity.add_component(hp_comp)

	# Add camp component (enemy faction)
	var camp_comp := CCamp.new()
	camp_comp.camp = CCamp.CampType.ENEMY
	spawner_entity.add_component(camp_comp)

	# Add collision component for hit detection
	var collision := CCollision.new()
	var collision_shape := CircleShape2D.new()
	collision_shape.radius = 20.0
	collision.collision_shape = collision_shape
	spawner_entity.add_component(collision)

	# Add to world
	add_entity(spawner_entity)

	print("[GOLWorld] Spawned enemy spawner at POI position: ", pos)


## Spawn loot boxes at BUILDING POI positions from PCG
func _spawn_loot_boxes_at_building_pois() -> void:
	var pcg_result := ServiceContext.pcg().last_result
	if pcg_result == null:
		push_warning("[GOLWorld] No PCG result available, skipping loot box generation")
		return

	if pcg_result.poi_list == null:
		push_warning("[GOLWorld] No POI list in PCG result, skipping loot box generation")
		return

	var building_pois: Array = pcg_result.poi_list.get_pois_by_type(POIList.POIType.BUILDING)
	if building_pois.is_empty():
		push_warning("[GOLWorld] No BUILDING POIs found in PCG result")
		return

	print("[GOLWorld] Spawning loot boxes at %d BUILDING POI positions" % building_pois.size())

	for i: int in range(building_pois.size()):
		var poi: POIList.POI = building_pois[i] as POIList.POI
		if poi == null:
			continue

		_spawn_loot_box_at_position(poi.position, i)


## Spawn a single loot box entity at the specified position with random weapon
func _spawn_loot_box_at_position(pos: Vector2, index: int) -> void:
	# Create entity for the loot box
	var loot_box_entity := Entity.new()
	loot_box_entity.name = "LootBox_BUILDING_%d" % index

	# Add transform component with position
	var transform := CTransform.new()
	transform.position = pos
	loot_box_entity.add_component(transform)

	# Add sprite component for visual representation
	var sprite := CSprite.new()
	var texture := load(LOOT_BOX_TEXTURE_PATH) as Texture2D
	if texture:
		sprite.texture = texture
	loot_box_entity.add_component(sprite)

	# Add collision component
	var collision := CCollision.new()
	var collision_shape := CircleShape2D.new()
	collision_shape.radius = 16.0
	collision.collision_shape = collision_shape
	loot_box_entity.add_component(collision)

	# Add container component with random weapon
	var container := CContainer.new()
	var random_weapon := LOOT_WEAPON_RECIPES[randi() % LOOT_WEAPON_RECIPES.size()]
	container.stored_recipe_id = random_weapon
	loot_box_entity.add_component(container)

	# Add to world
	add_entity(loot_box_entity)

	print("[GOLWorld] Spawned loot box at BUILDING POI position: %s with weapon: %s" % [pos, random_weapon])


## Load all System scripts from the systems directory and instantiate them
func _load_all_systems() -> void:
	var system_scripts := _scan_system_scripts(SYSTEMS_DIR)
	for script_path in system_scripts:
		# Verify resource exists before loading (handles orphaned .uid files)
		if not ResourceLoader.exists(script_path):
			continue
		
		var script := load(script_path) as GDScript
		if script == null:
			push_warning("GOLWorld: Failed to load system script: %s" % script_path)
			continue
		
		# Check if the script extends System
		var instance = script.new()
		if instance is System:
			add_system(instance)
		else:
			instance.free()
			push_warning("GOLWorld: Script does not extend System: %s" % script_path)

## Recursively scan directory for .gd files
## Uses ResourceLoader.list_directory for compatibility with exported builds
func _scan_system_scripts(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var files := ResourceLoader.list_directory(dir_path)
	
	if files.is_empty():
		push_error("GOLWorld: Cannot list systems directory or directory is empty: %s" % dir_path)
		return result
	
	for file_name in files:
		# Handle .remap files in exported builds
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		
		var full_path := dir_path.path_join(file_name)
		
		if file_name.ends_with(".gd"):
			result.append(full_path)
		elif not file_name.contains("."):
			# Likely a directory (no extension), scan recursively
			result.append_array(_scan_system_scripts(full_path))
	
	return result
	
func merge_entity(src: Entity, dest: Entity) -> void:
	print("LogGOLWorld: merge_entity Merge Entities: ", src, " -> " , dest)
	
	if dest.has_method("on_merge"):
		print("LogGOLWorld: Merging entities with on_merge method")
		dest.on_merge(src)
	
	for component in src.components.values():
		if not dest.has_component(component.get_script()):
			print("LogGOLWorld: Adding component ", component, " to destination entity ", dest)
			dest.add_component(component)
		else:
			var dest_comp = dest.get_component(component.get_script())
			if dest_comp.has_method("on_merge"):
				print("LogGOLWorld: Merge component ", component, " to destination entity ", dest)
				dest_comp.on_merge(component)
			else:
				pass
	
	remove_entity(src)
