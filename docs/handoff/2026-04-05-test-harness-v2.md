# Handoff: test-harness-v2

Date: 2026-04-05
Session focus: Reorganize GOL test framework into subagent-driven architecture (v2) — completed, verified, pushed.

## User Requests (Verbatim)

- `docs/superpowers/plans/2026-04-05-test-harness-v2.md execute the plan` — execute the plan
- "squash merge to main, notice there are other work in progress, do not effect not related files."
- "the omo settings of project needs to be tracked by git and commited. also, omo config renamed to oh-my-openagent.jsonc, mind this thing"
- "setup models in project scope, use codebuddy/kimi-k2.5-ioa for default, fallback to minimax(cb), then k2p5(kimi for coding)."
- "does it support model fallback chain configurations? just like the builtin omo agent"
- "if you updated the hook shell, do I need to restarted the opencode to make it work?"
- ".claude settings needs to be tracked either. hooks, settings, etc."
- "i had restarted, continue" (after hook fix)
- "log works and issues and findings and solutions in handoff doc. directly write it based on context, no tool call more"

## Goal

Test Harness v2 implementation is **complete and verified**. All 6 steps of the plan executed: test normalization → new agents → dispatch skill + hooks → OMO config → E2E2 verification → commit/push. Ready for next feature work or bug fixes.

## Work Completed

### Plan Execution (`docs/superpowers/plans/2026-04-05-test-harness-v2.md`)
- **Step 1**: Normalized 10 integration tests in gol-project worktree (`feat/test-harness-v2` branch)
  - Migrated 5 tests with wrong-name `_find()` → `_find_entity()`
  - Removed 4 redundant local `_find_entity()` shadows
  - Fixed `test_base_helpers.gd`: replaced indirect `call("_find_entity",...)` with direct calls
  - Removed 1 redundant `_wait_frames()` shadow
  - Committed as `ab70d0c`, squash-merged to gol-project main as `fd4647c`
- **Step 2**: Created 3 new agent definitions + deleted old `test-writer.md`
  - `test-writer-integration.md` (~195 lines) — SceneConfig expert, self-contained
  - `test-writer-unit.md` (~107 lines) — gdUnit4 expert, self-contained
  - `test-runner.md` (~152 lines) — unified multi-tier runner, read-only
  - Key discovery during code review: agents had **wrong SceneConfig API** (used `_describe()/setup()/EntityConfig` vs real `scene_name()/systems()/entities()/test_run()`) — fixed by reading actual source
- **Step 3**: Created dispatch skill + shell hooks, deleted old skills/hookify files
  - `gol-test-dispatch/SKILL.md` (~79 lines) — routing-only, no test knowledge
  - 2 shell hook scripts with jq guard, wildcard path matching, block messages to stderr
  - `.claude/settings.local.json` with PreToolUse hook registration
  - Deleted: `gol-test/`, `gol-test-integration/` (entire directories), 5 hookify `.local.md` files
- **Step 4**: Rewrote OMO config with 3 agent entries + bridge enabled
  - Renamed `oh-my-opencode.jsonc` → `oh-my-openagent.jsonc`
- **Step 5**: Verification — parallel background agents checked all file integrity, config consistency, naming correctness
- **Step 6**: Cleanup + commit + push (management repo + submodule pointer update)

### Bug Fixes Applied During Execution
1. **Missing components quick-ref** (spec review found) — added components table to test-writer-integration.md
2. **Wrong SceneConfig API** (code quality review) — read actual `scene_config.gd`, corrected all method signatures
3. **Wrong gdUnit4 assertion API** (code quality review) — fixed `has_size()`, `is_equal_approx()` etc.
4. **`.input.*` → `.tool_input.*`** (E2E hook test failure) — CC PreToolUse JSON uses `tool_input` not `input`
5. **Stdin double-consumption** (E2E hook test failure — THE BIG ONE) — two `$(jq < stdin)` calls, second always empty. Fixed with `mktemp` file pattern
6. **`.gitignore negation order** — negation rule must come AFTER directory ignore rule
7. **OMO config not tracked** — added to `.gitignore`, made `oh-my-openagent.jsonc` a tracked file
8. **`.claude/ contents not tracked** — expanded `.gitignore` negations for agents/, hooks/, settings.local.json
9. **Restored `.claude/settings.json`** after subagent accidentally deleted it during E2E test

