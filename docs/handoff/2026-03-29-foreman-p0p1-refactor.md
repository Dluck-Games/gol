# Handoff: Foreman P0+P1 Refactor

Date: 2026-03-29
Session focus: Execute the 19-task P0+P1 refactoring plan for the Foreman daemon, fixing 6 critical reliability and safety issues

## User Requests (Verbatim)

- `docs/superpowers/plans/2026-03-29-foreman-p0p1-refactor.md`
- `deep 和 unspecific-high 额度快用完了，尝试使用 unspecific-low 委派后续任务`

## Goal

Merge the `foreman-p0p1-refactor` branch into `gol-tools/main`, create PR, then update the main repo's submodule pointer.

## Work Completed

- Executed all 19 tasks from the refactoring plan using subagent-driven development (Module 1 → Module 3 → Module 2 order)
- 18 atomic commits on `gol-tools/foreman-p0p1-refactor` branch (pushed to origin)
- All 210 tests passing (0 failures)

### Module 1 — Safety & Correctness (#6 CI Gate + #7 Permissions)
- CI gate `getPRChecks()` now returns `passed: false` on gh CLI error instead of silently passing
- `#runCiGate()` catches command execution errors separately from test failures (`summary: 'execution_error'`)
- Coder uses explicit `allowedTools` whitelist instead of inheriting `disallowedTools` from defaults
- `resolveRoleConfig()` supports `allowedTools` — when set, `disallowedTools` is cleared to `[]`
- `--allowedTools` added to process-manager spawn (variadic, after positional prompt like `--disallowedTools`)
- AGENTS.md rule injection in workspace-manager (appends "Foreman Rules" section after copy)
- Coder prompt stripped of all git/gh instructions; "Framework-Managed Operations" section added
- New `#runCommitStep()` method: `git add -A` → check staged changes → `git commit` → `git push`, wired into `#onProcessExit()` before CI gate
- New `createPR()` and `findOpenPR()` helpers in github-sync.mjs for framework-managed PR creation

### Module 3 — Rate Limit Unification + Decision File Split (#10 + #15)
- Extracted `RateLimitDetector` class with unified patterns for codebuddy/claude/claude-internal
- Replaced `#detectRateLimit()` in daemon (threshold >= 3) and `#isRateLimited()` in TL dispatcher (threshold >= 1)
- Removed `rateLimitPatterns` from `PROVIDER_SPECS` (patterns now solely in RateLimitDetector)
- Note: Task 8 agent adjusted codebuddy pattern to avoid false positives on bare "429" text
- DocManager gained decision file split: `decisions/` subdirectory, `writeDecisionFromDaemon()`, `readDecision()`, `readLatestDecision()`, `getDecisionCount()`, `isLegacyFormat()`, `appendDecisionIndex()`
- `initOrchestration()` now includes a Decision Log table header
- Worker docs migrated to `iterations/` subdirectory (`getIterationsDir()`, `nextSeq()`, `listDocs()` updated)
- Daemon spawn methods (`#spawnPlanner`, `#spawnCoder`, `#spawnReviewer`, `#spawnTester`) pass `getIterationsDir()` as docDir
- TL prompt template updated: replaced `{{ORCHESTRATION_PATH}}` with `{{DECISION_PATH}}`, added `{{LATEST_DECISION}}` and `{{SYSTEM_ALERTS}}`
- `buildTLPrompt()` accepts new fields: `latestDecision`, `decisionPath`, `systemAlerts`
- `parseDecisionFile()` added to TLDispatcher for standalone decision files (`**Action:**`, `**Model:**` format)
- `parseLatestDecision()` renamed to `parseLegacyDecision()` for backward compat
- `requestDecision()` supports dual format: legacy (orchestration.md) vs split-file (decisions/)
- System alerts injection: rate limit, CI failure, commit failure, tool error → formatted and passed to TL prompt

