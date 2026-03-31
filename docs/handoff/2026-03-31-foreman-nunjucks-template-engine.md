# Handoff: Foreman Nunjucks Template Engine Migration

Date: 2026-03-31
Session focus: Migrate foreman's PromptBuilder from `.replace()` to Nunjucks template engine with conditional rendering

## User Requests (Verbatim)

- `docs/superpowers/plans/2026-03-31-foreman-nunjucks-template-engine.md 实现此计划，通过 worktree 工作，完成后提交一个 PR 请求合入 gol-tools 模块，不影响当前工作区`
- `记录工作`

## Goal

PR https://github.com/Dluck-Games/gol-tools/pull/4 is created and ready for review/merge. After merging, update the gol main repo's submodule pointer.

## Work Completed

- Created worktree at `.worktrees/manual/foreman-nunjucks/` on branch `feat/foreman-nunjucks-template-engine` from `gol-tools` submodule
- Installed `nunjucks@^3.2.4` as dependency in `foreman/package.json`
- Rewrote `foreman/lib/prompt-builder.mjs`: replaced `.replace()` chains with `nunjucks.Environment.render()`, using private `#render()` method, `FileSystemLoader`, and options `autoescape: false`, `throwOnUndefined: true`, `trimBlocks: true`, `lstripBlocks: true`
- Migrated all 5 prompt templates from `{{UPPER_SNAKE}}` to `{{ camelCase }}` syntax: `reviewer-task.md`, `tester-task.md`, `planner-task.md`, `coder-task.md`, `tl-decision.md`
- Added conditional rendering blocks: `{% if issueBody %}` in planner, `{% if planDoc %}` / `{% if prevHandoff %}` in coder, `{% if systemAlerts and systemAlerts != "None" %}` in tl-decision
- Fixed consecutive blank lines issue from collapsed `{% if %}` blocks by adjusting whitespace layout around conditionals
- Created 29 unit tests in `foreman/tests/prompt-builder.test.mjs` covering all build methods, conditionals (both present/empty), error handling, whitespace handling, and template configuration
- All 224+ tests pass (including existing `tl-dispatcher.test.mjs` which mocks `buildTLPrompt`)
- Verified zero `{{UPPER_SNAKE}}` patterns remain via `grep -rn '{{[A-Z_]*}}' prompts/`
- Pushed branch and created PR #4 to `Dluck-Games/gol-tools`

## Current State

- Worktree at `.worktrees/manual/foreman-nunjucks/` has clean working tree, 10 commits on `feat/foreman-nunjucks-template-engine`
- Branch pushed to `origin` (gol-tools remote)
- PR #4 open at https://github.com/Dluck-Games/gol-tools/pull/4
- Main `gol-tools/` submodule on `main` is **unaffected** (no changes there)
- Main `gol/` repo submodule pointer is **unaffected**

## Pending Tasks

- Merge PR #4 in gol-tools repo
- After merge: update gol main repo submodule pointer (`git add gol-tools` in `gol/`)
- Clean up worktree: `git -C gol-tools worktree remove ../.worktrees/manual/foreman-nunjucks` (optional)

## Key Files

- `gol-tools/foreman/lib/prompt-builder.mjs` — Rewritten Nunjucks-based template renderer
- `gol-tools/foreman/prompts/coder-task.md` — Migrated with planDoc/prevHandoff conditionals
- `gol-tools/foreman/prompts/planner-task.md` — Migrated with issueBody conditional
- `gol-tools/foreman/prompts/tl-decision.md` — Migrated with systemAlerts conditional
- `gol-tools/foreman/tests/prompt-builder.test.mjs` — 29 unit tests (new file)
- `gol-tools/foreman/package.json` — Added nunjucks dependency
- `docs/superpowers/plans/2026-03-31-foreman-nunjucks-template-engine.md` — Original implementation plan

## Important Decisions

- Used `trimBlocks: true` + `lstripBlocks: true` in Nunjucks config to minimize whitespace issues from `{% %}` tags, but still needed manual blank line adjustments around conditional blocks to prevent 4+ consecutive newlines when conditionals collapse
- The subagent created 29 tests instead of the plan's specified 11 — more comprehensive coverage (includes template configuration tests, more conditional edge cases) which is an improvement
- `throwOnUndefined: true` ensures template rendering fails loudly if a variable name is misspelled, rather than silently producing broken output

## Constraints

- All work was done in a worktree to avoid affecting the current workspace
- All `build*` method signatures were kept identical — zero consumer changes
- Template variable syntax change is backward-incompatible (old `.replace()` patterns won't work with new Nunjucks engine)

## Context for Continuation

- The `coder-task.md` line 10 has `{{ tlContext }}{% if planDoc %}` on the same line — this is intentional to prevent blank lines when tlContext is empty and planDoc conditional collapses. Functionally correct but cosmetically tight.
- The plan specified `@types/nunjucks` was not added by the final subagent (was added in an earlier failed attempt) — this is fine, it's a devDependency only for editor LSP, not needed at runtime
- Worktree is at `/Users/dluckdu/Documents/Github/gol/.worktrees/manual/foreman-nunjucks/` — can be removed after PR merge

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
