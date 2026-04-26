---
name: gol-debug
description: AI Debug Bridge for God of Lego - Execute debug commands, capture screenshots, run GDScript, refresh game assets, and profile performance
---

# gol-debug

AI debugging toolkit - capture screenshots, execute commands, run scripts, control game state, refresh assets, profile performance.

> When debugging, prefer `gol run game` (headless) over `--windowed`. Headless is faster, uses less resources, and allows `gol debug` commands for inspection.

## Features

| Feature | Command |
|---------|---------|
| Screenshot | `gol debug screenshot` |
| Execute Command | `gol debug console <cmd>` |
| Expression Evaluation | `gol debug eval <expr>` |
| Get State | `gol debug get <property>` |
| Set State | `gol debug set <prop> <val>` |
| Run Script | `gol debug script <file.gd>` |
| Refresh Assets | `gol debug refresh [what]` |
| Reimport | `gol reimport` |
| Boot Game | `gol run game` |
| Stop Game | `gol stop` |
| Perf Snapshot | `gol debug perf` |
| Perf Systems | `gol debug perf systems` |
| Perf Entities | `gol debug perf entities` |
| Perf Memory | `gol debug perf memory` |

## Screenshots

```bash
cd /Users/dluckdu/Documents/Github/gol
gol debug screenshot
```

## Debug Commands

### Execute Console Commands

```bash
# Heal player
gol debug console heal full

# Teleport to location
gol debug console tp 100 200

# Set time
gol debug console time 12
gol debug console day
gol debug console night

# God mode
gol debug console god

# List entities
gol debug console list enemy

# Kill entities
gol debug console kill enemy
```

### Get Game State

```bash
# Get player position
gol debug get player.pos

# Get player HP
gol debug get player.hp

# Get current time
gol debug get time

# Get entity count
gol debug get entity_count
```

### Set Game State

```bash
# Set time to midnight
gol debug set time 0

# Set to noon
gol debug set time 12
```

### Expression Evaluation

```bash
# Simple calculation
gol debug eval "1 + 1"

# Note: Variable access is limited
```

## Performance Profiling

Collect runtime performance data from the running game. Returns JSON for agent parsing.

### Quick Snapshot (most common)

```bash
# Full performance snapshot — FPS, frame time, system timing, entity counts, memory
gol debug perf
# Same as:
gol debug perf snapshot
```

Returns JSON with: `fps`, `frame_time_ms`, `process_time_ms`, `physics_time_ms`, `object_count`, `memory_mib`, `entity_count`, `archetype_count`, `system_count`, `systems` (array sorted by execution_time_ms desc), `query_cache`.

### Per-System Timing

```bash
# Detailed per-system execution times (sorted slowest first)
gol debug perf systems
```

Returns JSON array: `[{name, group, execution_time_ms, entity_count, archetype_count, active, parallel}, ...]`

### Entity Distribution

```bash
# Entity counts by archetype + top 20 most common components
gol debug perf entities
```

Returns JSON: `{total, archetypes: [{signature, entity_count, component_count}], by_component: {name: count}}`

### Memory Stats

```bash
# Memory and object counts
gol debug perf memory
```

Returns JSON: `{static_memory_mib, object_count, resource_count, node_count, orphan_node_count}`

### Note on ECS Debug Mode

System timing data (`execution_time_ms`, `entity_count` per system) requires `ECS.debug = true` in Godot project settings (`gecs/debug_mode`). When disabled, the `systems` array returns `[{"debug_mode": false, "note": "..."}]`. FPS, memory, and entity counts are always available.

## Debug Script Sandbox

**ALL debug scripts written by AI agents MUST go to `.debug/scripts/` in the management repo root.**

```bash
# Repository root path (management repo)
# macOS: /Users/dluckdu/Documents/Github/gol/
# The sandbox directory: <repo-root>/.debug/scripts/
```

### Why `.debug/scripts/`?

