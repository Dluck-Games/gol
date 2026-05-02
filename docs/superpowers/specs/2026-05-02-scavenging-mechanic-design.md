# Scavenging Mechanic Design

> **Date:** 2026-05-02
> **Status:** Draft
> **Version:** V0.3 scope

## Overview

搜刮是 GOL 的核心资源获取机制之一，与采集（可再生资源）互补，提供不可再生的高价值物品。玩家靠近废弃车辆、垃圾桶等搜刮点后长按交互键，进入一个 6-10 秒的**渐进式检定过程**——每秒独立判定是否掉落物品，越往后掉落概率越高、品质越好。物品掉落在地上由玩家拾取。

搜刮是连接**探索系统**和**生存系统**的桥梁：城市区域搜刮点密集但危险，郊区稀少但安全，驱动玩家做出风险-回报决策。

### Design Pillars

1. **渐进式紧张感**：搜刮不是读条等待，每一秒都是"继续还是跑"的微决策
2. **探索驱动**：高价值搜刮点集中在危险区域，推动玩家离开安全区
3. **不可逆承诺**：松手即耗尽，已消耗的秒数不可恢复
4. **蓝图获取重心转移**：搜刮成为蓝图的主要获取途径，怪物掉率降低

## Gameplay Mechanics

### Core Loop

```
接近搜刮点 → 显示提示 → 长按 E 开始搜刮 → 每秒检定 → 物品掉地上
                                              ↓
                           松手 / 完成 → 标记已搜刮 → 拾取地上物品
```

### Progressive Tick System

搜刮是一个**离散 tick 过程**，而非连续计时器：

- 每个搜刮点有固定的 **total_ticks**（垃圾桶 6，车辆 10）
- 每 **1 秒** 触发一次检定 tick
- 每次 tick 独立掷骰：命中 → 从当前阶段掉落池抽取物品并 spawn
- 掉落的物品散落在搜刮点周围（scatter_radius），玩家触碰拾取
- **松手立即终止**，搜刮点标记为 `depleted = true`，剩余 tick 作废
- **已掉落的物品保留在地上**，不会因为中断而消失

### Phased Loot Tables

每个搜刮点类型关联一个**分阶段掉落表**，掉落概率和品质随 tick 递增：

#### 废弃车辆（vehicle） — 10 ticks

| 阶段 | Tick 范围 | 每 tick 掉落概率 | 掉落池 |
|------|-----------|-----------------|--------|
| 早期 | 1-3 | 30% | 基础资源（食物、木材） |
| 中期 | 4-7 | 40% | 中级物资（弹药、材料）+ 蓝图低概率 |
| 后期 | 8-10 | 50% | 稀有物品（组件、配方）+ 蓝图高概率 |

#### 垃圾桶（trash_bin） — 6 ticks

| 阶段 | Tick 范围 | 每 tick 掉落概率 | 掉落池 |
|------|-----------|-----------------|--------|
| 早期 | 1-3 | 35% | 基础资源（食物） |
| 后期 | 4-6 | 45% | 混合资源（食物、木材）+ 蓝图极低概率 |

### Empty-Handed Probability

完整搜完后空手而归的概率需要足够低，让"认真搜完还空手"成为极小概率事件：

- **车辆**：(0.7)³ × (0.6)⁴ × (0.5)³ ≈ **0.56%**
- **垃圾桶**：(0.65)³ × (0.55)³ ≈ **4.6%**

只搜了前几秒就跑的玩家空手概率显著更高，这是符合预期的。

### Blueprint Integration

搜刮成为蓝图获取的**主要途径**，同时降低怪物蓝图掉率：

| 获取路径 | 当前概率 | 调整后概率 | 备注 |
|---------|---------|-----------|------|
| 怪物击杀掉落 | 10% | **3%** | 大幅降低，战斗不再是蓝图主要来源 |
| 建筑 POI 预置 | 1-2 个/地图 | 保持不变 | 初期保底获取 |
| 搜刮 - 车辆后期阶段 | N/A | **每 tick 15%** | 秒 8-10，每秒 15% 概率掉蓝图 |
| 搜刮 - 车辆中期阶段 | N/A | **每 tick 5%** | 秒 4-7，低概率惊喜 |
| 搜刮 - 垃圾桶后期 | N/A | **每 tick 3%** | 秒 4-6，极低但存在 |

蓝图掉落使用现有的 `BLUEPRINT_RECIPES` 列表随机选择，spawn 方式与怪物掉落一致（`ServiceContext.recipe().create_entity_by_id(blueprint_recipe_id)`，带 `CBlueprint` 组件）。

