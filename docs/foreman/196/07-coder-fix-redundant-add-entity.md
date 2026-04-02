# 07-coder-fix-redundant-add-entity.md

## 完成的工作

### 修改的文件
| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/systems/s_enemy_spawn.gd` | 修改 | 移除 `_spawn_wave()` 中冗余的 `ECS.world.add_entity(new_entity)` 调用 |
| `scripts/systems/s_damage.gd` | 修改 | 移除 `_spawner_death_burst()` 中冗余的 `ECS.world.add_entity(new_entity)` 调用 |

### 修改原因
之前的修复（commit `41c83c2`）在 `_spawn_wave()` 和 `_spawner_death_burst()` 中添加了 `ECS.world.add_entity(new_entity)` 调用。然而，这个调用是**冗余的**，因为：

1. `ServiceContext.recipe().create_entity_by_id()` 内部调用 `_instantiate_entity()`
2. `_instantiate_entity()` 在 `service_recipe.gd:130` 已经调用了 `ECS.world.add_entity(entity)`
3. 再次调用 `add_entity()` 会触发 ID collision handling，导致实体被 `remove_entity()` 释放后重新添加
4. 这种 double-add 行为可能导致实体状态损坏，使 `is_instance_valid()` 返回 false

### 修复内容
从以下两个位置各移除一行代码：
- `s_enemy_spawn.gd:85` - 移除 `ECS.world.add_entity(new_entity)`
- `s_damage.gd:335` - 移除 `ECS.world.add_entity(new_entity)`

## 测试契约覆盖

### Unit Tests
| 契约 | 状态 | 说明 |
|------|------|------|
| `test_spawn_wave_adds_entity_to_world` | 无需修改 | 集成测试层面验证 |
| `test_spawn_wave_sets_correct_position` | 无需修改 | E2E 级别验证 |
| `test_spawn_wave_empty_recipe_id_no_crash` | 已覆盖 | 现有测试覆盖 AuthoringSpawner 层面 |
| `test_spawn_wave_respects_max_spawn_count` | 已覆盖 | Unit test 覆盖 count 计算逻辑 |

### Integration Tests
| 契约 | 状态 | 说明 |
|------|------|------|
| `test_spawner_spawns_enemy_into_world` | 已覆盖 | `test_flow_enemy_spawn_scene.gd` Test 1 验证 |
| `test_poison_enemy_visible_with_area_effect` | 已覆盖 | `test_flow_enemy_spawn_scene.gd` Test 3 验证 |

### E2E Tests
| 契约 | 状态 | 说明 |
|------|------|------|
| `test_poison_fog_visible_on_map` | 未覆盖 | 需要 AI Debug Bridge 运行时验证 |

## 决策记录

1. **识别冗余调用**: 通过阅读 `service_recipe.gd` 发现 `create_entity_by_id()` → `_instantiate_entity()` 已经包含 `ECS.world.add_entity()` 调用。

2. **移除而非保留**: 由于 `add_entity()` 内部有 ID collision 检测（`world.gd:296-304`），重复调用会导致：
   - 检测到相同 ID 的实体已存在
   - 调用 `remove_entity()` 释放原有实体（调用 `on_destroy()` 和 `free()`/`queue_free()`）
   - 将新实体添加到世界
   - 这可能导致实体引用变为无效

3. **保持 `spawner.spawned.append(new_entity)`**: 这行代码保留在循环内，用于追踪已生成的实体，供 max_spawn_count 和 cleanup 逻辑使用。

## 仓库状态

- **branch**: `foreman/issue-196`
- **commit SHA**: `c334b0c`
- **PR**: https://github.com/Dluck-Games/god-of-lego/pull/219
- **变更统计**: 2 files changed, 3 deletions(-)

### 验证步骤
由于 foreman worktree 没有 `.godot` 导入缓存，无法本地运行 gdUnit4 测试。修复逻辑已通过代码审查验证：

1. `create_entity_by_id("enemy_basic")` → `_instantiate_entity()` → `ECS.world.add_entity(entity)` ✓
2. 移除后的 `_spawn_wave()` 不再重复调用 `add_entity()` ✓
3. 实体通过 recipe 创建后已自动加入世界，SEnemySpawn 无需再次添加 ✓

## 未完成事项

- 等待 CI 运行结果确认测试通过
- E2E 测试（通过 AI Debug Bridge 运行时验证毒僵尸刷出后有绿色粒子效果）仍需后续手动验证
