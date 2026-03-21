# AI Debug Screenshot Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the ai-debug screenshot tool with delay parameters, piggyback screenshots on any command, multi-frame capture, and a JSON IPC protocol.

**Architecture:** Three-file change across two submodules. Game side (GDScript) handles JSON command parsing, async capture scheduling, and frame-synced screenshots. CLI side (Node.js) sends JSON commands, parses JSON results, and supports `--screenshot` flag on all commands. Backward compatible via first-character detection (`{` → JSON, else legacy).

**Tech Stack:** GDScript (Godot 4.6), Node.js ESM, file-based IPC

**Spec:** `docs/superpowers/specs/2026-03-21-ai-debug-screenshot-upgrade-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `gol-project/scripts/debug/screenshot_manager.gd` | Modify | Remove legacy request/ready polling, become pure utility |
| `gol-project/scripts/debug/ai_debug_bridge.gd` | Modify | JSON protocol, sync screenshot w/ delay, piggyback capture, fetch command |
| `gol-tools/ai-debug/ai-debug.mjs` | Modify | JSON command serialization, --screenshot flag, fetch subcommand, dynamic timeout |
| `gol-tools/ai-debug/e2e_test_screenshot_upgrade.sh` | Create | E2E test covering all new screenshot flows |

---

### Task 1: Clean Up ScreenshotManager (Remove Legacy Polling)

**Files:**
- Modify: `gol-project/scripts/debug/screenshot_manager.gd`

- [ ] **Step 1: Remove legacy constants and polling state**

Remove these lines from the top of the file:

```gdscript
# DELETE these constants:
const POLL_INTERVAL := 0.1
const SIGNAL_DIR := "user://ai_signals"
const REQUEST_FILE := "user://ai_signals/request"
const READY_FILE := "user://ai_signals/ready"

# DELETE this variable:
var _poll_timer: float = 0.0
```

- [ ] **Step 2: Remove `_process()` and `_check_request_signal()`**

Delete the entire `_process()` method (lines 32-44) and `_check_request_signal()` method (lines 68-82).

- [ ] **Step 3: Remove `ai_signals` dir creation from `_ensure_runtime_dirs()`**

In `_ensure_runtime_dirs()`, remove the line `dir.make_dir_recursive("ai_signals")`. The ai_signals directory is owned by AIDebugBridge, not ScreenshotManager.

- [ ] **Step 4: Remove `get_signal_dir()`**

Delete the `get_signal_dir()` method (lines 174-175) — it references the removed `SIGNAL_DIR` constant and was only useful for the legacy IPC path.

- [ ] **Step 5: Verify the file compiles**

The remaining file should have: constants (SCREENSHOT_DIR, PREFIX, EXTENSION, RESIZE_*, MAX_HISTORY), `@export var enabled`, `_viewport`, `_latest_screenshot_path`, `_ready()`, `_ensure_runtime_dirs()`, `_restore_latest_screenshot_path()`, `_capture_and_save()`, `_build_screenshot_path()`, `_prune_old_screenshots()`, `_list_screenshot_files()`, `capture_now()`, `get_screenshot_path()`.

Verify: No references to removed constants remain. `enabled` export is kept (may be useful for future toggle even though `_process` is gone).

- [ ] **Step 6: Commit**

```bash
cd gol-project && git add scripts/debug/screenshot_manager.gd && git commit -m "refactor: remove legacy request/ready polling from ScreenshotManager

ScreenshotManager is now a pure utility class. All screenshot
triggering goes through AIDebugBridge."
```

---

### Task 2: AIDebugBridge — JSON Parsing Layer + Re-entrancy Guard

**Files:**
- Modify: `gol-project/scripts/debug/ai_debug_bridge.gd`

This task adds the JSON protocol foundation without changing any command behavior. After this task, both JSON and legacy commands work identically.

- [ ] **Step 1: Add re-entrancy guard variable**

Add after the existing `var _poll_timer` line:

```gdscript
var _command_in_progress: bool = false
```

- [ ] **Step 2: Guard `_process()` against re-entrancy**

Replace the current `_process()` body with:

```gdscript
func _process(delta: float) -> void:
	if _command_in_progress:
		return
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		if FileAccess.file_exists(COMMAND_FILE):
			_execute_command_file()
