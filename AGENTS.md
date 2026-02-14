# PROJECT KNOWLEDGE BASE

**Generated:** 2026-02-15 | **Commit:** 4d392d0 | **Branch:** main

## OVERVIEW

God of Lego (GOL) -- 2D survival game, Godot 4.5. ECS (GECS addon) + MVVM UI + GOAP AI + PCG map generation.
Monorepo with `gol-proj-main/` (READ-ONLY reference) and numbered work directories.

## CRITICAL: Directory Permissions

| Directory | Permission | Purpose |
|-----------|------------|---------|
| `gol-proj-main/` | **READ-ONLY** | Reference implementation. NEVER modify. |
| `gol-proj-01/` | Read/Write | Active work directory (mirrors main) |
| `gol-proj-02/` - `gol-proj-04/` | Read/Write | Reserved (currently empty) |
| `gol-tools/` | Read/Write | Dev tools (LSP bridge, tile generators) |

## STRUCTURE

```
gol/
├── AGENTS.md                    # This file
├── gol-proj-main/               # READ-ONLY reference (git submodule)
│   ├── project.godot            # Godot config, autoloads, input maps
│   ├── scripts/                 # All game code (~180 GDScript files)
│   │   ├── gol.gd              # GOL autoload -- game manager entry point
│   │   ├── main.gd             # Scene entry -- calls GOL.setup() + start_game()
│   │   ├── components/         # ECS Components (29 files, c_*.gd)
│   │   ├── systems/            # ECS Systems (25 files, s_*.gd)
│   │   ├── gameplay/           # GOAP AI + ECS authoring + game state
│   │   ├── pcg/                # Procedural Content Generation (pipeline + WFC)
│   │   ├── services/           # ServiceContext + 7 service implementations
│   │   ├── ui/                 # MVVM: ObservableProperty + ViewModels + Views
│   │   ├── debug/              # ImGui debuggers (ECS, GOAP, PCG)
│   │   ├── configs/            # Config.gd -- game constants
│   │   ├── utils/              # ECSUtils helper
│   │   └── actions/            # Action base class (non-GOAP)
│   ├── scenes/                  # .tscn files (main, maps, UI, tests)
│   ├── resources/               # .tres data (recipes, goals, sprite_frames)
│   ├── tests/                   # gdUnit4 tests (ai, flow, pcg, system, unit)
│   ├── shaders/                 # daynight_lighting, hit_flash
│   ├── assets/                  # Sprites, tiles, backgrounds, UI art
│   ├── addons/                  # gecs, gdUnit4, imgui-godot
│   └── .github/workflows/       # CI: run-tests, debug build, release build
├── gol-proj-01/                 # Work copy (identical scripts to main)
└── gol-tools/                   # LSP bridge (Node.js), tile gen (Python)
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add new entity type | `scripts/gameplay/ecs/authoring/` + `resources/recipes/` | Create authoring + recipe .tres |
| Add ECS component | `scripts/components/c_*.gd` | Extend Component, data only |
| Add ECS system | `scripts/systems/s_*.gd` | Extend System, set group in `_ready()` |
| Add GOAP action | `scripts/gameplay/goap/actions/` | Extend GoapAction, set preconditions/effects |
| Add GOAP goal | `resources/goals/*.tres` | GoapGoal resource, assign to recipe |
| Add UI element | `scripts/ui/viewmodels/` + `scripts/ui/views/` + `scenes/ui/` | ViewModel + View + .tscn |
| Add service | `scripts/services/impl/service_*.gd` | Extend ServiceBase, register in ServiceContext |
| Add PCG phase | `scripts/pcg/phases/` | Extend PCGPhase, add to pipeline |
| Add test | `tests/{category}/test_*.gd` | gdUnit4 format |
| Debug AI | `scripts/debug/goap_debugger.gd` | ImGui-based GOAP inspector |
| Debug ECS | `scripts/debug/ecs_debugger.gd` | ImGui-based entity inspector |
| Game constants | `scripts/configs/config.gd` | Speeds, GOAP distances, base components |

## ARCHITECTURE

### Data Flow (one-way)

```
System -> Component -> ViewModel -> View
```

### System Processing Order (GOLWorld)

| Order | Group | Frame | Purpose |
|-------|-------|-------|---------|
| 1 | `gameplay` | `_process` | Movement, combat, AI, spawning, day/night |
| 2 | `ui` | `_process` | HUD, HP bars |
| 3 | `render` | `_process` | Sprite sync, map render, lighting |
| 4 | `physics` | `_physics_process` | Collision detection (Area2D) |

### Autoloads

| Name | Path | Purpose |
|------|------|---------|
| `ECS` | `addons/gecs/ecs.gd` | ECS framework singleton |
| `GOL` | `scripts/gol.gd` | Game manager (GOL.Game for state) |
| `DebugPanel` | `scripts/debug/debug_panel.gd` | Debug UI toggle |
| `ImGuiRoot` | `addons/imgui-godot/data/ImGuiRoot.tscn` | ImGui rendering |

### Boot Sequence

```
main.tscn -> main.gd._ready()
  -> GOL.setup()
    -> ServiceContext.static_setup(root)  # Registers all 7 services
  -> GOL.start_game()
    -> ServiceContext.pcg().generate()    # PCG map generation
    -> ServiceContext.scene().switch_scene("procedural")
      -> GOLWorld.initialize()
        -> _load_all_systems()            # Auto-discovers s_*.gd
        -> EntityBaker.bake_world()       # Bakes authoring nodes
        -> _spawn_player/campfire/guards/spawners/loot
```

## CONVENTIONS

### Naming (STRICT)

| Type | Class Pattern | File Pattern | Example |
|------|---------------|--------------|---------|
| Component | `CThing` | `c_thing.gd` | `CTransform` in `c_transform.gd` |
| System | `SThing` | `s_thing.gd` | `SMove` in `s_move.gd` |
| Service | `Service_Thing` | `service_thing.gd` | `Service_PCG` in `service_pcg.gd` |
| ViewModel | `ViewModelThing` | `viewmodel_thing.gd` | `ViewModelHud` in `viewmodel_hud.gd` |
| View | `ViewThing` / `View_Thing` | `view_thing.gd` | `View_HPBar` in `view_hp_bar.gd` |
| GOAP Action | `GoapAction_Thing` | `thing.gd` (snake_case) | `GoapAction_ChaseTarget` in `chase_target.gd` |
| GOAP Goal | -- | `thing.tres` | `eliminate_threat.tres` |
| Entity Recipe | -- | `thing.tres` | `enemy_basic.tres` |

### File Structure (every .gd file)

```gdscript
class_name MyClass
extends ParentClass

# Order: Constants -> Signals -> Enums -> @export -> Public vars -> Private vars
# Then: Lifecycle -> Public funcs -> Private funcs
```

### Code Style

- **Indentation**: Tabs
- **Types**: Static typing everywhere (`: int`, `-> void`)
- **Functions**: Short, early returns
- **Singletons**: Only `ServiceContext` and `ECS`. Access services via `ServiceContext.thing()`
- **Entity creation**: Prefer `ServiceContext.recipe().create_entity_by_id("id")` over manual assembly

## ANTI-PATTERNS (THIS PROJECT)

- **DO NOT** modify `gol-proj-main/`. Work in numbered directories only.
- **DO NOT** create singletons beyond `ServiceContext` and `ECS`.
- **DO NOT** put logic in Components -- they are pure data containers.
- **DO NOT** access services directly -- always go through `ServiceContext.thing()`.
- **DO NOT** manually instantiate systems -- `GOLWorld._load_all_systems()` auto-discovers them.
- **DO NOT** use `GoapAction_MoveTo` directly -- it's abstract. Extend it.
- **DO NOT** skip `class_name` declaration at top of any .gd file.

## COMMANDS

```bash
# Run tests (gdUnit4) -- from project directory
Godot --path "." -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --run-tests

# Run single test file
Godot --path "." -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --run-tests=res://tests/ai/test_enemy_ai.gd

# No build/lint commands -- use Godot editor
```

## CI/CD

- **run-tests.yml**: Runs gdUnit4 on push to main/develop and PRs
- **debug.yml**: Debug build on push to main (Windows)
- **release.yml**: Release build on version tags (`X.Y.Z`)
- All use Godot 4.5.1, Ubuntu (tests) / Windows (builds)

## NOTES

- `gol-proj-01/` has `.godot/` cache + `reports/` (test reports) that `gol-proj-main/` doesn't
- Chinese comments exist in some files (Config.gd, SMove, ECSUtils) -- this is normal
- GoapGoal uses untyped Dictionary to avoid Godot 4.x StringName leak bug with typed dicts in .tres
- `Config.BASE_COMPONENTS` defines which components survive death (non-droppable)
- `Config.DEATH_REMOVE_COMPONENTS` defines components stripped on death animation
- PCG uses seeded RNG -- same seed = same map
- Entity recipes support inheritance via `base_recipe` field

## SUBDIRECTORY AGENTS.md

Detailed domain knowledge in child files:
- `gol-proj-main/scripts/components/AGENTS.md` -- Component catalog & patterns
- `gol-proj-main/scripts/systems/AGENTS.md` -- System catalog & group assignments
- `gol-proj-main/scripts/gameplay/AGENTS.md` -- GOAP AI + ECS authoring + recipes
- `gol-proj-main/scripts/pcg/AGENTS.md` -- PCG pipeline, WFC, phases
- `gol-proj-main/scripts/services/AGENTS.md` -- Service layer patterns
- `gol-proj-main/scripts/ui/AGENTS.md` -- MVVM bindings & view lifecycle
- `gol-proj-main/tests/AGENTS.md` -- Test patterns & gdUnit4 conventions

## AI ASSISTANT TOOLS

```bash
# Claude Code Internal (preferred)
claude-internal -p --output-format stream-json --verbose "task"

# CodeBuddy CLI (fallback)
codebuddy -p --model claude-4.5 --verbose "task"
```
