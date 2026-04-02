# Issue #193: 角色死亡后无法复活 — Round 2 分析

## 需求分析

**Issue 症状（精确复现步骤）：**
1. 角色正常掉落可掉落组件（触发 `_on_no_hp` 中的组件掉落路径，存活在 1 HP）
2. 随后被怪物攻击致死（再次触发 `_on_no_hp`，此时无可掉落组件，进入 `_start_death`）
3. 鼠标失去对准心控制（`SMove` 不再处理玩家输入）
4. 屏幕短暂停留后，摄像机被重置到了某个地图无人的位置
5. 没有复活流程（玩家卡死，无法操作）

**期望行为：** 死亡后倒计时后，在出生点复活，重新获得控制权。

---

## 影响面分析

### 受影响文件

| 文件 | 角色 | 问题 |
|------|------|------|
| `scripts/gameplay/gol_game_state.gd:74` | 复活逻辑 | **`_respawn_player()` 中对 `create_entity_by_id` 返回的实体重复调用 `ECS.world.add_entity()`，导致新实体被 `queue_free()`** |
| `scripts/services/impl/service_recipe.gd:130` | 实体创建 | `create_entity_by_id` 内部已调用 `add_entity`，返回的实体已在世界中 |
| `scripts/systems/s_dead.gd` | 死亡系统 | `_complete_death` 调用链正确，但上游的 `_respawn_player` 存在 double-add bug |
| `scripts/systems/s_camera.gd` | 摄像机系统 | 新实体的 Camera2D 因 double-add bug 被连带销毁 |
| `scripts/systems/s_damage.gd:549-568` | 伤害系统 | `_kill_entity()` 死代码，无调用点 |

---

## 维度 1：死亡调用链追踪

### 完整调用链（含文件路径和行号）

```
SDamage._on_no_hp(target_entity)                    # s_damage.gd:261
  │
  ├─ [组件掉落检查] losable_count == 0 ?
  │   ├─ YES → drop_count > 0 → hp = 1, 存活（第一次被打时的路径）
  │   └─ NO  → _start_death(target_entity, knockback)  # s_damage.gd:300-302
  │
  └─ _start_death(target_entity, knockback)         # s_damage.gd:571-575
       │ 创建 CDead，添加到 entity
       │ entity.add_component(dead)
       │
       └─ [下一帧] SDead.process() 检测到 CDead + CTransform
            │ s_dead.gd:20-29
            │
            └─ SDead._initialize(entity, dead)       # s_dead.gd:32
                 │ dead._initialized = true
                 │ _remove_interfering_components(entity)   # s_dead.gd:36
                 │   → 移除 Config.DEATH_REMOVE_COMPONENTS 中的组件
                 │   → 注意: CPlayer、CCamp、CCamera 不在列表中
                 │
                 ├─ entity.has_component(CPlayer)? → YES
                 │   └─ _initialize_player_death()   # s_dead.gd:92-110
                 │        │ 锁定移动 (forbidden_move = true)
                 │        │ 播放 "death" 动画
                 │        │ 连接 animation_finished 信号 (ONE_SHOT)
                 │        │
                 │        └─ [动画结束] _on_player_death_animation_finished()  # s_dead.gd:113
                 │             │ dead._tween = entity.create_tween()
                 │             │ dead._tween.tween_interval(PLAYER_RESPAWN_DELAY)  # 3.0s
                 │             │ dead._tween.tween_callback(_complete_death)
                 │             │
                 │             └─ [3秒后] _complete_death(entity, dead)  # s_dead.gd:211
                 │                  │ entity.has_component(CPlayer) → true
                 │                  │ GOL.Game.handle_player_down()    # s_dead.gd:224
                 │                  │   → gol_game_state.gd:15-18
                 │                  │     → if is_game_over: return
                 │                  │     → _respawn_player()          # gol_game_state.gd:54
                 │                  │       ★ 此处存在 double-add bug（见维度 2）
                 │                  │
                 │                  └─ ECSUtils.remove_entity(entity)  # s_dead.gd:227
                 │                       → addons/gecs/ecs/world.gd:393
                 │                       → entity.queue_free() (帧末释放)
                 │
                 ├─ entity.has_component(CSpawner)? → YES
                 │   └─ _initialize_building_death()  # s_dead.gd:58
                 │
                 └─ else → _initialize_generic_death()  # s_dead.gd:127
```

### 关键验证

