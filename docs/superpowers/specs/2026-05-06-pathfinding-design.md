# Pathfinding System Design

**Date:** 2026-05-06
**Status:** Draft
**Scope:** Service_Map 扩展 + Service_PCG 精简 + NPC 寻路 + 玩家阻挡

---

## 1. 目标

为 GOL 添加寻路能力，支撑墙体建筑、门、营火等玩法。NPC 能绕障碍移动，玩家被障碍物理阻挡。

**明确不做的事：**
- 不引入 Service_Navigation（合入 Service_Map）
- 不使用 Godot NavigationServer2D / AStar2D
- 不使用异步队列/分帧调度
- 不使用 signal 通知
- 不引入同步专用 Component（CNavigationDirty 等）

---

## 2. 架构决策

### 2.1 Service 职责重划

```
Service_PCG (精简)
├── generate(config) → PCGResult
└── _ensure_minimum_pois()
    结束。不再持有查询方法。

Service_Map (扩展为地图唯一真相来源)
├── 坐标转换
├── 地形/区域/POI 查询
├── 动态障碍管理
└── 寻路
```

### 2.2 Service_PCG 删除的方法

| 方法 | 迁移目标 |
|---|---|
| `get_zone_map()` | `Service_Map.get_zone_map()` |
| `get_road_cells()` | `Service_Map.get_road_cells()` |
| `find_nearest_village_poi()` | `Service_Map.find_nearest_village_poi()` |

### 2.3 数据流

```
[启动]
  gol.gd:
    var result = ServiceContext.pcg().generate(config)
    ServiceContext.map().accept_pcg_result(result)

[运行时写入] — System 在逻辑发生处直接调用
  SBuildSiteComplete → map.mark_blocked(pos)
  S拆除逻辑         → map.mark_unblocked(pos)
  S门交互           → map.set_door_state(pos, open, faction)
  S营火放置         → map.set_danger_zone(center, radius, cost)
  S营火移除         → map.clear_danger_zone(center, radius)

[运行时读取]
  GOAP MoveTo       → map.find_path(from, to, context)
  SMove             → map.is_position_blocked(pos) (阻挡 + 滑动)
```

---

## 3. Service_Map 完整 API

```gdscript
class_name Service_Map extends ServiceBase

# ─── 生命周期 ─────────────────────────────────────
func setup() -> void
func teardown() -> void
func accept_pcg_result(result: PCGResult) -> void

# ─── 坐标转换 ─────────────────────────────────────
func grid_to_world(grid_pos: Vector2i) -> Vector2
func world_to_grid(world_pos: Vector2) -> Vector2i

# ─── 地形查询 ─────────────────────────────────────
func get_grid() -> Dictionary
func get_cell(pos: Vector2i) -> PCGCell
func is_walkable(pos: Vector2i) -> bool  # 仅 base 层地形（PCG 静态数据）

# ─── 区域/POI 查询 ────────────────────────────────
func get_zone_map() -> ZoneMap
func get_road_cells() -> Dictionary
func get_pois_by_type(poi_type: int) -> Array
func find_nearest_poi(world_pos: Vector2, excluded_types: Array) -> Variant
func find_nearest_poi_of_type(world_pos: Vector2, poi_type: int) -> Variant
func find_nearest_village_poi(center: Vector2) -> Vector2
func get_positions_by_zone(zone_type: int) -> Array[Vector2i]

# ─── 动态障碍管理 ─────────────────────────────────
func mark_blocked(pos: Vector2i) -> void
func mark_unblocked(pos: Vector2i) -> void
func set_door_state(pos: Vector2i, open: bool, owner_faction: int) -> void
func set_danger_zone(center: Vector2i, radius: int, peak_cost: float) -> void
func clear_danger_zone(center: Vector2i, radius: int) -> void

# ─── 寻路 ─────────────────────────────────────────
func find_path(from: Vector2i, to: Vector2i, context: NavigationContext) -> PathResult
func is_path_still_valid(path: PathResult) -> bool
func is_reachable(from: Vector2i, to: Vector2i) -> bool  # A* early-exit，只判断可达
func is_position_blocked(pos: Vector2i) -> bool  # base + dynamic 合并判断（运行时完整状态）

# ─── Cost 查询 ────────────────────────────────────
func get_movement_cost(pos: Vector2i, context: NavigationContext) -> float
```

---

## 4. 数据结构

### 4.1 Service_Map 内部状态