### Model Configuration
- All 3 test agents now have explicit `model` + `fallback_models` in `oh-my-openagent.jsonc`:
  - Primary: `codebuddy/kimi-k2.5-ioa`
  - Fallback 1: `codebuddy/minimax-m2.7-ioa`
  - Fallback 2: `kimi-for-coding/k2p5`

## Current State

- **Management repo** (`gol/`): clean, on `main`, all pushed
  - Latest: `e78a20c chore: restore .claude/settings.json with hook config`
  - Submodule `gol-project/` points to `fd4647c` (normalized tests committed)
- **Worktree** at `gol/.worktrees/manual/test-harness-v2/` still exists on `feat/test-harness-v2` branch (can clean up later)
- **All hooks verified working** via real OMO subagent invocation (not just shell-level testing)
- **No uncommitted changes** in management repo (except foreman/docs noise)

## Pending Tasks

- Clean up worktree `gol/.worktrees/manual/test-harness-v2/` (no longer needed after squash merge)
- Consider merging `feat/sceneconfig-helpers` worktree if that's ready
- Next feature work TBD by user

## Key Files

- `docs/superpowers/plans/2026-04-05-test-harness-v2.md` — **the executed plan (reference)**
- `.claude/agents/test-writer-integration.md` — SceneConfig integration test writer agent (~195 lines)
- `.claude/agents/test-writer-unit.md` — gdUnit4 unit test writer agent (~107 lines)
- `.claude/agents/test-runner.md` — Unified multi-tier test runner agent (~152 lines)
- `.claude/skills/gol-test-dispatch/SKILL.md` — Routing skill for test subagents (~79 lines)
- `.claude/hooks/block-gdunit-in-integration.sh` — PreToolUse hook: blocks GdUnitTestSuite in integration/
- `.claude/hooks/block-sceneconfig-in-unit.sh` — PreToolUse hook: blocks SceneConfig in unit/
- `.claude/settings.json` — Registers PreToolUse hooks for Write|Edit tools
- `.opencode/oh-my-openagent.jsonc` — OMO config: 3 agent definitions with model fallback chains + CC bridge

## Important Decisions

- **D1-D6 from plan**: All upheld — subagent-over-skill for test writing, zero-reference maintenance, platform-neutral agents, native shell hooks for hard rules
- **Agent knowledge is embedded** (~150 lines max), not in skill docs — avoids stale reference problem from v1
- **`model` field uses string-only**, fallback chain uses separate `fallback_models` array — confirmed from OMO docs and global config
- **Hook scripts MUST use `mktemp` pattern** — `$(cat | jq)` double-consumption is a silent failure mode; this was the root cause of hooks appearing broken
- **`.gitignore` negation rules MUST appear AFTER the directory ignore rule they exempt** — git processes them sequentially

## Constraints

- Management repo (`gol/`) is for coordination only — no game code, no scenes, no assets here
- All game code changes happen in `gol-project/` submodule (with worktrees under `gol/.worktrees/`)
- Agent `.md` files must NOT include `model` field (platform-neutral, set in OMO config instead)
- Hooks are shell-command PreToolUse on Write|Edit matcher, exit 2 = deny, exit 0 = allow
- Godot project uses `GOLWorld` (ECS), `SceneConfig` (integration base), `GdUnitTestSuite` (unit base), `TestResult` API

## Context for Continuation

- **Hook debugging was the hardest part of this session** — if hooks seem broken again, check these in order:
  1. Are hook scripts using `mktemp` pattern? (don't use `$(cat | jq)` twice)
  2. Are they using `.tool_input.*` path (not `.input.*`)?
  3. Is `.claude/settings.json` present? (not `.local.json` — OMO may not read local)
  4. Test hooks with `python3 -c "import json; json.dump(...)" | bash script.sh` before suspecting OMO bridging issues
- **OMO's `claude_code.hooks: true` enables the bridge but may not support PreToolUse shell hooks** — if hooks never fire for subagent tasks but work for direct CC usage, this is an OMO limitation, not a config error
- **Model fallback chain format**: `model` (string) + `fallback_models` (array of strings or objects) — NOT `models` plural, NOT array for `model`
- **Renamed config**: it's `oh-my-openagent.jsonc` (not `oh-my-opencode.jsonc`) — easy to mix up
- **Worktree cleanup needed**: `gol/.worktrees/manual/test-harness-v2/` can be removed after confirming squash merge is stable
