# Issue #198 计划：雷属性组件拾取/受击效果优化

> **日期**: 2026-04-05
> **状态**: 规划完成，待 coder 实现
> **Issue**: #198 — 优化雷属性组件拾取及受击效果逻辑设计

---

## 一、需求分析

### 1.1 问题描述（来自 Issue）

| 编号 | 问题 | 期望行为 | 现状行为 |
|------|------|----------|----------|
| P1 | 拾取雷武器后准星颤抖 | 仅对**敌人**造成伤害效果；玩家自身不应受散射惩罚影响准星稳定性 | `SElectricSpreadConflict` 对所有持有者无差别施加 +15 度 spread，导致准星抖动 |
| P2 | 受敌人雷攻击时仅扣血 | 受到 Electric affliction 时应有**准星干扰**效果（瞄准不稳定） | `SElementalAffliction._apply_tick_effect()` 的 Electric 分支只处理 `_queue_damage`（DoT 伤害），无瞄准干扰逻辑 |
| P3 | Tracker 与 Electric 的排斥关系未考虑 | Tracker（自动追踪）+ Electric（散射惩罚）同时存在时的交互应明确定义 | 两系统各自独立运行，无协调逻辑 |

### 1.2 设计意图推导

从现有代码结构推断原始设计意图：

- **Electric 武器的 +15° 散射**：作为"代价"机制——高伤害武器命中精度降低
- **Tracker 自动追踪**：作为补偿——自动锁定目标降低瞄准难度
- **CrosshairView 的 ELECTRIC_COLOR 渲染**：spread_ratio > 0.01 时显示闪电火花，说明设计上**预期**了 Electric 武器会影响准星视觉

**核心矛盾**：
- P1 表明"玩家拾取 Electric 后准星抖动是错误行为"——即 +15° spread 代价不应影响玩家（或至少不应以准星抖动形式表现）
- P2 表明"被敌人 Electric 命中后应有准星干扰"——即 Electric affliction 应对**受害者**造成瞄准扰动

**结论**：Electric 的瞄准干扰应是**被动 affliction 效果**（被击中时），而非**主动持有代价**（拾取武器时）。当前实现把两者搞反了。

### 1.3 明确需求定义

| 需求 | 具体行为 |
|------|----------|
| D1 | 玩家拾取 Electric 武器 → **不产生准星抖动**（移除或限制 SElectricSpreadConflict 对玩家的影响） |
| D2 | 玩家被 Electric 攻击命中（获得 CElementalAffliction[ELECTRIC]）→ **准星出现抖动/干扰**（新增 affliction-driven aim disturbance） |
| D3 | CTracker + Electric 武器共存时 → Tracker 追踪不受 Electric scatter 影响（或受影响的程度明确可控） |
| D4 | 敌方实体被 Electric 命中 → 保持现有 DoT + 传播行为不变 |

---

## 二、影响面分析

### 2.1 直接涉及文件

| 文件 | 角色 | 当前行为 | 需修改 |
|------|------|----------|--------|
| `scripts/systems/s_electric_spread_conflict.gd` | cost 系统：Electric 武器 +15° spread | 对所有 CWeapon 实体无条件生效 | **修改**：排除 CCamp=PLAYER 的实体 |
| `scripts/systems/s_elemental_affliction.gd` | gameplay 系统：元素状态 DoT | Electric 只做 `_queue_damage` | **修改**：Electric 分支增加 aim disturbance 逻辑 |
| `scripts/components/c_aim.gd` | 数据组件：瞄准位置/散布 | 有 `spread_ratio`、`spread_angle_degrees` 等字段 | 可能需扩展字段 |
| `scripts/systems/s_crosshair.gd` | gameplay 系统：鼠标准星 | 读 CWeapon.spread_degrees 计算 jitter | **可能修改**：增加 affliction 干扰源 |
| `scripts/systems/s_track_location.gd` | gameplay 系统：追踪准星 | 同 SCrosshair 逻辑的 `_update_display_aim` | **可能修改**：同步 affliction 干扰 |
| `scripts/ui/crosshair.gd` | View 层：准星渲染 | 根据 spread_ratio 做 electric 视觉 | 无需修改（已有 electric 渲染支持） |
| `scripts/configs/config.gd` | 配置常量 | `ELECTRIC_SPREAD_DEGREES=15`, `MAX_SPREAD_DEGREES=30` | **可能新增**：affliction 干扰参数 |

