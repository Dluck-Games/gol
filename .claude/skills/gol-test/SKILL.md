---
name: gol-test
description: Run and write tests for God of Lego — unit (gdUnit4), integration (SceneConfig), and E2E (AI Debug Bridge). Use when running tests, writing new tests, or deciding which test tier to use.
allowed-tools: Bash, Read, Write
---

# gol-test-runner — GOL Test Runner & Writing Guide

> **SAFETY: This skill operates from a MANAGEMENT REPO (gol/).**
> Game code lives in the `gol-project/` submodule.
> **ALL Godot and git branch operations MUST execute inside `gol-project/`.**
> **NEVER run git checkout, Godot, or create game files in the gol/ root directory.**

## Three-Tier Architecture

GOL uses a strict three-tier test architecture. **Never mix frameworks across tiers.**

| Tier | Framework | Directory | `extends` | Runner |
|------|-----------|-----------|-----------|--------|
| **Unit** | gdUnit4 | `tests/unit/` | `GdUnitTestSuite` | gdUnit4 CLI |
| **Integration** | SceneConfig | `tests/integration/` | `SceneConfig` | `test_main.tscn` |
| **E2E** | AI Debug Bridge | `/tmp/` (ephemeral) | none | live game + `ai-debug.mjs` |

### Hard Rules

- `tests/unit/` — **ONLY** `extends GdUnitTestSuite`. No `World`, no `ECS.world`, no `GOLWorld`.
- `tests/integration/` — **ONLY** `extends SceneConfig`. **No GdUnitTestSuite. No manual World construction.**
- E2E scripts are **never committed** to the repo. They live in `/tmp/` and are deleted after use.

### Decision Rule: Where Does My Test Go?

| Question | Yes → | No → |
|----------|-------|------|
| Does it need a `World` or `ECS.world`? | Integration | Unit |
| Does it test multiple systems together? | Integration | Unit |
| Does it use `GOL.setup()` / services? | Integration | Unit |
| Does it need a live game with rendering? | E2E | Integration |
| Does it need AI Debug Bridge injection? | E2E | Integration |

## Paths

| Item | Path |
|------|------|
| Godot binary | `/Applications/Godot.app/Contents/MacOS/Godot` |
| Project root | `/Users/dluckdu/Documents/Github/gol/gol-project` |
| Management repo | `/Users/dluckdu/Documents/Github/gol` |
| AI Debug Bridge | `gol-tools/ai-debug/ai-debug.mjs` |

## Running All Tests

```bash
# From management repo root — runs both phases with ASCII report
./run-tests.command
```

Phase 1 runs gdUnit4 on `tests/unit/`. Phase 2 discovers and runs all SceneConfig tests in `tests/integration/` recursively.

---

## Tier 1: Unit Tests (gdUnit4)

See: [reference/unit-tests.md](reference/unit-tests.md)

### Quick Run

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project

# All unit tests
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/unit/ -c --ignoreHeadlessMode

# Specific file
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/unit/system/test_foo.gd -c --ignoreHeadlessMode

# Specific directory
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/unit/ai/ -c --ignoreHeadlessMode
```

---

## Tier 2: Integration Tests (SceneConfig)

See: [reference/integration-tests.md](reference/integration-tests.md)

### Quick Run

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project

# Single test
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --scene scenes/tests/test_main.tscn \
  -- --config=res://tests/integration/test_combat.gd

# Keep running for inspection (add --no-exit)
/Applications/Godot.app/Contents/MacOS/Godot --path . \
  --scene scenes/tests/test_main.tscn \
  -- --config=res://tests/integration/flow/test_flow_component_drop_scene.gd --no-exit
```

Exit codes: `0` = pass, `1` = fail.

---

## Tier 3: E2E Tests (AI Debug Bridge)

See: [reference/e2e-tests.md](reference/e2e-tests.md)

### Quick Run

