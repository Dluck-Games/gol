---
name: gol-e2e
description: Run E2E acceptance tests against a live Godot game instance using AI Debug Bridge. Use when verifying features, accepting PRs, or validating bug fixes against functional specs.
allowed-tools: Bash, Read, Write
---

# gol-e2e — End-to-End Acceptance Testing

> **SAFETY: This skill operates from a MANAGEMENT REPO (gol/).**
> Game code lives in the `gol-project/` submodule.
> **ALL Godot and git branch operations MUST execute inside `gol-project/`.**
> **NEVER run git checkout, Godot, or create game files in the gol/ root directory.**

## What This Is

E2E tests verify features by running diagnostic scripts inside a **live game instance** via the AI Debug Bridge. No test code is committed to the repository. The AI reads a functional spec (Issue/ticket), writes temporary diagnostic scripts, injects them into the running game, and judges PASS/FAIL.

## When to Use

- Accepting a feature implementation against its Issue spec
- Verifying a bug fix in the running game
- Validating PCG output on the actual rendered map
- Any check that requires a live game process (rendering, ECS entities, game state)

## Prerequisites

- Godot installed at `/Applications/Godot.app/Contents/MacOS/Godot`
- Working directory: `/Users/dluckdu/Documents/Github/gol`
- AI Debug Bridge enabled (autoload in project.godot)

---

## Phase 0: Branch Preparation (MANDATORY before any test)

When testing a specific issue/PR, you MUST switch `gol-project` to the correct branch **before** launching the game.

### 0.1 Safety Checks

```bash
# VERIFY you are in the management repo root
pwd
# Expected: /Users/dluckdu/Documents/Github/gol

# ALWAYS cd into the submodule for ANY git or Godot operation
cd /Users/dluckdu/Documents/Github/gol/gol-project
```

**HARD RULES:**
- **NEVER** run `git checkout` / `git switch` / `git branch` from `/Users/dluckdu/Documents/Github/gol/` (the root)
- **NEVER** run Godot `--path .` from the root — always `--path gol-project` or `cd gol-project` first
- **NEVER** create or copy `.gd`, `.tscn`, `.tres` files into the gol/ root

### 0.2 Find the Issue Branch

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project

# Fetch latest remote branches
git fetch --prune origin

# Search for issue-related branches (e.g., issue-136)
git branch -r | grep -i "136"

# Common branch patterns in this project:
#   origin/worker/01/issue-NNN
#   origin/coder/01/issue-NNN
#   origin/fix/issue-NNN-description
#   origin/feature/description
```

### 0.3 Switch to the Branch

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project

# Ensure clean working tree first
git status
# If dirty, stash or restore:
#   git stash push -m "pre-e2e"
#   OR git restore .

# Checkout the branch
git checkout origin/worker/01/issue-136 -b test/issue-136
# Or if branch already exists locally:
#   git checkout test/issue-136 && git pull

# Verify
git log --oneline -3
```

### 0.4 Post-Test Cleanup (MANDATORY)

After testing is complete, restore gol-project to match the management repo:

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project

# Delete the temporary test branch
git checkout --detach
git branch -D test/issue-136 2>/dev/null

# Restore to management repo's recorded commit
cd /Users/dluckdu/Documents/Github/gol
git submodule update --init gol-project

# Verify clean state
git status
# Expected: nothing to commit, working tree clean
```

---

## Workflow

### Step 1: Read the Acceptance Criteria

Read the feature spec / Issue / PR description. Identify concrete, verifiable conditions. Example:

> "Crosswalks should appear at distance 2 from junctions where road depth >= 3"

Translate into checkable assertions:
- `CrosswalkValidator.validate()` reports 0 failures
- `crosswalk_positions.size() > 0`
- No crosswalk on straight roads

### Step 2: Choose the Test Scene

| Feature | Scene | Why |
|---------|-------|-----|
| PCG map generation | `scenes/tests/test_main.tscn` with `--config=res://tests/integration/test_pcg_map.gd` | SceneConfig with full PCG pipeline |
| Gameplay (combat, AI, movement) | `scenes/main.tscn` | Full game with player, enemies, etc. |
| UI/HUD | `scenes/main.tscn` | Needs full game context |
| Integration test (combat, AI) | `scenes/tests/test_main.tscn` with `--config=...` | Isolated systems, no PCG overhead |

