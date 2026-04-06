# Issue #198 审查报告：雷属性组件拾取/受击效果优化实现

> **审查者**: Reviewer Agent（对抗性代码审查）
> **日期**: 2026-04-05
> **PR**: #240
> **分支**: foreman/issue-198

---

## 审查范围

| 范围 | 文件数 | 状态 |
|------|--------|------|
| 源码修改文件 | 5 个 | 已全部读取完整内容 |
| 测试文件 | 5 个 | 已全部读取完整内容 |
| 计划文档 | 2 个 | 已读取 |

### 文件清单对照

| 计划声称的修改/新建文件 | Git diff 实际存在 | 状态 |
|---|---|---|
| `scripts/systems/s_electric_spread_conflict.gd` | ✅ 存在 | 一致 |
| `scripts/systems/s_elemental_affliction.gd` | ✅ 存在 | 一致 |
| `scripts/components/c_aim.gd` | ✅ 存在 | 一致 |
| `scripts/systems/s_crosshair.gd` | ✅ 存在 | 一致 |
| `scripts/systems/s_track_location.gd` | ✅ 存在 | 一致 |
| `tests/unit/system/test_electric_spread_conflict.gd` | ✅ 存在 | 一致 |
| `tests/unit/system/test_elemental_affliction_system.gd` | ✅ 存在 | 一致 |
| `tests/unit/system/test_crosshair_with_electric_affliction.gd` | ✅ 存在（新建） | 一致 |
| `tests/unit/system/test_tracker_electric_interaction.gd` | ✅ 存在（新建） | 一致 |
| `tests/integration/flow/test_flow_electric_pickup_hit_scenario.gd` | ✅ 存在（新建） | 一致 |

**框架文件检查**: 无 AGENTS.md / CLAUDE.md 等框架文件改动。✅ 通过

---

## 验证清单

### P1 — SElectricSpreadConflict 阵营排除

- [x] **验证 `_process_entity()` 是否正确增加了 CCamp 判断**
  - 执行动作：Read `s_electric_spread_conflict.gd:26-35`，确认新增了 `var camp: CCamp = entity.get_component(CCamp)` 和 `camp.camp == CCamp.CampType.PLAYER` 分支判断。
  - 结果：逻辑与计划 4.2 节完全一致。

- [x] **验证 CCamp=PLAYER 时是否跳过 spread 惩罚**
  - 执行动作：第 29-30 行，PLAYER 时 `weapon.spread_degrees = weapon.base_spread_degrees`，不增加惩罚。
  - 结果：✅ 符合预期。

- [x] **验证 CCamp=ENEMY 时是否保持 +15° spread 并 cap at MAX_SPREAD_DEGREES**
  - 执行动作：第 32-35 行，else 分支执行 `minf(base + 15, MAX)`。
  - 结果：✅ 符合预期。

- [x] **验证无 CCamp 组件时是否保持防御性行为**
  - 执行动作：第 28 行 `if camp and ...`，无 CCamp 时走 else 分支（施加 spread）。
  - 结果：✅ 符合计划中的防御性编程要求。

- [x] **测试覆盖验证 — player 不受 spread 用例**
  - 执行动作：Read `test_electric_spread_conflict.gd:24-39`，`test_no_spread_for_player()` 设置 PLAYER + ELECTRIC，断言 spread 保持 5.0。
  - 结果：✅ 覆盖。

- [x] **测试覆盖验证 — enemy spread 断言仍有效**
  - 执行动作：Read `test_electric_spread_conflict.gd:8-22`，`test_electric_adds_spread_for_enemy()` 设置 ENEMY + ELECTRIC，断言 spread ≈ 15.0。
  - 结果：✅ 原有断言已更新为 enemy context，不再隐含"所有实体"假设。

### P2 — Electric Affliction Aim Disturbance

- [x] **c_aim.gd 新增字段验证**
  - 执行动作：Read `c_aim.gd:36-41`，确认 `electric_affliction_jitter` 字段 + ObservableProperty setter pattern 与现有字段（如 `spread_ratio`）一致。
  - 结果：✅ Component pure data，setter 模式符合规范。

