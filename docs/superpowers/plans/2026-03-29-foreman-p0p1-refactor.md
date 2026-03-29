# Foreman P0+P1 Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 6 most critical reliability and safety issues in the Foreman daemon (P0: #6, #7; P1: #4, #5, #10, #15).

**Architecture:** Three modules executed sequentially — Module 1 (safety fixes, low risk) → Module 3 (rate limit unification + decision file split, medium risk) → Module 2 (state persistence + pending ops queue, high risk). Each module builds on the previous, and each task within a module is independently committable.

**Tech Stack:** Node.js 18+, ESM modules, `node:test` for testing, `gh` CLI for GitHub operations, git worktrees.

**Spec:** `docs/superpowers/specs/2026-03-29-foreman-p0p1-refactor-design.md`
**Scope:** `gol-tools/foreman/`

---

## Dependency Graph

```
Module 1 (Safety & Correctness)
  Task 1: CI gate reversal
  Task 2: Coder allowedTools + config-utils
  Task 3: AGENTS.md rule injection
  Task 4: Coder prompt cleanup
  Task 5: Committer framework step
  Task 6: PR creation helper + coder prompt cleanup

Module 3 (Rate Limit + Decision Split) — depends on Module 1
  Task 7: RateLimitDetector extraction
  Task 8: Wire RateLimitDetector into daemon + TL dispatcher
  Task 9: DocManager decision file split
  Task 10: Worker doc path migration (iterations/)
  Task 11: TL prompt template + PromptBuilder changes
  Task 12: TLDispatcher parsing from decision files
  Task 13: System alerts injection

Module 2 (State Reliability) — depends on Module 3
  Task 14: #save() throw on failure
  Task 15: State schema v4 + spawnContext/retryState persistence
  Task 16: Daemon restart recovery
  Task 17: PendingOps queue in StateManager
  Task 18: State-first terminal operations (verify/abandon/cancel)
  Task 19: PendingOps retry mechanism
```

---

## Module 1: Safety & Correctness (#6 CI Gate + #7 Permissions)

### Task 1: CI Gate Default Reversal

**Files:**
- Modify: `lib/github-sync.mjs:298-313` (`getPRChecks()` catch block)
- Modify: `foreman-daemon.mjs:617-669` (`#runCiGate()` / CI execution error handling)
- Test: `tests/github-sync.test.mjs`

- [ ] **Step 1: Write failing test for getPRChecks error path**

In `tests/github-sync.test.mjs`, add a test that verifies errors return `passed: false`:

```js
test('getPRChecks returns passed:false on gh CLI error', async (t) => {
    const gh = new GithubSync({
        repo: 'owner/repo',
        labels: { assign: 'a', progress: 'p', done: 'd', blocked: 'b', cancelled: 'c' },
    });
    // Force #gh to throw by using an invalid repo that gh CLI will reject
    // Or mock via subclass override
    const result = await gh.getPRChecks(99999);
    // With a non-existent PR, gh will throw
    assert.strictEqual(result.passed, false);
    assert.ok(result.failing.includes('check_unavailable'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd gol-tools/foreman && node --test tests/github-sync.test.mjs`
Expected: FAIL — currently returns `{ passed: true }` on error.

- [ ] **Step 3: Fix getPRChecks catch block**

In `lib/github-sync.mjs`, replace the catch block at line 309:

```js
// Before (line 309-311):
    } catch {
        // If gh pr checks fails (e.g., no checks configured), assume passed
        return { passed: true, failing: [], pending: false };
    }

// After:
    } catch (err) {
        warn('github-sync', `getPRChecks(#${prNumber}) failed: ${err.message}`);
        return { passed: false, failing: ['check_unavailable'], pending: false };
    }
```

Add `warn` import if not present — `github-sync.mjs` already uses a logger pattern via `this.#log?.()` or direct import. Check the file's logging mechanism and use the same pattern.

- [ ] **Step 3b: Return execution_error from daemon-side CI execution failures**

In `foreman-daemon.mjs`, update the CI execution error path so command execution failures are surfaced instead of swallowed:

```js
// In #runCiGate() / the execSync error handling path:
} catch (err) {
    warn(COMPONENT, `#${issue_number}: CI command execution failed: ${err.message}`);
    return {
        passed: false,
        output: err.message,
        summary: 'execution_error',
    };
}
```

Keep ordinary test failures as `passed: false` with parsed output summary. This new branch is specifically for command execution errors (missing binary, bad command, spawn failure, etc.).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd gol-tools/foreman && node --test tests/github-sync.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/github-sync.mjs foreman-daemon.mjs tests/github-sync.test.mjs
git commit -m "fix(foreman): CI gate returns passed:false on error instead of true (#6)"
```

---

### Task 2: Coder allowedTools Whitelist + Config Utils

**Files:**
- Modify: `config/default.json:48-51` (coder role config)
- Modify: `lib/config-utils.mjs:109-122` (`resolveRoleConfig()`)
- Modify: `lib/process-manager.mjs:143-148` (spawn CLI arg construction)
- Test: `tests/config-migration.test.mjs`

- [ ] **Step 1: Write failing test for resolveRoleConfig with allowedTools**

In `tests/config-migration.test.mjs`, add:

```js
test('resolveRoleConfig returns allowedTools when present', (t) => {
    const config = {
        defaults: { client: 'codebuddy', model: 'test', maxTurns: 100, disallowedTools: ['AskUserQuestion'] },
        roles: {
            coder: {
                model: 'kimi',
                allowedTools: ['Read', 'Write', 'Edit', 'Bash', 'Grep', 'Glob', 'LS'],
            },
        },
    };
    const result = resolveRoleConfig(config, 'coder');
    assert.deepStrictEqual(result.allowedTools, ['Read', 'Write', 'Edit', 'Bash', 'Grep', 'Glob', 'LS']);
    assert.deepStrictEqual(result.disallowedTools, []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd gol-tools/foreman && node --test tests/config-migration.test.mjs`
Expected: FAIL — `allowedTools` not returned by current `resolveRoleConfig()`.

- [ ] **Step 3: Update resolveRoleConfig to support allowedTools**

In `lib/config-utils.mjs`, replace `resolveRoleConfig()` (lines 109–122):

```js
export function resolveRoleConfig(config, role) {
    const defaults = config.defaults || {};
    const roleOverride = config.roles?.[role] || {};

    const merged = {
        client: roleOverride.client || defaults.client,
        model: roleOverride.model || defaults.model,
        maxTurns: roleOverride.maxTurns ?? defaults.maxTurns,
    };

    // allowedTools takes precedence — if set, disallowedTools is ignored
    if (roleOverride.allowedTools) {
        merged.allowedTools = roleOverride.allowedTools;
        merged.disallowedTools = [];
    } else {
        merged.allowedTools = null;
        merged.disallowedTools = roleOverride.disallowedTools || defaults.disallowedTools || [];
    }

    return merged;
}
```

- [ ] **Step 4: Update process-manager spawn to support allowedTools**

In `lib/process-manager.mjs`, find the CLI arg construction (around lines 143–148) where `--disallowedTools` is appended. Add `--allowedTools` support:

```js
// After the existing disallowedTools block:
if (roleConfig.disallowedTools?.length) {
    args.push('--disallowedTools', ...roleConfig.disallowedTools);
}

// Add:
if (roleConfig.allowedTools?.length) {
    args.push('--allowedTools', ...roleConfig.allowedTools);
}
```

Note: `--allowedTools` and `--disallowedTools` are mutually exclusive per the config design. The `resolveRoleConfig` function ensures only one is populated.

- [ ] **Step 5: Update config/default.json coder role**

Replace the coder role entry in `config/default.json`:

```json
"coder": {
    "model": "kimi-k2.5-ioa",
    "fallbackModels": ["minimax-m2.7-ioa"],
    "allowedTools": [
        "Read", "Write", "Edit", "Grep", "Glob", "LS",
        "Bash", "Agent", "WebFetch", "WebSearch",
        "TodoWrite", "NotebookEdit"
    ]
}
```

This removes the implicit inheritance of `defaults.disallowedTools` and replaces it with an explicit whitelist.

- [ ] **Step 6: Run tests to verify**

