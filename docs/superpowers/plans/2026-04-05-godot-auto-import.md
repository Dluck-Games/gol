# Godot Auto-Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automate Godot import cache initialization and `.uid` file generation across all AI workflows (foreman, claude code, opencode) to eliminate manual `chore:` commits and tester runtime failures.

**Architecture:** Extract a reusable `godot-import.mjs` module (library + CLI) from `ai-debug`. Integrate it at four workflow points: worktree creation, pre-commit UID generation, tester launch guard, and AI editor hooks. All consumers call the module via CLI (`node godot-import.mjs <cmd> <dir>`) to avoid cross-package JS imports.

**Tech Stack:** Node.js ESM, Godot 4.6 CLI (`--headless --import --path <dir>`), bash, `node:test` for tests

---

## Problem Context

Three related failures caused by missing Godot import automation:

| Problem | Evidence | Impact |
|---------|----------|--------|
| Worktrees lack `.godot/` cache | Issue #198 tester abort | Tester can't start Godot — all E2E tests fail |
| New `.gd` files lack `.uid` siblings | `foreman/issue-198` branch missing 3 `.uid` files; manual commit `ededcf2` | Incomplete commits, manual cleanup |
| `ai-debug reimport` hardcoded to `gol-project/` | `resolveRuntimePaths()` line 100 | Can't reimport worktrees or non-standard layouts |

## File Structure

```
gol-tools/ai-debug/
├── ai-debug.mjs                    # MODIFY: refactor reimport to use lib
├── lib/
│   └─��� godot-import.mjs            # CREATE: reusable import module + CLI
└── tests/
    ├── ai-debug.test.mjs           # MODIFY: update resolveRuntimePaths tests
    └── godot-import.test.mjs       # CREATE: tests for new module

gol-tools/foreman/
��── bin/
│   └── tester-start-godot.sh       # MODIFY: add .godot/ guard
├── lib/
│   └── workspace-manager.mjs       # MODIFY: auto-import after create()
└── foreman-daemon.mjs              # MODIFY: UID generation before commit

gol-project/
└── .claude/
    └── settings.json               # CREATE: PostToolUse hook for .gd files

gol/.opencode/
└── oh-my-opencode.jsonc            # MODIFY: add godot import bash allow pattern
```

---

### Task 1: Create `godot-import.mjs` Core Module

**Files:**
- Create: `gol-tools/ai-debug/lib/godot-import.mjs`
- Create: `gol-tools/ai-debug/tests/godot-import.test.mjs`

This module provides both importable functions AND a standalone CLI. All other integrations call it via CLI to avoid cross-package JS imports.

- [ ] **Step 1: Create lib directory**

```bash
mkdir -p gol-tools/ai-debug/lib
```

- [ ] **Step 2: Write failing tests for `findProjectDir()`**

```js
// gol-tools/ai-debug/tests/godot-import.test.mjs
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { findProjectDir, findMissingUids, cleanOrphanedUids } from '../lib/godot-import.mjs';

describe('findProjectDir', () => {
    let tmpDir;

    beforeEach(() => {
        tmpDir = mkdtempSync(join(tmpdir(), 'godot-import-test-'));
    });

    afterEach(() => {
        rmSync(tmpDir, { recursive: true, force: true });
    });

    it('finds project.godot at startDir root (worktree layout)', () => {
        writeFileSync(join(tmpDir, 'project.godot'), '');
        assert.equal(findProjectDir(tmpDir), tmpDir);
    });

    it('finds project.godot in gol-project/ subdir (management repo layout)', () => {
        const subDir = join(tmpDir, 'gol-project');
        mkdirSync(subDir);
        writeFileSync(join(subDir, 'project.godot'), '');
        assert.equal(findProjectDir(tmpDir), subDir);
    });

    it('walks upward to find project.godot', () => {
        writeFileSync(join(tmpDir, 'project.godot'), '');
        const deepDir = join(tmpDir, 'scripts', 'systems');
        mkdirSync(deepDir, { recursive: true });
        assert.equal(findProjectDir(deepDir), tmpDir);
    });

    it('prefers direct project.godot over gol-project/ subdir', () => {
        writeFileSync(join(tmpDir, 'project.godot'), '');
        const subDir = join(tmpDir, 'gol-project');
        mkdirSync(subDir);
        writeFileSync(join(subDir, 'project.godot'), '');
        assert.equal(findProjectDir(tmpDir), tmpDir);
    });

    it('returns null when no project found', () => {
        assert.equal(findProjectDir(tmpDir), null);
    });
});
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd gol-tools/ai-debug && node --test tests/godot-import.test.mjs
```

