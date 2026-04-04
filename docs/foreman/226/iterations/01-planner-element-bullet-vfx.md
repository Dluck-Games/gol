# 元素子弹 VFX 特效 — 实现规划

## 需求分析

### Issue 目标
为各类元素子弹（火、水、冰、电）添加对应的 VFX 特效，覆盖**飞行轨迹**（trail）和**命中表现**（impact）。

### 当前状态
- 所有 4 种元素武器（weapon_fire / weapon_wet / weapon_cold / weapon_electric）共用同一个子弹 recipe：`bullet_normal`
- 子弹实体由 `SFireBullet` 通过 `ServiceContext.recipe().create_entity_by_id("bullet_normal")` 创建
- 子弹实体组件：`CMovement, CTransform, CSprite, CBullet, CCollision, CLifeTime`
- **当前子弹没有任何 VFX**——只是移动中的静态 Sprite2D
- 元素信息（`CElementalAttack`）只存在于射击者身上，子弹本身不携带元素类型信息
- 命中时 `SDamage._apply_bullet_effects()` 通过 `bullet.owner_entity` 回查射击者的 `CElementalAttack` 来应用元素效果
- 子弹生命周期终止路径：
  - **命中**：`SDamage._process_bullet_collision()` → `ECS.world.remove_entity(bullet_entity)`
  - **超时**：`SLife._handle_lifetime_expired()` → `ECS.world.remove_entity(entity)`

### 关键发现：元素信息传递断层
当前 `CBullet` 组件不包含元素类型信息。VFX 系统需要知道子弹属于哪个元素，但这个信息只存在于射击者的 `CElementalAttack` 上。需要在子弹创建时传递元素类型。

### 需求分层
1. **代码框架层**（本次实现）：新 component + system 定义，支持占位粒子效果
2. **美术资产层**（后续迭代）：具体粒子材质、纹理、颜色精调

---

## 影响面分析

### 现有文件需修改

| 文件 | 修改内容 |
|------|----------|
| `scripts/components/c_bullet.gd` | 新增 `element_type: int` 字段，记录元素类型 |
| `scripts/systems/s_fire_bullet.gd` | 在 `_create_bullet()` 中从射击者 `CElementalAttack` 拷贝元素类型到子弹 |
| `scripts/systems/s_damage.gd` | 在 `_process_bullet_collision()` 命中时触发命中 VFX（或发出信号） |

### 新建文件

| 文件 | 类型 | 说明 |
|------|------|------|
| `scripts/systems/s_bullet_vfx.gd` | System (render group) | 子弹 VFX 系统：飞行轨迹粒子 + 命中爆发粒子 |

### 不需要新建 Component
飞行轨迹 VFX 是子弹实体的视觉附属物，由 `SBulletVfx` 系统在 `render` group 中根据 `CBullet.element_type` 和 `CTransform` 动态管理。不需要额外的 component，因为 VFX 配置是元素类型的映射，不是 per-entity 数据。

### 不涉及的文件
- `s_render_view.gd`：无需修改，它只负责 Sprite2D 同步
- `s_elemental_visual.gd`：无需修改，它只处理 affliction（元素异常状态）的视觉
- `resources/recipes/bullet_normal.tres`：**不需要拆分**为多元素子弹 recipe。继续共用 `bullet_normal`，通过 runtime 属性区分元素
- `resources/recipes/weapon_*.tres`：无需修改

---

## 实现方案

### 1. CBullet 扩展 — 携带元素类型

在 `c_bullet.gd` 中新增字段：

```gdscript
## 元素类型，对应 CElementalAttack.ElementType 枚举
## -1 = 无元素（普通子弹）
@export var element_type: int = -1
```

### 2. SFireBullet 修改 — 传递元素类型

在 `_create_bullet()` 函数中，创建子弹后、设置 velocity/position/owner 之后，拷贝射击者的元素类型：

```gdscript
# 拷贝元素类型到子弹
if shooter.has_component(CElementalAttack):
    var elemental_attack: CElementalAttack = shooter.get_component(CElementalAttack)
    bullet_comp.element_type = elemental_attack.element_type
```

### 3. 新建 SBulletVfx 系统 — 核心 VFX 逻辑

**文件**：`scripts/systems/s_bullet_vfx.gd`
**Class**：`SBulletVfx`
**Group**：`render`（与 `SRenderView`、`SElementalVisual` 同组）
**Query**：`q.with_all([CBullet, CTransform]).with_none([CDead])`

