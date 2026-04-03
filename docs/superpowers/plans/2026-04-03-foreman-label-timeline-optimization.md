# Foreman Label Timeline Optimization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate redundant GitHub label add/remove operations that pollute issue timelines.

**Architecture:** Two independent call-site fixes — (1) rewrite the `reset` command's label logic to compute a minimal diff before calling `gh`, (2) add a `pendingOp` guard to Phase C stale demotion so it doesn't race with queued `label_swap` operations. No changes to the shared `transitionLabels()` API.

**Tech Stack:** Node.js (ESM), `node:test` for testing, `gh` CLI for GitHub API.

---

### Task 1: Write tests for `reset` command label optimization

**Files:**
- Create: `gol-tools/foreman/tests/foreman-ctl-reset-labels.test.mjs`

The `reset` command uses raw `execSync` (not `GithubSync`), so we test the label-diff logic as a pure function extracted into a helper. This avoids needing to mock `execSync` (no established pattern exists) while covering all the decision branches.

- [ ] **Step 1: Create the test file with all label-diff scenarios**

Create `gol-tools/foreman/tests/foreman-ctl-reset-labels.test.mjs`:

```js
import { describe, it } from 'node:test';
import assert from 'node:assert';
import { computeResetLabelDiff } from '../bin/reset-label-utils.mjs';

describe('computeResetLabelDiff', () => {
    it('returns no-op when issue has only foreman:assign', () => {
        const result = computeResetLabelDiff([
            { name: 'foreman:assign' },
            { name: 'bug' },
        ]);
        assert.deepStrictEqual(result, { toRemove: [], toAdd: [] });
    });

    it('removes foreman:progress but keeps foreman:assign', () => {
        const result = computeResetLabelDiff([
            { name: 'foreman:assign' },
            { name: 'foreman:progress' },
        ]);
        assert.deepStrictEqual(result, { toRemove: ['foreman:progress'], toAdd: [] });
    });

    it('removes foreman:progress and adds foreman:assign when missing', () => {
        const result = computeResetLabelDiff([
            { name: 'foreman:progress' },
        ]);
        assert.deepStrictEqual(result, {
            toRemove: ['foreman:progress'],
            toAdd: ['foreman:assign'],
        });
    });

    it('adds foreman:assign when no foreman labels exist', () => {
        const result = computeResetLabelDiff([
            { name: 'bug' },
            { name: 'enhancement' },
        ]);
        assert.deepStrictEqual(result, { toRemove: [], toAdd: ['foreman:assign'] });
    });

    it('removes multiple foreman labels but keeps foreman:assign', () => {
        const result = computeResetLabelDiff([
            { name: 'foreman:assign' },
            { name: 'foreman:progress' },
            { name: 'foreman:done' },
        ]);
        assert.deepStrictEqual(result, {
            toRemove: ['foreman:progress', 'foreman:done'],
            toAdd: [],
        });
    });

    it('handles foreman:blocked without foreman:assign', () => {
        const result = computeResetLabelDiff([
            { name: 'foreman:blocked' },
        ]);
        assert.deepStrictEqual(result, {
            toRemove: ['foreman:blocked'],
            toAdd: ['foreman:assign'],
        });
    });

    it('adds foreman:assign when labels array is empty', () => {
        const result = computeResetLabelDiff([]);
        assert.deepStrictEqual(result, { toRemove: [], toAdd: ['foreman:assign'] });
    });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && node --test tests/foreman-ctl-reset-labels.test.mjs`
Expected: FAIL with `Cannot find module '../bin/reset-label-utils.mjs'`

---

### Task 2: Implement the `reset` label-diff logic

**Files:**
- Create: `gol-tools/foreman/bin/reset-label-utils.mjs`
- Modify: `gol-tools/foreman/bin/foreman-ctl.mjs:260-277`

- [ ] **Step 1: Create `reset-label-utils.mjs` with the pure function**

Create `gol-tools/foreman/bin/reset-label-utils.mjs`:

```js
/**
 * Compute the minimal label diff to reach the desired reset state (only foreman:assign).
 * @param {Array<{name: string}>} currentLabels - all labels currently on the issue
 * @returns {{ toRemove: string[], toAdd: string[] }}
 */
export function computeResetLabelDiff(currentLabels) {
    const DESIRED = 'foreman:assign';
    const foremanLabels = currentLabels.filter(l => l.name.startsWith('foreman:'));

    const toRemove = foremanLabels
        .filter(l => l.name !== DESIRED)
        .map(l => l.name);

    const hasDesired = foremanLabels.some(l => l.name === DESIRED);
    const toAdd = hasDesired ? [] : [DESIRED];

    return { toRemove, toAdd };
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd gol-tools/foreman && node --test tests/foreman-ctl-reset-labels.test.mjs`
Expected: All 7 tests PASS

- [ ] **Step 3: Replace the label logic in `foreman-ctl.mjs`**

Add import at the top of `gol-tools/foreman/bin/foreman-ctl.mjs`:

```js
import { computeResetLabelDiff } from './reset-label-utils.mjs';
```

Replace lines 260-277 (the `try` block body for label updates) with:

```js
        try {
            const labelOutput = execSync(
                `gh issue view ${issueNumber} -R ${ghRepo} --json labels`,
                { encoding: 'utf-8' },
            );
            const labelsData = JSON.parse(labelOutput);
            const currentLabels = labelsData.labels || [];

            const { toRemove, toAdd } = computeResetLabelDiff(currentLabels);

            if (toRemove.length === 0 && toAdd.length === 0) {
                console.log('  Labels already in desired state, no changes needed');
            } else {
                const args = [`gh issue edit ${issueNumber} -R ${ghRepo}`];
                if (toRemove.length > 0) args.push(`--remove-label "${toRemove.join(',')}"`);
                if (toAdd.length > 0) args.push(`--add-label "${toAdd.join(',')}"`);
                execSync(args.join(' '), { stdio: 'ignore' });

                if (toRemove.length > 0) console.log(`  Removed labels: ${toRemove.join(', ')}`);
                if (toAdd.length > 0) console.log(`  Added labels: ${toAdd.join(', ')}`);
            }
        } catch (error) {
            console.error('  Warning: Failed to update GitHub labels:', error.message);
        }
```

