# Handoff: Foreman Bug Fixes, Architecture Compliance & Unified Worktrees

Date: 2026-03-28
Session focus: Fix 2 critical bugs from TL E2E testing, implement architecture compliance spec, unify worktree directory layout, and verify with full E2E tests

## User Requests (Verbatim)

- "docs/handoff/2026-03-28-foreman-architecture-compliance.md docs/handoff/2026-03-28-foreman-tl-e2e-test-bugs.md 阅读两个交接文档，你需要：修复 bug；完成遗留事项；架构功能开发和迭代；推送代码；继续使用一个 issue 来完成端到端测试。"
- "ok 清理测试用的 issue 和 pr。然后继续为我实现 docs/superpowers/plans/2026-03-28-unified-worktrees.md 的内容，再进行一次简单验证"
- "ok 把你的工作记录，编写到 handoff doc 中"

## Goal

All planned work is complete. Foreman TL architecture is stable — bugs fixed, architecture compliance implemented, worktree layout unified, and two full E2E tests passed.

## Work Completed

### Bug Fixes (from E2E test handoff)

- **Bug 1 — TL orchestration.md write path mismatch (CRITICAL)**: TL agent was spawned with `cwd = task.workspace`, so when it followed the prompt instruction "append to orchestration.md", it wrote to `workspace/orchestration.md` instead of `docs/foreman/{issue}/orchestration.md`. This caused an infinite reviewer loop because daemon read from docs/ but TL wrote to workspace. Fixed by injecting `{{ORCHESTRATION_PATH}}` absolute path into `tl-decision.md` template, passing it through `prompt-builder.mjs` (`buildTLPrompt`) and `tl-dispatcher.mjs` (`requestDecision`).
- **Bug 2 — Cancel label config missing (MODERATE)**: `foreman-daemon.mjs:892` referenced `this.#config.labels.cancelled` but `default.json` only defined `assign/progress/done/blocked`. Fixed by adding `"cancelled": "foreman:cancelled"` to `default.json` and creating the GitHub label.

### Architecture Compliance Spec Implementation

- Implemented spec from `docs/superpowers/specs/2026-03-28-foreman-architecture-compliance-design.md`:
  - `planner-task.md` — Added `### 架构约束` required section (must list AGENTS.md files, architecture patterns, directory placement, test modes)
  - `reviewer-task.md` — Added 5 fixed architecture compliance checks with severity Important
  - `doc-manager.mjs` — Added `'## 架构约束'` to `REQUIRED_SECTIONS.planner`

### AGENTS.md Overhaul

- Rewrote `gol-tools/AGENTS.md` to reflect new TL architecture (was still referencing deleted `scheduler.mjs`, old labels `foreman:build/dluck:verify/foreman:rework`, old lifecycle)

### Unified Worktree Layout

- Implemented plan from `docs/superpowers/plans/2026-03-28-unified-worktrees.md`:
  - `workspace-manager.mjs` — Changed `#wsDir` from `.foreman/workspaces/` to `.worktrees/foreman/`
  - Cleaned up old `.foreman/workspaces/` directory
  - Updated `AGENTS.md` and `CLAUDE.md` to document `manual/` + `foreman/` subdirectory convention

### E2E Test Results

- **Issue #208** (full lifecycle): assign → planning → building → reviewing → verify → done ✅
  - All 4 TL decisions correctly written to `docs/foreman/208/orchestration.md`
  - Planner produced `## 架构约束` section
  - PR #209 created, reviewer passed
- **Issue #210** (worktree + cancel verification): worktree created at `.worktrees/foreman/` ✅, cancel label = `foreman:cancelled` ✅
- Both test issues and PR #209 cleaned up after verification

### Commits Pushed

**gol-tools submodule** (4 commits):
1. `d9485de` fix(foreman): fix TL orchestration.md write path and cancel label config
2. `cc8e63f` feat(foreman): add architecture compliance to planner and reviewer
3. `b972343` docs(foreman): update AGENTS.md for TL-driven architecture
4. `a89a00e` refactor(foreman): move worktrees from .foreman/workspaces/ to .worktrees/foreman/

**Parent repo** (3 commits):
1. `c6a72c1` chore(foreman): update gol-tools submodule — bug fixes + architecture compliance
2. `2d97898` docs(foreman): add architecture compliance spec and E2E test handoffs
3. `925e758` chore: unify worktree layout — .worktrees/{manual,foreman}

## Current State

- Foreman daemon running (PID 19650), 0 active tasks, 3 dead letter entries
- All code pushed — no uncommitted changes in gol-tools
- Parent repo has untracked `docs/superpowers/plans/2026-03-28-unified-worktrees.md` (the implementation plan, not yet committed as doc)
- `gol-project` submodule has untracked content (normal — Godot import cache)

## Pending Tasks

- None from this session — all requested work is complete

## Key Files

- `gol-tools/foreman/prompts/tl-decision.md` — TL prompt with `{{ORCHESTRATION_PATH}}` fix
- `gol-tools/foreman/lib/tl-dispatcher.mjs` — Passes `orchestrationPath` to prompt builder
- `gol-tools/foreman/lib/prompt-builder.mjs` — `buildTLPrompt` accepts and injects `orchestrationPath`
- `gol-tools/foreman/config/default.json` — Added `cancelled` label (5 labels total now)
- `gol-tools/foreman/prompts/planner-task.md` — New `### 架构约束` required section
- `gol-tools/foreman/prompts/reviewer-task.md` — 5 architecture compliance fixed checks
- `gol-tools/foreman/lib/doc-manager.mjs` — `REQUIRED_SECTIONS.planner` includes `架构约束`
- `gol-tools/foreman/lib/workspace-manager.mjs` — wsDir now `.worktrees/foreman/`
- `gol-tools/AGENTS.md` — Fully rewritten for TL architecture
- `docs/superpowers/specs/2026-03-28-foreman-architecture-compliance-design.md` — Architecture compliance spec

## Important Decisions

- **Bug 1 fix approach**: Inject absolute path via prompt template rather than changing TL's cwd, because workers need to operate in workspace but TL needs to write to docs/ — separate concerns
- **Architecture compliance**: Planner defines constraints, reviewer verifies — no new architect role needed (per spec decision from earlier session)
- **Architecture violation severity = Important**: Not Minor, because drift cost grows over time
- **Worktree layout**: `foreman/` subdirectory under `.worktrees/` rather than flat naming, to coexist with `manual/` agent worktrees in one discoverable root

## Constraints

- gol-tools is a git submodule — push submodule first, then update parent repo
- Foreman uses pure ESM (.mjs), node:test, node:assert, no external dependencies
- Do not modify coder-task.md, tester-task.md, tl-decision.md prompt content beyond the bug fix

## Context for Continuation

- Foreman TL architecture is now production-stable with 2 successful E2E runs
- The dead letter count in state.json is 3 (issues #171 and 2 test issues) — can be ignored or cleaned manually
- Next natural step would be picking a real small issue from the backlog for a production E2E run
- Architecture compliance is in place but hasn't been tested with a complex multi-file change yet — the test issues were trivial single-function additions

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