### Interruption Rules

- **松手 / 走出范围**：搜刮立即中断
- 搜刮点标记为 `depleted = true`（**一次性耗尽，不保存进度**）
- 已掉落的物品保留在地上，不会消失（受 `CLifetime` 限制，120 秒后自动清除）
- 搜刮点外观变为已搜刮状态（半透明）

### NPC Behavior

V0.3 中 **NPC 不参与搜刮**。原因：

1. 搜刮有随机性，NPC 自动搜刮会削弱玩家的"开箱惊喜感"
2. 搜刮点不可再生，NPC 搜刮会抢占玩家资源
3. 搜刮是推动玩家亲自探索的核心动力

## Visual & Feedback Design

### Interaction Hint

靠近搜刮点时显示提示，复用现有 `InteractionHintStyle` 系统：

- **垃圾桶**：`[E] 长按搜索 · 垃圾桶`
- **车辆**：`[E] 长按搜索 · 废弃车辆`

提示文字与采集的 `[E] 长按采集` 不同，用"搜索"替代"采集"以形成差异感。

### Progress Bar

复用 `ViewProgressBar`，新增琥珀色配色：

```gdscript
const COLOR_SCAVENGE: Color = Color(0.85, 0.65, 0.13, 1.0)  # 琥珀色/金色
```

进度条基于 `current_tick / total_ticks` 更新，呈阶梯式推进（每 tick 跳一格）而非平滑填充，强化离散检定的节奏感。

### Speech Bubble — "搜索中..." Animation

搜刮时**玩家角色**头顶显示**动画对话气泡**，用于区分搜刮与其他行为（注意：气泡跟随玩家，不是搜刮点）：

#### 显示内容

```
搜索中 ● ○ ○    ← 文字 + 弹跳圆点（动画）
```

三个圆点依次弹跳，形成"加载中"的视觉效果。

#### Animation Specification

- **文字**：`"搜索中"` 静态文字
- **圆点**：3 个圆点字符（`·` 或 `●`），依次执行弹跳动画
- **弹跳周期**：每个圆点上跳耗时 0.2 秒，停留 0.1 秒，下落 0.2 秒，总周期 0.5 秒
- **圆点间延迟**：相邻圆点相隔 0.15 秒开始弹跳，形成波浪效果
- **完整循环**：3 个圆点完成一轮弹跳约 0.8 秒，循环间隔 0.4 秒后重新开始
- **字体**：与现有 `View_SpeechBubble` 一致（白色文字，黑色描边，8px 字号）

#### Implementation Approach

通过 `CSpeechBubble.show_event_text()` 无法实现逐字符动画。需要在搜刮期间由 `SHarvest` 系统在**玩家实体**上直接控制一个专用的动画 Label 节点：

1. 搜刮开始时，在**玩家实体**头顶创建 `_ScavengeLabel` 节点（与 harvest hint 同层）
2. Label 分为两部分：静态文字 `"搜索中"` + 动画圆点容器
3. 圆点动画通过 `_process` 中的简单计时器驱动 y-offset
4. 搜刮结束时移除 `_ScavengeLabel`

#### Existing Speech Bubble — Non-Interference

搜刮动画使用独立的 Label 节点，**不经过 CSpeechBubble/SSpeechBubble 系统**。原因：

- `CSpeechBubble` 的事件文字是一次性显示后自动消失的，不支持持续动画
- 搜刮气泡需要持续显示并有帧动画，这是 speech bubble 系统不支持的
- 使用独立节点避免与饥饿/战斗等高优先级气泡状态冲突

位置偏移：搜刮气泡在**玩家**上方 **-48px**（比 speech bubble 的 -72px 更低），避免视觉重叠。

### Loot Drop Feedback

每次 tick 命中时：

1. 物品实体 spawn 在搜刮点附近（scatter_radius 12-16px）
2. 玩家头顶冒出 `"+1 🥫"` 或 `"+1 🔧"` 的事件文字（复用 `CSpeechBubble.show_event_text()`）
3. 物品有短暂的"弹出"视觉效果（可选，V0.3 可先不做）

### Depleted State Visual

搜刮完成/中断后：

- 搜刮点实体的渲染透明度设为 `0.3`（通过 `CLabelDisplay` 系统的 modulate 控制）
- 文字内容不变，仅透明度降低表示已耗尽

### Placeholder Art

V0.3 无正式美术资源，使用引擎内绘图 + emoji 占位：