Expected: FAIL — `../lib/godot-import.mjs` does not exist.

- [ ] **Step 4: Implement `findProjectDir()` and `getGodotPath()`**

```js
// gol-tools/ai-debug/lib/godot-import.mjs
//
// Reusable Godot import module — library + CLI.
//
// Library: import { ensureImportCache, runImport, ... } from './godot-import.mjs'
// CLI:    node godot-import.mjs <ensure|reimport|clean-uids|check-uids> <projectDir>

import { existsSync, readdirSync, unlinkSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { execFileSync, spawn } from 'node:child_process';
import { platform } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

/**
 * Find the Godot project directory starting from startDir, walking upward.
 * Recognizes two layouts:
 *   1. Direct: project.godot at directory root (worktree or gol-project checkout)
 *   2. Management repo: gol-project/project.godot
 * @param {string} startDir
 * @returns {string|null} Absolute path to project directory, or null
 */
export function findProjectDir(startDir) {
    let current = resolve(startDir);
    while (true) {
        if (existsSync(join(current, 'project.godot'))) return current;
        if (existsSync(join(current, 'gol-project', 'project.godot'))) {
            return join(current, 'gol-project');
        }
        const parent = dirname(current);
        if (parent === current) return null;
        current = parent;
    }
}

/**
 * Resolve Godot binary path from env or platform default.
 * @returns {string}
 */
export function getGodotPath() {
    if (process.env.GODOT_PATH) return process.env.GODOT_PATH;
    if (platform() === 'darwin') return '/Applications/Godot.app/Contents/MacOS/Godot';
    if (platform() === 'win32') return 'godot.exe';
    return 'godot';
}
```

- [ ] **Step 5: Run tests to verify `findProjectDir` passes**

```bash
cd gol-tools/ai-debug && node --test tests/godot-import.test.mjs
```

Expected: 5 tests PASS.

- [ ] **Step 6: Write failing tests for `findMissingUids()` and `cleanOrphanedUids()`**

Append to `godot-import.test.mjs`:

```js
describe('findMissingUids', () => {
    let tmpDir;

    beforeEach(() => {
        tmpDir = mkdtempSync(join(tmpdir(), 'godot-import-test-'));
        writeFileSync(join(tmpDir, 'project.godot'), '');
        mkdirSync(join(tmpDir, 'scripts'), { recursive: true });
    });

    afterEach(() => {
        rmSync(tmpDir, { recursive: true, force: true });
    });

    it('returns empty array when all .gd have .uid', () => {
        writeFileSync(join(tmpDir, 'scripts', 'main.gd'), '');
        writeFileSync(join(tmpDir, 'scripts', 'main.gd.uid'), 'uid://abc123');
        assert.deepEqual(findMissingUids(tmpDir), []);
    });

    it('returns .gd paths missing .uid', () => {
        writeFileSync(join(tmpDir, 'scripts', 'main.gd'), '');
        writeFileSync(join(tmpDir, 'scripts', 'helper.gd'), '');
        writeFileSync(join(tmpDir, 'scripts', 'helper.gd.uid'), 'uid://def456');
        assert.deepEqual(findMissingUids(tmpDir), [join('scripts', 'main.gd')]);
    });

    it('ignores .godot directory', () => {
        mkdirSync(join(tmpDir, '.godot'), { recursive: true });
        writeFileSync(join(tmpDir, '.godot', 'cache.gd'), '');
        assert.deepEqual(findMissingUids(tmpDir), []);
    });
});

describe('cleanOrphanedUids', () => {
    let tmpDir;

    beforeEach(() => {
        tmpDir = mkdtempSync(join(tmpdir(), 'godot-import-test-'));
        writeFileSync(join(tmpDir, 'project.godot'), '');
        mkdirSync(join(tmpDir, 'scripts'), { recursive: true });
    });

    afterEach(() => {
        rmSync(tmpDir, { recursive: true, force: true });
    });

    it('removes .uid without corresponding source file', () => {
        writeFileSync(join(tmpDir, 'scripts', 'deleted.gd.uid'), 'uid://orphan');
        const removed = cleanOrphanedUids(tmpDir);
        assert.deepEqual(removed, [join('scripts', 'deleted.gd.uid')]);
        assert.equal(existsSync(join(tmpDir, 'scripts', 'deleted.gd.uid')), false);
    });

    it('keeps .uid with existing source file', () => {
        writeFileSync(join(tmpDir, 'scripts', 'alive.gd'), '');
        writeFileSync(join(tmpDir, 'scripts', 'alive.gd.uid'), 'uid://keep');
        const removed = cleanOrphanedUids(tmpDir);
        assert.deepEqual(removed, []);
        assert.equal(existsSync(join(tmpDir, 'scripts', 'alive.gd.uid')), true);
    });

    it('handles mixed orphaned and valid uids', () => {
        writeFileSync(join(tmpDir, 'scripts', 'alive.gd'), '');
        writeFileSync(join(tmpDir, 'scripts', 'alive.gd.uid'), 'uid://keep');
        writeFileSync(join(tmpDir, 'scripts', 'dead.gd.uid'), 'uid://orphan');
        const removed = cleanOrphanedUids(tmpDir);
        assert.deepEqual(removed, [join('scripts', 'dead.gd.uid')]);
    });
});
```

