# Decision 1 — 2026-04-03 18:00
**Trigger:** 新 issue #226 — 元素子弹添加 VFX 特效
**Assessment:** 首次收到 issue，调度轮次 0/3，无历史决策和迭代。Issue 要求为不同元素类型的子弹添加粒子/特效（火焰、冰、雷电等），覆盖飞行轨迹和命中表现。备注提到"具体特效风格和资产待设计确认"，但 core 需求（代码框架层）可以先规划。当前项目中存在 `CBullet` 组件和 `SDamage` 系统（处理子弹碰撞和命中效果），render group 下有视觉渲染系统，但尚无 VFX 专用系统或组件。需要 planner 深入探索：1) 现有元素子弹的定义和类型系统；2) 当前 `SDamage` 中命中效果的处理方式；3) `SFireBullet` 中子弹生成的流程；4) 是否已有 VFX/particle 相关代码或资产。
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5.0-turbo-ioa
**Guidance:** 重点探索现有子弹系统架构，确定元素类型的定义方式，评估 VFX 实现的技术路径（新 component + 新 system vs 现有系统扩展）。注意 issue 备注"具体特效风格和资产待设计确认"，planner 应在方案中区分代码框架层和美术资产层。

**TL Context for @planner:**
> ## Issue #226: 元素子弹添加 VFX 特效
>
> **Issue 目标：** 为各类元素子弹添加对应的 VFX 特效，覆盖飞行轨迹和命中表现。
>
> **你需要探索的关键文件：**
> 1. `gol-project/scripts/components/c_bullet.gd` — 子弹组件，了解现有子弹数据结构
> 2. `gol-project/scripts/systems/s_damage.gd` — 命中处理系统，查看现有命中效果逻辑
> 3. `gol-project/scripts/systems/s_fire_bullet.gd` — 子弹发射系统，了解子弹生成流程
> 4. `gol-project/scripts/systems/s_render_view.gd` — 渲染系统，了解视觉表现方式
> 5. `gol-project/scripts/systems/s_dead.gd` — 死亡效果系统，可能有 tween 动画参考
> 6. `gol-project/scripts/gameplay/` — 搜索 element 相关的 authoring 和 GOAP 定义
> 7. `gol-project/resources/recipes/` — 搜索 bullet 相关 recipe，了解子弹类型定义
>
> **架构参考（必读）：**
> - `gol-project/AGENTS.md` — 命名规范、代码风格、ECS 架构
> - `gol-project/scripts/components/AGENTS.md` — 组件目录
> - `gol-project/scripts/systems/AGENTS.md` — 系统目录和分组
>
> **约束：**
> - Components 是纯数据，逻辑必须放在 System 中
> - System 必须设置 `group`（render group 适合 VFX 系统）
> - 必须声明 `class_name`，文件名 `c_xxx.gd` / `s_xxx.gd`
> - 使用 static typing
> - Issue 备注"具体特效风格和资产待设计确认"——你的方案应明确区分代码框架层（component/system 定义）和美术资产层（具体粒子材质），代码框架层可先行实现
>
> **产出要求：** 方案需包含：1) 现有系统分析（元素类型如何定义、子弹生命周期）；2) VFX 架构设计（新 component + 新 system 的具体方案）；3) 文件变更清单（新建/修改哪些文件）；4) 测试策略。