### 2.2 间接涉及文件

| 文件 | 影响 |
|------|------|
| `tests/unit/system/test_electric_spread_conflict.gd` | 现有测试验证"electric adds spread"，需更新断言 |
| `tests/unit/system/test_elemental_affliction_system.gd` | 新增 Electric aim disturbance 测试 |
| `tests/integration/flow/test_flow_composition_cost_scene.gd` | integration 场景包含 electric spread 测试 |

### 2.3 不涉及的文件

- `scripts/components/c_elemental_attack.gd` — 数据定义不变
- `scripts/components/c_elemental_affliction.gd` — 容器组件不变
- `scripts/utils/elemental_utils.gd` — apply_payload 逻辑不变
- `scripts/systems/s_damage.gd` — 命中时 apply_attack 流程不变
- `scripts/ui/crosshair_view_model.gd` — ViewModel 已有 spread_ratio 绑定

---

## 三、问题根因定位

### 3.1 P1 根因：SElectricSpreadConflict 无差别施放

**文件**: `scripts/systems/s_electric_spread_conflict.gd:26-30`

```gdscript
var elemental: CElementalAttack = entity.get_component(CElementalAttack)
if elemental and elemental.element_type == CElementalAttack.ElementType.ELECTRIC:
    weapon.spread_degrees = minf(
        weapon.base_spread_degrees + Config.ELECTRIC_SPREAD_DEGREES,
        Config.MAX_SPREAD_DEGREES
    )
```

**根因**: query 为 `q.with_all([CWeapon])`，匹配**所有**持武实体（包括玩家和敌人），且 process 内**无阵营判断**。玩家拾取 Electric 武器后立即受到 +15° spread 影响 → `SCrosshair._update_display_aim()` 或 `STrackLocation._update_display_aim()` 读取增大的 `weapon.spread_degrees` → 准星开始 jitter 抖动。

### 3.2 P2 根因：SElementalAffliction Electric 分支缺少非伤害效果

**文件**: `scripts/systems/s_elemental_affliction.gd:95-97`

```gdscript
COMPONENT_ELEMENTAL_ATTACK.ElementType.ELECTRIC:
    var damage_multiplier := WET_ELECTRIC_DAMAGE_MULTIPLIER if ...
    _queue_damage(entity, intensity * 6.0 * tick_interval * damage_multiplier)
```

**根因**: Electric 分支**只有** `_queue_damage`。对比 Cold 元素有完整的 movement modifier 系统（冻结减速），Electric 完全没有对瞄准系统的副作用。

**缺失路径**: 应在 `_apply_tick_effect` 的 Electric 分支中，向 CAim 组件写入干扰参数（类似 Cold 向 CMovement 写入减速参数的模式）。

### 3.3 P3 根因：两个独立系统无交叉感知

- `SElectricSpreadConflict` (group: `"cost"`) 在 group 1 执行
- `SCrosshair` / `STrackLocation` (group: `"gameplay"`) 在 group 1 执行
- `SElementalAffliction` (group: `"gameplay"`) 在 group 1 执行

三个系统互不知晓对方存在。当玩家同时拥有 CTracker + CWeapon(Electric) 时：
- STrackLocation 控制瞄准位置（自动追踪）
- SElectricSpreadConflict 放大武器 spread → STrackLocation 的 `_update_display_aim` 读到了更大的 spread_degrees → 追踪准星也抖动

**这不是 bug 而是设计空白**：需要明确定义"Tracker 是否免疫 Electric scatter"规则。

---

## 四、实现方案

### 4.1 方案总览

采用 **"持有不惩罚，受害才干扰"** 策略：

```
┌──────────────────────┬────────────────────────┬───────────────────────┐
│       行为           │     当前实现            │      修改后          │
├──────────────────────┼────────────────────────┼───────────────────────┤
│ 拾取 Electric 武器   │ +15° spread（全阵营）    │ +15° spread（仅敌方） │
│ 被 Electric 命中     │ 只有 DoT 伤害           │ DoT + 准星干扰         │
│ Tracker + Electric   │ 追踪也抖动             │ 追踪不抖动（可选配置） │
└──────────────────────┴────────────────────────┴───────────────────────┘
```

