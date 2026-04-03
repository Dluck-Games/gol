# Foreman Pure-CLI Permission Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the broken `settings.local.json` permission layer and move all permission control to CLI `--allowedTools` with path-scoped patterns, fixing the two root causes that render agent path constraints void.

**Architecture:** Extract the path-scoping logic from `#writeAgentSettings()` into a pure function `buildScopedTools()` in a new `lib/permission-utils.mjs`. Each daemon spawn method calls this function to build path-scoped tool entries (e.g. `Write(/abs/path/**)`), then passes them as `roleConfig.allowedTools` to `ProcessManager.spawn()`. The CLI `--permission-mode` changes from `bypassPermissions` to `default`, and the scoped entries flow directly as `--allowedTools` CLI args. No files are written or cleaned up.

**Tech Stack:** Node.js (ES modules), `node:test` for testing

**Root causes addressed:**
1. `bypassPermissions` mode ignores `settings.local.json` entirely → fixed by switching to `default` mode
2. `--allowedTools` CLI flag with bare tool names overrides path-scoped `settings.local.json` rules → fixed by passing path-scoped entries directly via CLI, eliminating `settings.local.json` entirely

---

### Task 1: Create `buildScopedTools()` pure function

**Files:**
- Create: `gol-tools/foreman/lib/permission-utils.mjs`
- Test: `gol-tools/foreman/tests/permission-utils.test.mjs`

This extracts the core logic from `#writeAgentSettings()` (foreman-daemon.mjs:378–410) into a standalone, testable pure function. The logic is identical — it maps `allowedTools` strings + `pathConstraints` object into an array of scoped permission entries.

- [ ] **Step 1: Write the failing tests**

```js
// tests/permission-utils.test.mjs
import { describe, it } from 'node:test';
import assert from 'node:assert';
import { buildScopedTools } from '../lib/permission-utils.mjs';

describe('buildScopedTools', () => {
    it('scopes Read/Grep/Glob/LS to readPaths', () => {
        const result = buildScopedTools(
            ['Read', 'Grep', 'Glob', 'LS'],
            { readPaths: ['/ws/project', '/ws/docs'] },
        );
        assert.deepStrictEqual(result, [
            'Read(/ws/project/**)', 'Read(/ws/docs/**)',
            'Grep(/ws/project/**)', 'Grep(/ws/docs/**)',
            'Glob(/ws/project/**)', 'Glob(/ws/docs/**)',
            'LS(/ws/project/**)',   'LS(/ws/docs/**)',
        ]);
    });

    it('scopes Write/NotebookEdit to writePaths', () => {
        const result = buildScopedTools(
            ['Write', 'NotebookEdit'],
            { writePaths: ['/ws/scripts', '/ws/docs'] },
        );
        assert.deepStrictEqual(result, [
            'Write(/ws/scripts/**)', 'Write(/ws/docs/**)',
            'NotebookEdit(/ws/scripts/**)', 'NotebookEdit(/ws/docs/**)',
        ]);
    });

    it('scopes Edit to editPaths', () => {
        const result = buildScopedTools(
            ['Edit'],
            { editPaths: ['/ws/scripts'] },
        );
        assert.deepStrictEqual(result, ['Edit(/ws/scripts/**)']);
    });

    it('scopes Bash to bashAllow commands', () => {
        const result = buildScopedTools(
            ['Bash'],
            { bashAllow: ['git status', 'git status:*'] },
        );
        assert.deepStrictEqual(result, [
            'Bash(git status)', 'Bash(git status:*)',
        ]);
    });

    it('passes non-file tools unscoped', () => {
        const result = buildScopedTools(
            ['TodoWrite', 'Task', 'TaskOutput'],
            {},
        );
        assert.deepStrictEqual(result, ['TodoWrite', 'Task', 'TaskOutput']);
    });

    it('falls back to wildcard (**) when no paths provided for file tools', () => {
        const result = buildScopedTools(['Read', 'Write', 'Edit'], {});
        assert.deepStrictEqual(result, ['Read(**)', 'Write(**)', 'Edit(**)']);
    });

    it('returns empty array for null/undefined allowedTools', () => {
        assert.deepStrictEqual(buildScopedTools(null, {}), []);
        assert.deepStrictEqual(buildScopedTools(undefined, {}), []);
    });

    it('omits Bash entirely when no bashAllow commands given', () => {
        const result = buildScopedTools(['Bash'], {});
        assert.deepStrictEqual(result, []);
    });

    it('handles full coder role scenario', () => {
        const result = buildScopedTools(
            ['Read', 'Write', 'Edit', 'Grep', 'Glob', 'LS', 'Bash', 'Task', 'TaskOutput', 'TodoWrite'],
            {
                readPaths:  ['/ws', '/docs'],
                writePaths: ['/ws/scripts', '/ws/tests', '/docs'],
                editPaths:  ['/ws/scripts', '/ws/tests'],
                bashAllow:  ['/bin/run-tests.sh', '/bin/run-tests.sh:*'],
            },
        );
        assert.ok(result.includes('Read(/ws/**)'));
        assert.ok(result.includes('Read(/docs/**)'));
        assert.ok(result.includes('Write(/ws/scripts/**)'));
        assert.ok(result.includes('Write(/ws/tests/**)'));
        assert.ok(result.includes('Write(/docs/**)'));
        assert.ok(result.includes('Edit(/ws/scripts/**)'));
        assert.ok(result.includes('Edit(/ws/tests/**)'));
        assert.ok(result.includes('Bash(/bin/run-tests.sh)'));
        assert.ok(result.includes('Bash(/bin/run-tests.sh:*)'));
        assert.ok(result.includes('Task'));
        assert.ok(result.includes('TodoWrite'));
        // Edit should NOT have /docs/** (not in editPaths)
        assert.ok(!result.includes('Edit(/docs/**)'));
        // Write should NOT have /ws/** (not in writePaths, only subdirs)
        assert.ok(!result.includes('Write(/ws/**)'));
    });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && node --test tests/permission-utils.test.mjs`
