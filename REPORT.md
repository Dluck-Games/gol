# 守卫夜袭巡逻 AI 问题调查报告

**日期：** 2026-05-26
**状态：** 已回退代码，待重新实现

---

## 1. 问题背景

在 Night Raid 自动化 playtest 中，守卫（ScenarioGuard）在夜间阶段表现异常：

- 守卫从营地中心出发后，径直走向左下角围墙旁边
- 到达墙边后站立不动，不巡逻、不攻击
- 敌人从外围逼近时，守卫无反应（因为站在墙边远离战斗区域）

预期行为：守卫应在营地围墙内巡逻，发现敌人后主动交战。

---

## 2. 调查过程

### 第一阶段：初步假设

最初怀疑两个独立问题：

1. **子弹打在自家围墙上** — `s_move.gd` 对所有 `_dynamic_blocked` 格子无差别击杀子弹，不区分墙和建筑
2. **守卫岗位位置计算错误** — `_choose_guard_post_position()` 将岗位放在围墙外

### 第二阶段：实现 Fix A + Fix B

- **Fix A（子弹穿墙）**：将 `_dynamic_blocked` 从 `bool` 升级为 `int` 枚举（BLOCKER_WALL / BLOCKER_BUILDING），子弹遇到 WALL 类型时穿过。单元测试通过。
- **Fix B（岗位位置验证）**：在 `_choose_guard_post_position()` 中加入 `is_position_blocked()` 检查，如果候选位置被阻挡则沿方向回退或尝试垂直方向。单元测试通过。

### 第三阶段：视频验证失败

录制 playtest 视频后确认：**Fix B 完全无效**。守卫仍然走到左下角墙边站着不动。

### 第四阶段：深入架构分析

逐层阅读 GOAP 三层架构代码后发现：

- 守卫的 `_at_post_prev` 默认值为 `true`，加上 hysteresis 逻辑，导致 `at_guard_post` 在初始帧就为 `true`
- GuardDuty 目标（priority=60）在第一帧就已满足，GOAP 规划器跳过它
- 规划器选择 PatrolCamp 目标（priority=1）→ SA_Patrol → PatrolTemplate → PatrolStep
- PatrolStep 在夜间调用 `PlayerSafeZoneUtils.try_find_wall_edge_patrol_position()`
- **这才是守卫走向墙边的真正原因**

---

## 3. 根因分析

### 直接原因

`patrol_step.gd` → `_generate_safe_patrol_waypoint()` 在夜间（`ECSUtils.is_night()` 为 true）时调用：

```
PlayerSafeZoneUtils.try_find_wall_edge_patrol_position(guard_pos, min_distance, true)
```

该函数的选点逻辑：

1. 收集所有玩家阵营的 barrier cells（围墙格子）
2. 对每个 barrier cell 的四邻居，筛选可行走的格子作为候选
3. 用 `abs(distance - target_distance)` 打分，选距离最接近 128px 的候选

### 为什么总是同一个点

- Dictionary 的 key 迭代顺序是确定性的（基于插入顺序）
- 围墙注册顺序固定（先上下行，再左右列）
- 打分函数没有随机化，相同输入永远产生相同输出
- 结果：每次 PatrolStep 重新进入时，都选到同一个墙边格子

### 为什么守卫站着不动

1. PatrolStep 生成 waypoint → 守卫走到墙边 → 到达 → 返回 COMPLETED
2. PatrolTemplate（loops=true）重新进入 PatrolStep
3. PatrolStep 再次调用 wall_edge_patrol → 选到相同/极近的点
4. 守卫"到达"新 waypoint（因为已经在那里）→ 立即 COMPLETED
5. 循环往复，表现为"站着不动"

---

## 4. 已尝试的修复及失败原因

### Fix B：guard_post_position 验证

**做了什么：** 在 `_choose_guard_post_position()` 中检查候选格子是否被 `is_position_blocked()` 阻挡，如果是则回退寻找未阻挡的格子。

**为什么失败：**

1. 守卫的可见行为根本不是由 GuardDuty/guard_post_position 驱动的 — 由于 hysteresis 默认值，GuardDuty 目标在第一帧就已满足
2. 守卫实际执行的是 PatrolCamp → PatrolStep → wall_edge_patrol 路径
3. Fix B 修的是 guard_post_position 的几何计算，但守卫从未执行 SA_Guard 动作
4. 即使 guard_post_position 正确，`is_position_blocked()` 只检查目标格子本身是否是墙，不检查从当前位置能否寻路到达（围墙外的空地返回 false）

---

## 5. 最终决策

**简化巡逻逻辑：白天黑夜统一用随机选点。**

设计原则：
- 守卫不管白天黑夜，都在 `patrol_radius` 内随机选择可到达的点作为 waypoint
- 删除夜间 `PlayerSafeZoneUtils.try_find_wall_edge_patrol_position()` 特殊路径
- 增加寻路可达性验证，确保候选点从当前位置可以走到

---

## 6. 后续计划

### 需要改动的文件

| 文件 | 改动 |
|------|------|
| `scripts/gameplay/goap/steps/patrol_step.gd` | 删除 `_generate_safe_patrol_waypoint()` 中的夜间 wall-edge 分支，统一为随机选点 + 可达性验证 |
| `scripts/utils/player_safe_zone_utils.gd` | 确认无其他调用者后可删除，或保留但 patrol 不再引用 |

### 不需要改动的文件

- `s_semantic_translation.gd` — guard_post_position 逻辑与巡逻 waypoint 无关
- `guard_template.gd` / `patrol_template.gd` — 模板层不变
- `c_guard.gd` — 参数不变
- GOAP 框架层（`s_goal_decision.gd`, `s_plan_execution.gd`）— 不变

### 大致方向

1. `_generate_safe_patrol_waypoint()` 去掉 `if ECSUtils.is_night()` 分支
2. 对随机生成的候选 waypoint 增加局部寻路验证（`_find_local_patrol_path()` 确认路径存在）
3. 保留重试机制（N 次尝试，失败则用当前位置）

### 独立遗留问题

- Fix A（子弹穿墙）的设计方向正确，需要重新实现
- guard_post_position 落在围墙外的问题仍存在，但优先级低（当前 GuardDuty 目标因 hysteresis 默认值不会触发）
