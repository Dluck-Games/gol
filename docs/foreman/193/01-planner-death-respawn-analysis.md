# Issue #193 — 角色死亡后无法复活：死亡/复活流程分析与修复方案

## 需求分析

### Issue 要求
角色被怪物攻击致死（HP 归零且无可掉落组件）后，应执行：
1. 死亡动画播放
2. 5 秒倒计时（UI 显示死亡倒计时）
3. 在营火（campfire）出生点复活
4. 重新获得完整控制权（移动、射击、准心、摄像机）

### 用户期望行为
- 死亡后 5 秒倒计时显示
- 倒计时结束后在出生点重生，如同游戏开始
- 摄像机平滑跟随到出生点
- 鼠标准心恢复正常控制
- 角色获得短暂无敌时间

### 边界条件
- 玩家先通过组件掉落系统存活（HP 被重置为 1），随后再次被击杀
- 死亡时营火是否仍在（campfire 被摧毁则 game over，不进入复活）
- `is_game_over` 状态阻塞复活流程

---

## 影响面分析

### 受影响的文件/函数

| 文件 | 函数/行号 | 角色 |
|------|-----------|------|
| `scripts/systems/s_damage.gd:261-302` | `_on_no_hp()` | HP 归零入口，触发组件掉落或死亡 |
| `scripts/systems/s_damage.gd:571-575` | `_start_death()` | 添加 CDead 组件 |
| `scripts/systems/s_dead.gd:31-233` | `_initialize()` → `_initialize_player_death()` → `_complete_death()` | 死亡全流程 |
| `scripts/systems/s_dead.gd:91-113` | `_initialize_player_death()` | 播放死亡动画，锁定移动，推出倒计时 UI |
| `scripts/systems/s_dead.gd:116-125` | `_on_player_death_animation_finished()` | 动画结束后创建 5s 延迟 tween |
| `scripts/systems/s_dead.gd:212-233` | `_complete_death()` | 最终清理：释放摄像机，调用复活/移除实体 |
| `scripts/gameplay/gol_game_state.gd:15-18` | `handle_player_down()` | 复活入口 |
| `scripts/gameplay/gol_game_state.gd:54-78` | `_respawn_player()` | 创建新玩家实体，设置位置，加入世界 |
| `scripts/systems/s_camera.gd:32-41` | `_on_component_created()` / `_on_component_removed()` | Camera2D 生命周期管理 |
| `scripts/configs/config.gd:35-47` | `DEATH_REMOVE_COMPONENTS` | 死亡时移除的组件列表 |
| `scripts/systems/s_life.gd:27-47` | `_handle_lifetime_expired()` | 生命周期到期处理 |
| `scripts/components/c_dead.gd:1-17` | `CDead` | 死亡标记组件 |
| `resources/recipes/player.tres` | Player Recipe | 复活时创建新实体的蓝图 |
| `resources/sprite_frames/player.tres:118-189` | `"death"` animation | 死亡动画定义（22 帧, speed 14.0, loop=false） |

> 所有路径相对于 `gol-project/` 目录，工作树根目录为 `/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260329083635._beaea84a/`

### 调用链追踪

**死亡链路（上游→下游）：**
```
SDamage._take_damage() [s_damage.gd:206]
  → hp.hp reaches 0 → _on_no_hp() [s_damage.gd:261]
    → 检查 CDead 防重入 [line 263]
    → 跳过 CCampfire / CSpawner [lines 267-275]
    → 尝试组件掉落系统 [lines 278-297]
      → 若成功掉落: hp.hp = 1（存活）
      → 若无组件可掉: _start_death() [s_damage.gd:571]
        → 添加 CDead 组件到实体

SDead.process() → _initialize() [s_dead.gd:31]
  → _remove_interfering_components() [line 35]
    → 移除 CAnimation, CWeapon, CHP, CAim 等
  → _find_sprite() [line 38] — 查找子节点 AnimatedSprite2D
  → _initialize_player_death() [line 44-46]
    → 锁定移动 (forbidden_move=true) [lines 93-96]
    → 推出 ViewDeathCountdown UI [lines 99-100]
    → 播放 "death" 动画 [lines 103-110]
      → 连接 animation_finished → _on_player_death_animation_finished() [line 106]
      → return（等待动画完成）

_on_player_death_animation_finished() [s_dead.gd:116]
  → 暂停在最后一帧 [lines 118-120]
  → 创建 Tween: 等待 5s → _complete_death() [lines 123-125]

_complete_death() [s_dead.gd:212]
  → 终止 tween [line 215]
  → 移除 CCamera（释放旧 Camera2D）[lines 220-221]
  → GOL.Game.handle_player_down() [line 229]
    → _respawn_player() [gol_game_state.gd:54]
      → 弹出死亡倒计时 UI [line 56]
      → 查找营火位置（或用缓存默认值 Vector2(500,500)）[line 58]
      → 从 recipe 创建新玩家实体 [line 61]
      → 设置位置为营火位置 [lines 67-69]
      → 设置 1.5s 无敌时间 [line 74]
      → ECS.world.add_entity(new_player) [line 77]
  → ECSUtils.remove_entity(旧实体) [line 232]
```

