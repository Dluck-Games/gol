# Night Assault Director Design

> **Date:** 2026-05-20
> **Status:** Draft
> **Scope:** 夜间袭击节奏系统 + 敌人攻墙行为
> **Related notes:** GOL 怪物威胁度设计, GOL 机制 - TOD, GOL v0.3 版本规划

---

## 1. Overview

为 GOL 添加 **Night Director** 系统，将现有的碎片化出怪机制整合为有节奏的昼夜游戏循环。灵感来源于 Left 4 Dead 的 AI Director——但采用更简洁的时间驱动模型。

核心体验循环：

```
白天（16min）：建造、采集、搜刮，野外零星怪物维持紧张感
    ↓
黄昏（2min）：天空变暗 + 钟表旋转 + 玩家角色自言自语警告
    ↓
夜间（8min）：敌人按渐进曲线出怪（缓慢→升温→峰值）
    ↓
黎明（~1min）：敌人远离营火撤退，spawner 停止，"守住了"仪式感
    ↓
难度随天数线性增长，7-10 晚到达生存极限
```

### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| 压力信号 | 时间驱动渐进曲线 | 玩家直觉理解"活得越久越难"，不产生奇怪的游戏行为（如故意受伤降难度） |
| 夜间节奏 | 渐进升温 + 峰值收尾 | 像拧紧发条，深夜压力持续攀升，黎明前最后一波最猛 |
| 难度增长 | 线性增长，7-10 晚到极限 | 每天都有明确目标感"再活一晚"，作为一局游戏的核心驱动力 |
| 预警方式 | 环境渐变 + 玩家角色自言自语 | 复用现有对话管线和 TOD 视觉，零额外资源。饥荒式设计 |
| 黎明处理 | 敌人远离营火撤退 + spawner 停止 | "守住了"仪式感，玩家能看到敌人离开 |
| 敌人攻墙 | 寻路失败后备行为 | 墙依然迫使敌人绕路，只是不再是永恒屏障。所有敌人行为一致，不做差异化 |
| 难度参数管理 | DirectorTable（GOL.Tables） | 集中管理所有难度策划参数，与代码逻辑解耦，方便调参和未来难度选择 |

### 明确不做的事

- 不引入新的 Service 类
- 不替换 SEnemySpawn 核心逻辑
- 不做基于玩家状态的动态难度调节
- 不做敌人差异化攻墙能力（后续版本）
- 不加入音效（游戏暂无音频系统）
- 不做敌人类型解锁仪式/特殊演出（后续版本）
- 墙被摧毁后不做死亡动画，直接消失

---

## 2. Architecture

```
┌─ DirectorTable (GOL.Tables.director()) ──────────────────┐
│   scripts/gameplay/tables/director_table.gd               │
│   Per-night: spawn_count, recipe_weights, stat_multipliers│
│   Per-phase: intensity_curve, duration_ratios              │
│   Burst: enrage_multiplier, death_burst_count              │
└───────────────────────────────────────────────────────────┘
              ▲ 读取
              │
┌─ SNightDirector (gameplay group) ─────────────────────────┐
│   scripts/systems/s_night_director.gd                      │
│   ├── 监听 TOD 时间，驱动阶段切换                           │
│   ├── 管理 DirectorState（全局 Resource 单例）              │
│   ├── 从 DirectorTable 读取当晩参数                        │
│   ├── 按 spawn_intensity 调整 SEnemySpawn 参数             │
│   ├── 黄昏触发对话警告事件                                  │
│   └── 黎明触发敌人撤退行为                                  │
└───────────────────────────────────────────────────────────┘
              │ 调整参数（调旋钮，不接管）
              ▼
┌─ SEnemySpawn (现有，修改读取逻辑) ─────────────────────────┐
│   读取 DirectorState.spawn_intensity / night_difficulty    │
│   调整实际 spawn_interval 和 recipe_weights                 │
│   读取 DirectorTable 的 enrage / burst 参数                │
└───────────────────────────────────────────────────────────┘
```