- **NOT inside `gol-project/scripts/`** — Godot scans that directory and would import debug scripts as game code
- **NOT `/tmp/`** — `/tmp` is shared system-wide, volatile across reboots, and not project-scoped
- **Inside the repo tree but gitignored** — co-located with the project, never committed, survives reboot

### Workflow

1. Write debug scripts to `.debug/scripts/<descriptive_name>.gd`
2. Execute via: `gol debug script .debug/scripts/<descriptive_name>.gd`
3. The CLI reads the script, copies content to the Godot signal directory, and sends the execute command

### Example

```bash
# 1. Write script to sandbox
# (Write .debug/scripts/check_enemy_count.gd)

# 2. Execute
gol debug script .debug/scripts/check_enemy_count.gd
```

## Dynamic Script Execution

AI can write and execute GDScript to test functionality:

### 1. Create Test Script

Write the script to `.debug/scripts/` — for example `.debug/scripts/check_enemy_count.gd`:

```gdscript
# .debug/scripts/check_enemy_count.gd
extends Node

func run():
    var count = 0
    for entity in ECS.world.entities:
        if entity.has_component(CGoapAgent):
            var camp = entity.get_component(CCamp)
            if camp and camp.camp == CCamp.CampType.ENEMY:
                count += 1
    return "Enemy count: %d" % count
```

### 2. Execute Script

```bash
gol debug script .debug/scripts/check_enemy_count.gd
```

### Script Requirements

- Must `extends Node`
- Must implement `func run()` method
- Return value will be converted to string output
- **Must be written to `.debug/scripts/`** — never `gol-project/scripts/`, never `/tmp/`

## Asset Refresh

### Refresh Game Data

```bash
# Reload entity recipes
gol debug refresh recipes

# Refresh config
gol debug refresh config

# Refresh UI
gol debug refresh ui

# Refresh all
gol debug refresh all
```

### Reimport Assets

Used to resolve uid file update issues or reimport after resource changes:

```bash
gol debug reimport
```

## How It Works

```
AI/CLI                              Godot Game
  |                                     |
  |-- write 'command' file ----------->|
  |                                     |
  |                                     |-- AIDebugBridge detects file
  |                                     |-- Parse and execute command
  |                                     |-- Write result file
  |                                     |
  |<-- write 'result' file ------------|
  |                                     |
  |-- read result -------------------->|
```

## File Locations

| Platform | Signal Directory | Screenshot File |
|----------|------------------|-----------------|
| macOS | `~/Library/Application Support/Godot/app_userdata/God of Lego/ai_signals/` | `~/Library/Application Support/Godot/app_userdata/God of Lego/ai_screenshot.png` |
| Linux | `~/.local/share/godot/app_userdata/God of Lego/ai_signals/` | `~/.local/share/godot/app_userdata/God of Lego/ai_screenshot.png` |
| Windows | `%APPDATA%/Godot/app_userdata/God of Lego/ai_signals/` | `%APPDATA%/Godot/app_userdata/God of Lego/ai_screenshot.png` |

## Requirements

- Godot game must be running
- `ScreenshotManager` and `AIDebugBridge` must be in autoloads
- First startup requires waiting 3 frames for initialization

## Troubleshooting

### "Timeout after 10s. Is the game running?"

```bash
# Start the game
/Applications/Godot.app/Contents/MacOS/Godot --path gol-project
```

### Command Unresponsive

Check if AIDebugBridge is loaded: Look for "AIDebugBridge ready" in Godot output

### Script Execution Failed

- Ensure script `extends Node`
- Ensure it has `func run()` method
- Check Godot console output for detailed errors

### Auto-Import (UID generation)

When creating new `.gd` files, run import to generate `.uid` sidecar files:

    gol reimport ensure gol-project

To check for missing UIDs without importing:

    gol reimport check-uids gol-project

To clean orphaned `.uid` files after deleting scripts:

    gol reimport clean-uids gol-project

For worktrees, replace `gol-project` with the worktree path.