- [ ] **Step 7: Run tests to verify they fail**

```bash
cd gol-tools/ai-debug && node --test tests/godot-import.test.mjs
```

Expected: New tests FAIL — functions not yet exported.

- [ ] **Step 8: Implement `findMissingUids()` and `cleanOrphanedUids()`**

Append to `godot-import.mjs`:

```js
/**
 * Find .gd files without corresponding .uid sibling files.
 * @param {string} projectDir
 * @returns {string[]} Relative paths of .gd files missing .uid
 */
export function findMissingUids(projectDir) {
    const missing = [];
    const walk = (dir) => {
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
            if (entry.name === '.godot' || entry.name === 'node_modules' || entry.name === '.git') continue;
            const full = join(dir, entry.name);
            if (entry.isDirectory()) {
                walk(full);
            } else if (entry.name.endsWith('.gd') && !entry.name.endsWith('.uid')) {
                if (!existsSync(full + '.uid')) {
                    missing.push(full.slice(projectDir.length + 1));
                }
            }
        }
    };
    walk(projectDir);
    return missing;
}

/**
 * Remove .uid files whose source file no longer exists.
 * @param {string} projectDir
 * @returns {string[]} Relative paths of removed .uid files
 */
export function cleanOrphanedUids(projectDir) {
    const removed = [];
    const walk = (dir) => {
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
            if (entry.name === '.godot' || entry.name === 'node_modules' || entry.name === '.git') continue;
            const full = join(dir, entry.name);
            if (entry.isDirectory()) {
                walk(full);
            } else if (entry.name.endsWith('.uid')) {
                const sourcePath = full.slice(0, -4);
                if (!existsSync(sourcePath)) {
                    unlinkSync(full);
                    removed.push(full.slice(projectDir.length + 1));
                }
            }
        }
    };
    walk(projectDir);
    return removed;
}
```

- [ ] **Step 9: Run tests to verify all pass**

```bash
cd gol-tools/ai-debug && node --test tests/godot-import.test.mjs
```

Expected: All 11 tests PASS.

- [ ] **Step 10: Implement `runImport()` and `ensureImportCache()`**

Insert into `godot-import.mjs` between `getGodotPath()` and `findMissingUids()`:

