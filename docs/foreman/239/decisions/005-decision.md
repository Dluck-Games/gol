# Decision 5 — 2026-04-05 13:25
**Trigger:** @reviewer 完成 rework-review（Decision 4 重试），产出审查文档 `03-reviewer-review.md`，结论为 **rework（仅测试质量）**
**Assessment:** Reviewer 对生产代码给出明确 PASS 判定——三处源码修复（`s_crosshair.gd`、`crosshair.gd`、`s_track_location.gd`）全部符合 Planner 方案，T8 偏差合理，对话系统兼容性安全，无回归风险。

Rework 范围严格限定为测试质量：当前 10 个单元测试（T1-T10）均不调用被测方法，而是在测试内部复制生产代码逻辑后断言，不具备回归防护能力。Reviewer 要求至少补充一个调用真实方法的集成级测试，或说明不可行原因并标注 TODO。

调度轮次仍处早期（本轮为首次 coder rework），问题范围明确且可操作。
**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** 生产代码无需修改，仅针对测试质量进行 rework。Reviewer 已给出具体修改建议和优先级排序。
**TL Context for @coder:**
> ## 任务：#239 准心 Bug 修复 — 测试质量 Rework
>
> ### 背景
> Reviewer（第3轮审查）对生产代码判定 **PASS**，但对测试代码判定 **REWORK**。你只需要改进测试文件，不要动任何生产代码。
>
> ### 核心问题
> 当前 `tests/unit/ui/test_crosshair_view.gd`（T1-T5）和 `tests/unit/system/test_crosshair.gd`（T6-T10）共 10 个测试，**均不调用被测方法**，而是在测试内部复制生产代码逻辑再断言。如果未来有人回滚修复代码，这些测试仍会通过——它们验证的是自身逻辑副本，而非生产代码路径。
>
> 根因：`_update_display_aim()` 依赖 `entity.get_viewport()`、`_try_bind_entity()` 依赖 `ECS.world.query`——纯 gdUnit4 环境中不可用。
>
> ### Rework 要求（按优先级）
>
> **P0 — 至少一个真实方法调用测试**
> - 在 `tests/unit/system/test_crosshair.gd` 中，尝试构造最小可行环境调用 `system._update_display_aim(entity, aim, delta)`
> - 如果 gdUnit4 无法提供 viewport mock / ECS world mock：
>   - 在对应测试顶部用注释说明限制原因并标注 `TODO: 需 SceneConfig 集成测试覆盖此路径`
>   - 但必须至少尝试一次，证明你确实尝试过而非直接放弃
>
> **P1 — T6/T7/T9/T10 优先改善**
> - 这些 System 层测试目前完整复制了 `_update_display_aim()` 的 weapon-null 分支逻辑
> - 尝试将断言改为验证 system 内部状态变化（如 `display_aim_position` 的值），而非在测试中重新实现分支判断
>
> **P2 — T1-T3 绑定测试**
> - 可考虑使用 GECS 框架的 mock 能力（如果有）来测试真实的 `_try_bind_entity()` 路径
> - 如不可行，保留现有测试但在文件头部注释中注明："纯单元测试限制：无法 mock ECS.world.query，本测试作为行为契约文档记录期望行为，真实路径覆盖依赖 SceneConfig 集成测试"
>
> ### 必读文档
> 1. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/03-reviewer-review.md` — 完整审查报告，含逐项验证表和 Rework TL Context
> 2. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/02-coder-fix-crosshair-weapon-check.md` — Coder 原始交接文档（了解哪些是生产代码，不要改）
> 3. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/plans/01-planner-crosshair-no-weapon-fix.md` — Planner 原始计划中的测试契约定义
>
> ### 约束
> - **禁止修改以下生产代码文件**：`scripts/systems/s_crosshair.gd`、`scripts/ui/crosshair.gd`、`scripts/systems/s_track_location.gd`
> - 仅允许修改/重写：`tests/unit/ui/test_crosshair_view.gd` 和 `tests/unit/system/test_crosshair.gd`
> - 测试 ID 编号保持不变（T1-T10），方便与 Planner 契约对照
> - 输出交接文档到 `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/04-coder-rework-test-quality.md`
