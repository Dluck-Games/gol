# AI Debug Screenshot Upgrade — Design Spec

## Problem

The current ai-debug screenshot tool has two usability issues:

1. **No delay support** — screenshots capture the instant the command is received, making it impossible to observe game state after an action takes effect.
2. **Extra round-trip overhead** — AI must issue a separate `screenshot` command after every debug command, adding ~200ms+ per call. When verifying multiple actions, this compounds.

## Solution

Upgrade the screenshot system with two complementary features and a JSON protocol:

1. **Delay parameter** — standalone `screenshot` supports waiting N seconds before capture.
2. **Piggyback screenshot** — any command can request a non-blocking screenshot attachment via a `screenshot` field. The command result returns immediately with a `capture_id`; the screenshot is taken asynchronously and retrieved later via `fetch`.
3. **Multi-frame capture** — both modes support taking multiple screenshots at fixed intervals.
4. **Legacy cleanup** — remove the unused request/ready file IPC mechanism from ScreenshotManager.

## Protocol

### Command File Format

JSON object. Backward compatible: if the first character is not `{`, the game falls back to legacy space-delimited parsing.

```jsonc
// Basic command
{"cmd": "console", "args": ["heal", "full"]}

// Command with piggyback screenshot
{"cmd": "console", "args": ["heal", "full"], "screenshot": {"delay": 2}}

// Command with multi-frame piggyback
{"cmd": "console", "args": ["heal", "full"], "screenshot": {"delay": 1, "count": 3, "interval": 0.5}}

// Standalone screenshot (synchronous)
{"cmd": "screenshot"}
{"cmd": "screenshot", "args": {"delay": 3}}
{"cmd": "screenshot", "args": {"delay": 0, "count": 5, "interval": 1}}

// Fetch async screenshot result
{"cmd": "fetch", "args": {"capture_id": "cap_1711012345678"}}
```

#### Screenshot Parameters

| Field      | Type  | Default | Max | Description                         |
|------------|-------|---------|-----|-------------------------------------|
| `delay`    | float | 0       | 30  | Seconds to wait before first capture |
| `count`    | int   | 1       | 20  | Number of screenshots to take        |
| `interval` | float | 1.0     | 10  | Seconds between captures (when count > 1) |

Values exceeding max are clamped. Max `count` of 20 prevents a single command from consuming too much disk (MAX_HISTORY is 100).

### Result File Format

JSON object. Backward compatible: if the first character is not `{`, CLI treats it as plain text.

```jsonc
// Basic command result
{"result": "Healed to full"}

// Piggyback — command result + pending capture
{"result": "Healed to full", "capture_id": "cap_1711012345678"}

// Standalone screenshot — single
{"result": "/absolute/path/to/screenshot.png"}

// Standalone screenshot — multi-frame
{"result": ["/path/1.png", "/path/2.png", "/path/3.png"]}

// Fetch — ready
{"result": ["/path/1.png", "/path/2.png"], "status": "ready"}

// Fetch — pending
{"result": null, "status": "pending", "progress": "2/5"}

// Fetch — not found (expired or invalid)
{"result": null, "status": "error", "message": "Capture not found: cap_xxx"}
```

## Flow: Synchronous Screenshot

```
CLI                                Game
 │  {"cmd":"screenshot",            │
 │   "args":{"delay":3,             │
 │           "count":2,             │
 │           "interval":1}}         │
 │ ──── command file ─────────────> │
 │                                  │  await 3s delay
 │                                  │  capture #1
 │                                  │  await 1s interval
 │                                  │  capture #2
 │ <──── result file ────────────── │
 │  {"result":["/p/1.png",         │
 │             "/p/2.png"]}         │
 ▼ prints paths, exits              │
```

CLI blocks. Timeout = `delay + max(0, count - 1) * interval + 10s` base. The interval is between captures, not after the last one.

## Flow: Piggyback Screenshot (Non-Blocking)

```
CLI                                Game
 │  {"cmd":"console",               │
 │   "args":["heal","full"],        │
 │   "screenshot":{"delay":2}}     │
 │ ──── command file ─────────────> │
 │                                  │  execute heal immediately
 │                                  │  generate capture_id
 │                                  │  start background timer
 │ <──── result file ────────────── │
 │  {"result":"Healed to full",    │
 │   "capture_id":"cap_xxx"}       │
 ▼ prints result + capture_id       │
                                    │  ... 2s later, capture screenshot
--- later ---                       │
 │  {"cmd":"fetch",                 │
 │   "args":{"capture_id":          │
 │           "cap_xxx"}}            │
 │ ──── command file ─────────────> │
 │                                  │  look up capture_id
 │ <──── result file ────────────── │
 │  {"result":["/p/1.png"],        │
 │   "status":"ready"}              │
 ▼ prints paths                     │
```

