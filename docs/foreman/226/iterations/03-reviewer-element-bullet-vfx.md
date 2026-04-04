# Issue #226 元素子弹 VFX — 审查报告

## 审查范围

| 文件 | 操作 | 审查深度 |
|------|------|----------|
| `scripts/components/c_bullet.gd` | 修改 | 完整文件阅读 |
| `scripts/systems/s_fire_bullet.gd` | 修改 | 完整文件阅读 + diff 对比 |
| `scripts/systems/s_bullet_vfx.gd` | 新建 | 完整文件阅读（402 行） |
| `scripts/systems/s_damage.gd` | 修改 | diff + 完整文件阅读 |
| `tests/unit/system/test_bullet_vfx.gd` | 新建 | 完整文件阅读 |
| `tests/integration/test_bullet_vfx.gd` | 新建 | 完整文件阅读 |
| `scripts/components/AGENTS.md` | 修改 | diff 对比 |
| `scripts/systems/AGENTS.md` | 修改 | diff 对比 |

参考对比文件：`s_elemental_visual.gd`、`s_dead.gd`、`s_area_effect_modifier_render.gd`、`s_life.gd`、`entity.gd`、`world.gd`

## 验证清单

### 文件完整性
- [x] **Coder 文档声称文件 vs git diff 实际文件一一对比** — 8/8 匹配，无缺失文件
- [x] **无 AGENTS.md/CLAUDE.md 框架文件违规改动** — AGENTS.md 修改仅为文档更新（组件/系统目录说明），不属于框架规则改动

### c_bullet.gd 审查
- [x] **Component 纯数据约束** — `element_type: int = -1` 是纯数据字段，无逻辑。验证动作：阅读完整文件（12 行），确认无方法、无信号
- [x] **默认值安全** — `-1` 表示无元素，`element_type < 0` 判断在 SBulletVfx 和 SDamage 中一致使用
- [x] **@export 声明** — 使用 `@export` 允许编辑器配置，与其他组件字段风格一致

### s_fire_bullet.gd 审查
- [x] **preload 模式** — `const COMPONENT_ELEMENTAL_ATTACK = preload(...)` 在文件顶部（第 5 行），与 s_damage.gd 的 preload 模式一致
- [x] **拷贝时机** — 在 `_create_bullet()` 中、`bullet_comp.owner_entity = shooter` 之后立即拷贝（第 137-139 行），子弹创建时就携带元素类型
- [x] **Group 处理顺序保证** — SFireBullet 在 `gameplay` group，SBulletVfx 在 `render` group。按 AGENTS.md 定义，gameplay 在 render 之前处理，确保 element_type 在 VFX 系统查询时已设置
- [x] **边界条件** — `shooter.has_component(COMPONENT_ELEMENTAL_ATTACK)` 检查防止无元素射击者访问不存在的组件。验证动作：追踪代码路径，确认 `CElementalAttack` 只在确认存在后才 `get_component`

### s_bullet_vfx.gd 审查（核心审查目标）
- [x] **class_name 和继承** — `class_name SBulletVfx extends System`，声明正确
- [x] **Group 设置** — `_ready()` 中 `group = "render"`，与 planner 指定一致
- [x] **Query 模式** — `q.with_all([CBullet, CTransform]).with_none([CDead])`，排除已死亡实体
- [x] **_trails Dictionary 缓存** — `var _trails: Dictionary = {}`，key 为 `entity.get_instance_id()`，value 包含 `particles` 和 `entity` 引用
- [x] **component_removed 信号** — `_create_trail()` 第 89-90 行连接信号，第 289-291 行处理回调。验证动作：对比 SElementalVisual 第 78-79 行和第 344-346 行，模式完全一致
- [x] **信号签名匹配** — Entity.component_removed 签名 `(entity: Entity, component: Resource)`，SBulletVfx 回调签名 `(entity: Entity, component: Variant, entity_id: int)` 通过 `.bind(entity_id)` 注入第三参数，Godot bind 机制兼容
- [x] **4 种元素 trail 配置** — FIRE/WET/COLD/ELECTRIC 均有独立配置方法，参数差异合理
- [x] **spawn_impact 静态方法** — `static func spawn_impact(position: Vector2, element_type: int)` 使用 `ECS.world.add_child()`，与 s_dead.gd 第 208 行模式一致
- [x] **CPUParticles2D 自清理** — 4 个 impact 方法均连接 `particles.finished.connect(particles.queue_free)`，与 s_dead.gd 第 206 行一致
- [x] **local_coords = false + global_position 同步** — 第 63-64 行设置，第 257 行每帧同步，与 SElementalVisual 的 `_update_view` 模式一致
- [x] **未知元素类型处理** — `_create_trail()` 第 76-78 行 match 的 `_` 分支执行 `particles.queue_free()` 并 return，不会留下未释放节点