| 搜刮物 | 视觉方案 | 尺寸 |
|-------|---------|------|
| 垃圾桶 | `CLabelDisplay` emoji `"🗑️"` + 16×16 深灰 ColorRect 背景 | 16×16 |
| 车辆 | `CLabelDisplay` emoji `"🚗"` + 32×16 深灰 ColorRect 背景 | 32×16 |

占位方案使用 `CLabelDisplay` 系统（与树木 🌳、草 🌱 一致），背景 ColorRect 可选——如果 emoji 足够辨识就不需要额外背景。

## Technical Design

### New Component: CScavengeNode

```gdscript
class_name CScavengeNode
extends Component

## Scavenge type ID, maps to ScavengeTable entry ("vehicle" / "trash_bin")
@export var scavenge_type: String = ""

## Total tick count for this scavenge point
@export var total_ticks: int = 10

## Seconds between each tick
@export var tick_interval: float = 1.0

## Hint text shown when player is in range
@export var hint_label: String = ""

## Runtime state — not exported
var current_tick: int = 0
var depleted: bool = false
```

**设计决策**：不复用 `CResourceNode`，独立组件。原因：

- 搜刮的离散 tick 检定与采集的连续计时器是根本不同的时间模型
- 搜刮需要分阶段掉落表，采集只需固定 yield_type
- 搜刮有蓝图掉落逻辑，采集不需要
- 独立组件为未来扩展（工具需求、陷阱、NPC 搜刮）保留空间

### New Data Table: ScavengeTable

与 `LootTable` 平行的新数据表，存储分阶段掉落配置：

```gdscript
class_name ScavengeTable
extends Resource

## Phase structure:
## {
##     tick_range: [int, int],         # inclusive range [from, to]
##     drop_chance: float,             # probability per tick (0.0 - 1.0)
##     blueprint_chance: float,        # additional independent blueprint check per tick
##     drops: [
##         { type: "resource", resource: String, amount: int, weight: int },
##         { type: "loot", recipe_id: String, weight: int },
##     ]
## }

const TABLES: Dictionary = {
    "vehicle": [
        {
            tick_range = [1, 3],
            drop_chance = 0.30,
            blueprint_chance = 0.0,
            drops = [
                { type = "resource", resource = "RFood", amount = 1, weight = 3 },
                { type = "resource", resource = "RWood", amount = 1, weight = 2 },
            ]
        },
        {
            tick_range = [4, 7],
            drop_chance = 0.40,
            blueprint_chance = 0.05,
            drops = [
                { type = "resource", resource = "RFood", amount = 2, weight = 2 },
                { type = "resource", resource = "RWood", amount = 2, weight = 2 },
            ]
        },
        {
            tick_range = [8, 10],
            drop_chance = 0.50,
            blueprint_chance = 0.15,
            drops = [
                { type = "resource", resource = "RFood", amount = 3, weight = 2 },
                { type = "resource", resource = "RWood", amount = 2, weight = 1 },
            ]
        },
    ],

    "trash_bin": [
        {
            tick_range = [1, 3],
            drop_chance = 0.35,
            blueprint_chance = 0.0,
            drops = [
                { type = "resource", resource = "RFood", amount = 1, weight = 4 },
            ]
        },
        {
            tick_range = [4, 6],
            drop_chance = 0.45,
            blueprint_chance = 0.03,
            drops = [
                { type = "resource", resource = "RFood", amount = 1, weight = 3 },
                { type = "resource", resource = "RWood", amount = 1, weight = 2 },
            ]
        },
    ],
}
```

**蓝图掉落独立于普通掉落**：每个 tick 先做普通掉落检定，再做蓝图检定。两者可以同时命中（一个 tick 掉出普通物品 + 蓝图）。

### SHarvest System Extension

在现有 `SHarvest` 中新增 `SCAVENGING` 状态分支：

#### State Machine Extension

```
enum State { IDLE, GATHERING, SCAVENGING, COMPLETE }
                              ↑ new
```

#### Key Behavioral Differences

| | GATHERING (采集) | SCAVENGING (搜刮) |
|---|---|---|
| 时间模型 | 连续 elapsed timer | 离散 tick counter |
| 产出时机 | 完成时一次性结算 | 每 tick 独立掷骰 |
| 产出位置 | 直接进营地 stockpile | 掉落在地上 |
| 进度条颜色 | 绿色 `COLOR_HARVEST` | 琥珀色 `COLOR_SCAVENGE` |
| 打断后状态 | 目标不受影响 | 目标标记已耗尽 |
| 提示文字 | `[E] 长按采集` | `[E] 长按搜索 · {hint_label}` |
| 头顶气泡 | 无 | "搜索中..." 弹跳动画 |

