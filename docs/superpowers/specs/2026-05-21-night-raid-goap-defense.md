# 夜袭 GOAP 防御行为设计

> 日期: 2026-05-21
> 状态: 设计确认，待实现
> 范围: gol-project/scripts/gameplay/goap/ + scripts/systems/

---

## 1. 背景问题

GOL 已有完整的夜袭波次系统（丧尸围城、造墙防御），NPC 也有 GOAP AI 系统（Goal/Action/BehaviorTemplate 三层架构）。但两套系统目前**平行运行**：

- 白天 NPC 各干各的（采集、建造、探索）
- 夜袭时敌人来攻，但 NPC 的行为优先级**没有变化**
- 由于 SA_Flee 的 gate 是 `[has_threat, is_low_health]`（OR 逻辑），夜袭时 has_threat=true，所有 NPC 会优先逃跑（cost 1.0 最低），而不是战斗或修墙
- Builder/Gatherer 没有任何战斗 action，遇到威胁只能僵住或逃跑

**核心需求：** 夜袭阶段 NPC 自动切换到防御模式——专注于战斗、修墙、配合防守，白天恢复正常工作节奏。

---

## 2. 设计决策总结

| # | 决策 | 理由 |
|---|------|------|
| D1 | NPC 全部作为防守方（友军），不做敌对/背叛机制 | MVP 聚焦，敌对阵营后续再做 |
| D2 | 不做玩家指令系统（不选 NPC、不发命令） | 游戏是俯视角第三人称操作单一角色，不是 RTS |
| D3 | NPC 通过环境观察 + GOAP 优先级自然切换防御行为 | 最小 MVP，不需要新交互系统 |
| D4 | 战略层统一 SA_Fight（合并 FightMelee + FightRanged） | GOAP 只决定"打不打"，底层 FSM 决定"怎么打" |
| D5 | 战术撤退（放风筝）是 Fight FSM 内部行为，不是独立 Goal | Goal 层只有"打"和"逃"，战术层处理战斗方式 |
| D6 | SA_Flee 只在濒死时触发（gate: is_critical_health） | 夜袭健康 NPC 不逃跑，濒死才跑保命 |
| D7 | 合并 SA_Build + SA_Demolish → SA_Work | Build 本质是 Work，一个 Goal + 一个 SA 统一驱动 |
| D8 | 场景过滤（SceneActionTable）从 SA gate 中分离 | SA gate 只管能力/条件，场景规则集中在配置表，新场景只改表 |
| D9 | 角色能力（work_capabilities）与场景配置取交集 | 三层过滤：场景允许 × 角色能力 × 实际任务 |
| D10 | 所有 NPC 至少有近战能力，武器架后续再加 | MVP 先跑起来 |

---

## 3. 架构方案：三层过滤系统

### 3.1 整体过滤流程

```
NPC 的 action_registry（角色定义层）
  "这个角色会哪些 action？"
  由 NPC recipe 初始化，运行时不变
      ↓
SceneActionTable.BLOCKED_ACTIONS（场景过滤层）
  "当前场景屏蔽哪些 action？"
  由 Director 驱动，随游戏阶段变化
      ↓
StrategicAction.viability_gate（能力过滤层）
  "NPC 当前自身条件够不够？"
  由 Perception 写入 world_state
      ↓
Planner 在过滤后的 action 池中做 A* 搜索
```

### 3.2 SceneActionTable 配置

```gdscript
# scene_action_table.gd
class_name SceneActionTable
extends RefCounted

# Layer 1: 粗粒度 — 屏蔽整个 StrategicAction
const BLOCKED_ACTIONS: Dictionary = {
    &"daytime":     [],
    &"night_raid":  [&"Explore"],
}

# Layer 2: 细粒度 — SA_Work 内部的子行为调度（按优先级排序）
const WORK_SCHEDULE: Dictionary = {
    &"daytime":     [&"build", &"demolish", &"gather"],
    &"night_raid":  [&"repair", &"build"],
}
```

### 3.3 角色能力配置

角色能力通过独立组件 + 资源文件配置，策划可通过 .tres 文件调整，无需改代码。

**组件：**

```gdscript
# components/ai/c_work_capability.gd
class_name CWorkCapability
extends Component

@export var capabilities: Array[StringName] = []
```

