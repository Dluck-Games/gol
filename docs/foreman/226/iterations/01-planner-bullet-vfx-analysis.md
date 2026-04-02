# Issue #226 — 元素子弹 VFX 特效：初始分析

## 需求分析

### Issue 概要
为元素子弹（FIRE/WET/COLD/ELECTRIC）添加 VFX 特效，覆盖两个阶段：
1. **飞行轨迹**：子弹在飞行过程中展示元素粒子拖尾
2. **命中表现**：子弹命中目标时展示元素粒子爆发

### 当前状态
- **子弹无元素信息**：`CBullet` 仅有 `damage: float` 和 `owner_entity: Entity`，所有武器共用 `bullet_normal.tres`
- **元素来源为发射者**：`SDamage._apply_bullet_effects()` 从 `bullet.owner_entity` 读取 `CElementalAttack`，子弹本身不知道自己携带什么元素
- **无子弹 VFX**：子弹由 `SRenderView` 渲染为普通 `Sprite2D`（`bullet_normal_12x.png`），无拖尾、无元素着色
- **命中特效仅有通用 hit_flash**：`SDamage._play_hit_blink()` 使用 `hit_flash.tres` shader 做白色闪白+溶解，无元素区分

### 设计决策

#### 决策 1：子弹如何携带元素信息 → 选项 A（推荐）
**在 `CBullet` 新增 `element_type` 字段，`SFireBullet` 创建时从发射者复制。**

理由：
- 解耦子弹与发射者生命周期（`owner_entity` 可能已失效）
- 新系统直接查询子弹组件即可，无需间接查询发射者
- 非 元素武器（手枪、步枪）的子弹 `element_type = -1`，VFX 系统自动跳过，零影响
- 与 ECS 数据驱动原则一致：组件携带自身所需数据

#### 决策 2：命中特效 → 需要额外元素粒子爆发
Issue 明确要求「命中表现」。当前 `hit_flash` 是通用的白色闪白效果，不含元素信息。需要：
- 保留现有 `hit_flash` shader（不改动）
- 在命中点生成 `one_shot` 粒子爆发，颜色和形态随元素类型变化
- 粒子为自清理型（`finished` 信号触发 `queue_free`），不影响已有逻辑

#### 决策 3：子弹配方 → 继续共用 `bullet_normal`
不需要为 4 种元素创建独立配方。元素信息通过 `CBullet.element_type` 运行时字段传递，配方保持单一 `bullet_normal.tres`。

---

## 影响面分析

### 直接修改文件

| # | 文件路径 | 修改内容 | 风险 |
|---|---------|---------|------|
| 1 | `scripts/components/c_bullet.gd` | 新增 `element_type: int = -1` 字段 | 低 — 新增字段，默认值不改变现有行为 |
| 2 | `scripts/systems/s_fire_bullet.gd` | `_create_bullet()` 中从发射者 `CElementalAttack` 复制 `element_type` 到子弹 | 低 — 仅在发射者有元素攻击时设置 |
| 3 | `scripts/systems/s_damage.gd` | `_process_bullet_collision()` 中命中时生成元素粒子爆发 | 中 — 需在 `remove_entity` 之前插入粒子生成逻辑 |

### 新增文件

| # | 文件路径 | 内容 |
|---|---------|------|
| 1 | `scripts/systems/s_bullet_vfx.gd` | `SBulletVFX` 系统（render 组），飞行拖尾粒子 |

### 间接影响文件

| # | 文件路径 | 影响方式 |
|---|---------|---------|
| 1 | `scripts/systems/s_render_view.gd` | 已有代码调用 `ELEMENTAL_UTILS.apply_elemental_glow(sprite, parent)`，但子弹无 `CElementalAffliction`，不影响。新增 VFX 不改变此路径 |
| 2 | `scripts/systems/s_elemental_visual.gd` | 参考实现模式，不修改 |
| 3 | `scripts/utils/elemental_utils.gd` | 可能复用颜色常量（`FIRE_VISUAL_COLOR` 等），不修改 |
| 4 | `resources/recipes/bullet_normal.tres` | 不修改 — 元素信息通过运行时字段传递 |