### Module 2 — State Reliability (#4 Persistence + #5 Transactions)
- `#save()` now re-throws errors instead of silently swallowing (after `#cleanupAndRestore()`)
- State schema v4: `EMPTY_STATE.version = 4`, added `pendingOps: []`, v3→v4 migration
- `#normalizeTask()` defaults `spawnContext` and `retryState` to `null`
- New methods: `updateSpawnContext()`, `updateRetryState()`, `clearRuntimeContext()` — all persist to disk
- `#recoverOrphanedTasks()` rewritten: restores `retryState`/`spawnContext` from persisted state on daemon restart
- `#handleRateLimitRetry()` and spawn-tracking code now sync to StateManager (wrapped in try/catch since #save throws)
- PendingOps CRUD: `getPendingOps()`, `addPendingOp()`, `updatePendingOp()`, `removePendingOp()`
- State-first terminal operations: `#handleVerify`, `#handleAbandon`, `#cancelTask` record intent via pendingOps before executing side effects
- `#executePendingOp()` iterates steps, persists progress after each, stops on first failure
- `#executeStep()` handles: `create_pr`, `pr_checks`, `github_comment`, `label_swap`, `cleanup`, `kill_process`
- `hasCommentMarker()` added to github-sync.mjs for idempotent comment posting
- `#retryPendingOps()` runs on every daemon tick + startup, retries failed steps, expires ops older than 1 hour

## Current State

- Branch `foreman-p0p1-refactor` pushed to `gol-tools` origin at commit `b545173`
- Worktree at `.worktrees/manual/foreman-p0p1-refactor` (branch: `foreman-p0p1-refactor`)
- `gol-tools` submodule in main repo still points to `main` at `fcb079b` — **needs update after merge**
- Main repo has uncommitted changes (docs/foreman/ orchestration updates, docs/superpowers/plans/ plan file)
- 210 tests passing, 0 failures
- E2E test skipped (expected — requires real process spawning environment)

## Pending Tasks

- Create PR on `gol-tools` repo: `foreman-p0p1-refactor` → `main`
- After PR merge: update main repo submodule pointer (`git submodule update --remote gol-tools && git add gol-tools && git commit`)
- Main repo also has uncommitted docs changes (orchestration notes, plan file) — decide whether to commit those

## Key Files

- `docs/superpowers/plans/2026-03-29-foreman-p0p1-refactor.md` — The full 19-task implementation plan (2023 lines)
- `docs/superpowers/specs/2026-03-29-foreman-p0p1-refactor-design.md` — Design spec (472 lines)
- `gol-tools/foreman/foreman-daemon.mjs` — Main daemon file, heavily modified (commit step, rate limit, state persistence, pendingOps, system alerts, restart recovery)
- `gol-tools/foreman/lib/github-sync.mjs` — CI gate fix, PR creation helpers, hasCommentMarker
- `gol-tools/foreman/lib/state-manager.mjs` — v4 schema, #save throws, spawnContext/retryState, pendingOps CRUD
- `gol-tools/foreman/lib/doc-manager.mjs` — Decision file split, iterations/ subdirectory
- `gol-tools/foreman/lib/tl-dispatcher.mjs` — Decision file parsing, dual legacy/split format, RateLimitDetector wiring
- `gol-tools/foreman/lib/rate-limit-detector.mjs` — New: unified rate-limit detection class
- `gol-tools/foreman/lib/process-manager.mjs` — Removed rateLimitPatterns, added allowedTools support
- `gol-tools/foreman/config/default.json` — Coder allowedTools whitelist

## Important Decisions

- **Module order**: Plan specified Module 1 → Module 3 → Module 2 (safety first, then data, then state). This ordering prevents state persistence code from being affected by the safety refactors.
- **`parseLegacyDecision` naming**: The plan referenced a method that didn't exist. The existing method was `parseLatestDecision()` which was renamed to `parseLegacyDecision()`. New `parseDecisionFile()` added for standalone files.
- **`check_unavailable` naming**: Code quality reviewer flagged this as conflating infra failures with CI failures. Kept as-is per plan spec — downstream `#handleVerify()` already distinguishes these paths separately.
- **`--allowedTools` variadic constraint**: Must come after positional prompt arg (same as `--disallowedTools`). Verified and preserved.
- **State calls wrapped in try/catch**: Since Task 14 made `#save()` throw, all StateManager calls from the daemon are wrapped to prevent crashes.
- **`unspecified-low` for later tasks**: User requested switching from `deep`/`unspecified-high` to `unspecified-low` after Task 9 due to budget. All subsequent tasks completed successfully with the cheaper model.
- **Submodule workflow**: Feature branch pushed to origin but NOT yet merged into gol-tools/main. Main repo submodule pointer NOT updated (waiting for merge).

## Constraints

- **MONOREPO RULES**: Push submodule first, then update main repo reference
- **NEVER** create game files at this root — always work inside `gol-project/`
- **NEVER** run Godot from this directory
- **NEVER** create branches in the main repo — all development in submodules
- **ALWAYS** Keep all worktree checkouts under `gol/.worktrees/`
- `--allowedTools` and `--disallowedTools` are mutually exclusive per config design
- Legacy tasks (no `decisions/` directory) are NOT migrated mid-flight — they stay on old orchestration.md parsing

## Context for Continuation

- The PR needs to be created on `gol-tools` repo (not the main `gol` repo): `gh pr create -R Dluck-Games/gol-tools`
- After merge, run `git submodule update --remote gol-tools` from the main repo root, then `git add gol-tools && git commit && git push`
- The worktree at `.worktrees/manual/foreman-p0p1-refactor` can be cleaned up after merge
- Code quality reviewer noted: `check_unavailable` in getPRChecks creates same failure path as real CI failures — could be refined later to distinguish infra vs code failures
- The `RateLimitDetector` patterns for codebuddy were adjusted (bare "429" text removed to avoid false positives) — this deviates slightly from the plan's original pattern list
