# Decision 001 — 2026-04-04 00:00

**Trigger:** 新 Issue #195 — 角色/怪物受到冻结伤害后偶现丢失移动动画（new_issue）

**Assessment:** 首次调度，无历史记录。Issue 描述了一个动画状态机 bug：实体受到冻结伤害后，移动动画偶现丢失，表现为"滑行"。需要先由 planner 分析根因并制定修复方案。

**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5v-turbo-ioa
**Guidance:** 这是一个视觉类 bug，涉及动画状态机与冻结效果系统的交互。重点分析冻结伤害如何影响动画状态机的状态转换，找出可能导致状态卡死的代码路径。

**TL Context for @planner:**

> ## 任务：分析 Issue #195 并制定修复方案
>
> **Bug 摘要：** 角色或怪物受到冰冻/冻结伤害后，移动时偶现丢失动画（滑行现象）。怀疑是动画状态机在冻结效果触发/解除时未能正确过渡回移动状态。
>
> **分析要求：**
> 1. 阅读以下入口文档了解项目结构：
>    - `gol-project/AGENTS.md` — 项目代码概览
>    - `gol-project/scripts/components/AGENTS.md` — 组件目录（关注动画相关组件）
>    - `gol-project/scripts/systems/AGENTS.md` — 系统目录（关注动画系统）
> 2. 定位以下关键模块的代码：
>    - **动画状态机实现** — 找到 Player/Monster 的 AnimationTree / AnimationPlayer / StateMachine 配置和驱动逻辑
>    - **冻结/冰冻伤害系统** — 定位 freeze/frost/chill 相关的伤害效果组件或系统
>    - **两者交互点** — 冻结效果如何影响动画状态（是否禁用动画、修改状态机参数、或直接操控播放）
> 3. 分析可能的根因路径：
>    - 冻结效果结束时是否遗漏了恢复动画状态的逻辑？
>    - 动画状态机是否存在从 frozen → move 的非法/缺失过渡？
>    - 是否有竞态条件（如快速连续受到冻结伤害）导致状态不一致？
> 4. 输出一份 plan 文档到 `docs/foreman/195/plans/` 目录，包含：
>    - 根因分析结论
>    - 具体修复方案（涉及哪些文件、函数、改动点）
>    - 测试策略（单元测试 + E2E 测试要点）
>
> **约束：**
> - 只做分析和规划，不写任何代码
> - 方案必须可操作，具体到文件路径和函数名
> - 如果发现需求不清晰或信息不足以判断根因，在 plan 中明确标注需要补充的信息

---

**GitHub Comment:**
（待后续阶段产出）