**资源配置示例：**

```tres
# resources/work_capabilities/builder_capabilities.tres
[resource]
capabilities = PackedStringArray(["repair", "build", "gather"])
```

各角色配置：

| 角色 | 资源文件 | capabilities |
|------|---------|-------------|
| Builder | `builder_capabilities.tres` | `[&"repair", &"build", &"gather"]` |
| Gatherer | `gatherer_capabilities.tres` | `[&"gather"]` |
| Worker | `worker_capabilities.tres` | `[&"repair", &"build", &"gather", &"demolish"]` |
| Survivor | *(不挂此组件)* | — |
| Composer | *(不挂此组件)* | — |

**使用方式：** WorkTemplate 从 entity 上查询 CWorkCapability 组件获取能力列表：

```gdscript
var caps_comp: CWorkCapability = entity.get_component(CWorkCapability)
var caps: Array[StringName] = caps_comp.capabilities if caps_comp else []
```

### 3.4 三层交集逻辑

```
WORK_SCHEDULE（场景允许）: night_raid → [repair, build]
work_capabilities（角色能力）: Builder → [repair, build, gather]
实际任务（世界状态）: 3 面损坏墙壁

Builder 可做: [repair, build] ∩ [repair, build, gather] = [repair, build]
→ 有损坏墙壁 → repair（优先级最高）→ 去修墙

Gatherer 可做: [repair, build] ∩ [gather] = []
→ 无匹配工作 → template 失败 → GOAP 走 Fight
```

---

## 4. StrategicAction 清单（合并后）

### 4.1 现有 Action 变更

| 操作 | 变更内容 |
|------|---------|
| SA_FightMelee + SA_FightRanged → **SA_Fight** | 合并为一个 action，底层 FSM 选战斗方式 |
| SA_Build + SA_Demolish → **SA_Work** | 合并为一个 action，WORK_SCHEDULE 驱动子行为 |
| **SA_Flee** | gate 从 `[has_threat, is_low_health]` 改为 `[is_critical_health]` |
| **SA_Work** | 原 SA_Work 的采集逻辑保留为 gather 子行为 |
| **SA_Explore** | 场景过滤处理（SceneActionTable.BLOCKED_ACTIONS） |

### 4.2 完整 Action 列表

| # | SA | Cost | Gate | Preconditions | Effects | 说明 |
|---|-----|------|------|---------------|---------|------|
| 1 | **SA_Fight** | 2.0 | `has_threat` | `{has_threat: true}` | `{has_threat: false, is_safe: true}` | 统一战斗，FSM 选方式 |
| 2 | **SA_Flee** | 1.0 | `is_critical_health` | `{}` | `{is_safe: true}` | 濒死逃跑 |
| 3 | **SA_Feed** | 3.0 | `has_visible_food`, `has_food_stockpile` | `{is_hungry: true}` | `{is_hungry: false}` | 吃饭 |
| 4 | **SA_Work** | 5.0 | *(空)* | `{work_done: false}` | `{work_done: true}` | 工作（采集/建造/修墙/拆除） |
| 5 | **SA_Guard** | 5.0 | `is_guard` | `{is_guard: true}` | `{at_guard_post: true}` | 守哨位 |
| 6 | **SA_Patrol** | 5.0 | `is_guard` | `{is_guard: true}` | `{is_patrolling: true}` | 巡逻 |
| 7 | **SA_Rest** | 8.0 | `is_low_energy` | `{is_low_energy: true}` | `{is_rested: true}` | 休息 |
| 8 | **SA_Explore** | 10.0 | *(空)* | `{}` | `{is_exploring: true}` | 探索（场景过滤） |

### 4.3 Goal 清单

| # | Goal | Priority | Desired State | 变更 |
|---|------|----------|---------------|------|
| 1 | Survive | 100 | `{is_safe: true}` | 不变 |
| 2 | GuardDuty | 60 | `{at_guard_post: true}` | 不变 |
| 3 | FeedSelf | 50 | `{is_hungry: false}` | 不变 |
| 4 | EliminateThreat | 30 | `{has_threat: false}` | 不变 |
| 5 | Work | 20 | `{work_done: true}` | **合并原 Work + Build** |
| 6 | PatrolCamp | 1 | `{is_patrolling: true}` | 不变 |
| 7 | Explore | 1 | `{is_exploring: true}` | 不变 |

