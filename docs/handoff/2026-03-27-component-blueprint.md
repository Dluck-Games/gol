# Handoff: Component Blueprint System (组件设计图机制)

Date: 2026-03-27
Session focus: Implement the full component blueprint unlock/crafting system with composer NPC, dialogue system, and MVVM UI

## User Requests (Verbatim)

- "执行组件设计图实现计划 — 使用 superpowers:subagent-driven-development skill 逐任务执行以下计划。"
- "选 3 — Full codebase alignment。理由：MVVM 是我们在设计阶段明确同意的（spec 中定义了 ViewModelDialogue 和 ViewModelComposer）。计划里跳过 ViewModel 是写 plan 时的简化遗漏，不是有意设计决策"
- "创建文档说明你的工作成果"

## Goal

PR #205 is merged → manual playtest the blueprint system in-game, then iterate on any issues found.

## Work Completed

- Implemented the full component blueprint system across 19 commits, 39 files, +1,466 lines
- Created PlayerData global data class (`scripts/gameplay/player_data.gd`) wired into GOL autoload
- Added 4 Config constants: DIALOGUE_RANGE=64, BLUEPRINT_DROP_CHANCE=0.1, CRAFT_COST=2, DISMANTLE_YIELD=1
- Created CBlueprint component with `@export var component_type: Script`
- Created DialogueData (Entry, Option, DialogueAction enum) + CDialogue component
- Implemented ComposerUtils with unlock_blueprint/craft_component/dismantle_component static functions
- Added CBlueprint early-exit branch in SPickup (detects blueprint → unlock → remove entity → skip normal box flow)
- Added `interact` input action (E key) to project.godot and Service_Input._watched_actions
- Created full MVVM dialogue system: ViewModel_Dialogue + View_Dialogue + dialogue.tscn
- Created full MVVM composer system: ViewModel_Composer + View_Composer + composer.tscn
- Created dialogue hint: ViewModel_DialogueHint + View_DialogueHint + dialogue_hint.tscn
- Implemented SDialogue system using Service_Input (not raw Input), proximity poll, option dispatch
- Created 4 blueprint recipes (weapon, tracker, healer, poison) + npc_composer recipe
- Added spawn logic in GOLWorld: composer NPC at campfire, 1-2 blueprints at BUILDING POIs
- Added 10% blueprint drop chance for enemies in SDamage._on_no_hp()
- Unit tests: 9 composer_utils + 3 blueprint pickup = 12 tests pass
- Integration test: 11 assertions pass in test_flow_composer_scene.gd
- Fixed implementer issues: Config.new() → Config static, load() → class_name references, int → DialogueData.DialogueAction
- PR created: https://github.com/Dluck-Games/god-of-lego/pull/205 (Closes #109)
- Worktree cleaned up, parent repo submodule updated and pushed

## Current State

- All code committed and pushed on `feat/component-blueprint` branch in gol-project submodule
- Parent repo (gol/) submodule reference updated to point to feature branch HEAD
- gol-project local working tree is on feat/component-blueprint (fast-forwarded from main)
- gol-project has one untracked file: `fix_issues.sh` (leftover from implementer, harmless)
- gol/ parent has untracked `.claude/skills/gol-issue/` and `docs/handoff/2026-03-26-...` (pre-existing)
- run-tests.command hardcodes `gol/` path so cannot run from worktree — tests were verified individually by subagents

## Pending Tasks

- **Merge PR #205** after review and manual playtest
- **Manual playtest**: find blueprint → return to camp → NPC dialogue → craft/dismantle
- **Potential follow-ups from playtest**: UI layout tuning, component_type serialization verification in .tres files

## Key Files

- `scripts/gameplay/player_data.gd` — PlayerData global data class (unlocked_blueprints, component_points, signals)
- `scripts/utils/composer_utils.gd` — Core logic: unlock_blueprint, craft_component, dismantle_component
- `scripts/systems/s_dialogue.gd` — Dialogue system: proximity poll, interact trigger, option dispatch
- `scripts/ui/views/view_dialogue.gd` — Dialogue View (MVVM, setup/bind/teardown lifecycle)
- `scripts/ui/views/view_composer.gd` — Composer View (MVVM, craft/dismantle lists with dynamic refresh)
- `scripts/gameplay/dialogue_data.gd` — DialogueData with Entry, Option, DialogueAction enum
- `scripts/gameplay/ecs/gol_world.gd` — Added _spawn_composer_npc(), _spawn_blueprints_at_building_pois()
- `scripts/systems/s_damage.gd` — Added _try_drop_blueprint() in _on_no_hp()
- `docs/superpowers/specs/2026-03-27-component-blueprint-design.md` — Design spec (reference)
- `docs/superpowers/plans/2026-03-27-component-blueprint.md` — Implementation plan (reference)

## Important Decisions

- **MVVM enforced over plan's simplification**: Plan originally skipped ViewModels for dialogue/composer. User explicitly chose full codebase alignment — ViewModel_Dialogue, ViewModel_Composer, ViewModel_DialogueHint all created
- **Service_Input used instead of raw Input**: Added "interact" action (E key) to project.godot + Service_Input._watched_actions. SDialogue uses `ServiceContext.input().pop_action_pressed("interact")`
- **class_name references over load()**: Subagent initially replaced all class_names with `load()` calls for worktree LSP compatibility. I reverted to class_name references (CDialogue, Config, ComposerUtils) — matches codebase convention
- **DialogueAction enum used instead of raw int**: Views and SDialogue use `DialogueData.DialogueAction` type, not magic int constants
- **Runtime setup for .tres non-serializable fields**: CDialogue.entries and CBlueprint.component_type are set at runtime in GOLWorld spawn methods (nested custom classes don't serialize in .tres)
- **CBlueprint.component_type**: Attempted .tres serialization via ext_resource → may work. Runtime fallback exists in _spawn_blueprint_box_at_position() and _try_drop_blueprint()
- **Config constants use `static var`**: DIALOGUE_RANGE, BLUEPRINT_DROP_CHANCE, CRAFT_COST, DISMANTLE_YIELD — NOT `const` (tunable at runtime)

## Constraints

- Config constants use `static var` (可调值), not `const` (不可调值)
- `interact` is a game input action for NPC dialogue, defined in project.godot (E key)
- Tests: unit tests use `extends GdUnitTestSuite` + `auto_free()`, integration tests use `extends SceneConfig`
- Worktree development pattern: create worktree at sibling directory, all work there, push submodule first, then parent repo

## Context for Continuation

- PR #205 is the active PR — merge target is main branch of Dluck-Games/god-of-lego
- Issue #109 tracks this feature — design spec and implementation plan are in docs/superpowers/
- NPC has GOAP goals: Survive + Wander only (no attack actions) — non-combat NPC that flees from threats
- Composer NPC has CHP=30 (killable by enemies) — protecting NPC is a gameplay pressure
- Component points economy: dismantle gives 1 point, craft costs 2 points (intentional resource pressure)
- gol-project local is currently on feat/component-blueprint (not main) — merge PR first, then `git checkout main && git pull` to sync
- The .tres files for blueprints reference component scripts via ext_resource — Godot editor may regenerate these files with UIDs when it loads them

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
