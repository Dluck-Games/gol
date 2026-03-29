# 04-reviewer-scope-creep-and-untested-fix.md

## 审查范围

### 审查文件
| 文件 | 类型 | 行数 |
|------|------|------|
| `scripts/systems/s_enemy_spawn.gd` | 核心修复 | 147 |
| `scripts/systems/s_damage.gd` | 未计划修改 | 578 |
| `scripts/systems/s_area_effect_modifier.gd` | 未计划修改 | 173 |
| `scripts/systems/s_loot_spawn.gd` | 新增 | 80 |
| `scripts/components/c_loot_point.gd` | 新增 | 17 |
| `scripts/components/c_spawner.gd` | 追踪调用链 | 44 |
| `scripts/gameplay/ecs/gol_world.gd` | 重构（440-560） | 554 |
| `scripts/components/c_container.gd` | 深拷贝验证 | - |
| `addons/gecs/ecs/world.gd` | add_entity 行为 | - |
| `addons/gecs/ecs/entity.gd` | _initialize 深拷贝 | - |
| `tests/unit/system/test_spawner_system.gd` | 单元测试 | 192 |
| `tests/unit/test_loot_point_component.gd` | 单元测试 | 39 |
| `tests/unit/test_spawner_loot_drop.gd` | 单元测试 | 47 |
| `tests/unit/system/test_loot_spawn.gd` | 单元测试 | 128 |
| `tests/unit/system/test_area_effect_modifier.gd` | 单元测试 | - |
| `tests/integration/flow/test_flow_enemy_spawn_scene.gd` | 集成测试 | 87 |
| `tests/integration/flow/test_flow_loot_spawn_scene.gd` | 集成测试 | 81 |
| `tests/integration/flow/test_flow_loot_respawn_scene.gd` | 集成测试 | 112 |
| `tests/integration/flow/test_flow_spawner_loot_drop_scene.gd` | 集成测试 | 108 |

### 审查代码路径
1. `SEnemySpawn._spawn_wave()` → `ServiceContext.recipe().create_entity_by_id()` → `ECS.world.add_entity()` 调用链
2. `SDamage._handle_spawner_death()` → `_spawner_death_burst()` → 检查 add_entity 是否遗漏
3. `SDamage._spawner_drop_loot()` → 对比同类 add_entity 用法
4. `SLootSpawn._process_entity()` → `_spawn_loot_box()` → `ECS.world.add_entity()` + typed ref 生命周期
5. `GOLWorld._spawn_loot_boxes_at_building_pois()` → `_spawn_loot_point_at_position()` 重构路径
6. `SPickup.remove_entity()` → `queue_free` 时序 → `CLootPoint.active_box` auto-null 行为
7. GECS `World.add_entity()` → `Entity._initialize()` → 深拷贝 (duplicate_deep) 行为

### 验证手段
- `grep` 搜索所有 `ECS.world.add_entity` 调用点（6处）和 `add_entity` 调用点（8处），逐一对比
- 读取 `addons/gecs/ecs/world.gd:291-359` 和 `entity.gd:88-113` 验证 deep-copy 机制
- 读取 `CContainer` 源码确认 `stored_recipe_id` 是 `@export var`（值类型，深拷贝安全）
- 读取 `SDamage._spawner_death_burst()` 全函数（318-334），确认同类 bug
- `grep` 搜索 `remove_entity` 调用点，验证实体生命周期

## 验证清单

