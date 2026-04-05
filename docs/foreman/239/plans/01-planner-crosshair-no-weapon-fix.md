# 计划：#239 准心 Bug 修复

## 需求分析

**Issue**: `bug(crosshair): 玩家无远程武器时不应显示准心`

**现象**: 玩家不拥有 `CWeapon` 组件时（初始状态、死亡重生后、武器被击落），`CrosshairView` 仍然在鼠标位置渲染准心。

**期望行为**:
- 无 `CWeapon` → 准心完全隐藏
- 获得/捡起远程武器 → 准心重新出现
- 武器丢失（被击落等）→ 准心立即消失

---

## 根因确认

### 调用链追踪

```
CrosshairView._process() (每帧)
  └─ _try_bind_entity()
       └─ ECS.world.query.with_all([CPlayer, CAim])   ← 只查 CPlayer + CAim，无 CWeapon 检查
            └─ _view_model.bind_to_entity(entity)        ← 绑定到玩家实体
                 └─ aim_position.bind_component(CAim, "display_aim_position")
                      └─ spread_ratio.bind_component(CAim, "spread_ratio")

SCrosshair._process() (gameplay 组, 每帧)
  └─ query: with_all([CAim])                             ← 同样无 CWeapon 要求
       └─ _update_display_aim(entity, aim, delta)
            ├─ aim.display_aim_position = aim.aim_position  ← 第45行：无条件赋值！
            ├─ weapon = entity.get_component(CWeapon)
            └─ if weapon == null: return                     ← 第51行：早返回，未清除 display_aim_position

CrosshairView._on_draw()
  └─ 读取 _view_model.aim_position.value (即 CAim.display_aim_position)
       └─ 绘制4条准心线 + shock_effect                       ← 始终绘制
```

### 根因定位

**主根因在 `s_crosshair.gd:44-55` (`_update_display_aim`)**:

1. **第45行**: `aim.display_aim_position = aim.aim_position` 在检查 `CWeapon` 是否存在之前就无条件执行了
2. **第51行**: 当 `weapon == null` 时只重置了 `spread_*` 相关字段并 early return，但 `display_aim_position` 已被设为鼠标坐标
3. **结果**: `CAim.display_aim_position` 始终有有效屏幕坐标 → `CrosshairViewModel` 推送到 View → `_on_draw()` 无条件绘制

**次要根因在 `crosshair.gd:78-95` (`_try_bind_entity`)**:
- 绑定查询条件为 `with_all([CPlayer, CAim])`，不含 `CWeapon`
- 即使玩家没有武器，绑定也会成功

**同模式问题存在于 `s_track_location.gd:110-121`**:
- `STrackLocation` 的 `_update_display_aim` 有完全相同的无条件写 + weapon null 早返回模式
- 自动瞄准实体无武器时同样会污染 `display_aim_position`

---

## 影响面分析

### 直接修改文件（必改）

| 文件 | 改动内容 | 风险 |
|------|---------|------|
| `scripts/ui/crosshair.gd` | `_try_bind_entity()` 增加 `CWeapon` 条件 + `_on_draw()` 增加 visible 守卫 | 低 — UI 层逻辑变更 |
| `scripts/systems/s_crosshair.gd` | `_update_display_aim()` 中 weapon==null 时清除 `display_aim_position` | 低 — 已有 null check 框架 |

### 可选修改文件（建议同步修复）

| 文件 | 改动内容 | 风险 |
|------|---------|------|
| `scripts/systems/s_track_location.gd` | 同样的 `_update_display_aim` bug pattern | 低 — 与 s_crosshair 对称修改 |

### 间接关联文件（不需修改但需验证）

| 文件 | 关联方式 | 验证点 |
|------|---------|--------|
| `scripts/systems/s_dialogue.gd` | 通过 preload 引用 `crosshair.gd`，调用 `_set_crosshair_visible()` 切换可见性 | 对话框关闭后准心应正确恢复隐藏/显示状态 |
| `scripts/components/c_weapon.gd` | `CWeapon` 定义 — 不修改，仅引用 | — |
| `scripts/components/c_aim.gd` | `CAim` 组件定义 — 需确认字段语义 | — |
| `scripts/ui/crosshair_view_model.gd` | 数据绑定层 — 不需改动 | — |
| `resources/recipes/player.tres` | 玩家配方不含 CWeapon（预期行为） | — |
| `scripts/gameplay/ecs/authoring/authoring_player.gd` | 保证玩家有 CAim 但不保证有 CWeapon | — |
| `scripts/configs/config.gd` | `CWeapon` 在 `LOSABLE_COMPONENTS` 和 `DEATH_REMOVE_COMPONENTS` 中；`CAim` 同时在 `BASE_COMPONENTS` 中（重生恢复） | 确认配置一致性 |

