# Handoff: Foreman Team Leader Architecture Redesign

Date: 2026-03-28
Session focus: Implement the TL (Team Leader) architecture to replace the hardcoded state machine in Foreman

## User Requests (Verbatim)

- "docs/superpowers/plans/2026-03-28-foreman-team-leader-implementation.md 阅读这份实现计划与设计 docs/superpowers/specs/2026-03-28-foreman-team-leader-design.md，实现此功能。"
- "推送，然后生成 /handoff-doc 文档"

## Goal

The TL architecture is fully implemented and pushed. The next step is **end-to-end integration testing** — manually create a test issue with `foreman:assign`, restart the daemon, and verify the full flow works in production.

## Work Completed

- I implemented the entire Foreman Team Leader architecture redesign across 6 phases (5 commits in gol-tools submodule)
- **Phase 1**: Created `lib/doc-manager.mjs` (document directory manager) and simplified `lib/state-manager.mjs` (v3 with removed fields, migration)
- **Phase 2**: Created `lib/tl-dispatcher.mjs` (TL dispatcher with decision parsing) and rewrote `lib/prompt-builder.mjs` (new buildTLPrompt, TL_CONTEXT/DOC_DIR/SEQ for all workers)
- **Phase 3**: Rewrote all 5 prompt templates (tl-decision.md, planner-task.md, coder-task.md, reviewer-task.md, tester-task.md) from JSON artifact output to .md document output
- **Phase 4**: Rewrote `foreman-daemon.mjs` — replaced Scheduler with TLDispatcher, unified #onProcessExit to TL dispatch, all spawn methods use decision objects, new verify/abandon terminal handlers, simplified CI gate, simplified GitHub sync
- **Phase 5**: Updated config (TL role, simplified labels to 4, removed backoff/ci.maxRetries), deleted scheduler.mjs, updated tests
- **Phase 6**: Created tests for doc-manager (14 tests) and tl-dispatcher (6 tests), updated existing tests
- Pushed submodule + parent repo

## Current State

- **182/183 tests pass** (1 pre-existing process-manager environment failure)
- **All 5 commits pushed** to both `gol-tools` submodule and parent `gol` repo
- Working tree clean in both repos
- Daemon has NOT been restarted with the new code yet
- No E2E integration testing has been done

## Pending Tasks

- **E2E integration testing**: Restart the daemon and test with a real issue
  - Verify orchestration.md gets created and appended with Decision chain
  - Verify all documents follow naming format and contain required sections
  - Verify user only sees foreman:assign → foreman:progress → foreman:done
  - Verify GitHub comments only appear at terminal states (verify/abandon)
  - Verify internal iterations (CI failure, reviewer rework) are transparent to user
  - Verify daemon restart recovery from foreman:progress label
  - Verify TL invalid action → automatic abandon fallback
- **GitHub label housekeeping**: Create `foreman:progress` label on god-of-lego repo, remove old labels (foreman:plan, foreman:build, foreman:rework, foreman:testing)
- **Run existing scheduler.test.mjs tests were deleted** — the old scheduler test file is gone, no action needed

## Key Files

- `gol-tools/foreman/foreman-daemon.mjs` — Main daemon, fully rewritten for TL dispatch
- `gol-tools/foreman/lib/tl-dispatcher.mjs` — TL dispatcher, spawns TL agent and parses decisions
- `gol-tools/foreman/lib/doc-manager.mjs` — Document directory manager (seq, validation, read/write)
- `gol-tools/foreman/lib/state-manager.mjs` — Simplified v3 state (removed feedback, rework_count, etc.)
- `gol-tools/foreman/lib/prompt-builder.mjs` — All build methods rewritten for TL_CONTEXT injection
- `gol-tools/foreman/prompts/tl-decision.md` — TL prompt template with decision format
- `gol-tools/foreman/config/default.json` — TL role config, 4-label scheme
- `gol-tools/foreman/lib/config-utils.mjs` — Config migration for TL changes

## Important Decisions

- **TL agent is stateless**: Each decision point spawns a fresh TL session. Memory lives in orchestration.md only.
- **Workers have zero GitHub access**: TL is the only role that posts comments or changes labels.
- **No intermediate labels**: All internal states (planning/building/reviewing) stay in state.json only. GitHub only shows assign → progress → done/blocked.
- **CI is a framework hard gate**: Daemon runs CI after coder exits, passes result as trigger to TL. TL cannot skip CI.
- **Decision parsing from orchestration.md**: TL appends Decision blocks to orchestration.md. Daemon re-reads and parses the latest block. No JSON output channel.
- **Invalid action auto-abandon**: If TL returns an unrecognized action, daemon treats it as abandon.
- **Transitions are flexible**: Any active state can transition to any other active state (TL decides the flow, not the state machine).
- **Documents are permanent**: docs/foreman/{issue-number}/ is never cleaned up (unlike old plans/reviews/tests dirs).

## Constraints

- User specified: "FOREMAN: ALWAYS Push the submodule first, then update the main repo reference"
- Monorepo rules: Never create game files at root, never run Godot from root, no branches in main repo
- The plan spec said "no more JSON artifacts" — all agent communication is through .md documents

## Context for Continuation

- The design spec is at `docs/superpowers/specs/2026-03-28-foreman-team-leader-design.md` and the implementation plan at `docs/superpowers/plans/2026-03-28-foreman-team-leader-implementation.md`
- Key architectural doc: the design spec has full flow walkthroughs (normal path, CI failure, reviewer→planner back, abandon)
- The daemon runs as a macOS launchd service. To restart: `launchctl unload ~/Library/LaunchAgents/com.dluckdu.foreman-daemon.plist && launchctl load ~/Library/LaunchAgents/com.dluckdu.foreman-daemon.plist`
- CLI tool: `node gol-tools/foreman/bin/foreman-ctl.mjs status` shows daemon/task state
- The TL agent uses the same codebuddy client as other workers, but with `disallowedTools: [AskUserQuestion, EnterPlanMode, Edit, Write, NotebookEdit]` — it can only append to orchestration.md
- **Potential issues to watch**: TL might not format Decision blocks exactly as the parser expects (regex in parseLatestDecision is the integration point). The tester prompt still references `ai-debug.mjs` which is the existing debug bridge.
- `resolveRoleConfig()` in config-utils still checks `task.last_failure_reason` for rate-limit fallback — this field no longer exists on tasks but is only accessed if provided, so it's harmless (just won't trigger the fallback for new tasks)

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
