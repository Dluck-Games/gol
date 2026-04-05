class_name TestComponentFlowTemplate
extends SceneConfig

## Template: Kill → Component Drop → Pickup flow.
## Based on: test_flow_component_drop_scene.gd (most complete game loop test)
##
## Demonstrates the full lifecycle: entity death, component drop as Box,
## data preservation through round-trip, and player pickup.

func scene_name() -> String:
	return "test"

func systems() -> Variant:
	return [
		"res://scripts/systems/s_damage.gd",
		"res://scripts/systems/s_pickup.gd",
		"res://scripts/systems/s_life.gd",
		"res://scripts/systems/s_dead.gd",
	]

func enable_pcg() -> bool:
	return false

func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "{{PLAYER_NAME}}",  # default: "TestPlayer"
			"components": {
				# NOTE: Enemy spacing should be CLOSE (~20px apart) because no
				# movement system is registered. Entities won't chase each other.
				"CTransform": { "position": Vector2({{PLAYER_X}}, {{PLAYER_Y}}) },  # default: 100, 100
			},
		},
		{
			"recipe": "enemy_basic",
			"name": "{{ENEMY_NAME}}",  # default: "TestEnemy"
			"components": {
				"CTransform": { "position": Vector2({{ENEMY_X}}, {{ENEMY_Y}}) },  # default: 120, 100 (20px apart)
			},
		},
	]

func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	# Frame delays: 1 init frame for scene setup + 2 processing frames after damage
	await world.get_tree().process_frame

	# --- Find entities ---
	var player: Entity = _find_entity(world, "{{PLAYER_NAME}}")
	var enemy: Entity = _find_entity(world, "{{ENEMY_NAME}}")

	result.assert_true(player != null, "Player exists")
	result.assert_true(enemy != null, "Enemy exists")
	if player == null or enemy == null:
		return result

	# --- Attach test component to enemy ---
	# {{COMPONENT_ATTACHMENT_BLOCK}}
	# Example: attach CWeapon so enemy drops something on death
	# var comp := {{COMPONENT_CLASS}}.new()
	# comp.{{PRESERVE_FIELD}} = {{ORIGINAL_VALUE}}
	# enemy.add_component(comp)

	# --- Deal lethal damage via CDamage component ---
	var damage := CDamage.new()
	damage.amount = 999.0
	damage.knockback_direction = Vector2.RIGHT
	enemy.add_component(damage)

	# Let SDamage + SDead process the death and drop
	await world.get_tree().process_frame
	await world.get_tree().process_frame

	# --- Verify enemy lost component (death consumed it) ---
	result.assert_true(not enemy.has_component({{COMPONENT_CLASS}}),
		"Enemy lost {{COMPONENT_CLASS}} after lethal damage")

	# --- Find dropped Box by CContainer holding the component ---
	var box: Entity = _find_component_box(world, {{BOX_COMPONENT_CLASS}})
	result.assert_true(box != null, "{{COMPONENT_CLASS}} Box spawned")
	if box == null:
		return result

	# --- Verify Box contents and data preservation ---
	var container: CContainer = box.get_component(CContainer)
	result.assert_true(container != null, "Box has CContainer")
	result.assert_true(container.stored_components.size() > 0, "Box has stored components")

	# Data preservation check: values survive round-trip through death→drop→Box
	var stored := container.stored_components[0]
	result.assert_equal(stored.{{PRESERVE_FIELD}}, {{ORIGINAL_VALUE}},
		"Stored {{COMPONENT_CLASS}} preserves {{PRESERVE_FIELD}}")

	# --- Player picks up via SPickup system ---
	# Remove existing component if present (clean slate)
	if player.has_component({{COMPONENT_CLASS}}):
		player.remove_component({{COMPONENT_CLASS}})

	# System discovery: dual-location search (world children + Systems node).
	# This is critical because system placement varies across test setups.
	var pickup_system: SPickup = _find_system(world, SPickup)
	result.assert_true(pickup_system != null, "SPickup system found")
	if pickup_system == null:
		return result

	var pickup: CPickup = player.get_component(CPickup)
	pickup_system._open_box(player, box, pickup)

	# --- Verify player gained component from Box ---
	result.assert_true(player.has_component({{COMPONENT_CLASS}}),
		"Player gained {{COMPONENT_CLASS}} after pickup")

	# {{ADDITIONAL_STEPS}}

	return result


# --- Helpers ---

func _find_entity(world: GOLWorld, entity_name: String) -> Entity:
	return world.find_entity(entity_name)


func _find_component_box(world: GOLWorld, component_class: GDScript) -> Entity:
	for entity: Entity in world.entities:
		if entity.has_component(component_class):
			var container: CContainer = entity.get_component(CContainer)
			if container != null and container.stored_components.size() > 0:
				return entity
	return null


func _find_system(world: GOLWorld, script_class: GDScript) -> Node:
	# Search direct children of world first
	for child in world.get_children():
		if child is script_class or child.get_script() == script_class:
			return child
	# Then check Systems node (alternative placement)
	if world.has_node("Systems"):
		for child in world.get_node("Systems").get_children():
			if child is script_class or child.get_script() == script_class:
				return child
	return null
