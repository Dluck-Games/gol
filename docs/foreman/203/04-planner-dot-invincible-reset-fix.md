# 04 — Planner: bypass_invincible invincible_time 重置修复

## 需求分析

### Issue 背景

Issue #203 报告：毒丧尸的毒伤害极低且无法造成近战伤害。第一轮修复（01-03）已实现 `CDamage.bypass_invincible` 机制，允许 DoT 伤害绕过 `invincible_time` 检查。Reviewer（03）在审查中发现两个关联缺陷，需要第二轮修复。

### 本轮需修复的问题

**Reviewer Issue 1 (Critical) — bypass_invincible 的 DoT 持续刷新 invincible_time，阻断非 DoT 伤害**

当 `bypass_invincible=true` 的 DoT 伤害成功扣血后，`s_damage.gd:229` 仍无条件设置 `hp.invincible_time = HURT_INVINCIBLE_TIME (0.3s)`。DoT 每帧刷新 invincible_time → 永远不降到 0 → 同目标上的非 DoT 伤害（近战、子弹）被完全阻断。

**Reviewer Issue 2 (Important) — CDamage 累积导致 bypass_invincible 标记跨系统泄漏**

多个 gameplay 组系统在同一帧内向同一实体的 CDamage 累积伤害。由于系统执行顺序不确定（filesystem order），存在两种泄漏场景：
- 场景 A：SMeleeAttack 先创建 CDamage（bypass=false），SAreaEffectModifier 后累积并设置 bypass=true → 近战伤害也绕过
- 场景 B：SAreaEffectModifier 先创建 CDamage（bypass=true），SMeleeAttack 后累积不改标记 → 近战伤害被拉入 bypass

### 用户期望的行为

- 毒丧尸能造成正常近战伤害（与基础丧尸一致）
- 毒丧尸的毒效果产生可感知的伤害量
- DoT 不应阻断其他伤害来源
- 近战/子弹等非 DoT 伤害应正确触发 invincible_time 保护
- 持续 DoT 期间不应出现视觉闪烁（hit blink）刷屏

### 边界条件

- DoT + 近战同时作用于同一目标
- 多个 DoT 来源（毒 + 元素）同时作用于同一目标
- 玩家装备 materia_damage 时的 area melee 行为
- DoT 期间的视觉反馈（hit blink、knockback）

## 影响面分析

### Issue 1 受影响位置

| 文件 | 行号 | 角色 |
|------|------|------|
| `scripts/systems/s_damage.gd` | 229 | `hp.invincible_time = HURT_INVINCIBLE_TIME` — 无条件设置 |

**调用链追踪**：
```
SDamage._process_pending_damage()  [s_damage.gd:32-38]
  → _take_damage(entity, amount, knockback, bypass_invincible)  [s_damage.gd:37]
    → hp.hp -= amount  [s_damage.gd:226]  ✅ 正确扣血
    → hp.invincible_time = HURT_INVINCIBLE_TIME  [s_damage.gd:229]  ❌ 无条件刷新
    → _play_hit_blink(entity)  [s_damage.gd:250]  ❌ DoT 每帧触发闪烁
    → _apply_knockback(entity, direction)  [s_damage.gd:253]  ✅ DoT 的 direction=ZERO 会被跳过
```

**受影响的实体/组件类型**：
- 任何同时受到 DoT 和非 DoT 伤害的实体（玩家站在毒雾中同时被近战、多个元素同时作用于目标）
- `CHP.invincible_time` — 被持续刷新
- `CDamage.bypass_invincible` — 已存在的 bypass 机制

### Issue 2 受影响位置

| 文件 | 行号 | 角色 |
|------|------|------|
| `scripts/systems/s_area_effect_modifier.gd` | 163-166 | 累积时设置 `bypass_invincible = true` |
| `scripts/systems/s_melee_attack.gd` | 139-147 | 累积时不触碰 `bypass_invincible`（保持已有值） |
| `resources/recipes/materia_damage.tres` | 18 | `apply_melee = true` → area melee 通过 `_add_damage_to_target` 创建 bypass CDamage |