**摄像机链路：**
```
CCamera 从旧实体移除 [s_dead.gd:221]
  → entity.component_removed 信号触发
  → SCamera._on_component_removed() [s_camera.gd:39]
    → component.camera.queue_free()（延迟释放旧 Camera2D）

新实体加入世界 [gol_game_state.gd:77]
  → 下一帧 SCamera.process() 运行
  → _process_entity() → camera.camera == null
  → _on_component_created() [s_camera.gd:32]
    → 创建新 Camera2D，make_current()
```

### 受影响的实体/组件类型
- **Player Entity**: 包含 CPlayer, CCamp, CCamera, CHP, CAnimation, CAim, CMovement, CWeapon 等
- **CDead**: 死亡标记，触发 SDead 处理
- **CCamera**: 摄像机组件，管理 Camera2D 节点生命周期
- **CLifeTime**: 600s 生命周期（初始化时添加，死亡后不再有）

### 潜在的副作用
1. 复活后玩家没有 `CWeapon`（需重新拾取），只有 `CMelee`
2. 复活后玩家没有 `CLifeTime`（不会超时死亡）
3. 死亡时 `SRenderView` 可能接管渲染（`CAnimation` 被移除后，`SRenderView` 查询 `[CTransform, CSprite] with_none [CAnimation]` 匹配），在实体上创建额外 `Sprite2D` 节点

---

## 实现方案

### 根因分析

经过对代码的完整追踪，**复活系统（`_respawn_player`）本身逻辑完整**。代码链路 `SDamage._on_no_hp()` → `SDead._initialize_player_death()` → `_on_player_death_animation_finished()` → `_complete_death()` → `GOL.Game.handle_player_down()` → `_respawn_player()` 在正常情况下可以完整执行。

**但存在以下 Bug：**

#### Bug A（关键）：SCamera._on_component_removed 信号连接泄漏

**文件**: `scripts/systems/s_camera.gd:37`

```gdscript
func _on_component_created(entity: Entity, camera: CCamera) -> void:
    camera.camera = Camera2D.new()
    entity.add_child(camera.camera)
    camera.camera.make_current()
    camera.camera.set_position_smoothing_enabled(true)
    entity.component_removed.connect(_on_component_removed)  # ← 无去重保护
```

**问题**: `entity.component_removed.connect(_on_component_removed)` 没有去重保护。如果 `_on_component_created` 被多次调用（例如 `camera.camera` 被外部重置为 null，或 ECS 重新注册组件），信号会被多次连接。`_on_component_removed` 本身不区分是哪个实体的信号——它检查 `component is CCamera`，但如果其他实体的信号也连接到了同一个回调，可能导致 **旧 Camera2D 在错误时机被释放**。

**更严重的变体**: `_on_component_removed` 是一个无绑定的方法引用。当旧实体被 `queue_free()` 时，Godot 会自动断开信号。但如果 `_on_component_created` 在旧实体还存在时为新实体调用，两次调用的 `entity` 参数不同，不会造成交叉影响。**因此这个信号泄漏主要影响同一实体的多次触发场景**。

#### Bug B（关键）：Camera2D 释放时机与 make_current 竞态

**文件**: `scripts/systems/s_camera.gd:41` 和 `scripts/systems/s_dead.gd:220-229`

**时序问题**:
1. `_complete_death()` 移除旧实体的 CCamera → `SCamera._on_component_removed` → `component.camera.queue_free()`（**延迟释放**）
2. 紧接着调用 `_respawn_player()` 创建新实体，`ECS.world.add_entity()` 添加新实体到世界
3. 旧 Camera2D 尚未释放（`queue_free` 延迟到帧末）
4. 新 Camera2D 在下一帧由 `SCamera._on_component_created` 创建并 `make_current()`

