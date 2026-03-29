# Planner: Weapon Merge — Keep Best Stats on Pickup

**Issue:** #214 — 拾取同类武器组件时不应直接覆盖更高参数（如攻速）
**Status:** READY

---

## 需求分析

### Issue 要求

当前拾取同类武器组件（如 CWeapon）时，`on_merge()` 对所有参数执行**全量覆盖**（last-write-wins），导致：
- 持有步枪（interval=0.5，即高攻速）时拾取手枪（interval=2.0 默认值），攻速被拖慢
- 持有高品质武器后拾取低品质同类武器，各项参数均被降级

### 用户期望行为

拾取同类组件时，应**逐字段保留更优值**：
- **interval**：越小越好（攻速越快）→ `min(self.interval, other.interval)`
- **bullet_speed**：越大越好 → `max(self.bullet_speed, other.bullet_speed)`
- **attack_range**：越大越好 → `max(self.attack_range, other.attack_range)`
- **spread_degrees**：越小越好（精准度越高）→ `min(self.spread_degrees, other.spread_degrees)`

### 边界条件

1. **首次拾取**：实体尚无该组件 → 走 `add_component` 路径，不涉及 merge，不受影响
2. **bullet_recipe_id**：子弹类型是标识性字段，不是"越高越好"的参数 → 应始终覆盖（新武器替换子弹类型）
3. **CMelee 同理**：`attack_interval` 越小越好，`damage` / `attack_range` 越大越好
4. **CElementalAttack**：元素类型改变时属于更换元素，应全量覆盖（不同类型不可比）
5. **Cost system 交互**：`on_merge` 重置 `base_interval = -1.0`，触发 cost system 重新捕获 base → 修改 merge 后必须确保 cost system 正常工作
6. **Composer 合成**：合成组件使用默认构造值 → 不走 `on_merge`（首次添加），不受影响
7. **掉落后自拾取**：`container.dropped_by` 检查防止自拾取 → 不受影响

---

## 影响面分析

### 受影响的文件/函数

| 文件 | 函数/行 | 变更类型 |
|------|---------|---------|
| `scripts/components/c_weapon.gd:52-64` | `CWeapon.on_merge()` | **修改** — 从全量覆盖改为 per-field max/min |
| `scripts/components/c_melee.gd:39-49` | `CMelee.on_merge()` | **修改** — 同上 |
| `scripts/components/c_elemental_attack.gd:35-49` | `CElementalAttack.on_merge()` | **不修改** — 元素类型不可比，全量覆盖正确 |
| `scripts/components/c_healer.gd:11-15` | `CHealer.on_merge()` | **不修改** — 非战斗组件，issue 仅要求武器相关 |
| `scripts/components/c_poison.gd` | `CPoison.on_merge()` | **不修改** — 同上 |
| `scripts/components/c_area_effect.gd` | `CAreaEffect.on_merge()` | **不修改** — 同上 |
| `scripts/systems/s_pickup.gd:118-148` | `SPickup._open_box()` | **不修改** — 调用 `on_merge`，merge 逻辑在组件内 |
| `scripts/gameplay/ecs/gol_world.gd:633-652` | `GOLWorld.merge_entity()` | **不修改** — 通用 merge 入口，逻辑正确 |
| `scripts/systems/s_cold_rate_conflict.gd` | `SColdRateConflict` | **不修改** — cost system，已正确处理 base_interval |
| `scripts/systems/s_electric_spread_conflict.gd` | `SElectricSpreadConflict` | **不修改** — cost system，已正确处理 base_spread |
| `tests/unit/test_reverse_composition.gd` | 多个 test | **修改** — 更新断言以匹配新行为 |

### 调用链追踪

**CWeapon.on_merge 的两条调用路径：**

```
路径 1: Recipe mode (loot boxes)
  SPickup._open_box() → GOLWorld.merge_entity() → CWeapon.on_merge()
  s_pickup.gd:143    → gol_world.gd:648          → c_weapon.gd:52

路径 2: Instance mode (dropped components)
  SPickup._open_box() → existing.on_merge(comp)
  s_pickup.gd:131     → c_weapon.gd:52
```

