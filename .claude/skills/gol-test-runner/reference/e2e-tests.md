# E2E Tests — AI Debug Bridge

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

## Workflow

### Step 1: Branch Preparation (if testing a PR)

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project

# Fetch and find the branch
git fetch --prune origin
git branch -r | grep -i "136"

# Checkout
git checkout origin/worker/01/issue-136 -b test/issue-136
```

### Step 2: Read Acceptance Criteria

Read the feature spec / Issue / PR description. Translate into checkable assertions.

### Step 3: Choose Scene

| Feature | Scene | Why |
|---------|-------|-----|
| PCG map generation | `test_main.tscn` with `--config=...` | SceneConfig with full PCG pipeline |
| Gameplay (combat, AI) | `scenes/main.tscn` | Full game |
| Integration test + E2E | `test_main.tscn` with `--no-exit` | Isolated systems, inspectable |

### Step 4: Launch Game

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
/Applications/Godot.app/Contents/MacOS/Godot --scene scenes/main.tscn 2>&1 | tee /tmp/godot_e2e.log &
```

Wait ~10s, then verify:

```bash
cd /Users/dluckdu/Documents/Github/gol
node gol-tools/ai-debug/ai-debug.mjs get entity_count
```

### Step 5: Write Diagnostic Scripts

Write scripts to `/tmp/e2e_*.gd`. Rules:

- `func run()` required, returns a string
- No `extends` needed (RefCounted by default)
- All game singletons accessible: `ECS`, `GOL`, `ServiceContext`, `ScreenshotManager`
- Output format: `key=value` pairs, last line `status=PASS` or `status=FAIL`
- Keep scripts focused — one script per check
- **WRITE TO `/tmp/` ONLY** — never to gol/ or gol-project/

### Step 6: Inject and Parse

```bash
cd /Users/dluckdu/Documents/Github/gol
node gol-tools/ai-debug/ai-debug.mjs script /tmp/e2e_check_name.gd
```

### Step 7: Screenshot & Upload (Optional)

```bash
# Capture
node gol-tools/ai-debug/ai-debug.mjs screenshot

# Upload to Litterbox (72h retention, no registration)
curl -F "fileToUpload=@$HOME/Library/Application Support/Godot/app_userdata/God of Lego/ai_screenshot.png" \
  -F "reqtype=fileupload" \
  -F "time=72h" \
  https://litterbox.catbox.moe/resources/internals/api.php

# Add to GitHub Issue
cd gol-project && gh issue comment <ISSUE_NUMBER> --body "![E2E Screenshot](<URL>)"
```

### Step 8: Cleanup (MANDATORY)

```bash
# Remove temp scripts
rm -f /tmp/e2e_*.gd

# Kill game process
kill $(pgrep -f "Godot") 2>/dev/null

# Restore gol-project submodule
cd /Users/dluckdu/Documents/Github/gol/gol-project
git checkout --detach
git branch -D test/issue-* 2>/dev/null
cd /Users/dluckdu/Documents/Github/gol
git submodule update --init gol-project
```

## Common Diagnostic Patterns

### ECS Entity Count

```gdscript
func run():
	if not ECS.world:
		return "status=FAIL\nreason=No ECS world"
	return "entities=%d\nstatus=PASS" % ECS.world.entities.size()
```

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
	return "checks=%d\nfailures=%d\nstatus=%s" % [
		result.total_checks, result.failures.size(),
		"PASS" if result.passed else "FAIL"
	]
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

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Timeout after 30s" | Game not running or AIDebugBridge not loaded. Check `pgrep -f Godot` and `/tmp/godot_e2e.log` |
| Empty result from script | Check Godot log for runtime errors |
| Script compilation error | GDScript syntax issue. Fix and retry |