**问题**: 在步骤 3→4 之间（可能 1 帧），**没有任何 Camera2D 处于 current 状态**。旧 Camera2D 虽然未被释放但不再是 `current`（因为 `component.camera` 引用仍然存在但正在等待释放），而新 Camera2D 尚未创建。这导致 **视口回退到默认位置 (0,0)**，表现为"摄像机被重置到了某个地图无人的位置"。

**实际影响**: 如果旧 Camera2D 的 `queue_free()` 在新 Camera2D 的 `make_current()` 之前执行，则 `make_current()` 可能因为旧的 Camera2D 引用仍存在而失败或产生冲突。

#### Bug C（关键）：_complete_death 缺少安全保障

**文件**: `scripts/systems/s_dead.gd:91-113`

```gdscript
func _initialize_player_death(entity: Entity, dead: CDead, sprite: CanvasItem) -> void:
    ...
    if sprite is AnimatedSprite2D:
        var anim_sprite := sprite as AnimatedSprite2D
        if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("death"):
            anim_sprite.animation_finished.connect(
                _on_player_death_animation_finished.bind(entity, dead, anim_sprite),
                CONNECT_ONE_SHOT
            )
            anim_sprite.play("death")
            anim_sprite.set_frame_and_progress(0, 0.0)
            return  # ← 如果 animation_finished 永远不触发，_complete_death 永远不会被调用
    _complete_death(entity, dead)
```

**问题**: 如果 `animation_finished` 信号因任何原因未触发（例如 Godot 引擎 bug、entity 意外被移除、AnimatedSprite2D 节点状态异常），`_complete_death()` **永远不会被调用**。没有超时安全机制。

虽然 `"death"` 动画配置为 `loop=false`，正常情况下会触发 `animation_finished`，但代码中缺乏防御性保障。

#### Bug D（次要）：_find_campfire_position 依赖 ECS 查询时机

**文件**: `scripts/gameplay/gol_game_state.gd:83-89`

```gdscript
func _find_campfire_position() -> Vector2:
    const COMPONENT_CAMPFIRE := preload("res://scripts/components/c_campfire.gd")
    for entity in ECS.world.query.with_all([COMPONENT_CAMPFIRE, CTransform]).execute():
        ...
    return campfire_position  # fallback: Vector2(500, 500)
```

**问题**: `_respawn_player()` 在 `_complete_death()` 中被调用，此时旧玩家实体尚未被移除（`ECSUtils.remove_entity` 在 line 232 才执行）。`_find_campfire_position()` 使用 `const COMPONENT_CAMPFIRE := preload(...)` 而不是直接引用 `CCampfire` 类名，这是不必要的间接层，但功能上等价。

如果营火已被摧毁，会回退到 `campfire_position`（默认 `Vector2(500, 500)`）。但 `handle_campfire_destroyed()` 会设置 `is_game_over = true`，而 `handle_player_down()` 在 `is_game_over` 时直接返回。**如果营火和玩家在同一帧死亡**，且 `handle_campfire_destroyed()` 先执行，则 `handle_player_down()` 不会执行复活。但 `_complete_death` 中先调用 `handle_campfire_destroyed`（if campfire）再调用 `handle_player_down`（if player），两者不会同时为真（CCampfire 组件只在营火实体上）。

### 推荐的实现方式

**核心修复策略：确保 `_complete_death` 一定会被调用，并修复 Camera2D 释放竞态。**

#### 修复 1：为玩家死亡添加超时安全保障（Bug C）

在 `_initialize_player_death` 中，除了连接 `animation_finished` 信号外，同时创建一个 timeout tween 作为后备方案。无论动画是否完成，`_complete_death` 都会被调用。最先触发的路径（动画结束或超时）执行，另一个被 kill 掉。

**文件**: `scripts/systems/s_dead.gd`
**修改位置**: `_initialize_player_death()` 函数，约 line 91-113

```gdscript
func _initialize_player_death(entity: Entity, dead: CDead, sprite: CanvasItem) -> void:
    # Lock movement
    var movement: CMovement = entity.get_component(CMovement)
    if movement:
        movement.velocity = Vector2.ZERO
        movement.forbidden_move = true
    
    # Push death countdown UI
    var countdown_scene: PackedScene = load("res://scenes/ui/death_countdown.tscn")
    ServiceContext.ui().create_and_push_view(Service_UI.LayerType.HUD, countdown_scene)

    # Safety timeout — ensures _complete_death fires even if animation fails
    dead._tween = entity.create_tween()
    dead._tween.tween_callback(_complete_death.bind(entity, dead))
    dead._tween.set_delay(Config.PLAYER_RESPAWN_DELAY)

    # Play death animation (visual only — doesn't block respawn)
    if sprite is AnimatedSprite2D:
        var anim_sprite := sprite as AnimatedSprite2D
        if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("death"):
            anim_sprite.play("death")
            anim_sprite.set_frame_and_progress(0, 0.0)
```