```

- [ ] **Step 3: Rename `_execute_command()` to `_execute_command_legacy()`**

Rename the existing `_execute_command(cmd_line: String) -> String` to `_execute_command_legacy(cmd_line: String) -> String`. This preserves the legacy space-delimited parsing path.

- [ ] **Step 4: Add `_write_result()` helper**

Add a helper that writes the result file, used by both JSON and legacy paths:

```gdscript
func _write_result(content: String) -> void:
	var out := FileAccess.open(RESULT_FILE, FileAccess.WRITE)
	if out:
		out.store_string(content)
		out.close()
```

- [ ] **Step 5: Add `_write_json_result()` helper**

```gdscript
func _write_json_result(data: Dictionary) -> void:
	_write_result(JSON.stringify(data))
```

- [ ] **Step 6: Add `_execute_command_json()` method**

This dispatches JSON commands. For now it calls the same legacy handlers by converting Dictionary args to Array. The `screenshot` field (piggyback) will be added in Task 4.

```gdscript
func _execute_command_json(cmd_dict: Dictionary) -> void:
	var cmd: String = cmd_dict.get("cmd", "")
	if cmd.is_empty():
		_write_json_result({"result": "Error: missing 'cmd' field"})
		return

	var result: String
	if cmd == "screenshot":
		# Will be replaced in Task 3 with delay/count/interval support
		result = _handle_screenshot([])
	elif cmd == "fetch":
		# Will be implemented in Task 4
		_write_json_result({"result": null, "status": "error", "message": "fetch not yet implemented"})
		return
	elif _handlers.has(cmd):
		var args_raw = cmd_dict.get("args", [])
		var args: Array = args_raw if args_raw is Array else []
		result = _handlers[cmd].call(args)
	else:
		_write_json_result({"result": "Unknown command: %s" % cmd})
		return

	_write_json_result({"result": result})
```

- [ ] **Step 7: Update `_execute_command_file()` with JSON detection**

Replace the current `_execute_command_file()` with:

```gdscript
func _execute_command_file() -> void:
	var file := FileAccess.open(COMMAND_FILE, FileAccess.READ)
	if not file:
		return

	var content := file.get_as_text().strip_edges()
	file.close()
	DirAccess.remove_absolute(COMMAND_FILE)

	if content.is_empty():
		return

	print("AIDebugBridge: executing command: ", content)

	if content.begins_with("{"):
		# JSON protocol path
		var parsed = JSON.parse_string(content)
		if parsed == null or not parsed is Dictionary:
			_write_json_result({"result": "Error: invalid JSON"})
			return
		_command_in_progress = true
		_execute_command_json(parsed)
		_command_in_progress = false
	else:
		# Legacy plain-text path (backward compatible)
		var result := _execute_command_legacy(content)
		print("AIDebugBridge: result: ", result)
		_write_result(result)
```

- [ ] **Step 8: Commit**

```bash
cd gol-project && git add scripts/debug/ai_debug_bridge.gd && git commit -m "feat: add JSON protocol layer to AIDebugBridge

JSON commands detected by first char '{'. Legacy plain-text
commands preserved for backward compatibility. Re-entrancy
guard added for upcoming async screenshot support."
```

---

### Task 3: AIDebugBridge — Synchronous Screenshot with Delay + Multi-Frame

**Files:**
- Modify: `gol-project/scripts/debug/ai_debug_bridge.gd`

- [ ] **Step 1: Add screenshot parameter constants**

Add after the existing constants block:

```gdscript
const MAX_SCREENSHOT_DELAY := 30.0
const MAX_SCREENSHOT_COUNT := 20
const MAX_SCREENSHOT_INTERVAL := 10.0
```

- [ ] **Step 2: Add `_parse_screenshot_opts()` helper**

Extracts and clamps screenshot parameters from a Dictionary:

```gdscript
func _parse_screenshot_opts(opts: Dictionary) -> Dictionary:
	return {
		"delay": clampf(float(opts.get("delay", 0.0)), 0.0, MAX_SCREENSHOT_DELAY),
		"count": clampi(int(opts.get("count", 1)), 1, MAX_SCREENSHOT_COUNT),
		"interval": clampf(float(opts.get("interval", 1.0)), 0.1, MAX_SCREENSHOT_INTERVAL),
	}