```gdscript
var _pcg_result: PCGResult
var _base_cost: Dictionary = {}        # Dictionary[Vector2i, float] — 地形 cost
var _dynamic_blocked: Dictionary = {}  # Dictionary[Vector2i, bool] — 建筑阻挡
var _doors: Dictionary = {}            # Dictionary[Vector2i, DoorData] — 门状态
var _danger_cost: Dictionary = {}      # Dictionary[Vector2i, float] — 危险区域
var _grid_version: int = 0             # 每次变化 +1
var _path_solver: PathSolver           # A* 算法实例

# 缓存（已有）
var _zone_positions_cache: Dictionary = {}
var _cached_poi_by_type: Dictionary = {}
```

### 4.2 NavigationContext

```gdscript
class NavigationContext:
    var faction: int = -1
    var can_break_doors: bool = false
    var danger_tolerance: float = 1.0  # 0=无视危险, 1=正常回避
```

### 4.3 PathResult

```gdscript
class PathResult:
    var waypoints: Array[Vector2i] = []
    var total_cost: float = 0.0
    var is_valid: bool = false
    var grid_version: int = 0
```

### 4.4 DoorData

```gdscript
class DoorData:
    var is_open: bool = false
    var owner_faction: int = -1
```

---

## 5. Cost 模型

### 5.1 合并公式

```
final_cost(pos, context) = base_cost[pos]
                         + dynamic_cost(pos, context)
                         + danger_cost[pos] * context.danger_tolerance
```

### 5.2 Base Cost（地形）

| logic_type | cost |
|---|---|
| GRASS, DIRT | 1.0 |
| ROAD, SIDEWALK, CROSSWALK | 0.8 |
| WATER | INF |
| BUILDING | INF |

### 5.3 Dynamic Cost（门）

```gdscript
func _get_door_cost(pos: Vector2i, context: NavigationContext) -> float:
    var door = _doors.get(pos)
    if door == null:
        return 0.0
    if door.is_open:
        return 0.0
    if door.owner_faction == context.faction:
        return 2.0
    elif context.can_break_doors:
        return 20.0
    else:
        return INF
```

### 5.4 Danger Cost（营火等）

放置时按曼哈顿距离线性衰减写入 `_danger_cost`：
```
cost = peak_cost * (1.0 - dist / (radius + 1))
```

---

## 6. A* 算法

### 6.1 网格拓扑

菱形 tile，4 方向正交邻居：
```
N = (0, -1)    E = (+1, 0)
S = (0, +1)    W = (-1, 0)
```

所有方向移动代价相同（不需要 √2 对角线修正）。

### 6.2 启发函数

```gdscript
func _heuristic(a: Vector2i, b: Vector2i) -> float:
    return float(abs(a.x - b.x) + abs(a.y - b.y))
```

### 6.3 避免无意义计算（三道防线）

**防线 1 — 直线检测：**
起点到终点之间无障碍 → 返回 [from, to]，不跑 A*。

```gdscript
func _line_of_sight(from: Vector2i, to: Vector2i) -> bool:
    # Bresenham 遍历经过的格子，任一格 blocked → false
    for pos in _bresenham_line(from, to):
        if is_position_blocked(pos):
            return false
    return true
```

**防线 2 — 路径有效检测：**
```gdscript
func is_path_still_valid(path: PathResult) -> bool:
    if path.grid_version == _grid_version:
        return true  # 网格没变，必然有效
    for waypoint in path.waypoints:
        if is_position_blocked(waypoint):
            return false
    return true
```

**防线 3 — 目标未变（GOAP Action 侧）：**
目标格子没变 + 路径有效 → 继续跟随，不重新请求。

---

## 7. GOAP 集成

### 7.1 MoveTo 基类改造

```gdscript
# 核心变化：直线走 → 路径跟随
var _path: PathResult = null
var _current_waypoint_index: int = 0
var _last_target_grid: Vector2i
var _stuck_timer: float = 0.0

func perform(agent, delta) -> bool:
    var map = ServiceContext.map()
    var agent_pos = agent.get_component(CTransform).position
    var agent_grid = map.world_to_grid(agent_pos)
    var target_grid = map.world_to_grid(target_pos)

    # 需要新路径？
    if _needs_new_path(agent_grid, target_grid):
        _path = map.find_path(agent_grid, target_grid, _build_context(agent))
        _current_waypoint_index = 0
        if not _path.is_valid:
            fail_plan(agent)
            return false

    # 卡住检测
    if _check_stuck(agent_pos, delta):
        fail_plan(agent)
        return false

    # 跟随 waypoint
    var wp_world = map.grid_to_world(_path.waypoints[_current_waypoint_index])
    var dir = (wp_world - agent_pos).normalized()
    movement.velocity = dir * movement.max_speed

    if agent_pos.distance_to(wp_world) < WAYPOINT_REACH_THRESHOLD:
        _current_waypoint_index += 1
        if _current_waypoint_index >= _path.waypoints.size():
            return true  # 到达

    return false

func _needs_new_path(agent_grid: Vector2i, target_grid: Vector2i) -> bool:
    if _path == null:
        return true
    if target_grid != _last_target_grid:
        _last_target_grid = target_grid
        return true
    if not ServiceContext.map().is_path_still_valid(_path):
        return true
    return false
```