Run: `cd gol-tools/foreman && node --test tests/config-migration.test.mjs`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
cd gol-tools/foreman
git add lib/config-utils.mjs lib/process-manager.mjs config/default.json tests/config-migration.test.mjs
git commit -m "feat(foreman): coder allowedTools whitelist replaces disallowedTools (#7)"
```

---

### Task 3: AGENTS.md Rule Injection in Workspace Manager

**Files:**
- Modify: `lib/workspace-manager.mjs:103-112` (post-create AGENTS.md handling)

- [ ] **Step 1: Add Foreman rules append to workspace create()**

In `lib/workspace-manager.mjs`, after the existing AGENTS.md copy logic (around line 112), append Foreman-specific rules:

```js
// After existing AGENTS.md copy/symlink block (line ~112):
const foremanRules = `

## Foreman Rules
- Do NOT use \`git\` commands — commits are handled by the framework
- Do NOT use \`gh\` commands — GitHub operations are handled by the framework
- Focus on writing code, tests, and documentation only
`;

const agentsMdPath = join(wsPath, 'AGENTS.md');
if (existsSync(agentsMdPath)) {
    appendFileSync(agentsMdPath, foremanRules, 'utf-8');
}
```

Add `appendFileSync` to the `node:fs` import at the top of the file.

- [ ] **Step 2: Verify manually**

Run: `cd gol-tools/foreman && node -e "import('./lib/workspace-manager.mjs')"`
Expected: No import errors.

- [ ] **Step 3: Commit**

```bash
cd gol-tools/foreman
git add lib/workspace-manager.mjs
git commit -m "feat(foreman): inject Foreman rules into worktree AGENTS.md (#7)"
```

---

### Task 4: Coder Prompt Cleanup

**Files:**
- Modify: `prompts/coder-task.md`

- [ ] **Step 1: Update coder prompt to remove git/GitHub instructions**

In `prompts/coder-task.md`:

1. Remove any instructions about creating PRs (`gh pr create`), committing (`git commit`), or pushing (`git push`).
2. Remove references to `{{BRANCH}}` in the context of PR creation (keep it if used for other context).
3. Add explicit framework delegation note:

```markdown
## Framework-Managed Operations
The following operations are handled automatically by the Foreman framework — do NOT perform them:
- `git add`, `git commit`, `git push` — the framework commits and pushes after you finish
- `gh pr create` — PR is created by the framework after verification
- Any `gh` commands — all GitHub operations are framework-managed

Your job is to write code and tests. When done, write your handoff document and exit.
```

4. Keep the existing prohibition on `rm`/`trash`/file deletion, `gh issue close`, etc.

- [ ] **Step 2: Commit**

```bash
cd gol-tools/foreman
git add prompts/coder-task.md
git commit -m "feat(foreman): remove git/GitHub from coder prompt, delegate to framework (#7)"
```

---

### Task 5: Committer Framework Step

**Files:**
- Modify: `foreman-daemon.mjs:105-180` (`#onProcessExit()` flow)

- [ ] **Step 1: Add #runCommitStep() method to ForemanDaemon**

In `foreman-daemon.mjs`, add a new private method after `#runCiGate()` (around line 637):

```js
#runCommitStep(task) {
    const { issue_number, workspace } = task;
    if (!workspace) {
        warn(COMPONENT, `#${issue_number}: no workspace for commit step, skipping`);
        return { success: true, skipped: true };
    }

    try {
        // Stage all changes
        execSync('git add -A', { cwd: workspace, timeout: 30000 });

        // Check if there's anything to commit
        try {
            execSync('git diff --cached --quiet', { cwd: workspace, timeout: 30000 });
            info(COMPONENT, `#${issue_number}: no changes to commit, skipping`);
            return { success: true, skipped: true };
        } catch {
            // Non-zero exit means there ARE staged changes — proceed
        }

        const iteration = (task.worker_spawn_counts?.coder || 1);
        const msg = `feat(#${issue_number}): ${task.issue_title} — iteration ${iteration}`;
        execSync(`git commit -m ${JSON.stringify(msg)}`, {
            cwd: workspace, encoding: 'utf-8', timeout: 30000,
        });

        const branch = task.branch;
        if (branch) {
            execSync(`git push origin ${branch}`, {
                cwd: workspace, encoding: 'utf-8', timeout: 60000,
            });
            info(COMPONENT, `#${issue_number}: committed and pushed to ${branch}`);
        }

        return { success: true, skipped: false };
    } catch (err) {
        warn(COMPONENT, `#${issue_number}: commit step failed: ${err.message}`);
        return { success: false, error: err.message };
    }
}
```

- [ ] **Step 2: Wire #runCommitStep into #onProcessExit**

In `#onProcessExit()`, after the doc validation block and before the CI gate block (around line 167), insert the commit step for coder:

```js
// After doc validation, before CI gate (around line 165):
if (agentRole === 'coder') {
    const commitResult = this.#runCommitStep(task);
    if (!commitResult.success) {
        trigger.commitFailed = true;
        trigger.commitError = commitResult.error;
    }
}
```

The existing `#runCiGate()` call remains unchanged — it runs after commit so CI tests the committed code.

- [ ] **Step 3: Verify no import errors**

Run: `cd gol-tools/foreman && node -e "import('./foreman-daemon.mjs')"`
Expected: No errors (may warn about missing config, that's fine).

- [ ] **Step 4: Commit**

```bash
cd gol-tools/foreman
git add foreman-daemon.mjs
git commit -m "feat(foreman): add committer framework step after coder exits (#7)"
```

---

### Task 6: PR Creation Helper + Coder Prompt Cleanup

**Files:**
- Modify: `lib/github-sync.mjs` (`createPR()` and `findOpenPR()`)
- Modify: `prompts/coder-task.md` (remove PR creation instructions)

- [ ] **Step 1: Add GitHub helpers for framework-managed PR creation**

In `lib/github-sync.mjs`, add a `createPR()` helper and an idempotency helper for branch lookup:

```js
async createPR(issueNumber, branch, title) {
    const result = await this.#gh([
        'pr', 'create',
        '--title', `${title} (#${issueNumber})`,
        '--body', `Refs #${issueNumber}\n\n_Created by Foreman_`,
        '--base', 'main',
        '--head', branch,
        '--json', 'number,url',
    ]);
    return result;
}

async findOpenPR(branch) {
    const prs = await this.#gh([
        'pr', 'list',
        '--state', 'open',
        '--head', branch,
        '--json', 'number,headRefName',
    ]);
    return prs.find(pr => pr.headRefName === branch) || null;
}
```

- [ ] **Step 2: Remove PR creation from coder prompt**

In `prompts/coder-task.md`, remove the instructions that tell the coder to create a PR directly. Keep branch-oriented context only. The prompt should explicitly say that git commit/push and PR creation are handled by the framework, not by the agent.

Do **not** rewrite `#handleVerify()` in this task — the canonical state-first verify flow belongs in Task 18.

- [ ] **Step 3: Verify no import errors**

Run: `cd gol-tools/foreman && node -e "import('./foreman-daemon.mjs')"`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
cd gol-tools/foreman
git add lib/github-sync.mjs prompts/coder-task.md
git commit -m "refactor(foreman): add PR creation helpers and remove PR creation from coder prompt (#7)"
```

---

## Module 3: Rate Limit Unification + Decision File Split (#10 + #15)

### Task 7: RateLimitDetector Extraction

**Files:**
- Create: `lib/rate-limit-detector.mjs`
- Create: `tests/rate-limit-detector.test.mjs`

- [ ] **Step 1: Write failing tests for RateLimitDetector**

Create `tests/rate-limit-detector.test.mjs`:

```js
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { RateLimitDetector } from '../lib/rate-limit-detector.mjs';