### Step 3: Launch Game

```bash
# ALWAYS launch from inside gol-project or use --path
cd /Users/dluckdu/Documents/Github/gol/gol-project
/Applications/Godot.app/Contents/MacOS/Godot --scene <SCENE> 2>&1 | tee /tmp/godot_e2e.log &
```

Wait for initialization (~10s), then verify:

```bash
cd /Users/dluckdu/Documents/Github/gol
node gol-tools/ai-debug/ai-debug.mjs get entity_count
```

If timeout: game didn't start. Check `/tmp/godot_e2e.log` for errors.

#### Launching with Integration Test Config

For testing specific systems in isolation without the full PCG overhead, use the integration test scene with a SceneConfig:

```bash
# ALWAYS launch from inside gol-project or use --path
cd /Users/dluckdu/Documents/Github/gol/gol-project
/Applications/Godot.app/Contents/MacOS/Godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_combat.gd --no-exit 2>&1 | tee /tmp/godot_e2e.log &
```

**Key arguments:**
- `--config=res://tests/integration/test_combat.gd` — Path to a GDScript extending SceneConfig that defines what systems/entities to load
- `--no-exit` — Keeps the scene running after setup so AI Debug Bridge can inject diagnostic scripts (without this, the test runs and exits automatically)

The integration test system uses SceneConfig subclasses to configure the test environment. The test runs and exits with exit code 0/1 automatically unless `--no-exit` is provided. With `--no-exit`, you can inject diagnostic scripts and interact with the running game.

### Step 4: Write Diagnostic Scripts

Write scripts to `/tmp/e2e_*.gd`. Rules:

- `func run()` required, returns a string
- No `extends` needed (RefCounted by default, handled correctly)
- All game singletons accessible: `ECS`, `GOL`, `ServiceContext`, `ScreenshotManager`
- All game classes accessible: `CrosswalkValidator`, `PCGContext`, `PCGCell`, etc.
- Output format: `key=value` pairs, last line `status=PASS` or `status=FAIL`
- Keep scripts focused — one script per check, not one mega-script
- **WRITE TO `/tmp/` ONLY** — never to gol/ or gol-project/

**Output Convention:**

```
key1=value1
key2=value2
status=PASS
```

or on failure:

```
key1=value1
reason=description of what went wrong
status=FAIL
```

### Step 5: Inject and Parse

```bash
cd /Users/dluckdu/Documents/Github/gol
node gol-tools/ai-debug/ai-debug.mjs script /tmp/e2e_check_name.gd
```

**Success output:**
```
Sending: script
Script result: checks=1417
failures=0
status=PASS
```

**Failure output:**
```
Sending: script
Script result: failures=3
reason=[distance_2_crosswalk] pos=(5,-3) expected crosswalk got normal_road
status=FAIL
```

**Error output (script bug):**
```
Error: failed to compile script (error 43)
```

### Step 6: Screenshot & Upload (Optional)

For visual features, capture a screenshot and upload to share in GitHub Issue/PR:

#### 6.1 Capture Screenshot

```bash
node gol-tools/ai-debug/ai-debug.mjs screenshot
```

Screenshot saved to: `~/Library/Application Support/Godot/app_userdata/God of Lego/ai_screenshot.png`

#### 6.2 Upload to Litterbox (Recommended)

Use Litterbox (Catbox temporary storage) — **no registration required**, supports up to 1GB files.

**Upload command:**

```bash
curl -F "fileToUpload=@/Users/dluckdu/Library/Application Support/Godot/app_userdata/God of Lego/ai_screenshot.png" \
  -F "reqtype=fileupload" \
  -F "time=72h" \
  https://litterbox.catbox.moe/resources/internals/api.php
```

**Parameters:**
- `time`: Expiration time — `1h`, `12h`, `24h`, or `72h` (default: 72h for maximum retention)

**Response:** Returns direct image URL (e.g., `https://litter.catbox.moe/xxxxx.png`)

#### 6.3 Add to GitHub Issue/PR

```bash
cd gol-project && gh issue comment <ISSUE_NUMBER> --body "![E2E Screenshot](<URL_FROM_STEP_6_2>)"
```

**Why Litterbox:**
- ✅ No registration or API key needed
- ✅ No daily upload limits
- ✅ 72-hour retention (sufficient for issue comments)
- ✅ Supports files up to 1GB

