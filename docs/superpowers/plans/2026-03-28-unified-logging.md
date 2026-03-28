# Unified Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate Foreman daemon logs, per-issue worker logs, progress files, and game launch output under the management repo `logs/` directory without changing log formats or introducing a new game logging framework.

**Architecture:** Keep `.foreman/` as Foreman's state directory, but move all human-facing runtime logs to `logs/foreman/` and `logs/game/` under the management repo root. In `gol-tools`, make nested log paths first-class so issue-specific files live in `logs/foreman/issues/issue-{N}/`; in `gol-project`, remove the single-use `PCGLogger` wrapper and rely on direct `print()` output captured by the launch script.

**Tech Stack:** Node.js test runner (`node --test`), Foreman daemon (`gol-tools/foreman`), GDScript + gdUnit4 + SceneConfig (`gol-project`), bash launch scripts, macOS `launchd`

---

## File Map

- Modify: `.gitignore`
- Modify: `shortcuts/run-game.command`
- Modify: `gol-tools/foreman/lib/logger.mjs`
- Modify: `gol-tools/foreman/lib/progress-writer.mjs`
- Modify: `gol-tools/foreman/foreman-daemon.mjs`
- Modify: `gol-tools/foreman/lib/tl-dispatcher.mjs`
- Modify: `gol-tools/foreman/com.dluckdu.foreman-daemon.plist`
- Modify: `gol-tools/.gitignore`
- Modify: `gol-tools/foreman/tests/process-manager.test.mjs`
- Create: `gol-tools/foreman/tests/progress-writer.test.mjs`
- Modify: `gol-project/scripts/pcg/wfc/wfc_solver.gd`
- Delete: `gol-project/scripts/debug/pcg_logger.gd`
- Create: `gol-project/tests/unit/pcg/test_wfc_solver.gd`

## Out of Scope Guardrails

- Do not change `docs/foreman/**` document paths.
- Do not change `.foreman/state.json` or `.foreman/cancel/` semantics.
- Do not add a new Godot singleton or service for logging.
- Do not normalize every existing `print()` call in the game; only remove the single-use `PCGLogger` path used by `WFCSolver`.

---

### Task 1: Management Repo Ignore Rule

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Confirm the current root ignore block**

Run:

```bash
grep -n "firebase-debug.log\|logs/" .gitignore
```

Expected: one `firebase-debug.log` match and no `logs/` match.

- [ ] **Step 2: Update the ignore rule**

Replace the current log block in `.gitignore`:

```gitignore
# Logs
firebase-debug.log
```

With:

```gitignore
# Logs
logs/
```

- [ ] **Step 3: Verify the new ignore rule**

Run:

```bash
grep -n "# Logs\|logs/" .gitignore
```

Expected: the `# Logs` header followed by `logs/`.

- [ ] **Step 4: Commit the management-repo change**

```bash
git add .gitignore
git commit -m "chore: ignore unified logs directory"
```

---

### Task 2: Foreman Nested Process Logs

**Files:**
- Modify: `gol-tools/foreman/lib/logger.mjs`
- Modify: `gol-tools/foreman/tests/process-manager.test.mjs`
- Test: `gol-tools/foreman/tests/process-manager.test.mjs`

- [ ] **Step 1: Write the failing test for nested process log paths**

Add `existsSync` and `join` to the imports, then add this test near the other `spawn` tests in `gol-tools/foreman/tests/process-manager.test.mjs`:

```js
import { existsSync } from 'node:fs';
import { join } from 'node:path';

        it('creates parent directories for nested log prefixes', () => {
            processManager.spawn(1201, '/tmp/work', 'test', 'issues/issue-1201/coder', coderRole(config));

            assert.ok(existsSync(join(logDir, 'issues', 'issue-1201')));
        });
```

- [ ] **Step 2: Run the focused Node test to watch it fail**

Run:

```bash
cd gol-tools/foreman && node --test tests/process-manager.test.mjs
```

Expected: FAIL because `createProcessLog()` only creates `logDir`, not the nested parent directory for `issues/issue-1201/`.

- [ ] **Step 3: Implement nested directory creation in `logger.mjs`**

Update the imports and `createProcessLog()` in `gol-tools/foreman/lib/logger.mjs`:

