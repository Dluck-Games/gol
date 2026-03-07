---
name: gol-run
description: Use when running Godot game for playtesting, feature acceptance, or quick verification without opening the editor
---

# gol-run

Run Godot game directly for playtesting and feature acceptance.

## Overview

Launch the God of Lego game in standalone mode without opening the Godot editor. Used for quick iteration and hands-free testing.

## When to Use

- Feature acceptance testing
- Quick gameplay verification
- Performance testing
- Validating PCG generation
- Testing UI/UX flows
- Verifying AI behavior

## Quick Reference

| Task | Command |
|------|---------|
| Run main game | `/Applications/Godot.app/Contents/MacOS/Godot --path gol-project --scene scenes/main.tscn` |
| Run with verbose | Add `--verbose` flag |
| Run specific scene | Replace `scenes/main.tscn` with target scene |

## Implementation

### Basic Run

```bash
cd /Users/dluckdu/Documents/Github/gol
cd gol-project
/Applications/Godot.app/Contents/MacOS/Godot --scene scenes/main.tscn
```

### Background Run (non-blocking)

```bash
cd gol-project
/Applications/Godot.app/Contents/MacOS/Godot --scene scenes/main.tscn 2>&1 &
```

### With Debug Output

```bash
cd gol-project
/Applications/Godot.app/Contents/MacOS/Godot --scene scenes/main.tscn --verbose 2>&1 | tee /tmp/gol-run.log
```

## Common Parameters

| Flag | Purpose |
|------|---------|
| `--scene PATH` | Launch specific scene directly |
| `--path DIR` | Set project root directory |
| `--verbose` | Enable detailed logging |
| `--headless` | Run without window (for tests) |
| `--debug` | Enable debug mode |

## Acceptance Checklist

When running for feature acceptance, verify:

- [ ] Game launches without errors
- [ ] PCG map generates correctly
- [ ] Player movement (WASD) works
- [ ] Enemy AI behaves as expected
- [ ] UI/HUD displays properly
- [ ] Day/night cycle functions
- [ ] No console errors or warnings

## Troubleshooting

### "command not found: godot"

Use full path: `/Applications/Godot.app/Contents/MacOS/Godot`

### Game window not appearing

- Check if another Godot instance is running
- Verify scene path is correct
- Check console output for errors

### Slow startup

- First launch compiles shaders (normal)
- Subsequent launches are faster
- Use `--verbose` to see progress

## Project Structure Reference

```
gol-project/
├── scenes/main.tscn          # Main game scene
├── scenes/ui/                # UI scenes
├── scenes/maps/              # Map scenes
└── project.godot             # Project config
```
