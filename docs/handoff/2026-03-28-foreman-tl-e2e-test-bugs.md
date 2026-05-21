# Handoff: Foreman TL E2E Test — Bug Report

Date: 2026-03-28
Session focus: End-to-end test of Foreman Team Leader architecture, discovered critical bugs during real issue execution

## User Requests (Verbatim)

- "docs/handoff/2026-03-28-foreman-team-leader.md 查看这个交接文档，帮我测试foreman最新的功能。你需要先在我本地部署开启foreman，然后创先创建一个测试的功能单，提一个测试用的一issue，然后查看formman是不是能正常巡检完成到这个19过程中，你不需要修改任何former本身的代码，仅做功能的测试和验证工作。当测试用的票单通过后，你可以从现有的票单里取一个实际的小功能，你觉得合适用于测试的，把它打上对应的标签，让foreman能够能够拾取它，然后进行一次端到端的验证和测试，整个过程你只观察和总结和记。"
- "清理状态，你已经发现一个 bug，创建一个 handoff-doc 记录它，我将处理修复"

## Goal

Fix the two bugs discovered during TL E2E testing so Foreman can complete a full issue lifecycle (assign → plan → code → review → verify) without looping or crashing.

## Work Completed

- Created missing `foreman:progress` GitHub label (was listed in config but not created on repo)
- Restarted foreman daemon with new TL architecture code (PID 70679, state migrated v2→v3)
- Created test issue #206 (`【Foreman TL 测试】添加一个简单的控制台调试日志函数`) with `foreman:assign` label
- Observed full TL lifecycle up to the reviewer loop:
  - ✅ Issue discovery → `foreman:assign` → `foreman:progress` label transition
  - ✅ Decision 1: spawn @planner — planner completed with excellent `01-planner-debug-logger-analysis.md` (all required sections)
  - ✅ Decision 2: spawn @coder — coder completed, CI PASSED, PR #207 created
  - ✅ Decision 3: spawn @reviewer — reviewer 04 produced `verified` conclusion with detailed quality analysis
  - ✅ Decision 4 (in workspace): verify — but daemon couldn't read it
  - ❌ Daemon entered infinite reviewer loop (spawned 3 reviewers before manual cancel)
- Cancelled #206 via `foreman-ctl cancel 206`
- Cleaned up GitHub labels on #206 (removed `foreman:progress`, added `wontfix`)
- Identified 2 bugs from the test run (details below)

## Current State