**可掉落组件为空 vs 非空的两条路径：**

- **非空路径（有可掉落组件）**：`s_damage.gd:293-297` — `drop_count > 0` 时 `hp = 1` 存活，不触发 `_start_death`，不添加 `CDead`，`SDead._initialize()` 不会被调用
- **空路径（无可掉落组件）**：`s_damage.gd:299-302` — `_start_death()` 被调用，`CDead` 被添加，`SDead._initialize()` 正常触发

两条路径都会正确执行：有组件时不进入死亡流程（存活），无组件时进入死亡流程。

**`_complete_death` 对有 `CPlayer` 实体的处理：**

`s_dead.gd:222-224`:
```gdscript
elif entity.has_component(CPlayer):
    if GOL and is_instance_valid(GOL.Game):
        GOL.Game.handle_player_down()
```

条件满足时必定调用 `handle_player_down()`。但 `CPlayer` 不在 `DEATH_REMOVE_COMPONENTS` 中（`config.gd:32-44`），所以 `CPlayer` 在 `_remove_interfering_components` 后仍存在。✅ 此路径正确。

---

## 维度 2：Camera 生命周期分析（核心根因）

### Camera2D 的创建与销毁

| 阶段 | 代码位置 | 行为 |
|------|----------|------|
| 创建 | `s_camera.gd:33-35` | `Camera2D.new()` + `entity.add_child()` + `make_current()` |
| 位置同步 | `s_camera.gd:27-29` | 每帧 `camera.position = transform.position` |
| 销毁 | `s_camera.gd:39-41` | `component.camera.queue_free()` (当 CCamera 被移除时) |
| 实体销毁连带 | `addons/gecs/ecs/world.gd:443-444` | `entity.queue_free()` 连带销毁所有子节点（含 Camera2D） |

### `_complete_death` 执行顺序的帧级分析

```
帧 N (死亡动画完成后的 3s):
  ┌─ Tween callback: _complete_death(old_entity, dead)
  │    ├─ GOL.Game.handle_player_down()
  │    │    └─ _respawn_player()
  │    │         ├─ create_entity_by_id("player")    ← 内部调用 add_entity #1
  │    │         │    → 新实体加入世界，分配 UUID
  │    │         │    → 新实体 CCamera.camera == null
  │    │         │
  │    │         ├─ transform.position = campfire_position
  │    │         ├─ hp.invincible_time = 1.5
  │    │         │
  │    │         └─ ECS.world.add_entity(new_player)  ← add_entity #2 ★ BUG
  │    │              → entity.id 已存在（来自 #1）
  │    │              → entity_id_registry[uuid] == new_player
  │    │              → remove_entity(new_player)      ← 自我移除!
  │    │              → entity.queue_free()             ← 新实体被标记删除!
  │    │              → 重新注册、重新添加到 entities 列表
  │    │              → 但 entity 已 queue_free，帧末将被释放
  │    │
  │    └─ ECSUtils.remove_entity(old_entity)
  │         → old_entity.queue_free()                   ← 旧实体也被标记删除
  │
  ├─ GOLWorld._process(delta)                         ← 同帧稍后执行
  │    └─ ECS.process(delta, "gameplay")
  │         └─ SCamera._process_entity(new_player)
  │              → CCamera.camera == null
  │              → _on_component_created()
  │              → Camera2D.new() + make_current()
  │              → 新 Camera2D 被创建并激活 ✅
  │
  └─ 帧末: idle processing
       ├─ old_entity freed → 旧 Camera2D freed
       └─ new_player freed → 新 Camera2D freed ← ★ 新实体因 queue_free 被连带销毁!
```

**结果：** 帧 N 结束后，没有任何活跃的 Camera2D。帧 N+1，Godot 使用默认视口（无 camera → 显示原点/地图无人位置），这完美解释了 Issue 症状 4 "摄像机被重置到了某个地图无人的位置"。

### 根因代码

`gol_game_state.gd:58` 和 `gol_game_state.gd:74`:
```gdscript
var new_player: Entity = ServiceContext.recipe().create_entity_by_id("player")  # 已调用 add_entity
# ... 设置属性 ...
ECS.world.add_entity(new_player)  # ← 第二次 add_entity，触发 ID 碰撞 → 自我 remove → queue_free
```

`service_recipe.gd:130`:
```gdscript
ECS.world.add_entity(entity)  # create_entity_by_id 内部已将实体加入世界
```

