# Decision 3 — 2026-04-05 12:55
**Trigger:** @coder 完成 implement，产出迭代文档 `02-coder-fix-crosshair-weapon-check.md`
**Assessment:** Coder 已完成全部计划实施。修改 3 个文件（`s_crosshair.gd`、`crosshair.gd`、`s_track_location.gd`），新增 2 个测试文件（`test_crosshair_view.gd`、`test_crosshair.gd`）。测试契约 T1-T7、T9-T10 全部覆盖，T8 有合理偏差说明（System 层 query 保持 `[CAim]` 不加 CWeapon 是正确的架构决策）。代码未实际运行测试（环境限制），需 reviewer 验证代码质量 + 测试完整性后进入 CI。
**Action:** spawn @reviewer
**Task:** full-review
**Model:** glm-5v-turbo-ioa
**Guidance:** 审查 coder 的 3 处改动 + 2 个测试文件。重点关注：T8 偏差是否合理、STrackLocation 同步修复正确性、测试断言充分性、对话系统兼容性。
**TL Context for @reviewer:**
> ## 任务：全量审查 #239 准心 Bug 修复实现
>
> ### 审查范围
>
> **修改文件（必须逐行审查）：**
> - `scripts/systems/s_crosshair.gd` — `_update_display_aim()` 中 display_aim_position 赋值移到 weapon null check 之后 + 无效坐标设置
> - `scripts/ui/crosshair.gd` — `_try_bind_entity()` query 加 CWeapon + `_process()` 武器丢失检测 + `_on_draw()` null 守卫
> - `scripts/systems/s_track_location.gd` — 与 s_crosshair 相同模式的同步修复
>
> **新增文件（审查测试质量和覆盖率）：**
> - `tests/unit/ui/test_crosshair_view.gd` — T1-T5（绑定/解绑/绘制）
> - `tests/unit/system/test_crosshair.gd` — T6-T10（System 层逻辑）
>
> ### 必读文档
> 1. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/plans/01-planner-crosshair-no-weapon-fix.md` — 原始计划和测试契约（T1-T8 定义）
> 2. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/02-coder-fix-crosshair-weapon-check.md` — Coder 交接文档，含偏差说明和决策记录
> 3. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/orchestration.md` — Issue 原始需求
>
> ### 审查重点
> 1. **T8 偏差的合理性**: Coder 选择 System 层 query 保持 `with_all([CAim])` 不加 CWeapon，理由是 SCrosshair 需处理所有 CAim 实体。确认这是否符合架构设计（System 层处理宽、UI 层过滤窄）。
> 2. **STrackLocation 修复一致性**: 确认修复模式与 s_crosshair 完全对称，无遗漏。
> 3. **测试充分性**: 新增测试是否覆盖了边界条件（null entity、武器丢失帧、对话系统交互）。
> 4. **对话系统兼容性**: `_process()` 中武器丢失检测的 unbind 是否会与 `SDialogue._set_crosshair_visible()` 冲突——coder 文档称每帧重试保证 rebind，需验证时序。
> 5. **回归风险**: 改动是否影响现有 CWeapon 相关功能（如 `test_fire_bullet.gd`）。
>
> ### 审判标准
> - **pass**: 所有核心改动正确、测试充分、无回归风险 → 可进入 CI
> - **rework**: 存在 bug 或遗漏 → 列出具体问题，指明需要改的函数/行号
> - **major-issue**: 架构性问题 → 回退到 planner 重新设计方案
>
> ### 输出要求
> - 审查结论写入 `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/03-reviewer-review.md`
> - 使用中文
> - rework 时 TL Context 必须包含具体文件路径和修改点，不可泛泛而谈