### 4.2 步骤一：修复 SElectricSpreadConflict — 排除玩家

**文件**: `scripts/systems/s_electric_spread_conflict.gd`

**改动**: 在 `_process_entity` 中增加阵营判断：

```gdscript
func _process_entity(entity: Entity, _delta: float) -> void:
	var weapon: CWeapon = entity.get_component(CWeapon)
	if not weapon:
		return

	# Lazy-capture base
	if weapon.base_spread_degrees < 0.0:
		weapon.base_spread_degrees = weapon.spread_degrees

	var elemental: CElementalAttack = entity.get_component(CElementalAttack)
	if elemental and elemental.element_type == CElementalAttack.ElementType.ELECTRIC:
		# [修改] 仅对非玩家阵营施加散射惩罚
		var camp: CCamp = entity.get_component(CCamp)
		if camp and camp.camp == CCamp.CampType.PLAYER:
			weapon.spread_degrees = weapon.base_spread_degrees  # 玩家不惩罚
		else:
			weapon.spread_degrees = minf(
				weapon.base_spread_degrees + Config.ELECTRIC_SPREAD_DEGREES,
				Config.MAX_SPREAD_DEGREES
			)
	else:
		weapon.spread_degrees = weapon.base_spread_degrees
```

**理由**:
- Electric 武器的散射代价保留给 AI 敌人使用（敌方的 Electric 武器命中率降低）
- 玩家拾取后体验流畅，不会自我惩罚
- 最小改动，只加一个 if 分支

### 4.3 步骤二：新增 Electric Affliction Aim Disturbance

**文件**: `scripts/systems/s_elemental_affliction.gd`

**改动**: 在 `_apply_tick_effect()` 的 Electric 分支中增加准星干扰写入：

```gdscript
COMPONENT_ELEMENTAL_ATTACK.ElementType.ELECTRIC:
    var damage_multiplier := WET_ELECTRIC_DAMAGE_MULTIPLIER if affliction.entries.has(COMPONENT_ELEMENTAL_ATTACK.ElementType.WET) else 1.0
    _queue_damage(entity, intensity * ELECTRIC_DAMAGE_PER_SECOND * tick_interval * damage_multiplier)
    # [新增] Electric affliction 对有 CAim 的实体造成准星干扰
    _apply_electric_aim_disturbance(entity, intensity, tick_interval)
```

新增私有方法：

```gdscript
const ELECTRIC_AIM_DISTURBANCE_BASE_DEGREES: float = 8.0   # 基础干扰角度
const ELECTRIC_AIM_DISTURBANCE_MAX_DEGREES: float = 20.0   # 最大干扰角度

func _apply_electric_aim_disturbance(entity: Entity, intensity: float, tick_interval: float) -> void:
    var aim: CAim = entity.get_component(CAim)
    if aim == null:
        return
    # 以 intensity 比例叠加干扰（类似 spread 但独立于武器）
    var disturbance_degrees := minf(
        intensity * ELECTRIC_AIM_DISTURBANCE_BASE_DEGREES,
        ELECTRIC_AIM_DISTURBANCE_MAX_DEGREES
    )
    # 通过 ObservableProperty 通知 ViewModel/View
    aim.electric_affliction_jitter = disturbance_degrees
```

**对应数据层改动** — `scripts/components/c_aim.gd`:

新增字段：

```gdscript
## Electric affliction 导致的准星干扰强度（0 = 无干扰）
var electric_affliction_jitter: float = 0.0:
    set(v):
        electric_affliction_jitter = v
        electric_affliction_jitter_observable.set_value(v)
var electric_affliction_jitter_observable: ObservableProperty = ObservableProperty.new(electric_affliction_jitter)
```

### 4.4 步骤三：准星系统消费 Aim Disturbance

**方案 A（推荐）— 在 SCrosshair 和 STrackLocation 中合并干扰源**

**文件**: `scripts/systems/s_crosshair.gd` — 修改 `_update_display_aim()`

在计算 `spread_degrees` 之后，将 `electric_affliction_jitter` 叠加到最终的 jitter 计算中：

```gdscript
# 现有：var spread_degrees: float = weapon.spread_degrees
# 修改为：
var total_jitter_degrees: float = weapon.spread_degrees
# 叠加 Electric affliction 干扰
var aim_comp: CAim = entity.get_component(CAim)
if aim_comp:
    total_jitter_degrees += aim_comp.electric_affliction_jitter

# 后续使用 total_jitter_degrees 替代 spread_degrees 进行 jitter 计算
```