```js
/**
 * Run Godot headless import for a project directory.
 * Uses execFileSync with array args (no shell injection risk).
 * @param {string} projectDir — must contain project.godot
 * @param {object} [opts]
 * @param {boolean} [opts.killExisting] — pkill Godot first
 * @param {boolean} [opts.clearCache] — remove .godot/imported/ before import
 * @param {string}  [opts.godotPath] — override Godot binary
 * @param {number}  [opts.timeout] — ms, default 120000
 * @returns {Promise<{status: string, projectDir: string}>}
 */
export async function runImport(projectDir, opts = {}) {
    const godotPath = opts.godotPath || getGodotPath();
    const timeout = opts.timeout || 120000;

    if (opts.killExisting) {
        try { execFileSync('pkill', ['-f', 'Godot'], { stdio: 'ignore' }); } catch {}
        await new Promise(r => setTimeout(r, 1000));
    }

    if (opts.clearCache) {
        const importedDir = join(projectDir, '.godot', 'imported');
        if (existsSync(importedDir)) {
            rmSync(importedDir, { recursive: true, force: true });
        }
    }

    return new Promise((resolve, reject) => {
        const proc = spawn(godotPath, ['--headless', '--import', '--path', projectDir], {
            stdio: ['ignore', 'pipe', 'pipe'],
        });

        let stderr = '';
        proc.stderr.on('data', d => { stderr += d.toString(); });

        const timer = setTimeout(() => {
            proc.kill('SIGTERM');
            reject(new Error(`Import timed out after ${timeout}ms`));
        }, timeout);

        proc.on('close', code => {
            clearTimeout(timer);
            if (code === 0) resolve({ status: 'imported', projectDir });
            else reject(new Error(`Import failed (exit ${code}): ${stderr.slice(-500)}`));
        });

        proc.on('error', err => {
            clearTimeout(timer);
            reject(new Error(`Failed to run Godot: ${err.message}`));
        });
    });
}

/**
 * Ensure .godot/ import cache exists. Runs headless import only if missing.
 * @param {string} projectDir
 * @param {object} [opts] — same as runImport opts, plus:
 * @param {boolean} [opts.force] — reimport even if .godot/ exists
 * @returns {Promise<{status: string, projectDir: string}>}
 */
export async function ensureImportCache(projectDir, opts = {}) {
    if (!projectDir) throw new Error('projectDir is required');
    if (!existsSync(join(projectDir, 'project.godot'))) {
        throw new Error(`Not a Godot project: ${projectDir}`);
    }

    const godotDir = join(projectDir, '.godot');
    if (existsSync(godotDir) && !opts.force) {
        return { status: 'exists', projectDir };
    }

    return runImport(projectDir, opts);
}
```

- [ ] **Step 11: Add CLI entry point**

Append to the end of `godot-import.mjs`:

```js
// --- CLI entry point ---
const __filename = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === resolve(__filename)) {
    const [cmd, dir] = process.argv.slice(2);
    if (!cmd || !dir) {
        console.error('Usage: godot-import.mjs <ensure|reimport|clean-uids|check-uids> <projectDir>');
        process.exit(2);
    }

    try {
        switch (cmd) {
            case 'ensure': {
                const result = await ensureImportCache(dir);
                console.log(result.status === 'exists' ? 'Cache already exists' : 'Import completed');
                break;
            }
            case 'reimport': {
                await runImport(dir, { killExisting: true, clearCache: true });
                console.log('Reimport completed');
                break;
            }
            case 'clean-uids': {
                const removed = cleanOrphanedUids(dir);
                if (removed.length) console.log(`Removed ${removed.length} orphaned .uid files:\n${removed.join('\n')}`);
                else console.log('No orphaned .uid files');
                break;
            }
            case 'check-uids': {
                const missing = findMissingUids(dir);
                if (missing.length) {
                    console.log(`Missing .uid for ${missing.length} files:\n${missing.join('\n')}`);
                    process.exit(1);
                } else {
                    console.log('All .gd files have .uid');
                }
                break;
            }
            default:
                console.error(`Unknown command: ${cmd}`);
                process.exit(2);
        }
    } catch (err) {
        console.error(`Error: ${err.message}`);
        process.exit(1);
    }
}
```

- [ ] **Step 12: Run all tests**

```bash
cd gol-tools/ai-debug && node --test tests/godot-import.test.mjs
```

Expected: All 11 tests PASS. (`runImport`/`ensureImportCache` are not unit-tested — they require real Godot; verified via integration in Task 7.)

- [ ] **Step 13: Commit**

```bash
cd gol-tools/ai-debug
git add lib/godot-import.mjs tests/godot-import.test.mjs
git commit -m "feat(ai-debug): add godot-import module — reusable import cache and UID management"
```

---

### Task 2: Refactor `ai-debug.mjs` to Use the Module