### 重命名影响面（Optional Task）

若执行 `CWeapon → CShooterWeapon` 重命名：

| 类别 | 文件数 | 示例 |
|------|-------|------|
| Systems | 7 | s_crosshair, s_fire_bullet, s_electric_spread_conflict, s_cold_rate_conflict, s_track_location, s_damage, s_semantic_translation |
| GOAP Actions | 4 | attack_ranged, chase_target, flee, adjust_shoot_position |
| UI | 1 | view_hp_bar |
| Components | 1 | c_blueprint (注释), c_semantic_translation |
| Config | 1 | config.gd |
| Tests | ~20+ | test_fire_bullet, test_flow_component_drop_scene 等 |
| Resources/Recipes | 待确认 | 可能涉及 .tres 配方文件 |

**重命名影响约 35+ 文件，属于独立 task，不应阻塞主修复。**

---

## 实现方案

### 方案对比

| 维度 | 路径 A：绑定层拦截（推荐） | 路径 B：绘制层守卫 | 路径 C：System 层清除 |
|------|--------------------------|-------------------|--------------------|
| **修改位置** | `crosshair.gd:_try_bind_entity()` | `crosshair.gd:_on_draw()` | `s_crosshair.gd:_update_display_aim()` |
| **核心思路** | 绑定时要求 `CWeapon` 存在；无武器则 unbind | 绘制前检查 ViewModel 是否有合法数据 | weapon==null 时将 `display_aim_position` 置为无效值 |
| **防御深度** | 源头拦截，ViewModel 不收到脏数据 | 最后一道防线，数据已污染但不可见 | 数据层清洁，但依赖 System 的正确性 |
| **代码改动量** | 小（~10 行） | 极小（~3 行） | 小（~5 行） |
| **对 STrackLocation 影响** | 自然覆盖（绑定了才有数据） | 自然覆盖 | 需单独改 s_track_location |
| **对话系统兼容性** | 需验证 unbind/rebind 时序 | 天然兼容（visible 由 dialogue 控制） | 天然兼容 |
| **可测试性** | 好（bind/unbind 状态明确） | 一般（需截图或 mock draw） | 好（断言属性值） |

### 推荐：路径 A + C 双重防御

采用 **路径 A 为主、路径 C 为辅** 的组合策略：

#### 主修复：路径 A — 绑定层拦截

**文件**: `scripts/ui/crosshair.gd`

**改动 1**: 修改 `_try_bind_entity()` (第78-95行)

```gdscript
# 改前：
var entities: Array = ECS.world.query.with_all([CPlayer, CAim]).execute()

# 改后：
var entities: Array = ECS.world.query.with_all([CPlayer, CAim, CWeapon]).execute()
```

同时增加每帧重检逻辑——当前实现只在 `_bound_entity` 失效时才重新查询。如果玩家中途丢失武器（被击落），绑定不会更新。

**需要在 `_process()` 中增加武器存在性检查**：

```gdscript
func _process(_delta: float) -> void:
	_try_bind_entity()

	# 新增：如果已绑定但武器已丢失，解绑并隐藏
	if _bound_entity and is_instance_valid(_bound_entity):
		if not _bound_entity.has_component(CWeapon):
			_view_model.unbind()
			_bound_entity = null

	_draw_node.queue_redraw()
```

**改动 2**: 修改 `_on_draw()` (第44行)，增加 visible 守卫作为最终防线

```gdscript
func _on_draw() -> void:
	# 新增：无绑定实体时不绘制
	if _bound_entity == null:
		return

	# ... 原有绘制逻辑不变
```

#### 辅助修复：路径 C — System 层清洁

**文件**: `scripts/systems/s_crosshair.gd`

**改动**: 修改 `_update_display_aim()` (第44-55行)