- Foreman daemon running (PID 70679), 0 active tasks
- Test issue #206 closed with `wontfix` label
- PR #207 still open on `foreman/issue-206-foreman-tl` branch (test artifact, should be closed)
- `docs/foreman/206/` directory exists with 5 worker documents + orchestration.md (only 3 decisions recorded)
- `.foreman/state.json` clean — 0 tasks, 1 dead letter entry (old #171)

## Pending Tasks

- **Fix Bug 1: TL writes orchestration.md to workspace instead of docs/foreman/**
- **Fix Bug 2: Cancel label transition uses non-existent `labels.cancelled` config key**
- Re-run E2E test after fixes to verify full lifecycle
- Pick a real small issue for end-to-end validation after fixes confirmed
- Clean up PR #207 (test artifact)

## Key Files

- `gol-tools/foreman/lib/tl-dispatcher.mjs` — **BUG 1 ROOT CAUSE**: TL spawns agents with `cwd = task.workspace` (line 58), so TL agent's working directory IS the workspace. When TL follows prompt instruction "append to orchestration.md", it writes to `workspace/orchestration.md` instead of `docs/foreman/206/orchestration.md`
- `gol-tools/foreman/prompts/tl-decision.md` — TL prompt says "在 orchestration.md 末尾追加" (line 53) but doesn't specify the **absolute path**. Since TL's cwd is the workspace, it writes to workspace
- `gol-tools/foreman/lib/doc-manager.mjs` — The `appendOrchestration()` method (line 149) uses `this.#baseDir` (docs/foreman/) which is correct, but TL agent doesn't use this method — it writes directly via its own tools
- `gol-tools/foreman/foreman-daemon.mjs` — **BUG 2 ROOT CAUSE**: `#transitionToCancelled()` references `this.#config.labels.cancelled` (lines 892, 899) but config only has `assign`, `progress`, `done`, `blocked` — no `cancelled` key
- `gol-tools/foreman/config/default.json` — Config has 4 labels, missing `cancelled`
- `gol-tools/foreman/lib/state-manager.mjs` — State has `cancelled` as valid terminal state but no label config backing it
- `docs/foreman/206/orchestration.md` — Only has Decision 1-3 (daemon's doc-manager wrote these during init/planner). Decisions 4+ went to workspace
- `docs/foreman/206/01-planner-debug-logger-analysis.md` — Excellent planner output, reference for quality expectations
- `docs/foreman/206/04-reviewer-test-quality-gaps.md` — Excellent reviewer output, reference for quality expectations
- `docs/foreman/206/05-reviewer-placement-convention-violation.md` — Second reviewer found file placement issue

## Important Decisions

- **Bug 1 is an architecture-level issue**: The TL agent has `disallowedTools: [Edit, Write, NotebookEdit]` (can only use Bash/Read), but uses Bash to `cat <<'EOF' > orchestration.md` which works in ANY directory. The prompt template doesn't provide the absolute path to `docs/foreman/{issue_number}/orchestration.md`. The TL cwd is set to `task.workspace` because that's where workers need to operate, but TL is a meta-role that should be operating on the docs directory.
- **Bug 1 fix options**:
  1. Change TL's `cwd` to the workDir (repo root) and pass the absolute orchestration path in the prompt
  2. Add `DOC_DIR` or `ORCHESTRATION_PATH` to the TL prompt template with the absolute path
  3. Don't spawn TL in workspace at all — spawn in workDir and pass workspace path as context
- **Bug 2 is a simple config omission**: `default.json` needs a `cancelled` label, or `#transitionToCancelled()` should fall back to a different label (e.g., `blocked`)

## Constraints

- User specified: "你不需要修改任何former本身的代码，仅做功能的测试和验证工作" — testing only, no code changes
- Bug fix will be done by user in a separate session
- Monorepo rules: push submodule first, then parent repo

## Context for Continuation

### Bug 1: TL orchestration.md write path mismatch (CRITICAL)

**Symptom**: After Decision 3 (spawn @reviewer), the reviewer completed with `verified` conclusion. TL agent (Decision 4) correctly decided `verify` and wrote it to the orchestration.md — BUT wrote it to `workspace/orchestration.md` instead of `docs/foreman/206/orchestration.md`.

**Why**: In `tl-dispatcher.mjs` line 58, TL's cwd is set to `task.workspace || this.#config.workDir`. When coder runs, workspace is e.g. `.foreman/workspaces/ws_xxx/`. TL is spawned in that same workspace. The prompt says "在 orchestration.md 末尾追加" without specifying the absolute path. TL agent creates/writes `orchestration.md` in its cwd (the workspace).

**Evidence from TL log** (`tl-issue-206.log`):
```
TL tried: Read /Users/dluckdu/.../ws_xxx/orchestration.md → "File does not exist"
TL created: touch ws_xxx/orchestration.md
TL wrote: cat <<'ORCHEOF' > ws_xxx/orchestration.md  (4 decisions including verify)
```

Meanwhile, daemon reads from `docs/foreman/206/orchestration.md` (via `doc-manager.readOrchestration()`) which only has Decisions 1-3 (written by the prompt builder injection for the first TL call, and by the TL agent during Decision 1 which ran in workDir since no workspace existed yet).

**Result**: Daemon parses Decision 3 as the latest → spawns @reviewer again → reviewer writes another doc → TL reads workspace (now has Decision 4 verify) but daemon reads docs/foreman (still Decision 3) → infinite loop.

**Root cause chain**:
1. `tl-dispatcher.mjs:58` — `cwd = task.workspace` → TL runs in workspace
2. `tl-decision.md:53` — "在 orchestration.md 末尾追加" → relative path, resolves to cwd
3. When workspace is null (first TL call), cwd = workDir (repo root), and the first TL agent happened to write to the correct `docs/foreman/206/orchestration.md` because doc-manager had already created it via `initOrchestration()`. But on subsequent calls, workspace exists and TL runs there.

### Bug 2: Cancel label config missing (MODERATE)

**Symptom**: When cancelling #206, daemon logged `#206: labels foreman:progress -> undefined`.

**Why**: `foreman-daemon.mjs:892` uses `this.#config.labels.cancelled` but `default.json` only defines `assign`, `progress`, `done`, `blocked`. The value is `undefined`, causing the GitHub API call to fail silently.

### Test observations (for future reference)

- TL agent quality is excellent — decisions are well-reasoned with detailed context
- Planner output quality is excellent — thorough analysis, proper required sections
- Reviewer output quality is excellent — adversarial review with actionable findings
- Coder successfully created PR, CI passed automatically
- Worker agent spawns, workspace creation, and state transitions all work correctly
- The only failure point is the orchestration.md path mismatch

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
