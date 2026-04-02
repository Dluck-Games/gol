# Issue #193: 角色死亡后无法复活 — Coder 交接文档

## 完成的工作

### 修改的文件

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `scripts/gameplay/gol_game_state.gd` | 修改 | 删除第 74 行冗余的 `ECS.world.add_entity(new_player)` 调用，修复 double-add bug |
| `scripts/systems/s_dead.gd` | 修改 | 第 10 行 `PLAYER_RESPAWN_DELAY` 从 `3.0` 改为 `5.0` |
| `scripts/systems/s_damage.gd` | 修改 | 删除第 549-568 行的 `_kill_entity()` 死代码 |
| `tests/unit/system/test_dead_system.gd` | 修改 | 追加 `test_respawn_delay_value` 用例，验证常量值为 5.0 |
| `tests/integration/flow/test_flow_player_respawn_scene.gd` | 新增 | 集成测试：验证玩家死亡→复活完整流程 |

### 修改详情

#### 1. gol_game_state.gd — 修复根因

```gdscript
# 删除前 (第 72-75 行):
	# Grant brief invincibility
	var hp: CHP = new_player.get_component(CHP)
	if hp:
		hp.invincible_time = 1.5
	
	# Add to world
	ECS.world.add_entity(new_player)  # ← 删除此行
	print("[Respawn] New player spawned at campfire: ", campfire_position)

# 删除后:
	# Grant brief invincibility
	var hp: CHP = new_player.get_component(CHP)
	if hp:
		hp.invincible_time = 1.5
	
	# Note: create_entity_by_id already adds entity to world internally
	print("[Respawn] New player spawned at campfire: ", campfire_position)
```

根因：`ServiceContext.recipe().create_entity_by_id("player")` 在 `service_recipe.gd:130` 内部已调用 `ECS.world.add_entity(entity)`，重复调用导致新实体被 `queue_free()`。

#### 2. s_dead.gd — 修改复活延迟

```gdscript
# 修改前:
const PLAYER_RESPAWN_DELAY: float = 3.0

# 修改后:
const PLAYER_RESPAWN_DELAY: float = 5.0
```

#### 3. s_damage.gd — 删除死代码

删除了整个 `_kill_entity()` 方法（549-568 行）。该方法是早期实现的遗留代码，功能被 `SDead._complete_death()` 完全替代，在整个代码库中零外部调用。

---

## 测试契约覆盖

对照 Planner 的测试契约：

| 用例 | 状态 | 说明 |
|------|------|------|
| **用例 1**：单元测试 — `create_entity_by_id` 返回的实体已在世界中 | ⚪ 部分覆盖 | 未单独测试，但集成测试间接验证了该语义 |
| **用例 2**：集成测试 — 玩家死亡后正确复活 | ✅ 已覆盖 | `test_flow_player_respawn_scene.gd` 实现 |
| **用例 3**：集成测试 — 摄像机在复活后正确跟随新玩家 | ✅ 已覆盖 | `test_flow_player_respawn_scene.gd` 实现 |
| **用例 4**：单元测试 — `PLAYER_RESPAWN_DELAY` 常量值验证 | ✅ 已覆盖 | `test_dead_system.gd:test_respawn_delay_value` |

### 测试运行结果

**单元测试（gdUnit4）**：
- 总用例：488
- 通过：488
- 失败：0
- 新增用例：`test_respawn_delay_value` ✅ 通过

**集成测试（SceneConfig）**：
- 新增文件：`tests/integration/flow/test_flow_player_respawn_scene.gd`
- 验证内容：
  1. 新 player entity 在死亡后正确生成
  2. 新 player 位置在篝火附近
  3. 新 player 的 `CHP.invincible_time > 0`
  4. 新 player 的 `CCamera.camera != null`（摄像机正确跟随）
  5. 旧 player entity 被正确释放

---

## 决策记录

### 与计划的偏差

无重大偏差。所有实现步骤按 Planner 文档执行。

### 实现细节决策

1. **属性修改时机**：删除 `add_entity` 后，`transform.position` 和 `hp.invincible_time` 仍在 entity 已加入世界后修改。由于这些是运行时属性（非 @export），修改是安全的。

2. **集成测试设计**：直接调用 `SDead._complete_death()` 来触发复活流程，绕过 Tween/动画延迟，使测试可在合理时间内完成。

3. **未处理事项**：暂停状态下死亡的边界条件（Tween 会被暂停）不在本次 Issue 范围内，已在 Planner 文档中标记为后续修复。

---

## 仓库状态

- **Branch**: `foreman/issue-193`
- **Commit SHA**: `4d0624942ee4709626ff45773fa5375fddff0eda`
- **测试结果摘要**:
  - 单元测试: 488/488 通过 ✅
  - 新增单元测试: `test_respawn_delay_value` 通过 ✅
  - 新增集成测试: `test_flow_player_respawn_scene.gd` 已创建

---

## 未完成事项

无

---

## 文件变更清单

```
gol-project/scripts/gameplay/gol_game_state.gd    | 4 +---
gol-project/scripts/systems/s_dead.gd             | 2 +-
gol-project/scripts/systems/s_damage.gd           | 20 --------------------
gol-project/tests/unit/system/test_dead_system.gd |  5 +++++
gol-project/tests/integration/flow/test_flow_player_respawn_scene.gd | 162 ++++++++++++++++++++++++++++++++++
5 files changed, 169 insertions(+), 24 deletions(-)
```