### File Structure

| File | Type | Responsibility |
|------|------|---------------|
| `scripts/systems/s_night_director.gd` | New | Director 主逻辑：阶段切换、压力曲线、事件触发 |
| `scripts/resources/director_state.gd` | New | Director 运行时状态（全局单例 Resource） |
| `scripts/gameplay/tables/director_table.gd` | New | 难度策划参数表（GOL.Tables.director()） |
| `scripts/gameplay/goap/facts/goap_fact_path_blocked.gd` | New | GOAP 事实：路径被墙阻挡 |
| `scripts/gameplay/goap/goals/goap_goal_clear_obstacle.gd` | New | GOAP 目标：清除障碍（打墙） |
| `scripts/gameplay/goap/strategic_actions/sa_clear_obstacle.gd` | New | GOAP 战略动作：移向墙 → 攻击墙 |
| `scripts/gameplay/goap/steps/attack_wall_step.gd` | New | GOAP 步骤：对墙执行近战攻击 |
| `scripts/systems/s_enemy_spawn.gd` | Modified | 读取 DirectorState 参数调整出怪行为 |
| `scripts/systems/s_perception.gd` | Modified | 寻路失败时写入 path_blocked 事实 |
| `scripts/gameplay/game_tables.gd` | Modified | 添加 _director + director() accessor |
| `scripts/gameplay/ecs/gol_world.gd` | Modified | 注册 DirectorState 单例 |
| `scripts/ui/` (具体文件 TBD) | Modified | 钟表 HUD 读取 DirectorState.current_phase 变色 |

---

## 3. DirectorState

```gdscript
class_name DirectorState
extends Resource

enum Phase {
    DAYTIME,        # 白天，野外零星出怪
    DUSK_WARNING,   # 黄昏预警，视觉+对话警告
    NIGHT_ACTIVE,   # 夜间出怪，按曲线升温
    NIGHT_PEAK,     # 黎明前峰值
    DAWN_RETREAT,   # 黎明，敌人撤退
}

# ── 全局进度 ──
var night_number: int = 0           # 第几晚（从 1 开始）
var current_phase: Phase = Phase.DAYTIME
var phase_elapsed: float = 0.0      # 当前阶段已持续时间

# ── 夜间压力参数（由 SNightDirector 每帧更新）──
var spawn_intensity: float = 0.0    # 0.0-1.0，当前生成强度
var night_difficulty: float = 0.0   # 0.0-1.0，当晚总难度系数
```

---

## 4. SNightDirector

SNightDirector 是 ECS System，挂在 `gameplay` 组上，每帧执行。

### 4.1 阶段切换

```gdscript
func _update(delta: float) -> void:
    var tod = ServiceContext.tod()
    var time_of_day = tod.get_time_of_day()  # 0.0-1.0，0=午夜

    match current_phase:
        Phase.DAYTIME:
            _update_daytime(delta)
        Phase.DUSK_WARNING:
            _update_dusk_warning(delta)
        Phase.NIGHT_ACTIVE:
            _update_night_active(delta)
        Phase.NIGHT_PEAK:
            _update_night_peak(delta)
        Phase.DAWN_RETREAT:
            _update_dawn_retreat(delta)

func _check_phase_transition() -> void:
    var tod_ratio = _get_time_ratio()
    # 白天 → 黄昏：夜幕前 2 分钟
    if current_phase == Phase.DAYTIME and tod_ratio >= _dusk_threshold():
        _enter_dusk_warning()
    # 黄昏 → 夜间：夜幕降临
    elif current_phase == Phase.DUSK_WARNING and tod_ratio >= _night_start():
        _enter_night_active()
    # 夜间 → 峰值：夜晚最后 2 分钟
    elif current_phase == Phase.NIGHT_ACTIVE and tod_ratio >= _peak_threshold():
        _enter_night_peak()
    # 峰值 → 黎明：天亮
    elif current_phase == Phase.NIGHT_PEAK and tod_ratio >= _dawn_threshold():
        _enter_dawn_retreat()
    # 黎明 → 白天：撤退完成
    elif current_phase == Phase.DAWN_RETREAT and _retreat_complete():
        _enter_daytime()
```

