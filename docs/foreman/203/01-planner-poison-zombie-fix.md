# Planner — Issue #203: Poison Zombie Effect Fix

## 需求分析

Issue #203 报告两个问题：
1. **毒伤害极低，几乎无法察觉** — 带毒属性的丧尸虽然能对玩家造成毒伤害，但伤害量极小
2. **该类丧尸无法造成近战伤害** — 毒丧尸的近战攻击无效

用户期望：
- 毒丧尸应当能造成正常的近战伤害（与基础丧尸一致）
- 毒丧尸的毒效果（AoE 持续伤害）应当产生可感知的伤害量

## 影响面分析

### 问题 1 根因：invincible_time 严重压制毒伤害

**核心发现**：`SDamage._take_damage()` 在 `s_damage.gd:215` 检查 `hp.invincible_time > 0`，如果目标处于无敌帧内则直接跳过伤害。每次成功造成伤害后，在 `s_damage.gd:229` 设置 `hp.invincible_time = HURT_INVINCIBLE_TIME = 0.3s`。

**毒伤害链路**：
1. `SAreaEffectModifier` 每帧对半径内的目标添加 `CDamage`（`s_area_effect_modifier.gd:150-156`）
2. `SDamage` 处理 `CDamage` 时调用 `_take_damage()`
3. 第一帧命中成功 → 设置 0.3s 无敌时间
4. 接下来 ~18 帧（60fps）的所有毒伤害全部被 `invincible_time` 检查阻挡
5. 0.3s 后无敌帧结束，再次命中一帧 → 又设置 0.3s 无敌
6. **实际有效 DPS ≈ damage_per_sec * power_ratio * (1/0.3) = 1.8 * 3.33 = 6.0/s** 理论上...但实际更糟：由于 damage 是按帧累积到 CDamage 的，0.3s 内累积的 damage 只在第一帧被处理一次，后续累积的被丢弃（因为 CDamage 被 remove 了）

**实际计算**：
- 每帧累积伤害：`3.0 * 0.6 * (1/60) ≈ 0.03/frame`
- 每 0.3s 累积：`0.03 * 18 ≈ 0.54` — 然后被一次性应用
- 实际 DPS：`0.54 / 0.3 = 1.8/s` — 但看起来还行？

**更严重的问题**：系统执行顺序。如果 `SDamage` 先于 `SAreaEffectModifier` 执行，那么：
- Frame 1: SAreaEffectModifier 累积 0.03 到 CDamage
- Frame 1: SDamage 处理 0.03 伤害 → invincible_time = 0.3s
- Frame 2-18: SAreaEffectModifier 继续累积到 CDamage → 但 CDamage 已被 SDamage 在 Frame 1 删除
  - 新的 CDamage 被创建（`s_area_effect_modifier.gd:167-169`），累积 0.03 * 17 ≈ 0.51
- Frame 19: SDamage 处理 0.51 伤害 → invincible_time = 0.3s（又有延迟）

**结论**：invincible_time 机制导致毒伤害被严重节流，加上极低的 base damage (3.0 * 0.6 = 1.8/sec)，使得实际感受上的毒伤害几乎为零。

**对比元素系统**：`SElementalAffliction` 的 `_queue_damage()` (`s_elemental_affliction.gd:159-168`) 也使用 CDamage 组件，同样会受 invincible_time 阻挡。但元素伤害的 intensity 通常较高（如火焰 tick 伤害 = intensity * 4.0 * tick_interval），所以即使被节流也能被感知。

### 问题 2 根因：毒丧尸近战攻击确实生效，但被误报

**分析**：`enemy_poison.tres` 的 recipe 中确实包含了 `CMelee` 组件，且 `SMeleeAttack` 系统没有针对毒丧尸的过滤逻辑。毒丧尸的 GOAP 配置包含 `clear_threat` 目标（攻击目标），会触发 `GoapAction_AttackMelee`。