**Files:**
- Modify: `gol-tools/ai-debug/ai-debug.mjs:63-107` (path resolution) and `401-458` (reimport)
- Modify: `gol-tools/ai-debug/tests/ai-debug.test.mjs:234-259` (resolveRuntimePaths tests)

- [ ] **Step 1: Update `resolveRuntimePaths()` to use `findProjectDir()`**

In `ai-debug.mjs`, replace the path resolution block (lines 63–107). Remove `hasProjectLayout()`, `findRepoRoot()`, `getDefaultGodotPath()`. Replace `resolveRuntimePaths()`:

```js
import { findProjectDir, getGodotPath } from './lib/godot-import.mjs';

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));

export function resolveRuntimePaths(moduleDir = MODULE_DIR) {
    const projectDir = findProjectDir(moduleDir);
    const repoRoot = projectDir ? path.resolve(projectDir, '..') : path.resolve(moduleDir, '..', '..');
    return {
        repoRoot,
        projectDir: projectDir || path.join(repoRoot, 'gol-project'),
        importedDir: path.join(projectDir || path.join(repoRoot, 'gol-project'), '.godot', 'imported'),
        godotPath: getGodotPath(),
    };
}
```

- [ ] **Step 2: Replace `reimportAssets()` with delegation to module**

Replace `reimportAssets()` (lines 401–458) with:

```js
import { runImport } from './lib/godot-import.mjs';

async function reimportAssets(projectDir) {
    projectDir = projectDir || PROJECT_DIR;
    console.log(`Reimporting assets in ${projectDir}...`);
    await runImport(projectDir, { killExisting: true, clearCache: true });
    return 'Asset reimport completed. UID files refreshed.';
}
```

- [ ] **Step 3: Add `--path` support to reimport CLI route**

Update `resolveCommand()` case for `reimport` (around line 237):

```js
case 'reimport':
    return { type: 'reimport', projectDir: positional[0] || null };
```

Update `main()` reimport handler (around line 490):

```js
case 'reimport':
    result = await reimportAssets(route.projectDir);
    break;
```

- [ ] **Step 4: Update tests for `resolveRuntimePaths`**

The existing tests at `tests/ai-debug.test.mjs:234-259` use `withExistsSyncMap` to mock filesystem. Update them to reflect the new `findProjectDir` path — the behavior should be the same (management repo layout: `<root>/gol-project/project.godot`). If any test checks for internal function names like `hasProjectLayout`, update to match new code.

- [ ] **Step 5: Run all ai-debug tests**

```bash
cd gol-tools/ai-debug && node --test tests/ai-debug.test.mjs && node --test tests/godot-import.test.mjs
```

Expected: All tests PASS.

- [ ] **Step 6: Verify CLI reimport with path arg works**

```bash
cd gol-tools/ai-debug
node ai-debug.mjs reimport /tmp/nonexistent 2>&1 | grep -q "Not a Godot project" && echo "PASS: path validation works"
```

- [ ] **Step 7: Commit**

```bash
cd gol-tools/ai-debug
git add ai-debug.mjs tests/ai-debug.test.mjs
git commit -m "refactor(ai-debug): delegate reimport to godot-import module, add --path support"
```

---

### Task 3: Add `.godot/` Guard to `tester-start-godot.sh`

**Files:**
- Modify: `gol-tools/foreman/bin/tester-start-godot.sh`

This is the quickest fix — a bash guard that ensures `.godot/` exists before launching Godot. Acts as the last line of defense even if workspace-manager import fails.

- [ ] **Step 1: Add import guard to tester-start-godot.sh**

Replace the full file with:

```bash
#!/bin/bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <workspace> <scene-path> [extra-godot-args...]" >&2
    exit 2
fi

WORKSPACE="$1"
SCENE_PATH="$2"
shift 2

GODOT_BIN="${GODOT_PATH:-/Applications/Godot.app/Contents/MacOS/Godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT_SCRIPT="$SCRIPT_DIR/../../ai-debug/lib/godot-import.mjs"

# Ensure .godot/ import cache exists before launching
if [ ! -d "$WORKSPACE/.godot" ]; then
    echo "Missing .godot/ cache — running headless import..." >&2
    node "$IMPORT_SCRIPT" ensure "$WORKSPACE"
fi

cd "$WORKSPACE"
exec "$GODOT_BIN" --path "$WORKSPACE" "$SCENE_PATH" "$@"
```