### s_damage.gd 审查
- [x] **VFX 调用位置** — `SBULLET_VFX.spawn_impact()` 在第 108 行，位于 `ECS.world.remove_entity(bullet_entity)` 第 110 行之前。验证动作：完整阅读 `_process_bullet_collision()` 函数流程
- [x] **条件检查** — `if bullet and bullet.element_type >= 0:` 在 `_apply_bullet_effects` 之后、`remove_entity` 之前
- [x] **preload 模式** — `const SBULLET_VFX = preload(...)` 在文件顶部第 9 行，与其他 preload 风格一致
- [x] **不影响非目标路径** — VFX 调用仅在 `_process_bullet_collision` 的命中路径中，`_process_pending_damage` 路径不受影响。验证动作：追踪 `_process_entity()` 的两个分支

### 测试审查
- [x] **单元测试框架** — `extends GdUnitTestSuite`，位于 `tests/unit/system/`，符合 tests/AGENTS.md 约束
- [x] **集成测试框架** — `class_name TestBulletVfxConfig extends SceneConfig`，位于 `tests/integration/`，符合约束
- [x] **auto_free 使用** — 所有单元测试中的 Entity/Component/System 均使用 `auto_free()` 包裹
- [x] **文件命名** — `test_bullet_vfx.gd` 符合 `test_*.gd` 约定

### 架构一致性对照（固定检查项）
- [x] 新增代码是否遵循 planner 指定的架构模式 — SBulletVfx 放在 render group，query 使用 `with_all + with_none`，字典缓存 + component_removed 清理
- [x] 新增文件是否放在正确目录，命名符合 AGENTS.md 约定 — `s_bullet_vfx.gd` 在 `scripts/systems/`，class_name `SBulletVfx`，文件命名 `s_bullet_vfx`
- [x] 是否存在平行实现——功能和已有代码重叠但没有复用 — SBulletVfx 复用了 SElementalVisual 的粒子创建模式、s_dead 的 CPUParticles2D one_shot 模式，不存在平行实现
- [x] 测试是否使用正确的测试模式 — 单元测试 GdUnitTestSuite、集成测试 SceneConfig，各在正确目录
- [x] 测试是否验证了真实行为 — 位置同步测试（第 128-152 行）、清理测试（第 156-185 行）验证了具体行为而非仅存根

## 发现的问题

### Issue 1: 子弹超时移除不触发 impact VFX
- **严重程度**: Important
- **置信度**: 高
- **文件位置**: `scripts/systems/s_life.gd:32-33`
- **描述**: 当子弹因生命周期到期（CLifeTime）被 `SLife._handle_lifetime_expired()` 移除时，直接调用 `ECS.world.remove_entity(entity)` 而不触发 `SBulletVfx.spawn_impact()`。只有 `SDamage._process_bullet_collision()` 中的命中路径会触发 impact。这意味着元素子弹飞出屏幕超时消失时不会有命中特效——这在视觉上可能是可接受的（子弹没命中就不应该有 impact），但 coder 文档声称 "覆盖飞行轨迹和命中表现"，而实际 impact 仅覆盖了命中路径。

  然而，从游戏设计角度看，超时子弹 = 未命中，不显示 impact 是合理行为。planner 文档的 "命中表现" 描述也明确指 "命中时"。此处为 **设计确认**，非代码缺陷。**降级为 Minor，无需修复。**

