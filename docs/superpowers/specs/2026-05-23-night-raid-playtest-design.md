# Night Raid Automated Playtest Design

## Overview

A dedicated automated gameplay test (playtest) for the Night Raid wave system, separated from SceneConfig integration tests as an independent tier. Runs the full night raid cycle through the real game startup path, validates ~12 checkpoints, and optionally records video. Serves as the merge baseline for the night raid branch.

## Design Principles

1. **Zero divergence from real gameplay** — playtest walks the exact same `GOL.start_game()` path as a real player session. No shortcuts, no bypassed initialization.
2. **Binary checkpoints** — each checkpoint either passes or fails. No soft/optional checks.
3. **Test error vs test failure** — "test didn't complete" (timeout, crash) is an error, distinct from "checkpoint didn't pass" which is a failure.
4. **1:1 parameter mapping** — each test tier has its own dedicated Godot launch arg. CLI maps directly, no shared parameter, no priority resolution.
5. **Minimal game code invasion** — PCGConfig, Service_PCG gain preset capability; GOL gains `--playtest=` parsing; legacy `--scenario` match block removed.

## Architecture

### Entry Point

```
gol test playtest --suite night_raid [--record] [--verbose]
```

### CLI Layer (Go)

New playtest runner in `gol-tools/cli/internal/testrunner/playtest.go`:

1. **Discovery**: scans `tests/playtest/` for `.gd` files extending `AutomationPlayTestSuite`
2. **Suite matching**: `--suite night_raid` matches `playtest_night_raid.gd` (strip `playtest_` prefix, match remainder)
3. **Execution**: launches Godot in windowed mode:
   ```
   godot --path <projectDir> scenes/main.tscn -- --skip-menu --playtest=night_raid [--record]
   ```
4. **Post-processing**: if `--record`, runs `encode-frames.swift` to produce mp4 after Godot exits
5. **Report**: parses exit code + report file from `user://playtest_results/`

### Unified Test Parameter: Direct 1:1 Mapping

Each test tier has its own dedicated Godot launch arg. CLI maps directly — no shared parameter, no priority resolution, no ambiguity.

| CLI Command | Godot Launch Arg | Resolved by |
|-------------|-----------------|-------------|
| `gol test playtest --suite night_raid` | `--playtest=night_raid` | `GOL.start_game()` |
| `gol test integration --suite night_raid` | `--integration=res://tests/integration/night_raid/test_xxx.gd` | `test_main.gd` |
| `gol test unit --suite system` | `--add res://tests/unit/system/` | gdUnit4 (unchanged) |

**Godot-side resolution (per tier):**

- `--playtest=<name>`: `GOL.start_game()` loads `res://tests/playtest/playtest_<name>.gd`, instantiates as `AutomationPlayTestSuite`, uses it as the config for the full game startup path.
- `--integration=<path>`: `test_main.gd` loads the script at the given resource path, instantiates as `SceneConfig`, runs via existing integration test lifecycle.
- `--add=<path>`: gdUnit4's existing parameter, unchanged.

**Removed legacy parameters:**

| Parameter | Was used by | Status |
|-----------|-------------|--------|
| `--scenario=<name>` | `GOL._create_launch_config()` match block | **Removed** |
| `--scenario-param=k=v` | `NightRaidFullFlowVerifyConfig.apply_launch_args()` | **Removed** |
| `--config=<path>` | `test_main.gd` | **Replaced by `--integration=<path>`** |

**Removed code:**

| File | What's removed |
|------|----------------|
| `gol.gd` | `_create_launch_config()` match block (6+ hardcoded scenarios), `--scenario` / `--scenario-param` parsing |
| `test_main.gd` | `--config=` parsing (replaced by `--integration=`) |

### Startup Flow (Godot Side)