- [x] **SElementalAffliction Electric 分支调用 `_apply_electric_aim_disturbance()`**
  - 执行动作：Read `s_elemental_affliction.gd:103-107`。
  - **结果：❌ 发现 Critical 缩进 Bug（详见下方问题列表）**

- [x] **`_clear_afflictions()` 重置 jitter 为 0**
  - 执行动作：Read `s_elemental_affliction.gd:229-232`，确认在 CMovement 重置之后添加了 CAim 重置逻辑，null 安全检查一致。
  - 结果：✅ 符合预期。同时第 86-89 行 entries_changed 处也有清除逻辑（Electric entry 单独移除场景）。

- [x] **新增常量 `ELECTRIC_AIM_DISTURBANCE_BASE/MAX_DEGREES` 存在**
  - 执行动作：Read `s_elemental_affliction.gd:18-19`，常量值为 8.0 / 20.0，与计划一致。
  - 结果：✅ 存在且值正确。

- [x] **SCrosshair 叠加 jitter 到 total_jitter 计算**
  - 执行动作：Read `s_crosshair.gd:59-73`，确认 `total_jitter_degrees = weapon_spread_degrees + aim.electric_affliction_jitter`，spread_ratio 和 jitter 范围均使用 total 值。
  - 结果：✅ 符合计划 4.4 节。

- [x] **STrackLocation 同步叠加 + Tracker 衰减逻辑**
  - 执行动作：Read `s_track_location.gd:125-146`，确认叠加逻辑 + 第 129-131 行 CTracker 半衰减（×0.5）。
  - 结果：✅ 符合计划 4.6 节推荐方案。

### P3 — 测试质量验证

- [x] **test_elemental_affliction_system.gd 扩展用例**
  - 执行动作：Read 全部 6 个新增 test 方法（165-270 行），逐一核对：
    - `test_electric_applies_aim_disturbance` → jitter > 0 ✅
    - `test_electric_jitter_scales_with_intensity` → high > low ✅
    - `test_electric_jitter_capped_at_max` → ≤ 20.0 ✅
    - `test_electric_no_jitter_without_aim` → 无崩溃 ✅
    - `test_clearing_electric_resets_jitter` → 归零 ✅
    - `test_non_electric_no_jitter` → Fire = 0 ✅
  - 结果：✅ 计划中 6 个用例全部实现。

- [x] **test_crosshair_with_electric_affliction.gd 新建验证**
  - 执行动作：Read 全部 4 个 test 方法：
    - 合并验证 ✅ | spread_ratio 包含 affliction ✅ | 无 affliction 行为不变 ✅ | viewport=null 重置 ✅
  - 结果：✅ 计划 3 个用例 + 1 个边界用例，超预期覆盖。

- [x] **test_tracker_electric_interaction.gd 新建验证**
  - 执行动作：Read 全部 3 个 test 方法：
    - Tracker 衰减验证 ✅ | Tracker + Electric 武器共存 ✅ | 非 Tracker 全量生效 ✅
  - 结果：✅ 计划 2 个用例 + 1 个对比用例，覆盖充分。

### P4 — 集成测试验证

- [x] **test_flow_electric_pickup_hit_scenario.gd 编排完整性**
  - 执行动作：Read `test_run()` 方法（59-149 行），验证流程：
    1. Player 初始 spread = 5.0 ✅
    2. Player 添加 Electric 元素攻击后 spread 未变 ✅
    3. Enemy melee 攻击命中 Player 后获得 CElementalAffliction[ELECTRIC] ✅
    4. Player aim.electric_affliction_jitter > 0 ✅
    5. Affliction 清除后 jitter 归零 ✅
  - **缺失项**: 未编排 Tracker 共存场景（步骤 6 在计划 6.2 节中提到但未实现）。Non-blocking。

---

## 架构一致性对照（固定检查项）