```

- [ ] **Step 3: Add `_capture_with_frame_sync()` helper**

Waits for the frame to finish rendering, then captures:

```gdscript
func _capture_with_frame_sync() -> String:
	await RenderingServer.frame_post_draw
	return ScreenshotManager.capture_now()
```

- [ ] **Step 4: Add `_handle_screenshot_json()` method**

Synchronous screenshot handler with delay/count/interval support. This is an async function (uses `await`), which is why the re-entrancy guard from Task 2 is needed.

```gdscript
func _handle_screenshot_json(args: Dictionary) -> void:
	var opts := _parse_screenshot_opts(args)
	var delay: float = opts["delay"]
	var count: int = opts["count"]
	var interval: float = opts["interval"]

	# Wait for initial delay
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	# Capture screenshots
	var paths: Array[String] = []
	for i in range(count):
		if i > 0:
			await get_tree().create_timer(interval).timeout
		var p := await _capture_with_frame_sync()
		if not p.is_empty():
			paths.append(p)

	# Write result
	if paths.is_empty():
		_write_json_result({"result": "Error: failed to capture screenshot"})
	elif paths.size() == 1:
		_write_json_result({"result": paths[0]})
	else:
		_write_json_result({"result": paths})
```

- [ ] **Step 5: Update `_execute_command_json()` to call the new handler**

Replace the screenshot branch in `_execute_command_json()`:

```gdscript
	if cmd == "screenshot":
		var args = cmd_dict.get("args", {})
		if not args is Dictionary:
			args = {}
		await _handle_screenshot_json(args)
		return
```

- [ ] **Step 6: Make `_execute_command_json()` async-aware**

Since `_handle_screenshot_json` uses `await`, the call in `_execute_command_json` also needs `await`. Update the function signature — it becomes implicitly async when it contains `await`. The `_execute_command_file()` caller must also `await` it.

In `_execute_command_file()`, change:
```gdscript
		_command_in_progress = true
		_execute_command_json(parsed)
		_command_in_progress = false
```
to:
```gdscript
		_command_in_progress = true
		await _execute_command_json(parsed)
		_command_in_progress = false
```

**IMPORTANT: `_execute_command_file()` is intentionally called WITHOUT `await` from `_process()`.** This is a fire-and-forget pattern: `_process()` cannot be async in GDScript. When `_execute_command_file()` hits its first `await`, control returns to `_process()` which finishes normally. The re-entrancy guard (`_command_in_progress = true` set before the await) protects against `_process()` polling new commands before the current one completes. When the awaited operation finishes, execution resumes and eventually `_command_in_progress = false` is set. **Do NOT try to `await _execute_command_file()` in `_process()`.**

- [ ] **Step 7: Commit**

```bash
cd gol-project && git add scripts/debug/ai_debug_bridge.gd && git commit -m "feat: synchronous screenshot with delay and multi-frame capture

screenshot command now accepts delay/count/interval parameters.
Uses RenderingServer.frame_post_draw for frame-accurate captures."
```

---

### Task 4: AIDebugBridge — Piggyback Screenshot + Fetch + Capture Lifecycle

**Files:**
- Modify: `gol-project/scripts/debug/ai_debug_bridge.gd`

- [ ] **Step 1: Add capture tracking state**

Add after the existing variables:

```gdscript
const CAPTURE_EXPIRY_SECONDS := 60.0
const CAPTURE_CLEANUP_INTERVAL := 5.0

var _pending_captures: Dictionary = {}  # capture_id -> {paths, status, total, completed_at}
var _capture_cleanup_timer: float = 0.0
```

- [ ] **Step 2: Add `_generate_capture_id()` helper**

```gdscript
func _generate_capture_id() -> String:
	var unix_ms := int(Time.get_unix_time_from_system() * 1000)
	return "cap_%d" % unix_ms