#### 职责

1. **飞行轨迹（Trail）**：为带元素类型的子弹创建 GPUParticles2D 尾迹粒子
2. **命中爆发（Impact）**：在子弹被移除前生成一次性命中粒子效果

#### 架构设计

```
SBulletVfx (render group)
├── _trails: Dictionary  # instance_id → GPUParticles2D（飞行尾迹）
├── process(): 创建/更新/清理尾迹粒子
└── spawn_impact(position, element_type): 静态方法，供 SDamage 调用
```

#### Trail 粒子配置（代码生成，参照 SElementalVisual 模式）

| 元素 | 方向 | 颜色 | 数量 | 生命周期 | 特征 |
|------|------|------|------|----------|------|
| FIRE | 向后（子弹飞行反方向） | 橙红渐变 | 6-8 | 0.4s | 缩小消散 |
| WET | 向后 | 蓝青色 | 4-6 | 0.5s | 水滴扩散 |
| COLD | 向后+随机 | 冰蓝白色 | 5-7 | 0.6s | 冰晶闪烁 |
| ELECTRIC | 随机闪烁 | 亮黄白色 | 3-5 | 0.2s | 高爆发性 |

**Trail 实现关键点**：
- GPUParticles2D 挂载为子弹 Entity 子节点（`local_coords = false`）
- 每帧同步粒子位置到子弹 `CTransform.position`，但粒子 `local_coords = false` + `emission_shape = SPHERE` + 小半径，产生拖尾效果
- 或者更优方案：使用 `local_coords = true` 让粒子自然留在原位形成拖尾（但需要子弹 Entity 本身跟随位置更新，已有 SRenderView/SCollision 做这件事）
- **推荐方案**：`local_coords = false`，粒子 position 跟随子弹，但通过短生命周期+重力产生拖尾错觉

#### Impact 粒子配置（一次性爆发）

| 元素 | 方向 | 颜色 | 数量 | 生命周期 | 特征 |
|------|------|------|------|----------|------|
| FIRE | 全方向 | 橙红 | 12 | 0.5s | 火花爆发 |
| WET | 全方向+向下 | 蓝青 | 10 | 0.6s | 水花飞溅 |
| COLD | 全方向 | 冰蓝白 | 10 | 0.7s | 冰晶碎裂 |
| ELECTRIC | 随机闪烁 | 黄白 | 8 | 0.3s | 电弧扩散 |

**Impact 实现关键点**：
- 使用 CPUParticles2D（一次性爆发，参照 `s_dead.gd:_spawn_debris` 模式）
- `one_shot = true, explosiveness = 1.0`
- 添加到 `ECS.world`（而非实体），确保子弹被移除后粒子仍可存活
- `finished` 信号连接 `queue_free` 自清理

### 4. SDamage 修改 — 触发命中 VFX

在 `_process_bullet_collision()` 中，`ECS.world.remove_entity(bullet_entity)` 之前调用：

```gdscript
# 触发命中 VFX
if bullet and bullet.element_type >= 0:
    SBulletVfx.spawn_impact(bullet_transform.position, bullet.element_type)
```

---

## 架构约束

### 涉及的 AGENTS.md 文件
- `gol-project/AGENTS.md` — ECS 架构、命名规范、代码风格
- `gol-project/scripts/components/AGENTS.md` — Component 纯数据约束
- `gol-project/scripts/systems/AGENTS.md` — System 分组和 query 模式
- `gol-project/tests/AGENTS.md` — 三层测试架构

### 引用的架构模式
- **ECS 数据流**：System → Component → ViewModel → View（VFX 属于 View 层）
- **Render group 系统**：`SBulletVfx` 放在 render group，在 `SRenderView` 和 `SAnimation` 之后处理
- **_views Dictionary 模式**：参照 `SElementalVisual`、`SRenderView`、`SAreaEffectModifierRender` 的实例缓存模式
- **component_removed 信号**：用于清理视图数据，参照 `SElementalVisual._on_component_removed()`
- **CPUParticles2D 一次性爆发**：参照 `s_dead.gd:_spawn_debris()` 模式
- **GPUParticles2D 持续发射**：参照 `s_elemental_visual.gd` 模式