```
Engine autoloads → GOL.setup() → main._ready() → GOL.start_game()
  → _parse_launch_args() detects --playtest=night_raid
  → loads res://tests/playtest/playtest_night_raid.gd
  → instantiates as AutomationPlayTestSuite
  → PCG: generate(config.pcg_config()) → preset mode → flat grass map
  → map.accept_pcg_result() → nav grid built
  → switch_scene(config) → GOLWorld.initialize() → entities spawned
  → after_entities_spawned() → director configured, playtest loop starts
  → checkpoints validated → report written → exit
```

### Game Code Changes

| File | Change | Lines |
|------|--------|-------|
| `scripts/pcg/data/pcg_config.gd` | Add `preset` enum and `preset_grid_size` field | ~4 |
| `scripts/services/impl/service_pcg.gd` | Add preset branch in `generate()` + `_generate_flat_grass()` | ~15 |
| `scripts/gol.gd` | Add `--playtest=` parsing in `_parse_launch_args()`; in `start_game()`, load playtest config if arg present; remove `_create_launch_config()` match block + `--scenario`/`--scenario-param` parsing | net ~-15 |
| `scripts/tests/test_main.gd` | Replace `--config=` with `--integration=` | ~2 |

### PCG Preset Mode

`PCGConfig` gains a `preset` enum:

```gdscript
enum Preset { NONE, FLAT_GRASS }

var preset: Preset = Preset.NONE
var preset_grid_size: int = 20
```

`Service_PCG.generate()` checks `config.preset` first:
- `FLAT_GRASS`: generates a `preset_grid_size x preset_grid_size` grid of GRASS cells, empty RoadGraph, returns valid PCGResult
- `NONE`: runs normal pipeline

This is an official PCG capability, not a test hack. Future presets (ARENA, SMALL_VILLAGE, etc.) can be added here.

## File Structure

```
gol-project/
├── scripts/
│   └── tests/
│       ├── automation_playtest_suite.gd   ← NEW: playtest base class
│       ├── test_main.gd                   ← existing (integration tests, unchanged)
│       └── test_result.gd                 ← existing (shared)
├── tests/
│   ├── integration/
│   │   └── night_raid/
│   │       ├── test_night_raid_verify_scene.gd         ← keep
│   │       ├── test_night_raid_breach_entry_scene.gd   ← keep
│   │       └── test_night_raid_full_flow_scene.gd      ← REMOVE (replaced by playtest)
│   └── playtest/
│       └── playtest_night_raid.gd         ← NEW: night raid playtest
└── logs/
    └── playtest/                          ← output directory (gitignored)
```

## AutomationPlayTestSuite Base Class

```gdscript
class_name AutomationPlayTestSuite extends SceneConfig
```

Note: `SceneConfig extends RefCounted`. The playtest tick loop runs inside `test_run()` as a coroutine (same pattern as existing integration tests using `_wait_frames()` / `_wait_until()`). Recording is handled by injecting a helper Node into the scene tree during `after_entities_spawned()`.

### Responsibilities

- Checkpoint registration and sequential validation
- Recording lifecycle (start/stop frame capture via injected Node)
- Timeout monitoring
- Report generation (pass/fail per checkpoint + elapsed time)
- Clean exit with appropriate exit code

### Key Interface

```gdscript
# Subclass overrides:
func suite_name() -> String           # e.g. "night_raid"
func timeout_seconds() -> float       # budget, default 300 (5 min)
func setup_checkpoints() -> void      # register checkpoints in order
func check_next_checkpoint(world: GOLWorld) -> bool  # evaluate current checkpoint

# Base class provides:
func register_checkpoint(name: String) -> void
func pass_checkpoint(name: String) -> void
func is_checkpoint_passed(name: String) -> bool
func all_checkpoints_passed() -> bool
func current_checkpoint_name() -> String
```

### Lifecycle

1. `after_entities_spawned(world)` — calls `setup_checkpoints()`, injects recorder Node if `--record`
2. `test_run(world)` — coroutine loop: each frame calls `check_next_checkpoint(world)`, tracks elapsed time, checks timeout. Uses `_wait_frames(world, 1)` to yield per frame.
3. When `all_checkpoints_passed()` or timeout — stops recording, writes report, returns TestResult