`addons/gecs/ecs/world.gd:296-304`:
```gdscript
if entity_id in entity_id_registry:
    var existing_entity = entity_id_registry[entity_id]
    remove_entity(existing_entity)  # ← 同一实体被移除并 queue_free
```

### 其他调用点对比

| 调用位置 | `create_entity_by_id` 后是否再次 `add_entity`? |
|----------|----------------------------------------------|
| `gol_world.gd:137` (`_spawn_entities_from_config`) | 否 ✅ |
| `s_enemy_spawn.gd:72` | 否 ✅ |
| `s_fire_bullet.gd:117` | 否 ✅ |
| `s_damage.gd:324,425` | 否 ✅ |
| `s_pickup.gd:137` | 否 ✅ |
| `gol_game_state.gd:58,74` (`_respawn_player`) | **是** ❌ |

### `_kill_entity` 与 `component_removed` 信号断连

补充发现：`world.remove_entity()` 在 line 406-409 **先断开** entity 的所有信号（`component_added`、`component_removed`），再在 line 417-419 手动 emit `component_removed`。这意味着 `s_camera.gd:37` 连接的 `entity.component_removed` 信号在 `remove_entity` 时不会被触发。Camera2D 的清理依赖 `entity.queue_free()` 连带销毁子节点，而非 `_on_component_removed` 回调。

---

## 维度 3：`_kill_entity()` 死代码验证

### 搜索结果

在整个代码库中搜索 `_kill_entity`：

```
唯一调用点: s_damage.gd:549 (函数定义本身)
```

**结论：** `_kill_entity()` 在整个代码库中 **零外部调用**，是死代码。

### 与 `_complete_death()` 的关系

| 函数 | 调用时机 | 复活逻辑 | 实体移除 |
|------|----------|----------|----------|
| `SDamage._kill_entity()` (s_damage.gd:549-568) | **从未被调用** | 直接调用 `GOL.Game.handle_player_down()`，不经过死亡动画 | `ECSUtils.remove_entity()` |
| `SDead._complete_death()` (s_dead.gd:211-227) | Tween 回调，死亡动画结束后 | 检查 `CPlayer` 后调用 `GOL.Game.handle_player_down()` | `ECSUtils.remove_entity()` |

`_kill_entity` 是早期实现的遗留代码，功能被 `SDead._complete_death()` 完全替代。

---

## 维度 4：PLAYER_RESPAWN_DELAY 差异

### 当前值

`s_dead.gd:10`:
```gdscript
const PLAYER_RESPAWN_DELAY: float = 3.0
```

### 期望值

Issue 期望 5 秒倒计时。

### 需要修改

将 `PLAYER_RESPAWN_DELAY` 从 `3.0` 改为 `5.0`。

---

## 实现方案

### 根因判断

基于以上 4 个维度的分析，最符合 Issue 症状的故障模式是：

**模式 C 的变体：`_complete_death` 正确触发，`_respawn_player` 执行，但因 double-add bug 导致新实体被 queue_free，camera handoff 失败**

证据链：
1. "摄像机被重置到无人位置" → 证明 `_complete_death` **已执行**（排除了模式 A）
2. `handle_player_down()` 中 `is_game_over` 检查不是问题根因（排除了模式 B，除非确实已 game over，但 Issue 未提及篝火被摧毁）
3. `_respawn_player()` 中 `create_entity_by_id` + `add_entity` 的 double-add 导致新实体被 `queue_free()` → 新 Camera2D 在帧末被连带销毁 → 无活跃 Camera2D → 视口回退到默认位置

### 修复方案

#### 修复 1：`_respawn_player()` double-add bug（根因修复）

**文件：** `scripts/gameplay/gol_game_state.gd`

**方案：** 删除 `_respawn_player()` 中的 `ECS.world.add_entity(new_player)` 调用（line 74），因为 `create_entity_by_id` 已在内部完成 `add_entity`。