Key changes vs original:
- `GODOT_BIN` now respects `$GODOT_PATH` env var (was hardcoded)
- `.godot/` existence check calls `godot-import.mjs ensure` before `exec`
- Uses `$SCRIPT_DIR` relative path to find import script (same submodule)

- [ ] **Step 2: Verify script syntax**

```bash
bash -n gol-tools/foreman/bin/tester-start-godot.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
cd gol-tools
git add foreman/bin/tester-start-godot.sh
git commit -m "fix(foreman): add .godot/ import guard to tester-start-godot.sh"
```

---

### Task 4: Auto-Import on Worktree Creation

**Files:**
- Modify: `gol-tools/foreman/lib/workspace-manager.mjs:110-113`
- Modify: `gol-tools/foreman/tests/workspace-manager.test.mjs`

When `workspace-manager.mjs:create()` finishes creating a worktree for `gol-project`, run `godot-import.mjs ensure` to seed the `.godot/` cache. This is non-fatal — if import fails, log a warning and continue (tester guard in Task 3 is the fallback).

- [ ] **Step 1: Write failing test for import integration**

Append to `gol-tools/foreman/tests/workspace-manager.test.mjs`. The real test is that `create()` completes without throwing when `godot-import.mjs ensure` fails (Godot not installed in test env):

```js
it('completes create() even when Godot import fails (no Godot binary)', async () => {
    // Add project.godot to source repo so worktree has it
    writeFileSync(join(repoDir, 'project.godot'), '');
    git(repoDir, ['add', 'project.godot']);
    git(repoDir, ['commit', '-m', 'add project.godot']);
    git(repoDir, ['push', 'origin', 'main']);

    const wm = new WorkspaceManager(config);
    const wsPath = await wm.create({ newBranch: 'test-import' });

    // Worktree created successfully despite import failure
    assert.ok(existsSync(join(wsPath, 'project.godot')));
});
```

- [ ] **Step 2: Add `#ensureGodotImport()` to WorkspaceManager**

In `workspace-manager.mjs`, add a new private method:

```js
#ensureGodotImport(wsPath) {
    if (!existsSync(join(wsPath, 'project.godot'))) return;

    const importScript = join(this.#config.workDir, 'gol-tools', 'ai-debug', 'lib', 'godot-import.mjs');
    if (!existsSync(importScript)) {
        warn(COMPONENT, `godot-import.mjs not found at ${importScript}, skipping import`);
        return;
    }

    try {
        info(COMPONENT, `Running Godot import for ${basename(wsPath)}...`);
        execFileSync('node', [importScript, 'ensure', wsPath], {
            timeout: 120000,
            stdio: 'pipe',
        });
        info(COMPONENT, `Godot import cache ready for ${basename(wsPath)}`);
    } catch (e) {
        warn(COMPONENT, `Godot import failed for ${basename(wsPath)}: ${e.message}`);
    }
}
```

