---
name: gol-integration
description: Write and run SceneConfig-based integration tests for God of Lego. Use when testing gameplay features that need a live ECS world with specific systems and entities, but don't need the full game or AI Debug Bridge.
allowed-tools: Bash, Read, Write
---

# gol-integration — SceneConfig Integration Testing

> **SAFETY: This skill operates from a MANAGEMENT REPO (gol/).**
> Game code lives in the `gol-project/` submodule.
> **ALL Godot and git branch operations MUST execute inside `gol-project/`.**
> **NEVER run git checkout, Godot, or create game files in the gol/ root directory.**

## What This Is

Integration tests sit between gdUnit4 unit tests and E2E acceptance tests. They load a real GOLWorld with specific systems and entities, run assertions against the ECS state, and report results. Unlike E2E tests, they don't require the AI Debug Bridge — the test runs the assertions directly and exits with a code.

Repository test layout note:
- `tests/unit/` is reserved for gdUnit4 unit suites.
- `tests/integration/` is the integration root; SceneConfig scripts live directly there, and gdUnit4 scenario suites live under `tests/integration/flow/`.

## When to Use

- Testing gameplay mechanics (combat, AI, spawning) in isolation
- Verifying system interactions without full PCG overhead
- Automated CI-friendly testing with exit codes
- Reproducing bugs with minimal world state

## Architecture

The integration test pipeline:

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

### SceneConfig API

Your test config must extend `SceneConfig` and override these methods:

| Method | Returns | Purpose |
|--------|---------|---------|
| `scene_name()` | `String` | Scene name prefix (e.g., "test" → `l_test.tscn`) |
| `systems()` | `Array[String]` | System script paths to register |
| `enable_pcg()` | `bool` | Whether to run PCG generation |
| `entities()` | `Array[Dictionary]` | Entity recipes to spawn |
| `test_run(world)` | `TestResult` | Your test logic (async) |

## Writing a Test Config

### Step-by-Step

1. Create a file in `tests/integration/test_*.gd`
2. Extend `SceneConfig`
3. Override the required methods
4. Implement `test_run()` with your assertions

### Template

```gdscript
class_name TestCombatBasics
extends SceneConfig

func scene_name() -> String:
    return "test"  # Uses scenes/maps/l_test.tscn (empty world)

func systems() -> Variant:
    return [
        "res://scripts/systems/s_hp.gd",
        "res://scripts/systems/s_damage.gd",
        "res://scripts/systems/s_dead.gd",
    ]

func enable_pcg() -> bool:
    return false

func entities() -> Variant:
    return [
        {
            "recipe": "player",
            "name": "TestPlayer",
            "components": {
                "CTransform": {"position": Vector2(100, 100)}
            }
        },
        {
            "recipe": "enemy_basic",
            "name": "TestEnemy",
            "components": {
                "CTransform": {"position": Vector2(200, 200)}
            }
        },
    ]

func test_run(world: GOLWorld) -> Variant:
    var result := TestResult.new()
    
    # Wait for systems to process
    for i in range(60):
        await world.get_tree().process_frame
    
    # Find entities by iterating world.entities (Array[Entity])
    var player: Entity = null
    var enemy: Entity = null
    for entity: Entity in world.entities:
        if entity.name == "TestPlayer":
            player = entity
        elif entity.name == "TestEnemy":
            enemy = entity
    
    result.assert_true(player != null, "Player entity exists")
    result.assert_true(enemy != null, "Enemy entity exists")
    result.assert_equal(player.get_component(CHP).current_hp, 100, "Player has full HP")
    
    return result
```

### Async Testing

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

## Running Tests

### Auto Mode (CI)

Runs the test and exits with code 0 (pass) or 1 (fail):

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
/Applications/Godot.app/Contents/MacOS/Godot \
    --path . \
    --scene scenes/tests/test_main.tscn \
    -- --config=res://tests/integration/test_combat.gd
```

### Debug Mode (Interactive)

Add `--no-exit` to keep the scene running after setup:

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
/Applications/Godot.app/Contents/MacOS/Godot \
    --path . \
    --scene scenes/tests/test_main.tscn \
    -- --config=res://tests/integration/test_combat.gd --no-exit
```

This is useful for inspecting the scene manually or using AI Debug Bridge.

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All assertions passed |
| 1 | One or more assertions failed |
| Other | Godot/engine error |

