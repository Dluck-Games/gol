# Integration Test Scene Loading — Config-Driven GOLWorld

**Date:** 2026-03-21
**Status:** Design approved, pending implementation

## Problem

Unit tests call `GOL.setup()`/`teardown()` but lack a real scene tree, ECS world, loaded systems, and baked entities. The gap between test and production environments hides bugs. Integration tests need the full boot sequence (`GOL.setup()` → ServiceContext → `switch_scene`) with customizable content.

## Goals

1. Unify scene loading — production and test share one config-driven mechanism
2. Single-file integration tests — one `.gd` file = config + assertions
3. Full boot fidelity — integration tests run the same startup flow as production
4. Future-proof — same mechanism supports multiple production levels
5. Clean isolation — test code excluded from release builds

## Architecture

### SceneConfig — Universal Level Descriptor

Every level (production or test) is described by a `SceneConfig`:

```gdscript
# scripts/gameplay/ecs/scene_config.gd
class_name SceneConfig extends RefCounted

func scene_name() -> String:
    return ""  # Subclass must implement

func scene_path() -> String:
    return "res://scenes/maps/l_%s.tscn" % scene_name()

# Systems: null = scan all from SYSTEMS_DIR; Array[String] = load specific scripts
func systems() -> Variant:
    return null

# PCG
func enable_pcg() -> bool:
    return true

# Cached PCGConfig instance — override to customize seed, params, etc.
var _pcg_config: PCGConfig = null
func pcg_config() -> PCGConfig:
    if _pcg_config == null:
        _pcg_config = PCGConfig.new()
    return _pcg_config

# Entities: null = GOLWorld default spawn logic; Array[Dictionary] = spawn from config
# Dictionary format: {"recipe": "player", "components": {"CTransform": {"position": Vector2(100, 100)}}}
func entities() -> Variant:
    return null

# Test assertions: return null = no test (normal scene); override to define test logic
func test_run(world: World) -> TestResult:
    return null
```

**Key design notes:**
- `pcg_config()` caches its instance — multiple calls return the same `PCGConfig`, so mutations like `.pcg_seed = randi()` persist.
- `test_run()` returning `null` means "no test." `test_main.gd` checks the return value directly — no separate `has_test()` needed.

### Production Config

```gdscript
# scripts/gameplay/configs/procedural_config.gd
class_name ProceduralConfig extends SceneConfig

func scene_name() -> String:
    return "procedural"

func systems() -> Variant:
    return null  # Load all

func enable_pcg() -> bool:
    return true

func entities() -> Variant:
    return null  # GOLWorld default spawn logic
```

### GOLWorld.initialize() — Config-Driven Refactor

```gdscript
# gol_world.gd changes

var _config: SceneConfig = null

func set_config(config: SceneConfig) -> void:
    _config = config

func initialize():
    super.initialize()

    # 1. Systems
    var system_list = _config.systems() if _config else null
    if system_list == null:
        _load_all_systems()
    else:
        _load_systems_from_list(system_list)

    # 2. EntityBaker (for .tscn authoring nodes)
    EntityBaker.bake_world(self)

    # 3. PCG map data
    var do_pcg = _config.enable_pcg() if _config else true
    if do_pcg:
        _setup_pcg_map()

    # 4. Entities
    var entity_defs = _config.entities() if _config else null
    if entity_defs == null:
        _spawn_default_entities()
    else:
        _spawn_entities_from_config(entity_defs)
```

**Extracted private methods:**

`_spawn_default_entities()` — moves current player/campfire/guards/spawners/loot logic unchanged.

`_setup_pcg_map()` — moves current CMapData entity creation from PCG result.

`_load_systems_from_list(paths: Array)`:
```gdscript
func _load_systems_from_list(paths: Array) -> void:
    for script_path in paths:
        if not ResourceLoader.exists(script_path):
            push_warning("GOLWorld: System script not found: %s" % script_path)
            continue
        var script := load(script_path) as GDScript
        if script == null or not script.can_instantiate():
            push_warning("GOLWorld: Cannot load system: %s" % script_path)
            continue
        var instance = script.new()
        if instance is System:
            add_system(instance)
        else:
            instance.free()
            push_warning("GOLWorld: Script does not extend System: %s" % script_path)
```