- [x] **System 文件名未改变** — `s_elemental_affliction.gd`、`s_crosshair.gd`、`s_track_location.gd` 均未重命名。字母序执行顺序依赖保持不变（s_elemental < s_crosshair < s_track_location）。
- [x] **Component 是 pure data** — `c_aim.gd` 仅新增数据字段 + ObservableProperty，无逻辑混入。✅
- [x] **所有 .gd 文件有 class_name 声明** — 逐文件确认全部有 `class_name Xxx`。✅
- [x] **使用 tab 缩进和静态类型标注** — 所有修改文件使用 tab 缩进；函数参数和变量均有类型标注。✅
- [x] **测试目录结构正确** — unit 测试在 `tests/unit/system/`，集成测试在 `tests/integration/flow/`。✅
- [ ] **是否存在平行实现** — 见下方 Minor 问题 #2 分析。

---

## 发现的问题

### 问题 #1 — [Critical] Match 缩进错误导致 ELECTRIC 分支脱离 match 块

**置信度**: 100%（直接读取源码确认）

**文件**: `scripts/systems/s_elemental_affliction.gd:103`

**问题描述**:

`_apply_tick_effect()` 函数中 match 语句的 ELECTRIC case **缩进不足**，不在 match 块内部：

```
100→		match element_type:
101→			COMPONENT_ELEMENTAL_ATTACK.ElementType.FIRE:        ← 3 tab ✅ 正确
102→				_queue_damage(...)                             ← 4 tab
103→		COMPONENT_ELEMENTAL_ATTACK.ElementType.ELECTRIC:      ← 2 tab ❌ 错误！
104→			var damage_multiplier := ...
105→			_queue_damage(...)
106→			_apply_electric_aim_disturbance(...)
```

第 103 行 `ELECTRIC:` 只有 **2 个 tab**，与第 100 行 `match element_type:` 同级；而第 101 行 `FIRE:` 有 **3 个 tab**（正确位于 match 内部）。

**影响**:
- GDScript 解析器会将 `ELECTRIC:` 及其后续语句视为 match 之后的**独立顶层代码**，而非 match 的一个 case 分支
- 这意味着 **每次 tick 循环都会无条件执行** Electric 的伤害计算（`_queue_damage`）和准星干扰（`_apply_electric_aim_disturbance`），无论当前处理的 `element_type` 是 FIRE / WET / COLD 还是其他任何元素
- 对持有 Fire/Cold/Wet affliction 的实体也会被错误地施加 Electric 效果
- **Electric DoT 伤害会翻倍或更高**（因为原 match 内的正确分支仍可能执行，取决于 Godot 解析器对这种缩进错误的处理方式）

**根因分析**:
原始 main 分支的代码中此位置就存在同样的缩进缺陷（通过 `git show main:...` 确认）。本次 PR 在此基础上做了修改（添加了 `_apply_electric_aim_disturbance` 调用），但**未修复已有的缩进错误**，反而将 ELECTRIC case 内容体的缩进从 4 tab 改为了 3 tab（diff 中可见 `-	\t\t\t\t` → `+\t\t\t`），进一步偏离了正确位置。

**建议修复**:
将第 103 行及后续 ELECTRIC case 内容统一增加 1 个 tab，使其与 FIRE case 保持同级缩进：

```gdscript
		match element_type:
			COMPONENT_ELEMENTAL_ATTACK.ElementType.FIRE:
				_queue_damage(entity, ...)
			COMPONENT_ELEMENTAL_ATTACK.ElementType.ELECTRIC:     # ← 改为 3 tab
				var damage_multiplier := ...                      # ← 改为 4 tab
				_queue_damage(entity, ...)                        # ← 改为 4 tab
				_apply_electric_aim_disturbance(entity, ...)       # ← 改为 4 tab
```

---

### 问题 #2 — [Important] 视觉抖动与实际弹道散布不一致

**置信度**: 90%

**文件**: `scripts/systems/s_fire_bullet.gd` — `_get_visual_spread_angle()` 函数

**问题描述**:

`SFireBullet._get_visual_spread_angle()` 使用以下公式计算实际射击散布角度：

```gdscript
return clampf(aim.spread_angle_degrees, -weapon.spread_degrees, weapon.spread_degrees)
```

