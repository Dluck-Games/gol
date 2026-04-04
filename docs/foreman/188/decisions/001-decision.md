# Decision 1 — 2026-04-04 00:00
**Trigger:** 新 issue #188 — 箱子会阻挡并消耗子弹（new_issue）
**Assessment:** 首次调度。Issue 已包含详细的根因分析：`SDamage._is_valid_bullet_target()` 未检查目标是否有 `CHP` 组件，导致无血量实体（如 CContainer 箱子）通过验证后子弹被移除但伤害无效。Orchestration 中已给出三个修复方案，方案 A（在 `_is_valid_bullet_target()` 增加 CHP 检查）被标记为推荐。无历史决策、无迭代文档。调度轮次 0/3。
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5v-turbo-ioa
**Guidance:** Issue 根因分析已经很清晰，Planner 应聚焦于产出可执行的实现计划，而非重新分析问题。
**TL Context for @planner:**
> ## 任务：为 #188 产出实现计划
>
> **Issue:** 子弹命中 CContainer 箱子后被移除但伤害无效（箱子无 CHP），导致子弹被"吃掉"无法穿透。
>
> **根因文件：** `gol-project/scripts/systems/s_damage.gd`
> - `SDamage._process_bullet_collision()` → `_is_valid_bullet_target()` 未检查 CHP
> - 无 CHP 实体通过目标验证 → `_take_damage()` 直接 return → 子弹仍被移除（line 99）
> - 箱子实体（`authoring_box.gd`）：CTransform + CSprite + CCollision(CircleShape2D r=16) + CContainer，无 CHP 无 CCamp
>
> **推荐方案 A：** 在 `_is_valid_bullet_target()` 中增加 `if not target.has_component(CHP): return false`
>
> **约束：**
> 1. 项目不使用 collision_layer/mask（所有 Area2D 默认 layer 1 / mask 1），不能通过碰撞层解决
> 2. 不影响近战攻击（SMeleeAttack 有独立碰撞逻辑）
> 3. 仅修改 `s_damage.gd` 一个文件
> 4. 需要考虑：其他无 CHP 的实体是否也应跳过（如障碍物、装饰物），还是仅处理 CContainer 场景
>
> **要求产出：**
> - 明确的修改方案选择及理由
> - 具体的代码改动点（文件路径 + 函数名 + 行号范围）
> - 影响评估（哪些实体类型会受影响）
> - 测试策略（需要什么测试覆盖）
>
> **参考文档：**
> - `/Users/dluckdu/Documents/Github/gol/docs/foreman/188/orchestration.md` — Issue 全文和根因分析
> - `gol-project/AGENTS.md` — 项目代码规范和架构说明
