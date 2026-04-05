class_name TestCombatFlowTemplate
extends SceneConfig

## Template: Combat / HP survival test pattern.
## Based on: test_combat.gd, test_flow_elemental_status_scene.gd

func scene_name() -> String:
	return "test"

func systems() -> Variant:
	return [
		"res://scripts/systems/s_hp.gd",
		"res://scripts/systems/s_damage.gd",
		"res://scripts/systems/s_dead.gd",
		# Add more systems as needed:
		# "res://scripts/systems/s_melee_attack.gd",
		# "res://scripts/systems/s_elemental_affliction.gd",
	]

func enable_pcg() -> bool:
	return false

func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "{{PLAYER_NAME}}",  # default: "TestPlayer"
			"components": {
				"CTransform": { "position": Vector2({{PLAYER_X}}, {{PLAYER_Y}}) },  # default: 100, 100
			},
		},
		{
			"recipe": "{{ENEMY_RECIPE}}",  # default: "enemy_basic"
			"name": "{{ENEMY_NAME}}",  # default: "TestEnemy"
			"components": {
				"CTransform": { "position": Vector2({{ENEMY_X}}, {{ENEMY_Y}}) },  # default: 300, 100 (200px apart)
				# Custom component overrides:
				# "CElementalAttack": { ... },
			},
		},
	]

func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	# Wait for initialization + simulation
	_wait_frames(world, {{FRAME_COUNT}})  # default: 60 (1 second at 60fps)

	# Find entities
	var player: Entity = _find_entity(world, "{{PLAYER_NAME}}")
	var enemy: Entity = _find_entity(world, "{{ENEMY_NAME}}")

	# Existence assertions with null-safety early returns
	result.assert_true(player != null, "{{PLAYER_NAME}} exists after simulation")
	if player == null:
		return result

	result.assert_true(enemy != null, "{{ENEMY_NAME}} exists after simulation")
	if enemy == null:
		return result

	# Component presence assertions
	var player_hp: CHP = player.get_component(CHP)
	result.assert_true(player_hp != null, "{{PLAYER_NAME}} has CHP component")
	if player_hp == null:
		return result

	# Value assertions — {{ASSERTION_DESCRIPTION}}
	result.assert_true(player_hp.hp > 0.0, "{{PLAYER_NAME}} is alive (HP > 0)")
	# result.assert_equal(player_hp.hp, expected_value, "Player HP after combat")

	# {{ADDITIONAL_ASSERTIONS}}

	return result


# Helper: find entity by name (delegates to SceneConfig base class)
func _find_entity(world: GOLWorld, entity_name: String) -> Entity:
	return world.find_entity(entity_name)


# Helper: wait N frames (delegates to SceneConfig base class)
func _wait_frames(world: GOLWorld, count: int) -> void:
	for i: int in range(count):
		await world.get_tree().process_frame


## Extension Patterns (commented examples)

## 1. Trigger melee attack on enemy (from elemental_status pattern):
# var melee: CMeleeAttack = enemy.get_component(CMeleeAttack)
# if melee != null:
#     melee.cooldown = 0.0
#     melee.pending = true

## 2. Attach damage component manually (from component_drop pattern):
# var dmg := CDamage.new()
# dmg.amount = 10.0
# dmg.source_id = player.get_instance_id()
# enemy.add_component(dmg)

## 3. Check enemy HP reduction after combat:
# var enemy_hp: CHP = enemy.get_component(CHP)
# result.assert_true(enemy_hp != null, "Enemy has CHP component")
# if enemy_hp != null:
#     result.assert_true(enemy_hp.hp < enemy_hp.max_hp, "Enemy took damage")

## 4. Verify death state (entity removal or CDead component):
# var dead_enemy: Entity = _find_entity(world, "{{ENEMY_NAME}}")
# result.assert_true(dead_enemy == null, "{{ENEMY_NAME}} was removed (dead)")
# # OR check for CDead component before removal:
# var dead_comp: CDead = enemy.get_component(CDead)
# result.assert_true(dead_comp != null, "{{ENEMY_NAME}} has CDead component")