#### SCAVENGING State Process Logic

```
每帧执行:
  1. 检查目标有效性（范围、是否被销毁）
  2. 检查 interact 键是否持续按下
  3. 累计 tick_elapsed += delta
  4. if tick_elapsed >= tick_interval:
       tick_elapsed -= tick_interval
       current_tick += 1
       执行掉落检定（普通 + 蓝图）
       更新进度条 (current_tick / total_ticks)
  5. 更新搜索气泡动画
  6. if current_tick >= total_ticks:
       标记 depleted, 进入 COMPLETE
```

#### Loot Spawn on Tick Hit

当 tick 检定命中时，spawn 逻辑：

1. **普通资源掉落**：创建 `CResourcePickup` 实体（与采集产出类型一致），散落在搜刮点周围
2. **蓝图掉落**：调用与 `SDamage._try_drop_blueprint()` 相同的逻辑——从 `BLUEPRINT_RECIPES` 随机选一个，通过 `ServiceContext.recipe().create_entity_by_id()` 创建，设置 `CBlueprint.component_type`

### Entity Recipes

新增两个 recipe `.tres` 文件：

#### `resources/recipes/scavenge_vehicle.tres`

```
Components:
- CTransform          (position set by GOLWorld)
- CCollision          (CircleShape2D, radius = 16)
- CLabelDisplay       (text = "🚗", font_size = 24)
- CScavengeNode       (scavenge_type = "vehicle",
                        total_ticks = 10,
                        tick_interval = 1.0,
                        hint_label = "废弃车辆")
```

#### `resources/recipes/scavenge_trash_bin.tres`

```
Components:
- CTransform          (position set by GOLWorld)
- CCollision          (CircleShape2D, radius = 12)
- CLabelDisplay       (text = "🗑️", font_size = 20)
- CScavengeNode       (scavenge_type = "trash_bin",
                        total_ticks = 6,
                        tick_interval = 1.0,
                        hint_label = "垃圾桶")
```

### Config Constants

在 `Config` 中新增搜刮相关常量：

```gdscript
## ── Scavenging ──────────────────────────
static var SCAVENGE_RANGE: float = 32.0              # 交互触发距离
static var SCAVENGE_CANCEL_RANGE_MULT: float = 2.0   # 取消距离 = RANGE × MULT (64px)
static var SCAVENGE_SCATTER_RADIUS: float = 16.0      # 掉落物散布半径
static var SCAVENGE_DEPLETED_ALPHA: float = 0.3       # 已搜刮半透明度

## Blueprint drop chance adjustment
static var BLUEPRINT_DROP_CHANCE: float = 0.03        # 怪物蓝图掉率: 10% → 3%
```

### Blueprint Drop Chance Adjustment

修改 `Config.BLUEPRINT_DROP_CHANCE` 从 `0.1` 降为 `0.03`。

这是一个单行配置改动，影响 `SDamage._try_drop_blueprint()` 中的检定：
```gdscript
if randf() >= Config.BLUEPRINT_DROP_CHANCE:  # 0.1 → 0.03
    return
```

### PCG Integration

#### New POIType

在 `POIList.POIType` 枚举中新增：

```gdscript
enum POIType {
    BUILDING = 0,
    VILLAGE = 1,
    ENEMY_SPAWN = 2,
    LOOT_SPAWN = 3,
    SCAVENGE = 4,       # new
}
```

#### GOLWorld Spawn Method

在 `_spawn_default_entities()` 中新增 `_spawn_scavenge_points()` 调用：

```gdscript
func _spawn_default_entities() -> void:
    # ... existing spawns ...
    _spawn_scavenge_points()     # new
```

#### Zone-Based Placement Rules

搜刮点不使用 POI 系统的 `SCAVENGE` 类型——而是基于 PCG grid 的 **cell 类型** 直接放置，与树木散布 (`_scatter_trees`) 模式类似：

| 条件 | 垃圾桶 | 车辆 |
|------|--------|------|
| 建筑旁 cell（`is_sidewalk()` 且有相邻 `is_building()`） | 40% 概率 | — |
| 道路 cell（`is_road()`） | — | 15% 概率 |
| 人行道 cell（`is_sidewalk()` 不靠近建筑） | 10% 概率 | 5% 概率 |
| 草地 cell | — | — |

放置约束：
- 最小间距 48px（搜刮点之间）
- 排除 POI 中心 64px 范围（不与营地/刷怪点重叠）
- 全局上限：垃圾桶 ≤ 30 个，车辆 ≤ 15 个

