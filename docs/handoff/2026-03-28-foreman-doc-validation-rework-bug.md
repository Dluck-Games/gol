# Handoff: Foreman Doc Validation Infinite Rework Bug

Date: 2026-03-28
Session focus: Real issue E2E test for Foreman, discovered critical doc_validation rework loop bug

## User Requests (Verbatim)

- "docs/handoff/2026-03-28-foreman-bugfixes-compliance-worktrees.md 参考交接记录，我希望进行一次真实 issue 测试，使用一个相对简单的真实的 issue 来测试 foremam 的新流程。"

## Goal

Fix the doc_validation infinite rework loop bug in Foreman — coder keeps being respawned because it cannot comply with Chinese handoff doc title requirements, and the rework count limit is not enforced correctly.

## Work Completed

- Selected issue #194 (游戏正常退出后日志报错：gecs/ecs/world.gd remove_entity 报错) for E2E test
- Triggered Foreman by adding `foreman:assign` label, confirmed pickup via manual `foreman-ctl sync`
- Monitored full lifecycle: queued → planning → building → rework loop → manual cancel
- Verified planner output quality — root cause analysis and architecture constraints were correct
- Verified TL decisions — 4 decisions written to `docs/foreman/194/orchestration.md` with detailed guidance
- Verified PR #211 code quality — dual-layer defense fix for world.gd is correct and minimal
- Manually cancelled task #194 after 7 coder spawns without progress (rework loop bug)
- Identified root cause and documented the bug (see below)

## Current State

- Foreman daemon running (PID 19650), 0 active tasks, 4 dead letter entries (added #194)
- PR #211 is OPEN on Dluck-Games/god-of-lego — code is correct but task was cancelled before review phase
- Issue #194 has labels: `bug`, `topic:framework`, `foreman:cancelled`
- 7 handoff docs exist under `docs/foreman/194/` (01-planner through 07-coder), all coder docs use English titles
- `docs/foreman/` directory is untracked in parent repo

## Pending Tasks

- **Fix doc_validation rework loop bug** (see Important Decisions for root cause analysis)
- Decide whether to retry issue #194 after fix, or merge PR #211 manually
- Clean up `docs/foreman/194/` test artifacts if retrying

## Key Files

- `gol-tools/foreman/foreman-daemon.mjs` — Scheduler and lifecycle management, rework count logic
- `gol-tools/foreman/lib/tl-dispatcher.mjs` — TL decision flow, doc_validation check
- `gol-tools/foreman/prompts/coder-task.md` — Coder prompt template (likely missing Chinese title requirement)
- `gol-tools/foreman/prompts/reviewer-task.md` — Reviewer prompt with doc validation checks
- `gol-tools/foreman/lib/doc-manager.mjs` — Document validation logic, REQUIRED_SECTIONS config
- `docs/foreman/194/orchestration.md` — TL decision log showing 4 decisions and the rework loop
- `docs/foreman/194/01-planner-entity-purge-freed-ref.md` — Planner output (high quality, passed validation)
- `docs/foreman/194/05-coder-accept-freed-entity-fix.md` — Example of coder doc that failed validation (English titles)

## Important Decisions

### Bug: Doc Validation Infinite Rework Loop

**Symptom**: Coder is respawned repeatedly (7 times observed) because handoff documents always fail `doc_validation` — coder uses English section headers (`## Completed Work`) but the framework requires Chinese (`## 完成的工作`). TL writes increasingly desperate instructions (Decision 3 → 4) but coder never complies.

**Root Cause Analysis (two issues)**:

1. **Chinese title requirement only in TL context, not in coder-task.md**: The coder prompt template (`coder-task.md`) likely doesn't include the Chinese standard section headers requirement. It's only injected via TL Context in `orchestration.md`. The codebuddy model (glm-5.0-turbo-ioa) has a strong preference for English headings and ignores the TL context format instructions.

2. **Rework count limit not enforced**: TL Decision 4 states "内部迭代将达第 3 次（Decision 2=第1次, Decision 3=第2次, 本次=第3次），仍在上限内（>3 才 abandon）". But the coder was spawned 7 times total (docs 02 through 07) without triggering abandon. Either the rework count is not tracking correctly, or the abandon threshold logic is broken.

**Recommended Fix Direction**:

- **Fix 1**: Add Chinese standard section headers directly into `coder-task.md` template as a hard rule, not just TL context
- **Fix 2**: Audit rework count tracking in `foreman-daemon.mjs` — verify the counter increments correctly per coder spawn and the abandon threshold fires at the right count
- **Fix 3** (optional): For pure doc format issues, consider having TL fix the doc directly instead of re-spawning coder

### What Worked Well

- Planning phase produced high-quality analysis with accurate root cause identification
- TL decisions were detailed and provided exact file paths, line numbers, and code diffs
- Code changes (PR #211) were correct and minimal — dual-layer defense for GDScript typed parameter issue
- Integration test followed `tests/AGENTS.md` conventions correctly (SceneConfig, not unit test)
- Worktree layout (`.worktrees/foreman/ws_*`) worked as designed
- Cancel mechanism (`foreman:cancelled` label) worked correctly

## Constraints

- gol-tools is a git submodule — push submodule first, then update parent repo
- Foreman uses pure ESM (.mjs), node:test, node:assert, no external dependencies
- Do not modify coder-task.md prompt content beyond the bug fix
- Do not modify tester-task.md, tl-decision.md prompt content

## Context for Continuation

- This was the first real-issue E2E test of the Foreman TL architecture (previous 2 tests used trivial fake issues)
- The code fix itself (PR #211) is good — the bug is purely in the Foreman framework's doc validation rework loop
- PR #211 is open and ready for review/merge if you want to bypass the Foreman flow
- The doc_validation rework loop will affect ALL future Foreman tasks — this is a blocking bug that needs to be fixed before running another E2E test
- `docs/foreman/` directory is untracked; consider whether to .gitignore it or commit the orchestration docs as part of the workflow

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