**但实际可能存在的问题**：毒丧尸的 `CMelee` 组件使用默认值（`damage = 10.0`, `attack_range = 24.0`），这些值与 `enemy_basic.tres` 一致。近战攻击本身应该能正常触发。

**可能的真正原因**：毒丧尸的 `max_speed = 80`（低于基础丧尸的 `100`），可能导致毒丧尸更难接近目标进入近战范围，使得玩家感知为"无法近战"。加上毒丧尸依赖 AoE 毒雾作为主要输出方式，可能在远距离就停下来了。

**但如果确实无法近战**：需要 E2E 验证。可能是 GOAP action 的 ready_range（默认 20）与毒丧尸的行为逻辑有关，需要实际运行时测试确认。

### 受影响的文件

| 文件 | 角色 |
|------|------|
| `scripts/systems/s_damage.gd:214-229` | invincible_time 机制（问题 1 根因） |
| `scripts/systems/s_area_effect_modifier.gd:150-169` | 毒伤害累积逻辑 |
| `scripts/systems/s_elemental_affliction.gd:159-168` | 元素伤害累积（对比参考） |
| `scripts/systems/s_melee_attack.gd:138-149` | 近战命中逻辑 |
| `scripts/components/c_poison.gd` | 毒伤害数值定义 |
| `resources/recipes/enemy_poison.tres` | 毒丧尸 entity recipe |
| `scripts/components/c_area_effect.gd` | 区域效果配置 |

### 调用链

**毒伤害链路**：
```
SAreaEffectModifier.process()
  → _process_entity() → _apply_effects()
    → _should_apply_poison() → _apply_poison_damage()
      → _add_damage_to_target() — 添加 CDamage 到目标
SDamage.process()
  → _process_pending_damage() → _take_damage()
    → hp.invincible_time 检查 — 阻挡伤害 ❌
```

**近战攻击链路**：
```
GoapAction_AttackMelee → 设置 CMelee.attack_pending = true
SMeleeAttack._process_entity()
  → _perform_attack()
    → 物理空间查询找到目标
    → _apply_melee_hit() → 添加 CDamage
    → _apply_on_hit_element() → ElementalUtils.apply_attack() — 毒丧尸无 CElementalAttack，无效果
SDamage._take_damage() → 正常处理近战伤害
```

### 受影响的实体/组件类型

- `CPoison` — 毒组件（数值偏低）
- `CAreaEffect` — 区域效果（配合毒使用）
- `CDamage` — 伤害标记（被 invincible_time 节流）
- `CHP` — 无敌时间来源

### 潜在副作用

- 修改 invincible_time 对 DoT 效果的豁免逻辑会影响所有 DoT 伤害（毒 + 元素火焰/闪电）
- 提高毒伤害数值需要平衡考虑
- 修改 CDamage 处理方式可能影响所有伤害来源

## 实现方案

### 方案：双层修复

**修复 A — 解决 invincible_time 阻挡 DoT 伤害（核心问题）**

在 `SDamage._take_damage()` 中，为 DoT 类伤害绕过 invincible_time 检查。

实现方式：在 `CDamage` 组件中新增 `bypass_invincible: bool = false` 字段。DoT 来源设置此字段为 true，`_take_damage()` 检查此字段来决定是否跳过 invincible_time 检查。

修改位置：
1. `scripts/components/c_damage.gd` — 新增 `var bypass_invincible: bool = false` 字段
2. `scripts/systems/s_damage.gd:214-216` — 修改 invincible_time 检查逻辑：
   ```gdscript
   if hp.invincible_time > 0 and not (damage.bypass_invincible if damage else false):
       return true
   ```
   但注意：`_take_damage()` 在 `_process_pending_damage()` 中被调用，此时已经从 CDamage 提取了 amount，需要传递 bypass_invincible 参数。

   实际上 `_process_pending_damage` 调用 `_take_damage(target_entity, damage.amount, damage.knockback_direction)`，需要增加参数传递 bypass_invincible。