## Capture Lifecycle

- **ID format**: `cap_` + unix timestamp in milliseconds (e.g., `cap_1711012345678`)
- **Storage**: In-memory `Dictionary` on game side: `{capture_id: {paths: Array, status: String, total: int, completed_at: int}}`
- **Expiry**: Captures are auto-cleaned 60 seconds after **completion** (not creation). This prevents long multi-frame captures from expiring mid-capture. Cleanup runs in `_process()` every 5 seconds.
- **After fetch**: Capture remains until expiry (allows re-fetch if needed)

## Changes

### `ai_debug_bridge.gd`

- `_execute_command_file()`: detect JSON vs plain text (first char `{`), route accordingly
- New `_command_in_progress: bool` guard flag — prevents re-entrancy when `_process()` fires during an `await`. While a synchronous screenshot is awaiting delay/interval timers, subsequent `_process()` polls are skipped.
- JSON path: parse command dict, dispatch to handler via new `_execute_command_json(cmd_dict: Dictionary)`, check for `screenshot` field
- Legacy path: existing `_execute_command()` renamed to `_execute_command_legacy()`, output remains **plain text** (not wrapped in JSON) to preserve backward compatibility with older CLI versions
- JSON path result writing: JSON-serialize via `JSON.stringify()`
- Handler dispatch: JSON commands call handlers with `Dictionary` args (e.g., `_handle_screenshot_json(args: Dictionary)`). Legacy commands continue calling handlers with `Array` args. Shared logic extracted where practical.
- `_handle_screenshot_json(args)`: support `delay`/`count`/`interval` via `await` (synchronous, blocks result file until all captures complete). Uses `await RenderingServer.frame_post_draw` before each `capture_now()` to ensure the captured frame is fully rendered.
- New `_schedule_piggyback_screenshot(opts: Dictionary) -> String`: create capture_id, kick off a coroutine (async function) that chains `await create_timer().timeout` + `await RenderingServer.frame_post_draw` + `capture_now()` for each frame. Returns capture_id immediately.
- New `_handle_fetch(args)`: look up capture_id in `_pending_captures`, return status/paths. Registered in `_handlers` alongside other commands.
- New `_pending_captures: Dictionary` for async capture tracking
- New `_cleanup_expired_captures()`: called periodically from `_process()` (every 5s)

### `screenshot_manager.gd`

- **Remove**: `_process()`, `_poll_timer`, `_check_request_signal()`, `REQUEST_FILE`, `READY_FILE`, `POLL_INTERVAL`, `SIGNAL_DIR` constants
- ScreenshotManager becomes a pure utility (no per-frame processing)
- `capture_now()` and other public methods unchanged

### `ai-debug.mjs`

- `sendCommand()`: serialize command as JSON, parse result as JSON (with plain-text fallback)
- `screenshot` subcommand: parse `--delay`, `--count`, `--interval` flags
- All commands: parse `--screenshot` flag (+ `--delay`, `--count`, `--interval`) for piggyback
- New `fetch` subcommand: `fetch <capture_id>`
- Dynamic timeout: `delay + max(0, count - 1) * interval + 10` seconds
- Output formatting: print `result`, and if `capture_id` present, print it on a separate line prefixed with `capture_id:`

### CLI Usage

```bash
# Standalone screenshot
node ai-debug.mjs screenshot
node ai-debug.mjs screenshot --delay 3
node ai-debug.mjs screenshot --count 5 --interval 1
node ai-debug.mjs screenshot --delay 2 --count 3 --interval 0.5

# Any command + piggyback screenshot
node ai-debug.mjs console heal full --screenshot
node ai-debug.mjs console heal full --screenshot --delay 2
node ai-debug.mjs eval ECS.world.entities.size() --screenshot --delay 1 --count 3 --interval 0.5

# Fetch async screenshot
node ai-debug.mjs fetch cap_1711012345678
```

## What Does NOT Change

- File signal mechanism (command/result files, polling)
- Other command handlers (console/eval/script/get/set/refresh/reimport) internal logic
- Screenshot storage paths, naming convention, history management, max 100 file limit
- POLL_INTERVAL on bridge side (100ms)
