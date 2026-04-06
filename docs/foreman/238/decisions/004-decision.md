# Decision 4 — 2026-04-06 01:50
**Trigger:** Reviewer 完成交接文档 `03-reviewer-crosshair-element-type.md`，结论为 **rework**
**Assessment:** Reviewer 完成了第 1 轮全量审查，结论为 **rework**（需修复后重新审查）。发现 3 个问题：
- **#1 [Important / 阻塞合并]**：`crosshair_view_model.gd:29-33` 的 else 分支缺少 `element_type.unbind()` 调用，导致组件移除后 ViewModel 残留对已脱离实体组件的旧 observable 绑定。修复量：1 行插入。
- **#2 [Minor / 推荐]**：重绑定 aim_position/spread_ratio 时产生冗余 Warning 日志。可优化 `_try_bind_entity` 为选择性重绑定。
- **#3 [Minor / 后续迭代]**：R2 检测逻辑缺 Integration 测试覆盖，建议后续补充。

问题 #1 是代码层面的遗漏（非架构设计缺陷），属于 coder 可直接修复的范畴。无需回退 planner 重设计方案。
**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** 修复 Reviewer 报告的 #1（必须）和 #2（推荐），保持其余代码不变。
**TL Context for @coder:**
> ## Issue #238 — 准心 UI 展示元素伤害类型：Rework 修复任务
>
> ### 背景
> Reviewer 第 1 轮审查结论为 **rework**，发现代码中存在 1 个阻塞合并的问题和 2 个建议优化项。你需要修复这些问题。
>
> ### 必须修复（阻塞合并）
>
> **问题 #1：`bind_to_entity` else 分支缺少 `element_type.unbind()`**
>
> - **文件**：`scripts/ui/crosshair_view_model.gd`，第 29-33 行附近
> - **原因**：当实体从「拥有 CElementalAttack」变为「失去该组件」时（如切换武器），else 分支仅执行 `element_type.set_value(-1)` 但未断开旧绑定，导致残留对已脱离实体的组件 observable 的信号连接。
> - **修复**：在 else 分支的 `set_value(-1)` 之前添加 `element_type.unbind()`：
> ```gdscript
> else:
>     element_type.unbind()       # 先断开旧绑定
>     element_type.set_value(-1)   # 再设为 NONE
> ```
>
> ### 建议修复（不阻塞但推荐）
>
> **问题 #2：冗余 Warning 日志**
>
> - **文件**：`scripts/ui/crosshair.gd`，`_try_bind_entity()` 方法（约第 99-100 行）
> - **原因**：检测到 CElementalAttack 变化时调用完整的 `bind_to_entity()` 会重新绑定 aim_position 和 spread_ratio，触发 `observable_property.gd` 的 Warning 日志。
> - **推荐方案 A（最小改动）**：将 `_try_bind_entity` 中对 `bind_to_entity` 的调用改为只处理 element_type 的选择性重绑定，避免重复绑定 aim_position/spread_ratio。
>
> ### 不需要修改的内容
> - 问题 #3（R2 测试缺失）标记为后续迭代处理，本次不修
> - 计划文档中的其他内容不需要改动
>
> ### 约束
> - 只修改上述 2 个文件（crosshair_view_model.gd 和 crosshair.gd）
> - 不要执行 git 操作（add/commit/push），由框架处理
> - 修复完成后确认文件状态正确即可
>
> ### 参考文档
> - 完整审查报告：`docs/foreman/238/iterations/03-reviewer-crosshair-element-type.md`
> - 计划文档：`docs/foreman/238/plans/01-planner-crosshair-element-type.md`