### Issue 2: remove_entity 时 trail 粒子可能泄漏
- **严重程度**: Minor
- **置信度**: 中
- **文件位置**: `scripts/systems/s_bullet_vfx.gd:273-285`（`_remove_trail`）
- **描述**: `remove_entity()` 流程中（world.gd:406-409），World 断开了自身对 `entity.component_removed` 的监听，但 SBulletVfx 的监听仍连接。不过 World 通过 `world.component_removed.emit()` 通知（world.gd:418），而非 `entity.component_removed.emit()`。因此 SBulletVfx 的 `_on_component_removed` 在 `remove_entity` 路径中**不会被调用**。

  Trail 清理实际依赖 `_cleanup_removed_trails(active_ids)` 在 `process()` 中执行——当实体从 World 中移除后，它不再出现在 query 结果中，下一帧 `process()` 会将其从 `_trails` 中清理。但存在一个时序问题：`entity.queue_free()`（world.gd:444）在 `remove_entity` 中被调用，Entity 节点被标记为待释放。如果 `process()` 在 `queue_free` 实际执行前运行，粒子节点仍作为 entity 子节点存在。`_remove_trail()` 中第 282 行 `particles.emitting = false` 和第 283 行 `particles.queue_free()` 会正确处理。但如果 `queue_free` 在 `process()` 之前执行（同一帧内的释放顺序），`is_instance_valid(particles)` 检查（第 281 行）会返回 false，跳过清理，`_trails` 字典中留下 stale entry。

  **实际影响**：`_trails` 字典中可能残留无效的 entity_id 条目，但由于 entity 已被移除，不会再被 query 匹配，不会导致功能错误。仅是微小的内存泄漏（Dictionary entry），在实际游戏中可忽略。

  **建议修复**（可选）：在 `_update_trail()` 和 `_remove_trail()` 中已使用 `is_instance_valid()` 保护，足够安全。无需强制修复。

### Issue 3: spawn_impact 中 CPUParticles2D.position 是局部坐标
- **严重程度**: Minor
- **置信度**: 高
- **文件位置**: `scripts/systems/s_bullet_vfx.gd:300-400`（所有 `_spawn_*_impact` 方法）
- **描述**: Impact 粒子通过 `particles.position = position` 设置位置，然后 `ECS.world.add_child(particles)`。由于 CPUParticles2D 默认 `local_coords = true`，`position` 是相对于父节点的。如果 `ECS.world` 的原点在 (0,0)（场景根节点），这没问题。但如果 World 有偏移，粒子的世界位置会不正确。

  **对比 s_dead.gd:186-208**：s_dead 使用完全相同的模式 `particles.position = transform.position` + `ECS.world.add_child(particles)`。说明这是项目已有的模式，如果 s_dead 没有问题，SBulletVfx 也不会有问题。**无需修复，与现有代码一致。**

### Issue 4: 集成测试中 test_impact_on_hit 契约标记为"部分覆盖"但未实际测试
- **严重程度**: Important
- **置信度**: 高
- **文件位置**: `tests/integration/test_bullet_vfx.gd`
- **描述**: Coder 文档声称集成测试包含 3 个测试用例，其中 `test_impact_on_hit` 为"部分覆盖"。但实际阅读文件后发现，集成测试文件只有一个 `test_run()` 方法（第 58 行），包含了 `test_elemental_bullet_has_trail` 和 `test_normal_bullet_no_trail` 两个验证，但没有独立的 impact 测试场景。这意味着：

  1. 契约中声称的 3 个集成测试实际只有 1 个 `test_run()` 方法
  2. `test_impact_on_hit` 没有被实现——即使 coder 文档声称是"部分覆盖"
  3. impact VFX 路径（SDamage → SBulletVfx.spawn_impact）完全缺乏集成级验证

  **影响**: Impact 粒子创建和挂载到 ECS.world 的完整路径没有被集成测试覆盖。SDamage 的改动（第 107-108 行）缺少端到端验证。

  **建议修复**: 在集成测试中添加独立的 impact 验证。可以通过直接调用 `SBulletVfx.spawn_impact()` 并检查 `ECS.world` 的子节点来验证，或通过构造子弹碰撞场景来端到端验证。最低限度应验证 `spawn_impact()` 能正确在 world 上创建粒子节点。