```js
import { createWriteStream, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';

export function createProcessLog(filename) {
    const path = join(logDir, filename);
    mkdirSync(dirname(path), { recursive: true });
    return createWriteStream(path, { flags: 'a' });
}
```

- [ ] **Step 4: Re-run the focused Node test**

Run:

```bash
cd gol-tools/foreman && node --test tests/process-manager.test.mjs
```

Expected: PASS for the new nested-path test and the pre-existing `ProcessManager` suite.

- [ ] **Step 5: Commit the Foreman logging helper change**

```bash
cd gol-tools
git add foreman/lib/logger.mjs foreman/tests/process-manager.test.mjs
git commit -m "feat(foreman): support nested process log paths"
```

---

### Task 3: Foreman Progress Files Under `logs/foreman/issues/`

**Files:**
- Create: `gol-tools/foreman/tests/progress-writer.test.mjs`
- Modify: `gol-tools/foreman/lib/progress-writer.mjs`
- Test: `gol-tools/foreman/tests/progress-writer.test.mjs`

- [ ] **Step 1: Write the failing progress-writer tests**

Create `gol-tools/foreman/tests/progress-writer.test.mjs` with this content:

```js
import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ProgressWriter } from '../lib/progress-writer.mjs';
import { cleanupTempDir, createTempDir } from './helpers.mjs';

const tempDirs = [];

afterEach(() => {
    while (tempDirs.length > 0) cleanupTempDir(tempDirs.pop());
});

describe('ProgressWriter', () => {
    it('writes issue progress into issues/issue-N/progress.md', () => {
        const dir = createTempDir();
        tempDirs.push(dir);
        const writer = new ProgressWriter(dir);

        writer.create(188, 'Example title');

        const path = join(dir, 'issues', 'issue-188', 'progress.md');
        assert.ok(existsSync(path));
        assert.match(readFileSync(path, 'utf-8'), /# Issue #188: Example title/);
    });
});
```

- [ ] **Step 2: Run the focused Node test to verify it fails**

Run:

```bash
cd gol-tools/foreman && node --test tests/progress-writer.test.mjs
```

Expected: FAIL because the current writer still uses the flat `issue-{N}.md` path.

- [ ] **Step 3: Implement the nested progress path and directory creation**

Update `gol-tools/foreman/lib/progress-writer.mjs` to this shape:

```js
import { mkdirSync, appendFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

export class ProgressWriter {
    #dir;

    constructor(dir) {
        this.#dir = dir;
    }

    create(issueNumber, issueTitle) {
        const path = this.#path(issueNumber);
        mkdirSync(dirname(path), { recursive: true });
        const header = `# Issue #${issueNumber}: ${issueTitle}\n\n## Timeline\n\n`;
        writeFileSync(path, header, 'utf-8');
        this.append(issueNumber, 'Task discovered and queued');
    }

    append(issueNumber, message) {
        const path = this.#path(issueNumber);
        mkdirSync(dirname(path), { recursive: true });
        if (!existsSync(path)) {
            writeFileSync(path, `# Issue #${issueNumber}\n\n## Timeline\n\n`, 'utf-8');
        }
        const ts = new Date().toISOString().replace('T', ' ').slice(0, 19);
        appendFileSync(path, `- **${ts}** — ${message}\n`, 'utf-8');
    }

    #path(issueNumber) {
        return join(this.#dir, 'issues', `issue-${issueNumber}`, 'progress.md');
    }
}
```

- [ ] **Step 4: Run the focused test again**

Run:

```bash
cd gol-tools/foreman && node --test tests/progress-writer.test.mjs
```

Expected: PASS.

- [ ] **Step 5: Commit the progress-writer task**

```bash
cd gol-tools
git add foreman/lib/progress-writer.mjs foreman/tests/progress-writer.test.mjs
git commit -m "feat(foreman): move progress files into issue log directories"
```

---

### Task 4: Rewire Foreman to `logs/foreman/`

**Files:**
- Modify: `gol-tools/foreman/foreman-daemon.mjs`
- Modify: `gol-tools/foreman/lib/tl-dispatcher.mjs`
- Test: `gol-tools/foreman/tests/process-manager.test.mjs`
- Test: `gol-tools/foreman/tests/progress-writer.test.mjs`

- [ ] **Step 1: Capture the current old path usage**

Run:

```bash
grep -n "planner-issue-\|coder-issue-\|reviewer-issue-\|tester-issue-\|tl-issue-\|join(dataDir, 'logs')\|join(dataDir, 'progress')" gol-tools/foreman/foreman-daemon.mjs gol-tools/foreman/lib/tl-dispatcher.mjs
```

Expected: matches for the flat log prefixes and `.foreman`-derived paths.

- [ ] **Step 2: Update the daemon log root and progress root**

In `gol-tools/foreman/foreman-daemon.mjs`, change the constructor setup to:

```js
        const dataDir = config.dataDir;
        const logDir = join(config.workDir, 'logs', 'foreman');
        initLogger(logDir);

        this.#state = new StateManager(dataDir);
        this.#workspaces = new WorkspaceManager(config);
        this.#prompts = new PromptBuilder(config.promptsDir);
        this.#notifier = new Notifier(config.notifyTarget);
        this.#progress = new ProgressWriter(logDir);