3. `scripts/systems/s_area_effect_modifier.gd:159-169` — `_add_damage_to_target()` 设置 `bypass_invincible = true`
4. `scripts/systems/s_elemental_affliction.gd:159-168` — `_queue_damage()` 设置 `bypass_invincible = true`

**修复 B — 提高毒丧尸的毒伤害数值**

当前 `CPoison.damage_per_sec = 3.0`，`CAreaEffect.power_ratio = 0.6`，有效 DPS = 1.8/s。对 100HP 的玩家来说需要 ~55 秒才能击杀，确实极低。

建议将 `enemy_poison.tres` 中的 `CPoison.damage_per_sec` 提高到 `8.0`，有效 DPS = 4.8/s，~21 秒击杀 100HP 玩家。这与其他元素的 DoT 伤害量级（火焰 4.0/sec * intensity）相当。

修改位置：
1. `resources/recipes/enemy_poison.tres` — 修改 `[sub_resource type="Resource" id="poison"]` 的 `damage_per_sec = 8.0`

**修复 C — 近战攻击问题排查**

毒丧尸确实有 CMelee 组件且无过滤逻辑，近战应该能工作。如果问题仍存在，可能原因：
1. 移速过低（80 vs 基础 100）导致难以接近 → 可选提高移速
2. GOAP 行为优先级问题 → 需要 E2E 验证

建议作为可选优化：将 `enemy_poison.tres` 的 `max_speed` 从 `80` 提高到 `90`，使其更接近目标。

### 文件修改列表

| 文件 | 修改类型 | 描述 |
|------|---------|------|
| `scripts/components/c_damage.gd` | 修改 | 新增 `bypass_invincible` 字段 |
| `scripts/systems/s_damage.gd` | 修改 | `_process_pending_damage` 传递 bypass_invincible；`_take_damage` 增加 bypass_invincible 参数 |
| `scripts/systems/s_area_effect_modifier.gd` | 修改 | `_add_damage_to_target` 创建 CDamage 时设置 `bypass_invincible = true` |
| `scripts/systems/s_elemental_affliction.gd` | 修改 | `_queue_damage` 创建 CDamage 时设置 `bypass_invincible = true` |
| `resources/recipes/enemy_poison.tres` | 修改 | `damage_per_sec` 从 3.0 改为 8.0；可选 `max_speed` 从 80 改为 90 |

## 架构约束

- **涉及的 AGENTS.md 文件**：
  - `scripts/components/AGENTS.md` — CDamage 修改，属于 Component 层
  - `scripts/systems/AGENTS.md` — SDamage、SAreaEffectModifier、SElementalAffliction 修改
  - `tests/AGENTS.md` — 测试模式

- **引用的架构模式**：
  - **Component = pure data**（`components/AGENTS.md`）：`CDamage.bypass_invincible` 是纯数据字段，符合约束
  - **System = logic**（`systems/AGENTS.md`）：所有逻辑修改在 System 层，不侵入 Component 逻辑
  - **CDamage 是 transient marker**（`components/AGENTS.md`）：CDamage 本身就是临时伤害标记，每帧被 SDamage 消费后删除。bypass_invincible 作为标记属性完全符合其 transient 特性

- **文件归属层级**：无新文件，所有修改在现有文件内

- **测试模式**：
  - 单元测试：gdUnit4 `GdUnitTestSuite` — 测试 `_take_damage` 的 bypass_invincible 逻辑、`_add_damage_to_target` 设置 bypass_invincible
  - E2E 测试：AI Debug Bridge — 运行时验证毒丧尸实际伤害输出和近战攻击

## 测试契约

- [ ] **单元测试：CDamage.bypass_invincible 字段存在且默认 false**
  - 验证方式：gdUnit4，创建 CDamage 实例，断言 `bypass_invincible == false`
  - 文件：`tests/unit/test_c_damage.gd`（如存在）或新建

