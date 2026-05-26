# Guard Engagement Range — 实现 Spec

**日期：** 2026-05-26
**状态：** Draft
**范围：** 守卫（及所有远程 GOAP 实体）的 Fight 触发条件改进

---

## 问题陈述

守卫在视野范围（600px）内发现敌人后立即进入 SA_Fight，但 FightTemplate 的远程路径只有 AttackStep（无 ChaseStep）。当敌人在射程（320px）外时，AttackStep 返回 `StepResult.RUNNING` 并将 velocity 置零 — 守卫站桩不动，永远不开火。

## 设计目标

1. 敌人在射程外时，SA_Fight 不应被规划（直接不可行，不是改 cost）
2. 可行性判断需考虑地形障碍（寻路可达性）
3. 配置为 per-entity 级别
4. 不影响近战实体（僵尸、worker）的现有行为

---

## 架构决策

### Engagement Range 计算公式

```
engagement_range = attack_range × 0.8
```

### 可达性判断逻辑

不是简单的欧几里得距离比较。完整逻辑：

1. 从守卫当前位置向敌人位置做局部 BFS 寻路（`LocalNavigationUtils.find_path`）
2. 如果路径有效（`path.is_valid`）：取路径终点（即敌人位置），计算终点到敌人的距离（= 0，因为路径到达了目标）→ engageable = true（敌人可达且在寻路范围内）
3. 如果路径无效（被墙隔开、超出搜索半径）：engageable = false
4. 额外条件：即使路径有效，如果路径长度（步数 × tile_size）> engagement_range → engageable = false

简化表述：
```
path = BFS(guard_pos → enemy_pos, max_radius, max_visited)
if path.is_valid AND path_world_distance <= engagement_range:
    is_threat_engageable = true
else:
    is_threat_engageable = false
```

其中 `path_world_distance = path.total_cost × tile_diagonal_size`（BFS 的 total_cost 是步数）。

### 为什么用 BFS 而非欧几里得距离

- 欧几里得距离无法感知墙壁：敌人在墙另一边直线距离 100px，但寻路距离可能 500px 或不可达
- 现有 `_candidate_is_reachable()` 在 `s_perception.gd` 中已经用了相同的 BFS 模式（`LocalNavigationUtils.find_path`，radius=18，max_visited=640）
- 复用相同的 API 和参数，行为一致

---

## 数据流

```
┌─────────────────────────────────────────────────────────────────┐
│ s_perception.gd (每 0.15s，LOD 节流)                             │
│                                                                   │
│ _process_entity():                                                │
│   1. 扫描视野内实体 → 设置 vision._nearest_enemy                  │
│   2. 写入 world_state["has_threat"] = (_nearest_enemy != null)    │
│   3. [新增] 计算 is_threat_engageable → 写入 world_state          │
└───────────────────────────────┬───────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ s_semantic_translation.gd (每帧)                                  │
│                                                                   │
│ _translate_threat_presence():                                     │
│   - 不再负责 has_threat（已由 s_perception 写入）                  │
│   - 不负责 is_threat_engageable（已由 s_perception 写入）          │
│   - 保留 is_threat_in_attack_range 的计算（用于其他系统）          │
└───────────────────────────────┬───────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ s_goal_decision.gd (每 update_interval，max 3/frame)              │
│                                                                   │
│ _process_decision_tick():                                         │
│   goals 按优先级排序 → EliminateThreat(30) 不满足                  │
│   → get_viable_actions_for_entity()                               │
│     → SA_Fight.is_viable(facts)                                   │
│       → facts["is_threat_engageable"] == true?                    │
│         → YES: SA_Fight 可行 → planner 选择 → FightTemplate       │
│         → NO:  SA_Fight 不可行 → 跳过 → fallback 到 PatrolCamp    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 文件改动清单

### 1. `scripts/systems/s_perception.gd`

**改动位置：** `_process_entity()` 函数末尾（当前 line 225-228 区域）

**新增逻辑：** 在设置 `has_threat` 之后，计算 `is_threat_engageable`

```
现有代码（保留）:
    var has_threat: bool = vision._nearest_enemy != null
    agent.world_state.update_fact("has_threat", has_threat)