## Common System Paths

| System | Path | Group | Purpose |
|--------|------|-------|---------|
| SHP | `res://scripts/systems/s_hp.gd` | gameplay | HP processing |
| SDamage | `res://scripts/systems/s_damage.gd` | gameplay | Damage application |
| SDead | `res://scripts/systems/s_dead.gd` | gameplay | Death handling |
| SMove | `res://scripts/systems/s_move.gd` | gameplay | Movement |
| SAI | `res://scripts/systems/s_ai.gd` | gameplay | GOAP AI |
| SPerception | `res://scripts/systems/s_perception.gd` | gameplay | Threat detection |
| SMeleeAttack | `res://scripts/systems/s_melee_attack.gd` | gameplay | Melee combat |
| SCollision | `res://scripts/systems/s_collision.gd` | physics | Collision detection |
| SFireBullet | `res://scripts/systems/s_fire_bullet.gd` | gameplay | Ranged combat |
| SEnemySpawn | `res://scripts/systems/s_enemy_spawn.gd` | gameplay | Spawner system |

## Common Recipe IDs

| Recipe | Description |
|--------|-------------|
| player | Player character |
| enemy_basic | Basic zombie |
| enemy_fire | Fire elemental zombie |
| enemy_wet | Water elemental zombie |
| enemy_cold | Ice elemental zombie |
| enemy_electric | Electric elemental zombie |
| survivor | Guard NPC |
| campfire | Player base/campfire |
| weapon_rifle | Rifle weapon |
| weapon_pistol | Pistol weapon |

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

## File Locations

| Purpose | Path |
|---------|------|
| Test configs | `tests/integration/test_*.gd` |
| Empty test scene | `scenes/maps/l_test.tscn` |
| Test entry point | `scenes/tests/test_main.tscn` |
| SceneConfig base | `scripts/gameplay/ecs/scene_config.gd` |
| TestResult class | `scripts/tests/test_result.gd` |

## Example: Combat Test

```gdscript
class_name TestCombatDamage
extends SceneConfig

func scene_name() -> String:
    return "test"

func systems() -> Variant:
    return [
        "res://scripts/systems/s_hp.gd",
        "res://scripts/systems/s_damage.gd",
        "res://scripts/systems/s_melee_attack.gd",
    ]

func enable_pcg() -> bool:
    return false

func entities() -> Variant:
    return [
        {
            "recipe": "player",
            "name": "Attacker",
            "components": {
                "CTransform": {"position": Vector2(100, 100)},
                "CAttack": {"damage": 20, "range": 50},
            }
        },
        {
            "recipe": "enemy_basic",
            "name": "Target",
            "components": {
                "CTransform": {"position": Vector2(140, 100)},  # Within melee range
                "CHP": {"max_hp": 100, "current_hp": 100},
            }
        },
    ]

func test_run(world: GOLWorld) -> Variant:
    var result := TestResult.new()
    
    # Let systems run for a few frames
    for i in range(10):
        await world.get_tree().process_frame
    
    # Check damage was applied
    var target = world.get_entity_by_name("Target")
    var target_hp = target.get_component(CHP)
    
    result.assert_true(target_hp.current_hp < 100, "Target took damage from melee attack")
    result.assert_equal(target_hp.current_hp, 80, "Target HP reduced by 20")
    
    return result
```

## Comparison: Test Types

| Aspect | Unit Tests (gdUnit4) | Integration Tests (SceneConfig) | E2E Tests (AI Debug) |
|--------|---------------------|--------------------------------|----------------------|
| Speed | Fast (~ms) | Medium (~seconds) | Slow (~tens of seconds) |
| World | None | Minimal GOLWorld | Full game |
| PCG | No | Optional | Yes |
| CI | Yes | Yes | Manual |
| Use case | Pure functions, logic | System interaction | Full feature validation |

## Troubleshooting

### "SceneConfig not found"

Ensure your test file extends `SceneConfig` and is saved with `.gd` extension.

### Systems not registering

Check system paths are correct and the scripts extend `GOLSystem`.

### Entities not spawning

Verify recipe names exist in `EntityRecipeService` and component data matches the component constructors.

### Test hangs

Add frame delays in `test_run()`. Infinite loops or awaiting signals that never fire will hang the test.

### Exit code always 0

Ensure you're returning the `TestResult` from `test_run()` and checking `result.passed()`.