### Step 7: Report Results

Summarize findings against the acceptance criteria:

```
## E2E Test Report: [Feature Name]

Scene: scenes/tests/l_test_pcg.tscn
Branch: worker/01/issue-136
Seed: (if applicable)

| Check | Result | Detail |
|-------|--------|--------|
| CrosswalkValidator passes | PASS | 1417 checks, 0 failures |
| Crosswalks exist | PASS | 198 crosswalks found |
| TileMapLayer rendered | PASS | 10008 cells on MapRenderLayer |

Overall: PASS
```

### Step 8: Cleanup (MANDATORY)

```bash
# Remove temp scripts
rm -f /tmp/e2e_*.gd

# Kill game process
kill $(pgrep -f "Godot") 2>/dev/null

# Restore gol-project submodule (Phase 0.4)
cd /Users/dluckdu/Documents/Github/gol/gol-project
git checkout --detach
git branch -D test/issue-* 2>/dev/null
cd /Users/dluckdu/Documents/Github/gol
git submodule update --init gol-project

# Final verification — must be clean
git status
```

---

## Common Diagnostic Patterns

### PCG CrosswalkValidator

```gdscript
func run():
    var pcg = ServiceContext.pcg()
    if pcg.last_result == null:
        return "status=FAIL\nreason=No PCG result"
    var context = PCGContext.new(pcg.last_result.config.pcg_seed)
    for pos in pcg.last_result.grid.keys():
        var cell = pcg.last_result.grid[pos]
        context.grid[pos] = cell
        if cell.is_road():
            context.road_cells[pos] = true
    context.road_graph = pcg.last_result.road_graph
    var validator = CrosswalkValidator.new()
    var result = validator.validate(context)
    return "checks=%d\nfailures=%d\njunctions=%d\ncrosswalks=%d\nstop_lines=%d\nstatus=%s" % [
        result.total_checks, result.failures.size(), result.junctions.size(),
        result.crosswalk_positions.size(), result.stop_line_positions.size(),
        "PASS" if result.passed else "FAIL"
    ]
```

### ECS Entity Count

```gdscript
func run():
    if not ECS.world:
        return "status=FAIL\nreason=No ECS world"
    return "entities=%d\nstatus=PASS" % ECS.world.entities.size()
```

### Tile Render Verification

```gdscript
func run():
    var root = Engine.get_main_loop().root
    var layers := []
    _find(root, layers)
    var total := 0
    for l in layers:
        total += l.get_used_cells().size()
    return "layers=%d\ncells=%d\nstatus=%s" % [layers.size(), total, "PASS" if total > 0 else "FAIL"]

func _find(node, result):
    if node is TileMapLayer:
        result.append(node)
    for child in node.get_children():
        _find(child, result)
```

### PCG Stats

```gdscript
func run():
    var pcg = ServiceContext.pcg()
    if pcg.last_result == null:
        return "status=FAIL\nreason=No PCG result"
    var grid = pcg.last_result.grid
    var road := 0
    var has_variant := 0
    for pos in grid.keys():
        var cell = grid[pos]
        if cell.is_road():
            road += 1
        if cell.data.has("tile_variant") and cell.data["tile_variant"] != "":
            has_variant += 1
    return "total=%d\nroad=%d\nhas_variant=%d\nstatus=%s" % [
        grid.size(), road, has_variant,
        "PASS" if road > 0 else "FAIL"
    ]
```

## Troubleshooting

### "Timeout after 30s"

Game not running or AIDebugBridge not loaded. Check:
```bash
pgrep -f "Godot"
cat /tmp/godot_e2e.log | tail -20
```

### Empty result from script

Check Godot log for runtime errors:
```bash
cat /tmp/godot_e2e.log | grep -E "ERROR|SCRIPT ERROR" | tail -10
```

### Script compilation error

GDScript syntax issue. The error code maps to Godot's Error enum. Fix the script and retry.

## Key Principle

The diagnostic scripts are **ephemeral**. They are written to `/tmp/`, executed once, and deleted. The **acceptance criteria** live in the feature spec (Issue/PR). The scripts are just the mechanism to check those criteria — like a QA tester typing console commands. Different AI sessions may write different scripts to verify the same spec, and that's fine.
