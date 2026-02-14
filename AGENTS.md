# AGENTS.md

This file guides agentic coding assistants working in this repository.

## ⚠️ IMPORTANT: Project Directory Rules

**`gol-proj-main/` is READ-ONLY.** All agent modifications must occur in numbered project directories.

| Directory | Permission | Purpose |
|-----------|------------|---------|
| `gol-proj-main/` | **READ-ONLY** | Reference implementation, stable source of truth |
| `gol-proj-01/` | Read/Write | Work directory for agent tasks |
| `gol-proj-02/` | Read/Write | Work directory for agent tasks |
| `gol-proj-03/` | Read/Write | Work directory for agent tasks |
| `gol-proj-04/` | Read/Write | Work directory for agent tasks |

**Agents MUST NOT modify files in `gol-proj-main/`.** Use it only as a reference for patterns, architecture, and existing implementations.

---

## Project Overview

God of Lego (GOL) is a 2D survival game built with Godot 4.5. The codebase uses:
- ECS architecture via the GECS addon
- MVVM for UI with ObservableProperty bindings
- GOAP (Goal-Oriented Action Planning) for AI behavior

## Commands

### Run the Game

```bash
# Use Godot MCP tools (preferred)
mcp__godot__run_project with projectPath: "d:/Repos/god-of-lego"

# Command line
Godot --path "d:/Repos/god-of-lego"
```

### Run Tests (gdUnit4)

```bash
# Run all tests
Godot --path "d:/Repos/god-of-lego" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --run-tests

# Run a single test file
Godot --path "d:/Repos/god-of-lego" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --run-tests=res://tests/ai/test_enemy_ai.gd
```

### Build / Export

- No automated export/build command is defined in-repo.
- Use Godot editor export presets if needed.

### Linting / Formatting

- No explicit lint or formatter configured in this repository.
- Rely on Godot editor formatting and the code patterns below.

## Repository Layout

```
scripts/
  components/           # ECS Components (c_*.gd)
  systems/              # ECS Systems (s_*.gd)
  gameplay/             # GOAP logic, ECS authoring, game state
  services/             # ServiceContext, ServiceRegistry, and impl/
  ui/                   # MVVM viewmodels/views
  debug/                # Debug UI and tools
  maps/, pcg/           # Map generation
resources/              # Recipes, goals
scenes/                 # Godot scenes
tests/                  # gdUnit4 tests (ai, flow, maps, system, unit)
```

## Architecture and Data Flow

- **ECS Core**: Components are pure data (RefCounted), systems are pure logic (Node).
- **MVVM UI**: ObservableProperty binds components to viewmodels to views.
- **GOAP AI**: Planner builds action sequences, SAI system executes.

Data flow (one way):
`System -> Component -> ViewModel -> View`

System groups (processing order defined in `GECS`):
1. `gameplay` (in _process)
2. `ui` (in _process)
3. `render` (in _process)
4. `physics` (in _physics_process)

## Code Style Guidelines (GDScript)

### Imports and File Structure

- **Class Name**: Must have `class_name MyClass` at the top.
- **Inheritance**: `extends ParentClass` on the next line.
- **Ordering**: Constants -> Signals -> Enums -> Exported Vars -> Public Vars -> Private Vars -> Lifecycle -> Public Funcs -> Private Funcs.
- **Services**: Access via `ServiceContext.service_name()`. Avoid singletons other than `ServiceContext` and `ECS`.

### Naming Conventions

- **Components**: Class `CThing` in `scripts/components/c_thing.gd`.
- **Systems**: Class `SThing` in `scripts/systems/s_thing.gd`.
- **Services**: Class `Service_Thing` in `scripts/services/impl/service_thing.gd`.
- **ViewModels**: Class `ThingViewModel` in `scripts/ui/view_model_thing.gd` (or similar).
- **Views**: Class `ViewThing` in `scripts/ui/views/view_thing.gd`.
- **GOAP Actions**: Class `GoapAction_Thing` in `scripts/gameplay/goap/actions/thing.gd` (snake_case file).

### Formatting

- **Indentation**: Tabs (default Godot style).
- **Type Safety**: Use static types (`: int`, `: String`, `-> void`) wherever possible.
- **Clarity**: Keep functions short. Favor early returns.

### ECS Patterns

- Systems extend `System`.
- Implement `query()` to define required components (e.g., `return ECS.world.query.with_all([CTransform, CPlayer])`).
- Implement `process(entity, delta)` for per-entity logic.
- Components extend `Component` and contain *only* data.

### MVVM Patterns

- ViewModels extend `RefCounted`. Expose data via `ObservableProperty`.
- Views extend `Control`. In `setup()`, subscribe to ViewModel properties.
- In `_exit_tree()` or teardown, ensure ViewModels are released/unsubscribed to prevent leaks.

### GOAP Patterns

- Actions extend `GoapAction`.
- Define `preconditions` and `effects` in `_init()` as `Dictionary[String, bool]`.
- Implement `perform(agent, delta, context) -> bool`. Return `true` when action is complete.
- Use `fail_plan()` if the action becomes impossible during execution.

## Testing

- Tests are located in `tests/` with subfolders `unit`, `integration`, `system`, etc.
- Use `gdUnit4` assertions (e.g., `assert_str(value).is_equal("test")`).
- Create tests for all new Systems and GOAP Actions.

## Cursor / Copilot Rules

- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` files found.