**城市 vs 郊区的密度差异**自然产生：城市区域有更多 building/road/sidewalk cell，郊区主要是 grass cell，搜刮点自然集中在城市。不需要额外的区域判断逻辑。

## Peripheral System Updates

### Input Hints

`SHarvest` 的 hint 系统需要区分采集和搜刮：

```gdscript
# 现有采集
const HARVEST_HINT_TEXT: String = "[E] 长按采集"

# 新增搜刮（动态拼接）
func _get_scavenge_hint_text(node: CScavengeNode) -> String:
    return "[E] 长按搜索 · %s" % node.hint_label
```

Hint panel 的样式（背景色、字体、位置偏移）与采集一致，不需要额外定制。

### `_find_nearest_harvestable()` Extension

现有方法搜索 `CResourceNode` 和 `CEatable`，新增 `CScavengeNode` 分支：

```gdscript
func _find_nearest_harvestable(player_pos: Vector2) -> Entity:
    # ... existing CResourceNode search ...
    # ... existing CEatable search ...

    # New: CScavengeNode search
    var scavenge_nodes := ECS.world.query.with_all([CScavengeNode, CTransform]).execute()
    for entity in scavenge_nodes:
        var node: CScavengeNode = entity.get_component(CScavengeNode)
        if node.depleted:
            continue
        var dist_sq := player_pos.distance_squared_to(
            entity.get_component(CTransform).position)
        if dist_sq < best_dist_sq:
            best = entity
            best_dist_sq = dist_sq

    return best
```

### Resource Spawn on Tick

资源类掉落（食物、木材）走现有的 `CResourcePickup` + `ServiceContext.recipe()` 路径：

1. 查找当前 tick 所在阶段的 drops 配置
2. 按 weight 加权随机选一个 drop entry
3. 如果 `type == "resource"`：创建对应的 resource pickup 实体（如 `food_pile`）
4. 如果 `type == "loot"`：创建对应 recipe 实体
5. 设置位置为搜刮点位置 + 随机偏移（scatter_radius 内）

蓝图掉落独立判定，逻辑复用 `SDamage._try_drop_blueprint()` 的 spawn 代码（提取为公共方法或放在 `ScavengeTable` 中）。

## Scope Boundaries

### V0.3 Included

- [x] CScavengeNode 组件
- [x] ScavengeTable 分阶段掉落表
- [x] SHarvest 搜刮状态分支
- [x] 搜刮中 "搜索中..." 弹跳圆点气泡动画
- [x] 琥珀色进度条
- [x] 两种搜刮物：垃圾桶、废弃车辆
- [x] 占位美术（emoji + CLabelDisplay）
- [x] 一次性耗尽 + 已搜刮半透明
- [x] 蓝图搜刮掉落 + 怪物蓝图掉率调整
- [x] PCG 基于 cell 类型的搜刮点放置
- [x] 交互提示文字更新

### V0.3 Excluded

- NPC 自动搜刮（未来可作为"侦察兵"职业技能）
- 搜刮点每日刷新
- 搜刮需要工具
- 搜刮陷阱（如搜刮时触发敌人）
- 正式美术资源
- 搜刮物品弹出动画
- 受伤打断搜刮（V0.3 只检测松手和走出范围）
- 搜刮音效

## File Change Summary

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `scripts/components/c_scavenge_node.gd` | **新增** | CScavengeNode 组件 |
| `scripts/gameplay/tables/scavenge_table.gd` | **新增** | 分阶段掉落表数据 |
| `scripts/systems/s_harvest.gd` | **修改** | 新增 SCAVENGING 状态、tick 逻辑、气泡动画、hint 文字 |
| `scripts/ui/view_progress_bar.gd` | **修改** | 新增 `COLOR_SCAVENGE` 琥珀色常量 |
| `scripts/configs/config.gd` | **修改** | 新增搜刮常量、调整 `BLUEPRINT_DROP_CHANCE` |
| `scripts/pcg/data/poi_list.gd` | **修改** | 新增 `SCAVENGE` POIType |
| `scripts/gameplay/ecs/gol_world.gd` | **修改** | 新增 `_spawn_scavenge_points()` |
| `resources/recipes/scavenge_vehicle.tres` | **新增** | 废弃车辆实体配方 |
| `resources/recipes/scavenge_trash_bin.tres` | **新增** | 垃圾桶实体配方 |
| `scripts/components/AGENTS.md` | **修改** | 组件目录更新 |