### 文件归属层级
- 新 component 字段：`scripts/components/c_bullet.gd`（修改）
- 新 system：`scripts/systems/s_bullet_vfx.gd`（新建）
- 修改 system：`scripts/systems/s_fire_bullet.gd`、`scripts/systems/s_damage.gd`
- 单元测试：`tests/unit/system/test_bullet_vfx.gd`（新建）
- 集成测试：`tests/integration/test_bullet_vfx.gd`（新建）

### 测试模式
- **单元测试**（`extends GdUnitTestSuite`）：测试 `SBulletVfx` 内部方法（trail 创建、impact 参数、清理逻辑）
- **集成测试**（`extends SceneConfig`）：验证子弹飞行时出现尾迹粒子、命中时出现爆发粒子

---

## 测试契约

### 单元测试（`tests/unit/system/test_bullet_vfx.gd`）

| 测试名 | 验证内容 |
|--------|----------|
| `test_create_fire_trail_creates_gpu_particles` | 为 fire 子弹创建 trail 粒子，验证 `_trails` 字典有记录 |
| `test_create_wet_trail_creates_gpu_particles` | 为 wet 子弹创建 trail 粒子 |
| `test_no_element_no_trail` | element_type = -1 的子弹不创建 trail |
| `test_remove_trail_on_entity_removal` | 模拟 component_removed 信号，验证清理逻辑 |
| `test_spawn_impact_creates_cpu_particles` | `spawn_impact()` 创建 CPUParticles2D 并挂载到 ECS.world |
| `test_spawn_impact_no_element_does_nothing` | element_type = -1 时不创建 impact |
| `test_element_type_on_bullet_default` | `CBullet.element_type` 默认值为 -1 |
| `test_element_type_settable` | `CBullet.element_type` 可以被设置和读取 |

### 集成测试（`tests/integration/test_bullet_vfx.gd`）

| 测试名 | 验证内容 |
|--------|----------|
| `test_elemental_bullet_has_trail` | 射击者带 CElementalAttack → 发射的子弹 entity 有子节点 GPUParticles2D |
| `test_normal_bullet_no_trail` | 无元素射击者 → 子弹无 trail 粒子子节点 |
| `test_impact_on_hit` | 子弹命中目标 → 命中位置出现 CPUParticles2D（通过 world 子节点检查） |

---

## 风险点

1. **Trail 粒子位置同步**：子弹 Entity 的 position 每帧由 `SMove` 更新（`CMovement` → `CTransform`），SCollision 和 SRenderView 各自同步 Area2D 和 Sprite2D 位置。SBulletVfx 的 GPUParticles2D 如果作为 Entity 子节点，需要 `local_coords = false` 并手动同步 `global_position`，否则不会跟随。或者使用 `local_coords = true` 让粒子留在原地形成拖尾效果——**后者更自然，但需要验证 Entity 节点自身是否移动**。
   - **缓解方案**：使用 `local_coords = false`，每帧同步 GPUParticles2D 的 global_position 到 CTransform.position。与 SElementalVisual 的 `_update_view` 同步模式一致。

2. **Impact 粒子挂在 ECS.world**：参照 `s_dead.gd:_spawn_debris()` 模式，使用 `ECS.world.add_child(particles)`。但 SBulletVfx 是 render group 系统，需确认可以访问 `ECS.world`。
   - **缓解方案**：`spawn_impact()` 为 static 方法或直接使用 `get_tree().current_scene`（World 继承自 Node）。参照 s_dead.gd 使用 `ECS.world`，这应该是可访问的。

3. **元素类型传递时机**：`SFireBullet` 在 `gameplay` group，`SBulletVfx` 在 `render` group。按照处理顺序，gameplay 先于 render，所以 `element_type` 在 VFX 系统查询时已经设置好。
   - **结论**：无风险，group 处理顺序保证正确。

4. **普通子弹（无元素）兼容性**：`element_type = -1`（默认值）的子弹不应产生任何 VFX。
   - **缓解方案**：SBulletVfx.query 只处理 `element_type >= 0` 的子弹，或在 process 中跳过。

5. **性能考量**：大量子弹同时飞行时的粒子数量。每个子弹 6-8 个粒子，假设同时 20 颗子弹 = ~160 个粒子。GPUParticles2D 的性能开销较低。
   - **结论**：可接受，但粒子参数应保守（少量、短生命周期）。