```

- [ ] **Step 3: Replace the worker log prefixes with per-issue paths**

In `gol-tools/foreman/foreman-daemon.mjs`, update each `this.#processes.spawn()` call to use these prefixes:

```js
`issues/issue-${issue_number}/planner`
`issues/issue-${issue_number}/coder`
`issues/issue-${issue_number}/reviewer-pr-${prNumber}`
`issues/issue-${issue_number}/tester`
```

In `gol-tools/foreman/lib/tl-dispatcher.mjs`, update the TL prefix to:

```js
`issues/issue-${issueNumber}/tl`
```

- [ ] **Step 4: Update the stale/rate-limit log path helper**

Replace `#coderLogPath()` in `gol-tools/foreman/foreman-daemon.mjs` with:

```js
    #coderLogPath(task) {
        const logDir = join(this.#config.workDir, 'logs', 'foreman');
        const issueDir = join(logDir, 'issues', `issue-${task.issue_number}`);

        if (task.state === 'planning') return join(issueDir, 'planner.log');
        if (task.state === 'building') return join(issueDir, 'coder.log');
        if (task.state === 'reviewing' && task.pr_number) {
            return join(issueDir, `reviewer-pr-${task.pr_number}.log`);
        }
        if (task.state === 'testing') return join(issueDir, 'tester.log');
        return null;
    }
```

- [ ] **Step 5: Re-run the old-path grep to make sure only intended references remain**

Run:

```bash
grep -n "planner-issue-\|coder-issue-\|reviewer-issue-\|tester-issue-\|tl-issue-\|join(dataDir, 'logs')\|join(dataDir, 'progress')" gol-tools/foreman/foreman-daemon.mjs gol-tools/foreman/lib/tl-dispatcher.mjs
```

Expected: no matches.

- [ ] **Step 6: Run the focused Node tests that cover the new path behavior**

Run:

```bash
cd gol-tools/foreman && node --test tests/process-manager.test.mjs tests/progress-writer.test.mjs
```

Expected: PASS.

- [ ] **Step 7: Run the full Foreman Node suite**

Run:

```bash
cd gol-tools/foreman && npm test
```

Expected: PASS for the committed Node test suite.

- [ ] **Step 8: Commit the daemon rewiring task**

```bash
cd gol-tools
git add foreman/foreman-daemon.mjs foreman/lib/tl-dispatcher.mjs
git commit -m "feat(foreman): move daemon and worker logs under logs/foreman"
```

---

### Task 5: Update launchd Paths and Remove Legacy Source-Tree Logs

**Files:**
- Modify: `gol-tools/foreman/com.dluckdu.foreman-daemon.plist`
- Modify: `gol-tools/.gitignore`
- Delete: `gol-tools/foreman/logs/daemon.log`
- Delete: `gol-tools/foreman/logs/launchd-daemon.log`
- Delete: `gol-tools/foreman/logs/launchd-daemon-error.log`

- [ ] **Step 1: Verify the legacy tracked log files exist**

Run:

```bash
cd gol-tools && git ls-files foreman/logs
```

Expected: the three tracked stub log files under `foreman/logs/`.

- [ ] **Step 2: Update the launchd plist to the new absolute paths**