注意：需要将 `aim.spread_ratio` 的计算基础从纯 weapon spread 改为包含 affliction 的总值，这样 CrosshairView 的电击渲染也会正确响应。

**文件**: `scripts/systems/s_track_location.gd` — 同步修改 `_update_display_aim()`

与 SCrosshair 相同的逻辑变更（两处 `_update_display_aim` 代码几乎相同，可后续提取公共方法但本次不做重构）。

### 4.5 步骤四：Affliction 清除时重置 Jitter

**文件**: `scripts/systems/s_elemental_affliction.gd` — 修改 `_clear_afflictions()`

```gdscript
func _clear_afflictions(entity: Entity, affliction: Variant) -> void:
    # ... existing cleanup ...
    # [新增] 重置准星干扰
    var aim: CAim = entity.get_component(CAim)
    if aim:
        aim.electric_affliction_jitter = 0.0
    # ... rest of cleanup ...
```

同时在 Electric entry 自然过期移除时（`_should_remove_entry` → `entries_changed`），也需要确保 jitter 被清除。这需要在 entries 擦除检测处添加清理逻辑。

### 4.6 关于 P3（Tracker + Electric 共存）的设计决策

**推荐决策**: Tracker 持有者**不完全免疫** Electric affliction jitter，但可以通过以下方式缓解：

1. **STrackLocation 中可选择性衰减**: 当 `entity.has_component(CTracker)` 时，将 `electric_affliction_jitter` 乘以 0.5（半衰减）
2. **理由**: Tracker 提供自动瞄准，即使有干扰也比手动抖动更容易接受；完全消除会削弱 Electric 敌人的威胁感

**替代方案（如 TL 决策不同）**: 完全免疫（CTracker 存在时忽略 `electric_affliction_jitter`）。只需在 STrackLocation 的 `_update_display_aim` 中跳过该值即可。

---

## 五、架构约束

### 5.1 涉及的 AGENTS.md 文件

| 文件 | 关键约束 |
|------|----------|
| `gol-project/AGENTS.md` | System group 顺序：cost → gameplay → render → physics；ECS data flow: System → Component → ViewModel → View |
| `gol-project/scripts/components/AGENTS.md` | Component 是 pure data；ObservableProperty setter pattern for UI；on_merge() 用于 pickup 行为 |
| `gol-project/scripts/systems/AGENTS.md` | System extends System, auto-discovered; group 必须在 `_ready()` 设置; Query with_all/with_any/with_none |
| `gol-project/scripts/gameplay/AGENTS.md` | Entity creation via ServiceContext.recipe(); MVVM binding via observable |

### 5.2 引用的架构模式

- **Cost System Pattern** (`SElectricSpreadConflict` 使用): lazy-capture base value, 每帧覆盖实际值，group=`"cost"` 在 gameplay 之前执行
- **Transient Marker Pattern**: CDamage 是瞬态标记，system 消费后移除
- **MVVM Observable Binding**: CAim 字段通过 ObservableProperty → ViewModel → View 链路传递

### 5.3 文件归属层级

| 文件 | 归属 |
|------|------|
| `scripts/systems/s_electric_spread_conflict.gd` | Cost 组 System |
| `scripts/systems/s_elemental_affliction.gd` | Gameplay 组 System |
| `scripts/systems/s_crosshair.gd` | Gameplay 组 System |
| `scripts/systems/s_track_location.gd` | Gameplay 组 System |
| `scripts/components/c_aim.gd` | Combat 组件 |
| `scripts/configs/config.gd` | 全局配置常量 |
| `scripts/ui/crosshair.gd` | UI View 层（不改） |

### 5.4 测试模式

- **Unit tests**: `extends GdUnitTestSuite`, `auto_free()` 管理生命周期, `assert_float/is_equal_approx` 数值断言
- **Integration tests**: `extends SceneConfig`, `systems()` 加载系统列表, `test_run()` 编排场景
- **测试目录**: `tests/unit/system/` for unit; `tests/integration/flow/` for integration

---

## 六、测试契约

### 6.1 单元测试

#### 测试文件 1: `test_electric_spread_conflict.gd`（修改现有）