---

## 建议的实现步骤

### Step 1: 扩展 CBullet 组件
- **文件**：`scripts/components/c_bullet.gd`
- **操作**：新增 `@export var element_type: int = -1`
- **影响**：无破坏性，默认值 -1 表示无元素

### Step 2: 修改 SFireBullet 传递元素类型
- **文件**：`scripts/systems/s_fire_bullet.gd`
- **操作**：在 `_create_bullet()` 中，创建子弹后，如果射击者有 `CElementalAttack`，拷贝 `element_type` 到子弹的 `CBullet`
- **前置依赖**：Step 1
- **注意**：需要在文件顶部 preload `CElementalAttack`（参照 `s_damage.gd` 的 `const COMPONENT_ELEMENTAL_ATTACK = preload(...)` 模式）

### Step 3: 创建 SBulletVfx 系统
- **文件**：`scripts/systems/s_bullet_vfx.gd`（新建）
- **操作**：
  1. 声明 `class_name SBulletVfx extends System`
  2. `_ready()` 设置 `group = "render"`
  3. `query()` 返回 `q.with_all([CBullet, CTransform]).with_none([CDead])`
  4. 实现 `_create_trail(entity, bullet, transform)` — 根据 `element_type` 创建 GPUParticles2D
  5. 实现 4 种元素的 trail 配置方法（参照 `s_elemental_visual.gd` 的 `_setup_*_particles` 模式）
  6. 实现 `_update_trails()` — 同步粒子位置到子弹位置
  7. 实现 `_cleanup_trails()` — 清理已移除实体的 trail 数据
  8. 实现 `static func spawn_impact(position: Vector2, element_type: int)` — 创建 CPUParticles2D 命中效果
  9. 实现 4 种元素的 impact 配置
- **前置依赖**：Step 1

### Step 4: 修改 SDamage 触发命中 VFX
- **文件**：`scripts/systems/s_damage.gd`
- **操作**：在 `_process_bullet_collision()` 中，在 `ECS.world.remove_entity(bullet_entity)` 之前，如果 `bullet.element_type >= 0`，调用 `SBulletVfx.spawn_impact(bullet_transform.position, bullet.element_type)`
- **前置依赖**：Step 3
- **注意**：需要在文件顶部 const 或 preload 引用 SBulletVfx

### Step 5: 单元测试
- **文件**：`tests/unit/system/test_bullet_vfx.gd`（新建）
- **操作**：实现测试契约中列出的 8 个单元测试
- **前置依赖**：Step 1, 3

### Step 6: 集成测试
- **文件**：`tests/integration/test_bullet_vfx.gd`（新建）
- **操作**：实现测试契约中列出的 3 个集成测试
- **前置依赖**：Step 2, 3, 4

### Step 7: 更新 AGENTS.md 文档
- **文件**：`scripts/components/AGENTS.md` — 在 Combat 表中更新 CBullet 描述，加入 element_type
- **文件**：`scripts/systems/AGENTS.md` — 在 Render Group 表中新增 SBulletVfx 条目

---

## 参考代码路径

| 用途 | 文件路径 |
|------|----------|
| 子弹组件 | `scripts/components/c_bullet.gd` |
| 子弹 recipe | `resources/recipes/bullet_normal.tres` |
| 子弹发射系统 | `scripts/systems/s_fire_bullet.gd` |
| 伤害/碰撞系统 | `scripts/systems/s_damage.gd` |
| 子弹生命周期 | `scripts/systems/s_life.gd` |
| 元素攻击组件 | `scripts/components/c_elemental_attack.gd` |
| 元素视觉系统（参考） | `scripts/systems/s_elemental_visual.gd` |
| 死亡粒子（参考） | `scripts/systems/s_dead.gd:186-208` |
| 精灵渲染系统 | `scripts/systems/s_render_view.gd` |
| 元素工具类 | `scripts/utils/elemental_utils.gd` |
| 区域效果渲染系统（参考） | `scripts/systems/s_area_effect_modifier_render.gd` |
| 武器组件 | `scripts/components/c_weapon.gd` |
| 元素武器 recipe | `resources/recipes/weapon_fire.tres` 等 |
| 单元测试参考 | `tests/unit/system/test_area_effect_modifier_render.gd` |
| 测试框架指南 | `tests/AGENTS.md` |
