# Issue #193: 角色死亡后无法复活

## 需求分析

Issue 标题 "角色死亡后无法复活" 描述的是玩家角色死亡后无法正确复活的问题。

**期望行为**: 玩家 HP 降为 0 后，经过死亡动画 → 延迟 3 秒 → 在篝火位置生成新的玩家实体（1.5 秒无敌），玩家恢复正常操作。

**边界条件**:
1. 游戏暂停（`is_paused = true`）时玩家死亡 — Tween 不运行，`_complete_death` 回调永远不会触发
2. 游戏结束（`is_game_over = true`）后触发 `handle_player_down()` — `handle_player_down()` 第一行检查 `is_game_over` 直接 return，不执行复活
3. 死亡动画期间再次受到伤害 — 已有 `CDead` 组件防止重复触发
4. 场景切换/teardown 期间 — `GOL.Game` 可能被释放，null check 会跳过复活

## 影响面分析

### 受影响的文件

| 文件 | 作用 | 问题 |
|------|------|------|
| `scripts/systems/s_dead.gd` | 死亡动画系统 | `_complete_death` 通过 Tween 回调触发，暂停时 Tween 不执行 |
| `scripts/gameplay/gol_game_state.gd` | 游戏状态管理 | `handle_player_down()` 依赖 `_complete_death` 被调用 |
| `scripts/systems/s_damage.gd` | 伤害处理系统 | `_kill_entity()` 已废弃但未清理 |
| `scripts/systems/s_life.gd` | 生命时间系统 | 可替代路径触发死亡 |
| `scripts/components/c_dead.gd` | 死亡标记组件 | 纯数据，无问题 |

### 完整调用链

```
玩家 HP 降为 0
  → SDamage._on_no_hp() (s_damage.gd:261)
    → [component loss check] → 若无可丢组件
      → SDamage._start_death() (s_damage.gd:571) 添加 CDead
        → SDead._initialize() (s_dead.gd:32)
          → SDead._remove_interfering_components() — 移除 CHP, CAnimation, CCollision 等
          → SDead._initialize_player_death() (s_dead.gd:92)
            → 播放 "death" 动画
            → 动画结束后 _on_player_death_animation_finished() (s_dead.gd:113)
              → dead._tween.tween_interval(3.0)  ← Tween 延迟 3 秒
              → dead._tween.tween_callback(_complete_death)  ← 回调
  *** 若此时游戏被暂停 (tree.paused = true)，Tween 暂停，回调永远不触发 ***

若 _complete_death 正常触发 (s_dead.gd:211):
  → entity.has_component(CPlayer) → true
    → GOL.Game.handle_player_down() (gol_game_state.gd:15)
      → if is_game_over: return  ← 若已 game over，不复活
      → _respawn_player() (gol_game_state.gd:54)
        → _find_campfire_position() 查找篝火
        → ServiceContext.recipe().create_entity_by_id("player") 创建新实体
        → 设置位置 + 1.5s 无敌
        → ECS.world.add_entity(new_player)
  → ECSUtils.remove_entity(entity) 移除旧实体
```

### 潜在问题根因分析

**核心问题: 游戏暂停状态下玩家死亡导致复活链断裂**

`s_dead.gd:122-124`:
```gdscript
dead._tween = entity.create_tween()
dead._tween.tween_interval(PLAYER_RESPAWN_DELAY)
dead._tween.tween_callback(_complete_death.bind(entity, dead))
```

`create_tween()` 创建的 Tween 默认受 `SceneTree.paused` 控制。当 `GOLGameState.toggle_pause()` 调用 `tree.paused = true` 时，所有正在运行的 Tween 暂停，`_complete_death` 回调永远不会执行，玩家实体被卡在死亡状态。

次要问题:
1. **`s_damage.gd:549` `_kill_entity()` 已废弃但未删除** — 该函数有类似的复活逻辑但从未被调用，属于死代码
2. **`gol_game_state.gd:100-112` `_lock_player_controls_on_game_over()` 查询 `CCamp + CPlayer`** — 复活后的新玩家不会被锁控制（因为 game_over 时 `handle_player_down` 直接 return）

## 实现方案

### 方案: 修复 Tween 暂停问题

死亡系统的 Tween 回调需要不受游戏暂停影响。

**具体修改**:

1. **`scripts/systems/s_dead.gd`** — 所有 `create_tween()` 调用设置 `Tween.TWEEN_PROCESS_PAUSE`:
   - `_initialize_player_death()` 中的 `_on_player_death_animation_finished` 的 `dead._tween` (line 122)
   - `_initialize_generic_death()` 中的 `dead._tween` (line 147)
   - `_initialize_building_death()` 中的 `dead._tween` (line 65)
   - `_play_hit_blink()` 中的 tween (line 498) — 这个不需要改，因为 hit blink 发生在死亡流程之前

   修改方式: 在 `create_tween()` 后添加 `dead._tween.set_pause_mode(Tween.TWEEN_PROCESS_PAUSE)` (Godot 4.x 中使用 `Tween.set_process_mode(Tween.TWEEN_PROCESS_PAUSED)` 或节点 `process_mode`)

   注意: `Entity.create_tween()` 创建的 Tween 继承 Entity 节点的 `process_mode`。需要将 Entity 的 `process_mode` 设为 `Node.PROCESS_MODE_ALWAYS` 或在 Tween 上设置。

   实际上，更好的做法是在 `_initialize_player_death` 中，确保死亡动画流程不受暂停影响：
   - 方案 A: 在 `_complete_death` 之前设置 `entity.process_mode = Node.PROCESS_MODE_ALWAYS`
   - 方案 B: 使用 `SceneTree.create_tween()` 替代 `entity.create_tween()`
   - 方案 C: 在 `entity.create_tween()` 之后调用 `dead._tween.set_pause_mode(Tween.TWEEN_PROCESS_ALWAYS)` (4.x API: `dead._tween.set_process_mode(Node.PROCESS_MODE_ALWAYS)`)

   **推荐方案 A**: 在 `_initialize()` 中设置 `entity.process_mode = Node.PROCESS_MODE_ALWAYS`，确保死亡流程（Tween 动画 + 回调）在暂停时仍然执行。在 `_complete_death()` 中不需要重置，因为旧实体即将被移除。

