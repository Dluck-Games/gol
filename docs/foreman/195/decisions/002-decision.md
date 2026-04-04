# Decision 2 — 2026-04-04
**Trigger:** 新 Issue #195 — 角色/怪物受到冻结伤害后偶现丢失移动动画（首次调度）
**Assessment:** 全新 bug issue，无任何历史工作产物（plans/ 和 iterations/ 均为空）。Issue 描述清晰：冻结伤害效果触发后实体移动动画偶现丢失，疑似 AnimationStateMachine 未正确恢复。按照流程，首步必须由 planner 进行根因分析并产出修复方案。
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5v-turbo-ioa
**Guidance:** 聚焦冻结伤害 → 动画状态机链路，定位丢失动画的根因点。阅读 AGENTS.md 了解项目架构后开始分析。
**TL Context for @planner:**
> ## Issue #195 — 冻结伤害后移动动画丢失
>
> ### 问题
> 角色或怪物受到冰冻/冻结伤害效果后，移动时偶现动画不播放（实体"滑行"），疑似 AnimationStateMachine 卡死或过渡失败。
>
> ### 分析方向
> 1. **冻结伤害系统**: 定位冻结效果的实现代码——找到施加冻结状态的组件、系统或 gameplay 脚本，理解冻结期间和结束时的行为。
> 2. **动画状态机**: 找到 Player 和 Monster 的 AnimationTree / AnimationPlayer / 状态机配置，特别关注：
>    - 冻结状态节点与移动（idle/walk/run）状态之间的 transition 条件
>    - 冻结结束后是否有正确的 transition 回移动状态
>    - 是否存在竞态条件（如冻结结束信号与移动输入同时触发时状态机行为）
> 3. **伤害处理链路**: 从受伤入口追踪到动画状态变更的完整调用链。
>
> ### 必读文档
> - `gol-project/AGENTS.md` — 项目架构总览
> - `gol-project/scripts/components/AGENTS.md` — 组件目录
> - `gol-project/scripts/systems/AGENTS.md` — 系统目录
> - `gol-project/scripts/gameplay/AGENTS.md` — GOAP AI / ECS Authoring
>
> ### 输出要求
> - 产出计划文档到 `docs/foreman/195/plans/` 目录
> - 计划需包含：根因分析、涉及文件列表、修复方案、测试策略
> - 使用中文撰写