**下游依赖（on_merge 之后）：**

```
CWeapon.on_merge() 
  → 重置 base_interval = -1.0
    → SColdRateConflict.process() 捕获新 base_interval (s_cold_rate_conflict.gd:22-23)
    → SColdRateConflict 应用 cold 1.4x 倍率 (s_cold_rate_conflict.gd:24)
  → 重置 base_spread_degrees = -1.0
    → SElectricSpreadConflict.process() 捕获新 base (s_electric_spread_conflict.gd:22-23)
  → SFireBullet.process() 使用 weapon.interval 计算冷却 (s_fire_bullet.gd)
```

### 受影响的实体/组件类型

- **所有持有 CWeapon 的实体**：Player、Enemy（如持有远程武器）
- **所有持有 CMelee 的实体**：Player、大部分 Enemy

### 潜在的副作用

1. **子弹类型混合**：如果玩家从步枪换成元素步枪，`bullet_recipe_id` 应跟随新武器 → 仍需全量覆盖此字段
2. **AI 行为**：`CWeapon` 的 `interval` 影响 AI 射击频率。max-merge 后敌人拾取低攻速武器不会降级 → 对玩家是有利行为，符合预期
3. **CWeapon.can_fire**：AI 控制标志，merge 时重置为 `true` → 保持现有行为不变
4. **CMelee.night_attack_speed_multiplier**：是敌人夜间攻击倍率，不是"越高越好" → 如果 merge 不同 melee，此字段应跟随新组件

---

## 实现方案

### 推荐方案：Per-field "keep best" merge

**核心思路**：对每个参数字段定义"更优方向"（higher-is-better 或 lower-is-better），merge 时逐字段比较保留更优值。非参数字段（如 bullet_recipe_id、元素类型）保持全量覆盖。

**理由**：
- 方案 A（per-field max）最精确，不会丢失单项优势
- 方案 B（品质评分）需要引入新的评分系统，过度工程化，且不同参数的重要性因场景而异
- 当前组件字段少（CWeapon 5 个参数字段、CMelee 6 个），per-field 比较的成本极低

### CWeapon 字段分析

| 字段 | 方向 | Merge 策略 | 理由 |
|------|------|-----------|------|
| `interval` | 越小越好 | `min(self, other)` | 攻速越快越好 |
| `bullet_speed` | 越大越好 | `max(self, other)` | 弹速越快越好 |
| `attack_range` | 越大越好 | `max(self, other)` | 射程越远越好 |
| `spread_degrees` | 越小越好 | `min(self, other)` | 散布越小越精准 |
| `bullet_recipe_id` | 标识字段 | 全量覆盖 | 子弹类型跟随新武器 |
| `can_fire` | 控制标志 | 重置为 `true` | 保持现有行为 |

### CMelee 字段分析

| 字段 | 方向 | Merge 策略 | 理由 |
|------|------|-----------|------|
| `attack_interval` | 越小越好 | `min(self, other)` | 攻击频率越快越好 |
| `damage` | 越大越好 | `max(self, other)` | 伤害越高越好 |
| `attack_range` | 越大越好 | `max(self, other)` | 攻击范围越远越好 |
| `ready_range` | 越大越好 | `max(self, other)` | AI 就绪距离越远越好 |
| `swing_angle` | 越大越好 | `max(self, other)` | 挥砍角度越大越好 |
| `swing_duration` | 越小越好 | `min(self, other)` | 挥砍越快越好 |
| `night_attack_speed_multiplier` | 标识/设计字段 | 全量覆盖 | 敌人夜间倍率跟随新组件设计 |

### 具体的代码修改位置

**文件 1: `scripts/components/c_weapon.gd:52-64`**

修改 `CWeapon.on_merge()` 为：
```gdscript
func on_merge(other: CWeapon) -> void:
    # Keep best stats (lower = better for interval/spread, higher = better for rest)
    interval = minf(interval, other.interval)
    bullet_speed = maxf(bullet_speed, other.bullet_speed)
    attack_range = maxf(attack_range, other.attack_range)
    spread_degrees = minf(spread_degrees, other.spread_degrees)
    # Identity fields: always take from incoming
    bullet_recipe_id = other.bullet_recipe_id
    # Reset base fields so cost systems re-capture
    base_interval = -1.0
    base_spread_degrees = -1.0
    # Reset runtime state
    last_fire_direction = Vector2.UP
    time_amount_before_last_fire = 0.0
    can_fire = true
```