```bash
# 1. Launch game
cd /Users/dluckdu/Documents/Github/gol/gol-project
/Applications/Godot.app/Contents/MacOS/Godot --scene scenes/main.tscn 2>&1 | tee /tmp/godot_e2e.log &

# 2. Wait ~10s, then verify
cd /Users/dluckdu/Documents/Github/gol
node gol-tools/ai-debug/ai-debug.mjs get entity_count

# 3. Inject diagnostic script
node gol-tools/ai-debug/ai-debug.mjs script /tmp/e2e_check.gd

# 4. Cleanup
rm -f /tmp/e2e_*.gd
kill $(pgrep -f "Godot") 2>/dev/null
```

---

## Common Reference

### Test Directory Structure

```
tests/
├── unit/                                    # gdUnit4 ONLY
│   ├── ai/                                  # GOAP planner + action suites
│   ├── debug/                               # AI Debug Bridge unit tests
│   ├── pcg/                                 # PCG single-phase tests
│   ├── service/                             # Service-layer unit tests
│   ├── system/                              # ECS system unit tests
│   └── test_*.gd                            # Component/entity tests
└── integration/                             # SceneConfig ONLY
    ├── test_combat.gd                       # Player+enemy combat
    ├── pcg/                                 # Full-pipeline PCG tests
    └── flow/                                # Multi-system gameplay flows
```

### Common System Paths (for integration tests)

| System | Path | Group |
|--------|------|-------|
| SHP | `res://scripts/systems/s_hp.gd` | gameplay |
| SDamage | `res://scripts/systems/s_damage.gd` | gameplay |
| SDead | `res://scripts/systems/s_dead.gd` | gameplay |
| SMove | `res://scripts/systems/s_move.gd` | gameplay |
| SAI | `res://scripts/systems/s_ai.gd` | gameplay |
| SPerception | `res://scripts/systems/s_perception.gd` | gameplay |
| SMeleeAttack | `res://scripts/systems/s_melee_attack.gd` | gameplay |
| SCollision | `res://scripts/systems/s_collision.gd` | physics |
| SFireBullet | `res://scripts/systems/s_fire_bullet.gd` | gameplay |
| SEnemySpawn | `res://scripts/systems/s_enemy_spawn.gd` | gameplay |
| SPickup | `res://scripts/systems/s_pickup.gd` | gameplay |

### Common Recipe IDs (for integration tests)

| Recipe | Description |
|--------|-------------|
| `player` | Player character |
| `enemy_basic` | Basic zombie |
| `enemy_fire` | Fire elemental zombie |
| `enemy_wet` | Water elemental zombie |
| `enemy_cold` | Ice elemental zombie |
| `enemy_electric` | Electric elemental zombie |
| `survivor` | Guard NPC |
| `campfire` | Player base/campfire |
| `weapon_rifle` | Rifle weapon |
| `weapon_pistol` | Pistol weapon |

### Key File Locations

| Purpose | Path |
|---------|------|
| SceneConfig base class | `scripts/gameplay/ecs/scene_config.gd` |
| TestResult class | `scripts/tests/test_result.gd` |
| Test entry point (integration) | `scenes/tests/test_main.tscn` |
| Empty test scene | `scenes/maps/l_test.tscn` |
| gdUnit4 CLI | `addons/gdUnit4/bin/GdUnitCmdTool.gd` |
| AI Debug Bridge CLI | `gol-tools/ai-debug/ai-debug.mjs` |

### Gotchas

- **GECS deep-copy**: `World.add_entity()` calls `Entity._initialize()` which does `components.values().duplicate_deep()`. Non-`@export` runtime fields are reset. Set them AFTER `add_entity()`.
- **World.entities**: Entities live under `entity_nodes_root`, not as direct World children. Use `world.entities` (Array[Entity]) to iterate.
- **No enemy recipe has CWeapon by default**: `enemy_raider` inherits `enemy_basic` but doesn't include CWeapon. Manually attach in test if needed.
