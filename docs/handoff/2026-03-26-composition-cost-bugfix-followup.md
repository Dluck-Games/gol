# Handoff: Composition Cost Bugfix Followup

Date: 2026-03-26
Session focus: I fixed the reported composition-cost combat/status regressions, committed the work on the issue branch, and verified the fixes in both automated tests and live runtime.

## User Requests (Verbatim)

- [search-mode]
MAXIMIZE SEARCH EFFORT. Launch multiple background agents IN PARALLEL:
- explore agents (codebase patterns, file structures, ast-grep)
- librarian agents (remote repos, official docs, GitHub examples)
Plus direct tools: Grep, ripgrep (rg), ast-grep (sg)
NEVER stop at first result - be exhaustive.

---

请阅读 composition-cost 的 handoff 文档，了解需求之前的实现细节，然后为我修复如下几个我已发现的 bug 以及体验优化。

[Pasted ~7 lines] bug 1 - 开局所有人都在闪烁，身上有毒药（或者是 healer）的特效持续闪烁，永不消失。

bug 2 - 偶现攻击敌人无法造成伤害，连锁效果是敌人持续播放移动动画但实际无法移动，一旦另一个敌人来到附近，攻击造成元素伤害后，两个敌人移动一起都恢复正常，但恢复后依旧无法通过子弹造成伤害。

Bug 3 - 医疗效果可能过于猛，玩家受到多个敌人攻击无法死亡。并且出生似乎自带医疗效果，身上拥有绿色粒子特效。

体验优化：当电击效果造成弹道射击抖动时，准心依旧要显示的准确，并且带有电击特效告诉玩家电击效果影响了准心。否则追踪器依旧把准心锁在敌人身上，而玩家的子弹乱跳，不能明显察觉到电击影响准头的机制的存在。

- 先在当前 PR 所在分支上提交一版，然后进行一次完整的 E2E 验证，确保我说的问题不再出现了。
- 创建交接文档，并把修复记录 comments 在 issue 的评论区，需要包含问题产生的根本原因，以及你的处理方式。

## Goal

Continue from a fully committed local fix set on issue branch `feature/issue-108-composition-cost`, push/comment/update parent repo if needed, and preserve the exact root-cause and verification context for issue `#108`.

## Work Completed

- I read the existing context in `docs/handoff/2026-03-25-composition-cost.md`, `docs/handoff/2026-03-25-composition-cost-verification.md`, `docs/superpowers/specs/2026-03-24-composition-cost-design.md`, and `docs/superpowers/plans/2026-03-24-composition-cost.md` before touching code.
- I traced the reported bugs to the composition-cost aura/modifier path and found that `CAreaEffect` was still effectively applying every compatible companion component on the source entity, which let healer/poison setups leak unintended behaviors.
- I added explicit channel selection to `gol-project/scripts/components/c_area_effect.gd` and enforced it in `gol-project/scripts/systems/s_area_effect_modifier.gd` so aura sources can opt into only heal, poison, or melee effects.
- I corrected recipe behavior in `gol-project/resources/recipes/enemy_poison.tres`, `gol-project/resources/recipes/materia_damage.tres`, `gol-project/resources/recipes/materia_heal.tres`, and `gol-project/resources/recipes/survivor_healer.tres` so healer entities no longer apply unintended damage aura and poison no longer targets allied enemies.
- I fixed status/area-effect visuals in `gol-project/scripts/systems/s_area_effect_modifier_render.gd` and hit-flash cleanup in `gol-project/scripts/systems/s_damage.gd`, which removed the spawn-time permanent flicker / lingering fog symptoms.
- I made electric spread truthful in the UI by sharing spread state through `gol-project/scripts/components/c_aim.gd`, consuming it in `gol-project/scripts/systems/s_fire_bullet.gd`, and reflecting it in `gol-project/scripts/systems/s_crosshair.gd`, `gol-project/scripts/systems/s_track_location.gd`, `gol-project/scripts/ui/crosshair.gd`, and `gol-project/scripts/ui/crosshair_view_model.gd`.
- I fixed the fallback bullet-targeting path in `gol-project/scripts/systems/s_damage.gd` so the direct physics query excludes the bullet itself instead of self-hitting and disappearing without dealing damage.
- During live E2E I uncovered a second class of bugs unrelated to the original aura logic: respawn-time stale entity references across ECS/UI loops. I added defensive `is_instance_valid()` guards in the relevant runtime systems, including `gol-project/scripts/systems/s_weight_penalty.gd`, `gol-project/scripts/systems/s_presence_penalty.gd`, `gol-project/scripts/systems/s_fire_heal_conflict.gd`, `gol-project/scripts/systems/s_cold_rate_conflict.gd`, `gol-project/scripts/systems/s_electric_spread_conflict.gd`, `gol-project/scripts/systems/s_area_effect_modifier.gd`, `gol-project/scripts/systems/s_healer.gd`, `gol-project/scripts/systems/s_ai.gd`, `gol-project/scripts/systems/s_animation.gd`, `gol-project/scripts/systems/s_camera.gd`, `gol-project/scripts/systems/s_collision.gd`, `gol-project/scripts/systems/s_crosshair.gd`, `gol-project/scripts/systems/s_pickup.gd`, `gol-project/scripts/systems/s_perception.gd`, `gol-project/scripts/systems/s_move.gd`, `gol-project/scripts/systems/s_melee_attack.gd`, `gol-project/scripts/systems/s_hp.gd`, `gol-project/scripts/systems/s_life.gd`, `gol-project/scripts/systems/s_trigger.gd`, `gol-project/scripts/systems/s_elemental_affliction.gd`, `gol-project/scripts/systems/ui/s_ui.gd`, `gol-project/scripts/systems/ui/s_ui_hpbar.gd`, and `gol-project/scripts/ui/crosshair.gd`.
- I committed the work directly on the current PR branch in `gol-project` as a stack of semantic commits; the branch is now ahead of origin by 13 commits.