新增代码:
    var is_engageable: bool = false
    if has_threat:
        is_engageable = _is_threat_engageable(entity, transform, vision._nearest_enemy)
    agent.world_state.update_fact("is_threat_engageable", is_engageable)
```

**新增函数：** `_is_threat_engageable(observer: Entity, observer_transform: CTransform, target: Entity) -> bool`

逻辑：
1. 如果 observer 没有 CWeapon → return true（近战实体总是 engageable，因为有 ChaseStep）
2. 获取 weapon.attack_range × engagement_multiplier → engagement_range
3. 获取 observer 和 target 的 grid 坐标
4. 先做快速欧几里得距离检查：如果 world_distance <= engagement_range → return true（无需寻路）
5. 如果 world_distance > engagement_range：
   - 调用 `LOCAL_NAVIGATION_UTILS.find_path(map, from_grid, to_grid, nav_context, max_radius, max_visited)`
   - 如果 path.is_valid 且 `path.total_cost * tile_step_size <= engagement_range` → return true
   - 否则 → return false

**常量：**
```
const ENGAGEMENT_RANGE_MULTIPLIER: float = 0.8
const ENGAGEMENT_MAX_RADIUS_TILES: int = 12
const ENGAGEMENT_MAX_VISITED: int = 320
```

**为什么放在 s_perception 而非 s_semantic_translation：**
- s_perception 已有 LOD 节流（每 0.15s 一次，非每帧），BFS 开销可控
- s_perception 已有 `_candidate_is_reachable()` 的先例，用相同的 API
- s_semantic_translation 每帧运行无节流，放 BFS 会导致 N×60 次/秒的寻路调用

### 2. `scripts/gameplay/goap/strategic_actions/sa_fight.gd`

**改动：** `viability_gate` 从 `["has_threat"]` 改为 `["is_threat_engageable"]`

```
改前:
    viability_gate = ["has_threat"]

改后:
    viability_gate = ["is_threat_engageable"]
```

**preconditions 不变：** 保持 `{"has_threat": true}`。这确保 planner 的 A* 搜索中仍然要求 `has_threat = true` 才能匹配 SA_Fight。viability_gate 是预过滤（快速拒绝），preconditions 是精确匹配。

**效果：**
- `is_threat_engageable = false` 时：SA_Fight 在 viability 阶段就被过滤掉，planner 不会考虑它
- `is_threat_engageable = true` 时：通过 viability，planner 检查 preconditions `has_threat = true`（此时必然为 true，因为 engageable 蕴含 has_threat）

### 3. `scripts/gameplay/goap/steps/attack_step.gd`

**改动位置：** `_loop_ranged()` 函数，line 129-132

**改动：** out-of-range 时返回 `StepResult.COMPLETED` 而非 `StepResult.RUNNING`

```
改前:
    if distance > max_range:
        weapon.can_fire = false
        movement.velocity = Vector2.ZERO
        return StepResult.RUNNING

改后:
    if distance > max_range:
        weapon.can_fire = false
        movement.velocity = Vector2.ZERO
        return StepResult.COMPLETED