### Recording Helper Node

A lightweight Node (`PlaytestRecorder`) is added to the scene tree in `after_entities_spawned()`. Its `_process()` captures viewport frames at the configured fps. The base class starts/stops it via method calls. This separates frame capture (needs Node lifecycle) from test logic (runs in coroutine).

## Night Raid Playtest Scenario

### Scene Setup

- **Map**: 20x20 flat grass (PCG preset FLAT_GRASS)
- **Entities**: reuses `NightRaidVerifyConfig` layout — walled camp (7,7)-(13,13), campfire at (10,10), player, 2 workers, 1 guard, damaged wall at (10,7) with 90 HP, door at (10,13)
- **Director**: forced to DUSK_WARNING phase at start (not NIGHT_ACTIVE like integration tests)
- **Time compression**: spawn interval multiplier set to 0.5x via `apply_launch_args` / direct config; Director drives all subsequent phase transitions naturally
- **Zombies**: NOT pre-spawned. Director spawns them naturally during NIGHT_ACTIVE phase.

### Key Difference from Integration Tests

| Aspect | Integration (verify/breach) | Playtest |
|--------|---------------------------|----------|
| Start phase | NIGHT_ACTIVE (forced) | DUSK_WARNING (natural progression) |
| Enemies | Pre-spawned, pre-configured | Director spawns naturally |
| Time flow | Frozen (speed=0) | Real time, Director-driven |
| Duration | 720-7200 frames (~12-120s) | Full cycle (~2-3 min) |
| Validation | Poll-based assertions | Sequential checkpoints |
| Recording | None | Optional video capture |

### Time Compression Strategy

- Force time to DUSK_WARNING start (skip daytime, ~1 in-game hour before night)
- Director drives DUSK → NIGHT_ACTIVE → NIGHT_PEAK → DAWN_RETREAT → DAYTIME naturally
- Spawn interval multiplier: 0.5x (halved wait between waves)
- No acceleration of behavior logic (movement, combat, repair speeds unchanged)

## Checkpoints (12)

Sequential, strictly ordered. Each must pass before the next is evaluated.

| # | Name | Phase | Condition |
|---|------|-------|-----------|
| 1 | `dusk_warning_triggered` | DUSK_WARNING | `DirectorState.current_phase == DUSK_WARNING` |
| 2 | `night_phase_entered` | NIGHT_ACTIVE | `DirectorState.current_phase == NIGHT_ACTIVE` |
| 3 | `enemies_spawned` | NIGHT_ACTIVE | At least 1 entity with `CAssaultIntent` exists |
| 4 | `enemies_approaching_walls` | NIGHT_ACTIVE | At least 1 enemy within 3 grid cells of any wall |
| 5 | `wall_under_attack` | NIGHT_ACTIVE | At least 1 wall HP < initial value |
| 6 | `worker_repairing` | NIGHT_ACTIVE | At least 1 worker's current GOAP action == repair-related |
| 7 | `wall_breached` | NIGHT_ACTIVE/PEAK | At least 1 wall entity destroyed, cell unblocked |
| 8 | `enemy_entered_camp` | NIGHT_ACTIVE/PEAK | At least 1 enemy position inside wall perimeter |
| 9 | `guard_engaging` | NIGHT_ACTIVE/PEAK | Guard's GOAP current action == Fight |
| 10 | `night_peak_reached` | NIGHT_PEAK | `DirectorState.current_phase == NIGHT_PEAK` |
| 11 | `dawn_retreat_started` | DAWN_RETREAT | `DirectorState.current_phase == DAWN_RETREAT` |
| 12 | `night_survived` | DAYTIME | `DirectorState.current_phase == DAYTIME` AND `night_number` incremented AND campfire alive |

### Checkpoint Timing Expectations

- Checkpoints 1-2: ~5-15s (dusk → night transition)
- Checkpoints 3-9: ~30-120s (combat phase)
- Checkpoints 10-11: ~30-60s (peak → retreat)
- Checkpoint 12: ~20-30s (retreat completes)
- Total expected: ~2-3 minutes