Replace the log path block in `gol-tools/foreman/com.dluckdu.foreman-daemon.plist` with:

```xml
    <key>StandardOutPath</key>
    <string>/Users/dluckdu/Documents/Github/gol/logs/foreman/launchd-daemon.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/dluckdu/Documents/Github/gol/logs/foreman/launchd-daemon-error.log</string>
```

- [ ] **Step 3: Remove only the obsolete `foreman/logs/` ignore rule**

In `gol-tools/.gitignore`, delete this line only:

```gitignore
foreman/logs/
```

Keep the rest of the file unchanged, including:

```gitignore
logs
.DS_Store
*.backup.*
*.v1
firebase-debug.log
.codebuddy/
node_modules/
foreman/external/
```

- [ ] **Step 4: Delete the tracked legacy log files**

Run:

```bash
cd gol-tools && git rm foreman/logs/daemon.log foreman/logs/launchd-daemon.log foreman/logs/launchd-daemon-error.log
```

Expected: the three files are staged for deletion.

- [ ] **Step 5: Commit the launchd and cleanup task**

```bash
cd gol-tools
git add .gitignore foreman/com.dluckdu.foreman-daemon.plist
git commit -m "chore(foreman): remove legacy log files and update launchd paths"
```

---

### Task 6: Remove `PCGLogger` from `WFCSolver`

**Files:**
- Create: `gol-project/tests/unit/pcg/test_wfc_solver.gd`
- Modify: `gol-project/scripts/pcg/wfc/wfc_solver.gd`
- Delete: `gol-project/scripts/debug/pcg_logger.gd`
- Test: `gol-project/tests/unit/pcg/test_wfc_solver.gd`

- [ ] **Step 1: Write the failing gdUnit test for the public API change**

Create `gol-project/tests/unit/pcg/test_wfc_solver.gd`:

```gdscript
extends GdUnitTestSuite


func test_solver_no_longer_exposes_set_logger() -> void:
	var solver: WFCSolver = auto_free(WFCSolver.new()) as WFCSolver
	assert_bool(solver.has_method("set_logger")).is_false()


func test_set_precondition_without_initialized_cell_still_returns_cleanly() -> void:
	var solver: WFCSolver = auto_free(WFCSolver.new()) as WFCSolver
	solver.log_level = 2
	solver.set_precondition(Vector2i.ZERO, "missing_tile")
	assert_int(solver.get_state()).is_equal(WFCSolver.State.READY)
```

- [ ] **Step 2: Run the focused gdUnit test and confirm it fails**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/pcg/test_wfc_solver.gd --ignoreHeadlessMode --verbose
```

Expected: FAIL because `WFCSolver` still exposes `set_logger()`.

- [ ] **Step 3: Replace `PCGLogger` usage with a local print helper**

In `gol-project/scripts/pcg/wfc/wfc_solver.gd`:

1. Remove the preload, the `logger` field, and the `set_logger()` method.
2. Add this helper near the other private helpers:

```gdscript
func _log_event(required_level: int, event: String, data: Dictionary = {}) -> void:
	if log_level < required_level:
		return
	print("[WFC] %s %s" % [event, JSON.stringify(data)])
```

3. Replace each old logger block with direct helper calls, for example:

```gdscript
	_log_event(2, "precondition_skipped", {
		"pos": pos,
		"tile_id": tile_id,
		"reason": "position_not_initialized",
	})
```

```gdscript
	_log_event(1, "solve_started", {
		"cell_count": _domains.size(),
		"backtracking_enabled": backtracking_enabled,
	})
```

```gdscript
	_log_event(1, "solve_completed", {
		"final_state": _get_state_name(_state),
		"iterations": iteration,
	})
```

- [ ] **Step 4: Delete the obsolete logger class**

Run:

```bash
cd gol-project && git rm scripts/debug/pcg_logger.gd
```

- [ ] **Step 5: Re-run the focused gdUnit test**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/pcg/test_wfc_solver.gd --ignoreHeadlessMode --verbose
```

Expected: PASS.