`_spawn_entities_from_config(defs: Array)`:
```gdscript
func _spawn_entities_from_config(defs: Array) -> void:
    for def: Dictionary in defs:
        var recipe_id: String = def.get("recipe", "")
        if recipe_id.is_empty():
            push_warning("GOLWorld: Entity config missing 'recipe' key")
            continue

        var entity: Entity = ServiceContext.recipe().create_entity_by_id(recipe_id)
        if not entity:
            push_error("GOLWorld: Failed to create entity from recipe: %s" % recipe_id)
            continue

        # Apply component property overrides
        if def.has("components"):
            var comp_overrides: Dictionary = def["components"]
            for comp_class_name: String in comp_overrides:
                var comp = _find_component_by_class_name(entity, comp_class_name)
                if comp == null:
                    push_warning("GOLWorld: Component '%s' not found on entity '%s'" % [comp_class_name, recipe_id])
                    continue
                var props: Dictionary = comp_overrides[comp_class_name]
                for prop_name: String in props:
                    comp.set(prop_name, props[prop_name])

        # Set entity name if provided
        if def.has("name"):
            entity.name = def["name"]

func _find_component_by_class_name(entity: Entity, class_name_str: String) -> Variant:
    for comp in entity.components.values():
        if comp.get_script().get_global_name() == class_name_str:
            return comp
    return null
```

### Service_Scene — Unified Config Interface

**CRITICAL TIMING NOTE:** `set_config()` MUST be called before `ECS.world = scene`, because the ECS.world setter adds the world to the scene tree, triggering `World._ready()` → `initialize()`. If config is set after, `initialize()` sees `_config == null` and silently falls through to defaults.

```gdscript
# service_scene.gd — full rewrite

class_name Service_Scene
extends ServiceBase

var _current_scene: String = ""
var _pending_config: SceneConfig = null

func teardown() -> void:
    print("Service_Scene: Cleaning up current scene")
    _pop_ui_layers()
    if ECS and ECS.world:
        var world: Node = ECS.world
        ECS.world = null
        world.purge()
        if world.tree_exited.is_connected(_on_world_unloaded):
            world.tree_exited.disconnect(_on_world_unloaded)
        world.queue_free()
    _current_scene = ""
    _pending_config = null

func switch_scene(config: SceneConfig) -> void:
    if _current_scene == config.scene_name():
        return

    _pending_config = config
    if _current_scene != "":
        _unload()
    else:
        _load_with_config(config)

func scene_exist(scene_name: String) -> bool:
    var scene_path := "res://scenes/maps/l_%s.tscn" % scene_name
    return ResourceLoader.exists(scene_path)

func at_scene(scene_name) -> bool:
    return scene_name == _current_scene

### private methods ###

func _load_with_config(config: SceneConfig) -> void:
    var scene_path := config.scene_path()
    if not ResourceLoader.exists(scene_path):
        push_error("Service_Scene: Scene file not found: %s" % scene_path)
        return

    print("Load scene: %s (path: %s)" % [config.scene_name(), scene_path])
    var scene = load(scene_path).instantiate()

    # CRITICAL: set_config BEFORE ECS.world assignment
    # ECS.world setter → add_child → _ready() → initialize() reads _config
    if scene is GOLWorld:
        scene.set_config(config)

    ECS.world = scene
    _current_scene = config.scene_name()
    _pending_config = null

func _unload() -> void:
    print("Unload scene: " + _current_scene)

    if ECS.world:
        _pop_ui_layers()
        var old_world: World = ECS.world
        ECS.world = null
        old_world.purge()
        if old_world.tree_exited.is_connected(_on_world_unloaded):
            old_world.tree_exited.disconnect(_on_world_unloaded)
        old_world.tree_exited.connect(_on_world_unloaded, Object.CONNECT_ONE_SHOT)
        old_world.queue_free()
    else:
        push_error("Scene not loaded: " + _current_scene)

func _on_world_unloaded():
    _current_scene = ""
    if _pending_config != null:
        _load_with_config(_pending_config)

func _pop_ui_layers() -> void:
    var ui_service := ServiceContext.ui()
    if ui_service:
        ui_service.pop_views_by_layer(Service_UI.LayerType.HUD)
        ui_service.pop_views_by_layer(Service_UI.LayerType.GAME)
```

**Key changes from existing code:**
- `switch_scene()` now takes `SceneConfig` instead of `String` — only caller is `gol.gd:start_game()`, updated accordingly.
- `_on_world_unloaded()` now calls `_load_with_config(_pending_config)` instead of the old string-based `_load()`, ensuring config is preserved across async unload/reload.
- Removed `_pending_scene` field — scene name is derived from `_pending_config.scene_name()`.
- `_load_with_config()` validates scene path existence before loading.
- `_unload()` and `teardown()` logic preserved unchanged.

### GOL.start_game() Change

