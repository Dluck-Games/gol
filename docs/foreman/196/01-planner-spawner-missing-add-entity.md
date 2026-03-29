# Issue #196 Planner: Spawner Missing `add_entity` Call

## 需求分析

### Issue 要求
Issue #196 报告"毒药和范围化组件在地图上不刷新"。实际表现为：**所有通过 CSpawner/SEnemySpawn 刷出的敌人均不会出现在地图上**，不仅仅是毒药和范围化组件。

Issue 标题中的"毒药和范围化组件"对应：
- **毒药** → `enemy_poison` recipe（CPoison + CAreaEffect 组件的毒僵尸）
- **范围化组件** → `CAreaEffect` 组件（FF7 风格的范围化魔晶石，修改近战/治疗/毒药为范围效果）

但问题根源是通用的——**所有 SEnemySpawn 系统刷出的实体都不会出现在地图上**。

### 用户期望的行为
1. 地图上的 EnemySpawner POI 应按照 `CSpawner` 配置定时刷出敌人实体
2. 毒僵尸（`enemy_poison`）应正常刷出并显示绿色毒雾范围效果
3. 带有 `CAreaEffect` 的实体刷出后应正常触发 `SAreaEffectModifier` 和 `SAreaEffectModifierRender`
4. 所有类型敌人（fire/wet/cold/electric/poison/fast/raider/basic）均应正常刷出

### 边界条件
- `max_spawn_count` 限制是否正确工作
- `active_condition`（ALWAYS/DAY_ONLY/NIGHT_ONLY）切换时是否正确刷出首波
- spawner 被 `SDamage` 击杀后 `enraged` 状态是否正常
- spawner 被击杀时死亡爆发掉落物是否正常

## 影响面分析

### 根因
**`scripts/systems/s_enemy_spawn.gd:84`** — `_spawn_wave()` 函数在创建实体后仅将其 append 到 `spawner.spawned` 数组，**未调用 `ECS.world.add_entity(new_entity)`**。

GECS v3.5.1 → v6.7.2 升级（commit `255c608`）时完全重写了 `_spawn_wave()`。旧版本（commit `a23a5b7`）在第 24 行有 `ECS.world.add_entity(new_entity)`，但升级过程中遗漏了这行调用。

### 调用链追踪

**正常刷怪流程（期望）：**
```
GOLWorld._spawn_enemy_spawners_at_pois()           # gol_world.gd:310
  → _spawn_enemy_spawner_at_position(pos, index)    # gol_world.gd:336
    → CSpawner.spawn_recipe_id = _choose_enemy_spawn_recipe(index)  # gol_world.gd:406
    → add_entity(spawner_entity)                    # gol_world.gd:401  ✓ spawner 本身被正确加入世界

SEnemySpawn.process()                               # s_enemy_spawn.gd:18
  → _process_entity(entity, delta)                  # s_enemy_spawn.gd:23
    → _spawn_wave(spawner, transform)               # s_enemy_spawn.gd:51/38
      → ServiceContext.recipe().create_entity_by_id(recipe_id)  # s_enemy_spawn.gd:72  ✓ 创建实体
      → spawner.spawned.append(new_entity)          # s_enemy_spawn.gd:84  ✓ 记录到 spawned
      ✗ ECS.world.add_entity(new_entity)            # <--- 缺失！
```

**不调用 `add_entity` 的后果：**
1. 实体不在 `ECS.world.entities` 中 → 所有 system 的 query 不会匹配该实体
2. `SRenderView` (render group) 无法为其创建 Sprite2D → **地图上不可见**
3. `SCollision` 无法为其创建 Area2D → 无碰撞检测
4. `SAreaEffectModifier` 无法处理 → 即使毒僵尸有 CPoison+CAreaEffect，范围毒伤不生效
5. `SAreaEffectModifierRender` 无法处理 → 无绿色毒雾粒子效果
6. `SDamage` / `SDead` / `SMove` 等所有 system 均不处理该实体
7. `_cleanup_invalid_entities()` 中 `is_instance_valid(spawned_entity)` 始终为 true（因为实体本身是有效的，只是没加入世界）→ max_spawn_count 永远不会释放配额