```

**效果：**
- FightTemplate 只有一个 step（AttackStep），step 返回 COMPLETED → template 结束
- `s_plan_execution.gd` 设置 `needs_decision = true`
- 下一个 decision tick：重新评估 goals → 重新检查 `is_threat_engageable`
- 如果敌人仍在射程外 → SA_Fight 不可行 → fallback 到 Patrol
- 如果敌人已进入射程 → SA_Fight 可行 → 重新进入 Fight → 开火

**防抖动：** 不会出现 Fight→exit→Fight→exit 循环，因为：
- engagement_range = attack_range × 0.8 = 256px
- comfortable_range_max = attack_range × 1.0 = 320px
- 如果 `is_threat_engageable = true`（距离 ≤ 256px），那么 `distance ≤ 256 < 320 = max_range`
- AttackStep 中 `distance > max_range` 不会触发 → 正常开火
- **engagement_range < comfortable_range_max 保证了进入 Fight 时一定在射程内**

### 4. `scripts/gameplay/goap/strategic_actions/sa_guard.gd`

**改动：** `is_viable()` 中的 `has_threat` 检查改为 `is_threat_engageable`

```
改前:
    func is_viable(world_state: Dictionary) -> bool:
        return world_state.get("is_guard", false) and not world_state.get("has_threat", false)

改后:
    func is_viable(world_state: Dictionary) -> bool:
        return world_state.get("is_guard", false) and not world_state.get("is_threat_engageable", false)
```

**原因：** SA_Guard 的 viability 条件是"没有需要打的敌人"。改用 `is_threat_engageable` 后，远处有敌人（has_threat=true）但打不到（is_threat_engageable=false）时，SA_Guard 仍然可行 — 守卫继续守岗而非空转。

### 5. `scripts/systems/s_semantic_translation.gd`

**改动：** 删除 `_translate_threat_presence()` 中对 `has_threat` 的重复写入

```
改前:
    func _translate_threat_presence(...) -> void:
        var has_threat := vision._nearest_enemy != null
        agent.world_state.update_fact("has_threat", has_threat)

改后:
    删除此函数（或保留为空/只保留其他逻辑）
```

**原因：** `has_threat` 和 `is_threat_engageable` 现在都由 `s_perception.gd` 写入（在 LOD 节流的扫描周期内）。`s_semantic_translation` 不再需要重复写入 `has_threat`。

**注意：** `_translate_enemy_in_range()`（设置 `is_threat_in_attack_range`）保留不动 — 它用于其他系统（如 weapon aiming）。

---

## 性能考量

### BFS 开销分析

| 参数 | 值 | 说明 |
|------|-----|------|
| BFS max_radius_tiles | 12 | 比 chase_step 的 18 更小，因为 engagement 只需要判断"能不能到" |
| BFS max_visited | 320 | 比 chase_step 的 640 更小，快速失败 |
| 调用频率 | 每 0.15s 每实体 | 跟随 s_perception 的 LOD 节流 |
| 最坏情况 | 320 nodes × N 个有 CWeapon 的 GOAP 实体 | 当前场景约 1-3 个守卫/治疗师 |

### 快速路径优化

在调用 BFS 之前，先做欧几里得距离检查：
- 如果 `world_distance <= engagement_range` → 直接 return true（不需要寻路验证，因为近距离大概率可达）
- 如果 `world_distance > vision_range` → 直接 return false（不可能 engageable）
- 只有 `engagement_range < world_distance <= vision_range` 的中间区间才需要 BFS

**实际触发 BFS 的场景：** 敌人在 256px~600px 之间，且有墙壁可能阻隔。在 Night Raid 中这是常见场景（敌人从围墙外逼近），但实体数量少（1-3 个守卫），开销可忽略。

### 缓存策略

**不需要额外缓存。** 理由：
- `s_perception` 已有 per-entity timer 节流（0.15s）
- BFS 结果隐含在 `is_threat_engageable` fact 中，写入 world_state 后被 GOAP 系统读取
- Grid version 变化时（墙被破坏），下次 perception scan 自然重新计算
- 如果未来实体数量增加，可以加 `_engagement_cache_frame` 类似 `_pos_cache` 的模式

---

## Per-Entity 配置方案

### engagement_multiplier 的位置

**放在 `CSemanticTranslation` 组件上：**

```gdscript
# c_semantic_translation.gd 新增字段
@export var engagement_range_multiplier: float = 0.8
```

**读取逻辑（在 s_perception.gd 中）：**

```
var semantic := entity.get_component(CSemanticTranslation)
var multiplier := semantic.engagement_range_multiplier if semantic != null else 0.8
var engagement_range := weapon.attack_range * multiplier
```

### 各实体预期配置

| 实体 | CWeapon? | engagement_range_multiplier | 实际 engagement_range | 行为 |
|------|----------|----------------------------|----------------------|------|
| 守卫 (survivor) | 是 (320px) | 0.8 | 256px | 敌人进入 256px 才 Fight |
| 治疗师 (healer) | 是 (320px) | 0.8 | 256px | 同守卫 |
| 武装僵尸 (raider) | 是 (200px) | 0.8 | 160px | 进入 160px 才 Fight |
| Worker | 否 | N/A | ∞（近战总是 engageable） | 看到就可以 Fight |
| 普通僵尸 | 否 | N/A | ∞（近战总是 engageable） | 看到就冲 |
| 兔子 | 无 CSemanticTranslation | N/A | 不受影响 | 不受影响 |

### 为什么不放在 CWeapon 上

- `CWeapon` 是纯武器数据（射程、射速、子弹类型），不应包含 AI 决策参数
- `CSemanticTranslation` 的职责就是"感知→决策的翻译配置"，engagement multiplier 属于这个语义
- 如果实体没有 `CSemanticTranslation`（如兔子），自然不受影响

---

## 对现有系统的影响

### s_perception.gd 中的 `_should_track_as_threat()`

当前逻辑（line 272-274）：
```gdscript
if observer.has_component(CWeapon):
    return true    # 有武器的玩家阵营实体：跳过可达性检查