### 7.2 ChaseTarget 特殊处理

追击活动目标时，目标移动超过 3 格才重算路径：

```gdscript
func _needs_new_path(agent_grid, target_grid) -> bool:
    if _path == null or not ServiceContext.map().is_path_still_valid(_path):
        return true
    var drift = abs(target_grid.x - _last_target_grid.x) + abs(target_grid.y - _last_target_grid.y)
    if drift >= 3:
        _last_target_grid = target_grid
        return true
    return false
```

### 7.3 卡住检测

```gdscript
const STUCK_TIMEOUT: float = 3.0

func _check_stuck(agent_pos: Vector2, delta: float) -> bool:
    if agent_pos.distance_to(_last_position) < 2.0:
        _stuck_timer += delta
    else:
        _stuck_timer = 0.0
        _last_position = agent_pos
    return _stuck_timer >= STUCK_TIMEOUT
```

### 7.4 受影响的 Action 清单

| Action | 改造 |
|---|---|
| MoveTo (基类) | 完整路径跟随 + 卡住检测 |
| MoveToResourceNode | 继承 MoveTo，无额外改动 |
| ChaseTarget | 目标漂移阈值 |
| Wander | 随机选可达格子 → find_path |
| ReturnToCamp | 目标固定，继承 MoveTo |
| Patrol | waypoint 间逐段寻路 |
| SBuildWorker (FSM) | MOVING_TO_* 阶段用 find_path |

---

## 8. SMove 阻挡与滑动

### 8.1 逻辑

在 SMove 现有流程中，速度计算完成后、写入 position 前，加入阻挡检测：

```gdscript
var new_pos = transform.position + movement.velocity * delta
var new_grid = map.world_to_grid(new_pos)

if not map.is_position_blocked(new_grid):
    transform.position = new_pos
else:
    # 分轴滑动
    var slide_x = Vector2(new_pos.x, transform.position.y)
    if not map.is_position_blocked(map.world_to_grid(slide_x)):
        transform.position = slide_x
    else:
        var slide_y = Vector2(transform.position.x, new_pos.y)
        if not map.is_position_blocked(map.world_to_grid(slide_y)):
            transform.position = slide_y
    # 两轴都不行 → 不动，velocity 保留（下帧可能解除）
```

### 8.2 适用对象

所有经过 SMove 处理的实体（含玩家和 NPC）。NPC 正常情况下不会撞墙（寻路已规避），此逻辑作为兜底。

---

## 9. accept_pcg_result 初始化

此方法替代现有 `Service_Map` 的懒加载模式（`get_pcg_result()` 每次检查 PCG 服务）。改为显式交接：PCG 生成完成后由调用方一次性传入，Service_Map 不再运行时访问 Service_PCG。

```gdscript
func accept_pcg_result(result: PCGResult) -> void:
    _pcg_result = result
    _base_cost.clear()
    _dynamic_blocked.clear()
    _doors.clear()
    _danger_cost.clear()
    _grid_version = 0
    _invalidate_caches()

    # 构建 base cost
    for pos in result.grid:
        var cell = result.grid[pos] as PCGCell
        _base_cost[pos] = _logic_type_to_cost(cell.logic_type)

func _logic_type_to_cost(logic_type: int) -> float:
    match logic_type:
        TileAssetResolver.LogicType.GRASS, TileAssetResolver.LogicType.DIRT:
            return 1.0
        TileAssetResolver.LogicType.ROAD, TileAssetResolver.LogicType.SIDEWALK, \
        TileAssetResolver.LogicType.CROSSWALK:
            return 0.8
        TileAssetResolver.LogicType.WATER, TileAssetResolver.LogicType.BUILDING:
            return INF
        _:
            return 1.0
```

---

## 10. 迁移影响

### 10.1 需要修改的调用点

