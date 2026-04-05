class_name TestPCGPipelineTemplate
extends SceneConfig

## Template: PCG map generation pipeline test.
## Based on: test_pcg_map.gd (shortest integration test, 38 lines)
##
## Key differentiators vs. combat-flow / component-flow:
##   - enable_pcg() = true  (PCG generates everything)
##   - entities() = []      (no recipe spawning)
##   - Timer-based wait     (PCG needs real time, not frame count)
##   - ECS query lookup     (PCG entities don't have test names)

func scene_name() -> String:
	return "test"

func systems() -> Variant:
	return [
		"res://scripts/systems/{{MAIN_SYSTEM}}.gd",  # default: s_map_render
		# Common PCG-related systems:
		# "res://scripts/systems/s_map_render.gd",
	]

func enable_pcg() -> bool:
	return true  # ← KEY: enables PCG generation

func entities() -> Variant:
	return []  # ← PCG generates entities; no recipe spawning

func test_run(world: GOLWorld) -> Variant:
	# Use timer wait instead of frame count — PCG needs real time
	await world.get_tree().create_timer({{WAIT_SECONDS}}).timeout  # default: 0.5

	var result := TestResult.new()

	# Use ECS query (not name-based) — PCG entities don't have test names
	var query_result = ECS.world.query.with_all([{{QUERY_COMPONENT}}]).execute()

	result.assert_true(query_result.size() > 0,
		"{{QUERY_COMPONENT}} entity exists after PCG generation")

	if query_result.size() > 0:
		var entity: Entity = query_result[0]
		var comp: {{QUERY_COMPONENT}} = entity.get_component({{QUERY_COMPONENT}})

		result.assert_true(comp != null, "Entity has {{QUERY_COMPONENT}}")
		if comp != null:
			result.assert_true(comp.{{VALIDATION_METHOD}}(),
				"PCG {{RESULT_NAME}} is valid")
			# result.assert_true(comp.pcg_result != null, "PCG result non-null")

	return result


## Extension Patterns (commented examples)

## 1. Add more systems for richer PCG testing (biome, collision, etc.):
# func systems() -> Variant:
# 	return [
# 		"res://scripts/systems/s_map_render.gd",
# 		"res://scripts/systems/s_biome.gd",
# 		"res://scripts/systems/s_collision_grid.gd",
# 	]

## 2. Query for multiple component types in one test:
# var map_entities = ECS.world.query.with_all([CMapData]).execute()
# var biome_entities = ECS.world.query.with_all([CBiomeData]).execute()
# result.assert_true(map_entities.size() > 0, "Map entity exists")
# result.assert_true(biome_entities.size() > 0, "Biome entity exists")

## 3. Verify specific PCG output properties:
# var map_data: CMapData = query_result[0].get_component(CMapData)
# result.assert_true(map_data.pcg_result.map_size.x > 0, "Map width > 0")
# result.assert_true(map_data.pcg_result.biomes.size() > 0, "Has biomes")

## 4. Difference from combat-flow pattern:
##    combat-flow:  enable_pcg=false, entities=[recipes], _find_entity(name), _wait_frames
##    pcg-pipeline: enable_pcg=true,  entities=[],       ECS query,        timer wait