return _candidate_is_reachable(observer, candidate)
```

**这里有一个现有的设计决策：** 有 CWeapon 的玩家阵营实体（守卫/治疗师）对敌人的 threat tracking 跳过了可达性检查。这意味着 `_nearest_enemy` 可以是墙另一边的不可达敌人。

**新增的 `_is_threat_engageable()` 会补上这个缺口：** 即使 `_nearest_enemy` 是不可达的（因为跳过了 reachability check），`is_threat_engageable` 的 BFS 会正确判断为 false。

### SA_Guard 的 viability 变化

改前：有敌人（has_threat=true）→ SA_Guard 不可行 → 守卫不会回岗
改后：有敌人但打不到（is_threat_engageable=false）→ SA_Guard 可行 → 守卫可以回岗

这是正确的行为：远处有敌人但打不到时，守卫应该继续守岗/巡逻，而非空转。

### EliminateThreat Goal 的满足条件

EliminateThreat 的 desired state 是 `{has_threat: false}`。当 `has_threat = true` 但 `is_threat_engageable = false` 时：
- EliminateThreat 目标不满足（has_threat=true ≠ desired false）
- 但 SA_Fight 不可行（is_threat_engageable=false）
- planner 找不到可行 action → 跳过此 goal
- 继续评估下一优先级 goal（PatrolCamp）

**不会死循环：** planner 跳过找不到 action 的 goal 是正常行为，不会重试。

### 对 `s_semantic_translation.gd` 的 `_translate_threat_presence()` 的处理

当前 `s_semantic_translation` 和 `s_perception` 都写入 `has_threat`（重复写入）。改动后：

- `s_perception`：写入 `has_threat` 和 `is_threat_engageable`（在 LOD 节流的扫描中）
- `s_semantic_translation`：删除 `_translate_threat_presence()` 中的 `has_threat` 写入

**风险：** `s_semantic_translation` 每帧运行，`s_perception` 每 0.15s 运行。删除 semantic translation 的写入后，`has_threat` 的更新频率从"每帧"降为"每 0.15s"。

**影响评估：** 0.15s 的延迟对 AI 决策无感知影响（GOAP decision tick 本身也有 update_interval 节流）。且 `s_perception` 在检测到 `_nearest_enemy != null` 时会切换到全速率扫描（不降频），所以威胁出现后的响应不会有额外延迟。

---

## 测试验证方案

### 1. 单元测试：`test_engagement_range.gd`

| 测试用例 | 场景 | 预期 |
|----------|------|------|
| `test_ranged_entity_engageable_in_range` | 守卫有 CWeapon(320px)，敌人在 200px，无障碍 | `is_threat_engageable = true` |
| `test_ranged_entity_not_engageable_out_of_range` | 守卫有 CWeapon(320px)，敌人在 400px，无障碍 | `is_threat_engageable = false` |
| `test_ranged_entity_not_engageable_behind_wall` | 守卫有 CWeapon(320px)，敌人在 200px 直线距离，但被墙隔开（寻路距离 > 256px） | `is_threat_engageable = false` |
| `test_melee_entity_always_engageable` | 僵尸无 CWeapon，敌人在 500px | `is_threat_engageable = true` |
| `test_engagement_multiplier_configurable` | 守卫 engagement_range_multiplier=0.5，敌人在 200px | `is_threat_engageable = false`（256×0.5/0.8=160px threshold） |
| `test_sa_fight_not_viable_when_not_engageable` | world_state = {has_threat: true, is_threat_engageable: false} | `SA_Fight.is_viable() = false` |
| `test_sa_fight_viable_when_engageable` | world_state = {has_threat: true, is_threat_engageable: true} | `SA_Fight.is_viable() = true` |
| `test_sa_guard_viable_when_threat_not_engageable` | world_state = {is_guard: true, has_threat: true, is_threat_engageable: false} | `SA_Guard.is_viable() = true` |

### 2. 自动化 Playtest：Night Raid

运行 `gol test playtest --suite night_raid --record`，验证：

- 守卫在敌人远处时继续巡逻（不站桩）
- 敌人进入 engagement range 后守卫开始射击
- 守卫不会冲出围墙
- 敌人被墙隔开时守卫不会尝试 Fight

### 3. 回归测试

- `gol test unit --suite ai` — 现有 AI 测试通过
- `gol test unit --suite system` — 现有系统测试通过
- `gol test playtest --suite night_raid` — 夜袭流程完整通过所有 checkpoint

---

## 实现顺序

1. **`c_semantic_translation.gd`** — 新增 `engagement_range_multiplier` 字段
2. **`s_perception.gd`** — 新增 `_is_threat_engageable()` 函数和 world_state 写入
3. **`sa_fight.gd`** — viability_gate 改为 `["is_threat_engageable"]`
4. **`sa_guard.gd`** — is_viable() 改用 `is_threat_engageable`
5. **`attack_step.gd`** — out-of-range 返回 COMPLETED
6. **`s_semantic_translation.gd`** — 删除 `_translate_threat_presence()` 中的 has_threat 重复写入
7. **单元测试** — `test_engagement_range.gd`
8. **Playtest 验证** — night_raid 录像确认

---

## 风险矩阵

| 风险 | 级别 | 缓解措施 |
|------|------|----------|
| BFS 性能开销 | 低 | 快速路径优化（欧几里得预检）+ 小 radius/visited + LOD 节流 |
| has_threat 更新频率降低 | 低 | s_perception 在有威胁时不降频；0.15s 延迟对 AI 无感知影响 |
| 守卫在 engagement 边界抖动 | 无 | engagement_range(256) < comfortable_range_max(320)，进入 Fight 时必在射程内 |
| 近战实体行为改变 | 无 | 无 CWeapon 实体 `_is_threat_engageable` 直接返回 true |
| SA_Guard viability 变化 | 低 | 行为更合理：远处有敌人但打不到时继续守岗 |
| AttackStep COMPLETED 导致频繁 replan | 低 | 只在"已进入 Fight 但敌人退出射程"的罕见场景触发；正常流程中 engagement 保证在射程内 |