```

- [ ] **Step 3: Add `_schedule_piggyback_screenshot()` method**

This creates a capture_id, starts a background coroutine, and returns the id immediately:

```gdscript
func _schedule_piggyback_screenshot(opts: Dictionary) -> String:
	var parsed := _parse_screenshot_opts(opts)
	var capture_id := _generate_capture_id()

	_pending_captures[capture_id] = {
		"paths": [] as Array[String],
		"status": "pending",
		"total": parsed["count"],
		"completed_at": 0,
	}

	# Fire-and-forget coroutine
	_run_piggyback_capture(capture_id, parsed)
	return capture_id


func _run_piggyback_capture(capture_id: String, opts: Dictionary) -> void:
	var delay: float = opts["delay"]
	var count: int = opts["count"]
	var interval: float = opts["interval"]

	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	for i in range(count):
		if i > 0:
			await get_tree().create_timer(interval).timeout
		var p := await _capture_with_frame_sync()
		if not p.is_empty() and _pending_captures.has(capture_id):
			_pending_captures[capture_id]["paths"].append(p)

	if _pending_captures.has(capture_id):
		_pending_captures[capture_id]["status"] = "ready"
		_pending_captures[capture_id]["completed_at"] = Time.get_ticks_msec()
```

- [ ] **Step 4: Add `_handle_fetch_json()` method**

```gdscript
func _handle_fetch_json(args: Dictionary) -> void:
	var capture_id: String = args.get("capture_id", "")
	if capture_id.is_empty():
		_write_json_result({"result": null, "status": "error", "message": "Missing capture_id"})
		return

	if not _pending_captures.has(capture_id):
		_write_json_result({"result": null, "status": "error", "message": "Capture not found: %s" % capture_id})
		return

	var capture: Dictionary = _pending_captures[capture_id]
	if capture["status"] == "pending":
		var done: int = capture["paths"].size()
		var total: int = capture["total"]
		_write_json_result({"result": null, "status": "pending", "progress": "%d/%d" % [done, total]})
	else:
		_write_json_result({"result": capture["paths"], "status": "ready"})
```

- [ ] **Step 5: Add capture cleanup to `_process()`**

Add after the existing poll logic in `_process()`:

```gdscript
	_capture_cleanup_timer += delta
	if _capture_cleanup_timer >= CAPTURE_CLEANUP_INTERVAL:
		_capture_cleanup_timer = 0.0
		_cleanup_expired_captures()
```

Add the cleanup method:

```gdscript
func _cleanup_expired_captures() -> void:
	var now := Time.get_ticks_msec()
	var expired: Array[String] = []
	for id in _pending_captures:
		var cap: Dictionary = _pending_captures[id]
		if cap["status"] == "ready" and cap["completed_at"] > 0:
			if (now - cap["completed_at"]) > CAPTURE_EXPIRY_SECONDS * 1000:
				expired.append(id)
	for id in expired:
		_pending_captures.erase(id)
```

- [ ] **Step 6: Wire piggyback and fetch into `_execute_command_json()`**

Update `_execute_command_json()`:

1. Replace the fetch branch:
```gdscript
	elif cmd == "fetch":
		var args = cmd_dict.get("args", {})
		if not args is Dictionary:
			args = {}
		_handle_fetch_json(args)
		return
```

2. **Replace** the final `_write_json_result({"result": result})` line at the bottom of the function with the piggyback check:
```gdscript
	# Check for piggyback screenshot
	var screenshot_opts = cmd_dict.get("screenshot", null)
	if screenshot_opts is Dictionary:
		var capture_id := _schedule_piggyback_screenshot(screenshot_opts)
		_write_json_result({"result": result, "capture_id": capture_id})
	else:
		_write_json_result({"result": result})
```

- [ ] **Step 7: Commit**

```bash
cd gol-project && git add scripts/debug/ai_debug_bridge.gd && git commit -m "feat: piggyback screenshot and fetch command for async capture

