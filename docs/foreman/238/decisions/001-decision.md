# Decision 1 — 2026-04-06 00:00
**Trigger:** 新 issue #238 — feat(crosshair): 在准心 UI 展示当前元素伤害类型
**Assessment:** 首次调度。Issue 描述清晰：需要在准心 UI 展示玩家当前的元素伤害类型（FIRE/WET/COLD/ELECTRIC），数据来源为 `CElementalAttack.element_type` 组件，展示层为 `CrosshairView` / `CrosshairViewModel`。Issue 已标注涉及的文件路径和组件，但尚无实现方案或架构设计。需要 planner 先分析现有代码并产出实现计划。
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5v-turbo-ioa
**Guidance:** 分析准心 UI 系统现状、元素攻击组件结构，产出可执行的实现计划。
**TL Context for @planner:**
> ## Issue #238 — 准心 UI 展示元素伤害类型
>
> ### 目标
> 当玩家拥有 `CElementalAttack` 组件时，在准心附近显示当前元素伤害类型的视觉提示（FIRE/WET/COLD/ELECTRIC）。
>
> ### 需要分析的文件
> 1. **数据源组件** — `gol-project/scripts/components/c_elemental_attack.gd`：了解 `element_type` 枚举定义和组件结构
> 2. **UI 层** — `gol-project/scripts/ui/crosshair.gd` 和 `gol-project/scripts/ui/crosshair_view_model.gd`：分析 CrosshairView/CrosshairViewModel 的 MVVM 结构，特别是现有的电击特效颜色（`ELECTRIC_COLOR`）绘制模式
> 3. **UI AGENTS.md** — `gol-project/scripts/ui/AGENTS.md`：了解 UI 层的编码规范和模式
> 4. **Components AGENTS.md** — `gol-project/scripts/components/AGENTS.md`：了解组件目录规范
> 5. **Gameplay AGENTS.md** — `gol-project/scripts/gameplay/AGENTS.md`：了解 GOAP AI / ECS 编排方式
> 6. **项目 AGENTS.md** — `gol-project/AGENTS.md`：项目整体代码概览
>
> ### 输出要求
> 计划需包含：
> - 现有代码结构分析（CrosshairView 的绘制逻辑、ViewModel 的属性绑定机制）
> - 具体修改点和文件路径（新增哪些 ObservableProperty、哪些方法需要改动）
> - 元素类型到视觉表现的颜色/图标映射方案
> - 实现步骤清单（按顺序）
> - 需要注意的约束（如 MVVM 模式要求、组件依赖关系）
>
> ### 约束
> - 遵循项目 MVVM UI 模式（View 只负责绘制，ViewModel 管理数据和绑定）
> - 复用已有的 `ELECTRIC_COLOR` 模式扩展其他元素
> - 不引入新的第三方依赖