```gdscript
# 修复前 (gol_game_state.gd:54-75):
func _respawn_player() -> void:
    campfire_position = _find_campfire_position()
    var new_player: Entity = ServiceContext.recipe().create_entity_by_id("player")
    if not new_player:
        push_error("[Respawn] Failed to create new player entity")
        return
    var transform: CTransform = new_player.get_component(CTransform)
    if transform:
        transform.position = campfire_position
    var hp: CHP = new_player.get_component(CHP)
    if hp:
        hp.invincible_time = 1.5
    ECS.world.add_entity(new_player)  # ← 删除此行
    print("[Respawn] New player spawned at campfire: ", campfire_position)

# 修复后:
func _respawn_player() -> void:
    campfire_position = _find_campfire_position()
    var new_player: Entity = ServiceContext.recipe().create_entity_by_id("player")
    if not new_player:
        push_error("[Respawn] Failed to create new player entity")
        return
    var transform: CTransform = new_player.get_component(CTransform)
    if transform:
        transform.position = campfire_position
    var hp: CHP = new_player.get_component(CHP)
    if hp:
        hp.invincible_time = 1.5
    # create_entity_by_id 已在内部调用 add_entity，无需重复添加
    print("[Respawn] New player spawned at campfire: ", campfire_position)
```

**风险评估：** `create_entity_by_id` → `_instantiate_entity` 在 `add_entity` 之后设置 `entity.name`（line 133）。`_respawn_player` 在 `add_entity` 之后修改 `transform.position` 和 `hp.invincible_time`。修改在 entity 已加入世界之后进行，对于 `position` 和 `invincible_time` 这样的运行时属性是安全的（它们不是 @export 序列化属性，不需要通过 add_entity 的 `_initialize` 深拷贝流程）。

#### 修复 2：PLAYER_RESPAWN_DELAY 3.0 → 5.0

**文件：** `scripts/systems/s_dead.gd`

**修改：** line 10，将 `3.0` 改为 `5.0`。

```gdscript
# 修复前:
const PLAYER_RESPAWN_DELAY: float = 3.0

# 修复后:
const PLAYER_RESPAWN_DELAY: float = 5.0
```

#### 修复 3：删除 `_kill_entity()` 死代码

**文件：** `scripts/systems/s_damage.gd`

**修改：** 删除 `s_damage.gd:549-568` 的 `_kill_entity` 方法。

---

## 架构约束

### 涉及的 AGENTS.md 文件
- `scripts/systems/AGENTS.md` — SDead、SDamage、SCamera 系统修改，遵循 System 模板
- `scripts/components/AGENTS.md` — CDead、CCamera 组件（只读，不修改）
- `scripts/gameplay/AGENTS.md` — GOLGameState 复活流程修改
- `scripts/services/AGENTS.md` — `create_entity_by_id` 语义（返回的实体已在世界中）
- `tests/AGENTS.md` — 测试分层规则

### 引用的架构模式
- **System 模式**（`scripts/systems/AGENTS.md`）：SDead 属于 gameplay group，通过 `ECS.process(delta, "gameplay")` 执行
- **Service Recipe 模式**（`scripts/services/AGENTS.md`）：`create_entity_by_id` 封装了实体创建 + 世界注册
- **ECS 实体生命周期**：`add_entity` 分配 UUID、注册信号、添加到场景树、调用 `_initialize`

### 文件归属层级
- 系统修改 → `scripts/systems/`（s_dead.gd, s_damage.gd）
- 游戏状态修改 → `scripts/gameplay/`（gol_game_state.gd）
- 单元测试 → `tests/unit/system/`
- 集成测试 → `tests/integration/flow/`

### 测试模式
- **单元测试**：`extends GdUnitTestSuite`，手动构造 Entity，不依赖 World/ECS.world
- **集成测试**：复活完整流程涉及 GOLWorld + 多系统交互，应使用 `extends SceneConfig`
- **E2E**：暂停状态下死亡的运行时验证（AI Debug Bridge）

---

## 测试契约

### 用例 1：单元测试 — `create_entity_by_id` 返回的实体已在世界中

**文件：** `tests/unit/service/test_service_recipe.gd`（新增或追加）

**验证逻辑：** 调用 `create_entity_by_id("player")`，断言返回的 entity 不为 null，且该 entity 的 `id` 不为空（说明已通过 `add_entity` 注册）。
> 注意：此测试需要 World 实例。由于 AGENTS.md 规定 unit tests 不能创建 World，此测试更适合放在集成测试中，或通过 mock ECS.world 来验证。

**替代方案（纯单元测试）：** 测试 `_respawn_player` 逻辑不重复调用 `add_entity`——通过 mock `ServiceContext.recipe()` 返回一个假实体，验证 `ECS.world.add_entity` 仅被调用一次。

### 用例 2：集成测试 — 玩家死亡后正确复活

**文件：** `tests/integration/flow/test_flow_player_respawn_scene.gd`（新增）