### 不受影响的文件
- `resources/recipes/weapon_fire.tres` 等 4 个元素武器配方 — 不修改
- `resources/recipes/weapon_pistol.tres`、`weapon_rifle.tres` — 不修改
- `scripts/systems/s_life.gd` — 子弹生命周期不变
- `scripts/systems/s_animation.gd` — 子弹无 `CAnimation` 组件，不涉及

---

## 实现方案

### 1. CBullet 新增 element_type 字段

**文件**: `scripts/components/c_bullet.gd`

```
新增字段:
var element_type: int = -1  # CElementalAttack.ElementType 枚举值，-1 = 无元素
```

- 默认值 `-1` 确保非元素武器子弹不受影响
- 值为 `CElementalAttack.ElementType.FIRE/WET/COLD/ELECTRIC`（0/1/2/3）

### 2. SFireBullet 创建时复制元素信息

**文件**: `scripts/systems/s_fire_bullet.gd`，`_create_bullet()` 方法（第 113-135 行）

在现有 `bullet_comp.owner_entity = shooter` 之后，新增：

```
if bullet_comp and shooter.has_component(CElementalAttack):
    var attack: CElementalAttack = shooter.get_component(CElementalAttack)
    bullet_comp.element_type = attack.element_type
```

需要在文件顶部新增 preload：
```
const COMPONENT_ELEMENTAL_ATTACK = preload("res://scripts/components/c_elemental_attack.gd")
```

### 3. 新建 SBulletVFX 系统（飞行拖尾）

**文件**: `scripts/systems/s_bullet_vfx.gd`（新建）

**系统设计**:
- `group = "render"`
- `query()`: `with_all([CBullet, CTransform])`
- 遵循 `SElementalVisual` 的代码生成 GPUParticles2D 模式

**核心逻辑**:
1. 对每个子弹实体，检查 `bullet.element_type >= 0`
2. 如果有效，创建/更新拖尾粒子系统
3. 粒子使用 `local_coords = false`（世界坐标），使粒子留在发射位置形成拖尾
4. 每帧同步粒子节点位置到子弹 `CTransform.position`
5. 子弹被移除时（`component_removed` 信号），清理粒子节点

**4 种元素拖尾粒子设计**:

| 元素 | 颜色 | 行为 | 参数参考 |
|------|------|------|---------|
| FIRE | 橙红渐变 `Color(1.0, 0.6, 0.1)` → `Color(0.3, 0.05, 0.0)` | 余烬向后飘散，轻微上升 | amount=8, lifetime=0.4, scale 1.5-3.0 |
| WET | 蓝青 `Color(0.4, 0.8, 1.0)` → `Color(0.2, 0.5, 0.8)` | 水滴向后飞溅 | amount=6, lifetime=0.3, scale 1.0-2.0 |
| COLD | 冰蓝 `Color(0.8, 0.95, 1.0)` → `Color(1.0, 1.0, 1.0)` | 冰晶缓慢飘落 | amount=6, lifetime=0.5, scale 1.0-2.5 |
| ELECTRIC | 亮黄 `Color(1.0, 1.0, 0.4)` → `Color(1.0, 0.8, 0.0)` | 短暂火花闪烁 | amount=4, lifetime=0.15, scale 1.0-1.5 |

**视图数据结构**（与 `SElementalVisual` 一致）:
```
_views[entity_instance_id] = {
    "root": Node2D,         # 粒子容器节点
    "particles": GPUParticles2D,  # 拖尾粒子
}
```

**清理**: 监听 `entity.component_removed` 信号，当 `CBullet` 或 `CTransform` 被移除时清理视图。同时用 `_cleanup_stale_views()` 模式（参考 `SAreaEffectModifierRender`）处理实体被直接 remove 的情况。

### 4. SDamage 命中粒子爆发

**文件**: `scripts/systems/s_damage.gd`，`_process_bullet_collision()` 方法（第 60-105 行）

在 `ECS.world.remove_entity(bullet_entity)`（第 105 行）之前，新增命中粒子生成：

```
# 生成元素命中粒子爆发
if bullet and bullet.element_type >= 0:
    _spawn_elemental_hit_particles(bullet_transform.position, bullet.element_type)
```