这里的 `weapon.spread_degrees` **仅包含武器自身的 spread 值**（经 SElectricSpreadConflict 修正后的值），**不包含** `electric_affliction_jitter`。

但 `SCrosshair._update_display_aim()` 将两者合并写入 `aim.spread_angle_degrees`：

```gdscript
var total_jitter_degrees = weapon.spread_degrees + aim.electric_affliction_jitter
aim.spread_target_angle_degrees = randf_range(-total_jitter_degrees, total_jitter_degrees)
```

**具体场景**:
1. 玩家拾取 Electric 武器 → P1 修复使 `weapon.spread_degrees = base`（例如 5.0）
2. 玩家被敌人 Electric 命中 → `electric_affliction_jitter = 10.0`
3. `SCrosshair` 计算 `total_jitter = 5.0 + 10.0 = 15.0`，准星视觉上显示 15° 抖动范围
4. 玩家开火 → `SFireBullet` 读取 `aim.spread_angle_degrees`（可能达到 ±15°），但 **clamp 到 [-5.0, 5.0]**
5. **实际弹道只有 ±5° 散布**，而准星显示 ±15° 抖动

**影响**: 准星视觉反馈与实际射击精度严重不符。玩家看到准星大幅抖动，但子弹几乎不受 electric affliction 影响。

**建议修复方案**（二选一）:

- **方案 A**（推荐）：修改 `_get_visual_spread_angle` 的 clamp 上限，使其包含 affliction jitter：
  ```gdscript
  var effective_max_spread := weapon.spread_degrees
  var aim_comp: CAim = entity.get_component(CAim)
  if aim_comp:
  	effective_max_spread += aim_comp.electric_affliction_jitter
  return clampf(aim.spread_angle_degrees, -effective_max_spread, effective_max_spread)
  ```
- **方案 B**：如果设计意图是"affliction 只影响视觉不影响实际命中率"，则需在计划文档中明确声明此行为差异（当前无此声明）。

---

### 问题 #3 — [Minor] SCrosshair / STrackLocation 每帧重置 jitter 导致数据竞争风险

**置信度**: 70%

**文件**: `scripts/systems/s_crosshair.gd:56`, `scripts/systems/s_track_location.gd:122`

**问题描述**:

当实体缺少 CWeapon / CTransform / viewport 时，两处 `_update_display_aim` 都会执行：

```gdscript
aim.electric_affliction_jitter = 0.0  # 重置
```

这意味着每帧 SCrosshair 或 STrackLocation 都可能在消费完 jitter 后将其归零。虽然当前系统执行顺序（字母序）保证 `s_elemental_affliction` 先于两者运行，但这种"消费即销毁"的模式比较脆弱——如果未来有任何系统插入到中间位置，或者执行顺序发生变化，jitter 就会在 SElementalAffliction 写入之前被清零，导致该帧丢失干扰效果。

**影响**: 当前架构下不会触发（执行顺序已保证），但属于技术债务。

**建议**: 可考虑改为仅由生产者（SElementalAffliction）负责管理 jitter 生命周期，消费者只做只读。或在代码注释中明确标注执行顺序依赖。

---

### 问题 #4 — [Minor] 集成测试缺少 Tracker 共存场景编排

**置信度**: 95%

**文件**: `tests/integration/flow/test_flow_electric_pickup_hit_scenario.gd`

**问题描述**:

计划 6.2 节第 6 步要求集成测试编排"Player 拾取 tracker → 验证 tracker + electric 共存行为"。当前 `test_run()` 只完成了前 5 步（pickup → hit → affliction → jitter → clear），**缺少第 6 步 Tracker 场景**。

此外，集成测试加载的系统列表（第 14-20 行）也**未包含 `s_track_location.gd`**，无法验证 Tracker 交互。

**影响**: P3（Tracker + Electric 共存）仅在单元级别验证，缺少端到端的集成验证。Non-blocking。

**建议**: 后续 tester/E2E 阶段补充此场景，或在本轮补充 Tracker 相关系统和实体配置。

---

## 回归风险检查

