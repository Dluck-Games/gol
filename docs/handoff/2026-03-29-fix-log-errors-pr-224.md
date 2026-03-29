# Handoff: Fix Log Errors PR 224

Date: 2026-03-29
Session focus: Fix runtime/test log regressions in `gol-project`, merge PR #224, and preserve constraints for future follow-up.

## User Requests (Verbatim)

- 请你拾取 https://github.com/Dluck-Games/god-of-lego/issues 里的所有 log 错误的 issue，提交一个 PR 修复他们。不仅包括运行时日志报错，还包括跑测试时产生的报错，warning 等等。需要从根本修复，而不是遮掩问题。使用 worktree 来工作，不影响主工作区。
- 继续
- 我不希望修改 world.gd 和 entity.gd，他们是插件级别的，不应该修改
- 帮我合入这个 PR，然后 /handoff-doc 记录这次工作

## Goal

If this work continues, the next step is to investigate the remaining Godot process-exit resource leak logs without touching GECS plugin files.

## Work Completed

- I created and worked inside the isolated submodule worktree `gol/.worktrees/manual/fix-log-errors` on branch `fix/log-errors`.
- I opened and then merged PR #224: `https://github.com/Dluck-Games/god-of-lego/pull/224`.
- I fixed project-level test import noise in `project.godot` by replacing autoload UID references with stable resource paths.
- I fixed AI debug bridge test log pollution in `scripts/debug/ai_debug_bridge.gd`, `tests/unit/debug/ai_debug_bridge_test_doubles.gd`, and `tests/unit/debug/test_ai_debug_bridge.gd`.
- I added stale-entity/freed-node guards in `scripts/systems/s_dead.gd`, `scripts/systems/s_dialogue.gd`, and `scripts/systems/s_elemental_visual.gd` to address runtime log errors around death, dialogue, and elemental cleanup.
- I reduced UI/test log noise and made teardown behavior more deterministic in `scripts/services/impl/service_ui.gd`, `scripts/ui/observable_property.gd`, and `tests/unit/service/test_service_ui.gd`.
- I cleaned up console-related test fixtures in `tests/unit/service/console_test_utils.gd` and `tests/unit/service/test_service_console.gd` so command tests no longer create orphan-node noise.
- I cleaned up unit fixture ownership in `tests/unit/system/test_s_move.gd` and `tests/unit/test_flow_combat.gd`.
- I updated `tests/integration/test_bullet_flight.gd` to match the current lifetime system and current expected travel window, and removed expected-no-PCG warnings from `scripts/gameplay/ecs/gol_world.gd`.
- I temporarily edited `addons/gecs/ecs/world.gd` and `addons/gecs/ecs/entity.gd` while chasing exit-only leaks, but after your constraint I reverted those changes in commit `256464c` so the merged PR does **not** modify GECS plugin files.

## Current State

- PR #224 is merged into `main`.
- Merge commit: `9c3ab3f2119f1a5d69d9c26346b6054848f1e619`.
- The merged branch contains only project-level file changes; `addons/gecs/ecs/world.gd` and `addons/gecs/ecs/entity.gd` were explicitly removed from the PR before merge.
- Key targeted validations passed after the plugin-file revert:
  - `tests/unit/debug/test_ai_debug_bridge.gd`
  - `tests/unit/service/test_service_ui.gd`
  - `tests/unit/service/test_service_console.gd`
  - `tests/unit/system/test_dead_system.gd`
  - `tests/integration/test_bullet_flight.gd`
  - `tests/integration/flow/test_flow_composer_interaction_scene.gd`
- Full integration assertions passed, but there are still process-exit-only Godot logs in some runs (`ObjectDB instances leaked at exit` / `resources still in use at exit`).
- Current uncommitted state in the local worktree is only untracked `.uid` files produced locally during test/editor runs.

## Pending Tasks

- Investigate the remaining Godot process-exit leak logs while staying entirely in project-owned files.
- Avoid reintroducing any modifications under `addons/gecs/ecs/` unless the user explicitly changes that constraint.
- Optionally clean the local worktree’s untracked `.uid` files if this worktree is going to be kept around.

## Key Files

- `project.godot` — autoload path fix to remove import-time UID errors in tests
- `scripts/debug/ai_debug_bridge.gd` — JSON parse / stale command guard log cleanup
- `scripts/systems/s_dead.gd` — player/campfire death stale-entity guards
- `scripts/systems/s_dialogue.gd` — typed player query and dialogue cleanup safety
- `scripts/systems/s_elemental_visual.gd` — freed-node / missing-entry safety for elemental visuals
- `scripts/services/impl/service_ui.gd` — deterministic UI teardown behavior during tests
- `scripts/ui/observable_property.gd` — observable binding cleanup adjustments
- `tests/unit/service/test_service_console.gd` — console fixture ownership cleanup
- `tests/unit/service/test_service_ui.gd` — UI service tests updated to avoid intentional engine-error logs
- `tests/integration/test_bullet_flight.gd` — updated integration contract for current bullet lifetime/travel behavior

## Important Decisions

- I treated the user’s original request as both runtime-log fixing and test-log fixing, not just issue triage.
- I used a dedicated worktree to avoid touching the main working copy.
- I preserved the project-level fixes but removed plugin-level GECS edits after the explicit constraint against changing `world.gd` and `entity.gd`.
- I merged PR #224 after verifying GitHub checks were green and the PR merge state was `CLEAN`.

## Constraints

- 使用 worktree 来工作，不影响主工作区。
- 我不希望修改 world.gd 和 entity.gd，他们是插件级别的，不应该修改

## Context for Continuation

- The merged PR fixed the actionable runtime/test log regressions that were inside project-owned code and test fixtures.
- The remaining unsolved noise is narrower: Godot process-exit leak logs that still appear in some full-suite or scene-teardown runs.
- The most important continuation rule is to keep future fixes scoped to project files such as `scripts/services/`, `scripts/ui/`, `scripts/gameplay/ecs/`, and tests; do not touch `addons/gecs/ecs/world.gd` or `addons/gecs/ecs/entity.gd` unless the user explicitly approves it later.
- The local worktree still has many untracked `.uid` files from running tests; they were intentionally not committed.

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