```gdscript
func _update_display_aim(entity: Entity, aim: CAim, delta: float) -> void:
	var weapon: CWeapon = entity.get_component(CWeapon)
	var transform: CTransform = entity.get_component(CTransform)
	var viewport := entity.get_viewport()

	# 改动：将 display_aim_position 赋值移到 weapon check 之后
	if weapon == null or transform == null or viewport == null:
		aim.display_aim_position = Vector2(-99999, -99999)  # 新增：置为屏幕外无效坐标
		aim.spread_ratio = 0.0
		aim.spread_angle_degrees = 0.0
		aim.spread_target_angle_degrees = 0.0
		aim.spread_change_cooldown = 0.0
		return

	# 原有逻辑：weapon 存在时才设置有效的 display_aim_position
	aim.display_aim_position = aim.aim_position
	# ... 后续 spread 逻辑不变
```

#### 同步修复：STrackLocation

**文件**: `scripts/systems/s_track_location.gd`

**改动**: 对 `_update_display_aim` 应用与 `s_crosshair.gd` 相同的 pattern（将 `display_aim_position` 赋值移到 weapon null check 之后）。

---

## 架构约束

### 涉及的 AGENTS.md 文件

| 文件 | 关键规则 |
|------|---------|
| `gol/AGENTS.md` | VCS workflow：先 push 子模块，再更新主 repo 引用 |
| `gol-project/AGENTS.md` | MVVM 数据流：`System → Component → ViewModel → View`（单向）；组件是纯数据；命名规范 c_/s_/viewmodel_/View_ |
| `scripts/ui/AGENTS.md` | UI 层 MVVM 模式说明 |
| `scripts/systems/AGENTS.md` | System 自动发现、group 分组规则 |

### 引用的架构模式

- **MVVM 单向数据流**: `SCrosshair` 写入 `CAim.display_aim_position` → `CrosshairViewModel` 订阅 → `CrosshairView` 读取绘制
- **ECS Query 模式**: System 通过 `query().with_all(...)` 决定处理哪些实体
- **组件纯数据原则**: `CWeapon` / `CAim` 不含逻辑，判断逻辑放在 System 或 View 层

### 文件归属层级

| 文件 | 归属 | 修改权限 |
|------|------|---------|
| `scripts/ui/crosshair.gd` | UI View 层 | 可改 |
| `scripts/systems/s_crosshair.gd` | System 层 | 可改 |
| `scripts/systems/s_track_location.gd` | System 层 | 可改（建议同步修） |
| `scripts/components/c_weapon.gd` | Component 层 | 不改（纯数据） |
| `scripts/components/c_aim.gd` | Component 层 | 不改（纯数据） |
| `scripts/ui/crosshair_view_model.gd` | ViewModel 层 | 不改（绑定逻辑无需变动） |

### 测试模式

参考 AGENTS.md 定义的测试分层：
- **Unit tests** (`tests/unit/`): gdUnit4 `GdUnitTestSuite`，适合测试 `_try_bind_entity` 逻辑、`_update_display_aim` 的 weapon-null 分支
- **Integration tests** (`tests/integration/`): SceneConfig-based，加载真实 GOLWorld
- 当前 **无任何 crosshair 相关测试**，需要新建

---

## 测试契约

### 必须通过的测试场景

#### Unit Tests（新增文件: `tests/unit/ui/test_crosshair_view.gd`）

| # | 场景 | 输入 | 期望输出 |
|---|------|------|---------|
| T1 | 玩家有 CPlayer + CAim + CWeapon → 准心绑定成功 | Entity 含三个组件 | `_bound_entity != null`, `aim_position` 有有效值 |
| T2 | 玩家有 CPlayer + CAim 但无 CWeapon → 准心不绑定 | Entity 含两个组件 | `_bound_entity == null`, `_on_draw()` 不绘制 |
| T3 | 绑定后武器丢失（remove_component）→ 准心解绑 | 先 bind 再 remove CWeapon | `_bound_entity == null` |
| T4 | 解绑状态下 `_on_draw()` 不崩溃 | `_bound_entity == null` | 无异常，无绘制调用 |
| T5 | `_on_draw()` 正常绘制 | 有效 binding + 有效 ViewModel 数据 | 4条 line + 可选 shock_effect |

#### Unit Tests（新增/补充: `tests/unit/system/test_crosshair.gd`）

