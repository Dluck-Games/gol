# Decision 1 — 2026-04-05 00:00
**Trigger:** new_issue — Issue #239 首次进入调度队列
**Assessment:** 新 issue，无历史决策、计划或迭代记录。Issue 描述清晰，包含 Bug 复现路径、期望行为、可能原因分析及涉及文件列表。需要 @planner 先进行代码分析和方案设计。
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5v-turbo-ioa
**Guidance:** 分析准心显示逻辑与武器组件的绑定关系，产出可执行的修复方案。注意 issue 中提到的重命名建议作为可选优化项，不阻塞主修复。
**TL Context for @planner:**
> ## 任务：分析并设计 #239 准心 Bug 修复方案
>
> ### 问题背景
> 玩家不拥有远程武器（无 `CWeapon` 组件）时，`CrosshairView` 仍渲染准心。
>
> ### 必读文件
> - **Issue 完整描述**: `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/orchestration.md`（含可能原因和涉及文件）
> - **准心 UI**: `gol-project/scripts/ui/crosshair.gd` — 重点看 `_try_bind_entity()` 的绑定条件
> - **准心 ViewModel**: `gol-project/scripts/ui/crosshair_view_model.gd` — 数据绑定逻辑
> - **准心 System**: `gol-project/scripts/systems/s_crosshair.gd` — query 条件是否包含 `CWeapon`
> - **武器组件**: `gol-project/scripts/components/c_weapon.gd` — `CWeapon` 定义
>
> ### 分析要求
> 1. 确认 Bug 根因：是绑定条件缺失还是绘制逻辑未检查
> 2. 评估两种修复路径的优劣：
>    - 路径 A：在 `_try_bind_entity()` 增加对 `CWeapon` 的检查
>    - 路径 B：在 `_on_draw()` 中当 weapon == null 时跳过绘制
> 3. 评估 issue 提到的 `CWeapon → CShooterWeapon` 重命名影响范围
>
> ### 输出约束
> - 计划文档写入 `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/plans/` 目录
> - 使用中文撰写
> - 主修复方案必须具体到：改哪个函数、加什么判断、影响哪些文件
> - 重命名建议单独列为 optional task，不影响主修复的通过标准