describe('RateLimitDetector', () => {
    test('detects codebuddy 429 rate limit', () => {
        const log = 'some output\n429 usage exceeds frequency limit\nmore output';
        const result = RateLimitDetector.detect(log, 'codebuddy');
        assert.strictEqual(result.limited, true);
        assert.ok(result.matchCount >= 1);
    });

    test('detects claude overloaded pattern', () => {
        const log = 'request failed: overloaded\nretrying...\noverloaded again';
        const result = RateLimitDetector.detect(log, 'claude');
        assert.strictEqual(result.limited, true);
        assert.strictEqual(result.matchCount, 2);
    });

    test('returns limited:false when no patterns match', () => {
        const log = 'normal output\nall good\ntests passed';
        const result = RateLimitDetector.detect(log, 'codebuddy');
        assert.strictEqual(result.limited, false);
        assert.strictEqual(result.matchCount, 0);
    });

    test('returns limited:false for unknown client', () => {
        const log = '429 rate limit exceeded';
        const result = RateLimitDetector.detect(log, 'unknown-client');
        assert.strictEqual(result.limited, false);
        assert.strictEqual(result.matchCount, 0);
    });

    test('counts multiple matches across patterns', () => {
        const log = '429 error\nrate limit hit\n429 again\nToo Many Requests';
        const result = RateLimitDetector.detect(log, 'claude');
        assert.ok(result.matchCount >= 3);
    });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd gol-tools/foreman && node --test tests/rate-limit-detector.test.mjs`
Expected: FAIL — module doesn't exist yet.

- [ ] **Step 3: Implement RateLimitDetector**

Create `lib/rate-limit-detector.mjs`:

```js
/**
 * Centralized rate-limit detection for all Foreman process types.
 * Consolidates patterns from process-manager.mjs PROVIDER_SPECS,
 * foreman-daemon.mjs #detectRateLimit, and tl-dispatcher.mjs #isRateLimited.
 */
export class RateLimitDetector {
    static PATTERNS = {
        codebuddy: [
            /429/,
            /Too Many Requests/i,
            /429 usage exceeds frequency limit/,
            /rate.?limit/i,
        ],
        claude: [
            /429/,
            /Too Many Requests/i,
            /rate.?limit/i,
            /overloaded/i,
        ],
        'claude-internal': [
            /429/,
            /Too Many Requests/i,
            /rate.?limit/i,
            /overloaded/i,
        ],
    };

    /**
     * Detect rate limiting in log content.
     * @param {string} logContent - Log text to scan (typically last 4096 bytes)
     * @param {string} clientName - Client name (key into PATTERNS)
     * @returns {{ limited: boolean, matchCount: number, matchedPatterns: string[] }}
     */
    static detect(logContent, clientName) {
        const patterns = this.PATTERNS[clientName];
        if (!patterns) {
            return { limited: false, matchCount: 0, matchedPatterns: [] };
        }

        let totalMatches = 0;
        const matchedPatterns = [];

        for (const pattern of patterns) {
            const flags = 'g' + (pattern.flags.includes('i') ? 'i' : '');
            const re = new RegExp(pattern.source, flags);
            const matches = logContent.match(re);
            if (matches) {
                totalMatches += matches.length;
                matchedPatterns.push(pattern.source);
            }
        }

        return { limited: totalMatches > 0, matchCount: totalMatches, matchedPatterns };
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/foreman && node --test tests/rate-limit-detector.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/rate-limit-detector.mjs tests/rate-limit-detector.test.mjs
git commit -m "feat(foreman): extract RateLimitDetector with unified patterns (#10)"
```

---

### Task 8: Wire RateLimitDetector into Daemon + TL Dispatcher

**Files:**
- Modify: `foreman-daemon.mjs` (replace `#detectRateLimit()`, update `#runProcessCheck()`)
- Modify: `lib/tl-dispatcher.mjs` (replace `#isRateLimited()`)
- Modify: `lib/process-manager.mjs` (remove `rateLimitPatterns` from `PROVIDER_SPECS`)
- Test: `tests/rate-limit.test.mjs`

- [ ] **Step 1: Replace daemon's #detectRateLimit with RateLimitDetector**

In `foreman-daemon.mjs`:

1. Add import at top:
```js
import { RateLimitDetector } from './lib/rate-limit-detector.mjs';
```

2. Replace `#detectRateLimit()` method (lines 864–888) with:
```js
#detectRateLimit(logFile, clientName) {
    const tailBytes = 4096;
    const stat = statSync(logFile);
    if (stat.size === 0) return false;

    const fd = openSync(logFile, 'r');
    const start = Math.max(0, stat.size - tailBytes);
    const buf = Buffer.alloc(Math.min(tailBytes, stat.size));
    readSync(fd, buf, 0, buf.length, start);
    closeSync(fd);

    const tail = buf.toString('utf-8');
    const result = RateLimitDetector.detect(tail, clientName);
    return result.matchCount >= 3;  // daemon threshold: 3+ matches
}
```

The file reading logic stays the same, but pattern matching delegates to `RateLimitDetector`. Threshold remains 3 for daemon.

- [ ] **Step 2: Replace TL dispatcher's #isRateLimited with RateLimitDetector**

In `lib/tl-dispatcher.mjs`:

1. Add import:
```js
import { RateLimitDetector } from './rate-limit-detector.mjs';
```

2. Replace `#isRateLimited()` method (lines 198–222) with:
```js
#isRateLimited(logFile, clientName) {
    const tailBytes = 4096;
    const stat = statSync(logFile);
    if (stat.size === 0) return false;

    const fd = openSync(logFile, 'r');
    const start = Math.max(0, stat.size - tailBytes);
    const buf = Buffer.alloc(Math.min(tailBytes, stat.size));
    readSync(fd, buf, 0, buf.length, start);
    closeSync(fd);

    const tail = buf.toString('utf-8');
    const result = RateLimitDetector.detect(tail, clientName);
    return result.matchCount >= 1;  // TL threshold: 1+ match (more sensitive)
}
```

- [ ] **Step 3: Remove rateLimitPatterns from PROVIDER_SPECS**

In `lib/process-manager.mjs`, remove the `rateLimitPatterns` field from each entry in `PROVIDER_SPECS` (lines 31–69). The patterns are now solely owned by `RateLimitDetector`.

After removal, each spec entry should look like:
```js
'codebuddy': {
    binary: 'codebuddy',
    permissionFlag: '-y',
    extraArgs: [],
    stripEnvKeys: ['CODEBUDDY_API_KEY'],
    extraEnv: { CODEBUDDY_API_KEY_DISABLED: '1' },
},
```

Also remove the `PROVIDER_SPECS` export from the daemon's import line if it was only used for rate limit patterns.

- [ ] **Step 4: Run all tests**

Run: `cd gol-tools/foreman && node --test tests/`
Expected: All PASS. If `rate-limit.test.mjs` or other tests reference `PROVIDER_SPECS.rateLimitPatterns`, update them.

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add foreman-daemon.mjs lib/tl-dispatcher.mjs lib/process-manager.mjs
git commit -m "refactor(foreman): wire RateLimitDetector, remove duplicate patterns (#10)"
```

---

### Task 9: DocManager Decision File Split

**Files:**
- Modify: `lib/doc-manager.mjs`
- Test: `tests/doc-manager.test.mjs`

- [ ] **Step 1: Write failing tests for new DocManager methods**

In `tests/doc-manager.test.mjs`, add:

```js
describe('decision file management', () => {
    test('writeDecisionFromDaemon creates decision file and updates index', (t) => {
        const dm = new DocManager(tmpDir);
        dm.initOrchestration(100, 'Test Issue', ['bug'], 'Body text');

        dm.writeDecisionFromDaemon(100, 1, {
            trigger: 'new_issue',
            assessment: 'Initial analysis needed',
            action: 'spawn @planner',
            model: 'test-model',
            guidance: 'Analyze the issue',
            tlContext: 'Some context here',
        });

        // Decision file exists
        const decisionPath = join(tmpDir, '100', 'decisions', '001-planning.md');
        assert.ok(existsSync(decisionPath));

        // Orchestration index updated
        const orch = readFileSync(join(tmpDir, '100', 'orchestration.md'), 'utf-8');
        assert.ok(orch.includes('| 1 | spawn @planner |'));
    });

    test('readLatestDecision returns most recent decision', (t) => {
        const dm = new DocManager(tmpDir);
        dm.initOrchestration(101, 'Test', [], '');
        dm.writeDecisionFromDaemon(101, 1, { action: 'spawn @planner', assessment: 'first' });
        dm.writeDecisionFromDaemon(101, 2, { action: 'spawn @coder', assessment: 'second' });

        const latest = dm.readLatestDecision(101);
        assert.ok(latest.includes('spawn @coder'));
    });

    test('readDecision returns specific decision by number', (t) => {
        const dm = new DocManager(tmpDir);
        dm.initOrchestration(102, 'Test', [], '');
        dm.writeDecisionFromDaemon(102, 1, { action: 'spawn @planner', assessment: 'first' });

        const dec = dm.readDecision(102, 1);
        assert.ok(dec.includes('spawn @planner'));
    });

    test('getDecisionCount returns number of decision files', (t) => {
        const dm = new DocManager(tmpDir);
        dm.initOrchestration(103, 'Test', [], '');
        assert.strictEqual(dm.getDecisionCount(103), 0);

        dm.writeDecisionFromDaemon(103, 1, { action: 'spawn @planner', assessment: 'first' });
        assert.strictEqual(dm.getDecisionCount(103), 1);
    });

    test('isLegacyFormat returns true when decisions directory is missing', (t) => {
        const dm = new DocManager(tmpDir);
        dm.initOrchestration(104, 'Legacy', [], '');
        assert.strictEqual(dm.isLegacyFormat(104), true);
    });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd gol-tools/foreman && node --test tests/doc-manager.test.mjs`
Expected: FAIL — methods don't exist yet.

- [ ] **Step 3: Implement decision file methods in DocManager**

In `lib/doc-manager.mjs`, add these methods:

```js
/** Map action to slug for decision filenames */
#actionToSlug(action) {
    const map = {
        'spawn @planner': 'planning',
        'spawn @coder': 'building',
        'spawn @reviewer': 'reviewing',
        'spawn @tester': 'testing',
        'verify': 'verify',
        'abandon': 'abandon',
    };
    return map[action] || 'unknown';
}

/** Get the decisions directory path for an issue */
getDecisionsDir(issueNumber) {
    return join(this.getDocDir(issueNumber), 'decisions');
}

/** True when this issue still uses legacy orchestration-only format. */
isLegacyFormat(issueNumber) {
    return !existsSync(this.getDecisionsDir(issueNumber));
}

/** Path where the TL should write its next standalone decision file. */
getNextDecisionPath(issueNumber) {
    const nextNumber = this.getDecisionCount(issueNumber) + 1;
    const pad = String(nextNumber).padStart(3, '0');
    return join(this.getDecisionsDir(issueNumber), `${pad}-decision.md`);
}

/**
 * Write a daemon-initiated decision to its own file and update the orchestration index.
 * Used only when the daemon itself authors the decision file.
 * TL-authored decisions should use getNextDecisionPath() + appendDecisionIndex().
 * @param {number} issueNumber
 * @param {number} decisionNumber - 1-based
 * @param {object} decision - { trigger, assessment, action, model, guidance, tlContext, githubComment }
 */
writeDecisionFromDaemon(issueNumber, decisionNumber, decision) {
    const dir = this.getDecisionsDir(issueNumber);
    mkdirSync(dir, { recursive: true });

    const slug = this.#actionToSlug(decision.action);
    const pad = String(decisionNumber).padStart(3, '0');
    const filename = `${pad}-${slug}.md`;
    const filePath = join(dir, filename);

    const now = new Date().toISOString().replace('T', ' ').slice(0, 16);
    let content = `# Decision ${decisionNumber} — ${now}\n\n`;
    if (decision.trigger)    content += `**Trigger:** ${decision.trigger}\n`;
    if (decision.assessment) content += `**Assessment:** ${decision.assessment}\n`;
    content += `**Action:** ${decision.action}\n`;
    if (decision.model)      content += `**Model:** ${decision.model}\n`;
    if (decision.guidance)   content += `**Guidance:** ${decision.guidance}\n`;
    if (decision.tlContext) {
        const role = decision.action.replace('spawn @', '');
        content += `**TL Context for ${role}:**\n> ${decision.tlContext.replace(/\n/g, '\n> ')}\n`;
    }
    if (decision.githubComment) {
        content += `\n**GitHub Comment:**\n${decision.githubComment}\n`;
    }

    writeFileSync(filePath, content, 'utf-8');

    this.appendDecisionIndex(issueNumber, decisionNumber, decision);
}

appendDecisionIndex(issueNumber, decisionNumber, decision) {
    const safeSummary = (decision.assessment || decision.action)
        .slice(0, 80)
        .replace(/\|/g, '\\|')
        .replace(/\n/g, ' ');
    const indexLine = `| ${decisionNumber} | ${decision.action} | ${safeSummary} |\n`;
    appendFileSync(this.getOrchestrationPath(issueNumber), indexLine, 'utf-8');
}

/** Read a specific decision file */
readDecision(issueNumber, decisionNumber) {
    const dir = this.getDecisionsDir(issueNumber);
    const pad = String(decisionNumber).padStart(3, '0');
    const files = existsSync(dir) ? readdirSync(dir).filter(f => f.startsWith(pad)) : [];
    if (files.length === 0) return null;
    return readFileSync(join(dir, files[0]), 'utf-8');
}

/** Read the latest (highest-numbered) decision file */
readLatestDecision(issueNumber) {
    const dir = this.getDecisionsDir(issueNumber);
    if (!existsSync(dir)) return null;
    const files = readdirSync(dir).filter(f => /^\d{3}-/.test(f)).sort();
    if (files.length === 0) return null;
    return readFileSync(join(dir, files[files.length - 1]), 'utf-8');
}

/** Count decision files for an issue */
getDecisionCount(issueNumber) {
    const dir = this.getDecisionsDir(issueNumber);
    if (!existsSync(dir)) return 0;
    return readdirSync(dir).filter(f => /^\d{3}-/.test(f)).length;
}
```

Add required imports (`appendFileSync`, `readdirSync`, `mkdirSync`) to the top of the file if not already imported.

Add a note in the method comments that legacy tasks are **not migrated** to the new structure; if an issue has no `decisions/` directory, it stays on the old `orchestration.md` parsing path until completion.

Also update `initOrchestration()` to include the table header:

```js
// In initOrchestration(), change the Decision Log section to:
const content = `# Orchestration — Issue #${issueNumber}\n\n## Issue\n**Title:** ${issueTitle}\n**Labels:** ${labels}\n**Body:**\n${body}\n\n---\n\n## Decision Log\n| # | Action | Summary |\n|---|--------|--------|\n`;
```

- [ ] **Step 4: Run tests**

Run: `cd gol-tools/foreman && node --test tests/doc-manager.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/doc-manager.mjs tests/doc-manager.test.mjs
git commit -m "feat(foreman): DocManager decision file split with index (#15)"
```

---

### Task 10: Worker Doc Path Migration (iterations/)

**Files:**
- Modify: `lib/doc-manager.mjs` (worker doc paths)
- Modify: `lib/prompt-builder.mjs`
- Modify: `prompts/coder-task.md`, `prompts/planner-task.md`, `prompts/reviewer-task.md`, `prompts/tester-task.md`

- [ ] **Step 1: Update DocManager to use iterations/ subdirectory**

In `lib/doc-manager.mjs`, modify `nextSeq()`, `listDocs()`, `readLatestDoc()`, and any other method that operates on worker documents to use an `iterations/` subdirectory:

```js
/** Get the iterations directory for worker output docs */
getIterationsDir(issueNumber) {
    return join(this.getDocDir(issueNumber), 'iterations');
}

// In nextSeq(), change directory scan to use iterations/:
nextSeq(issueNumber) {
    const dir = this.getIterationsDir(issueNumber);
    mkdirSync(dir, { recursive: true });
    // ... rest of logic scanning dir instead of getDocDir()
}

// In listDocs(), scan iterations/ instead of root:
listDocs(issueNumber) {
    const dir = this.getIterationsDir(issueNumber);
    if (!existsSync(dir)) return [];
    return readdirSync(dir)
        .filter(f => f.endsWith('.md'))
        .sort();
}
```

Update the doc path that prompts receive via `{{DOC_DIR}}` — this should now point to `iterations/`.

- [ ] **Step 2: Update prompt templates**

In each prompt template (`planner-task.md`, `coder-task.md`, `reviewer-task.md`, `tester-task.md`), ensure `{{DOC_DIR}}` references are understood to be the `iterations/` subdirectory. The `PromptBuilder` will pass the correct path.

- [ ] **Step 3: Update PromptBuilder doc_dir substitution**

In `lib/prompt-builder.mjs`, where `{{DOC_DIR}}` is substituted, ensure it uses `docManager.getIterationsDir(issueNumber)` instead of `docManager.getDocDir(issueNumber)`.

- [ ] **Step 4: Run existing doc-manager tests to check for regressions**

Run: `cd gol-tools/foreman && node --test tests/doc-manager.test.mjs`
Expected: PASS (update any tests that assume root-level doc placement).

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/doc-manager.mjs lib/prompt-builder.mjs prompts/
git commit -m "refactor(foreman): worker docs moved to iterations/ subdirectory (#15)"
```

---

### Task 11: TL Prompt Template + PromptBuilder Changes

**Files:**
- Modify: `prompts/tl-decision.md`
- Modify: `lib/prompt-builder.mjs:13-25` (`buildTLPrompt()`)

- [ ] **Step 1: Update TL prompt template with new placeholders**

In `prompts/tl-decision.md`:

1. Replace `{{ORCHESTRATION_PATH}}` usage — TL no longer appends to orchestration.md. Instead, provide `{{DECISION_PATH}}`:

```markdown
## Your Output

Write your decision to the file at: `{{DECISION_PATH}}`

Use this exact format:
```

2. Add `{{LATEST_DECISION}}` section after orchestration content:

```markdown
## Latest Decision
{{LATEST_DECISION}}
```

3. Add `{{SYSTEM_ALERTS}}` section near the top:

```markdown
## System Alerts
{{SYSTEM_ALERTS}}
```

4. Remove any instruction about appending to orchestration.md. The TL now writes a standalone decision file.

- [ ] **Step 2: Update PromptBuilder.buildTLPrompt()**

In `lib/prompt-builder.mjs`, modify `buildTLPrompt()`:

```js
buildTLPrompt({ issueNumber, issueContext, trigger, orchestrationContent,
                docListing, latestDocContent, latestDecision,
                decisionPath, availableModels, systemAlerts }) {
    const template = this.#readTemplate('tl-decision.md');
    return template
        .replace('{{AVAILABLE_MODELS}}', availableModels || '')
        .replace('{{ISSUE_CONTEXT}}', issueContext || '')
        .replace('{{TRIGGER_EVENT}}', JSON.stringify(trigger) || '')
        .replace('{{ORCHESTRATION_CONTENT}}', orchestrationContent || '')
        .replace('{{DOC_LISTING}}', docListing || '')
        .replace('{{LATEST_DOC_CONTENT}}', latestDocContent || '')
        .replace('{{LATEST_DECISION}}', latestDecision || 'No previous decisions')
        .replace('{{DECISION_PATH}}', decisionPath || '')
        .replace('{{SYSTEM_ALERTS}}', systemAlerts || 'None');
}
```

- [ ] **Step 3: Commit**

```bash
cd gol-tools/foreman
git add prompts/tl-decision.md lib/prompt-builder.mjs
git commit -m "feat(foreman): TL prompt uses decision files + system alerts (#15)"
```

---

### Task 12: TLDispatcher Parsing from Decision Files

**Files:**
- Modify: `lib/tl-dispatcher.mjs`
- Modify: `foreman-daemon.mjs` (constructor wiring remains aligned)
- Test: `tests/tl-dispatcher.test.mjs`

- [ ] **Step 1: Write failing test for decision file parsing**

In `tests/tl-dispatcher.test.mjs`, add:

```js
test('parseDecisionFile reads from decision file', async (t) => {
    // Set up a decision file in the tmp dir
    const issueDir = join(tmpDir, 'docs/foreman/100/decisions');
    mkdirSync(issueDir, { recursive: true });
    writeFileSync(join(issueDir, '001-planning.md'), `# Decision 1 — 2026-03-29 14:00

**Trigger:** new_issue
**Assessment:** Needs planner analysis
**Action:** spawn @planner
**Model:** test-model
**Guidance:** Analyze requirements
**TL Context for planner:**
> Check the issue requirements
`);

    const decision = dispatcher.parseDecisionFile(
        readFileSync(join(issueDir, '001-planning.md'), 'utf-8')
    );
    assert.strictEqual(decision.action, 'spawn @planner');
    assert.strictEqual(decision.model, 'test-model');
    assert.ok(decision.tlContext.includes('Check the issue requirements'));
});

test('parseDecisionFile returns null for invalid action', async (t) => {
    const result = dispatcher.parseDecisionFile('**Action:** launch rockets');
    assert.strictEqual(result, null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd gol-tools/foreman && node --test tests/tl-dispatcher.test.mjs`
Expected: FAIL — `parseDecisionFile()` doesn't exist.

- [ ] **Step 3: Refactor TLDispatcher parsing**

In `lib/tl-dispatcher.mjs`:

1. Keep the existing orchestration parser as `parseLegacyDecision()` for legacy issues, and extract a new `parseDecisionFile(content)` method for standalone decision files:

```js
/**
 * Parse a single decision file's content.
 * @param {string} content - Raw markdown content of a decision file
 * @returns {{ action, model, tlContext, assessment, guidance, githubComment } | null}
 */
parseDecisionFile(content) {
    if (!content) return null;

    const actionMatch = content.match(/\*\*Action:\*\*\s*(.+)/);
    const action = actionMatch?.[1]?.trim();
    if (!action || !VALID_ACTIONS.has(action)) {
        return null;
    }

    const modelMatch = content.match(/\*\*Model:\*\*\s*(.+)/);
    const contextMatch = content.match(/\*\*TL Context for \w+:\*\*\s*\n([\s\S]*?)(?=\*\*|\n#|$)/);
    const assessmentMatch = content.match(/\*\*Assessment:\*\*\s*(.+)/);
    const guidanceMatch = content.match(/\*\*Guidance:\*\*\s*(.+)/);
    const commentMatch = content.match(/\*\*GitHub Comment:\*\*\s*\n([\s\S]*?)(?=\*\*|\n#|$)/);

    return {
        action,
        model: modelMatch?.[1]?.trim() || null,
        tlContext: contextMatch?.[1]?.trim() || '',
        assessment: assessmentMatch?.[1]?.trim() || '',
        guidance: guidanceMatch?.[1]?.trim() || '',
        githubComment: commentMatch?.[1]?.trim() || '',
    };
}
```

2. Update `requestDecision()` to support both legacy and split-file formats:

Before using the new decision-file flow, check `this.#docManager.isLegacyFormat(issueNumber)`. If it returns `true`, skip `{{DECISION_PATH}}`, fall back to the old `orchestration.md` behavior, and parse with `parseLegacyDecision()`. Legacy tasks are **not** migrated mid-flight.

For non-legacy issues, use Approach B only: TL writes the file at `{{DECISION_PATH}}`, daemon reads it back, parses it, and appends the index row.

```js
// In requestDecision():
if (this.#docManager.isLegacyFormat(issueNumber)) {
    const updatedOrchestration = this.#docManager.readOrchestration(issueNumber);
    return this.parseLegacyDecision(updatedOrchestration);
}

const decisionNum = this.#docManager.getDecisionCount(issueNumber) + 1;
const decisionPath = this.#docManager.getNextDecisionPath(issueNumber);
const prompt = this.#promptBuilder.buildTLPrompt({
    // ...existing fields...
    decisionPath,
});

// ... spawn TL and wait for exit ...

const decisionContent = this.#docManager.readDecision(issueNumber, decisionNum);
if (!decisionContent) {
    warn(COMPONENT, `#${issueNumber}: TL exited without writing ${decisionPath}`);
    return this.requestDecision(issueNumber, { type: 'parse_failure', decisionPath, summary: 'missing decision file' });
}

const parsed = this.parseDecisionFile(decisionContent);
if (!parsed) {
    warn(COMPONENT, `#${issueNumber}: invalid decision file at ${decisionPath}, requesting retry`);
    return this.requestDecision(issueNumber, { type: 'parse_failure', decisionPath, summary: 'invalid action or malformed decision file' });
}

this.#docManager.appendDecisionIndex(issueNumber, decisionNum, parsed);
return parsed;
```

3. Inject `DocManager` into `TLDispatcher` constructor and update `PromptBuilder.buildTLPrompt()` calls to pass `decisionPath` only for non-legacy issues.

- [ ] **Step 4: Run tests**

Run: `cd gol-tools/foreman && node --test tests/tl-dispatcher.test.mjs`
Expected: PASS

- [ ] **Step 5: Update daemon to pass DocManager to TLDispatcher**

In `foreman-daemon.mjs`, verify the constructor call still passes `this.#docs` in the existing argument list after the refactor:

```js
this.#tlDispatcher = new TLDispatcher(
    config,
    this.#state,
    this.#processes,
    this.#docs,
    this.#prompts,
    this.#workspaces,
);
```

- [ ] **Step 6: Run full test suite**

Run: `cd gol-tools/foreman && node --test tests/`
Expected: All PASS.

- [ ] **Step 7: Commit**

```bash
cd gol-tools/foreman
git add lib/tl-dispatcher.mjs foreman-daemon.mjs tests/tl-dispatcher.test.mjs
git commit -m "feat(foreman): TLDispatcher reads/writes decision files instead of orchestration.md (#15)"
```

---

### Task 13: System Alerts Injection

**Files:**
- Modify: `foreman-daemon.mjs` (`#requestTLDecision()` and `#onProcessExit()`)
- Modify: `lib/tl-dispatcher.mjs` (`requestDecision()`)

- [ ] **Step 1: Pass trigger context through to PromptBuilder**

In `foreman-daemon.mjs`, modify `#onProcessExit()` to build a structured trigger object that includes system alerts:

```js
// In #onProcessExit(), when building the trigger object:
const trigger = { type: 'agent_completed' };

// Rate limit info (if applicable, from earlier detection):
if (rateLimitDetected) {
    trigger.rateLimited = true;
    trigger.provider = clientName;
}

// CI failure info:
const ciResult = await this.#runCiGate(task);
if (ciResult) {
    trigger.type = 'ci_completed';
    trigger.ciFailed = true;
    trigger.ciSummary = ciResult.summary;
}

// Commit failure info:
if (commitResult && !commitResult.success) {
    trigger.commitFailed = true;
    trigger.commitError = commitResult.error;
}
```

In `lib/tl-dispatcher.mjs` `requestDecision()`, when building the TL prompt, format alerts from trigger:

```js
const alerts = [];
if (trigger.rateLimited)  alerts.push(`⚠ Rate limited: ${trigger.provider}`);
if (trigger.ciFailed)     alerts.push(`⚠ CI failed: ${trigger.ciSummary}`);
if (trigger.commitFailed) alerts.push(`⚠ Commit failed: ${trigger.commitError}`);
if (trigger.toolError)    alerts.push(`⚠ Tool error: ${trigger.toolError}`);
const systemAlerts = alerts.length ? alerts.join('\n') : 'None';
```

Pass `systemAlerts` to `PromptBuilder.buildTLPrompt()`.

- [ ] **Step 2: Verify no import errors**

Run: `cd gol-tools/foreman && node -e "import('./foreman-daemon.mjs')"`

- [ ] **Step 3: Commit**

```bash
cd gol-tools/foreman
git add foreman-daemon.mjs lib/tl-dispatcher.mjs
git commit -m "feat(foreman): inject system alerts (rate limit, CI, commit) into TL prompt (#15)"
```

---

## Module 2: State Reliability (#4 Persistence + #5 Transactions)

### Task 14: #save() Throw on Failure

**Files:**
- Modify: `lib/state-manager.mjs:296-355` (`#save()`)
- Test: `tests/state-manager.test.mjs`

- [ ] **Step 1: Write failing test for #save() throwing**

In `tests/state-manager.test.mjs`, add:

```js
test('#save throws when write fails', (t) => {
    const sm = new StateManager(tmpDir);
    sm.createTask(1, 'test');

    // Make the data dir read-only to force write failure
    const statePath = join(tmpDir, 'state.json');
    chmodSync(tmpDir, 0o444);

    try {
        assert.throws(() => {
            sm.createTask(2, 'should fail');
        }, /EACCES|EPERM/);
    } finally {
        chmodSync(tmpDir, 0o755);
    }
});
```

Note: the `chmodSync()` approach may be flaky in CI/macOS sandboxes. If it does not reliably fail writes in CI, replace the filesystem permission trick with a test-only mock/stub of `writeFileSync()` that throws.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd gol-tools/foreman && node --test tests/state-manager.test.mjs`
Expected: FAIL — currently `#save()` swallows the error.

- [ ] **Step 3: Make #save() throw on failure**

In `lib/state-manager.mjs`, modify the `#save()` method. Find the catch block that swallows errors and re-throw:

```js
// In #save(), the catch block currently only logs:
// Change to:
catch (err) {
    this.#cleanupAndRestore();
    error('state', `Failed to save state: ${err.message}`);
    throw err;  // Let caller know persistence failed
}
```

The key change: after `#cleanupAndRestore()` (which restores from backup), throw the error instead of silently continuing.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd gol-tools/foreman && node --test tests/state-manager.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/state-manager.mjs tests/state-manager.test.mjs
git commit -m "fix(foreman): #save() throws on write failure instead of silently swallowing (#13)"
```

Caller handling note: any caller of `StateManager` methods that trigger `#save()` should wrap those calls in `try/catch` and enter degraded mode (log error, skip state-dependent operations) instead of crashing. This is already expected to be enforced by the existing `foreman-daemon.mjs` try/catch blocks around state operations.

---

### Task 15: State Schema v4 + spawnContext/retryState Persistence

**Files:**
- Modify: `lib/state-manager.mjs` (schema migration, normalizeTask, new methods)
- Test: `tests/state-manager.test.mjs`

- [ ] **Step 1: Write failing tests for v4 schema**

In `tests/state-manager.test.mjs`, add:

```js
test('v4 migration adds spawnContext and retryState defaults', (t) => {
    // Write a v3 state file
    const v3State = {
        version: 3,
        tasks: { '100': { issue_number: 100, state: 'building', pid: 123, internal_rework_count: 0, worker_spawn_counts: { planner: 1, coder: 1 } } },
        dead_letter: [],
    };
    writeFileSync(join(tmpDir, 'state.json'), JSON.stringify(v3State));

    const sm = new StateManager(tmpDir);
    const task = sm.getTask(100);
    assert.strictEqual(task.spawnContext, null);
    assert.strictEqual(task.retryState, null);
});

test('v4 migration adds pendingOps default', (t) => {
    const v3State = { version: 3, tasks: {}, dead_letter: [] };
    writeFileSync(join(tmpDir, 'state.json'), JSON.stringify(v3State));

    const sm = new StateManager(tmpDir);
    // Access internal state to check pendingOps
    const state = JSON.parse(readFileSync(join(tmpDir, 'state.json'), 'utf-8'));
    // After load+save, version should be 4 with pendingOps
    assert.strictEqual(state.version, 4);
    assert.ok(Array.isArray(state.pendingOps));
});

test('updateSpawnContext persists to disk', (t) => {
    const sm = new StateManager(tmpDir);
    sm.createTask(200, 'test');
    sm.transition(200, 'planning', 'start');

    const ctx = { role: 'planner', model: 'test', decisionNumber: 1, worktreePath: '/tmp/ws' };
    sm.updateSpawnContext(200, ctx);

    // Reload from disk
    const sm2 = new StateManager(tmpDir);
    const task = sm2.getTask(200);
    assert.deepStrictEqual(task.spawnContext, ctx);
});

test('updateRetryState persists to disk', (t) => {
    const sm = new StateManager(tmpDir);
    sm.createTask(201, 'test');
    sm.transition(201, 'planning', 'start');

    const retry = { modelIndex: 1, backoffRound: 0, backoffMinutes: 4, lastAttempt: '2026-03-29T14:00:00Z' };
    sm.updateRetryState(201, retry);

    const sm2 = new StateManager(tmpDir);
    assert.deepStrictEqual(sm2.getTask(201).retryState, retry);
});

test('clearRuntimeContext nulls both fields', (t) => {
    const sm = new StateManager(tmpDir);
    sm.createTask(202, 'test');
    sm.transition(202, 'planning', 'start');
    sm.updateSpawnContext(202, { role: 'planner' });
    sm.updateRetryState(202, { modelIndex: 0 });

    sm.clearRuntimeContext(202);

    const task = sm.getTask(202);
    assert.strictEqual(task.spawnContext, null);
    assert.strictEqual(task.retryState, null);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && node --test tests/state-manager.test.mjs`
Expected: FAIL — methods don't exist, v4 migration not implemented.

- [ ] **Step 3: Implement v4 migration and new methods**

In `lib/state-manager.mjs`:

1. Update `EMPTY_STATE` version to 4:
```js
const EMPTY_STATE = { version: 4, tasks: {}, dead_letter: [], pendingOps: [] };
```

2. Update `#normalizeTask()`:
```js
#normalizeTask(task) {
    task.internal_rework_count ??= 0;
    task.worker_spawn_counts = {
        planner: task.worker_spawn_counts?.planner ?? 0,
        coder: task.worker_spawn_counts?.coder ?? 0,
    };
    task.spawnContext ??= null;
    task.retryState ??= null;
}
```

3. Update `#load()` to handle v3→v4 migration:
```js
// In #load(), after existing migration checks:
if (data.version === 3) {
    data.version = 4;
    data.pendingOps = data.pendingOps ?? [];
    // Tasks get normalized via #normalizeTask on access
}
if (data.version !== 4) {
    // ... existing migration logic for v1/v2
}
```

4. Add new methods:
```js
updateSpawnContext(issueNumber, context) {
    const task = this.getTask(issueNumber);
    if (!task) throw new Error(`Task #${issueNumber} not found`);
    task.spawnContext = context;
    this.#save();
}

updateRetryState(issueNumber, retryState) {
    const task = this.getTask(issueNumber);
    if (!task) throw new Error(`Task #${issueNumber} not found`);
    task.retryState = retryState;
    this.#save();
}

clearRuntimeContext(issueNumber) {
    const task = this.getTask(issueNumber);
    if (!task) throw new Error(`Task #${issueNumber} not found`);
    task.spawnContext = null;
    task.retryState = null;
    this.#save();
}
```

Read the actual `StateManager` source first and prefer public accessors like `getTask()` over direct internal property access wherever possible.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/foreman && node --test tests/state-manager.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/state-manager.mjs tests/state-manager.test.mjs
git commit -m "feat(foreman): state schema v4 with spawnContext/retryState persistence (#4)"
```

---

### Task 16: Daemon Restart Recovery

**Files:**
- Modify: `foreman-daemon.mjs` (startup/orphan recovery logic)

- [ ] **Step 1: Update daemon startup to use persisted context**

In `foreman-daemon.mjs`, find the orphan recovery logic (the startup code that iterates active tasks). Update it to use persisted `spawnContext` and `retryState`:

```js
// In startup / orphan recovery:
for (const [issueNumber, task] of Object.entries(activeTasks)) {
    if (task.pid) {
        const alive = this.#processes.isAlive(task.pid);
        if (alive) {
            // Re-track the running process
            this.#processes.retrack(issueNumber, task.pid);
            continue;
        }

        // Process dead but we have persisted context
        if (task.retryState) {
            info(COMPONENT, `#${issueNumber}: recovering retry state from persisted context`);
            this.#retryState.set(String(issueNumber), task.retryState);
            if (task.spawnContext) {
                this.#spawnContext.set(String(issueNumber), task.spawnContext);
            }
            this.#handleRateLimitRetry(issueNumber, task);
            continue;
        }

        if (task.spawnContext) {
            info(COMPONENT, `#${issueNumber}: process dead, requesting TL decision with spawn context`);
            this.#spawnContext.set(String(issueNumber), task.spawnContext);
            await this.#requestTLDecision(issueNumber, { type: 'agent_crashed' });
            continue;
        }

        // No context — generic orphan recovery
        info(COMPONENT, `#${issueNumber}: orphan detected, requesting TL decision`);
        await this.#requestTLDecision(issueNumber, { type: 'agent_crashed' });
    } else if (['planning', 'building', 'reviewing', 'testing'].includes(task.state)) {
        // Active state but no PID — state without process
        warn(COMPONENT, `#${issueNumber}: active state ${task.state} but no PID`);
        await this.#requestTLDecision(issueNumber, { type: 'orphan_state' });
    }
}
```

- [ ] **Step 2: Update #handleRateLimitRetry to persist state**

In the existing `#handleRateLimitRetry()` method, add calls to persist retry state after each change:

