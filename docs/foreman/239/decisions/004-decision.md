# Decision 4 — 2026-04-05 13:11
**Trigger:** @reviewer 完成 full-review，但未产出预期审查文档（`03-reviewer-review.md` 缺失）。触发事件仅引用了 coder 交接文档，无 reviewer 结论。
**Assessment:** Reviewer agent 执行完成但未按预期写入审查结论文档。iterations 目录中仅有 `01-planner-handoff-crosshair-fix.md` 和 `02-coder-fix-crosshair-weapon-check.md` 两份文档，缺少 reviewer 的 pass/rework/major-issue 判决输出。无法基于现有信息判断代码质量是否通过审查标准。调度轮次仍处于早期（本轮为第 2 次 review 尝试），应重试 reviewer 并要求其必须产出书面审查文档。
**Action:** spawn @reviewer
**Task:** rework-review
**Model:** glm-5v-turbo-ioa
**Guidance:** 上一次 reviewer 未产出审查文档，本次必须完成全量审查并写出书面结论。审查范围和重点不变。
**TL Context for @reviewer:**
> ## 任务：重新审查 #239 准心 Bug 修复实现（必须产出书面文档）
>
> ### 背景
> 上一次 review 调度未产出审查文档（`03-reviewer-review.md` 缺失），本次为重试。请务必在完成审查后将结论写入指定路径。
>
> ### 审查范围（与首次审查一致）
>
> **修改文件（逐行审查）：**
> - `scripts/systems/s_crosshair.gd` — `_update_display_aim()` 中 display_aim_position 赋值移到 weapon null check 之后 + 无效坐标设置
> - `scripts/ui/crosshair.gd` — `_try_bind_entity()` query 加 CWeapon + `_process()` 武器丢失检测 + `_on_draw()` null 守卫
> - `scripts/systems/s_track_location.gd` — 与 s_crosshair 相同模式的同步修复
>
> **新增测试文件（审查质量和覆盖率）：**
> - `tests/unit/ui/test_crosshair_view.gd` — T1-T5（绑定/解绑/绘制）
> - `tests/unit/system/test_crosshair.gd` — T6-T10（System 层逻辑）
>
> ### 必读文档（按顺序阅读）
> 1. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/plans/01-planner-crosshair-no-weapon-fix.md` — 原始计划和测试契约 T1-T8 定义
> 2. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/02-coder-fix-crosshair-weapon-check.md` — Coder 交接文档，含偏差说明（T8 部分覆盖的决策理由）和决策记录
> 3. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/orchestration.md` — Issue 原始需求
>
> ### 审查重点
> 1. **T8 偏差合理性**: Coder 选择 System 层 query 保持 `with_all([CAim])` 不加 CWeapon，理由是 SCrosshair 需处理所有 CAim 实体。确认这符合架构设计（System 处理宽、UI 过滤窄）。
> 2. **STrackLocation 修复一致性**: 确认修复模式与 s_crosshair 对称无遗漏。
> 3. **测试充分性**: 新增测试是否覆盖边界条件（null entity、武器丢失帧、对话系统交互）。
> 4. **对话系统兼容性**: `_process()` 武器丢失检测 unbind 是否与 `SDialogue._set_crosshair_visible()` 冲突——coder 称每帧重试保证 rebind，需验证时序。
> 5. **回归风险**: 改动是否影响现有 CWeapon 相关功能（如 `test_fire_bullet.gd`）。
>
> ### 审判标准
> - **pass**: 核心改动正确、测试充分、无回归风险 → 可进入 CI
> - **rework**: 存在 bug 或遗漏 → 列出具体问题，指明函数/行号和修改建议
> - **major-issue**: 架构性问题 → 回退到 planner 重新设计方案
>
> ### 输出要求（强制）
> - **必须将审查结论写入**: `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/03-reviewer-review.md`
> - 使用中文撰写
> - rework 时 TL Context 必须包含具体文件路径和修改点
> - 文档必须包含明确的 pass/rework/major-issue 判决