**文件 2: `scripts/components/c_melee.gd:39-49`**

修改 `CMelee.on_merge()` 为：
```gdscript
func on_merge(other: CMelee) -> void:
    # Keep best stats
    attack_interval = minf(attack_interval, other.attack_interval)
    damage = maxf(damage, other.damage)
    attack_range = maxf(attack_range, other.attack_range)
    ready_range = maxf(ready_range, other.ready_range)
    swing_angle = maxf(swing_angle, other.swing_angle)
    swing_duration = minf(swing_duration, other.swing_duration)
    # Design field: always take from incoming
    night_attack_speed_multiplier = other.night_attack_speed_multiplier
    # Reset base field so cost systems re-capture
    base_attack_interval = -1.0
    # Reset runtime state
    cooldown_remaining = 0.0
    attack_pending = false
    attack_direction = Vector2.ZERO
```

**文件 3: `tests/unit/test_reverse_composition.gd`**

修改 `test_weapon_on_merge_replaces_params` 以验证"keep best"行为。

---

## 架构约束

### 涉及的 AGENTS.md 文件

1. **`scripts/components/AGENTS.md`** — 定义 Component = pure data，`on_merge()` 是特殊模式
   - 组件/AGENTS.md 第 77 行：`on_merge(): Components can implement on_merge(other) for pickup/combine behavior`
   - 本次修改完全在 `on_merge()` 方法内，符合组件纯数据原则
2. **`scripts/systems/AGENTS.md`** — 定义 System = pure logic
   - 本次不修改任何 system，仅修改组件的 merge 逻辑
3. **`tests/AGENTS.md`** — 定义测试分层
   - 单元测试用 `extends GdUnitTestSuite`，放在 `tests/unit/`

### 引用的架构模式

- **on_merge 模式**（`scripts/components/AGENTS.md:77`）：Components implement `on_merge(other)` for pickup/combine behavior → 本次修改扩展此模式，从"全量覆盖"改为"keep best merge"
- **组件纯数据原则**（`scripts/components/AGENTS.md:1`）：Pure data containers, No logic → `minf`/`maxf` 是数据选择操作，不含业务逻辑，符合纯数据原则

### 文件归属层级

- 修改的组件文件位于 `scripts/components/` → 遵循 `scripts/components/AGENTS.md`
- 修改的测试文件位于 `tests/unit/` → 遵循 `tests/AGENTS.md`
- 无新增文件

### 测试模式

- 单元测试：`extends GdUnitTestSuite`，使用 `auto_free()` 管理生命周期
- 测试文件修改：`tests/unit/test_reverse_composition.gd`
- 不需要集成测试或 E2E 测试：修改范围限定在组件 `on_merge()` 方法内，不涉及 system 交互

---

## 测试契约

- [ ] **CWeapon on_merge keeps faster attack speed**：existing interval=0.5, incoming interval=2.0 → merge 后 interval 应为 0.5
- [ ] **CWeapon on_merge upgrades slow attack speed**：existing interval=2.0, incoming interval=0.5 → merge 后 interval 应为 0.5
- [ ] **CWeapon on_merge keeps higher bullet speed**：existing bullet_speed=1400, incoming bullet_speed=800 → merge 后应为 1400
- [ ] **CWeapon on_merge upgrades bullet speed**：existing bullet_speed=800, incoming bullet_speed=1400 → merge 后应为 1400
- [ ] **CWeapon on_merge keeps longer attack range**：existing attack_range=400, incoming attack_range=200 → merge 后应为 400
- [ ] **CWeapon on_merge keeps lower spread**：existing spread_degrees=0, incoming spread_degrees=15 → merge 后应为 0
- [ ] **CWeapon on_merge always replaces bullet_recipe_id**：existing "bullet_old", incoming "bullet_new" → 应为 "bullet_new"
- [ ] **CWeapon on_merge resets runtime state**：merge 后 `base_interval == -1.0`，`time_amount_before_last_fire == 0.0`，`can_fire == true`
- [ ] **CMelee on_merge keeps faster attack interval**：existing attack_interval=0.8, incoming 1.0 → 应为 0.8
- [ ] **CMelee on_merge keeps higher damage**：existing damage=20, incoming 10 → 应为 20
- [ ] **CMelee on_merge keeps longer range**：existing attack_range=30, incoming 24 → 应为 30
- [ ] **CMelee on_merge always replaces night_attack_speed_multiplier**：设计字段应跟随新组件
- [ ] **CMelee on_merge resets runtime state**：merge 后 `base_attack_interval == -1.0`，`cooldown_remaining == 0.0`