```js
// After setting retry state in #retryState Map:
this.#state.updateRetryState(issueNumber, retry);

// After clearing retry (on success or giving up):
this.#state.clearRuntimeContext(issueNumber);
```

Similarly, in spawn-tracking code (where `#spawnContext` is set), add:
```js
this.#state.updateSpawnContext(issueNumber, ctx);
```

And when clearing:
```js
this.#state.clearRuntimeContext(issueNumber);
```

- [ ] **Step 3: Verify no import errors**

Run: `cd gol-tools/foreman && node -e "import('./foreman-daemon.mjs')"`

- [ ] **Step 4: Commit**

```bash
cd gol-tools/foreman
git add foreman-daemon.mjs
git commit -m "feat(foreman): daemon restart recovers from persisted spawn/retry context (#4)"
```

---

### Task 17: PendingOps Queue in StateManager

**Files:**
- Modify: `lib/state-manager.mjs`
- Test: `tests/state-manager.test.mjs`

- [ ] **Step 1: Write failing tests for pendingOps CRUD**

In `tests/state-manager.test.mjs`, add:

```js
test('addPendingOp persists to disk', (t) => {
    const sm = new StateManager(tmpDir);
    const op = {
        id: 'verify_100_1711720000',
        type: 'verify',
        issueNumber: 100,
        steps: [
            { action: 'create_pr', status: 'pending' },
            { action: 'github_comment', status: 'pending' },
        ],
        createdAt: new Date().toISOString(),
    };

    sm.addPendingOp(op);

    const sm2 = new StateManager(tmpDir);
    const ops = sm2.getPendingOps();
    assert.strictEqual(ops.length, 1);
    assert.strictEqual(ops[0].id, 'verify_100_1711720000');
});

test('updatePendingOp updates step status', (t) => {
    const sm = new StateManager(tmpDir);
    const op = {
        id: 'abandon_101_1711720000',
        type: 'abandon',
        issueNumber: 101,
        steps: [
            { action: 'github_comment', status: 'pending' },
            { action: 'label_swap', status: 'pending' },
        ],
        createdAt: new Date().toISOString(),
    };
    sm.addPendingOp(op);

    op.steps[0].status = 'completed';
    sm.updatePendingOp(op);

    const sm2 = new StateManager(tmpDir);
    const ops = sm2.getPendingOps();
    assert.strictEqual(ops[0].steps[0].status, 'completed');
    assert.strictEqual(ops[0].steps[1].status, 'pending');
});

test('removePendingOp removes by id', (t) => {
    const sm = new StateManager(tmpDir);
    sm.addPendingOp({ id: 'op1', type: 'verify', issueNumber: 1, steps: [], createdAt: new Date().toISOString() });
    sm.addPendingOp({ id: 'op2', type: 'cancel', issueNumber: 2, steps: [], createdAt: new Date().toISOString() });

    sm.removePendingOp('op1');

    const sm2 = new StateManager(tmpDir);
    const ops = sm2.getPendingOps();
    assert.strictEqual(ops.length, 1);
    assert.strictEqual(ops[0].id, 'op2');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && node --test tests/state-manager.test.mjs`
