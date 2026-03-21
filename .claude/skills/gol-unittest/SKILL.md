---
name: gol-unittest
description: Run GdUnit4 unit tests for Godot 4 GDScript projects (god-of-lego)
allowed-tools: Bash
---

## What I do

- Execute GdUnit4 unit tests via Godot headless mode
- Run all tests, specific files, or directories
- Report test results including pass/fail counts and execution time

## When to use me

Use this skill when:
- Running unit tests for Godot 4 projects
- Verifying GDScript code changes
- CI/CD testing workflows

## Godot path detection

The skill uses `GODOT_PATH` from environment, falling back to:
- Steam: `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
- Official: `C:\Program Files\Godot\Godot_v*.exe`
- Scoop: `%USERPROFILE%\scoop\apps\godot\current\godot.exe`

## Commands

```bash
# Run all gdUnit unit suites
<GODOT_PATH> --headless --path "d:/Repos/god-of-lego" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/ -c --ignoreHeadlessMode

# Run specific test file
<GODOT_PATH> --headless --path "d:/Repos/god-of-lego" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/ai/test_enemy_ai.gd -c --ignoreHeadlessMode

# Run test directory
<GODOT_PATH> --headless --path "d:/Repos/god-of-lego" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/system/ -c --ignoreHeadlessMode
```

## Test directories

- `res://tests/unit/ai/` - AI and GOAP unit tests
- `res://tests/unit/pcg/` - PCG unit tests
- `res://tests/unit/system/` - ECS system unit tests
- `res://tests/unit/service/` - Service unit tests

For SceneConfig or scenario integration coverage, use `gol-integration` or run `res://tests/integration/` directly.