Note: `foreman-ctl.mjs` already uses `execSync` throughout (it's a synchronous CLI tool, not the async daemon). This is the existing pattern — we're not introducing new shell calls, just merging two into one.

- [ ] **Step 4: Commit**

```bash
cd gol-tools/foreman
git add bin/reset-label-utils.mjs bin/foreman-ctl.mjs tests/foreman-ctl-reset-labels.test.mjs
git commit -m "fix(ctl): optimize reset label ops to minimize GitHub timeline entries

Extract label-diff logic into computeResetLabelDiff() and merge
remove+add into a single gh issue edit call. Skip the call entirely
when labels are already in the desired state."
```

---

### Task 3: Write test for Phase C pendingOp guard

**Files:**
- Create: `gol-tools/foreman/tests/stale-demotion-guard.test.mjs`

- [ ] **Step 1: Create test file**

Create `gol-tools/foreman/tests/stale-demotion-guard.test.mjs`:

```js
import { describe, it } from 'node:test';
import assert from 'node:assert';
import { shouldDemoteProgress } from '../lib/label-guard.mjs';

describe('shouldDemoteProgress', () => {
    it('returns true when no task exists', () => {
        assert.strictEqual(shouldDemoteProgress(42, null, false, []), true);
    });

    it('returns false when task has a pid', () => {
        assert.strictEqual(shouldDemoteProgress(42, { pid: 1234 }, false, []), false);
    });

    it('returns false when decision is pending', () => {
        assert.strictEqual(shouldDemoteProgress(42, { pid: null }, true, []), false);
    });

    it('returns false when a label_swap pendingOp exists for the issue', () => {
        const pendingOps = [
            {
                issueNumber: 42,
                steps: [
                    { action: 'github_comment', status: 'completed' },
                    { action: 'label_swap', status: 'pending', target: 'foreman:blocked' },
                ],
            },
        ];
        assert.strictEqual(
            shouldDemoteProgress(42, { pid: null }, false, pendingOps),
            false,
        );
    });

    it('returns true when label_swap step is already completed', () => {
        const pendingOps = [
            {
                issueNumber: 42,
                steps: [
                    { action: 'label_swap', status: 'completed', target: 'foreman:blocked' },
                    { action: 'cleanup', status: 'pending' },
                ],
            },
        ];
        assert.strictEqual(
            shouldDemoteProgress(42, { pid: null }, false, pendingOps),
            true,
        );
    });

    it('returns true when pendingOp is for a different issue', () => {
        const pendingOps = [
            {
                issueNumber: 99,
                steps: [
                    { action: 'label_swap', status: 'pending', target: 'foreman:blocked' },
                ],
            },
        ];
        assert.strictEqual(
            shouldDemoteProgress(42, { pid: null }, false, pendingOps),
            true,
        );
    });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && node --test tests/stale-demotion-guard.test.mjs`
Expected: FAIL with `Cannot find module '../lib/label-guard.mjs'`

---

### Task 4: Implement the Phase C pendingOp guard

**Files:**
- Create: `gol-tools/foreman/lib/label-guard.mjs`
- Modify: `gol-tools/foreman/foreman-daemon.mjs:853-861`

- [ ] **Step 1: Create `label-guard.mjs`**

Create `gol-tools/foreman/lib/label-guard.mjs`:

```js
/**
 * Determine whether an issue with foreman:progress should be demoted to foreman:assign.
 * Returns true if the issue is NOT actively worked and should be demoted.
 *
 * @param {number} issueNumber
 * @param {object|null} task - the task record from state, or null if none exists
 * @param {boolean} decisionPending - whether a TL decision is in flight
 * @param {Array<{issueNumber: number, steps: Array<{action: string, status: string}>}>} allPendingOps
 * @returns {boolean}
 */
export function shouldDemoteProgress(issueNumber, task, decisionPending, allPendingOps) {
    if (!task) return true;
    if (task.pid) return false;
    if (decisionPending) return false;

    const hasPendingLabelOp = allPendingOps.some(op =>
        op.issueNumber === issueNumber &&
        op.steps.some(s => s.action === 'label_swap' && s.status !== 'completed')
    );
    if (hasPendingLabelOp) return false;

    return true;
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd gol-tools/foreman && node --test tests/stale-demotion-guard.test.mjs`
Expected: All 6 tests PASS

- [ ] **Step 3: Integrate into `foreman-daemon.mjs`**

Add import at the top of `gol-tools/foreman/foreman-daemon.mjs`:

```js
import { shouldDemoteProgress } from './lib/label-guard.mjs';
```

Replace lines 853-861 (the Phase C block in `#runGithubSync()`) with:

```js
            // Label hygiene: demote progress → assign for issues not actively worked
            const progressIssues = await this.#github.getIssuesByLabel(this.#progressLabel());
            const allPendingOps = this.#state.getPendingOps();
            for (const issue of progressIssues) {
                const task = this.#state.getTask(issue.number);
                const decisionPending = this.#decisionPending.has(String(issue.number));
                if (shouldDemoteProgress(issue.number, task, decisionPending, allPendingOps)) {
                    info(COMPONENT, `#${issue.number}: demoting stale progress label to assign`);
                    await this.#github.transitionLabels(issue.number, this.#progressLabel(), this.#config.labels.assign);
                }
            }
```

- [ ] **Step 4: Run full test suite**

Run: `cd gol-tools/foreman && npm test`
Expected: All tests PASS (existing + 2 new test files)

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/label-guard.mjs tests/stale-demotion-guard.test.mjs foreman-daemon.mjs
git commit -m "fix(daemon): add pendingOp guard to Phase C stale demotion

Prevent Phase C from demoting progress->assign when a label_swap
pendingOp is already queued for the issue. Avoid timeline pollution
in the same-cycle pickup+abandon edge case."
```
