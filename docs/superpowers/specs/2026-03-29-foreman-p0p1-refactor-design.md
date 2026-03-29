# Foreman P0+P1 Refactor Design

**Date:** 2026-03-29
**Scope:** 6 issues — #4, #5, #6, #7, #10, #15 (P0 + P1)
**Out of scope:** P2 (#1, #2, #3, #9), P3 (#12, #13 partial, #14, #16), #8 (internal tool, deferred)

## Overview

Address the most critical reliability and safety issues in the Foreman daemon without a full architectural rewrite. The design is organized into three implementation modules ordered by dependency and risk.

**Implementation order:** Module 1 → Module 3 → Module 2

---

## Module 1: Safety & Correctness (#6 CI Gate + #7 Permissions)

### 1.1 CI Gate Default Reversal (#6)

**Problem:** `github-sync.mjs` `getPRChecks()` returns `{ passed: true }` on any error (network, auth, config). CI gate is silently bypassed.

**Fix:**

- `getPRChecks()` catch block → return `{ passed: false, failing: ['check_unavailable'], pending: false }`
- `#runCiGate()` in daemon: `execSync` execution errors (not test failures) → return `{ passed: false, output: err.message, summary: 'execution_error' }`
- Log a warning on both paths so failures are visible

**Files:** `lib/github-sync.mjs`, `foreman-daemon.mjs`

### 1.2 Coder Permission Lockdown (#7)

**Problem:** Coder has no `disallowedTools` restrictions. Can execute `gh pr merge`, `gh issue close`, write outside workspace via Bash.

**Fix — allowedTools whitelist:**

```jsonc
// config/default.json
{
  "roles": {
    "coder": {
      "allowedTools": [
        "Read", "Write", "Edit", "Grep", "Glob", "LS",
        "Bash", "Agent", "WebFetch", "WebSearch",
        "TodoWrite", "NotebookEdit"
      ],
      "maxTurns": 200
    }
  }
}
```

Key exclusions: `AskUserQuestion`, `EnterPlanMode`, and any unlisted tools.

**Fix — AGENTS.md rule injection:**

`workspace-manager.mjs` appends Foreman-specific rules to the existing project AGENTS.md in the worktree (never overwrites):

```markdown
## Foreman Rules
- Do NOT use `git` commands — commits are handled by the framework
- Do NOT use `gh` commands — GitHub operations are handled by the framework
- Focus on writing code, tests, and documentation only
```

The same constraints are reinforced in `prompts/coder-task.md`.

**Files:** `config/default.json`, `lib/workspace-manager.mjs`, `prompts/coder-task.md`

### 1.3 Committer Framework Step (#7 extension)

**Problem:** Coder currently handles git add/commit/push and PR creation. This gives the model direct access to git/GitHub.

**Design:** Replace agent-driven git operations with a deterministic framework step.

**Flow:**

```
coder exits
  → #runCommitStep(task)
    → cd worktree
    → git add -A
    → git diff --cached --quiet ? (no changes → skip)
    → git commit -m "feat(#{issue}): {title} — iteration {N}"
    → git push origin {branch}
  → #runCiGate(task)
  → #requestTLDecision(trigger)
```

**Error handling:** commit/push failure → trigger type `commit_failed` passed to TL via `{{SYSTEM_ALERTS}}`.

**PR creation moved to `#handleVerify()`:**

```
#handleVerify(task)
  → all checks pass
  → gh pr create --title "..." --body "..." --base main --head {branch}
  → label swap → foreman:done
```

PR is only created after full verification. Agents never see PRs — they only know about branches.

**Files:** `foreman-daemon.mjs` (new `#runCommitStep()`, modify `#onProcessExit()` flow, modify `#handleVerify()`), `prompts/coder-task.md` (remove PR creation instructions)

---

## Module 3: Rate Limit Unification + Decision File Split (#10 + #15)

### 3.1 Unified RateLimitDetector (#10)

**Problem:** Rate limit detection implemented in 3 places with different patterns and thresholds.

**Fix:** New `lib/rate-limit-detector.mjs` — single source of truth for patterns and detection.

```javascript
export class RateLimitDetector {
  static PATTERNS = {
    codebuddy: [/rate.?limit/i, /too many requests/i, /429/],
    claude:    [/rate.?limit/i, /too many requests/i, /429/, /overloaded/i],
    // consolidated from process-manager.mjs PROVIDER_SPECS
  };

  /**
   * @param {string} logContent - log tail (typically last 4096 bytes)
   * @param {string} clientName
   * @returns {{ limited: boolean, matchCount: number, patterns: string[] }}
   */
  static detect(logContent, clientName) { ... }
}
```

**Callers retain their own threshold policies:**
- `foreman-daemon.mjs #runProcessCheck()`: `matchCount >= 3` (noise-tolerant for workers)
- `tl-dispatcher.mjs requestDecision()`: `matchCount >= 1` (sensitive for TL)

**Removals:**
- `foreman-daemon.mjs #detectRateLimit()` method
- `tl-dispatcher.mjs #isRateLimited()` method
- `process-manager.mjs PROVIDER_SPECS` `rateLimitPattern` field

**Files:** New `lib/rate-limit-detector.mjs`, modify `foreman-daemon.mjs`, `lib/tl-dispatcher.mjs`, `lib/process-manager.mjs`

### 3.2 Decision File Split + Orchestration Index (#15)

**Problem:** `orchestration.md` grows unboundedly. After 3+ iterations, full content injected into TL prompt may exceed context window.

**New file structure:**

```
docs/foreman/{issue}/
├── orchestration.md              # issue context + decision index table
├── decisions/
│   ├── 001-planning.md           # full Decision content
│   ├── 002-building.md
│   └── ...
└── iterations/
    ├── 001-planner-analysis.md   # worker output documents
    └── ...
```

**orchestration.md format:**

```markdown
# Orchestration — Issue #194

## Issue
**Title:** <title>
**Labels:** <labels>
**Body:**
<issue body>

---

## Decision Log
| # | Action | Summary |
|---|--------|---------|
| 1 | spawn @planner | Initial analysis, assess task scope |
| 2 | spawn @coder | Planner complete, begin implementation |
| 3 | spawn @coder | CI failed, fix test issues |
```

**Individual decision file format (e.g., `002-building.md`):**

```markdown
# Decision 2 — 2026-03-29 14:30

**Trigger:** agent_completed
**Assessment:** Planner analysis complete, ready to implement
**Action:** spawn @coder
**Model:** sonnet
**Guidance:** Focus on the fix described in planner analysis
**TL Context for Coder:**
> <multi-line context>
```

**TL writing behavior change:**
- TL prompt provides `{{DECISION_PATH}}` = path to the new decision file to write
- TL writes the decision to that file (no longer appends to orchestration.md)
- Daemon updates orchestration.md index after TL exits (extracts Assessment as Summary line)

**DocManager changes:**

```javascript
class DocManager {
  initOrchestration(issueNumber, issue) { ... }              // existing, keep
  writeDecision(issueNumber, decisionNumber, decision) { ... } // new: write file + update index
  readDecision(issueNumber, decisionNumber) { ... }            // new
  readLatestDecision(issueNumber) { ... }                      // new
  writeWorkerDoc(issueNumber, seq, role, slug, content) { ... } // path changed to iterations/
  getLatestWorkerDoc(issueNumber) { ... }                       // path changed to iterations/
}
```

**PromptBuilder changes — TL prompt injection:**

```javascript
buildTLPrompt(task, trigger) {
  const orchestration = readFile(orchestrationPath);          // index only
  const latestDecision = docManager.readLatestDecision(issueNumber);

  // System alerts: rate limit, CI failure, commit failure, tool errors
  const alerts = [];
  if (trigger.rateLimited)  alerts.push(`Rate limited: ${trigger.provider}, backoff ${trigger.backoffMin}m`);
  if (trigger.ciFailed)     alerts.push(`CI failed: ${trigger.ciSummary}`);
  if (trigger.commitFailed) alerts.push(`Commit step failed: ${trigger.error}`);
  if (trigger.toolError)    alerts.push(`Tool error: ${trigger.toolError}`);

  return template
    .replace('{{ORCHESTRATION_CONTENT}}', orchestration)
    .replace('{{LATEST_DECISION}}', latestDecision ?? 'No previous decisions')
    .replace('{{SYSTEM_ALERTS}}', alerts.length ? alerts.join('\n') : 'None');
}
```

TL prompt template (`tl-decision.md`) adds `{{LATEST_DECISION}}`, `{{DECISION_PATH}}`, and `{{SYSTEM_ALERTS}}` placeholders.

**TLDispatcher changes:**
- `parseLatestDecision()` reads the latest decision file (via DocManager) instead of parsing orchestration.md
- Decision count detection (`#countDecisions()`) checks the decisions/ directory file count instead of regex on orchestration.md

**Files:** `lib/doc-manager.mjs`, `lib/prompt-builder.mjs`, `lib/tl-dispatcher.mjs`, `foreman-daemon.mjs`, `prompts/tl-decision.md`

---

## Module 2: State Reliability (#4 Persistence + #5 Transactions)

### 2.1 Selective State Persistence (#4)

**Problem:** `#decisionPending`, `#retryState`, `#spawnContext`, `#recentlyCompleted` are pure in-memory. Daemon crash loses retry context and spawn state.

**Persisted fields** (added to task objects in `state.json`):

```jsonc
{
  "tasks": {
    "194": {
      // existing fields...
      "state": "building",
      "pid": 12345,
      "role": "coder",

      // new: persisted runtime context
      "spawnContext": {
        "role": "coder",
        "model": "sonnet",
        "decisionNumber": 3,
        "worktreePath": "/path/to/worktree"
      },
      "retryState": {
        "modelIndex": 1,
        "backoffRound": 0,
        "backoffMinutes": 4,
        "lastAttempt": "2026-03-29T14:30:00Z"
      }
    }
  }
}
```

**Not persisted** (rebuilt on restart):
- `#decisionPending` (Set) — restart clears locks; startup logic re-evaluates tasks naturally
- `#recentlyCompleted` (Map) — worst case: one redundant evaluation after restart, idempotent and harmless

**StateManager new methods:**

```javascript
updateSpawnContext(issueNumber, context) { ... }   // write + save
updateRetryState(issueNumber, retryState) { ... }  // write + save
clearRuntimeContext(issueNumber) { ... }            // null both + save
```

**Daemon restart recovery logic:**

```
On startup, for each active task:
  if task.pid && process alive → re-track (existing logic)
  if task.pid && process dead:
    if task.retryState → resume backoff retry (use persisted model/backoff context)
    if task.spawnContext → trigger TL decision with spawn context for fallback
    else → trigger TL decision (agent_crashed trigger)
  if !task.pid + active state → trigger TL decision (orphan_state trigger)
```

**Files:** `lib/state-manager.mjs`, `foreman-daemon.mjs`

### 2.2 State-First + Pending Operations Queue (#5)

**Problem:** verify/abandon/cancel involve multi-step side effects (GitHub comment → label swap → workspace cleanup → state update). Partial failure leaves ghost states.

**Design:** Write intent to state first, then execute side effects asynchronously with per-step tracking.

**state.json new top-level field:**

```jsonc
{
  "tasks": { ... },
  "dead_letter": [ ... ],
  "pendingOps": [
    {
      "id": "verify_194_1711720000",
      "type": "verify",
      "issueNumber": 194,
      "steps": [
        { "action": "create_pr",      "status": "completed", "result": { "prNumber": 42 } },
        { "action": "pr_checks",      "status": "completed" },
        { "action": "github_comment", "status": "pending" },
        { "action": "label_swap",     "status": "pending" },
        { "action": "cleanup",        "status": "pending" }
      ],
      "createdAt": "2026-03-29T14:30:00Z"
    }
  ]
}
```

**Terminal operation steps:**

| Operation | Steps (in order) |
|-----------|-----------------|
| verify | `create_pr` → `pr_checks` → `github_comment` → `label_swap(→done)` → `cleanup(workspace)` |
| abandon | `github_comment` → `label_swap(→blocked)` → `cleanup(workspace)` |
| cancel | `kill_process` → `github_comment` → `label_swap(→cancelled)` → `cleanup(workspace)` |

**Execution flow (verify example):**

```
#handleVerify(task):
  1. Build pendingOp (all steps pending)
  2. StateManager.transition(issueNumber, terminal state) ← state-first
  3. StateManager.addPendingOp(op)                        ← write to queue
  4. #executePendingOp(op)                                ← async execution

#executePendingOp(op):
  for each step where status === 'pending':
    try:
      execute step (idempotent)
      step.status = 'completed'
      StateManager.updatePendingOp(op)   ← persist after each step
    catch:
      step.status = 'failed'
      step.error = err.message
      StateManager.updatePendingOp(op)
      break  ← stop, wait for retry
```

**Idempotency guarantees:**
- `github_comment`: check for existing comment with same marker before posting
- `label_swap`: check current labels before swapping
- `cleanup`: check worktree exists before removing
- `create_pr`: check if open PR exists for the branch
- `kill_process`: check if pid is alive before kill

**Retry mechanism:**

```
Daemon tick (#runProcessCheck):
  → #retryPendingOps()
    → iterate pendingOps with any failed steps
    → if createdAt > 1 hour → give up, log alert, remove from queue
    → else → resume from failed step
    → all steps completed → remove op from pendingOps
```

**Files:** `lib/state-manager.mjs`, `foreman-daemon.mjs`

### 2.3 Prerequisite: #save() Must Throw on Failure (#13 partial)

**Problem:** `state-manager.mjs #save()` swallows write errors. All Module 2 persistence is meaningless if writes silently fail.

**Fix:**

```javascript
// Before
#save() {
  try { writeFileSync(...); }
  catch (e) { this.#log('error', ...); }
}

// After
#save() {
  try { writeFileSync(...); }
  catch (e) {
    this.#log('error', ...);
    throw e;
  }
}
```

Callers must handle the thrown error — typically by logging and entering a degraded mode rather than continuing with unpersisted state.

**Files:** `lib/state-manager.mjs`

---

## Migration Notes

### Existing orchestration.md files (Module 3)

In-progress tasks may have existing orchestration.md files in the old format (decisions inline). Migration strategy:
- New tasks use the new file structure (decisions/ + iterations/ subdirs)
- Existing in-progress tasks continue with their current orchestration.md until completion
- `DocManager` detects format by checking for `decisions/` directory existence and falls back to legacy parsing if absent
- No retroactive migration of old files — they age out naturally as tasks complete

### State Schema Migration (Module 2)

Current schema version is v3. This design requires a **v4 migration**:

**New fields:**
- `tasks[N].spawnContext` — default `null`
- `tasks[N].retryState` — default `null`
- `pendingOps` — default `[]`

**Migration:** `#normalizeTask()` already handles missing fields gracefully. Add defaults for `spawnContext` and `retryState`. Add `pendingOps: []` default at the top level during load if missing. Bump version to 4.

---

## Config Changes Summary

```jsonc
// config/default.json additions/changes
{
  "roles": {
    "coder": {
      "allowedTools": ["Read", "Write", "Edit", "Grep", "Glob", "LS",
                        "Bash", "Agent", "WebFetch", "WebSearch",
                        "TodoWrite", "NotebookEdit"],
      "maxTurns": 200
    }
  }
}
```

No new config keys beyond existing structure. `resolveRoleConfig()` must handle `allowedTools` as an alternative to `disallowedTools`.

---

## Test Strategy

Each module should update existing test suites:

- **Module 1:** `github-sync.test.mjs` — test `getPRChecks()` error paths return `passed: false`. New tests for `#runCommitStep()` success/failure paths.
- **Module 3:** `tl-dispatcher.test.mjs` — test parsing from decision files. `doc-manager.test.mjs` — test `writeDecision()`, `readLatestDecision()`, index update. New `rate-limit-detector.test.mjs`.
- **Module 2:** `state-manager.test.mjs` — test spawnContext/retryState persistence, pendingOps CRUD, v4 migration, `#save()` throw behavior. Integration test for pendingOp retry cycle.

---

## Summary

| Module | Issues | Key Changes | Risk |
|--------|--------|-------------|------|
| 1 | #6, #7 | CI default reversal, coder allowedTools whitelist, committer framework step, PR creation in verify | Low — config + flow changes, no state schema change |
| 3 | #10, #15 | RateLimitDetector extraction, decision file split, orchestration index, system alerts injection | Medium — file structure migration, TL prompt contract change |
| 2 | #4, #5, #13 | spawnContext/retryState persistence, pendingOps queue, #save() throw, restart recovery | High — state schema v4, changes core daemon flow |
