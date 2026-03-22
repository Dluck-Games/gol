# Integration Tests — SceneConfig

## What Belongs Here

- Multi-system interaction (e.g., SDamage + SPickup flow)
- Full PCG pipeline verification
- Recipe-based entity spawning validation
- Any test that needs a real World

## What Does NOT Belong Here

- `extends GdUnitTestSuite` — **FORBIDDEN** in this directory
- Manual `World.new()` / `ECS.world = ...` construction
- Single-class isolation tests (those go in `tests/unit/`)

## Architecture

```
SceneConfig subclass (test_*.gd)
    ↓
test_main.tscn parses --config= and --no-exit
    ↓
Sets up GOLWorld with specified systems
    ↓
Spawns entities via recipes
    ↓
Calls test_run(world) — your test code
    ↓
TestResult collects assertions
    ↓
Prints [PASS]/[FAIL] report
    ↓
Returns exit code (0 = pass, 1 = fail)
```

## SceneConfig API

Your test config must extend `SceneConfig` and override these methods:

| Method | Returns | Purpose |
|--------|---------|---------|
| `scene_name()` | `String` | Scene name prefix (e.g., `"test"` → `l_test.tscn`) |
| `systems()` | `Array[String]` | System script paths to register |
| `enable_pcg()` | `bool` | Whether to run PCG generation |
| `entities()` | `Array[Dictionary]` | Entity recipes to spawn |
| `test_run(world)` | `TestResult` | Your test logic (async) |

## Template

```gdscript
class_name TestMyFeatureConfig
extends SceneConfig


func scene_name() -> String:
	return "test"


func systems() -> Variant:
	return [
		"res://scripts/systems/s_damage.gd",
		"res://scripts/systems/s_pickup.gd",
	]


func enable_pcg() -> bool:
	return false


func entities() -> Variant:
	return [
		{
			"recipe": "player",
			"name": "TestPlayer",
			"components": {
				"CTransform": { "position": Vector2(100, 100) },
			},
		},
	]


func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()
	await world.get_tree().process_frame

	var player: Entity = _find(world, "TestPlayer")
	result.assert_true(player != null, "Player exists")

	return result


func _find(world: GOLWorld, entity_name: String) -> Entity:
	for entity: Entity in world.entities:
		if entity.name == entity_name:
			return entity
	return null
```

## TestResult API

```gdscript
var result := TestResult.new()

# Assertions
result.assert_true(condition: bool, description: String)
result.assert_equal(actual: Variant, expected: Variant, description: String)

# Results
result.passed() -> bool          # true if all assertions passed
result.exit_code() -> int        # 0 or 1
result.print_report() -> void    # Prints formatted report
```

### Example Output

```
[RUN] tests/integration/test_combat.gd
  ✓ Player entity exists
  ✓ Enemy entity exists
  ✓ Player has full HP
  ✗ Enemy took damage after attack (expected 80, got 100)
[FAIL] 3 passed, 1 failed
```

## Async Testing

Use `await` for frame delays and coroutines:

```gdscript
func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()

	# Wait 60 frames (~1 second at 60fps)
	for i in range(60):
		await world.get_tree().process_frame

	# Or use a timer
	await world.get_tree().create_timer(2.0).timeout

	result.assert_true(some_condition, "Condition after delay")
	return result
```

## Running

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project

# Auto mode (CI) — runs and exits with code 0/1
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --scene scenes/tests/test_main.tscn \
  -- --config=res://tests/integration/test_combat.gd

# Debug mode — keeps scene running for inspection
/Applications/Godot.app/Contents/MacOS/Godot --path . \
  --scene scenes/tests/test_main.tscn \
  -- --config=res://tests/integration/flow/test_flow_component_drop_scene.gd --no-exit
```

## Conventions

- **File naming**: `test_*.gd` or `test_*_scene.gd`
- **Always use recipe-based entities** — never manually construct with `Entity.new()`
- **Subdirectories**: `flow/` for multi-system gameplay flows, `pcg/` for full-pipeline PCG tests
- **Helper method**: Add `_find(world, name)` to locate entities by name

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "SceneConfig not found" | Ensure file extends `SceneConfig` and has `.gd` extension |
| Systems not registering | Check system paths are correct and scripts extend `GOLSystem` |
| Entities not spawning | Verify recipe names exist in `EntityRecipeService` |
| Test hangs | Add frame delays; check for infinite loops or signals that never fire |
| Exit code always 0 | Ensure you return `TestResult` from `test_run()` |
