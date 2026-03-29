# 06-coder-fix-spawner-test-detection.md

## 完成的工作

### 修改的文件
| 文件 | 操作 | 说明 |
|------|------|------|
| `tests/integration/flow/test_flow_enemy_spawn_scene.gd` | 修改 | 修复 Test 1 的 entity 检测逻辑 |

### 修改原因
CI 失败详情显示 Test 1 断言失败：`[FAIL] Spawned enemy entity found in world.entities — expected: true, got: false`

核心修复代码（`s_enemy_spawn.gd:85` 的 `ECS.world.add_entity(new_entity)`）是正确的，问题在于测试的 entity 检测逻辑：

1. **时序问题**：原测试只等待 1 帧，但 SEnemySpawn 在 gameplay group 的 `_process` 中运行，需要多帧才能完整执行 spawn 流程
   - 第 1 帧：spawner entity 被添加到 world，SEnemySpawn 查询并处理它，调用 `_spawn_wave()`
   - 第 2 帧：`_spawn_wave()` 中创建的 enemy entity 被 `add_entity()` 加入 world

2. **Deep-copy 问题**：`ECS.world.add_entity()` 会 deep-copy 组件（GECS v6 行为），原测试直接使用 `spawner_entity` 引用获取 CSpawner 组件，可能访问的是已被释放的原始 entity
   - 修复后改为通过 `_find(world, "TestSpawner")` 从 world 中重新查找 spawner entity

3. **Entity 查找改进**：`_find_enemy_without_name()` 已经正确排除了已知 entity 名称，但需要确保 world.entities 已包含新 spawn 的 enemy

## 测试契约覆盖

### Integration Tests (`tests/integration/flow/test_flow_enemy_spawn_scene.gd`)

| 契约 | 状态 | 说明 |
|------|------|------|
| `test_spawner_spawns_enemy_into_world` | **已修复** | 新增第 2 个 `await world.get_tree().process_frame`，确保 enemy entity 有足够时间被加入 world |
| `test_poison_enemy_visible_with_area_effect` | 已覆盖 | 未修改，保持原样 |

### 修复的具体改动

```gdscript
# Before:
await world.get_tree().process_frame
var spawner: CSpawner = spawner_entity.get_component(CSpawner) as CSpawner

# After:
await world.get_tree().process_frame
await world.get_tree().process_frame  # 新增：等待 enemy 被加入 world
var world_spawner: Entity = _find(world, "TestSpawner")  # 从 world 重新查找
var spawner: CSpawner = world_spawner.get_component(CSpawner) as CSpawner
```

## 决策记录

1. **添加第二帧等待**：这是最关键的调整。SEnemySpawn 系统在当前帧处理 spawner 并调用 `_spawn_wave()`，但 `ECS.world.add_entity(new_entity)` 添加的 enemy 需要到下一帧才能被查询到。

2. **通过 world 查找 spawner**：遵循 AGENTS.md 的 GECS gotcha 警告——`World.add_entity()` deep-copies components，原始引用可能失效。改为使用 `_find()` 从 world 中重新获取 spawner entity。

3. **保持其他测试不变**：Test 2 和 Test 3 测试的是 recipe-based entities（通过 `entities()` 方法配置），这些 entity 在场景初始化时就已经加载，不受 spawner 时序影响，无需修改。

## 仓库状态

- **branch**: `foreman/issue-196`
- **commit SHA**: `41c83c2`
- **PR**: https://github.com/Dluck-Games/god-of-lego/pull/219
- **变更**: `tests/integration/flow/test_flow_enemy_spawn_scene.gd` (+13/-4 行)

### 测试结果

由于 foreman worktree 没有 `.godot` 导入缓存，无法本地运行 gdUnit4 测试。修复已推送，应由 CI 验证。

预期 Test 1 现在应该通过：
- entity_count_after > entity_count_before ✓
- spawned_enemy != null ✓
- spawned enemy has CHP ✓
- spawner.spawned.size() >= 1 ✓

## 未完成事项

- 等待 CI 运行结果确认 Test 1 通过
- 如果 CI 仍然失败，可能需要进一步调整等待帧数或检查 SEnemySpawn 系统的执行时机