Any JSON command can now include a 'screenshot' field for
non-blocking capture. Fetch retrieves results by capture_id.
Captures auto-expire 60s after completion."
```

---

### Task 5: CLI Upgrade — JSON Protocol + Screenshot Flags + Fetch

**Files:**
- Modify: `gol-tools/ai-debug/ai-debug.mjs`

- [ ] **Step 1: Add `parseFlags()` utility function**

Add after the constants block. This extracts `--flag value` pairs from the args array, returning `{flags, positionalArgs}`:

```javascript
function parseFlags(args) {
    const flags = {};
    const positional = [];
    let i = 0;
    while (i < args.length) {
        if (args[i] === '--screenshot' || args[i] === '-s') {
            flags.screenshot = true;
            i++;
        } else if (args[i] === '--delay' || args[i] === '-d') {
            flags.delay = parseFloat(args[++i]) || 0;
            i++;
        } else if (args[i] === '--count' || args[i] === '-c') {
            flags.count = parseInt(args[++i]) || 1;
            i++;
        } else if (args[i] === '--interval' || args[i] === '-i') {
            flags.interval = parseFloat(args[++i]) || 1;
            i++;
        } else {
            positional.push(args[i]);
            i++;
        }
    }
    return { flags, positional };
}
```

- [ ] **Step 2: Add `buildScreenshotOpts()` helper**

Builds the screenshot options dict from parsed flags:

```javascript
function buildScreenshotOpts(flags) {
    const opts = {};
    if (flags.delay !== undefined) opts.delay = flags.delay;
    if (flags.count !== undefined) opts.count = flags.count;
    if (flags.interval !== undefined) opts.interval = flags.interval;
    return opts;
}
```

- [ ] **Step 3: Add `calculateTimeout()` helper**

```javascript
function calculateTimeout(flags) {
    const delay = flags.delay || 0;
    const count = flags.count || 1;
    const interval = flags.interval || 1;
    return delay + Math.max(0, count - 1) * interval + DEFAULT_TIMEOUT;
}
```

- [ ] **Step 4: Update `sendCommand()` to accept JSON objects and parse JSON results**

Replace the current `sendCommand()`:

```javascript
async function sendCommand(cmd, timeoutSeconds = DEFAULT_TIMEOUT) {
    await ensureSignalDir();
    cleanupStaleFiles();

    const payload = typeof cmd === 'object' ? JSON.stringify(cmd) : cmd;
    fs.writeFileSync(COMMAND_FILE, payload);
    console.error(`Sending: ${payload}`);

    const startTime = Date.now();
    const timeoutMs = timeoutSeconds * 1000;

    while (Date.now() - startTime < timeoutMs) {
        if (fs.existsSync(RESULT_FILE)) {
            const raw = fs.readFileSync(RESULT_FILE, 'utf8');
            fs.unlinkSync(RESULT_FILE);
            // Parse JSON result if possible, otherwise return as plain text
            if (raw.startsWith('{') || raw.startsWith('[')) {
                try { return JSON.parse(raw); } catch (_) { /* fall through */ }
            }
            return raw;
        }
        await new Promise(r => setTimeout(r, POLL_INTERVAL_MS));
    }

    throw new Error(`Timeout after ${timeoutSeconds}s. Is the game running?`);
}
```

Note: `console.log` changed to `console.error` for the "Sending:" message so it doesn't mix with stdout result output.

- [ ] **Step 5: Add `formatResult()` output helper**

Formats the result for stdout. Handles both JSON objects and plain text:

```javascript
function formatResult(result) {
    if (typeof result === 'string') {
        console.log(result);
        return;
    }
    // JSON result object
    if (result.result !== null && result.result !== undefined) {
        if (Array.isArray(result.result)) {
            result.result.forEach(p => console.log(p));
        } else {
            console.log(result.result);
        }
    }
    if (result.capture_id) {
        console.log(`capture_id:${result.capture_id}`);
    }
    if (result.status === 'pending') {
        console.log(`status:pending progress:${result.progress || 'unknown'}`);
    }
    if (result.status === 'error' && result.message) {
        console.error(`Error: ${result.message}`);
    }
}
```

- [ ] **Step 6: Rewrite the `main()` command dispatch**

Replace the entire switch block in `main()` with the new JSON-aware dispatch:

```javascript
async function main() {
    const rawArgs = process.argv.slice(2);

    if (rawArgs.length === 0 || rawArgs[0] === '--help' || rawArgs[0] === '-h') {
        console.log(`
ai-debug - AI Debug Bridge for God of Lego

Usage:
  node ai-debug.mjs <command> [args...] [--screenshot [-d N] [-c N] [-i N]]

Commands:
  console <cmd> [args...]  Execute console command
  screenshot [-d N] [-c N] [-i N]  Capture screenshot(s)
  eval <expression>        Evaluate GDScript expression
  script <file.gd>         Execute GDScript file
  get <property>           Get game state
  set <property> <value>   Set game state
  refresh [what]           Reload recipes/config/ui (what: recipes, config, ui, all)
  reimport                 Stop game, clear import cache, restart
  fetch <capture_id>       Retrieve async screenshot result

Screenshot flags (usable with --screenshot on any command, or with screenshot command):
  -d, --delay <seconds>    Wait before first capture (default: 0)
  -c, --count <N>          Number of screenshots (default: 1)
  -i, --interval <seconds> Time between captures (default: 1)
  -s, --screenshot         Attach piggyback screenshot to command

Examples:
  node ai-debug.mjs screenshot
  node ai-debug.mjs screenshot --delay 3
  node ai-debug.mjs screenshot --count 5 --interval 1
  node ai-debug.mjs console heal full --screenshot --delay 2
  node ai-debug.mjs fetch cap_1711012345678
`);
        process.exit(0);
    }

    const cmd = rawArgs[0];
    const { flags, positional } = parseFlags(rawArgs.slice(1));

    try {
        let result;

        switch (cmd) {
            case 'screenshot': {
                const screenshotArgs = buildScreenshotOpts(flags);
                const timeout = calculateTimeout(flags);
                result = await sendCommand({ cmd: 'screenshot', args: screenshotArgs }, timeout);
                break;
            }

            case 'fetch': {
                if (positional.length === 0) {
                    console.error('Error: capture_id required');
                    process.exit(1);
                }
                result = await sendCommand({ cmd: 'fetch', args: { capture_id: positional[0] } });
                break;
            }

            case 'console': {
                if (positional.length === 0) {
                    console.error('Error: console command required');
                    process.exit(1);
                }
                const payload = { cmd: 'console', args: positional };
                if (flags.screenshot) {
                    payload.screenshot = buildScreenshotOpts(flags);
                }
                result = await sendCommand(payload);
                break;
            }

            case 'eval': {
                if (positional.length === 0) {
                    console.error('Error: expression required');
                    process.exit(1);
                }
                const payload = { cmd: 'eval', args: positional };
                if (flags.screenshot) {
                    payload.screenshot = buildScreenshotOpts(flags);
                }
                result = await sendCommand(payload);
                break;
            }

            case 'script': {
                if (positional.length === 0) {
                    console.error('Error: script file required');
                    process.exit(1);
                }
                // Script still uses the special file-copy flow
                result = await executeScript(positional[0]);
                break;
            }

            case 'get': {
                if (positional.length === 0) {
                    console.error('Error: property required');
                    process.exit(1);
                }
                const payload = { cmd: 'get', args: [positional[0]] };
                if (flags.screenshot) {
                    payload.screenshot = buildScreenshotOpts(flags);
                }
                result = await sendCommand(payload);
                break;
            }

            case 'set': {
                if (positional.length < 2) {
                    console.error('Error: property and value required');
                    process.exit(1);
                }
                const payload = { cmd: 'set', args: [positional[0], positional[1]] };
                if (flags.screenshot) {
                    payload.screenshot = buildScreenshotOpts(flags);
                }
                result = await sendCommand(payload);
                break;
            }

            case 'refresh': {
                const payload = { cmd: 'refresh', args: positional };
                if (flags.screenshot) {
                    payload.screenshot = buildScreenshotOpts(flags);
                }
                result = await sendCommand(payload);
                break;
            }

            case 'reimport':
                result = await reimportAssets();
                break;

            default:
                console.error(`Unknown command: ${cmd}`);
                process.exit(1);
        }

        formatResult(result);
        process.exit(0);
    } catch (err) {
        console.error('Error:', err.message);
        process.exit(1);
    }
}
```

- [ ] **Step 7: Update `executeScript()` for JSON protocol**

The script command needs the special file-copy flow but should still send JSON:

```javascript
async function executeScript(scriptPath) {
    if (!fs.existsSync(scriptPath)) {
        throw new Error(`Script not found: ${scriptPath}`);
    }

    await ensureSignalDir();

    const scriptContent = fs.readFileSync(scriptPath, 'utf8');
    fs.writeFileSync(SCRIPT_FILE, scriptContent);

    return await sendCommand({ cmd: 'script' }, SCRIPT_TIMEOUT);
}
```

- [ ] **Step 8: Update file header comment**

Replace the top comment block to document the new commands and flags.

- [ ] **Step 9: Commit**

```bash
cd gol-tools/ai-debug && git add ai-debug.mjs && git commit -m "feat: JSON protocol with screenshot flags and fetch command