```gdscript
func start_game() -> void:
    var config := ProceduralConfig.new()
    config.pcg_config().pcg_seed = randi()
    var result := ServiceContext.pcg().generate(config.pcg_config())
    if result == null or not result.is_valid():
        push_error("PCG generation failed - aborting game start")
        return
    GOL.Game.campfire_position = ServiceContext.pcg().find_nearest_village_poi()
    ServiceContext.scene().switch_scene(config)
```

`main.gd` stays unchanged — still calls `GOL.setup()` + `GOL.start_game()`.

### TestResult — Lightweight Assertion Utility

```gdscript
# scripts/tests/test_result.gd
class_name TestResult extends RefCounted

var _assertions: Array[Dictionary] = []

func assert_true(condition: bool, name: String, message: String = "") -> void:
    _assertions.append({"name": name, "passed": condition,
        "message": message if not condition else ""})

func assert_equal(actual: Variant, expected: Variant, name: String) -> void:
    var passed := actual == expected
    var msg := "" if passed else "expected %s, got %s" % [expected, actual]
    _assertions.append({"name": name, "passed": passed, "message": msg})

func passed() -> bool:
    return _assertions.all(func(a): return a["passed"])

func exit_code() -> int:
    return 0 if passed() else 1

func print_report() -> void:
    print("\n=== TEST RESULTS ===")
    for a in _assertions:
        var status := "PASS" if a["passed"] else "FAIL"
        var line := "[%s] %s" % [status, a["name"]]
        if not a["message"].is_empty():
            line += " — %s" % a["message"]
        print(line)
    var total := _assertions.size()
    var passed_count := _assertions.filter(func(a): return a["passed"]).size()
    print("=== %d/%d passed ===" % [passed_count, total])
```

### Test Entry Point

```gdscript
# scripts/tests/test_main.gd
extends Node

func _ready() -> void:
    await get_tree().process_frame
    var config_path := _parse_arg("--config")
    var no_exit := _has_flag("--no-exit")

    if config_path.is_empty():
        push_error("No --config argument provided")
        get_tree().quit(1)
        return

    # Load and validate config
    var script = load(config_path)
    if script == null:
        push_error("Failed to load config: %s" % config_path)
        get_tree().quit(1)
        return
    var config = script.new()
    if not config is SceneConfig:
        push_error("Config does not extend SceneConfig: %s" % config_path)
        get_tree().quit(1)
        return

    GOL.setup()

    if config.enable_pcg():
        var pcg_cfg := config.pcg_config()
        var result := ServiceContext.pcg().generate(pcg_cfg)
        if result == null or not result.is_valid():
            push_error("PCG generation failed")
            get_tree().quit(1)
            return
        GOL.Game.campfire_position = ServiceContext.pcg().find_nearest_village_poi()

    ServiceContext.scene().switch_scene(config)

    # Wait for world to be fully initialized
    # ECS.world setter → add_child → _ready() → initialize() → finalize_system_setup()
    # Two frames ensures: 1) _ready() has fired, 2) deferred calls have executed
    await get_tree().process_frame
    await get_tree().process_frame

    # Run test assertions if config defines them
    var test_result := await config.test_run(ECS.world)
    if test_result != null:
        test_result.print_report()
        if not no_exit:
            get_tree().quit(test_result.exit_code())
    # If test_run returned null (non-test config) or --no-exit: scene keeps running

func _exit_tree() -> void:
    GOL.teardown()

func _parse_arg(prefix: String) -> String:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with(prefix + "="):
            return arg.substr((prefix + "=").length())
    return ""

func _has_flag(flag: String) -> bool:
    return flag in OS.get_cmdline_user_args()
```

### Example Integration Test

```gdscript
# tests/integration/test_combat.gd
extends SceneConfig

func scene_name() -> String:
    return "test"

func systems() -> Variant:
    return [
        "res://scripts/systems/gameplay/s_damage.gd",
        "res://scripts/systems/gameplay/s_hp.gd",
        "res://scripts/systems/physics/s_collision.gd",
    ]

func enable_pcg() -> bool:
    return false

func entities() -> Variant:
    return [
        {"recipe": "player", "name": "Player", "components": {"CTransform": {"position": Vector2(100, 100)}}},
        {"recipe": "enemy_basic", "name": "TestEnemy", "components": {"CTransform": {"position": Vector2(200, 100)}}},
    ]

func test_run(world: World) -> TestResult:
    # Let systems process for 1 second
    await world.get_tree().create_timer(1.0).timeout
    var players = ECS.world.query.with_all([CHP, CPlayer]).execute()
    var result = TestResult.new()
    result.assert_true(players.size() > 0, "Player entity exists")
    result.assert_true(players[0].get_component(CHP).hp > 0, "Player is alive")
    return result
```