所有测试均为单元测试（gdUnit4 GdUnitTestSuite），不涉及 World/ECS.world，不需要 E2E。

---

## 风险点

1. **CWeapon.can_fire 重置为 true**：如果 merge 发生在 AI 不应射击的时刻（如弹药用尽），重置为 true 可能导致意外射击。但 `can_fire` 是 AI 控制标志，AI 在每帧 GOAP 计划中会重新设置此值，所以影响极短暂。**风险等级：低**

2. **base_interval 重置后的 cost system 交互**：`on_merge` 重置 `base_interval = -1.0`，下一帧 cost system（SColdRateConflict）会以新的 `interval`（keep best 后的值）作为 base 重新计算。这确保了 cost penalty 正确应用到最优值上。**风险等级：无**

3. **bullet_recipe_id 覆盖可能导致弹道不匹配**：如果新武器的 bullet_recipe_id 对应的子弹有不同属性（如不同伤害），而武器参数（interval 等）保留了旧值，可能出现"快攻速 + 弱子弹"或"慢攻速 + 强子弹"的组合。但这是 keep best 策略的预期行为——用户在混合搭配中获益。**风险等级：低**

4. **反向拾取（掉落后重新拾取自己的武器）**：`container.dropped_by` 检查已防止此情况。但即使绕过此检查，keep best 策略下重新拾取自己的掉落武器不会导致降级（因为是自己的值 vs 自己的值）。**风险等级：无**

5. **CElementalAttack 未修改**：元素类型切换时（如火→冰），仍为全量覆盖。这意味着拾取冰元素武器会覆盖火元素的 elemental 参数。如果未来需要支持多元素共存，需要额外设计。但当前 issue 仅要求武器参数 keep best，元素类型不在范围内。**风险等级：无（符合 issue 范围）**

6. **CHealer/CPoison/CAreaEffect 未修改**：这些组件的 on_merge 仍为全量覆盖。如果存在拾取低级治疗/毒药组件导致降级的情况，需要单独 issue 处理。当前 issue 标签为 `topic:gameplay`，聚焦武器。**风险等级：无（符合 issue 范围）**

---

## 建议的实现步骤

1. **修改 `scripts/components/c_weapon.gd`**：将 `CWeapon.on_merge()` 从全量覆盖改为 per-field keep best（minf/maxf）。`bullet_recipe_id` 保持全量覆盖。runtime state 重置保持不变。

2. **修改 `scripts/components/c_melee.gd`**：将 `CMelee.on_merge()` 从全量覆盖改为 per-field keep best。`night_attack_speed_multiplier` 保持全量覆盖。runtime state 重置保持不变。

3. **修改 `tests/unit/test_reverse_composition.gd`**：
   - 更新 `test_weapon_on_merge_replaces_params`：验证 keep best 而非全量覆盖
   - 新增测试：攻速保留（existing 更快）、攻速升级（incoming 更快）、bullet_recipe_id 总是覆盖
   - 更新 `test_instance_merge_logic_on_merge_path`：断言改为 keep best 预期值
   - 新增 CMelee on_merge 测试：验证 damage/interval/range keep best

4. **运行单元测试**：`godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/test_reverse_composition.gd -c --ignoreHeadlessMode`，确认全部通过。

5. **运行全量单元测试**：确认没有其他测试被破坏。

6. **提交并推送**：在 `gol-project` 子模块内提交。