### 4.2 阶段行为

**DAYTIME：**
- Director 不干预 spawner
- 现有 `ALWAYS` 条件 spawner 正常工作（零星出怪）
- `night_number` 保持，不重置

**DUSK_WARNING：**
- 触发一次对话警告事件（内容根据 `night_number` 从台词表选取）
- 不改变出怪行为

**NIGHT_ACTIVE：**
- `spawn_intensity` 按时间线性插值：从 0.2 到 0.8
- SEnemySpawn 读取此值调整 spawn_interval

**NIGHT_PEAK：**
- `spawn_intensity` = 1.0
- 持续到天亮

**DAWN_RETREAT：**
- `spawn_intensity` = 0，所有 spawner 停止生成
- 所有 ENEMY 阵营实体注入 Flee 行为（远离营火方向移动）
- 实体到达地图边缘或超出一定距离后移除
- 撤退完成（无活跃 ENEMY 实体）→ 进入 DAYTIME
- `night_number += 1`

### 4.3 黄昏对话台词

```gdscript
const DUSK_LINES: Dictionary = {
    1: "天快黑了……不太妙。",
    2: "又来了，准备好防御。",
    3: "第三晚了……希望城墙够结实。",
    4: "它们越来越多了。",
    5: "今晚……感觉会很糟糕。",
}
# night_number > 5 时从最后几句中随机选取
```

通过现有对话管线（SDisplayDialogue）触发，不造新系统。

---

## 5. DirectorTable

难度策划参数集中管理表，遵循 GOL.Tables 模式。

```gdscript
class_name DirectorTable
extends RefCounted

## 每晚难度配置
struct NightConfig:
    var night: int                    # 第几晚
    var base_spawn_count: int         # 当晚基础出怪总数
    var spawn_interval_mult: float    # spawn_interval 倍率（越小越密集）
    var recipe_weights: Dictionary    # 敌人配方权重覆盖
    var speed_mult: float             # 敌人移速倍率
    var vision_mult: float            # 敌人视野倍率
    var enrage_burst_count: int       # 暴怒爆发数量
    var enrage_burst_elite: bool      # 暴怒爆发是否含精英

## 夜间阶段时长占比（占 8 分钟黑夜的比例）
var escalate_ratio: float = 0.75     # 升温阶段占比
var peak_ratio: float = 0.25         # 峰值阶段占比

## 白天参数
var daytime_spawn_mult: float = 1.0  # 白天 spawner 倍率

## 难度曲线表
var nights: Array[NightConfig] = []
```

### 5.1 默认难度曲线

基于现有敌人属性和 spawner 参数设计。需要实测调整，以下为初始值：

| Night | 总出怪 | interval 倍率 | 配方权重 | 移速 | 视野 | 暴怒爆发 |
|-------|--------|--------------|----------|------|------|----------|
| 1 | 3 | 1.0 | basic: 100 | 1.0x | 1.0x | 0 |
| 2 | 6 | 0.9 | basic: 80, fast: 20 | 1.05x | 1.0x | 0 |
| 3 | 10 | 0.8 | basic: 60, fast: 20, elemental: 20 | 1.1x | 1.05x | 1 |
| 4 | 15 | 0.7 | basic: 40, fast: 20, elemental: 30, raider: 10 | 1.15x | 1.1x | 2 |
| 5 | 20 | 0.6 | basic: 30, fast: 15, elemental: 35, raider: 20 | 1.2x | 1.15x | 3 |
| 6 | 28 | 0.5 | basic: 25, fast: 15, elemental: 30, raider: 30 | 1.25x | 1.2x | 4 |
| 7 | 35 | 0.4 | basic: 20, fast: 15, elemental: 30, raider: 35 | 1.3x | 1.25x | 5 |
| 8 | 42 | 0.35 | basic: 15, fast: 15, elemental: 30, raider: 40 | 1.35x | 1.3x | 6 |
| 9 | 50 | 0.3 | basic: 15, fast: 10, elemental: 35, raider: 40 | 1.4x | 1.35x | 7 |
| 10+ | 60 | 0.25 | basic: 10, fast: 10, elemental: 35, raider: 45 | 1.5x | 1.5x | 8 |

