# Decision 1 — 2026-04-04
**Trigger:** 新 issue #195 — 角色/怪物受到冻结伤害后偶现丢失移动动画
**Assessment:** 首次接手，无历史决策、计划或迭代记录。这是一个视觉类 bug，涉及冻结伤害效果与移动状态机的交互。需要先由 planner 分析根因和修复方案。
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5v-turbo-ioa
**Guidance:** 这是一个动画状态机相关的 bug，重点分析冻结伤害效果如何影响实体动画状态机，找出状态卡死或未恢复的代码路径。
**TL Context for @planner:**
> **Issue #195: 冻结伤害后移动动画丢失**
>
> ## Bug 描述
> 当角色或怪物受到冻结伤害（冰冻效果）后，偶现移动时丢失动画（实体"平移滑行"，不播放行走/跑动动画）。期望行为：冻结伤害触发/结束后，状态机能正常过渡回移动动画。实际行为：状态机卡死或动画未恢复。
>
> ## 分析要求
> 请在 `gol-project/` 子模块中分析以下内容：
>
> 1. **冻结/冰冻效果实现**：找到 freeze/frost/ice 相关的 damage effect 或 status effect 组件与系统，理解其生命周期（施加、持续、移除）
> 2. **动画状态机**：找到角色/怪物的 AnimationTree / AnimationPlayer / 状态机配置，特别关注移动状态（idle → walk/run）和冻结状态的转换逻辑
> 3. **交互点**：冻结效果如何影响/中断当前播放的动画？效果结束时是否正确恢复？
>
> ## 参考文档
> - `gol-project/AGENTS.md` — 代码结构概览
> - `gol-project/scripts/components/AGENTS.md` — 组件目录
> - `gol-project/scripts/systems/AGENTS.md` — 系统目录
>
> ## 输出要求
> - 在 `/Users/dluckdu/Documents/Github/gol/docs/foreman/195/plans/` 下输出分析文档
> - 明确标注：根因假设、涉及的关键文件和函数、修复方案、风险评估
> - 文档使用中文