| # | 场景 | 输入 | 期望输出 |
|---|------|------|---------|
| T6 | `SCrosshair._update_display_aim()` 无 weapon → display_aim_position 为无效值 | Entity 无 CWeapon | `display_aim_position` 为屏外坐标或 zero |
| T7 | `SCrosshair._update_display_aim()` 有 weapon → display_aim_position 为有效鼠标坐标 | Entity 有 CWeapon | `display_aim_position` ≈ `aim_position` |
| T8 | `SCrosshair.query()` 返回条件含 CWeapon | — | query builder 包含 CWeapon |

#### Integration Test（可选增强）

| # | 场景 | 验证方式 |
|---|------|---------|
| T9 | 玩家初始生成（无武器）→ 准心不可见 | SceneConfig 加载玩家 → 断言 CrosshairView.visible == false 或无绘制 |
| T10 | 玩家拾取武器 → 准心出现 | 添加 CWeapon → 断言准心可见 |

### 测试契约通过标准

- **P0（必须）**: T1–T8 全部通过
- **P1（应该）**: T9-T10 通过（Integration）
- **回归验证**: 所有现有测试不受影响（特别是 `test_fire_bullet.gd` 等 CWeapon 相关测试）

---

## 风险点

### 高风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| **对话系统时序冲突** | `SDialogue` 通过 `CrosshairView.visible = false/true` 控制可见性；如果我们的修复在对话期间 unbind 了实体，对话结束后可能无法正确 rebind | 验证对话流程中 `_try_bind_entity()` 仍能正常 rebind；`_process()` 每帧调用保证了重试 |
| **武器切换/拾取帧延迟** | 玩家捡起武器的那一帧，`_try_bind_entity` 先执行（发现无武器 unbind），然后 System 才添加 CWeapon，导致准心闪烁一帧消失 | 风险极低——CanvasLayer queue_redraw 在同一帧末尾生效，且下一帧即可 rebind |

### 中风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| **STrackLocation 未同步修复** | AI 敌人自动瞄准时可能仍会污染 `display_aim_position`（如果敌人无武器但有 CAim） | 作为同一 PR 的同步修改，不影响主修复通过标准但应一并提交 |
| **无既有测试覆盖** | 无法通过回归测试保证不改坏现有行为 | 新建 P0 unit tests 作为修复的一部分 |

### 低风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| **CWeapon 重命名（optional）** | 影响面广 (~35+ 文件)，容易遗漏 | 作为独立 issue/task，不在本次修复范围内 |

---

## 建议的实现步骤

### Step 1: 修复 SCrosshair System 层（路径 C）
**文件**: `scripts/systems/s_crosshair.gd`
1. 将 `aim.display_aim_position = aim.aim_position` 从第45行移到 weapon null check 之后（约第56行）
2. 在 weapon == null 分支中，显式设置 `display_aim_position = Vector2(-99999, -99999)` （防御性编程）
3. 验证：无武器实体的 `display_aim_position` 不再被设为鼠标坐标

### Step 2: 修复 CrosshairView 绑定层（路径 A — 主修复）
**文件**: `scripts/ui/crosshair.gd`
1. 修改 `_try_bind_entity()` 第89行 query 条件：`with_all([CPlayer, CAim])` → `with_all([CPlayer, CAim, CWeapon])`
2. 在 `_process()` 中增加武器丢失检测：已绑定实体若无 `CWeapon` 则 unbind
3. 在 `_on_draw()` 开头增加 `_bound_entity == null` 守卫

### Step 3: 同步修复 STrackLocation
**文件**: `scripts/systems/s_track_location.gd`
1. 对 `_update_display_aim` 应用与 Step 1 相同的 pattern

### Step 4: 编写单元测试
**新文件**:
- `tests/unit/ui/test_crosshair_view.gd` — T1-T5
- `tests/unit/system/test_crosshair.gd` — T6-T8（如尚不存在）

### Step 5: 验证对话系统集成
**手动/集成测试**:
- 验证进入对话 → 准心隐藏 → 退出对话 → 准心根据武器状态正确恢复

### Step 6 (Optional): CWeapon → CShooterWeapon 重命名
- 作为独立 task 处理，不影响 Steps 1-5 的合入

### 提交策略
- Steps 1-4 合并为一个 commit（完整修复 + 测试）
- Step 3（STrackLocation）可作为同一个 commit 或紧随其后的 commit
- Step 6（重命名为独立 commit/PR）