注：elemental 权重为总池，由 SEnemySpawn 按现有子权重（fire/wet/cold/electric/poison）分配。

### 5.2 配方权重交互

SEnemySpawn 在选择生成配方时，将 DirectorTable 的权重覆盖 GOLWorld 中的默认权重。只有 Director 存在且处于夜间阶段时才覆盖。

```gdscript
# SEnemySpawn 内部
func _get_recipe_weights() -> Dictionary:
    var state = _director_state()
    if state and state.current_phase in [NIGHT_ACTIVE, NIGHT_PEAK]:
        var table = GOL.Tables.director()
        var config = table.get_night_config(state.night_number)
        if config:
            return config.recipe_weights
    return _default_weights  # 现有逻辑
```

---

## 6. SEnemySpawn 修改

Director 通过参数影响 SEnemySpawn，不替换其核心逻辑。

### 6.1 调整的参数

| SEnemySpawn 行为 | Director 影响 | 方式 |
|------------------|--------------|------|
| spawn_interval | spawn_intensity × night_difficulty 越大 → interval 越短 | 读取 DirectorState |
| recipe_weights | 夜间覆盖为 DirectorTable 配置 | 读取 DirectorTable |
| enrage burst count | 使用 DirectorTable 的 enrage_burst_count | 读取 DirectorTable |
| enemy stat multipliers | speed_mult, vision_mult | 生成时应用 |
| spawner active | DAWN_RETREAT 阶段停止 | 读取 DirectorState.phase |

### 6.2 与现有系统的关系

- **Presence Penalty（SPresencePenalty）**：继续独立运行。Director 不干预 enrage 触发条件，但 enrage burst 的数量由 DirectorTable 决定
- **种群上限（enemy: 90）**：保持不变，作为硬上限。Director 的 spawn_count 不应超过此值
- **LOD（距离 LOD）**：保持不变
- **Spawner grace period（45s）**：保持不变

---

## 7. 敌人攻墙行为

### 7.1 行为链条

```
ChaseStep 执行中
  → find_path() 返回无效路径（被墙完全封锁）
    → SPerception 写入 GOAP 事实 path_blocked: true
      → 当前 eliminate_threat 计划失败
        → GOAP 重规划，选中新目标 clear_obstacle
          → AttackWallStep：移向最近阻挡墙 → 近战攻击
            → 墙 HP = 0 → 实体直接移除 + mark_unblocked()
              → 寻路重新畅通 → path_blocked 自动清除
                → 恢复 eliminate_threat 追击
```

### 7.2 新增 GOAP 基础设施

| 新增 | 文件 | 用途 |
|------|------|------|
| GOAP 事实 `path_blocked` | `goap_fact_path_blocked.gd` | 寻路失败时 true，路畅通时 false |
| GOAP 目标 `clear_obstacle` | `goap_goal_clear_obstacle.gd` | 前提 path_blocked: true，优先级 20 |
| StrategicAction `SA_ClearObstacle` | `sa_clear_obstacle.gd` | 模板：MoveToWall → AttackWallStep |
| Step `AttackWallStep` | `attack_wall_step.gd` | 移向墙，进入近战范围后触发攻击 |

### 7.3 GOAP 优先级

```
eliminate_threat (30)  >  clear_obstacle (20)  >  explore (1)
```

敌人优先追击玩家。只有路被墙完全堵死、无法到达目标时，才转而攻击墙。

### 7.4 攻墙行为细节

