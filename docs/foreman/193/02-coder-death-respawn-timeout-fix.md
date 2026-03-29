## 完成的工作

### 修改的文件

| 文件 | 修改内容 |
|------|---------|
| `scripts/systems/s_dead.gd` | 重写 `_initialize_player_death()`：移除 `animation_finished` 信号连接，改为直接创建 `PLAYER_RESPAWN_DELAY` 秒 timeout tween；删除 `_on_player_death_animation_finished()` 函数 |
| `scripts/systems/s_camera.gd` | `_on_component_removed`: `queue_free()` → `free()`（立即释放旧 Camera2D）；`_on_component_created`: 添加 `is_connected` 检查防止信号重复连接 |
| `scripts/systems/s_damage.gd` | 删除未使用的 `_kill_entity()` 函数（lines 549-568） |
| `tests/unit/system/test_dead_system.gd` | 新增 4 个测试：`test_player_death_completes_within_timeout`、`test_death_animation_plays_but_not_blocking`、`test_complete_death_kills_tween`、`test_camera_signal_no_duplicate`、`test_camera_immediate_free_not_deferred`；更新 `test_movement_locked_on_death` 断言 |

### 为什么这样改

- **Bug C 修复（关键）**：原流程依赖 `animation_finished` 信号触发 `_complete_death`，如果信号因任何原因未触发（Godot 引擎 bug、节点异常等），玩家将永远无法复活。改为 timeout tween 保证 `_complete_death` 一定会被调用。死亡动画作为纯视觉效果播放，不阻塞复活流程。
- **Bug B 修复（关键）**：旧 Camera2D 使用 `queue_free()` 延迟释放，导致在新 Camera2D 调用 `make_current()` 之前存在 1 帧无 Camera2D 处于 current 状态的空窗期，表现为摄像机跳到默认位置。改为 `free()` 立即释放消除竞态。
- **Bug A 修复（关键）**：`component_removed` 信号无去重保护，多次调用 `_on_component_created` 会导致信号重复连接。添加 `is_connected` 检查。
- **死代码清理**：`_kill_entity()` 从未被调用，且包含绕过 SDead 的死亡路径，删除以避免混淆。

## 测试契约覆盖

| 测试项 | 状态 | 说明 |
|--------|------|------|
| test_player_death_completes_within_timeout | 已覆盖 | 单元测试：验证 timeout 触发机制 |
| test_camera_removed_before_respawn | 已覆盖 | 已有测试，验证 CCamera 在 _complete_death 中被移除 |
| test_camera_signal_no_duplicate | 已覆盖 | 新增单元测试：验证 is_connected 防重复连接 |
| test_camera_immediate_free_not_deferred | 已覆盖 | 新增单元测试：验证 free() 行为 |
| test_respawn_creates_new_player_entity | 未覆盖 | 需要 ECS.world + recipe 系统，属于集成测试范围，违反单元测试规则（禁止创建 World） |
| test_respawn_player_has_expected_components | 未覆盖 | 同上，需要完整游戏状态 |
| test_death_animation_plays_but_not_blocking | 已覆盖 | 新增单元测试：验证动画不阻塞复活 |
| E2E 完整流程 | 未覆盖 | 需要运行时 AI Debug Bridge，超出代码修改范围 |

### 未覆盖测试原因

`test_respawn_creates_new_player_entity` 和 `test_respawn_player_has_expected_components` 在计划中被标记为"gdUnit4 单元测试"，但它们需要 `ServiceContext.recipe()` 和 `ECS.world.add_entity()`，这违反了 `tests/AGENTS.md` 中的硬规则："tests/unit/ — ONLY extends GdUnitTestSuite. No World, no ECS.world, no GOLWorld." 这两个测试应作为 SceneConfig 集成测试实现。

## 决策记录

1. **不修改 `_find_campfire_position` 的 preload 间接层** — 计划中提到这是代码风格问题，功能等价，不在本次修复范围内。

2. **死亡动画不再暂停在最后一帧** — 原流程中 `_on_player_death_animation_finished` 会将动画暂停在最后一帧。新流程中动画自然播放完毕（CAnimation 已被移除，SAnimation 不再处理此实体），动画会停在最后一帧。这等价于旧行为，无需额外处理。

3. **test_death_countdown_view.gd 测试失败** — 该测试由前序 foreman 会话添加，失败原因是 `Tween.set_process` 在 Godot 4.6 中不再是有效 API，与本次修改无关。主分支无此测试文件，属前序会话遗留问题。

4. **PR 复用** — 发现 foreman 已为 #193 创建 PR (#221)，新 commit 推送到同一分支后自动包含在 PR 中，更新了 PR 标题和描述。

## 仓库状态

- **branch**: `foreman/issue-193`
- **commit SHA**: `617e805`
- **PR**: https://github.com/Dluck-Games/god-of-lego/pull/221
- **测试结果**: `test_dead_system.gd` 11/11 pass；全量单元测试 487 baseline + 4 new = 491，0 regressions

## 未完成事项

- 集成测试 `test_respawn_creates_new_player_entity` 和 `test_respawn_player_has_expected_components` 未编写，建议作为后续 PR 的 SceneConfig 集成测试实现
- E2E 验证（AI Debug Bridge 运行时测试）未执行，需要 live game 环境