| 当前调用 | 迁移为 |
|---|---|
| `ServiceContext.pcg().last_result.grid` | `ServiceContext.map().get_grid()` |
| `ServiceContext.pcg().get_zone_map()` | `ServiceContext.map().get_zone_map()` |
| `ServiceContext.pcg().get_road_cells()` | `ServiceContext.map().get_road_cells()` |
| `ServiceContext.pcg().find_nearest_village_poi()` | `ServiceContext.map().find_nearest_village_poi()` |
| `pcg_result.grid_to_world(pos)` | `ServiceContext.map().grid_to_world(pos)` |

### 10.2 新增文件

| 文件 | 用途 |
|---|---|
| `scripts/services/impl/service_map.gd` | 扩展现有（已存在） |
| `scripts/navigation/path_solver.gd` | A* 算法实现 |
| `scripts/navigation/navigation_context.gd` | 请求者上下文 |
| `scripts/navigation/path_result.gd` | 路径结果 |

### 10.3 修改文件

| 文件 | 改动 |
|---|---|
| `service_pcg.gd` | 删除 3 个查询方法 |
| `gol.gd` | 启动时增加 `map().accept_pcg_result(result)` |
| `test_main.gd` | 同上 |
| `goap_eval_main.gd` | 同上 |
| `gol_world.gd` | PCG 引用改为 map 引用 |
| `s_world_growth.gd` | 同上 |
| `s_build_operation.gd` | 删除 `_grid_to_world()`，用 map 服务 |
| `s_build_site_complete.gd` | 建筑落成时调 `mark_blocked()` |
| `s_move.gd` | 添加阻挡 + 滑动逻辑 |
| `goap/actions/move_to.gd` | 路径跟随改造 |
| `goap/actions/chase_target.gd` | 漂移阈值 |
| `goap/actions/wander.gd` | 用 find_path |

---

## 11. 实体行为预期

### 11.1 移动实体（受寻路影响）

| 实体 | 寻路行为 | NavigationContext |
|---|---|---|
| **Player** | 不用寻路（手动操控）。SMove 阻挡 + 滑动 | — |
| **Survivor** | Patrol/ReturnToCamp/Chase/Flee 走 find_path | faction=PLAYER, can_break_doors=false, danger_tolerance=1.0 |
| **Survivor Healer** | 同 Survivor | 同 Survivor |
| **NPC Composer** | Wander 走 find_path | faction=PLAYER, can_break_doors=false, danger_tolerance=1.0 |
| **NPC Worker** | MoveToResource/MoveToStockpile 走 find_path | faction=PLAYER, can_break_doors=false, danger_tolerance=1.0 |
| **Enemy Basic** | Chase/Wander 走 find_path | faction=ENEMY, can_break_doors=false, danger_tolerance=1.0 |
| **Enemy Fast** | 同 Enemy Basic，速度更快 | 同 Enemy Basic |
| **Enemy Raider** | Chase/MarchToCampfire 走 find_path | faction=ENEMY, **can_break_doors=true**, danger_tolerance=1.0 |
| **Enemy Cold/Fire/Electric/Wet** | 同 Enemy Basic | 同 Enemy Basic |
| **Enemy Poison** | Chase/Wander 走 find_path | faction=ENEMY, can_break_doors=false, **danger_tolerance=0.0** |
| **Rabbit** | Flee/MoveToGrass/Wander 走 find_path | faction=NEUTRAL, can_break_doors=false, danger_tolerance=1.0 |
| **Bullet** | **不走寻路**。直线飞行，SMove 检测 blocked 则销毁 | — |

### 11.2 静态实体（作为障碍物）

| 实体 | 寻路层角色 | 规则 |
|---|---|---|
| **Wall** | mark_blocked — 绝对阻挡 | 占整格 tile (32×32) |
| **Door（新增）** | set_door_state — 按权限 | 开=通行，关=按 faction 判断 cost |
| **Campfire** | 自身 tile 不阻挡；周围 set_danger_zone | radius 和 peak_cost 由 CDangerZone 定义 |
| **Camp Stockpile** | mark_blocked — 阻挡 | 占整格 tile (32×32) |
| **Enemy Spawner** | mark_blocked — 阻挡 | 占整格 tile |
| **Ghost Building** | 不阻挡 | 施工中，可通行 |
| **Healing Station** | 不阻挡 | 碰撞半径 r=20，不占整格 |
| **Tree** | 不阻挡 | 碰撞半径 r=12，不占整格 |
| **Grass/Carrot/Food Pile/Blueprint** | 不阻挡 | 碰撞半径 ≤16，不占整格 |

### 11.3 阻挡判定原则

**只有占据整格 tile 的实体才调用 `mark_blocked()`。** 碰撞半径小于半格（<16px）的实体不参与寻路网格阻挡。

---

## 12. 验收测试集