Expected: FAIL — methods don't exist.

- [ ] **Step 3: Implement pendingOps methods in StateManager**

In `lib/state-manager.mjs`, add:

```js
getPendingOps() {
    return this.#state.pendingOps || [];
}

addPendingOp(op) {
    if (!this.#state.pendingOps) this.#state.pendingOps = [];
    this.#state.pendingOps.push(op);
    this.#save();
}

updatePendingOp(op) {
    const ops = this.#state.pendingOps || [];
    const idx = ops.findIndex(o => o.id === op.id);
    if (idx === -1) throw new Error(`PendingOp ${op.id} not found`);
    ops[idx] = op;
    this.#save();
}

removePendingOp(opId) {
    if (!this.#state.pendingOps) return;
    this.#state.pendingOps = this.#state.pendingOps.filter(o => o.id !== opId);
    this.#save();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/foreman && node --test tests/state-manager.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/state-manager.mjs tests/state-manager.test.mjs
git commit -m "feat(foreman): pendingOps CRUD in StateManager (#5)"
```

---

### Task 18: State-First Terminal Operations

**Files:**
- Modify: `foreman-daemon.mjs` (`#handleVerify()`, `#handleAbandon()`, `#cancelTask()`)
- Modify: `lib/github-sync.mjs` (idempotency helpers used by terminal ops)

