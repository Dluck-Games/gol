## Minimal SceneConfig integration test template.
## Copy this file, replace {{PLACEHOLDER}} markers, and add your assertions.
## This is the simplest valid starting point for any new integration test.

class_name TestMinimalTemplate
extends SceneConfig


## Returns the scene to load. Use "test" for l_test.tscn in most cases.
func scene_name() -> String:
	return "test"


## System scripts required by this test. Add paths for each system under test.
func systems() -> Variant:
	return [
		"{{SYSTEM_PATH}}",
	]


## Whether to enable PCG map generation. Default false unless testing PCG.
func enable_pcg() -> bool:
	return false


## Recipe-based entities to spawn into the world before test_run().
func entities() -> Variant:
	return [
		{
			"recipe": "{{RECIPE_ID}}",
			"name": "{{ENTITY_NAME}}",
			"components": {},
		},
	]


## Main test body. Always await at least 1 frame before accessing entities.
func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	await _wait_frames(world, 1)

	var entity: Entity = _find_entity(world, "{{ENTITY_NAME}}")
	result.assert_true(entity != null, "{{ASSERTION_DESCRIPTION}}")

	return result


## Helper: find an entity by name in the world. Delegates to base class.
func _find_entity(world: GOLWorld, entity_name: String) -> Entity:
	for entity: Entity in world.entities:
		if entity.name == entity_name:
			return entity
	return null


## Helper: await N frames for world initialization or timing.
func _wait_frames(world: GOLWorld, count: int) -> void:
	for _i: int in range(count):
		await world.get_tree().process_frame
