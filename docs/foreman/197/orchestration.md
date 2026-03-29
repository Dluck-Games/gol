# Orchestration — Issue #197

## Issue
**Title:** 偶现冰冻后，子弹射出会逐渐减速并停留在某个位置
**Labels:** bug, topic:gameplay, topic:visual, foreman:assign
**Body:**
**Bug 描述：**
射击冰冻效果后的子弹，偶尔会发生速度递减（减速）直到完全停止的问题。

**具体场景（基于观察）：**
1. 射击发生冰冻效果（带有冻结元素/被冰冻后）。
2. 子弹飞出后，并未保持匀速。
3. 偶现子弹在空中逐渐减速，最终停留在地图上的某个位置不再移动。

**期望行为：**
无论是否附带/受冰冻效果影响，子弹的运动表现应该是保持设定的匀速飞行，直到达到最大射程/发生碰撞而被销毁。

**实际行为：**
子弹速度衰减，在空中停止。

**环境：**
- 游戏版本：最新开发版本
- 影响对象：Bullet

---

## Decision Log

### Decision 1 — 2026-03-29 19:45
**Trigger:** New issue assigned
**Assessment:** 新 issue #197，冰冻效果后子弹偶现减速停止的 bug。Issue 描述清晰，有明确的期望行为和实际行为对比。需要 planner 追踪冰冻效果与子弹速度之间的关联链路。
**Action:** spawn @planner
**Model:** glm-5.0-turbo-ioa
**Guidance:** 分析冰冻效果如何影响子弹运动状态，追踪完整的影响链路，制定修复方案和测试契约
**TL Context for Planner:**
> ## 任务：分析 Issue #197 — 冰冻后子弹减速停止 bug
>
> ### 背景
> 子弹在冰冻效果发生后偶现速度递减直到停止，而非保持匀速飞行直到射程结束或碰撞销毁。
>
> ### 分析要求
> 1. **追踪冰冻效果传播链路**：从冰冻效果（FreezeStatus / SlowModifier 等）的施加，到它如何影响子弹的速度属性。重点关注：
>    - 冰冻效果是否通过某种组件（如 SpeedModifier、MovementSlow）影响所有实体
>    - 子弹是否意外地成为了冰冻减速效果的目标
>    - 子弹的速度是每帧设置（set_velocity）还是物理驱动（物理引擎衰减）
>
> 2. **定位偶现条件**：为什么是"偶现"而非必现？分析是否与以下因素有关：
>    - 冰冻效果施加的时机（子弹刚射出 vs 子弹飞行中）
>    - 射击者自身是否被冰冻（射击者冻结导致子弹初始速度异常）
>    - 并发/帧率相关的竞态条件
>
> 3. **评估影响面**：修复方案可能涉及哪些系统？特别关注：
>    - 子弹系统（Bullet 相关 components/systems）
>    - 状态效果系统（StatusEffect / Freeze 相关）
>    - 移动/速度修改系统（Speed / Movement modifiers）
>
> 4. **制定测试契约**：明确需要验证的测试场景，至少覆盖：
>    - 正常情况下子弹保持匀速飞行
>    - 冰冻效果不应用于子弹实体
>    - 冰冻实体射击时子弹速度不受射击者状态影响
>
> ### 产出
> 请输出完整的分析文档，包含：根因假设、影响面清单、推荐修复方案（包含具体代码位置）、测试契约。