### 受影响的实体/组件类型
**所有通过 spawner 刷出的敌人实体均受影响：**
| Recipe | 组件 | 影响 |
|--------|------|------|
| `enemy_basic` | CHP, CMovement, CCollision, CSprite, CMelee | 不可见、不可交互 |
| `enemy_fire` | + CElementalAttack(FIRE) | + 元素效果不生效 |
| `enemy_wet` | + CElementalAttack(WET) | + 元素效果不生效 |
| `enemy_cold` | + CElementalAttack(COLD) | + 元素效果不生效 |
| `enemy_electric` | + CElementalAttack(ELECTRIC) | + 元素效果不生效 |
| `enemy_poison` | + CPoison, CAreaEffect | + 毒雾范围不生效（Issue 核心关注） |
| `enemy_fast` | + 快速移动参数 | + 不可见 |
| `enemy_raider` | + CWeapon | + 远程攻击不生效 |

### 潜在的副作用
1. **max_spawn_count 配额耗尽**：spawner.spawned 数组持续增长但实体永远不会被清理（因为 `_cleanup_invalid_entities` 只检查 `is_instance_valid`，不检查实体是否在世界中）。spawner 在达到 max_spawn_count 后停止刷怪。
2. **内存泄漏风险**：spawned 实体被 spawner.spawned 数组引用，虽然实体最终会被垃圾回收（无 Node 父节点），但 spawner 被销毁前不会被释放。

## 实现方案

### 推荐的实现方式
**最小改动修复**：在 `s_enemy_spawn.gd` 的 `_spawn_wave()` 中添加 `ECS.world.add_entity(new_entity)` 调用。

### 具体的代码修改位置

**文件：`scripts/systems/s_enemy_spawn.gd`**

在 `_spawn_wave()` 函数的第 84 行之后（`spawner.spawned.append(new_entity)` 之后）添加：

```gdscript
ECS.world.add_entity(new_entity)
```

完整修改后的 `_spawn_wave()` 函数（第 71-84 行区域）：
```gdscript
for i in range(count_to_spawn):
    var new_entity := ServiceContext.recipe().create_entity_by_id(spawner.spawn_recipe_id)
    if not new_entity:
        push_error("SEnemySpawn: Failed to create entity")
        continue
    
    # 计算刷新位置
    var spawn_pos := _calculate_spawn_position(center, spawner.spawn_radius, i, count_to_spawn)
    
    var new_transform := new_entity.get_component(CTransform) as CTransform
    if new_transform:
        new_transform.position = spawn_pos
    
    spawner.spawned.append(new_entity)
    ECS.world.add_entity(new_entity)  # <-- 新增
```