**CDamage 创建点完整清单**（当前代码中所有 `CDamage.new()` 调用）：

| 文件 | bypass_invincible 值 | 说明 |
|------|---------------------|------|
| `s_area_effect_modifier.gd:168` | `true` | DoT / area melee |
| `s_elemental_affliction.gd:164` | `true` | 元素 DoT |
| `s_melee_attack.gd:144` | `false`（默认） | 近战伤害 |
| `service_console.gd:533` | `false`（默认） | 调试命令 |
| `test_flow_component_drop_scene.gd:73` | `false`（默认） | 集成测试 |
| `test_flow_blueprint_drop_scene.gd:58` | `false`（默认） | 集成测试 |

### 潜在副作用

1. **hit_blink 视觉刷屏**：修复 Issue 1 后，DoT 不再被 invincible_time 节流 → 每帧 `_play_hit_blink` 被调用 → tween 每帧重建 → 精灵持续闪烁。这是一个**新发现的问题**，必须在本次一并修复。
2. **materia_damage area melee 的 bypass 行为**：`materia_damage.tres` 的 area melee 通过 `_add_damage_to_target` 创建 bypass=true 的 CDamage。这是持续性范围伤害，bypass 行为合理。
3. **元素 DoT 受益于 bypass**：火焰/闪电的 tick 伤害也会绕过 invincible_time。这是第一轮 planner 已评估的预期行为。

## 实现方案

### 修复策略

**Issue 1 修复（Critical）— 条件化 invincible_time 设置 + 抑制 DoT 视觉效果**

在 `s_damage.gd` 的 `_take_damage()` 中：
1. 将 `hp.invincible_time = HURT_INVINCIBLE_TIME` 包裹在 `if not bypass_invincible:` 中
2. 将 `_play_hit_blink(target_entity)` 包裹在 `if not bypass_invincible:` 中

**Issue 2 决策 — 接受 bypass 泄漏，文档化为有意的架构权衡**

**理由**：

经过分析，bypass 泄漏（近战伤害被拉入 bypass）在实际影响上是可接受的：

1. **Issue 1 修复后，bypass 伤害不设置 invincible_time** → 不存在 invincible_time 阻断非 bypass 伤害的问题
2. **泄漏仅发生在 DoT + 近战同帧命中同一目标时** → 场景有限
3. **此时 invincible_time 不被设置** → 即使 bypass 泄漏，近战伤害也能正常命中（invincible_time 要么不存在，要么已被消耗）
4. **大改方案代价过高**：独立 CDamage 实例需要 SDamage 支持多 CDamage 处理，涉及架构重构

**具体来说**：当 DoT 和近战在同一帧命中同一目标时，CDamage 的 bypass=true 使总伤害绕过 invincible_time。但由于 bypass 不设置 invincible_time，下一帧其他敌人的近战攻击不会被阻断。唯一的行为变化是：当玩家同时受到 DoT + 近战时，近战伤害绕过了本来会被 invincible_time 阻挡的那 0.3s。这在游戏体验上是合理的（你站在毒雾里挨打，不应该有无敌保护）。

### 具体代码修改

**文件 1：`scripts/systems/s_damage.gd`**

修改 `_take_damage()` 函数（`s_damage.gd:226-253`）：

```gdscript
# 修改前（当前代码）:
hp.hp = max(0, hp.hp - amount)
hp.invincible_time = HURT_INVINCIBLE_TIME  # ← Issue 1: 无条件设置

# ... (中间代码不变) ...

_play_hit_blink(target_entity)  # ← 新发现: DoT 每帧触发闪烁

# 修改后:
hp.hp = max(0, hp.hp - amount)

# 只有非 bypass 伤害才设置 invincible_time 和触发受击视觉
# DoT (bypass) 不应刷新无敌帧或触发闪烁效果
if not bypass_invincible:
    hp.invincible_time = HURT_INVINCIBLE_TIME
    _play_hit_blink(target_entity)

# knockback 对 bypass 伤害仍保持现有行为（DoT 的 direction=ZERO 会被 _apply_knockback 跳过）
```