### Decision 2 — 2026-03-29 19:46
**Trigger:** @planner completed (no document produced)
**Assessment:** Planner 完成但未产出分析文档，无法评估 plan 质量。这是第 1 次内部迭代，重新调度 planner 并强调文档产出要求。
**Action:** spawn @planner
**Model:** glm-5.0-turbo-ioa
**Guidance:** 必须产出分析文档到 docs/foreman/197/ 目录
**TL Context for Planner:**
> ## 任务（重试）：分析 Issue #197 — 冰冻后子弹减速停止 bug
>
> ### 上次问题
> 上次 planner 完成但未产出任何文档。本次**必须**在 `/Users/dluckdu/Documents/Github/gol/docs/foreman/197/` 目录下创建分析文档，例如 `01-planner-freeze-bullet-analysis.md`。
>
> ### 背景
> 子弹在冰冻效果发生后偶现速度递减直到停止，而非保持匀速飞行直到射程结束或碰撞销毁。
>
> ### 分析要求
> 1. **追踪冰冻效果传播链路**：从冰冻效果（FreezeStatus / SlowModifier 等）的施加，到它如何影响子弹的速度属性。重点关注：
>    - 冰冻效果是否通过某种组件（如 SpeedModifier、MovementSlow）影响所有实体
>    - 子弹是否意外地成为了冰冻减速效果的目标
>    - 子弹的速度是每帧设置（set_velocity）还是物理驱动（物理引擎衰减）
>
> 2. **定位偶现条件**：为什么是"偶现"而非必现？分析是否与以下因素有关：
>    - 冰冻效果施加的时机（子弹刚射出 vs 子弹飞行中）
>    - 射击者自身是否被冰冻（射击者冻结导致子弹初始速度异常）
>    - 并发/帧率相关的竞态条件
>
> 3. **评估影响面**：修复方案可能涉及哪些系统？特别关注：
>    - 子弹系统（Bullet 相关 components/systems）
>    - 状态效果系统（StatusEffect / Freeze 相关）
>    - 移动/速度修改系统（Speed / Movement modifiers）
>
> 4. **制定测试契约**：明确需要验证的测试场景，至少覆盖：
>    - 正常情况下子弹保持匀速飞行
>    - 冰冻效果不应用于子弹实体
>    - 冰冻实体射击时子弹速度不受射击者状态影响
>
> ### 产出要求（必须）
> **必须**将分析文档写入 `/Users/dluckdu/Documents/Github/gol/docs/foreman/197/01-planner-freeze-bullet-analysis.md`。文档必须包含：根因假设、影响面清单、推荐修复方案（包含具体代码位置和文件路径）、测试契约。不产出文档视为未完成。

### Decision 3 — 2026-03-29 11:55
**Trigger:** @planner completed (01-planner-bullet-friction-analysis.md)
**Assessment:** Planner 产出了高质量分析文档。根因定位清晰：CMovement.friction 默认值 800.0 被 bullet recipe 继承，SMove._apply_friction() 对所有 CMovement 实体施加摩擦力导致子弹减速。Planner 正确指出冰冻效果是红鲱鱼——子弹无 CElementalAffliction 组件，不受元素系统影响。Planner 报告修复已在代码库中实现（s_fire_bullet.gd:130），且单元测试和集成测试已覆盖。因修复声称已完成，跳过 coder 阶段，直接交给 reviewer 验证现有代码和测试的正确性。
**Action:** spawn @reviewer
**Model:** glm-5.0-turbo-ioa
**Guidance:** 验证 planner 报告的修复是否真实存在于代码中，测试是否充分且通过
**TL Context for Reviewer:**
> ## 任务：验证 Issue #197 修复 — 子弹减速停止 bug
>
> ### 背景
> Planner 分析报告（01-planner-bullet-friction-analysis.md）指出：
> - **根因**：`CMovement.friction` 默认值 800.0 被 bullet recipe 继承，`SMove._apply_friction()` 对所有 `CMovement` 实体施加摩擦力
> - **修复**：`s_fire_bullet.gd:130` 已添加 `bullet_movement.friction = 0.0`
> - **测试**：`tests/unit/system/test_s_move.gd` 新增 friction=0 单元测试，`tests/integration/test_bullet_flight.gd` 新增端到端子弹飞行测试
> - **冰冻无关**：子弹无 `CElementalAffliction`，不受冰冻效果影响
>
> ### 审查要求
>
> 1. **验证修复存在且正确**：
>    - 读取 `gol-project/scripts/systems/s_fire_bullet.gd`，确认 `_create_bullet()` 中确实有 `bullet_movement.friction = 0.0`
>    - 确认此行在 `velocity` 赋值之后、函数返回之前
>    - 检查是否有其他子弹创建路径绕过此逻辑
>
> 2. **验证测试充分性**：
>    - 读取 `tests/unit/system/test_s_move.gd`，确认 friction=0 时速度不衰减的测试逻辑正确
>    - 读取 `tests/integration/test_bullet_flight.gd`，确认端到端测试覆盖了子弹匀速飞行
>    - 检查是否有回归风险：friction>0 的正常减速逻辑是否仍被测试覆盖
>
> 3. **验证影响面**：
>    - 确认 `CMovement.DEFAULT_FRICTION` 未被修改（仍为 800.0）
>    - 确认 `SMove._apply_friction()` 逻辑未被修改（系统行为不变，只是输入值变化）
>    - 确认不存在其他实体类型因 friction=0 导致异常移动的情况
>
> 4. **Planner 的建议补充测试是否需要**：
>    - Planner 建议补充 lifetime 销毁集成测试和冰冻场景 E2E 测试
>    - 评估这些建议是否必要，还是当前测试覆盖已足够关闭此 issue
>
> ### 审查重点
> - 如果修复和测试均正确且充分 → 报告 review pass
> - 如果发现修复不存在或测试不足 → 明确指出缺失项，推荐 spawn @coder
> - 如果发现架构问题 → 明确指出问题，推荐回退 spawn @planner