### 新增/修改的文件列表
| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/systems/s_enemy_spawn.gd` | 修改 | 添加 `ECS.world.add_entity(new_entity)` |
| `tests/unit/system/test_spawner_system.gd` | 修改 | 添加 SEnemySpawn 系统级 unit test |
| `tests/integration/flow/test_flow_enemy_spawn_scene.gd` | 新增 | 集成测试：验证 spawner 实际刷出实体到世界中 |

## 架构约束

### 涉及的 AGENTS.md 文件
- `scripts/systems/AGENTS.md` — SEnemySpawn 属于 Gameplay Group，修改需符合 system 模板
- `scripts/gameplay/AGENTS.md` — 涉及 ECS Authoring 和 Entity Creation 模式
- `tests/AGENTS.md` — 测试分层架构

### 引用的架构模式
- **System template**（`systems/AGENTS.md`）：SEnemySpawn 是 `extends System`，`group = "gameplay"`，query `CSpawner + CTransform`。修改不涉及 system 结构，仅修复内部逻辑。
- **Entity Creation**（`gameplay/AGENTS.md`）：`ServiceContext.recipe().create_entity_by_id()` 创建实体后必须通过 `ECS.world.add_entity()` 加入世界。这是 GECS v6 的标准流程——其他系统（如 `SDamage._drop_loot()` at `s_damage.gd:372` 和 `s_damage.gd:404`）都正确调用了 `add_entity()`。
- **GECS deep-copy gotcha**（`tests/AGENTS.md:199`）：`World.add_entity()` 会 deep-copy components，所以 runtime fields 必须在 `add_entity()` 之后设置。在 spawner 场景中，`new_entity` 通过 recipe 创建，所有组件都是 recipe 定义的 exported 字段，不存在 runtime-only fields 问题，因此 `add_entity` 在 append 之后调用是安全的。

### 文件归属层级
- 修改文件：`scripts/systems/s_enemy_spawn.gd` — 已有文件，无新增
- Unit test：`tests/unit/system/test_spawner_system.gd` — 已有文件，追加测试
- Integration test：`tests/integration/flow/test_flow_enemy_spawn_scene.gd` — 新增，放在 `tests/integration/flow/` 目录（符合 `tests/AGENTS.md` 中的 flow 测试目录约定）

### 测试模式
- **Unit tests**: `extends GdUnitTestSuite` 在 `tests/unit/system/`，不需要真实 World（`tests/AGENTS.md` 硬规则）
- **Integration tests**: `extends SceneConfig` 在 `tests/integration/flow/`，使用真实 GOLWorld（`tests/AGENTS.md` 硬规则）
- **E2E**: 需要 AI Debug Bridge 验证运行时视觉效果（毒雾粒子等）

## 测试契约

### Unit Tests（`tests/unit/system/test_spawner_system.gd`）

- [ ] **test_spawn_wave_adds_entity_to_world**：模拟 SEnemySpawn 环境（手动构造 World + ECS.world），验证 `_spawn_wave()` 后实体存在于 `ECS.world.entities` 中
- [ ] **test_spawn_wave_sets_correct_position**：验证刷出的实体 CTransform.position 在 spawner 附近
- [ ] **test_spawn_wave_empty_recipe_id_no_crash**：验证空 recipe_id 不 crash 且不产生实体
- [ ] **test_spawn_wave_respects_max_spawn_count**：验证达到 max_spawn_count 后不再刷出

### Integration Tests（`tests/integration/flow/test_flow_enemy_spawn_scene.gd`）

- [ ] **test_spawner_spawns_enemy_into_world**：配置 SceneConfig 包含 SEnemySpawn 系统 + 一个 CSpawner + CTransform 实体，等待 spawn_interval 后验证 `world.entities` 包含新实体（`E2E`）
- [ ] **test_poison_enemy_visible_with_area_effect**：spawner 配置为 `enemy_poison` recipe，验证刷出后实体有 CTransform/CSprite/CPoison/CAreaEffect 组件（`E2E`）

### E2E Tests
- [ ] **test_poison_fog_visible_on_map**：运行时验证毒僵尸刷出后有绿色粒子效果（AI Debug Bridge）

## 风险点

1. **`add_entity()` 的 deep-copy 行为**：GECS v6 的 `add_entity()` 会 deep-copy 所有组件。recipe 创建的实体所有字段都是 exported 的（在 .tres 中定义），所以 deep-copy 不会丢失数据。但如果将来 recipe 中添加了 runtime-only 字段（如 CContainer.stored_components），需要注意在 `add_entity` 之后重新设置。

2. **`_cleanup_invalid_entities` 的有效性**：修复后，被 SDamage 杀死的实体会触发 `SDead` → `remove_entity()`，实体变为无效引用。`_cleanup_invalid_entities()` 中的 `is_instance_valid()` 将正确返回 false，spawned 数组会被清理，max_spawn_count 配额会被释放。**修复前此机制失效**——这是为什么修复后还需要额外验证 cleanup 逻辑。

3. **多帧延迟**：`add_entity()` 在当前帧的 gameplay group processing 中调用。新实体可能需要到下一帧才能被其他 system（render group）查询到。这是正常行为，与 SDamage 中 `_drop_loot()` 的模式一致。

4. **影响范围**：此修复影响所有 spawner 类型。由于修复是补回遗漏的标准调用，风险极低——所有 recipe-based entity 创建都遵循这个模式。

## 建议的实现步骤

1. **修复 `s_enemy_spawn.gd`**：在 `_spawn_wave()` 函数中，`spawner.spawned.append(new_entity)` 之后添加 `ECS.world.add_entity(new_entity)`（1 行修改）
2. **添加 unit tests**：在 `tests/unit/system/test_spawner_system.gd` 中添加 SEnemySpawn 系统逻辑测试（spawn → add_entity、position、max_count、empty recipe）
3. **添加 integration test**：新建 `tests/integration/flow/test_flow_enemy_spawn_scene.gd`，验证 spawner 实际将实体刷入 GOLWorld
4. **运行现有测试**：运行 `tests/unit/system/test_spawner_system.gd`、`tests/unit/test_poison_component.gd`、`tests/unit/system/test_area_effect_modifier.gd` 确保无回归
5. **运行全部 unit tests**：确认整体测试通过
6. **E2E 验证**：通过 AI Debug Bridge 在运行时验证毒僵尸刷出后有可见的绿色毒雾粒子效果