新增 `_spawn_elemental_hit_particles()` 方法：
- 参数: `position: Vector2`, `element_type: int`
- 在命中位置创建 `GPUParticles2D`
- 设置 `one_shot = true`, `emitting = true`
- 粒子 360° 爆发散射，短暂寿命后消失
- 监听 `finished` 信号执行 `queue_free()` 自清理
- 将粒子节点添加到 `get_tree().current_scene`（而非实体子节点，因为实体即将被移除）

**4 种元素命中粒子设计**:

| 元素 | 颜色 | 行为 | 参数 |
|------|------|------|------|
| FIRE | 橙红 | 火花向四周爆散 | amount=16, lifetime=0.5, spread=180°, velocity 40-80 |
| WET | 蓝青 | 水花溅射 | amount=12, lifetime=0.4, spread=160°, velocity 30-60 |
| COLD | 冰白 | 冰晶碎裂四散 | amount=10, lifetime=0.6, spread=180°, velocity 20-50 |
| ELECTRIC | 亮黄 | 电弧短促闪烁 | amount=20, lifetime=0.2, spread=180°, velocity 50-100 |

需要在文件顶部新增 preload：
```
const COMPONENT_ELEMENTAL_ATTACK = preload("res://scripts/components/c_elemental_attack.gd")
```
（注意：`SDamage` 已有此 preload，无需重复）

### 5. 粒子工具复用

`SElementalVisual` 中的粒子设置函数（`_setup_fire_particles` 等）是私有方法且包含位置偏移（`position = Vector2(0, -8)`），不适合直接复用。

**方案**: `SBulletVFX` 和 `SDamage` 中的粒子配置各自独立实现，参数参考 `SElementalVisual` 的风格（颜色、大小范围），但针对子弹场景调整（更短寿命、更少粒子数、世界坐标）。这避免了 `SElementalVisual` 方法不适用的耦合。

颜色常量可从 `ElementalUtils` 复用：`FIRE_VISUAL_COLOR`, `WET_VISUAL_COLOR`, `COLD_VISUAL_COLOR`, `ELECTRIC_VISUAL_COLOR`。

---

## 架构约束

### 涉及的 AGENTS.md 文件
- `gol-project/AGENTS.md` — ECS 架构、系统分组、VFS 工作流
- `scripts/systems/AGENTS.md` — 系统模板、分组规则（SBulletVFX 归 render 组）
- `scripts/components/AGENTS.md` — 组件定义规范（纯数据，无逻辑）
- `tests/AGENTS.md` — 测试分层（单元测试用 GdUnitTestSuite，集成测试用 SceneConfig）

### 引用的架构模式
- **ECS 数据驱动**: 组件携带数据，系统处理逻辑。`CBullet.element_type` 遵循此模式
- **代码生成 VFX**: 所有粒子效果通过 `GPUParticles2D` + `ParticleProcessMaterial` 代码创建，不使用 .tscn 场景文件。参考 `SElementalVisual`、`SAreaEffectModifierRender`
- **Render 系统模式**: `group = "render"`，维护 `_views: Dictionary`，监听 `component_removed` 信号清理
- **系统自动发现**: `GOLWorld._load_all_systems()` 从 `res://scripts/systems/` 自动加载，新系统文件放此目录即可

### 文件归属层级
- `scripts/components/c_bullet.gd` — components 层
- `scripts/systems/s_fire_bullet.gd` — systems 层 (gameplay 组)
- `scripts/systems/s_damage.gd` — systems 层 (gameplay 组)
- `scripts/systems/s_bullet_vfx.gd` — systems 层 (render 组，**新建**)

### 测试模式
- **集成测试** (`extends SceneConfig`): 适合测试「元素武器发射 → 子弹携带 element_type → 子弹被移除 → 粒子已清理」的完整流程
- **单元测试** (`extends GdUnitTestSuite`): 适合测试 `CBullet.element_type` 字段默认值、`SFireBullet` 复制逻辑
- 参考 `test_bullet_flight.gd`（集成测试模式）和 `test_flow_elemental_status_scene.gd`（元素流程测试模式）