**注意**：`_apply_knockback` 不需要修改。DoT 的 `knockback_direction` 始终为 `Vector2.ZERO`，`_apply_knockback` 内部已检查 `direction.length_squared() < 0.01` 并跳过。当近战和 DoT 累积到同一 CDamage 时，近战会覆盖 knockback_direction 为攻击方向，这是合理行为（近战命中应触发击退）。

**文件 2：`scripts/systems/s_damage.gd`（新增注释）**

在 `CDamage` 的 bypass_invincible 使用处或 `_take_damage` 函数上方添加架构说明注释：

```gdscript
## Note on CDamage bypass_invincible flag isolation:
## CDamage is a single transient marker per entity. When multiple damage sources
## accumulate into the same CDamage in the same frame (e.g., melee + DoT),
## the bypass_invincible flag from one source applies to all accumulated damage.
## This is an acceptable trade-off: bypass only prevents invincible_time refresh,
## and in scenarios where leakage occurs, the target is already under sustained DoT.
## See Issue #203 review notes for full analysis.
```

**无其他文件需要修改。**

### 新增/修改的文件列表

| 文件 | 修改类型 | 描述 |
|------|---------|------|
| `scripts/systems/s_damage.gd` | 修改 | `_take_damage()` 中条件化 invincible_time 和 hit_blink；新增架构注释 |
| `tests/unit/system/test_damage_system.gd` | 修改 | 新增 bypass_invincible 不设置 invincible_time 的测试用例 |

### 实现步骤

1. 修改 `s_damage.gd:229` — 将 `hp.invincible_time = HURT_INVINCIBLE_TIME` 包裹在 `if not bypass_invincible:` 中
2. 修改 `s_damage.gd:250` — 将 `_play_hit_blink(target_entity)` 移入同一个 `if not bypass_invincible:` 块
3. 在 `_take_damage()` 函数上方添加架构说明注释
4. 在 `tests/unit/system/test_damage_system.gd` 新增测试用例（见测试契约）
5. 运行测试确认全部通过

## 架构约束

- **涉及的 AGENTS.md 文件**：
  - `scripts/systems/AGENTS.md` — SDamage 修改，属于 System 层
  - `tests/AGENTS.md` — 测试模式

- **引用的架构模式**：
  - **System = logic, Component = pure data**（`components/AGENTS.md`）：CDamage.bypass_invincible 是纯数据字段，所有逻辑在 SDamage System 中修改。符合 ECS 约束。
  - **CDamage 是 transient marker**（`components/AGENTS.md`）：CDamage 每帧被 SDamage 消费后删除。bypass_invincible 作为标记属性符合 transient 特性。
  - **gameplay 组系统执行顺序为 filesystem order，无拓扑排序**：这是 Issue 2 bypass 泄漏的根本原因。当前不接受架构重构，选择接受泄漏行为。

- **文件归属层级**：无新文件，所有修改在现有文件内。测试新增在 `tests/unit/system/` 目录，符合 `tests/AGENTS.md` 约定。

- **测试模式**：
  - 单元测试：gdUnit4 `GdUnitTestSuite` — 测试 bypass_invincible 对 invincible_time 和 hit_blink 的影响
  - E2E 测试：AI Debug Bridge — 验证 DoT 期间非 DoT 伤害正常、视觉无刷屏

## 测试契约

- [ ] **单元测试：bypass_invincible=true 时不设置 invincible_time**
  - 验证方式：gdUnit4，设置 `hp.invincible_time = 0.5`，调用 `_take_damage(bypass=true)`，断言 `hp.invincible_time` 仍为 0.5（未被重置）
  - 文件：`tests/unit/system/test_damage_system.gd`

- [ ] **单元测试：bypass_invincible=false 时正常设置 invincible_time**
  - 验证方式：gdUnit4，调用 `_take_damage(bypass=false)`，断言 `hp.invincible_time == HURT_INVINCIBLE_TIME`
  - 文件：`tests/unit/system/test_damage_system.gd`