Ensure `basename` is imported from `node:path` (check existing imports — `join` is imported, `basename` is used in `destroy()` but confirm it's in the import list).

- [ ] **Step 3: Call `#ensureGodotImport()` in `create()` before return**

Insert between the info log and return (between current lines 112 and 113):

```js
        info(COMPONENT, `Worktree created: ${wsPath}`);

        this.#ensureGodotImport(wsPath);

        return wsPath;
```

- [ ] **Step 4: Run workspace-manager tests**

```bash
cd gol-tools/foreman && node --test tests/workspace-manager.test.mjs
```

Expected: All tests PASS (existing tests unaffected, new test passes because import failure is non-fatal).

- [ ] **Step 5: Commit**

```bash
cd gol-tools
git add foreman/lib/workspace-manager.mjs foreman/tests/workspace-manager.test.mjs
git commit -m "feat(foreman): auto-import Godot cache on worktree creation"
```

---

### Task 5: UID Generation Before Commit in Foreman Daemon

**Files:**
- Modify: `gol-tools/foreman/foreman-daemon.mjs:230-231` (pre-commit injection point)

After the coder finishes and before `#runCommitStep`, run `godot-import.mjs ensure` to generate `.uid` files for new scripts, then `clean-uids` to remove orphans. The `git add -A` inside `#runCommitStep` (line 1078) will automatically stage the generated/removed `.uid` files.

- [ ] **Step 1: Add `#ensureUidsBeforeCommit()` method**

Add to the daemon class near `#runCommitStep`. Check existing imports at the top of the file — `existsSync` and `join` are likely already imported from previous code:

```js
#ensureUidsBeforeCommit(task) {
    const { issue_number, workspace } = task;
    if (!workspace) return;
    if (!existsSync(join(workspace, 'project.godot'))) return;

    const importScript = join(this.#config.workDir, 'gol-tools', 'ai-debug', 'lib', 'godot-import.mjs');
    if (!existsSync(importScript)) {
        warn(COMPONENT, `#${issue_number}: godot-import.mjs not found, skipping UID generation`);
        return;
    }

    try {
        execFileSync('node', [importScript, 'ensure', workspace], {
            timeout: 120000,
            stdio: 'pipe',
        });
        info(COMPONENT, `#${issue_number}: Godot import cache ensured`);
    } catch (e) {
        warn(COMPONENT, `#${issue_number}: Godot import failed: ${e.message}`);
    }

    try {
        const output = execFileSync('node', [importScript, 'clean-uids', workspace], {
            timeout: 30000,
            encoding: 'utf-8',
            stdio: 'pipe',
        });
        if (output.includes('Removed')) info(COMPONENT, `#${issue_number}: ${output.trim()}`);
    } catch (e) {
        warn(COMPONENT, `#${issue_number}: UID cleanup failed: ${e.message}`);
    }
}
```

Note: Uses `execFileSync` (array args) instead of `execSync` (shell string) — prevents command injection.

- [ ] **Step 2: Inject call before `#runCommitStep`**

At line 230–231, change:

```js
// BEFORE:
if (agentRole === 'coder') {
    const commitResult = this.#runCommitStep(task);

// AFTER:
if (agentRole === 'coder') {
    this.#ensureUidsBeforeCommit(task);
    const commitResult = this.#runCommitStep(task);
```

- [ ] **Step 3: Verify daemon loads without syntax errors**

```bash
cd gol-tools/foreman && node -e "import('./foreman-daemon.mjs').catch(e => { console.error(e.message); process.exit(1); })"
```

Expected: No syntax errors (may warn about missing config/state — that's fine).

- [ ] **Step 4: Commit**

```bash
cd gol-tools
git add foreman/foreman-daemon.mjs
git commit -m "feat(foreman): generate .uid files and clean orphans before coder commit"
```

---

### Task 6: Regular AI Workflow Integration

**Files:**
- Create: `gol-project/.claude/settings.json`
- Modify: `gol/.opencode/oh-my-opencode.jsonc`
- Modify: `gol/.claude/skills/gol-debug/SKILL.md` (documentation only)

- [ ] **Step 1: Create Claude Code project-level hook for gol-project**

When AI agents create `.gd` files in `gol-project/`, a PostToolUse hook runs `ensure` which is a no-op if `.godot/` already exists (instant return). Only triggers the heavier Godot import (~15-30s) when `.godot/` is missing or after cache deletion.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'if echo \"$CLAUDE_FILE_PATH\" | grep -qE \"\\.gd$\"; then REPO=$(cd gol-project 2>/dev/null && pwd || pwd); node gol-tools/ai-debug/lib/godot-import.mjs ensure \"$REPO\" 2>/dev/null; fi'"
          }
        ]
      }
    ]
  }
}
```

Save as `gol-project/.claude/settings.json`.

**Note:** This hook runs from the management repo root (`gol/`). The `$CLAUDE_FILE_PATH` env variable is set by Claude Code to the path of the file being written. The hook checks if it's a `.gd` file before invoking import.

- [ ] **Step 2: Update OpenCode bash allow patterns**

In `gol/.opencode/oh-my-opencode.jsonc`, find the `allowedBash` arrays for both agents and add:

```jsonc
"node*godot-import*"
```

This allows the `godot-import.mjs` CLI to run from OpenCode agents. The existing `godot* *--headless* *--path*` pattern already matches the `godot --headless --import --path <dir>` invocation.

- [ ] **Step 3: Update gol-debug skill documentation**

In `gol/.claude/skills/gol-debug/SKILL.md`, add a section:

```markdown
### Auto-Import (UID generation)