- [x] **核心修复位置验证**：读取 `s_enemy_spawn.gd` 全文，确认第 85 行 `ECS.world.add_entity(new_entity)` 紧跟 `spawner.spawned.append(new_entity)` 之后，与 planner 方案一致
- [x] **深拷贝安全性验证**：读取 GECS `Entity._initialize()` 实现和 `CContainer` 定义。`stored_recipe_id` 是 `@export var String`（值类型），在 `add_entity` 前设置可安全通过深拷贝。`new_transform.position` 同理。`spawner.spawned` 存储的是实体对象引用（非组件），不受组件深拷贝影响
- [x] **同类模式对比**：读取 `s_damage.gd:_spawner_drop_loot()` (336-374) 和 `s_damage.gd:_drop_component_box()` (377-412)。前者在 `add_entity` 前设置所有字段（值类型，安全）。后者在 `add_entity` 后设置 `stored_components` 和 `dropped_by`（引用类型，需 post-add 设置，代码有注释说明）。修复行的用法与 `_spawner_drop_loot` 一致
- [x] **同类 bug 搜索**：`grep "ECS.world.add_entity"` 全代码库 → 发现 `s_damage.gd:_spawner_death_burst()` (318-334) 同样调用 `create_entity_by_id()` 但未调用 `add_entity()`。**这是与本次修复完全相同的 bug 类别，但存在于 pre-existing 代码中**
- [x] **CDead guard 验证**：读取 `s_area_effect_modifier.gd` 全文。CDead guard 在 `_process_entity` 顶部（第 26-27 行），位于 null check 之后、组件获取之前。逻辑正确——dead 实体不应施加任何 area effect
- [x] **SLootSpawn typed ref 行为追踪**：读取 `SPickup.remove_entity` 调用（`s_pickup.gd:49, 134, 142`）。GECS `remove_entity` 对 in-tree 实体调用 `queue_free()`（延迟释放）。`CLootPoint.active_box: Entity` 类型声明后，Godot 4.x 在对象释放后应 auto-null typed ref。测试 `test_flow_loot_respawn_scene.gd` 通过 4 帧 await 验证了此时序
- [x] **gol_world.gd 重构验证**：读取 `_spawn_loot_point_at_position()` (537-554)。新函数创建 CLootPoint 实体（CTransform + CLootPoint + combined loot pool）并调用 `add_entity`，由 SLootSpawn 系统接管后续生成逻辑。原先的直接生成 LootBox 逻辑被完全替换
- [x] **s_damage.gd loot pool 变更验证**：读取 `_spawner_drop_loot()` (336-374)。原来硬编码 `["weapon_rifle", "weapon_pistol", "tracker", "weapon_fire", "weapon_cold", "weapon_wet", "weapon_electric"]`（7 项，仅武器），改为 `LOOT_WEAPON_RECIPES + LOOT_MATERIA_RECIPES`（9 项，武器+materia）。这是一个行为变更：spawner 死亡掉落池从 100% 武器变为 78% 武器 + 22% materia
- [x] **add_entity 调用完整性**：遍历所有 8 个 `add_entity` 调用点，确认新增的 `s_loot_spawn.gd:73` 和 `gol_world.gd:552` 均正确调用

#### 架构一致性对照（固定检查项）

- [x] 新增 `CLootPoint` 组件遵循 Component 模式：`extends Component`，`@export` 字段 + 运行时 `var` 分离，放在 `scripts/components/` 目录。符合 `components/AGENTS.md` 约定
- [x] 新增 `SLootSpawn` 系统遵循 System 模式：`extends System`，`_ready()` 设置 `group = "gameplay"`，`query()` 返回 `QueryBuilder`，`process()` 遍历 entities。放在 `scripts/systems/` 目录。符合 `systems/AGENTS.md` 约定
- [x] **架构违规：scope creep**（详见发现的问题 #1）。CLootPoint、SLootSpawn、gol_world.gd 重构、s_damage.gd loot pool 变更、s_area_effect_modifier.gd CDead guard 均未在 planner 方案（`01-planner-spawner-missing-add-entity.md`）中列出，也未在 orchestration 决策中被批准
- [x] 单元测试使用 `extends GdUnitTestSuite`，放在 `tests/unit/`。符合 `tests/AGENTS.md`
- [x] 集成测试使用 `extends SceneConfig`，放在 `tests/integration/flow/`。符合 `tests/AGENTS.md`
- [x] **测试质量不足**（详见发现的问题 #3）：核心修复（`add_entity` 一行）未被任何测试直接验证。`test_flow_enemy_spawn_scene.gd` 只验证 recipe-based 实体的组件结构，不验证 `_spawn_wave()` 的 add_entity 行为

## 发现的问题

### #1 scope creep — PR 混合了未批准的功能新增和行为变更
- **严重程度**: Important
- **置信度**: High
- **文件**: 多文件（见审查范围）
- **描述**: Planner 方案仅批准了 3 项变更：(1) `s_enemy_spawn.gd` 1 行修复，(2) spawner unit tests，(3) enemy spawn integration test。实际 PR 包含了以下未批准的变更：

  | 变更 | 类型 | 是否在 planner 方案中 |
  |------|------|----------------------|
  | `CLootPoint` 组件 | 新功能 | 否 |
  | `SLootSpawn` 系统 | 新功能 | 否 |
  | `gol_world.gd` 重构（loot box → loot point） | 行为变更 | 否 |
  | `s_damage.gd` loot pool 扩展（+materia） | 行为变更 | 否 |
  | `s_area_effect_modifier.gd` CDead guard | 独立 bug fix | 否 |
  | 4 个新测试文件（loot spawn/respawn/loot drop） | 测试 | 否 |

  `s_damage.gd` 的 loot pool 变更是**行为变更**——spawner 死亡掉落从 100% 武器变为 78% 武器 + 22% materia，这改变了游戏平衡。