- 所有敌人行为一致，不做类型差异化
- 敌人就近选择阻挡路径的墙实体
- 使用现有近战攻击系统（SMeleeAttack），攻击目标从 entity 切换为 wall entity
- 墙 HP = 0 后直接移除实体（不走死亡动画），调用 `Service_Map.mark_unblocked()` 更新寻路网格

### 7.5 SPerception 修改

在 SPerception 的感知更新中，增加寻路可达性检查：

```gdscript
# 当 has_threat = true 但 chase 目标不可达时
if vision.has_threat and not _is_target_reachable(entity):
    facts.path_blocked = true
else:
    facts.path_blocked = false
```

可达性检查使用 `Service_Map.is_reachable()`（A* 早期退出，只判断是否可达，不求完整路径）。

---

## 8. 墙被摧毁的连锁反应

```
墙 HP → 0
  → SDamage 添加 CDead
    → SDead 直接移除实体（跳过死亡动画）
      → SBuildSiteComplete 或 mark_unblocked() 更新寻路网格
        → 其他敌人卡住的路径自动失效
          → 下一帧重新寻路 → path_blocked 清除 → 恢复追击
```

复用现有 CDead + 实体移除管线 + 寻路网格更新。墙实体因无 CLosableComponent 等组件，SDead 自然走直接移除路径。

---

## 9. 数据流总结

```
[启动]
  gol.gd / test_main.gd:
    DirectorState 作为全局单例注册
    GOL.Tables 注册 DirectorTable

[每帧 - SNightDirector]
  读取 ServiceTOD 时间
  切换 DirectorState.current_phase
  从 DirectorTable 读取当晩 NightConfig
  按 phase + elapsed 计算 DirectorState.spawn_intensity
  更新 DirectorState.night_difficulty

[每帧 - SEnemySpawn]
  读取 DirectorState.spawn_intensity / current_phase
  读取 DirectorTable 的 recipe_weights / enrage_burst_count
  调整实际 spawn_interval 和配方选择
  DAWN_RETREAT 阶段停止生成

[每帧 - SPerception]
  检测寻路可达性
  写入 path_blocked GOAP 事实

[每帧 - GOAP]
  路径畅通：eliminate_threat（追击玩家/NPC）
  路径被堵：clear_obstacle（打墙）

[每帧 - HUD]
  读取 DirectorState.current_phase
  DUSK_WARNING 时钟表变色
```

---

## 10. 验收标准

### 10.1 Director 核心循环

| ID | 验收条件 | 测试方式 |
|----|----------|----------|
| D1 | 黄昏时玩家角色弹出对话警告 | 集成测试 / 手动验证 |
| D2 | 夜间敌人按曲线出怪，强度随时间增加 | 集成测试：统计不同时间点的出怪数 |
| D3 | 黎明时敌人远离营火撤退 | 集成测试：验证 ENEMY 实体向远离营火方向移动 |
| D4 | 撤退完成后 spawner 停止 | 集成测试：无新敌人生成 |
| D5 | 每晚难度比前一晚更高（更多怪、更快） | 集成测试：比较连续两晚的 spawn_count |
| D6 | 第 1 晚只有 2-3 只基础僵尸 | 集成测试 |

### 10.2 敌人攻墙

| ID | 验收条件 | 测试方式 |
|----|----------|----------|
| W1 | 敌人被墙完全阻挡时转向攻击墙 | 集成测试 |
| W2 | 墙被摧毁后敌人恢复追击 | 集成测试 |
| W3 | 墙被摧毁后寻路网格更新 | 单元测试：mark_unblocked 后 is_position_blocked = false |
| W4 | 多个敌人同时攻击不同墙 | 集成测试 |

### 10.3 DirectorTable

| ID | 验收条件 | 测试方式 |
|----|----------|----------|
| T1 | DirectorTable 正确返回每晚配置 | 单元测试 |
| T2 | 配方权重覆盖生效 | 单元测试：验证夜间 vs 白天的权重 |
| T3 | night_number 超出表范围时使用最后一行配置 | 单元测试 |