## Recording

### Activation

```bash
gol test playtest --suite night_raid --record
```

CLI passes `--record` as a Godot launch arg. Base class detects it and enables frame capture.

### Implementation (In-Process)

- Captures viewport every 250ms (4 fps)
- Saves PNG frames to `user://playtest_frames/<suite_name>/`
- On test completion, Godot exits
- CLI post-processes: calls `encode-frames.swift` to produce mp4
- Output: `logs/playtest/<suite_name>/recording.mp4`

### Why In-Process

- Game runs in windowed mode (not headless) when recording
- Uses Godot's own viewport capture (avoids macOS Metal black-frame issue)
- No dependency on debug bridge IPC
- Self-contained: no external process coordination needed during test

## Output

### Report Format

Written to `user://playtest_results/<suite_name>/report.txt` by the playtest process. CLI reads it after Godot exits.

```
=== PLAYTEST: night_raid ===
Status: PASSED | FAILED | ERROR

Checkpoints:
  [PASS]  dusk_warning_triggered        (2.1s)
  [PASS]  night_phase_entered           (8.4s)
  [PASS]  enemies_spawned               (12.7s)
  [PASS]  enemies_approaching_walls     (28.3s)
  [PASS]  wall_under_attack             (35.1s)
  [PASS]  worker_repairing              (41.6s)
  [PASS]  wall_breached                 (78.2s)
  [PASS]  enemy_entered_camp            (82.5s)
  [PASS]  guard_engaging                (84.1s)
  [PASS]  night_peak_reached            (105.3s)
  [PASS]  dawn_retreat_started          (142.7s)
  [PASS]  night_survived                (163.0s)

Total: 12/12 passed in 163.0s
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checkpoints passed |
| 1 | One or more checkpoints failed |
| 2 | Test error (timeout, crash, unhandled exception) |

### File Outputs

```
logs/playtest/night_raid/
  report.txt          ← always generated
  recording.mp4       ← only with --record