All commands now sent as JSON. --screenshot flag enables piggyback
capture on any command. New fetch command retrieves async results.
Dynamic timeout calculation for delayed/multi-frame captures."
```

---

### Task 6: E2E Test Script

**Files:**
- Create: `gol-tools/ai-debug/e2e_test_screenshot_upgrade.sh`

**Prerequisites:** Game must be running with a generated map.

- [ ] **Step 1: Write the test script**

```bash
#!/bin/bash
# e2e_test_screenshot_upgrade.sh
# End-to-end test for AI Debug screenshot upgrade
#
# Prerequisites:
#   - Game must be running with a generated map
#   - node and gol-tools/ai-debug/ai-debug.mjs must be accessible
#
# Usage: bash e2e_test_screenshot_upgrade.sh

set -euo pipefail

GOL_DIR="/Users/dluckdu/Documents/Github/gol"
AI_DEBUG="node ${GOL_DIR}/gol-tools/ai-debug/ai-debug.mjs"
PASS=0
FAIL=0

log_pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
log_fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "=== E2E Test: Screenshot Upgrade ==="
echo ""

# --- Test 1: Basic screenshot (JSON protocol) ---
echo "[Test 1] Basic screenshot via JSON protocol"
OUTPUT=$(cd "${GOL_DIR}" && ${AI_DEBUG} screenshot 2>/dev/null) || true
if echo "$OUTPUT" | grep -q "ai_screenshot_.*\.png"; then
    log_pass "Screenshot returned PNG path"