- [ ] **Step 1: Define step builders for each terminal operation**

In `foreman-daemon.mjs`, add helper methods:

```js
#buildVerifySteps(task) {
    return [
        { action: 'create_pr', status: 'pending' },
        { action: 'pr_checks', status: 'pending' },
        { action: 'github_comment', status: 'pending' },
        { action: 'label_swap', status: 'pending', target: this.#config.labels.done },
        { action: 'cleanup', status: 'pending' },
    ];
}

#buildAbandonSteps() {
    return [
        { action: 'github_comment', status: 'pending' },
        { action: 'label_swap', status: 'pending', target: this.#config.labels.blocked },
        { action: 'cleanup', status: 'pending' },
    ];
}

#buildCancelSteps(task) {
    const steps = [];
    if (task.pid) steps.push({ action: 'kill_process', status: 'pending' });
    steps.push(
        { action: 'github_comment', status: 'pending' },
        { action: 'label_swap', status: 'pending', target: this.#config.labels.cancelled },
        { action: 'cleanup', status: 'pending' },
    );
    return steps;
}
```

- [ ] **Step 2: Refactor #handleVerify to state-first**

```js
async #handleVerify(task, decision) {
    const { issue_number } = task;
    const opId = `verify_${issue_number}_${Date.now()}`;
    const op = {
        id: opId,
        type: 'verify',
        issueNumber: issue_number,
        steps: this.#buildVerifySteps(task),
        context: { branch: task.branch, workspace: task.workspace, title: task.issue_title, comment: decision.githubComment },
        createdAt: new Date().toISOString(),
    };

    // Queue the intent before side effects, but keep the task record until
    // create_pr + pr_checks finish so TL can still re-dispatch on CI failure.
    this.#state.addPendingOp(op);

    // Execute side effects
    await this.#executePendingOp(op);

    const prChecksStep = op.steps.find(step => step.action === 'pr_checks');
    if (prChecksStep?.result?.passed === false) {
        this.#state.removePendingOp(op.id);
        const prNumber = op.steps.find(step => step.action === 'create_pr')?.result?.prNumber;
        const summary = prChecksStep.result.pending
            ? `PR #${prNumber} checks still pending`
            : `PR #${prNumber} failing checks: ${prChecksStep.result.failing.join(', ')}`;
        this.#decisionPending.delete(String(issue_number));
        this.#retryState.delete(String(issue_number));
        this.#spawnContext.delete(String(issue_number));
        await this.#requestTLDecision(issue_number, {
            type: 'ci_failed',
            prNumber,
            summary,
        });
        return;
    }

    // Verify completed successfully — now remove active task state.
    this.#decisionPending.delete(String(issue_number));
    this.#retryState.delete(String(issue_number));
    this.#spawnContext.delete(String(issue_number));
    this.#state.removeTask(issue_number);
    this.#markRecentlyCompleted(issue_number);
}
```

- [ ] **Step 3: Refactor #handleAbandon to state-first**

```js
async #handleAbandon(task, decision) {
    const { issue_number } = task;
    const comment = decision.githubComment || '任务无法完成';
    const opId = `abandon_${issue_number}_${Date.now()}`;
    const op = {
        id: opId,
        type: 'abandon',
        issueNumber: issue_number,
        steps: this.#buildAbandonSteps(),
        context: { workspace: task.workspace, comment },
        createdAt: new Date().toISOString(),
    };

    // State-first
    this.#state.abandon(issue_number, comment);
    this.#state.addPendingOp(op);

    this.#decisionPending.delete(String(issue_number));
    this.#retryState.delete(String(issue_number));
    this.#spawnContext.delete(String(issue_number));
    this.#markRecentlyCompleted(issue_number);

    await this.#executePendingOp(op);
}
```

- [ ] **Step 4: Refactor #cancelTask to state-first**

```js
async #cancelTask(issueNumber, reason) {
    const task = this.#state.getTask(issueNumber);
    if (!task) { warn(COMPONENT, `#${issueNumber}: cancel — task not found`); return; }

    const opId = `cancel_${issueNumber}_${Date.now()}`;
    const op = {
        id: opId,
        type: 'cancel',
        issueNumber,
        steps: this.#buildCancelSteps(task),
        context: { workspace: task.workspace, reason, pid: task.pid },
        createdAt: new Date().toISOString(),
    };

    // State-first
    this.#state.cancel(issueNumber, reason);
    this.#state.addPendingOp(op);

    this.#decisionPending.delete(String(issueNumber));
    this.#retryState.delete(String(issueNumber));
    this.#spawnContext.delete(String(issueNumber));
    this.#markRecentlyCompleted(issueNumber);

    await this.#executePendingOp(op);
}
```

- [ ] **Step 5: Implement #executePendingOp**

```js
async #executePendingOp(op) {
    for (const step of op.steps) {
        if (step.status !== 'pending') continue;

        try {
            await this.#executeStep(op, step);
            step.status = 'completed';
            this.#state.updatePendingOp(op);
        } catch (err) {
            step.status = 'failed';
            step.error = err.message;
            this.#state.updatePendingOp(op);
            warn(COMPONENT, `PendingOp ${op.id} step ${step.action} failed: ${err.message}`);
            return; // Stop — will be retried by #retryPendingOps
        }
    }

    // All steps completed — remove op
    this.#state.removePendingOp(op.id);
    info(COMPONENT, `PendingOp ${op.id} completed successfully`);
}