### Issue 5: 单元测试 test_spawn_impact_static_method_exists 和 test_spawn_impact_no_element_does_nothing 是空测试
- **严重程度**: Important
- **置信度**: 高
- **文件位置**: `tests/unit/system/test_bullet_vfx.gd:88-101`
- **描述**: 两个 spawn_impact 相关的单元测试实质上是空断言：
  - `test_spawn_impact_static_method_exists`（第 88-93 行）：只执行 `BULLET_VFX_SYSTEM.has_script_signal("")`（检查一个空信号名），然后断言 `true`。这既不验证方法存在，也不验证任何行为。
  - `test_spawn_impact_no_element_does_nothing`（第 98-101 行）：只有 `assert_bool(true).is_true()`，完全不测试任何东西。

  Coder 文档正确地将这两个标记为"部分覆盖"，但实际上它们是**零覆盖**。tests/AGENTS.md 明确允许单元测试中不测试需要 World 的功能，但这两个测试应该被标记为跳过（使用 `skip()`）或至少有一个有意义的断言，而不是伪装为通过的测试。

  **建议修复**: 使用 gdUnit4 的 `skip("需要 ECS.world 环境")` 标记跳过，或移除这两个测试并用注释说明为什么不能在单元测试中验证。

## 测试契约检查

### 单元测试契约

| 契约测试名 | 状态 | 说明 |
|------------|------|------|
| `test_create_fire_trail_creates_gpu_particles` | ✅ 通过 | 验证 _trails 有记录，粒子非空 |
| `test_create_wet_trail_creates_gpu_particles` | ✅ 通过 | WET 元素 trail 创建 |
| `test_no_element_no_trail` | ✅ 通过 | element_type=-1 不创建 trail |
| `test_remove_trail_on_entity_removal` | ✅ 通过 | component_removed 信号清理 |
| `test_spawn_impact_creates_cpu_particles` | ❌ 空测试 | 无实际断言，仅 assert_bool(true) |
| `test_spawn_impact_no_element_does_nothing` | ❌ 空测试 | 无实际断言 |
| `test_element_type_on_bullet_default` | ✅ 通过 | 默认值 -1 |
| `test_element_type_settable` | ✅ 通过 | 4 种元素可设置读取 |

**扩展测试**: 3 个额外测试（COLD/ELECTRIC trail 创建、位置更新、批量清理）均有效。

**契约覆盖率**: 6/8 通过，2 个空测试。

### 集成测试契约

| 契约测试名 | 状态 | 说明 |
|------------|------|------|
| `test_elemental_bullet_has_trail` | ✅ 通过 | 在 test_run() 中验证 |
| `test_normal_bullet_no_trail` | ✅ 通过 | 在 test_run() 中验证 |
| `test_impact_on_hit` | ❌ 未实现 | 文件中不存在独立 impact 测试 |

**契约覆盖率**: 2/3 通过，1 个未实现。

### 集成测试代码质量
- [x] SceneConfig 模式正确：`scene_name()`、`systems()`、`enable_pcg()`、`entities()`、`test_run()` 均存在
- [x] entities 使用 recipe-based 声明（"player"、"enemy_basic"）
- [ ] **违反 tests/AGENTS.md**：`_create_test_bullet()` 方法（第 117-141 行）使用 `Entity.new()` 手动构造子弹，而非 recipe-based 方式。虽然测试文档允许在集成测试中手动构造复杂测试实体，但使用 recipe 更符合约定

## 结论

**`rework`** — 发现 2 个 Important 级别问题需要修复：

1. **集成测试 test_impact_on_hit 未实现**（Important）— coder 文档声称"部分覆盖"但实际完全未实现，SDamage 的 VFX 调用路径缺乏任何集成级验证
2. **两个 spawn_impact 单元测试是空测试**（Important）— `test_spawn_impact_static_method_exists` 和 `test_spawn_impact_no_element_does_nothing` 无实际断言，应使用 `skip()` 或移除

**修复清单**：
1. 在集成测试中添加 impact 验证（至少验证 `spawn_impact()` 能在 world 上创建 CPUParticles2D 节点）
2. 将两个空单元测试标记为 `skip()` 或移除