遵循 SceneConfig 集成测试模式。每个测试：启动世界 → 放置实体 → 模拟帧 → 断言位置/状态。

### 12.1 基础寻路功能

| ID | 测试名 | 场景设置 | 预期结果 |
|---|---|---|---|
| T1 | `test_npc_pathfinds_around_wall` | Survivor + 目标位置，中间一排墙隔开，侧面有开口 | NPC 在 600 帧内到达目标（绕墙） |
| T2 | `test_npc_direct_path_no_wall` | Survivor + 目标位置，无障碍 | NPC 走近似直线到达（直线检测生效） |
| T3 | `test_npc_unreachable_target` | Survivor + 目标位置，目标被墙完全包围 | NPC 触发 fail_plan，不卡死，3 秒内重规划 |

### 12.2 玩家阻挡与滑动

| ID | 测试名 | 场景设置 | 预期结果 |
|---|---|---|---|
| T4 | `test_player_blocked_by_wall` | 玩家设置 velocity 朝向墙体 | 300 帧后位置未穿过墙体所在 tile |
| T5 | `test_player_slides_along_wall` | 玩家斜 45° 方向撞墙 | 位置沿墙滑动（单轴方向有位移），非完全静止 |
| T6 | `test_player_passes_open_door` | 玩家设置 velocity 朝向开着的门 | 正常通过门所在 tile |
| T7 | `test_player_blocked_by_closed_door` | 玩家设置 velocity 朝向关着的门 | 被阻挡，位置未穿过 |

### 12.3 门权限

| ID | 测试名 | 场景设置 | 预期结果 |
|---|---|---|---|
| T8 | `test_friendly_npc_passes_own_door` | Survivor + 目标，路径经过己方关闭门 | NPC 路径包含门 tile，正常到达目标 |
| T9 | `test_enemy_blocked_by_player_door` | Enemy Basic + 目标，直线经过玩家门（关闭），有绕路 | NPC 绕路到达目标，路径不经过门 |
| T10 | `test_raider_breaks_player_door` | Enemy Raider + 目标，直线经过玩家门（关闭），绕路更远 | Raider 路径经过门（cost=20 < 绕路 cost） |

### 12.4 危险区域回避

| ID | 测试名 | 场景设置 | 预期结果 |
|---|---|---|---|
| T11 | `test_npc_avoids_campfire_zone` | NPC + 目标，直线经过营火 danger zone，有等长绕路 | NPC 选择绕路（danger cost 使直线路径更贵） |
| T12 | `test_npc_crosses_danger_when_forced` | NPC + 目标，唯一路径经过营火 danger zone | NPC 穿越 danger zone 到达目标 |
| T13 | `test_poison_enemy_ignores_danger` | Enemy Poison + 目标，直线经过营火 danger zone | 直线穿过（danger_tolerance=0，danger cost 无效） |

### 12.5 动态变化响应

| ID | 测试名 | 场景设置 | 预期结果 |
|---|---|---|---|
| T14 | `test_path_invalidates_on_wall_placed` | NPC 正在跟随路径 → 中途在路径上放置墙 | NPC 重新寻路，最终到达目标 |
| T15 | `test_path_updates_on_door_opened` | NPC 正在绕路 → 途中门被打开 | 下次 _needs_new_path 检测时走门（路径更短） |
| T16 | `test_wall_removed_opens_path` | NPC 正在绕路 → 墙被拆除 | 下次 _needs_new_path 检测时走新开通路径 |

### 12.6 特殊实体行为

| ID | 测试名 | 场景设置 | 预期结果 |
|---|---|---|---|
| T17 | `test_bullet_destroyed_by_wall` | 子弹射向墙体 | 子弹到达墙 tile 时被销毁，不穿透 |
| T18 | `test_worker_pathfinds_to_stockpile` | Worker + 资源节点 + Stockpile，中间有墙 | Worker 完成采集→搬运循环（绕墙到达 stockpile） |
| T19 | `test_rabbit_flees_around_wall` | Rabbit + 威胁源，墙隔在逃跑方向 | Rabbit 沿可达路径远离威胁（不卡墙） |
| T20 | `test_raider_marches_around_obstacles` | Raider + 营火目标，路上有墙 | Raider 绕障碍持续逼近营火 |

### 12.7 卡住检测

| ID | 测试名 | 场景设置 | 预期结果 |
|---|---|---|---|
| T21 | `test_stuck_detection_triggers_replan` | NPC 开始移动后，在其路径上动态放置墙形成包围 | 3 秒内触发 fail_plan（stuck 检测），不无限循环 |