else
    log_fail "No PNG path in output: $OUTPUT"
fi

# --- Test 2: Screenshot with delay ---
echo ""
echo "[Test 2] Screenshot with 1s delay"
START=$(date +%s)
OUTPUT=$(cd "${GOL_DIR}" && ${AI_DEBUG} screenshot --delay 1 2>/dev/null) || true
END=$(date +%s)
ELAPSED=$((END - START))
if [ "$ELAPSED" -ge 1 ]; then
    log_pass "Delay respected (${ELAPSED}s elapsed)"
else
    log_fail "Delay not respected (${ELAPSED}s elapsed, expected >=1)"
fi
if echo "$OUTPUT" | grep -q "ai_screenshot_.*\.png"; then
    log_pass "Screenshot returned PNG path after delay"
else
    log_fail "No PNG path in output: $OUTPUT"
fi

# --- Test 3: Multi-frame capture ---
echo ""
echo "[Test 3] Multi-frame capture (3 shots, 0.5s interval)"
OUTPUT=$(cd "${GOL_DIR}" && ${AI_DEBUG} screenshot --count 3 --interval 0.5 2>/dev/null) || true
COUNT=$(echo "$OUTPUT" | grep -c "ai_screenshot_.*\.png" || true)
if [ "$COUNT" -eq 3 ]; then
    log_pass "Got 3 screenshot paths"
else
    log_fail "Expected 3 paths, got ${COUNT}: $OUTPUT"
fi