- [ ] **单元测试：bypass_invincible=true 时不触发 hit_blink**
  - 验证方式：gdUnit4，调用 `_take_damage(bypass=true)`，断言 sprite 节点的 material 未被设置（通过 mock 或 inspect node tree）
  - 文件：`tests/unit/system/test_damage_system.gd`
  - 注：如果 SDamage 的 `_play_hit_blink` 依赖 viewport/scene tree，可能需要跳过此项，改为 E2E 验证

- [ ] **E2E 验证：DoT 期间非 DoT 伤害正常命中** (运行时行为)
  - 验证方式：AI Debug Bridge，让玩家站在毒丧尸 AoE 范围内，同时让基础丧尸近战攻击玩家，确认近战伤害正常生效（不被 invincible_time 阻断）

- [ ] **E2E 验证：DoT 期间玩家不出现视觉闪烁刷屏** (运行时行为)
  - 验证方式：AI Debug Bridge，截图确认玩家精灵在持续受到毒伤害时无异常闪烁

- [ ] **回归测试：普通近战攻击（无 DoT）仍正确设置 invincible_time**
  - 验证方式：E2E，基础丧尸近战攻击玩家后，确认 invincible_time 被设置，连续快速近战被节流

- [ ] **回归测试：元素 DoT（火焰/闪电）正常工作**
  - 验证方式：E2E，火焰丧尸攻击玩家，确认 DoT 伤害正常生效且不触发闪烁

## 风险点

1. **hit_blink 抑制的副作用**：将 `_play_hit_blink` 放入 `if not bypass_invincible:` 后，任何 bypass=true 的伤害都不触发闪烁。这包括元素 DoT 的 tick 伤害。如果元素 tick 伤害原本就有可见的闪烁反馈（之前被 invincible_time 节流，大约每 0.3s 闪一次），修复后会完全消失。需要确认这是否是期望行为。如果不期望完全消除，可以改为基于 damage 阈值过滤（如 `amount > 1.0` 才触发闪烁）。

2. **bypass 泄漏的长期风险**：如果未来增加新的伤害来源（如持续光束、debuff），它们可能也会受到 CDamage 累积的影响。当前的"接受泄漏"决策需要在代码注释中记录，以便后续开发者理解权衡。

3. **materia_damage area melee**：当前 area melee 通过 `_add_damage_to_target` 创建 bypass=true 的 CDamage。修复后，area melee 也不设置 invincible_time，这意味着 area melee 伤害不会被节流。这是合理的（持续性范围伤害不应被节流），但如果 area melee 的伤害过高，需要通过数值调整而非 invincible_time 来平衡。

4. **_play_hit_blink 的 tween 管理**：即使修复后 DoT 不再触发 hit_blink，当前 hit_blink 实现中每帧创建新 tween 且不清理旧 tween 的问题仍然存在于非 bypass 路径中。这不是本轮修复的范围，但值得记录为技术债。

## 建议的实现步骤

1. 修改 `scripts/systems/s_damage.gd` 的 `_take_damage()` 函数：
   - 将第 229 行 `hp.invincible_time = HURT_INVINCIBLE_TIME` 移入 `if not bypass_invincible:` 块
   - 将第 250 行 `_play_hit_blink(target_entity)` 移入同一个 `if not bypass_invincible:` 块
   - 在 `_take_damage()` 上方添加架构说明注释（关于 CDamage bypass 泄漏的权衡）
2. 在 `tests/unit/system/test_damage_system.gd` 新增测试：
   - `test_bypass_invincible_does_not_set_invincible_time`
   - `test_non_bypass_still_sets_invincible_time`
3. 运行单元测试确认全部通过
4. E2E 验证（AI Debug Bridge）：
   - 毒丧尸毒伤害 + 基础丧尸近战同时作用于玩家 → 两者都正常
   - DoT 期间无视觉闪烁刷屏
