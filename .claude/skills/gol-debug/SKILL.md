---
name: gol-debug
description: AI Debug Bridge for God of Lego - Execute debug commands, capture screenshots, run GDScript, and refresh game assets
---

# gol-debug

AI debugging toolkit - capture screenshots, execute commands, run scripts, control game state, refresh assets.

## Features

| Feature | Command |
|---------|---------|
| Screenshot | `node gol-tools/ai-debug/ai-debug.mjs screenshot` |
| Execute Command | `node gol-tools/ai-debug/ai-debug.mjs console <cmd>` |
| Expression Evaluation | `node gol-tools/ai-debug/ai-debug.mjs eval <expr>` |
| Get State | `node gol-tools/ai-debug/ai-debug.mjs get <property>` |
| Set State | `node gol-tools/ai-debug/ai-debug.mjs set <prop> <val>` |
| Run Script | `node gol-tools/ai-debug/ai-debug.mjs script <file.gd>` |
| Refresh Assets | `node gol-tools/ai-debug/ai-debug.mjs refresh [what]` |
| Reimport | `node gol-tools/ai-debug/ai-debug.mjs reimport` |

## Screenshots

```bash
cd /Users/dluckdu/Documents/Github/gol
node gol-tools/ai-debug/ai-debug.mjs screenshot
```

## Debug Commands

### Execute Console Commands

```bash
# Heal player
node gol-tools/ai-debug/ai-debug.mjs console heal full

# Teleport to location
node gol-tools/ai-debug/ai-debug.mjs console tp 100 200

# Set time
node gol-tools/ai-debug/ai-debug.mjs console time 12
node gol-tools/ai-debug/ai-debug.mjs console day
node gol-tools/ai-debug/ai-debug.mjs console night

# God mode
node gol-tools/ai-debug/ai-debug.mjs console god

# List entities
node gol-tools/ai-debug/ai-debug.mjs console list enemy

# Kill entities
node gol-tools/ai-debug/ai-debug.mjs console kill enemy
```

### Get Game State

```bash
# Get player position
node gol-tools/ai-debug/ai-debug.mjs get player.pos

# Get player HP
node gol-tools/ai-debug/ai-debug.mjs get player.hp

# Get current time
node gol-tools/ai-debug/ai-debug.mjs get time

# Get entity count
node gol-tools/ai-debug/ai-debug.mjs get entity_count
```

### Set Game State

```bash
# Set time to midnight
node gol-tools/ai-debug/ai-debug.mjs set time 0

# Set to noon
node gol-tools/ai-debug/ai-debug.mjs set time 12
```

### Expression Evaluation

```bash
# Simple calculation
node gol-tools/ai-debug/ai-debug.mjs eval "1 + 1"

# Note: Variable access is limited
```

## Dynamic Script Execution

AI can write and execute GDScript to test functionality:

### 1. Create Test Script

```gdscript
# test_enemy_count.gd
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
node gol-tools/ai-debug/ai-debug.mjs script test_enemy_count.gd
```

### Script Requirements

- Must `extends Node`
- Must implement `func run()` method
- Return value will be converted to string output

## Asset Refresh

### Refresh Game Data

```bash
# Reload entity recipes
node gol-tools/ai-debug/ai-debug.mjs refresh recipes

# Refresh config
node gol-tools/ai-debug/ai-debug.mjs refresh config

# Refresh UI
node gol-tools/ai-debug/ai-debug.mjs refresh ui

# Refresh all
node gol-tools/ai-debug/ai-debug.mjs refresh all
```

### Reimport Assets

Used to resolve uid file update issues or reimport after resource changes:

```bash
node gol-tools/ai-debug/ai-debug.mjs reimport
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

    node gol-tools/ai-debug/lib/godot-import.mjs ensure gol-project

To check for missing UIDs without importing:

    node gol-tools/ai-debug/lib/godot-import.mjs check-uids gol-project

To clean orphaned `.uid` files after deleting scripts:

    node gol-tools/ai-debug/lib/godot-import.mjs clean-uids gol-project

For worktrees, replace `gol-project` with the worktree path.