---

## 测试契约

### 测试 1: CBullet element_type 默认值（单元测试）
- **文件**: `tests/unit/system/test_bullet_vfx.gd`（新建）
- **验证**: 新建 `CBullet` 实例，`element_type` 默认为 `-1`
- **断言**: `assert_equal(bullet.element_type, -1)`

### 测试 2: SFireBullet 复制元素类型（单元测试）
- **文件**: `tests/unit/system/test_bullet_vfx.gd`（新建，同文件）
- **验证**: 模拟有 `CElementalAttack` 的发射者，调用 `_create_bullet` 后子弹 `element_type` 正确
- **前置**: 需要 mock Entity 和相关组件
- **断言**: 子弹 `element_type == CElementalAttack.ElementType.FIRE`

### 测试 3: 元素子弹飞行拖尾 VFX（集成测试）
- **文件**: `tests/integration/test_bullet_vfx.gd`（新建）
- **系统列表**: `s_move.gd`, `s_fire_bullet.gd`, `s_life.gd`, `s_bullet_vfx.gd`
- **实体**: 使用 `enemy_raider` + `CWeapon(bullet_recipe_id=bullet_normal)` + `CElementalAttack(element_type=FIRE)`
- **验证步骤**:
  1. 创建元素武器敌人，设置 `time_amount_before_last_fire` 使其立即开火
  2. 运行数帧后找到子弹实体
  3. 验证 `bullet.element_type == CElementalAttack.ElementType.FIRE`
  4. 验证子弹实体下存在 `GPUParticles2D` 子节点（拖尾粒子）
  5. 验证粒子正在发射（`emitting == true`）

### 测试 4: 非元素武器无 VFX（集成测试）
- **文件**: `tests/integration/test_bullet_vfx.gd`（新建，同文件或新 config）
- **验证**: 普通手枪发射的子弹 `element_type == -1`，无粒子子节点
- **断言**: `bullet.element_type == -1`

### 测试 5: 子弹销毁后粒子清理（集成测试）
- **文件**: `tests/integration/test_bullet_vfx.gd`（新建）
- **验证**: 子弹 lifetime 到期被移除后，粒子节点也被清理
- **前置**: 设置较短的子弹 lifetime
- **断言**: 等待足够帧数后，粒子节点不再存在

### 测试 6: 命中粒子爆发（集成测试）
- **文件**: `tests/integration/test_bullet_hit_vfx.gd`（新建）
- **系统列表**: `s_move.gd`, `s_fire_bullet.gd`, `s_life.gd`, `s_damage.gd`, `s_collision.gd`
- **验证**: 元素子弹命中目标后，命中位置生成 `GPUParticles2D`（one_shot）
- **前置**: 设置发射者和目标重叠位置，确保命中
- **断言**: world 中存在游离的 `GPUParticles2D` 节点

---

## 风险点

### 风险 1: 粒子性能
- **描述**: 每颗子弹持续发射粒子，高频射击时粒子数可能累积
- **缓解**: 子弹拖尾使用低粒子数（4-8 个）和短寿命（0.15-0.5s）。命中粒子为 one_shot 且自清理
- **监控**: 测试中观察多子弹场景的帧率

### 风险 2: SDamage 命中粒子挂在 scene tree 根节点
- **描述**: `_spawn_elemental_hit_particles()` 将粒子添加到 `get_tree().current_scene`，如果场景切换可能导致残留
- **缓解**: one_shot 粒子寿命极短（0.2-0.6s），finished 信号自动 queue_free，实际影响极小

### 风险 3: SBulletVFX 视图清理时序
- **描述**: 子弹可能通过 `ECS.world.remove_entity()` 直接移除，不走 `remove_component` 流程，导致 `component_removed` 信号不触发
- **缓解**: 采用 `SAreaEffectModifierRender` 的 `_cleanup_stale_views()` 模式——在每帧 `process()` 开头遍历当前活跃实体，清除 `_views` 中已不存在的条目