async #executeStep(op, step) {
    const ctx = op.context;
    switch (step.action) {
        case 'create_pr': {
            const existing = await this.#github.findOpenPR(ctx.branch);
            const pr = existing || await this.#github.createPR(op.issueNumber, ctx.branch, ctx.title);
            step.result = { prNumber: pr.number };
            break;
        }
        case 'pr_checks':
            const prevStep = op.steps.find(s => s.action === 'create_pr');
            const prNum = prevStep?.result?.prNumber;
            if (prNum) {
                const checks = await this.#github.getPRChecks(prNum);
                step.result = {
                    passed: checks.passed,
                    pending: checks.pending,
                    failing: checks.failing,
                };
            }
            break;
        case 'github_comment': {
            const marker = `<!-- foreman-${op.type} -->`;
            const existing = await this.#github.hasCommentMarker(op.issueNumber, marker);
            if (!existing) {
                await this.#github.postComment(op.issueNumber, `${marker}\n${ctx.comment || ''}`);
            }
            break;
        }
        case 'label_swap': {
            const labels = await this.#github.getIssueLabels(op.issueNumber);
            if (!labels.includes(step.target) || labels.includes(this.#progressLabel())) {
                await this.#github.transitionLabels(op.issueNumber, this.#progressLabel(), step.target);
            }
            break;
        }
        case 'cleanup':
            if (ctx.workspace && existsSync(ctx.workspace)) this.#workspaces.destroy(ctx.workspace);
            break;
        case 'kill_process':
            if (ctx.pid && this.#processes.isAlive(ctx.pid)) this.#processes.kill(op.issueNumber);
            break;
    }
}
```

Add the GitHub-side helpers needed by the idempotency checks if they do not already exist:

```js
// lib/github-sync.mjs
async hasCommentMarker(issueNumber, marker) {
    const body = await this.#gh([
        'issue', 'view', String(issueNumber),
        '--json', 'comments',
        '--jq', `[.comments[].body | contains(${JSON.stringify(marker)})] | any`
    ], { json: false });
    return body.trim() === 'true';
}
```

- [ ] **Step 6: Verify no import errors**

Run: `cd gol-tools/foreman && node -e "import('./foreman-daemon.mjs')"`

- [ ] **Step 7: Commit**

```bash
cd gol-tools/foreman
git add foreman-daemon.mjs lib/github-sync.mjs
git commit -m "feat(foreman): state-first terminal operations with pendingOps tracking (#5)"
```

---

### Task 19: PendingOps Retry Mechanism

**Files:**
- Modify: `foreman-daemon.mjs` (`#runProcessCheck()`)