| 测试名 | 验证内容 |
|--------|----------|
| `test_electric_adds_spread_for_enemy` | 敌方实体（CCamp=ENEMY）持有 Electric 武器 → spread 增加 15° |
| `test_no_spread_for_player` | **[新增]** 玩家实体（CCamp=PLAYER）持有 Electric 武器 → spread 不变（保持 base） |
| `test_spread_capped_at_max` | 敌方 base 20° + 15° = 35° → cap at MAX_SPREAD_DEGREES(30°) |
| `test_non_electric_no_spread` | 非 Electric 元素 → 无变化 |
| `test_player_without_camp_gets_spread` | **[边界]** 无 CCamp 组件的实体 → 按原逻辑施加 spread（防御性编程） |

#### 测试文件 2: `test_elemental_affliction_system.gd`（扩展现有）

| 测试名 | 验证内容 |
|--------|----------|
| `test_electric_applies_aim_disturbance` | **[新增]** 有 CAim + CElementalAffliction[ELECTRIC] 的实体 → `electric_affliction_jitter > 0` |
| `test_electric_jitter_scales_with_intensity` | **[新增]** intensity=1.0 vs 3.0 → jitter 成比例变化 |
| `test_electric_jitter_capped_at_max` | **[新增]** 高 intensity → jitter ≤ ELECTRIC_AIM_DISTURBANCE_MAX_DEGREES |
| `test_electric_no_jitter_without_aim` | **[新增]** 无 CAim 组件的实体 → 不崩溃，jitter 默认 0 |
| `test_clearing_electric_resets_jitter` | **[新增]** Electric entry 过期移除 → `electric_affliction_jitter = 0` |
| `test_non_electric_no_jitter` | **[新增]** Fire/Wet/Cold affliction → `electric_affliction_jitter = 0` |

#### 测试文件 3: `test_crosshair_with_electric_affliction.gd`（新建）

| 测试名 | 验证内容 |
|--------|----------|
| `test_crosshair_merges_weapon_spread_and_affliction_jitter` | SCrosshair._update_display_aim 将两者叠加到最终 jitter |
| `test_crosshair_spread_ratio_includes_affliction` | aim.spread_ratio 反映 weapon + affliction 总和 |
| `test_crosshair_no_affliction_no_extra_jitter` | 无 affliction 时 behavior 不变 |

#### 测试文件 4: `test_tracker_electric_interaction.gd`（新建）

| 测试名 | 验证内容 |
|--------|----------|
| `test_tracker_with_electric_affliction_gets_reduced_jitter` | STrackLocation 对 CTracker 实体的 affliction jitter 衰减（若采用推荐方案） |
| `test_tracker_without_electric_weapon_has_clean_aim` | 玩家有 CTracker + Electric 武器 → 无来自 weapon 的 spread（步骤一的成果验证） |

### 6.2 集成测试

#### 测试文件 5: `test_flow_electric_pickup_hit_scenario.gd`（新建，SceneConfig）

编排完整流程：
1. 创建 player + enemy(electric) 实体
2. Player 拾取 weapon_electric box → 验证 player weapon spread 未增加
3. Enemy 攻击命中 player → player 获得 CElementalAffliction[ELECTRIC]
4. 验证 player CAim.electric_affliction_jitter > 0
5. Affliction 过期后 → jitter 归零
6. Player 拾取 tracker → 验证 tracker + electric 共存行为

### 6.3 E2E 测试要点（AI Debug Bridge）

- 可视化确认：拾取 Electric 武器后准星稳定不抖动
- 可视化确认：被 Electric 敌人命中后准星出现黄色闪烁 + 抖动
- 可视化确认：拾取 Tracker 后 Electric 敌人攻击造成的抖动幅度减弱

---

## 七、风险点

### 7.1 高风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **CAim 新字段的 ViewModel 链路断裂** | `electric_affliction_jitter_observable` 若未被 ViewModel 绑定，UI 不更新 | CrosshairView 已基于 `spread_ratio` 重绘，只要 spread_ratio 包含新值即可渲染；无需新增 ViewModel 字段 |
| **SElementalAffliction 执行顺序依赖** | `_apply_electric_aim_disturbance` 写入 CAim，同帧 SCrosshair/STrackLocation 读取 | 三者均在 `"gameplay"` 组，同一组内按注册顺序执行；需确认 SElementalAffliction 在 SCrosshair/STrackLocation 之前执行（GOLWorld 按 `scripts/systems/` 文件名排序加载，`s_elemental_affliction.gd` < `s_crosshair.gd` < `s_track_location.gd`，字母序满足要求） |
| **Config 常量数值平衡性** | `ELECTRIC_AIM_DISTURBANCE_BASE_DEGREES=8.0` 是初始猜测值 | 先用此值落地，通过 E2E 调优；建议加入 Config.gd 方便调整 |