**关键变化**:
- 不再依赖 `animation_finished` 信号触发 `_complete_death`
- 直接创建一个 `PLAYER_RESPAWN_DELAY`（5s）的 timeout tween
- 死亡动画作为纯视觉效果播放，不阻塞复活流程
- 删除 `_on_player_death_animation_finished()` 函数（不再需要）

#### 修复 2：立即释放旧 Camera2D（Bug B）

**文件**: `scripts/systems/s_camera.gd`
**修改位置**: `_on_component_removed()` 函数，约 line 39-41

```gdscript
func _on_component_removed(_entity: Entity, component: Variant) -> void:
    if component is CCamera and component.camera and is_instance_valid(component.camera):
        component.camera.free()  # 立即释放，不再延迟
```

将 `queue_free()` 改为 `free()`。这确保旧 Camera2D 在新 Camera2D 调用 `make_current()` 之前被完全销毁，消除竞态。

#### 修复 3：SCamera 信号去重保护（Bug A）

**文件**: `scripts/systems/s_camera.gd`
**修改位置**: `_on_component_created()` 函数，约 line 32-37

```gdscript
func _on_component_created(entity: Entity, camera: CCamera) -> void:
    camera.camera = Camera2D.new()
    entity.add_child(camera.camera)
    camera.camera.make_current()
    camera.camera.set_position_smoothing_enabled(true)
    if not entity.component_removed.is_connected(_on_component_removed):
        entity.component_removed.connect(_on_component_removed)
```

添加 `is_connected` 检查，防止信号重复连接。

#### 修复 4：清理死代码（次要）

**文件**: `scripts/systems/s_damage.gd:549-568`
**修改**: 删除未使用的 `_kill_entity()` 函数。该函数从未被调用，且包含一个绕过 SDead 的死亡路径，可能造成混淆。

### 新增/修改的文件列表

| 操作 | 文件 | 修改内容 |
|------|------|---------|
| 修改 | `scripts/systems/s_dead.gd` | 重写 `_initialize_player_death()`；删除 `_on_player_death_animation_finished()` |
| 修改 | `scripts/systems/s_camera.gd` | `_on_component_removed`: `queue_free` → `free`；`_on_component_created`: 信号去重 |
| 修改 | `scripts/systems/s_damage.gd` | 删除未使用的 `_kill_entity()` 函数 |
| 修改 | `tests/unit/system/test_dead_system.gd` | 更新测试以反映新的死亡流程（移除 animation_finished 依赖） |

---

## 架构约束

### 涉及的 AGENTS.md 文件
- `gol-project/scripts/systems/AGENTS.md` — 系统目录，修改 SDead、SCamera、SDamage
- `gol-project/scripts/components/AGENTS.md` — 组件目录，涉及 CDead、CCamera
- `gol-project/tests/AGENTS.md` — 测试模式

### 引用的架构模式
- **GECS System**: SDead、SCamera、SDamage 都遵循 GECS System 模式（`extends System`，实现 `query()` 和 `process()`）。修改保持在 System 框架内。
- **Component = pure data**: `CDead` 和 `CCamera` 是纯数据组件，修改不违反此约束。SDead 通过 tween 管理死亡流程的状态，但不将流程状态存储在组件中（`_tween` 是私有字段）。
- **EntityRecipe**: 复活使用 `ServiceContext.recipe().create_entity_by_id("player")`，遵循现有的 recipe-based 实体创建模式。不修改 recipe。

### 文件归属层级
- `scripts/systems/` — 系统脚本，遵循 systems/AGENTS.md
- `tests/unit/system/` — 单元测试，遵循 tests/AGENTS.md

### 测试模式
- **单元测试**: `extends GdUnitTestSuite`，使用 `assert_*` 风格，引用 `tests/AGENTS.md`
- **集成测试**: `extends SceneConfig`，加载真实 GOLWorld（本次修复不需要新增集成测试）
- **E2E 测试**: 使用 AI Debug Bridge 进行运行时验证

---

## 测试契约