### 4.4 Action Registry（更新后）

| 角色 | Goals (priority) | Actions |
|------|-----------------|---------|
| **Survivor** | Survive(100) > GuardDuty(60) > FeedSelf(50) > EliminateThreat(30) > PatrolCamp(1) | Flee, Fight, Guard, Patrol, Feed |
| **Survivor Healer** | Survive(100) > GuardDuty(60) > EliminateThreat(30) > PatrolCamp(1) | Flee, Fight, Guard, Patrol |
| **Builder** | Survive(100) > FeedSelf(50) > Work(20) | Flee, Fight, Feed, Work |
| **Gatherer** | Survive(100) > FeedSelf(50) > Work(20) | Flee, Fight, Feed, Work |
| **Worker** | Survive(100) > FeedSelf(50) > Work(20) | Flee, Fight, Feed, Work |
| **Composer** | Survive(100) > Explore(1) | Flee, Fight, Explore |
| **Enemy** | EliminateThreat(30) > Explore(1) | Fight, Flee, Explore |

---

## 5. SA_Fight 的 FSM 设计

### 5.1 MVP（全部近战）

```
FightTemplate (loops: true)
  Step 1: ChaseStep → 追击最近威胁
  Step 2: AttackStep(melee) → 近战攻击
  退出条件: has_threat=false 或 is_critical_health=true
```

复用现有 FightMeleeTemplate 的 ChaseStep + AttackStep 结构。

### 5.2 未来扩展（加入远程 + 放风筝）

```
FightTemplate (loops: true)
  Step 1: CombatAssessStep → 评估战斗方式
      ├── 分支 A: 有远程武器 AND 自身速度 > 敌人速度
      │   └── KiteStep → AttackStep(ranged) [循环: 退后→射击→退后→射击]
      ├── 分支 B: 有远程武器 AND 自身速度 <= 敌人速度
      │   └── PositionStep → AttackStep(ranged) [站桩射击]
      └── 分支 C: 无远程 或 敌人已近身
          └── ChaseStep → AttackStep(melee) [近战]
```

CombatAssessStep 判断逻辑：
1. 检查 `has_shooter_weapon` world state fact
2. 比较 NPC 移动速度 vs 目标移动速度
3. 选择对应的战斗分支

---

## 6. SA_Flee 的两种模式

| 维度 | 濒死逃跑（Survival Flee） | 战术撤退（Kiting） |
|------|-------------------------|-------------------|
| **Goal 层** | Survive(100) — "保命" | Survive(100) 或 EliminateThreat(30) — "打" |
| **触发 SA** | SA_Flee | SA_Fight（内部分支） |
| **触发条件** | `is_critical_health = true` | 有远程武器 + 速度优势 |
| **FSM 行为** | 远离威胁，不停下攻击 | 边退边打，保持射击距离 |
| **结束条件** | `is_safe = true`（远离所有威胁） | `has_threat = false`（敌人死了） |
| **NPC 状态** | 不会回头攻击 | 始终在攻击，只是保持距离 |

**关键区别：** 放风筝不是逃跑，是战斗的一部分。在 Goal 层面 NPC 始终在执行 SA_Fight，放风筝只是 FightTemplate 内部的战术分支。

---

## 7. SA_Work 的 dispatch 设计

### 7.1 WorkTemplate 核心逻辑

```gdscript
func _build_steps(agent: CGoapAgent, entity: Entity) -> Array[BehaviorStep]:
    var schedule: Array = SceneActionTable.WORK_SCHEDULE.get(
        DirectorState.scene_type, [&"gather"]
    )
    var caps_comp: CWorkCapability = entity.get_component(CWorkCapability)
    var caps: Array[StringName] = caps_comp.capabilities if caps_comp else []

    for work_type: StringName in schedule:
        if work_type not in caps:
            continue
        if not _has_task_for(work_type, entity):
            continue
        return _create_steps_for(work_type)

    return []  # 无可用工作 → template 失败
```

### 7.2 子行为 Step 映射