- **建议**: 将 scope creep 变更拆分为独立 PR。核心修复 PR（`s_enemy_spawn.gd:85` 1 行）应独立合并。

### #2 `_spawner_death_burst()` 遗漏 `add_entity` — 与本次修复同类的 pre-existing bug
- **严重程度**: Important
- **置信度**: High
- **文件**: `scripts/systems/s_damage.gd:318-334`
- **描述**: `_spawner_death_burst()` 调用 `ServiceContext.recipe().create_entity_by_id()` 创建 3 个敌人实体，但**从未调用 `ECS.world.add_entity()`**。这与 Issue #196 的根因（`_spawn_wave()` 遗漏 `add_entity`）是**完全相同的 bug 类别**。结果是：spawner 被击杀时的死亡爆发（3 个敌人）不会出现在地图上。

  虽然这是 pre-existing 代码（不在 diff 中），但鉴于此 PR 的目的是修复 "所有 spawner 刷出的敌人不可见" 问题，这个遗漏高度相关。
- **建议**: 在同一 PR 或后续 PR 中修复。在 `_spawner_death_burst()` 的 for 循环内，在 `new_transform.position = ...` 之后添加 `ECS.world.add_entity(new_entity)`。

### #3 核心修复未被直接测试
- **严重程度**: Important
- **置信度**: High
- **文件**: `tests/unit/system/test_spawner_system.gd`, `tests/integration/flow/test_flow_enemy_spawn_scene.gd`
- **描述**: PR 的核心修复是 `s_enemy_spawn.gd:85` 的一行 `ECS.world.add_entity(new_entity)`。然而：
  - **Unit tests**（`test_spawner_system.gd`）只测试 CSpawner 的数据逻辑（max_spawn_count 计算、cleanup 逻辑），不测试 `_spawn_wave()` 函数
  - **Integration test**（`test_flow_enemy_spawn_scene.gd`）通过 recipe-based entities 加载 `enemy_basic` 和 `enemy_poison`，但**只验证了组件结构**（CPoison、CAreaEffect 存在），不验证 SEnemySpawn 系统的 `_spawn_wave()` 行为

  Coder 在 `02-coder-add-missing-entity-spawn.md` 中明确承认了这些测试缺口。没有任何测试验证 "修复后 spawner 能将实体加入世界" 这个核心断言。
- **建议**: 虽然 AGENTS.md 限制了 unit test 中使用 World/ECS.world，但 integration test（SceneConfig）中应该可以构造一个 spawner entity 并验证 `_spawn_wave` 结果。考虑补充一个 integration test：创建带 CSpawner + CTransform 的实体，配置短 spawn_interval，等待后验证 `world.entities` 包含新敌人。

### #4 `SLootSpawn` 的 typed ref auto-null 依赖
- **严重程度**: Minor
- **置信度**: Medium
- **文件**: `scripts/systems/s_loot_spawn.gd:35`
- **描述**: `loot_point.active_box != null` 依赖 Godot 4.x 的 typed reference auto-null 行为——当 `Entity` 被 `queue_free()` 释放后，`var active_box: Entity` 应自动变为 `null`。代码注释也明确依赖此行为。

  此行为在 Godot 4.2+ 中有文档记录，但依赖运行时行为而非显式检查（如 `is_instance_valid()`）是脆弱的。如果未来 Godot 版本改变此行为，loot respawn 机制会**静默失败**——`active_box` 永远不为 null，计时器永远不启动，loot box 永远不会重生。
- **建议**: 改用 `is_instance_valid(loot_point.active_box)` 进行显式检查，与 `s_enemy_spawn.gd:134` 和 `s_area_effect_modifier.gd:20` 的模式一致。

### #5 纹理路径硬编码重复
- **严重程度**: Minor
- **置信度**: High
- **文件**: `s_loot_spawn.gd:5`, `gol_world.gd:32`, `s_damage.gd:348`
- **描述**: `"res://assets/sprite_sheets/boxes/box_re_texture.png"` 在 3 个文件中各自硬编码。如果纹理路径变更，需要同步修改 3 处。
- **建议**: 将纹理路径提取到 `GOLWorld.LOOT_BOX_TEXTURE_PATH`（已存在）或独立的 constants 文件中。