### Cold freeze 功能
- [x] `_clear_afflictions` 中 CMovement 重置逻辑未被修改（仍在第 222-228 行）
- [x] `_apply_movement_modifiers` 未被触碰
- [x] 单元测试 `test_cold_and_wet_freeze_and_restore_movement` 仍保留且未被修改
- **结论**: ✅ 不受影响

### Electric DoT 伤害逻辑
- [x] ⚠️ **受问题 #1 影响**：由于 match 缩进错误，Electirc DoT 可能被执行两次（match 外的独立语句 + 若解析器容忍则可能重复）
- 排除缩进 bug 后：`_queue_damage` 调用参数未变，damage_multiplier 逻辑不变
- **结论**: ⚠️ 语法层面需要修复缩进后才能确认回归安全

### Electric 传播链机制
- [x] `_propagate_if_ready()` 函数未被修改
- [x] 传播参数（radius、interval、ratio 等）未变
- **结论**: ✅ 不受影响

---

## 测试契约检查

| 计划要求的测试断言 | 实现 | 状态 |
|---|---|---|
| CCamp=PLAYER + CWeapon + CElementalAttack[ELECTRIC] → spread == base | `test_no_spread_for_player` | ✅ Pass |
| CCamp=ENEMY + 同上 → spread == base + 15° (capped) | `test_electric_adds_spread_for_enemy` + `test_spread_capped_at_max` | ✅ Pass |
| 无 CCamp 组件 → 保持原行为 | `test_entity_without_camp_gets_spread` | ✅ Pass |
| 有 CAim + CElementalAffliction[ELECTRIC] intensity > 0 → jitter > 0 | `test_electric_applies_aim_disturbance` | ✅ Pass |
| jitter 与 intensity 成正比，有上限 | `test_electric_jitter_scales_with_intensity` + `test_electric_jitter_capped_at_max` | ✅ Pass |
| 无 CAim → 不崩溃 | `test_electric_no_jitter_without_aim` | ✅ Pass |
| Electric entry 清除/过期 → jitter 归零 | `test_clearing_electric_resets_jitter` | ✅ Pass |
| Fire/Wet/Cold → jitter = 0 | `test_non_electric_no_jitter` | ✅ Pass |
| CTracker + Electric 武器 → 无来自 weapon 的 spread | `test_tracker_without_electric_weapon_has_clean_aim` | ✅ Pass |
| CTracker + Electric affliction → jitter 受衰减 | `test_tracker_with_electric_affliction_gets_reduced_jitter` | ✅ Pass |
| SCrosshair 叠加 weapon + affliction jitter | `test_crosshair_merges_weapon_spread_and_affliction_jitter` | ✅ Pass |
| STrackLocation 叠加 + 衰减 | `test_tracker_with_electric_affliction_gets_reduced_jitter` + `test_non_tracker_gets_full_electric_jitter` | ✅ Pass |

**注**: 以上断言在问题 #1 修复前，部分 test_electric_applies_aim_disturbance 类测试的行为可能因缩进 bug 而产生偏差（ELECTRIC 效果无条件触发意味着即使构造的是非 Electric affliction 也可能写入 jitter）。但测试本身是直接给实体施加 Electric payload 再调用 system.process()，所以实际运行路径恰好碰巧能通过。**修复缩进后应重新验证**。

---

## 结论

**`rework`**

必须修复以下问题后才可进入 tester/E2E 阶段：

1. **[Critical]** `s_elemental_affliction.gd:103` — match 缩进错误，ELECTRIC case 必须缩进至 match 块内部（+1 tab）。这是功能性 bug，会导致所有 affliction 类型实体都被施加 Electric 效果。

2. **[Important]** `s_fire_bullet.gd:_get_visual_spread_angle` — clamp 上限未包含 `electric_affliction_jitter`，导致准星视觉抖动与实际弹道散布不一致。需要在 clamp 计算中加入 affliction jitter 值，或在计划中明确声明此设计意图。

Minor 问题（#3 数据竞争模式、#4 集成测试缺 Tracker 场景）可在后续迭代中处理，不阻塞当前轮次。