- [ ] **Step 6: Run the existing PCG integration test that exercises map generation**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path gol-project res://scenes/tests/test_main.tscn -- --config=res://tests/integration/pcg/test_pcg_map.gd
```

Expected: exit code `0`.

- [ ] **Step 7: Commit the game-side logger removal**

```bash
cd gol-project
git add scripts/pcg/wfc/wfc_solver.gd tests/unit/pcg/test_wfc_solver.gd
git commit -m "refactor(pcg): remove standalone WFC logger"
```

---

### Task 7: Capture Game Launch Output Under `logs/game/`

**Files:**
- Modify: `shortcuts/run-game.command`

- [ ] **Step 1: Replace the launch script with log capture**

Replace `shortcuts/run-game.command` with:

```bash
#!/bin/bash

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs/game"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/game-$TIMESTAMP.log"

cd "$REPO_ROOT/gol-project" || exit 1
/Applications/Godot.app/Contents/MacOS/Godot --path . 2>&1 | tee "$LOG_FILE"
```

- [ ] **Step 2: Restore executable permissions explicitly**

Run:

```bash
chmod +x shortcuts/run-game.command
```

Expected: command succeeds with no output.

- [ ] **Step 3: Preserve Godot's exit status in the script**

Add this line immediately after the shebang in `shortcuts/run-game.command`:

```bash
set -o pipefail
```

The final script should start like this:

```bash
#!/bin/bash
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
```

- [ ] **Step 4: Run the launch script once and verify a log file is created**

Run:

```bash
bash shortcuts/run-game.command
```

Expected: Godot opens normally and writes a new `logs/game/game-YYYYMMDD-HHMMSS.log` file before exit.

- [ ] **Step 5: Confirm the log file exists**

Run:

```bash
ls logs/game
```

Expected: at least one `game-*.log` file.

- [ ] **Step 6: Commit the launch-script update**

```bash
git add shortcuts/run-game.command
git commit -m "feat: capture game output in logs/game"
```

---

### Task 8: Final Runtime Cleanup and Verification

**Files:**
- Modify: none (verification + local runtime cleanup)

- [ ] **Step 1: Remove obsolete local Foreman runtime directories**

Run:

```bash
rm -rf .foreman/logs .foreman/progress .foreman/plans .foreman/reviews .foreman/tests
```

Expected: command succeeds silently.

- [ ] **Step 2: Create the target log directories before reloading launchd**

Run:

```bash
mkdir -p logs/foreman logs/game
```

- [ ] **Step 3: Copy the updated plist into LaunchAgents**

Run:

```bash
cp gol-tools/foreman/com.dluckdu.foreman-daemon.plist ~/Library/LaunchAgents/com.dluckdu.foreman-daemon.plist
```

Expected: the installed launchd file now matches the repo version.

- [ ] **Step 4: Reload the launchd agent**

Run:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.dluckdu.foreman-daemon.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.dluckdu.foreman-daemon.plist
```

Expected: `bootstrap` succeeds without a path error for `logs/foreman/`.

- [ ] **Step 5: Confirm Foreman writes into the new directory**

Run:

```bash
ls logs/foreman
```

Expected: `daemon-YYYYMMDD.log` plus the two `launchd-daemon*.log` files after the daemon starts.

- [ ] **Step 6: Confirm local `.foreman/` only keeps state and cancellation data**

Run:

```bash
ls -la .foreman
```

Expected: `state.json` and `cancel/` remain; the removed legacy directories do not.

- [ ] **Step 7: Run one final project-level verification pass**

Run:

```bash
cd gol-tools/foreman && npm test
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path gol-project -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/pcg/test_wfc_solver.gd --ignoreHeadlessMode --verbose
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path gol-project res://scenes/tests/test_main.tscn -- --config=res://tests/integration/pcg/test_pcg_map.gd
```

Expected: all three commands exit successfully.

---

### Task 9: Push Submodules First, Then Update the Management Repo Pointer

- [ ] **Step 1: Push the `gol-tools` submodule branch**

```bash
cd gol-tools && git push origin HEAD
```

- [ ] **Step 2: Push the `gol-project` submodule branch**

```bash
cd gol-project && git push origin HEAD
```

- [ ] **Step 3: Commit the updated submodule pointers in the management repo**

```bash
git add gol-tools gol-project
git commit -m "chore: update submodules for unified logging"
```

- [ ] **Step 4: Push the management repo branch**

```bash
git push origin HEAD
```