### 7.2 中风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **现有 test_electric_adds_spread 断言失效** | 步骤一修改后，原有"player 也受 spread"的隐含假设被打破 | 更新测试用例：区分 player/enemy 场景 |
| **Tracker 半衰减方案可能引起争议** | 设计选择可能不符合 TL/设计师预期 | 在交接文档中明确标注两种方案的切换方式 |
| **Enemy Electric 武器命中率下降过多** | 排除 player 后，敌方 Electric 武器的 spread 惩罚仍作用于其他敌方实体（如果敌方之间有 friendly fire 或误伤场景） | 当前 `affects_same_camp` 配置控制传播阵营；spread 惩罚仅影响持有者的射击精度，不影响传播 |

### 7.3 低风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| `c_aim.gd` 新字段增加内存占用 | 每个有 CAim 的实体多一个 float + ObservableProperty | 可忽略（CAim 仅 player 少数实体拥有） |
| CrosshairView 电击视觉效果过强 | spread_ratio 升高导致更多黄色+闪电渲染 | 现有代码已实现 pulse 动态调制，自然过渡 |

---

## 八、建议的实现步骤

### Phase 1: 修复持有端（P1）

1. **修改** `scripts/systems/s_electric_spread_conflict.gd:_process_entity`
   - 增加 CCamp 判断，PLAYER 跳过 spread 惩罚
2. **更新** `tests/unit/system/test_electric_spread_conflict.gd`
   - 添加 `test_no_spread_for_player`
   - 将现有 `test_electric_adds_spread` 改为 enemy context
3. **验证**: 运行 gdUnit4 全量测试

### Phase 2: 新增受害端效果（P2）

4. **扩展** `scripts/components/c_aim.gd`
   - 新增 `electric_affliction_jitter` + ObservableProperty
5. **修改** `scripts/systems/s_elemental_affliction.gd`
   - Electric 分支调用 `_apply_electric_aim_disturbance()`
   - `_clear_afflictions()` 中重置 jitter
   - 新增常量 `ELECTRIC_AIM_DISTURBANCE_BASE/MAX_DEGREES`
6. **修改** `scripts/systems/s_crosshair.gd:_update_display_aim`
   - 叠加 `electric_affliction_jitter` 到 jitter 计算
7. **修改** `scripts/systems/s_track_location.gd:_update_display_aim`
   - 同步叠加 + Tracker 衰减逻辑（P3）
8. **编写新单元测试**
   - `test_elemental_affliction_system.gd` 扩展（5 个新 case）
   - `test_crosshair_with_electric_affliction.gd`（新建）
   - `test_tracker_electric_interaction.gd`（新建）
9. **验证**: 运行全量测试

### Phase 3: 集成验证

10. **创建** `tests/integration/flow/test_flow_electric_pickup_hit_scenario.gd`
11. **运行** 全部测试套件
12. **E2E 验证**: AI Debug Bridge 目视检查

### 实现顺序依赖图

```
Phase 1 (P1 fix)
  ├─ Step 1: s_electric_spread_conflict.gd 修改
  ├─ Step 2: 更新旧测试
  └─ Step 3: 验证
       │
Phase 2 (P2 + P3)
  ├─ Step 4: c_aim.gd 扩展 ←── 无依赖
  ├─ Step 5: s_elemental_affliction.gd 修改 ←── 依赖 Step 4
  ├─ Step 6: s_crosshair.gd 修改 ←── 依赖 Step 4
  ├─ Step 7: s_track_location.gd 修改 ←── 依赖 Step 4
  ├─ Step 8: 新单元测试 ←── 依赖 Step 5-7
  └─ Step 9: 验证
       │
Phase 3
  ├─ Step 10: 集成测试 ←── 依赖 Phase 1+2
  ├─ Step 11: 全量测试
  └─ Step 12: E2E
```