## 测试契约检查

### Unit Tests（来自 planner 测试契约）

| 契约 | 状态 | 评估 |
|------|------|------|
| `test_spawn_wave_adds_entity_to_world` | **未覆盖** | 需要 `ECS.world`，coder 放弃实现。Integration test 也没有覆盖此路径 |
| `test_spawn_wave_sets_correct_position` | **未覆盖** | Coder 理由：依赖运行时随机数。实际可以验证 position 在 spawner 范围内 |
| `test_spawn_wave_empty_recipe_id_no_crash` | **间接覆盖** | 已有 `test_spawner_with_empty_recipe_id` 测试 AuthoringSpawner 层面。`_spawn_wave` 的空 recipe 分支（push_error + return）未被测试 |
| `test_spawn_wave_respects_max_spawn_count` | **部分覆盖** | 3 个 test 覆盖了 count 计算逻辑，但未通过 `_spawn_wave` 验证 |

### Integration Tests（来自 planner 测试契约）

| 契约 | 状态 | 评估 |
|------|------|------|
| `test_spawner_spawns_enemy_into_world` | **未覆盖** | Integration test 改为验证 recipe-based 实体组件，未测试 SEnemySpawn._spawn_wave |
| `test_poison_enemy_visible_with_area_effect` | **已覆盖** | 通过 `TestEnemyPoison` 验证 CPoison + CAreaEffect 组件存在 |

### E2E Tests（来自 planner 测试契约）

| 契约 | 状态 | 评估 |
|------|------|------|
| `test_poison_fog_visible_on_map` | **未覆盖** | 需要 AI Debug Bridge，已正确标记为后续 |

### 额外测试（未在 planner 契约中）

| 测试文件 | 测试数 | 覆盖内容 | 质量 |
|----------|--------|----------|------|
| `test_loot_point_component.gd` | 5 | CLootPoint 默认值、可变性、生命周期 | 低——仅测试数据模型，不测试系统行为 |
| `test_spawner_loot_drop.gd` | 5 | Loot pool 内容、概率、无重复 | 中——验证了 pool 组成 |
| `test_loot_spawn.gd` | 8 | CLootPoint 状态转换、计时器、方差 | 低——手动模拟 SLootSpawn 逻辑，不通过系统执行 |
| `test_area_effect_modifier.gd` (新增) | 3 | CDead guard | 中——但 regression test 绕过了 `_process_entity` |
| `test_flow_loot_spawn_scene.gd` | 6 | SLootSpawn 初始生成 | 高——真实 GOLWorld + 系统执行 |
| `test_flow_loot_respawn_scene.gd` | 9 | SLootSpawn 重生周期 | 高——验证了完整的 pickup → timer → respawn 流程 |
| `test_flow_spawner_loot_drop_scene.gd` | 7 | SDamage spawner 掉落 | 高——验证了 spawner 死亡 → loot box + CLifeTime |

**测试契约总结**: Planner 契约中 6 项测试中 2 项已覆盖、2 项部分覆盖、2 项未覆盖。额外的 43 个测试（7 个新文件）覆盖了 scope creep 代码的质量，但这些代码本不应在此 PR 中。

## 结论

**`rework`**

### 必须修复的问题

1. **Scope creep 需要分离**：CLootPoint/SLootSpawn 系统（新功能）、gol_world.gd 重构（行为变更）、s_damage.gd loot pool 扩展（平衡变更）、CDead guard（独立 bug fix）均应从 PR #219 中拆出。核心修复（`s_enemy_spawn.gd:85` 1 行）应独立合并。

2. **`_spawner_death_burst()` (s_damage.gd:318-334) 应一并修复**：这是与 Issue #196 完全相同类别的 bug——通过 `create_entity_by_id()` 创建的实体未加入世界。虽然 pre-existing，但与本次修复高度相关且影响 spawner 死亡爆发行为。

### 正确的部分

- 核心修复（`s_enemy_spawn.gd:85`）位置正确、与 planner 方案完全一致
- 深拷贝安全性已验证：`CTransform.position`（Vector2）和 `CContainer.stored_recipe_id`（String）在 `add_entity` 前设置可安全通过深拷贝
- CDead guard 逻辑正确
- CLootPoint/SLootSpawn 代码质量好（遵循架构模式），但不属于此 PR 范围