### 风险 4: SDamage 已有 COMPONENT_ELEMENTAL_ATTACK preload
- **描述**: SDamage 文件顶部已有 `const COMPONENT_ELEMENTAL_ATTACK = preload(...)` 声明，新增代码可直接使用
- **缓解**: 确认无需重复声明即可编译通过

---

## 建议的实现步骤

### 步骤 1: 修改 CBullet 组件
- **文件**: `scripts/components/c_bullet.gd`
- **内容**: 新增 `var element_type: int = -1`
- **验证**: 运行现有 `test_bullet_flight` 集成测试确认不破坏

### 步骤 2: 修改 SFireBullet 创建逻辑
- **文件**: `scripts/systems/s_fire_bullet.gd`
- **内容**:
  - 顶部新增 `const COMPONENT_ELEMENTAL_ATTACK = preload("res://scripts/components/c_elemental_attack.gd")`
  - `_create_bullet()` 中新增元素类型复制逻辑
- **验证**: 运行现有 `test_bullet_flight` 确认非元素武器不受影响

### 步骤 3: 创建 SBulletVFX 系统（飞行拖尾）
- **文件**: `scripts/systems/s_bullet_vfx.gd`（新建）
- **内容**:
  - class_name `SBulletVFX`, extends `System`, group = `"render"`
  - query: `CBullet` + `CTransform`
  - 实现 4 种元素的拖尾粒子配置方法
  - 实现 `_views` 字典、创建/更新/清理流程
  - 实现 `_cleanup_stale_views()` 防护
- **参考**: `SElementalVisual`（粒子模式）、`SAreaEffectModifierRender`（清理模式）

### 步骤 4: 修改 SDamage 添加命中粒子
- **文件**: `scripts/systems/s_damage.gd`
- **内容**:
  - 新增 `_spawn_elemental_hit_particles(position, element_type)` 方法
  - 在 `_process_bullet_collision()` 的 `remove_entity` 之前调用
  - 实现 4 种元素的命中爆发粒子配置
- **验证**: 运行现有 `test_combat` 集成测试确认不破坏

### 步骤 5: 编写测试
- **单元测试**: `tests/unit/system/test_bullet_vfx.gd`
  - CBullet element_type 默认值
  - SFireBullet 元素复制逻辑
- **集成测试**: `tests/integration/test_bullet_vfx.gd`
  - 元素子弹携带 element_type
  - 元素子弹有拖尾粒子
  - 非元素子弹无 VFX
  - 子弹销毁后粒子清理
- **集成测试**: `tests/integration/test_bullet_hit_vfx.gd`
  - 命中粒子爆发验证

### 步骤 6: 更新 systems/AGENTS.md
- **文件**: `scripts/systems/AGENTS.md`
- **内容**: 在 Render Group 表格中新增 `s_bullet_vfx.gd | SBulletVFX | CBullet, CTransform | 元素子弹飞行拖尾粒子`

---

## 附录：关键文件路径索引

| 文件 | 路径 | 作用 |
|------|------|------|
| CBullet 组件 | `scripts/components/c_bullet.gd` | 子弹数据（需修改） |
| CElementalAttack 组件 | `scripts/components/c_elemental_attack.gd` | ElementType 枚举定义 |
| CWeapon 组件 | `scripts/components/c_weapon.gd` | 武器数据 |
| SFireBullet | `scripts/systems/s_fire_bullet.gd` | 子弹创建（需修改） |
| SDamage | `scripts/systems/s_damage.gd` | 碰撞/命中处理（需修改） |
| SElementalVisual | `scripts/systems/s_elemental_visual.gd` | VFX 参考实现 |
| SAreaEffectModifierRender | `scripts/systems/s_area_effect_modifier_render.gd` | 清理模式参考 |
| SRenderView | `scripts/systems/s_render_view.gd` | 现有子弹渲染 |
| ElementalUtils | `scripts/utils/elemental_utils.gd` | 颜色常量 |
| bullet_normal.tres | `resources/recipes/bullet_normal.tres` | 子弹配方（不修改） |
| weapon_fire.tres | `resources/recipes/weapon_fire.tres` | 元素武器参考 |
| SBulletVFX | `scripts/systems/s_bullet_vfx.gd` | 新建飞行拖尾系统 |