- [ ] **Step 1: Add #retryPendingOps to daemon tick**

In `foreman-daemon.mjs`, add the retry method and wire it into `#runProcessCheck()`:

```js
async #retryPendingOps() {
    const ops = this.#state.getPendingOps();
    const now = Date.now();
    const maxAge = 60 * 60 * 1000; // 1 hour

    for (const op of ops) {
        const prChecksStep = op.steps.find(step => step.action === 'pr_checks');
        if (prChecksStep?.result?.passed === false) {
            info(COMPONENT, `Skipping pendingOp ${op.id}: CI failure already handed to TL`);
            continue;
        }

        const hasFailed = op.steps.some(s => s.status === 'failed');
        if (!hasFailed) continue;

        const age = now - new Date(op.createdAt).getTime();
        if (age > maxAge) {
            warn(COMPONENT, `PendingOp ${op.id} expired (${Math.round(age / 60000)}m old), removing`);
            this.#notifier.send('WARN', `PendingOp ${op.id} expired — manual cleanup may be needed for issue #${op.issueNumber}`);
            this.#state.removePendingOp(op.id);
            continue;
        }

        info(COMPONENT, `Retrying pendingOp ${op.id}`);
        // Reset failed steps to pending for retry
        for (const step of op.steps) {
            if (step.status === 'failed') {
                step.status = 'pending';
                delete step.error;
            }
        }
        await this.#executePendingOp(op);
    }
}
```

In `#runProcessCheck()`, add at the end (after `#processCancelRequests()`):

```js
// At the end of #runProcessCheck():
await this.#retryPendingOps();
```

- [ ] **Step 2: Also run pending ops on daemon startup**

In the daemon startup sequence, after orphan recovery, add:

```js
await this.#retryPendingOps();
```

This ensures any pending ops from before a crash are retried immediately on restart.

- [ ] **Step 3: Verify no import errors**

Run: `cd gol-tools/foreman && node -e "import('./foreman-daemon.mjs')"`

- [ ] **Step 4: Run full test suite**

Run: `cd gol-tools/foreman && node --test tests/`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add foreman-daemon.mjs
git commit -m "feat(foreman): pendingOps retry in daemon tick + startup recovery (#5)"
```

---

## Final Verification

- [ ] **Run full test suite**: `cd gol-tools/foreman && node --test tests/`
- [ ] **Verify daemon starts cleanly**: `cd gol-tools/foreman && node foreman-daemon.mjs` (Ctrl+C after startup log confirms no crashes)
- [ ] **Push submodule**: `cd gol-tools && git push origin main`
- [ ] **Update main repo submodule pointer**: `cd gol && git add gol-tools && git commit -m "chore: update gol-tools for foreman P0+P1 refactor" && git push`