Expected: FAIL — `Cannot find module '../lib/permission-utils.mjs'`

- [ ] **Step 3: Write the implementation**

```js
// lib/permission-utils.mjs

const READ_TOOLS  = new Set(['Read', 'Grep', 'Glob', 'LS']);
const WRITE_TOOLS = new Set(['Write', 'NotebookEdit']);
const EDIT_TOOLS  = new Set(['Edit']);

/**
 * Build path-scoped tool permission entries from role allowedTools + pathConstraints.
 *
 * Returns an array of strings like:
 *   "Read(/workspace/**)", "Write(/scripts/**)", "Bash(git status)", "TodoWrite"
 *
 * These are passed directly as CLI --allowedTools arguments.
 * In `--permission-mode default` with `-p` (headless), any tool NOT in this list
 * defaults to `ask` which auto-rejects — effectively a whitelist.
 *
 * @param {string[]|null} allowedTools  - bare tool names from role config (e.g. ['Read', 'Write', 'Bash'])
 * @param {object} pathConstraints      - path scoping per tool category
 * @param {string[]} [pathConstraints.readPaths]  - dirs for Read/Grep/Glob/LS
 * @param {string[]} [pathConstraints.writePaths] - dirs for Write/NotebookEdit
 * @param {string[]} [pathConstraints.editPaths]  - dirs for Edit
 * @param {string[]} [pathConstraints.bashAllow]  - exact command strings (pre-expanded with :* variants)
 * @returns {string[]} scoped permission entries for CLI --allowedTools
 */
export function buildScopedTools(allowedTools, pathConstraints = {}) {
    if (!allowedTools || allowedTools.length === 0) return [];

    const result = [];

    for (const tool of allowedTools) {
        if (READ_TOOLS.has(tool)) {
            const paths = pathConstraints.readPaths;
            if (paths?.length > 0) {
                for (const p of paths) result.push(`${tool}(${p}/**)`);
            } else {
                result.push(`${tool}(**)`);
            }
        } else if (EDIT_TOOLS.has(tool)) {
            const paths = pathConstraints.editPaths;
            if (paths?.length > 0) {
                for (const p of paths) result.push(`${tool}(${p}/**)`);
            } else {
                result.push(`${tool}(**)`);
            }
        } else if (WRITE_TOOLS.has(tool)) {
            const paths = pathConstraints.writePaths;
            if (paths?.length > 0) {
                for (const p of paths) result.push(`${tool}(${p}/**)`);
            } else {
                result.push(`${tool}(**)`);
            }
        } else if (tool === 'Bash') {
            const commands = pathConstraints.bashAllow || [];
            for (const command of commands) result.push(`Bash(${command})`);
        } else {
            result.push(tool);
        }
    }

    return result;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/foreman && node --test tests/permission-utils.test.mjs`
Expected: All 9 tests PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/permission-utils.mjs tests/permission-utils.test.mjs
git commit -m "feat(foreman): add buildScopedTools pure function for CLI permissions

Extracts path-scoping logic from #writeAgentSettings into a testable
pure function. This will replace the settings.local.json file-based
permission layer with direct CLI --allowedTools arguments."
```

---

### Task 2: Switch `process-manager` to `default` permission mode

**Files:**
- Modify: `gol-tools/foreman/lib/process-manager.mjs:30-51` — change `permissionFlags` in all 3 PROVIDER_SPECS entries
- Modify: `gol-tools/foreman/tests/process-manager.test.mjs` — update assertions that check spawned args

- [ ] **Step 1: Find and update test assertions for permission mode**

Search the test file for `bypassPermissions` references. Each provider test asserts the spawned CLI args contain `--permission-mode bypassPermissions`. Update all assertions to expect `default` instead.

In `tests/process-manager.test.mjs`, find every assertion matching `bypassPermissions` and replace with `default`. Example pattern:

```js
// BEFORE
assert.ok(spawnedArgs.includes('bypassPermissions'), ...);
// or
assert.deepStrictEqual(spawnedArgs.slice(x, y), ['--permission-mode', 'bypassPermissions']);

// AFTER
assert.ok(spawnedArgs.includes('default'), ...);
// or
assert.deepStrictEqual(spawnedArgs.slice(x, y), ['--permission-mode', 'default']);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && node --test tests/process-manager.test.mjs`
Expected: FAIL — tests expect `default` but code still produces `bypassPermissions`

- [ ] **Step 3: Change permissionFlags in process-manager.mjs**

In `gol-tools/foreman/lib/process-manager.mjs`, change lines 33, 40, 47:

```js
// BEFORE (line 33)
permissionFlags: ['--permission-mode', 'bypassPermissions'],

// AFTER (line 33)
permissionFlags: ['--permission-mode', 'default'],
```

Apply the same change for `claude` (line 40) and `claude-internal` (line 47).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/foreman && node --test tests/process-manager.test.mjs`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/process-manager.mjs tests/process-manager.test.mjs
git commit -m "fix(foreman): switch from bypassPermissions to default mode

bypassPermissions completely ignores settings.local.json and all
path-level permission rules. Switching to default mode enables
the CLI permission evaluation engine, making --allowedTools entries
(including path-scoped patterns) actually enforced."
```

---

### Task 3: Wire `buildScopedTools` into daemon spawn methods

**Files:**
- Modify: `gol-tools/foreman/foreman-daemon.mjs`
  - Add import for `buildScopedTools` from `./lib/permission-utils.mjs`
  - Lines 227-231: TL — replace `#writeAgentSettings` with `buildScopedTools`, pass scoped config to tl-dispatcher
  - Lines 475-481: Planner — replace `#writeAgentSettings` + `#spawnTracked` with scoped flow
  - Lines 526-535: Coder — same pattern
  - Lines 586-592: Reviewer — same pattern
  - Lines 639-646: Tester — same pattern
  - Lines 1337-1340: `#respawnCurrentAgent` — replace `#writeAgentSettings` with `buildScopedTools`

The pattern for each spawn method (planner/coder/reviewer/tester) is identical:

```js
// BEFORE (example: planner, lines 475-481)
const pathConstraints = {
    readPaths:  [workspace, docDir],
    writePaths: [docDir],
    bashAllow:  this.#getReadOnlyGitBashAllow(),
};
this.#writeAgentSettings(workspace, roleConfig, pathConstraints);
const pid = this.#spawnTracked(issue_number, workspace, prompt, logPrefix, roleConfig, pathConstraints);

// AFTER
const pathConstraints = {
    readPaths:  [workspace, docDir],
    writePaths: [docDir],
    bashAllow:  this.#getReadOnlyGitBashAllow(),
};
const scopedConfig = { ...roleConfig, allowedTools: buildScopedTools(roleConfig.allowedTools, pathConstraints) };
const pid = this.#spawnTracked(issue_number, workspace, prompt, logPrefix, scopedConfig, pathConstraints);
```

- [ ] **Step 1: Add import**

At top of `foreman-daemon.mjs`, add:

```js
import { buildScopedTools } from './lib/permission-utils.mjs';
```

- [ ] **Step 2: Replace planner spawn (lines ~475-481)**

Remove `this.#writeAgentSettings(workspace, roleConfig, pathConstraints);` and replace the spawn call:

```js
const pathConstraints = {
    readPaths:  [workspace, docDir],
    writePaths: [docDir],
    bashAllow:  this.#getReadOnlyGitBashAllow(),
};
const scopedConfig = { ...roleConfig, allowedTools: buildScopedTools(roleConfig.allowedTools, pathConstraints) };
const pid = this.#spawnTracked(issue_number, workspace, prompt, logPrefix, scopedConfig, pathConstraints);
```

- [ ] **Step 3: Replace coder spawn (lines ~526-535)**

Same pattern. Remove `this.#writeAgentSettings(...)`, build `scopedConfig`:

```js
const coderWriteSubdirs = ['scripts', 'tests', 'resources'].map(d => join(workspace, d));
const pathConstraints = {
    readPaths:  [workspace, docDir],
    writePaths: [...coderWriteSubdirs, docDir],
    editPaths:  [...coderWriteSubdirs],
    bashAllow:  this.#getCoderBashAllow(),
};
const scopedConfig = { ...roleConfig, allowedTools: buildScopedTools(roleConfig.allowedTools, pathConstraints) };
const pid = this.#spawnTracked(issue_number, workspace, prompt, logPrefix, scopedConfig, pathConstraints);
```

- [ ] **Step 4: Replace reviewer spawn (lines ~586-592)**

```js
const pathConstraints = {
    readPaths:  [cwd, docDir],
    writePaths: [docDir],
    bashAllow:  this.#getReadOnlyGitBashAllow(),
};
const scopedConfig = { ...roleConfig, allowedTools: buildScopedTools(roleConfig.allowedTools, pathConstraints) };
const pid = this.#spawnTracked(issue_number, cwd, prompt, logPrefix, scopedConfig, pathConstraints);
```

- [ ] **Step 5: Replace tester spawn (lines ~639-646)**

```js
const pathConstraints = {
    readPaths:  [cwd, docDir, '/tmp'],
    writePaths: ['/tmp', docDir],
    editPaths:  ['/tmp'],
    bashAllow:  this.#getTesterBashAllow(),
};
const scopedConfig = { ...roleConfig, allowedTools: buildScopedTools(roleConfig.allowedTools, pathConstraints) };
const pid = this.#spawnTracked(issue_number, cwd, prompt, logPrefix, scopedConfig, pathConstraints);
```

- [ ] **Step 6: Replace `#respawnCurrentAgent` (lines ~1337-1340)**

```js
// BEFORE
const pathConstraints = remapPathConstraintsForRespawn(ctx.pathConstraints, ctx.cwd, cwd);
this.#writeAgentSettings(cwd, roleConfig, pathConstraints || {});
const pid = this.#processes.spawn(issueNumber, cwd, ctx.prompt, ctx.logPrefix, roleConfig);

// AFTER
const pathConstraints = remapPathConstraintsForRespawn(ctx.pathConstraints, ctx.cwd, cwd);
const scopedConfig = { ...roleConfig, allowedTools: buildScopedTools(roleConfig.allowedTools, pathConstraints || {}) };
const pid = this.#processes.spawn(issueNumber, cwd, ctx.prompt, ctx.logPrefix, scopedConfig);
```

- [ ] **Step 7: Commit**

```bash
cd gol-tools/foreman
git add foreman-daemon.mjs
git commit -m "refactor(foreman): wire buildScopedTools into all spawn methods

Replace #writeAgentSettings file writes with buildScopedTools pure
function calls. Each spawn method now builds a scopedConfig with
path-scoped allowedTools entries that flow directly to CLI args."
```

---

### Task 4: Wire `buildScopedTools` into TL spawn path

**Files:**
- Modify: `gol-tools/foreman/foreman-daemon.mjs:221-231` — TL settings block
- Modify: `gol-tools/foreman/foreman-daemon.mjs:243` — `requestDecision` call
- Modify: `gol-tools/foreman/lib/tl-dispatcher.mjs:40-50` — `requestDecision` signature
- Modify: `gol-tools/foreman/lib/tl-dispatcher.mjs:109-115` — apply scopedTools to roleConfig before spawn

TL is special: it's spawned via `tl-dispatcher.mjs` which builds its own `roleConfig` via `#resolveTLConfig()` and has a model-chain retry loop. The daemon knows the pathConstraints but tl-dispatcher does the spawning.

Strategy: daemon builds `scopedTools` and passes it to `requestDecision` via the options object. tl-dispatcher applies it to each retry iteration's roleConfig.

- [ ] **Step 1: Modify daemon TL block (lines 221-231)**

Replace `#writeAgentSettings` with `buildScopedTools`, pass result to `requestDecision`:

```js
// BEFORE (lines 221-231, 243)
const tlTask = this.#state.getTask(issueNumber);
const wsPath = tlTask?.workspace;
const tlRoleConfig = wsPath ? resolveRoleConfig(this.#config, 'tl') : null;
if (wsPath && tlRoleConfig) {
    const docDir = this.#docs.getDocDir(issueNumber);
    this.#writeAgentSettings(wsPath, tlRoleConfig, {
        readPaths: [this.#config.workDir],
        writePaths: [docDir],
    });
}
// ... later:
const decision = await this.#tlDispatcher.requestDecision(issueNumber, trigger, { systemAlerts });

// AFTER
const tlTask = this.#state.getTask(issueNumber);
const wsPath = tlTask?.workspace;
let tlScopedTools = null;
if (wsPath) {
    const tlRoleConfig = resolveRoleConfig(this.#config, 'tl');
    const docDir = this.#docs.getDocDir(issueNumber);
    tlScopedTools = buildScopedTools(tlRoleConfig.allowedTools, {
        readPaths: [this.#config.workDir],
        writePaths: [docDir],
    });
}
// ... later:
const decision = await this.#tlDispatcher.requestDecision(issueNumber, trigger, { systemAlerts, scopedTools: tlScopedTools });
```

- [ ] **Step 2: Modify tl-dispatcher `requestDecision` to accept and use `scopedTools`**

In `gol-tools/foreman/lib/tl-dispatcher.mjs`, update the method signature (~line 40) and spawn logic (~line 109-115):

```js
// In requestDecision(), destructure scopedTools from options:
async requestDecision(issueNumber, trigger, { systemAlerts, scopedTools } = {}) {

// In the spawn loop (line 109-115):
// BEFORE
const roleConfig = { ...baseConfig, model };
const pid = this.#processManager.spawn(issueNumber, cwd, prompt, logPrefix, roleConfig);

// AFTER
const roleConfig = { ...baseConfig, model };
if (scopedTools) {
    roleConfig.allowedTools = scopedTools;
}
const pid = this.#processManager.spawn(issueNumber, cwd, prompt, logPrefix, roleConfig);
```

- [ ] **Step 3: Commit**

```bash
cd gol-tools/foreman
git add foreman-daemon.mjs lib/tl-dispatcher.mjs
git commit -m "refactor(foreman): wire buildScopedTools into TL spawn path

TL is spawned via tl-dispatcher which has its own model-chain retry
loop. Pass pre-built scopedTools from daemon to tl-dispatcher via
requestDecision options, applied to each retry iteration's roleConfig."
```

---

### Task 5: Remove `#writeAgentSettings`, `#cleanAgentSettings`, and file cleanup code

**Files:**
- Modify: `gol-tools/foreman/foreman-daemon.mjs`
  - Delete `#writeAgentSettings` method (lines 370-417)
  - Delete `#cleanAgentSettings` method (lines 432-442)
  - Remove all `#cleanAgentSettings` calls (lines 139, 246, 252)
  - Remove `mkdirSync`, `writeFileSync`, `unlinkSync`, `existsSync` imports if no longer used elsewhere

- [ ] **Step 1: Remove the three `#cleanAgentSettings` call sites**

Line 139 (on process exit callback):
```js
// BEFORE
if (task.workspace) {
    this.#cleanAgentSettings(task.workspace);
}

// AFTER — delete these 3 lines entirely
```

Lines 246 and 252 (after TL decision success/failure):
```js
// BEFORE
if (wsPath) {
    this.#cleanAgentSettings(wsPath);
}

// AFTER — delete these blocks (both occurrences)
```

- [ ] **Step 2: Delete the method definitions**

Delete `#writeAgentSettings` (lines 370-417) and `#cleanAgentSettings` (lines 432-442) entirely.

- [ ] **Step 3: Clean up unused imports**

Check if `mkdirSync`, `writeFileSync`, `unlinkSync` are still used elsewhere in the file. If not, remove them from the `import { ... } from 'node:fs'` statement. `existsSync` is likely still used by other methods — verify before removing.

- [ ] **Step 4: Run all foreman tests**

Run: `cd gol-tools/foreman && node --test tests/**/*.test.mjs`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add foreman-daemon.mjs
git commit -m "refactor(foreman): remove settings.local.json file-based permissions

Delete #writeAgentSettings and #cleanAgentSettings methods and all
call sites. Permissions are now fully controlled via CLI --allowedTools
with path-scoped patterns. No files written or cleaned up."
```

---

### Task 6: Clean up `remapPathConstraintsForRespawn` — remove bashAllow remapping

**Files:**
- Modify: `gol-tools/foreman/lib/daemon-runtime-utils.mjs:20-36`
- Modify: `gol-tools/foreman/tests/daemon-runtime-utils.test.mjs`

The `remapPathConstraintsForRespawn` function is still needed (respawn rebuilds scopedTools from remapped pathConstraints). However, the `bashAllow` remapping at line 34 is a no-op — bash commands are absolute script paths (e.g. `/path/to/foreman/bin/coder-run-tests.sh`) that never match a workspace directory path via strict equality. Remove it for clarity.

- [ ] **Step 1: Update tests for bashAllow behavior**

In `tests/daemon-runtime-utils.test.mjs`, find the test for `remapPathConstraintsForRespawn` and add/update a case asserting that `bashAllow` is preserved unchanged (passed through, not remapped):

```js
it('preserves bashAllow unchanged', () => {
    const result = remapPathConstraintsForRespawn(
        {
            readPaths:  ['/old/ws'],
            writePaths: ['/old/ws'],
            bashAllow:  ['/tools/bin/run-tests.sh', '/tools/bin/run-tests.sh:*'],
        },
        '/old/ws',
        '/new/ws',
    );
    assert.deepStrictEqual(result.readPaths, ['/new/ws']);
    assert.deepStrictEqual(result.writePaths, ['/new/ws']);
    assert.deepStrictEqual(result.bashAllow, ['/tools/bin/run-tests.sh', '/tools/bin/run-tests.sh:*']);
});
```

- [ ] **Step 2: Run test to verify it passes (bashAllow paths don't match cwd, so remap is a no-op)**

Run: `cd gol-tools/foreman && node --test tests/daemon-runtime-utils.test.mjs`
Expected: PASS (existing logic already preserves bashAllow since paths don't match)

- [ ] **Step 3: Remove bashAllow from remap logic**

```js
// BEFORE (lines 29-35)
return {
    ...pathConstraints,
    readPaths:  remap(pathConstraints.readPaths),
    writePaths: remap(pathConstraints.writePaths),
    editPaths:  remap(pathConstraints.editPaths),
    bashAllow:  remap(pathConstraints.bashAllow),
};

// AFTER
return {
    ...pathConstraints,
    readPaths:  remap(pathConstraints.readPaths),
    writePaths: remap(pathConstraints.writePaths),
    editPaths:  remap(pathConstraints.editPaths),
    // bashAllow: absolute script paths, not workspace-relative — no remapping needed
};
```

- [ ] **Step 4: Run tests to verify they still pass**

Run: `cd gol-tools/foreman && node --test tests/daemon-runtime-utils.test.mjs`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/daemon-runtime-utils.mjs tests/daemon-runtime-utils.test.mjs
git commit -m "refactor(foreman): remove no-op bashAllow remapping from respawn

bashAllow entries are absolute script paths that never match workspace
directory paths via strict equality. Remove the remapping for clarity
and add a test documenting the preserved-unchanged behavior."
```

---

### Task 7: Update AGENTS.md permission documentation

**Files:**
- Modify: `gol-tools/AGENTS.md` — update the permission table to reflect the new architecture

- [ ] **Step 1: Update the permission table**

Find the agent role/permission table in `gol-tools/AGENTS.md` and replace it with the new architecture description:

```markdown
## Agent Permissions

All agents spawn with `--permission-mode default` and path-scoped `--allowedTools`.
In headless mode (`-p`), any tool NOT in the whitelist is auto-rejected.

| Role     | Read Scope              | Write Scope                             | Edit Scope                    | Bash Scope                           |
|----------|-------------------------|-----------------------------------------|-------------------------------|--------------------------------------|
| TL       | `workDir`               | `docDir`                                | —                             | —                                    |
| Planner  | `workspace`, `docDir`   | `docDir`                                | —                             | read-only git commands               |
| Coder    | `workspace`, `docDir`   | `scripts/`, `tests/`, `resources/`, `docDir` | `scripts/`, `tests/`, `resources/` | `coder-run-tests.sh`            |
| Reviewer | `workspace`, `docDir`   | `docDir`                                | —                             | read-only git commands               |
| Tester   | `workspace`, `docDir`, `/tmp` | `/tmp`, `docDir`                   | `/tmp`                        | tester scripts (start, debug, cleanup) |

Non-file tools (TodoWrite, Task, TaskOutput, WebFetch, WebSearch) are passed unscoped per role config.
```

- [ ] **Step 2: Commit**

```bash
cd gol-tools
git add AGENTS.md
git commit -m "docs: update AGENTS.md with pure-CLI permission architecture"
```

---

### Task 8: Integration verification

**Files:** No file changes — verification only.

- [ ] **Step 1: Run full test suite**

Run: `cd gol-tools/foreman && node --test tests/**/*.test.mjs`
Expected: All tests PASS

- [ ] **Step 2: Verify no stale references to settings.local.json**

```bash
cd gol-tools/foreman
grep -r 'settings.local.json\|settingsPath\|settingsDir\|\.codebuddy' --include='*.mjs' lib/ foreman-daemon.mjs
```

Expected: Zero matches in production code. Test files may reference it in comments — that's fine.

- [ ] **Step 3: Verify no stale references to bypassPermissions**

```bash
cd gol-tools/foreman
grep -r 'bypassPermissions' --include='*.mjs' lib/ foreman-daemon.mjs
```

Expected: Zero matches.

- [ ] **Step 4: Dry-run spawn arg inspection**

Add a temporary `console.log(args)` in `process-manager.mjs` `#spawnProcess` before the actual spawn call, then trigger a test issue to verify the CLI args look correct:

```
codebuddy -p --permission-mode default --model <model> --output-format stream-json
  --max-turns N <prompt>
  --allowedTools Read(/workspace/**) Read(/docs/**) Write(/scripts/**) Bash(/bin/run-tests.sh) TodoWrite Task ...
```

Verify path-scoped entries are present. Remove the temporary log after verification.