```

## Relationship to Existing Tests

- `tests/integration/night_raid/test_night_raid_full_flow_scene.gd` — **REMOVED** (replaced by this playtest)
- `tests/integration/night_raid/test_night_raid_verify_scene.gd` — **KEPT** (fast regression for wall-attack + repair mechanics)
- `tests/integration/night_raid/test_night_raid_breach_entry_scene.gd` — **KEPT** (fast regression for breach pathfinding)

Integration tests remain as fast (~10s) component-level regression. Playtest is the comprehensive behavioral validation (~3 min).

## Naming Conventions

| Current Name | New Name | Reason |
|---|---|---|
| `SceneConfig` | `IntegrationTestSuite` | Clarifies purpose (deferred to implementation) |
| `test_main.gd/.tscn` | `integration_test_main.gd/.tscn` | Clarifies purpose (deferred to implementation) |
| (new) | `AutomationPlayTestSuite` | Playtest base class |

Note: renaming SceneConfig and test_main is a follow-up task, not part of this implementation. The playtest system works with the current names.

## Future Considerations (Out of Scope)

- CI/CD integration (nightly runs, PR gate)
- Additional PCG presets (ARENA, SMALL_VILLAGE)
- Additional playtest scenarios (resource gathering, building, exploration)
- Checkpoint data snapshots (entity counts, HP values at each checkpoint)
- Renaming SceneConfig → IntegrationTestSuite

## Affected Files Inventory

All files that must be created, modified, or deleted as part of this implementation.

### New Files

| File | Purpose |
|------|---------|
| `gol-project/scripts/tests/automation_playtest_suite.gd` | Playtest base class |
| `gol-project/tests/playtest/playtest_night_raid.gd` | Night raid playtest script |
| `gol-tools/cli/internal/testrunner/playtest.go` | CLI playtest runner |

### Source Code Changes

| # | File | Change |
|---|------|--------|
| 1 | `gol-project/scripts/gol.gd` | Remove `_create_launch_config()` match block, `_parse_scenario_param()`, `--scenario`/`--scenario-param` parsing; add `--playtest=` parsing and config loading in `start_game()` |
| 2 | `gol-project/scripts/tests/test_main.gd` | Replace `--config=` with `--integration=` |
| 3 | `gol-project/scripts/gameplay/configs/night_raid_full_flow_verify_config.gd` | **DELETE** (replaced by playtest) |
| 4 | `gol-project/scripts/pcg/data/pcg_config.gd` | Add `Preset` enum + `preset_grid_size` |
| 5 | `gol-project/scripts/services/impl/service_pcg.gd` | Add preset branch in `generate()` + `_generate_flat_grass()` |
| 6 | `gol-tools/cli/cmd/test.go` | Add `playtest` to ValidArgs, `--record` flag, update Use/Long |
| 7 | `gol-tools/cli/internal/testrunner/runner.go` | Add `TierPlaytest`, update `ParseTier()` and `Run()` |
| 8 | `gol-tools/cli/internal/testrunner/sceneconfig.go` | Change `--config=` to `--integration=` in Godot command args |
| 9 | `gol-tools/cli/internal/testrunner/report.go` | Add `Playtest` results field, update totals and rendering |

### Documentation Updates

| # | File | Change |
|---|------|--------|
| 10 | `gol/CLAUDE.md` | Add playtest commands to CLI table, add `--playtest=` to game args, update test architecture section |
| 11 | `gol/AGENTS.md` | Same as CLAUDE.md (these share the test documentation) |
| 12 | `gol-project/AGENTS.md` | Add playtest tier to "Where to Look" table and command reference |
| 13 | `gol-project/tests/AGENTS.md` | Add `tests/playtest/` directory, `AutomationPlayTestSuite`, update harness table, replace `--config` with `--integration` |

### Skill File Updates

| # | File | Change |
|---|------|--------|
| 14 | `.agents/skills/gol-test-runner/SKILL.md` | Add "Direct Playtest" mode to decision matrix and routing rules |
| 15 | `.agents/skills/gol-test-runner/references/runner-prompt.md` | Add playtest tier identification, commands, output parsing; update `--config` → `--integration` |
| 16 | `.agents/skills/gol-test-runner/references/playtest-prompt.md` | Add note distinguishing `gol test playtest` (automated) from interactive live playtest |
| 17 | `.agents/skills/gol-test-writer/SKILL.md` | Add playtest routing note or explicitly scope it out |
| 18 | `.agents/skills/gol-test-writer/references/integration-prompt.md` | Update `--config` → `--integration` references |
| 19 | `.agents/skills/gol-quick-feature-dev/SKILL.md` | Update playtest mention for automated vs interactive distinction |
| 20 | `.agents/skills/gol-fix-issue/SKILL.md` | Consider adding playtest to routing matrix |

### Hooks & Config

| # | File | Change |
|---|------|--------|
| 21 | `.agents/hooks/block-sceneconfig-in-unit.sh` | Add `AutomationPlayTestSuite` blocking in `tests/unit/` |
| 22 | `.agents/hooks/block-gdunit-in-integration.sh` | Add `GdUnitTestSuite` blocking in `tests/playtest/` |

### CI/CD

| # | File | Change |
|---|------|--------|
| 23 | `gol-project/.github/workflows/tests.yml` | Change `--config=` to `--integration=`; optionally add playtest job |

### Foreman

| # | File | Change |
|---|------|--------|
| 24 | `gol-tools/foreman/tasks/play-verify.yaml` | Update `--scenario=night_raid_full_flow_verify` example to `--playtest=night_raid` |
| 25 | `gol-tools/foreman/README.md` | Update `--scenario` example in launch_args description |

### Not Modified (Historical Records)

Handoff notes, foreman logs, and sisyphus plans that reference `--config`/`--scenario`/`SceneConfig` are immutable historical records and are NOT modified.
