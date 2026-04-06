# Decision 1 — 2026-04-05 00:00
**Trigger:** 新 Issue #198 首次触发，类型为 `new_issue`
**Assessment:** 这是一个全新的 gameplay 设计优化 Issue，涉及雷属性组件的拾取效果和受击效果的逻辑修正。当前无任何历史决策、计划或迭代记录，属于首次调度。需要先进行技术分析以理解现有代码结构和设计约束。
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5v-turbo-ioa
**Guidance:** 分析雷属性（Electric）相关组件的现有实现，理清拾取逻辑和受击效果的设计矛盾点，产出可执行的技术方案。

**TL Context for @planner:**
> ## 任务：分析并设计雷属性组件拾取/受击效果优化方案
>
> ### Issue 摘要
> Issue #198 要求修复雷属性组件的行为：
> - **现状问题1：** 拾取雷组件后玩家准星颤抖（错误行为——应只对敌人造成伤害）
> - **现状问题2：** 受到敌人雷攻击时仅扣血，无准星干扰（缺失行为——应干扰准星）
> - **现状问题3：** 仅拾取雷组件就导致瞄准干扰，未考虑 Tracker 组件的排斥关系
>
> ### 你需要完成
> 1. **代码探索**：在 `gol-project/` 子模块中定位以下内容：
>    - 雷属性相关的 Component 定义（搜索 `Electric`、`electric`、`thunder`、`lightning` 等关键词）
>    - 组件拾取逻辑（pickup / collect 系统）
>    - 受击效果处理系统（damage / hit effect）
>    - 准星/瞄准相关 UI 或 camera shake 逻辑
>    - Tracker 组件定义及其与 Electric 的交互逻辑
> 2. **阅读参考文档**：
>    - `gol-project/AGENTS.md` — 项目架构总览
>    - `gol-project/scripts/components/AGENTS.md` — 组件目录
>    - `gol-project/scripts/systems/AGENTS.md` — 系统目录
>    - `gol-project/scripts/gameplay/AGENTS.md` — 游戏玩法逻辑
>    - SSOT Notes 中关于雷属性/元素系统的设计笔记（如有）
> 3. **产出方案**：在 `/Users/dluckdu/Documents/Github/gol/docs/foreman/198/plans/` 目录下创建计划文档（格式 `YYYY-MM-DD-plan.md`），包含：
>    - 现有代码结构分析（涉及哪些文件、函数、信号连接）
>    - 问题根因定位
>    - 具体修改方案（文件级粒度，列出要改哪些文件的哪些部分）
>    - 测试策略（单元测试 + E2E 测试要点）
>
> ### 约束
> - 方案必须同时覆盖"拾取效果修正"和"受击效果补充"两个方面
> - 必须明确 Tracker 与 Electric 的排斥/组合规则
> - 所有修改在 `gol-project/` 子模块内完成
> - 文档使用中文撰写