| work_type | Steps | 复用 |
|-----------|-------|------|
| `repair` | `[BuildStep(task_filter="repair")]` | 复用现有 BuildStep，加 task_filter |
| `build` | `[BuildStep()]` | 直接复用 BuildStep |
| `demolish` | `[DemolishStep()]` | 直接复用 DemolishStep |
| `gather` | `[FindWorkTarget, MoveTo, Gather, MoveTo, Deposit]` | 现有 WorkTemplate 5 步流程 |

### 7.3 任务优先级（任务队列层面）

修墙 > 新建 > 拆除 > 采集 的优先级由 WORK_SCHEDULE 的排列顺序保证（schedule 列表本身就是优先级队列）。同类型内的优先级由任务队列内部的 priority 字段控制：

- RepairTask: priority 100（墙壁受损时自动创建）
- BuildTask: priority 50
- DemolishTask: priority 40
- Gather: fallback，不需要 priority

---

## 8. 白天 vs 夜袭 — 行为对比

### 8.1 白天

| 角色 | 行为流程 |
|------|---------|
| **Survivor** | Survive(满足) → GuardDuty → FeedSelf → PatrolCamp |
| **Builder** | Survive(满足) → FeedSelf → Work(build/demolish/gather) |
| **Gatherer** | Survive(满足) → FeedSelf → Work(gather) |
| **Worker** | Survive(满足) → FeedSelf → Work(build/demolish/gather) |

白天遇到威胁（所有角色）：Survive(100) → SA_Fight → 战斗

### 8.2 夜袭（有敌人）

| 角色 | 行为流程 |
|------|---------|
| **Survivor** | Survive(100) → SA_Fight → 战斗 |
| **Builder** | Survive(100) → SA_Fight → 战斗 |
| **Gatherer** | Survive(100) → SA_Fight → 战斗 |
| **Worker** | Survive(100) → SA_Fight → 战斗 |

所有 NPC 优先战斗。SA_Flee 在健康时 gate 不通过（is_critical_health=false）。

### 8.3 夜袭（战斗间隙，威胁暂时清除）

| 角色 | 行为流程 |
|------|---------|
| **Survivor** | Survive(满足) → GuardDuty → 守哨位 |
| **Builder** | Survive(满足) → FeedSelf → Work: schedule=[repair,build] → 修墙/建造 |
| **Gatherer** | Survive(满足) → FeedSelf → Work: schedule∩caps=[] → 待命 → 等敌人来再 Fight |
| **Worker** | Survive(满足) → FeedSelf → Work: schedule∩caps=[repair,build] → 修墙/建造 |

### 8.4 夜袭（濒死 NPC）

```
Survive(100): is_safe=false
  → SA_Flee gate [is_critical_health] → viable → cost 1.0 → 逃跑
  → HP 恢复到安全线 → is_critical_health=false → SA_Flee NOT viable → 回到战斗/修墙
```

---

## 9. World State Facts 变更

### GOAP 直接使用（SA gate 读取）

| Fact | 写入者 | 逻辑 | 使用者 |
|------|-------|------|--------|
| `is_critical_health` | SPerception | HP < 20% | SA_Flee gate |

场景过滤不通过 world_state，而是 SceneActionTable 直接读取 `DirectorState.scene_type`（由 S_NightDirector 在阶段切换时更新）。

### 供其他系统使用（GOAP 不直接读取）

| Fact | 写入者 | 逻辑 | 用途 |
|------|-------|------|------|
| `is_daytime` | SPerception | DirectorState.phase == DAYTIME | UI、对话、视觉系统等 |
| `is_night_raid` | SPerception | phase in [NIGHT_ACTIVE, NIGHT_PEAK] | UI、对话、视觉系统等 |

---

## 10. 文件变更清单

### 新增文件

| 文件 | 说明 | 估算行数 |
|------|------|---------|
| `scripts/gameplay/goap/scene_action_table.gd` | 场景过滤配置表 | ~15 |
| `scripts/gameplay/goap/strategic_actions/sa_fight.gd` | 合并后的统一战斗 SA | ~15 |
| `scripts/gameplay/goap/templates/fight_template.gd` | 合并后的战斗 Template | ~25 |
| `scripts/components/ai/c_work_capability.gd` | 新组件：角色工作能力 | ~10 |
| `resources/work_capabilities/*.tres` | 角色能力配置文件（策划可编辑） | ~4 文件 |