- [ ] **单元测试：SDamage._take_damage 在 bypass_invincible=true 时跳过 invincible_time 检查**
  - 验证方式：gdUnit4，设置 `hp.invincible_time > 0`，传入 `bypass_invincible=true`，断言伤害被正常应用
  - 文件：`tests/unit/test_s_damage.gd`（如存在）或新建

- [ ] **单元测试：SAreaEffectModifier._add_damage_to_target 创建的 CDamage 带 bypass_invincible=true**
  - 验证方式：gdUnit4，mock entity 调用 `_add_damage_to_target`，断言目标上的 CDamage.bypass_invincible == true

- [ ] **单元测试：SElementalAffliction._queue_damage 创建的 CDamage 带 bypass_invincible=true**
  - 验证方式：gdUnit4，mock entity 调用 `_queue_damage`，断言目标上的 CDamage.bypass_invincible == true

- [ ] **E2E 验证：毒丧尸对玩家造成持续可感知的毒伤害** (运行时行为)
  - 验证方式：AI Debug Bridge，生成毒丧尸，让玩家站在毒范围内，监控 HP 变化，确认 DPS 约为 4.8/s

- [ ] **E2E 验证：毒丧尸能正常执行近战攻击** (运行时行为)
  - 验证方式：AI Debug Bridge，生成毒丧尸并让其接近玩家，确认 CMelee.attack_pending 被触发，目标受到近战伤害

- [ ] **回归测试：普通丧尸近战攻击不受影响**
  - 验证方式：E2E，基础丧尸近战伤害正常，invincible_time 仍然对普通近战攻击生效

- [ ] **回归测试：元素 DoT 伤害仍然正常**
  - 验证方式：E2E，火焰丧尸的火焰 DoT 伤害正常生效

## 风险点

1. **bypass_invincible 改变了 DoT 伤害的核心行为** — 元素 DoT（火焰、闪电）也会受益于 bypass_invincible。需要确认这些 DoT 的伤害平衡是否仍然合理。当前元素 DoT 使用 tick_interval（0.5s），不受 invincible_time 影响可能使其伤害显著提升。需要评估是否需要同时调整元素 DoT 数值。

2. **SDamage._take_damage 签名变更** — 增加参数可能影响调用方。`_take_damage` 被多处调用（近战、子弹、DoT），需要确保所有调用点都传递正确参数。建议使用默认值 `bypass_invincible: bool = false` 保持向后兼容。

3. **毒伤害数值调整的平衡性** — 将 damage_per_sec 从 3.0 改为 8.0 是一个较大的提升。建议在 E2E 中实际感受后再微调。

4. **近战问题可能不是 bug** — 毒丧尸确实配置了 CMelee，问题可能是设计层面的（移速慢导致难以接近）。如果用户仍报告无法近战，需要通过 E2E 进一步排查。

## 建议的实现步骤

1. 修改 `scripts/components/c_damage.gd`：新增 `var bypass_invincible: bool = false` 字段
2. 修改 `scripts/systems/s_damage.gd`：
   - `_process_pending_damage()` 提取 `damage.bypass_invincible` 并传递给 `_take_damage()`
   - `_take_damage()` 增加 `bypass_invincible: bool = false` 参数，修改 invincible_time 检查逻辑
   - `_process_bullet_collision()` 和其他 `_take_damage` 调用点保持不传（使用默认 false）
3. 修改 `scripts/systems/s_area_effect_modifier.gd`：`_add_damage_to_target()` 创建新 CDamage 时设置 `bypass_invincible = true`；已有的 CDamage 也设置 `bypass_invincible = true`
4. 修改 `scripts/systems/s_elemental_affliction.gd`：`_queue_damage()` 创建新 CDamage 时设置 `bypass_invincible = true`；已有的 CDamage 也设置
5. 修改 `resources/recipes/enemy_poison.tres`：`damage_per_sec` 从 3.0 改为 8.0
6. 编写单元测试覆盖 bypass_invincible 逻辑
7. E2E 验证毒丧尸的毒伤害和近战攻击
8. 回归验证普通丧尸和元素丧尸不受影响