2. **`scripts/systems/s_damage.gd`** — 删除废弃的 `_kill_entity()` 方法 (line 549-568)

3. **`tests/unit/system/test_dead_system.gd`** — 新增测试:
   - 测试死亡流程中 `process_mode` 设置
   - 测试 `_complete_death` 对玩家实体的回调行为（mock GOL.Game）

### 新增/修改文件列表

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/systems/s_dead.gd` | 修改 | `_initialize()` 中设置 `entity.process_mode = PROCESS_MODE_ALWAYS` |
| `scripts/systems/s_damage.gd` | 修改 | 删除废弃的 `_kill_entity()` 方法 |
| `tests/unit/system/test_dead_system.gd` | 修改 | 新增 process_mode 相关测试 |

## 架构约束

- **涉及的 AGENTS.md 文件**:
  - `scripts/systems/AGENTS.md` — SDead 系统修改，遵循 System 模板
  - `scripts/components/AGENTS.md` — CDead 组件（只读，不需修改）
  - `scripts/gameplay/AGENTS.md` — GOLGameState 复活流程（只读，不需修改）
  - `tests/AGENTS.md` — 测试分层规则
- **引用的架构模式**: System 模式（`scripts/systems/AGENTS.md`），SDead 是 Gameplay group 系统
- **文件归属层级**:
  - 系统修改 → `scripts/systems/`
  - 单元测试 → `tests/unit/system/`
- **测试模式**:
  - 单元测试: `extends GdUnitTestSuite`，手动构造 Entity，不依赖 World/ECS.world
  - 集成测试: 复活完整流程涉及 GOLWorld + 多系统交互，应使用 `extends SceneConfig`
  - E2E: 暂停状态下死亡的运行时验证

## 测试契约

- [ ] **单元测试: 死亡实体 process_mode 设置** — `_initialize()` 调用后，entity.process_mode == PROCESS_MODE_ALWAYS（验证方式: 手动构造 Entity + CDead + CPlayer，调用 SDead 初始化逻辑，检查 process_mode）
- [ ] **单元测试: 干扰组件移除不受影响** — 现有 `test_interfering_components_removed` 继续通过
- [ ] **集成测试: 玩家死亡后复活** — 通过 SceneConfig 创建玩家实体，模拟致死伤害，等待死亡动画 + 3 秒延迟，验证新玩家实体在篝火位置生成（验证方式: `test_flow_player_respawn_scene.gd`，extends SceneConfig）
- [ ] **集成测试: 暂停状态下死亡仍能复活** — 暂停游戏后模拟致死伤害，验证玩家仍在 3+ 秒后复活（验证方式: 在集成测试中设置 `tree.paused = true`，等待足够时间后检查）
- [ ] **E2E: 真实游戏暂停+死亡+复活** — 运行时通过 AI Debug Bridge 暂停游戏、杀死玩家、验证复活正常

## 风险点

1. **`process_mode = PROCESS_MODE_ALWAYS` 对死亡动画渲染的影响** — 设置 `process_mode = PROCESS_MODE_ALWAYS` 可能导致 `_physics_process` 在暂停时仍执行，但死亡实体已移除 `CCollision` 和 `CMovement`（`forbidden_move = true`），物理行为应无副作用。需确认 SMove 不会在 `forbidden_move` 时仍产生位移。

2. **Entity 继承自 Node** — `process_mode` 是 Node 属性，Entity 继承自 Node，设置是安全的。

3. **Tween 与 process_mode 的关系** — `Node.create_tween()` 创建的 Tween 默认使用创建节点的 `process_mode`。修改 Entity 的 `process_mode` 后，已创建的 Tween 不会自动更新。需要在创建 Tween **之前**设置 `process_mode`，或在 Tween 上显式设置。

   修正: 应该在 `_initialize()` 中设置 `entity.process_mode = PROCESS_MODE_ALWAYS`，这样后续在该函数中通过 `entity.create_tween()` 创建的所有 Tween 都会继承 `PROCESS_MODE_ALWAYS`。`_initialize_player_death()` 和 `_initialize_generic_death()` 中的 Tween 都在 `_initialize()` 调用之后创建（通过 `_process_entity` → `_initialize` 的调用链），因此设置时机正确。

4. **`_play_hit_blink` 中的 Tween** — 该 Tween 在 SDamage 系统中创建，不在 SDead 中。如果命中闪烁效果在暂停状态下不受影响也无所谓（纯视觉效果），无需修改。

## 建议的实现步骤

1. **修改 `scripts/systems/s_dead.gd`** — 在 `_initialize()` 方法开头添加 `entity.process_mode = Node.PROCESS_MODE_ALWAYS`，确保后续创建的所有 Tween 和动画回调不受暂停影响
2. **删除 `scripts/systems/s_damage.gd` 中的 `_kill_entity()`** — 移除 line 549-568 的废弃方法
3. **新增单元测试到 `tests/unit/system/test_dead_system.gd`** — 验证 `_initialize()` 设置 `process_mode`
4. **新增集成测试 `tests/integration/flow/test_flow_player_respawn_scene.gd`** — 完整验证死亡→延迟→复活流程
5. **运行全部测试确认无回归**