### 修改文件

| 文件 | 变更 | 行数 |
|------|------|------|
| `scripts/systems/s_perception.gd` | 写入 is_critical_health fact | ~5 |
| `scripts/gameplay/goap/strategic_actions/sa_flee.gd` | gate 改为 `[is_critical_health]` | 1 |
| `scripts/gameplay/goap/strategic_actions/sa_work.gd` | 合并 SA_Build/SA_Demolish，改 preconditions/effects | ~5 |
| `scripts/gameplay/goap/templates/work_template.gd` | 重写为 dispatch 模式 | ~50 |
| `scripts/components/ai/c_goap_agent.gd` | scene 过滤逻辑（get_viable_actions 加 BLOCKED_ACTIONS 检查） | ~5 |
| `scripts/gameplay/goap/strategic_actions/sa_build.gd` | 删除 | — |
| `scripts/gameplay/goap/strategic_actions/sa_demolish.gd` | 删除 | — |
| `scripts/gameplay/goap/strategic_actions/sa_fight_melee.gd` | 删除 | — |
| `scripts/gameplay/goap/strategic_actions/sa_fight_ranged.gd` | 删除 | — |
| `scripts/gameplay/goap/templates/build_template.gd` | 删除（逻辑合并到 WorkTemplate） | — |
| `scripts/gameplay/goap/templates/demolish_template.gd` | 删除（逻辑合并到 WorkTemplate） | — |
| `scripts/gameplay/goap/templates/fight_melee_template.gd` | 删除（替换为 fight_template.gd） | — |
| `scripts/gameplay/goap/templates/fight_ranged_template.gd` | 删除（替换为 fight_template.gd） | — |
| `scripts/gameplay/goap/steps/build_step.gd` | 加 task_filter 参数 | ~5 |
| `resources/recipes/npc_*.tres` | 更新 Goals + Actions + work_capabilities | ~6 文件 |
| `resources/recipes/survivor*.tres` | 更新 Actions（Fight 替换 FightMelee/Ranged） | ~2 文件 |
| `resources/recipes/enemy_*.tres` | 更新 Actions | ~2 文件 |
| `resources/goals/build.tres` | 删除（合并到 Work goal） | — |
| `resources/director_state.gd` | 加 scene_type 字段 | 1 |
| `scripts/systems/s_night_director.gd` | 阶段切换时更新 scene_type | ~4 |

### 总计

- **新增**: ~65 行（4 个新代码文件 + ~4 个 .tres 资源）
- **修改**: ~75 行
- **删除**: 8 个文件 + 1 个 goal .tres
- **总计**: ~140 行新增/改动

---

## 11. 待确认事项

- [ ] BuildStep 的 task_filter 实现方式：是加参数还是新增 RepairStep？
- [ ] 修墙任务的创建时机：墙壁受损时自动创建 vs 定时扫描？
- [ ] `is_critical_health` 的阈值：20% HP 是否合适？
- [ ] Enemy 的 SA_Flee gate 是否也改为 is_critical_health？（当前方案是，敌人也更激进）
- [ ] Gatherer 在夜袭间隙完全待命是否可接受？还是需要一个简单的辅助行为？

---

## 12. 未来扩展方向

### Phase 2: 信号物系统
- 玩家使用道具（集结号角）在区域发信号
- 范围内 NPC 根据角色响应（Builder 修附近墙，Survivor 来战斗）
- 不打断第三人称操作，手柄友好

### Phase 3: 武器架系统
- NPC 可装备远程武器（从武器架取用）
- CombatAssessStep 判断战斗方式（近战/远程/放风筝）
- KiteStep 实现边退边打的战术撤退

### Phase 4: 更多场景
- 沙尘暴：Work 限 repair/build，Explore 屏蔽，视野受限
- 冬季：Work 限 gather(砍冰), build(保暖)，新增取暖行为
- 新场景只需在 SceneActionTable 加 2 行配置

### Phase 5: NPC 配合行为
- 多 NPC 修同一面墙的协作
- 前线 NPC 扛线、后方 Builder 修墙的隐式配合
- 基于共享 world state 的简单协调（不需要通信协议）