# --- Test 4: Piggyback screenshot (non-blocking) ---
echo ""
echo "[Test 4] Piggyback screenshot on console command"
OUTPUT=$(cd "${GOL_DIR}" && ${AI_DEBUG} get time --screenshot 2>/dev/null) || true
if echo "$OUTPUT" | grep -q "Time:"; then
    log_pass "Command result returned"
else
    log_fail "No command result: $OUTPUT"
fi
if echo "$OUTPUT" | grep -q "capture_id:cap_"; then
    log_pass "capture_id returned"
    CAPTURE_ID=$(echo "$OUTPUT" | grep "capture_id:" | sed 's/capture_id://')
else
    log_fail "No capture_id: $OUTPUT"
    CAPTURE_ID=""
fi

# --- Test 5: Fetch async screenshot ---
echo ""
echo "[Test 5] Fetch piggyback screenshot result"
if [ -n "$CAPTURE_ID" ]; then
    # Wait a moment for capture to complete
    sleep 1
    OUTPUT=$(cd "${GOL_DIR}" && ${AI_DEBUG} fetch "$CAPTURE_ID" 2>/dev/null) || true
    if echo "$OUTPUT" | grep -q "ai_screenshot_.*\.png"; then
        log_pass "Fetched screenshot path"
    else
        log_fail "No screenshot in fetch result: $OUTPUT"
    fi
else
    log_fail "Skipped (no capture_id from Test 4)"
fi

# --- Test 6: Fetch non-existent capture ---
echo ""
echo "[Test 6] Fetch invalid capture_id"
OUTPUT=$(cd "${GOL_DIR}" && ${AI_DEBUG} fetch cap_nonexistent 2>/dev/null) || true
if echo "$OUTPUT" | grep -qi "not found\|error"; then
    log_pass "Error returned for invalid capture_id"
else
    log_fail "No error for invalid capture_id: $OUTPUT"
fi

# --- Test 7: Legacy command still works ---
echo ""
echo "[Test 7] Legacy backward compatibility"
OUTPUT=$(cd "${GOL_DIR}" && ${AI_DEBUG} get time 2>/dev/null) || true
if echo "$OUTPUT" | grep -q "Time:"; then
    log_pass "Basic command still works"
else
    log_fail "Legacy command failed: $OUTPUT"
fi

# --- Test 8: Piggyback with delay ---
echo ""
echo "[Test 8] Piggyback with delay"
OUTPUT=$(cd "${GOL_DIR}" && ${AI_DEBUG} get time --screenshot --delay 1 2>/dev/null) || true
if echo "$OUTPUT" | grep -q "capture_id:cap_"; then
    log_pass "Piggyback with delay returned capture_id"
    CAPTURE_ID2=$(echo "$OUTPUT" | grep "capture_id:" | sed 's/capture_id://')
    sleep 2
    FETCH_OUTPUT=$(cd "${GOL_DIR}" && ${AI_DEBUG} fetch "$CAPTURE_ID2" 2>/dev/null) || true
    if echo "$FETCH_OUTPUT" | grep -q "ai_screenshot_.*\.png"; then
        log_pass "Delayed piggyback screenshot fetched"
    else
        log_fail "Delayed piggyback fetch failed: $FETCH_OUTPUT"
    fi
else
    log_fail "No capture_id with delay: $OUTPUT"
fi

# --- Summary ---
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
exit ${FAIL}
```

- [ ] **Step 2: Make executable and commit**

```bash
cd gol-tools/ai-debug && chmod +x e2e_test_screenshot_upgrade.sh && git add e2e_test_screenshot_upgrade.sh && git commit -m "test: add E2E test for screenshot upgrade

Covers: basic screenshot, delay, multi-frame, piggyback,
fetch, invalid capture_id, legacy compatibility."
```

---

## Execution Order

Tasks 1-4 are sequential (each builds on the previous). Task 5 (CLI) depends on Tasks 2-4 being complete. Task 6 (E2E test) depends on all prior tasks.

```
Task 1 (ScreenshotManager cleanup)
  → Task 2 (JSON parsing layer)
    → Task 3 (sync screenshot w/ delay)
      → Task 4 (piggyback + fetch)
        → Task 5 (CLI upgrade)
          → Task 6 (E2E test)
```