## Current State

- The active submodule branch is `feature/issue-108-composition-cost`, which is the issue branch for `#108`.
- `gol-project` is currently clean according to `git status --porcelain`.
- Recent local commit stack includes the bugfix and runtime-hardening commits through `09a603e fix(ui): avoid stale entity refs after respawn`.
- Automated verification passed:
  - `gol-project/tests/unit/system/test_area_effect_modifier.gd` — 23/23
  - `gol-project/tests/unit/system/test_fire_bullet.gd` — 2/2
  - `gol-project/tests/unit/system/test_damage_system.gd` — 2/2
  - `gol-project/tests/unit/system/test_area_effect_modifier_render.gd` — 2/2
  - `gol-project/tests/unit/system/test_electric_spread_conflict.gd` — 3/3
  - `gol-project/tests/integration/flow/test_flow_composition_cost_scene.gd` — 30/30
  - `gol-project/tests/integration/flow/test_flow_elemental_status_scene.gd` — 8/8
  - `gol-project/tests/integration/test_combat.gd` — 3/3
- Live runtime verification also passed for the originally requested symptoms:
  - fresh spawn screenshots showed no global blinking, no green poison fog, and no healer aura on spawn
  - forced player death/respawn no longer crashed the running `main.tscn` session
  - after the final respawn smoke test, grep for `handle_crash|SCRIPT ERROR` in `/tmp/gol_e2e_fix.log` returned no matches
- Uncommitted changes: none in `gol-project` at the time I wrote this handoff.

## Pending Tasks

- Push the 13 local `gol-project` commits to `origin/feature/issue-108-composition-cost` if the user wants the PR branch updated remotely.
- Post or update the issue comment on `#108` with the root-cause and fix summary if it has not been posted yet from the current session.
- If submodule synchronization is desired, update the parent repo `gol/` to the new `gol-project` submodule pointer and commit that separately after pushing the submodule.

## Key Files

- `docs/handoff/2026-03-25-composition-cost.md` — prior implementation handoff for the base feature work
- `docs/handoff/2026-03-25-composition-cost-verification.md` — prior verification handoff for the pre-bugfix state
- `docs/superpowers/specs/2026-03-24-composition-cost-design.md` — issue-linked design source of truth for `#108`
- `gol-project/scripts/components/c_area_effect.gd` — new explicit aura channel-selection data model
- `gol-project/scripts/systems/s_area_effect_modifier.gd` — aura effect application logic and respawn-time target guarding
- `gol-project/scripts/systems/s_damage.gd` — hit-flash cleanup and fallback bullet self-filtering
- `gol-project/scripts/systems/s_area_effect_modifier_render.gd` — fog lifecycle cleanup and stale-view cleanup
- `gol-project/scripts/components/c_aim.gd` — shared runtime spread/display state for electric aim truthfulness
- `gol-project/scripts/ui/crosshair.gd` — final crosshair rebinding and visual electric spread presentation
- `gol-project/tests/integration/flow/test_flow_composition_cost_scene.gd` — strongest integration coverage for the corrected aura/recipe behavior

## Important Decisions

- I chose to solve the healer/poison bug at the source by making `CAreaEffect` explicitly opt into channels instead of trying to special-case each recipe in systems.
- I treated the electric reticle problem as a truthfulness issue, so the UI now reflects the same spread state the weapon firing path consumes instead of animating an unrelated cosmetic shake.
- I kept the later respawn/stale-entity fixes even though they were discovered during E2E rather than in the original report, because they were blocking clean live verification and were clearly real runtime defects.
- I used multiple small commits on the issue branch rather than one large commit so aura behavior, combat fixes, UI truthfulness, tests, and runtime hardening remain independently reviewable.

## Constraints

- [search-mode]
MAXIMIZE SEARCH EFFORT. Launch multiple background agents IN PARALLEL:
- explore agents (codebase patterns, file structures, ast-grep)
- librarian agents (remote repos, official docs, GitHub examples)
Plus direct tools: Grep, ripgrep (rg), ast-grep (sg)
NEVER stop at first result - be exhaustive.

- [analyze-mode]
ANALYSIS MODE. Gather context before diving deep:

CONTEXT GATHERING (parallel):
- 1-2 explore agents (codebase patterns, implementations)
- 1-2 librarian agents (if external library involved)
- Direct tools: Grep, AST-grep, LSP for targeted searches

IF COMPLEX - DO NOT STRUGGLE ALONE. Consult specialists:
- **Oracle**: Conventional problems (architecture, debugging, complex logic)
- **Artistry**: Non-conventional problems (different approach needed)

SYNTHESIZE findings before proceeding.

- 创建交接文档，并把修复记录 comments 在 issue 的评论区，需要包含问题产生的根本原因，以及你的处理方式。

## Context for Continuation

- The relevant GitHub issue is `#108`, and the current open PR branch is `feature/issue-108-composition-cost`.
- The issue already contains the user’s March 25 bug report as a comment, so a good follow-up comment should explicitly answer those four reported problems one by one with root cause + fix + verification.
- If continuing from here, the next safe operational steps are: push the `gol-project` branch, post the issue comment, then optionally update the parent `gol/` submodule pointer.
- The live E2E is now strong enough to cite concretely: spawn visuals were clean, forced respawn no longer crashed the game, and `/tmp/gol_e2e_fix.log` was clean for `handle_crash|SCRIPT ERROR` after the final respawn test.
- Be careful to work in `gol-project/` for game-code git operations, then update the parent repo separately only after the submodule branch is pushed.

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