When creating new `.gd` files, run import to generate `.uid` sidecar files:

    node gol-tools/ai-debug/lib/godot-import.mjs ensure gol-project

To check for missing UIDs without importing:

    node gol-tools/ai-debug/lib/godot-import.mjs check-uids gol-project

To clean orphaned `.uid` files after deleting scripts:

    node gol-tools/ai-debug/lib/godot-import.mjs clean-uids gol-project

For worktrees, replace `gol-project` with the worktree path.
```

- [ ] **Step 4: Commit all workflow integration changes**

```bash
# In gol-project submodule:
cd gol-project
mkdir -p .claude
# (settings.json was created in Step 1)
git add .claude/settings.json
git commit -m "feat: add PostToolUse hook for automatic Godot .uid generation"

# In management repo:
cd ..
git add gol-project .opencode/oh-my-opencode.jsonc .claude/skills/gol-debug/SKILL.md
git commit -m "feat: integrate godot auto-import across AI workflows"
```

---

### Task 7: Integration Verification

**Files:** None (verification only)

- [ ] **Step 1: Run all test suites**

```bash
cd gol-tools/ai-debug && node --test tests/godot-import.test.mjs && node --test tests/ai-debug.test.mjs
cd ../foreman && node --test tests/workspace-manager.test.mjs
```

Expected: All tests PASS.

- [ ] **Step 2: Manual verification — reimport with --path**

```bash
cd gol
gol reimport gol-project
```

Expected: Import completes, `.godot/` exists, no errors.

- [ ] **Step 3: Manual verification — worktree import**

```bash
cd gol-project
git worktree add ../../.worktrees/manual/test-import -b test-import origin/main
ls ../../.worktrees/manual/test-import/.godot/ 2>&1  # Should NOT exist yet

node ../gol-tools/ai-debug/lib/godot-import.mjs ensure ../../.worktrees/manual/test-import
ls ../../.worktrees/manual/test-import/.godot/  # Should exist now

# Cleanup
git worktree remove ../../.worktrees/manual/test-import --force
git branch -D test-import
```

- [ ] **Step 4: Manual verification — UID check and generation**

```bash
# Create a test .gd file without .uid
echo 'extends Node' > gol-project/scripts/test_uid_check.gd
node gol-tools/ai-debug/lib/godot-import.mjs check-uids gol-project
# Expected: reports test_uid_check.gd as missing .uid

node gol-tools/ai-debug/lib/godot-import.mjs ensure gol-project --force
# Expected: import runs, generates .uid

ls gol-project/scripts/test_uid_check.gd.uid
# Expected: file exists

# Cleanup
rm gol-project/scripts/test_uid_check.gd gol-project/scripts/test_uid_check.gd.uid
```

- [ ] **Step 5: Manual verification — orphan cleanup**

```bash
echo 'uid://test123' > gol-project/scripts/orphan_test.gd.uid
node gol-tools/ai-debug/lib/godot-import.mjs clean-uids gol-project
# Expected: "Removed 1 orphaned .uid files"

ls gol-project/scripts/orphan_test.gd.uid 2>&1
# Expected: No such file
```

- [ ] **Step 6: Push submodule changes**

```bash
cd gol-tools && git push origin main
cd ../gol-project && git push origin main
cd .. && git add gol-tools gol-project && git commit -m "update submodules: godot auto-import feature" && git push
```

---

## Risk Notes

| Risk | Mitigation |
|------|------------|
| Headless import takes 15-30s, slowing worktree creation | Non-blocking for planner/reviewer (only runs when `project.godot` exists); acceptable one-time cost for coder/tester workflows |
| Godot binary not installed in CI | `#ensureGodotImport` is non-fatal (warn + skip); CI tests.yml uses its own Godot setup |
| Import generates unexpected file changes | `.godot/` is gitignored; only `.uid` files are tracked, and those are the intended output |
| `pkill -f "Godot"` in `runImport({killExisting})` could kill user's editor | Only used by `reimport` CLI command (explicit user action), never by `ensure` (workspace/tester flow) |