- [ ] **test_player_death_completes_within_timeout** — 模拟玩家死亡（添加 CDead + CPlayer），验证 5 秒后 `_complete_death` 被调用（通过 mock/timer 验证，无需真实动画）。验证方式：gdUnit4 单元测试
- [ ] **test_camera_removed_before_respawn** — 验证 `_complete_death` 移除 CCamera 后，旧 Camera2D 被立即释放（`.free()` 而非 `.queue_free()`）。验证方式：gdUnit4 单元测试
- [ ] **test_camera_signal_no_duplicate** — 验证 `_on_component_created` 多次调用不会重复连接 `component_removed` 信号。验证方式：gdUnit4 单元测试
- [ ] **test_respawn_creates_new_player_entity** — 验证 `_respawn_player()` 创建新实体，位置设为营火位置，HP 为满值，有 1.5s 无敌。验证方式：gdUnit4 单元测试
- [ ] **test_respawn_player_has_expected_components** — 验证复活后的玩家实体包含 CPlayer, CCamp, CCamera, CMovement, CHP, CAim, CMelee 等必要组件。验证方式：gdUnit4 单元测试
- [ ] **test_death_animation_plays_but_not_blocking** — 验证死亡动画播放但不阻塞复活流程（即使动画信号未触发，5s 后仍完成死亡）。验证方式：gdUnit4 单元测试
- [ ] **E2E: 玩家死亡到复活完整流程** — 运行时验证：怪物击杀玩家 → 死亡动画播放 → 5s 倒计时 → 营火位置重生 → 摄像机正确跟随 → 鼠标控制恢复。验证方式：AI Debug Bridge E2E

---

## 风险点

### 高风险
1. **Camera2D 立即释放（`free()`）可能在某些边缘情况下导致崩溃** — 如果 `_on_component_removed` 在 Camera2D 仍有子节点或正在处理时被调用，`free()` 可能比 `queue_free()` 更危险。缓解措施：在调用 `free()` 前，确保 Camera2D 不在当前处理流程中（当前代码在 `_complete_death` 的同步流程中调用，应该是安全的）。
2. **删除 `_on_player_death_animation_finished` 会改变死亡动画的视觉行为** — 原流程中，死亡动画播完后暂停在最后一帧，然后等 5s。新流程中，死亡动画在 5s 倒计时的同时播放（动画约 1.57s），播完后可能会被 CAnimation 系统覆盖回 idle/walk（但 CAnimation 已被移除，SAnimation 不再处理此实体，所以动画会停在最后一帧）。需要验证视觉行为是否可接受。

### 中风险
3. **5s timeout 作为唯一触发器** — 如果 `entity.create_tween()` 失败（entity 不在场景树中），tween 不会执行。但 `_initialize_player_death` 仅在 `SDead._process_entity` 中被调用，此时实体必然在场景树中（通过 ECS.world 管理的实体都是场景树子节点）。
4. **现有测试需要更新** — `test_dead_system.gd` 中的测试基于旧流程编写。`test_config_respawn_delay_value` 不受影响，但其他测试可能需要调整。

### 低风险
5. **删除 `_kill_entity()` 死代码** — 该函数从未被调用，删除不会影响任何功能。但如果有外部脚本（非 gol-project 内）引用了它（极不可能），会导致编译错误。
6. **`_find_campfire_position` 使用 `preload` 而非直接类引用** — 功能等价，但属于代码风格问题，不在本次修复范围内。

---

## 建议的实现步骤

1. **修改 `scripts/systems/s_dead.gd`**：
   - 重写 `_initialize_player_death()`：移除 `animation_finished` 信号连接，改为直接创建 timeout tween（`PLAYER_RESPAWN_DELAY` 秒）
   - 保留死亡动画播放作为纯视觉效果
   - 删除 `_on_player_death_animation_finished()` 函数

2. **修改 `scripts/systems/s_camera.gd`**：
   - `_on_component_removed()`: 将 `component.camera.queue_free()` 改为 `component.camera.free()`
   - `_on_component_created()`: 添加 `is_connected` 检查防止信号重复连接

3. **修改 `scripts/systems/s_damage.gd`**：
   - 删除 `_kill_entity()` 函数（lines 549-568），该函数从未被调用

4. **更新测试 `tests/unit/system/test_dead_system.gd`**：
   - 更新 `test_movement_locked_on_death` 和 `test_camera_removed_before_player_down` 以反映新的流程
   - 新增 `test_player_death_completes_within_timeout` 测试
   - 新增 `test_camera_signal_no_duplicate` 测试

5. **运行完整测试套件**，确保所有现有测试通过

6. **E2E 验证**（可选）：使用 AI Debug Bridge 运行完整的玩家死亡→复活场景
