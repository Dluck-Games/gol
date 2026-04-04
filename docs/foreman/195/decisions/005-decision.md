# Decision 5 — 2026-04-04 12:10
**Trigger:** doc_validation_failed — 框架报告计划文档校验失败（缺少必需章节）
**Assessment:** 触发事件为 `doc_validation_failed`，声称计划文档缺少需求分析、影响面分析、实现方案、架构约束、测试契约、风险点、实现步骤等章节。经人工审查，`plans/01-planner-freeze-animation-loss.md` 实际包含全部 7 个必需章节（第1-7章），内容完整且质量高：

- **根因分析充分**：定位 3 个 Bug（Bug-1 CRITICAL 无敌帧阻塞解冻恢复 / Bug-2 MODERATE max_speed 未恢复 / Bug-3 MINOR velocity 未重置）
- **代码定位精确**：给出具体文件路径+行号（`s_animation.gd:68-72` / `s_elemental_affliction.gd:186-195`）
- **修复方案可操作**：提供完整 before→after 代码 diff
- **测试契约清晰**：现有 T1-T7 + 新增 T8/T9/T10 覆盖空白场景
- **风险评估完整**：5 个风险点均有缓解措施

框架校验可能存在误判（章节标题格式或结构匹配问题）。计划文档实质内容满足下游 agent 执行要求，无需回退 planner 重做。
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**Guidance:** 按计划文档顺序执行：先修 Bug-1（s_animation.gd）→ 再修 Bug-2（s_elemental_affliction.gd）→ 补充单元测试。每步完成后运行测试确认无回归。
**TL Context for @coder:**
> ## Issue #195 — 冻结伤害后移动动画丢失 — 实现任务
>
> ### 背景
> Planner 已完成根因分析并产出详细修复计划。需按计划实施 2 处代码修改 + 3 个新增测试用例。
>
> ### 必读文档（按顺序）
> 1. **`docs/foreman/195/plans/01-planner-freeze-animation-loss.md`** — 主计划文档，包含完整根因分析、代码 diff、测试规范
> 2. **`docs/foreman/195/iterations/01-planner-handoff-freeze-animation-loss.md`** — 交接文档，推荐阅读顺序和关键注意点
>
> ### 实施步骤
>
> **Step 1 — 修 Bug-1 [CRITICAL]: s_animation.gd**
> - 文件：`scripts/systems/s_animation.gd`
> - 位置：`_update_animation()` 方法，约 line 68-77
> - 变更：将解冻恢复逻辑（`sprite.paused = false` + `animation_was_paused = false`）提升到无敌帧 `return` **之前**
> - 计划第 3 章有完整 before→after 代码 diff，直接参考
> - 约束：不改变动画选择逻辑、不改变翻转向量更新逻辑，仅做 unpause 操作
>
> **Step 2 — 修 Bug-2 [MODERATE]: s_elemental_affliction.gd**
> - 文件：`scripts/systems/s_elemental_affliction.gd`
> - 位置：`_apply_movement_modifiers()` 方法，约 line 190-194（冻结结束的 if 块）
> - 变更：在 `movement.forbidden_move = false` 之后添加 `movement.max_speed = base_speed`
> - 计划第 3 章有完整 diff
>
> **Step 3 — 补充单元测试**
> - 文件：`tests/unit/system/test_animation_freeze_recovery.gd`
> - 新增 3 个用例：
>   - **T8** `test_unfreeze_during_invincibility_recovers_sprite()` — 冻结中受伤(invincible_time>0) → 冻结结束 → sprite 应恢复播放
>   - **T9** `test_post_invincibility_anim_resumes()` — 无敌帧结束后动画正常选择 walk/idle
>   - **T10** `test_unfreeze_restores_max_speed()` — 解冻后 max_speed == base_max_speed
> - 保持与现有 T1-T7 一致的 mock 风格（手动构建 Entity + Component + System + process() 断言）
> - 详细用例规范见计划第 5 章"测试契约"
>
> ### 约束
> - 工作目录：`/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260404120254._43e08cab`
> - 所有文件修改在此 worktree 中进行
> - 不执行 git add / commit / push（由框架处理）
> - 不创建 PR（由框架处理）
> - 修改后运行 `tests/unit/system/test_animation_freeze_recovery.gd` 确认所有用例通过（含新旧）
> - 运行 Phase 1 全量单元测试确认无回归