**验证逻辑：**
1. 通过 SceneConfig 创建 player entity
2. 模拟致死伤害（直接将 CHP.hp 设为 0，或添加 CDamage + 模拟 SDamage 处理）
3. 添加 CDead 触发死亡流程
4. 等待 PLAYER_RESPAWN_DELAY (5s) + 死亡动画时间
5. 验证新 player entity 存在于世界中
6. 验证新 player 位置在篝火附近
7. 验证新 player 的 CHP.invincible_time > 0

### 用例 3：集成测试 — 摄像机在复活后正确跟随新玩家

**文件：** `tests/integration/flow/test_flow_player_respawn_scene.gd`（同文件，附加用例）

**验证逻辑：**
1. 复用用例 2 的场景
2. 在复活后验证 SCamera 系统对新实体创建了 Camera2D（`CCamera.camera != null`）
3. 验证没有残留的旧 Camera2D

### 用例 4：单元测试 — `PLAYER_RESPAWN_DELAY` 常量值验证

**文件：** `tests/unit/system/test_dead_system.gd`（追加）

**验证逻辑：** 断言 `SDead.PLAYER_RESPAWN_DELAY == 5.0`

---

## 风险点

1. **`_respawn_player` 中属性修改时机** — 删除 `add_entity` 后，`transform.position` 和 `hp.invincible_time` 在 entity 已加入世界后修改。由于这些是运行时属性（非 @export），修改是安全的。但如果未来需要在 `add_entity` 的 `_initialize` 中依赖这些值（例如位置初始化），则需要改为在 `add_entity` 前设置。当前代码无此依赖。

2. **`create_entity_by_id` 语义约定** — `Service_Recipe.create_entity_by_id` 内部调用 `add_entity` 是其设计契约。所有现有调用点（`gol_world.gd`、`s_enemy_spawn.gd` 等）都遵循"调用后不再 `add_entity`"的约定。`_respawn_player` 是唯一违反此约定的调用点。

3. **暂停状态下死亡**（上一轮 Planner 发现的次要问题）— 如果游戏在暂停状态下玩家死亡，`entity.create_tween()` 创建的 Tween 会因 `tree.paused = true` 而暂停，`_complete_death` 回调不会触发。当前 Issue 的复现步骤未提及暂停，但这是一个真实的边界条件，应在后续 Issue 中修复。

---

## 建议的实现步骤

### 步骤 1：修复 `_respawn_player` double-add bug
- **文件：** `scripts/gameplay/gol_game_state.gd`
- **操作：** 删除 line 74 的 `ECS.world.add_entity(new_player)`
- **影响：** 修复根因，新 player entity 不再被 queue_free

### 步骤 2：修改 `PLAYER_RESPAWN_DELAY` 为 5.0
- **文件：** `scripts/systems/s_dead.gd`
- **操作：** 修改 line 10，`3.0` → `5.0`
- **影响：** 符合 Issue 期望的 5 秒复活倒计时

### 步骤 3：删除 `_kill_entity()` 死代码
- **文件：** `scripts/systems/s_damage.gd`
- **操作：** 删除 line 549-568 的 `_kill_entity` 方法
- **影响：** 清理死代码，避免维护混淆

### 步骤 4：新增/追加单元测试
- **文件：** `tests/unit/system/test_dead_system.gd`
- **操作：** 追加 `test_respawn_delay_value` 用例

### 步骤 5：新增集成测试
- **文件：** `tests/integration/flow/test_flow_player_respawn_scene.gd`（新增）
- **操作：** 实现用例 2 + 用例 3 的 SceneConfig 集成测试

### 步骤 6：运行全部测试确认无回归
- 运行 gdUnit4 单元测试 + SceneConfig 集成测试

---

## 新增/修改文件列表

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/gameplay/gol_game_state.gd` | 修改 | 删除 line 74 `ECS.world.add_entity(new_player)` |
| `scripts/systems/s_dead.gd` | 修改 | line 10 `PLAYER_RESPAWN_DELAY` 3.0 → 5.0 |
| `scripts/systems/s_damage.gd` | 修改 | 删除 `_kill_entity()` 死代码 (line 549-568) |
| `tests/unit/system/test_dead_system.gd` | 修改 | 追加 respawn delay 常量测试 |
| `tests/integration/flow/test_flow_player_respawn_scene.gd` | 新增 | 死亡→复活集成测试（SceneConfig） |