### Empty Test World Scene

`scenes/maps/l_test.tscn` — A minimal `.tscn` with:
- Root node: `GOLWorld` (script: `gol_world.gd`)
- `entity_nodes_root`: set to an empty `Entities` child node
- `system_nodes_root`: set to an empty `Systems` child node
- No authoring nodes, no pre-placed systems

This mirrors `l_procedural.tscn` structure but with no content — config drives everything.

## Launch Commands

```bash
# CI — auto-run, print results, exit with code
godot --path gol-project --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_combat.gd

# Manual debug — run tests, keep alive for AI Debug Bridge
godot --path gol-project --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_combat.gd --no-exit

# Production — unchanged
godot --path gol-project --scene scenes/main.tscn
```

## File Structure

### New Files

| File | Purpose | Release |
|------|---------|:---:|
| `scripts/gameplay/ecs/scene_config.gd` | SceneConfig base class | Yes |
| `scripts/gameplay/configs/procedural_config.gd` | Production level config | Yes |
| `scripts/tests/test_result.gd` | Test assertion utility | No |
| `scripts/tests/test_main.gd` | Test entry script | No |
| `scenes/tests/test_main.tscn` | Test entry scene | No |
| `scenes/maps/l_test.tscn` | Empty test world (GOLWorld, Entities, Systems nodes only) | No |
| `tests/integration/test_combat.gd` | Example integration test | No |

### Modified Files

| File | Change |
|------|--------|
| `scripts/gameplay/ecs/gol_world.gd` | Add `set_config()`, refactor `initialize()` to config-driven, extract `_spawn_default_entities()` / `_setup_pcg_map()`, add `_load_systems_from_list()` / `_spawn_entities_from_config()` / `_find_component_by_class_name()` |
| `scripts/services/impl/service_scene.gd` | `switch_scene(config: SceneConfig)` replaces `switch_scene(scene_name: String)`, add `_load_with_config()`, update `_on_world_unloaded()` to use `_pending_config`, remove `_pending_scene` |
| `scripts/gol.gd` | `start_game()` creates `ProceduralConfig`, calls `switch_scene(config)` |
| `scripts/services/AGENTS.md` | Update `switch_scene` documentation to reflect config-based API |

### Unchanged

| File | Reason |
|------|--------|
| `scripts/main.gd` | Still calls `GOL.setup()` + `GOL.start_game()` |
| `project.godot` | Autoloads unchanged |
| `addons/gecs/` | ECS framework untouched |
| `tests/ai/`, `tests/pcg/`, etc. | GdUnit4 unit tests — independent path |

### Release Exclusion (export_presets.cfg)

```
exclude_filter="tests/*, scripts/tests/*, scripts/debug/*, scenes/tests/*"
```

## Skill Updates

| Skill | Change |
|------|--------|
| `gol-e2e` | Adapt launch command to `test_main.tscn -- --config=... --no-exit` |
| New `gol-integration` | Document integration test authoring, config file format, launch commands, result interpretation |
| `gol-unittest` | Unchanged |
| `gol-run` | Unchanged |

## Design Decisions

1. **Config over convention** — All levels defined by SceneConfig, production is just the "full" config
2. **Single file = single test** — Config + assertions in one `.gd`, AI-friendly to write
3. **null = default** — SceneConfig methods return null to use GOLWorld's existing behavior
4. **stdout + exit code** — CI-friendly, no file-based result passing
5. **--no-exit flag** — External control of exit behavior, config is agnostic
6. **Production code backward-compatible** — GOLWorld falls through to defaults when config is null
7. **Cached PCGConfig** — `pcg_config()` returns the same instance across calls to avoid mutation loss

## Implementation Notes

1. **Config timing is critical**: `GOLWorld.set_config()` must be called before `ECS.world = scene` assignment. The ECS.world setter triggers `add_child()` → `_ready()` → `initialize()`, which reads `_config`. Wrong ordering causes silent fallback to defaults.
2. **Async unload path**: When switching from an existing scene, `_unload()` uses `queue_free()` + `tree_exited` signal. `_on_world_unloaded()` must call `_load_with_config(_pending_config)` (not the old string-based `_load`), so config survives the async gap.
3. **Component lookup by class name**: `_find_component_by_class_name()` uses `get_script().get_global_name()` to match component class names from config dictionaries. This requires components to have `class_name` declarations (all GOL components already do).
4. **`switch_scene()` API change**: The only production caller is `gol.gd:start_game()`. No other code paths call `switch_scene()` directly.
