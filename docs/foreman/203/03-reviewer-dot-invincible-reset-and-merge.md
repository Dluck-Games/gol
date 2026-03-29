# 03 — Adversarial Review: bypass_invincible

## 审查范围

### 审查文件（全部完整阅读）
| 文件 | 角色 |
|------|------|
| `scripts/components/c_damage.gd` | 新增 `bypass_invincible` 字段 |
| `scripts/systems/s_damage.gd` | 修改 `_take_damage()` 和 `_process_pending_damage()` |
| `scripts/systems/s_area_effect_modifier.gd` | 修改 `_add_damage_to_target()` |
| `scripts/systems/s_elemental_affliction.gd` | 修改 `_queue_damage()` |
| `scripts/systems/s_melee_attack.gd` | **未修改**，但存在交互 |
| `resources/recipes/enemy_poison.tres` | 修改 `damage_per_sec` |
| `resources/recipes/materia_damage.tres` | **未修改**，但受副作用影响 |
| `scripts/services/impl/service_console.gd` | **未修改**，但存在 CDamage 创建 |
| `tests/unit/test_c_damage.gd` | 新增测试文件 |
| `tests/unit/system/test_damage_system.gd` | 新增 bypass 测试 |
| `tests/unit/system/test_area_effect_modifier.gd` | 新增 bypass 测试 |
| `tests/unit/system/test_elemental_affliction_system.gd` | 新增 bypass 测试 |
| `tests/integration/flow/test_flow_component_drop_scene.gd` | 存在 CDamage 创建，检查兼容性 |
| `tests/integration/flow/test_flow_composition_cost_scene.gd` | 存在 CDamage 读取，检查兼容性 |

### 审查代码路径
1. `_take_damage()` 的全部调用者（grep `_take_damage\(`）
2. `CDamage.new()` 的全部创建点（grep `CDamage\.new\(\)`）
3. `_add_damage_to_target()` 的全部调用者（grep `_add_damage_to_target\(`）
4. `_queue_damage()` 的全部调用者（grep `_queue_damage\(`）
5. `_apply_melee_hit()` 在 `s_melee_attack.gd` 中的 CDamage 创建
6. `cmd_damage()` 在 `service_console.gd` 中的 CDamage 创建
7. 系统处理顺序：`gol_world.gd` 中 `_load_all_systems()` 的加载方式（filesystem order，无拓扑排序）

### 验证手段
- `grep` 全局搜索所有 `CDamage` 创建和修改点
- `grep` 搜索所有 `_take_damage` 调用者
- 读取 `gol_world.gd` 和 `world.gd` 确认系统执行顺序
- 读取 `materia_damage.tres` 确认 CAreaEffect + CMelee 的组合使用

---

## 验证清单

### 核心逻辑验证
- [x] **CDamage.bypass_invincible 默认值 = false** — 读取 `c_damage.gd:13`，确认 `var bypass_invincible: bool = false`。测试 `test_c_damage.gd:11` 断言 `is_false()`。
- [x] **_take_damage 签名变更向后兼容** — 读取 `s_damage.gd:206`，确认 `bypass_invincible: bool = false` 默认参数。搜索所有 `_take_damage` 调用者：
  - `s_damage.gd:37` — 传 4 个参数 ✅
  - `s_damage.gd:98` — 传 3 个参数，使用默认 false ✅
  - `s_melee_attack.gd` — **不直接调用 `_take_damage`**，通过 CDamage 组件间接触发 ✅
- [x] **invincible_time 检查逻辑正确** — 读取 `s_damage.gd:215`，确认为 `if hp.invincible_time > 0 and not bypass_invincible`。逻辑正确。
- [x] **_process_pending_damage 正确传递 bypass_invincible** — 读取 `s_damage.gd:37`，确认从 `damage.bypass_invincible` 传给 `_take_damage`。

### CDamage 创建点验证
- [x] **s_area_effect_modifier._add_damage_to_target()** — 读取 `s_area_effect_modifier.gd:159-171`。新建和累积两种路径都设置 `bypass_invincible = true`。✅
- [x] **s_elemental_affliction._queue_damage()** — 读取 `s_elemental_affliction.gd:159-170`。新建和累积两种路径都设置 `bypass_invincible = true`。✅
- [x] **s_melee_attack._apply_melee_hit()** — 读取 `s_melee_attack.gd:138-147`。**不设置 `bypass_invincible`**。CDamage 默认 false。符合预期（近战不是 DoT）。
- [x] **service_console.cmd_damage()** — 读取 `service_console.gd:533-536`。**不设置 `bypass_invincible`**，CDamage 默认 false。console 自身已有 invincible_time 检查（line 530-531）。符合预期。
- [x] **integration test CDamage 创建** — 读取 `test_flow_component_drop_scene.gd:73-76`。不设置 bypass_invincible，默认 false。符合预期。

### 架构一致性对照（固定检查项）
- [x] **新增代码是否遵循 planner 指定的架构模式** — `CDamage.bypass_invincible` 是纯数据字段（Component 层），所有逻辑在 System 层修改。符合 ECS 约束。
- [x] **新增文件是否放在 planner 指定的目录，命名是否符合 AGENTS.md 约定** — 新增文件 `tests/unit/test_c_damage.gd`，位于 `tests/unit/` 目录，命名 `test_c_damage.gd` 符合 unit test 约定。
- [x] **是否存在平行实现** — 不存在。所有 DoT 来源统一使用 `_add_damage_to_target` / `_queue_damage` 设置 bypass。
- [x] **测试是否使用 planner 指定的测试模式** — 使用 gdUnit4 `GdUnitTestSuite`，通过 `auto_free` 管理生命周期，符合约定。
- [x] **测试是否验证了真实行为** — 见下方"测试契约检查"。

---

## 发现的问题

### Issue 1: bypass_invincible 的 DoT 持续刷新 invincible_time，阻断非 DoT 伤害

**严重程度**: Critical
**置信度**: High (100%)
**文件**: `scripts/systems/s_damage.gd:229`

**问题描述**:

当 `bypass_invincible=true` 时，`_take_damage()` 成功应用伤害后，**仍然在第 229 行设置 `hp.invincible_time = HURT_INVINCIBLE_TIME (0.3s)`**。

这意味着 DoT 伤害每一帧都会：
1. 绕过 invincible_time 检查 ✅
2. 正常扣血 ✅
3. **重置 invincible_time 为 0.3s** ❌

后果：**只要 DoT 持续作用，invincible_time 就会每帧被刷新为 0.3s，永远不会降到 0。**

这导致在同一帧内或稍后到达的非 DoT 伤害（近战攻击、子弹碰撞）会被 invincible_time 检查（line 215）**完全阻断**。

具体场景：
- 玩家站在毒丧尸的 AoE 范围内（每帧设置 invincible_time = 0.3s）
- 基础丧尸同时近战攻击玩家
- 基础丧尸的 CDamage 走 `_process_pending_damage → _take_damage(bypass=false)` → `invincible_time > 0` → **伤害被跳过**
- 玩家的子弹也无法正常造成伤害

**复现条件**：任何 DoT（毒 AoE 或元素 affliction）与非 DoT 伤害（近战/子弹）同时作用于同一目标。

**建议修复**:
```gdscript
# s_damage.gd, 在 _take_damage 中:
hp.hp = max(0, hp.hp - amount)

# 只有非 bypass 的伤害才设置 invincible_time
if not bypass_invincible:
    hp.invincible_time = HURT_INVINCIBLE_TIME
```

---

### Issue 2: 同一 CDamage 实例被多个来源累积，bypass_invincible 标记被错误覆盖

**严重程度**: Important
**置信度**: High (90%)
**文件**: `scripts/systems/s_area_effect_modifier.gd:163-166`, `scripts/systems/s_melee_attack.gd:139-142`

**问题描述**:

多个系统在同一帧内可以向同一实体的 CDamage 累积伤害。由于所有 `gameplay` 组系统的执行顺序是不确定的（filesystem order，无拓扑排序），以下交叉污染场景可能发生：

**场景 A — DoT 覆盖近战标记**:
1. `SMeleeAttack` 先执行，创建 CDamage（`bypass_invincible = false`，含近战伤害）
2. `SAreaEffectModifier` 后执行，看到已有 CDamage，累积毒伤害并**设置 `bypass_invincible = true`**
3. `SDamage` 处理 CDamage — 近战伤害现在也绕过了 invincible_time

**场景 B — 近战被拉入 DoT 标记**:
1. `SAreaEffectModifier` 先执行，创建 CDamage（`bypass_invincible = true`）
2. `SMeleeAttack` 后执行，累积近战伤害但**不修改 `bypass_invincible`**（保持 true）
3. `SDamage` 处理 CDamage — 近战伤害也绕过了 invincible_time

两种场景都导致近战伤害意外绕过 invincible_time 保护。

**额外影响**: `materia_damage.tres` 的 CAreaEffect + CMelee 组合也会触发此问题（`apply_melee = true`，通过 `_add_damage_to_target` 创建 bypass CDamage）。

**建议修复**:

方案一（推荐）：不再累积到现有 CDamage，每个来源创建独立的 CDamage 实例。但这需要 SDamage 支持处理多个 CDamage。

方案二：`SMeleeAttack._apply_melee_hit` 在累积时显式设置 `bypass_invincible = false`，确保近战伤害标记不被覆盖。但这仍无法解决场景 B（先创建 DoT CDamage，后累积近战）。

方案三：SDamage 对每个 damage source 分别处理，而非将所有累积到一个 CDamage。这是架构层面较大的改动。

---

### Issue 3: area melee 伤害（materia_damage）也绕过 invincible_time

**严重程度**: Minor
**置信度**: High (95%)
**文件**: `scripts/systems/s_area_effect_modifier.gd:128-134`, `resources/recipes/materia_damage.tres`

**问题描述**:

`_apply_melee_damage` 调用 `_add_damage_to_target`（line 134），后者始终设置 `bypass_invincible = true`。`materia_damage.tres` 配置了 `CAreaEffect + CMelee` + `apply_melee = true`，这意味着玩家装备伤害魔晶石后的 area melee 效果也会绕过 invincible_time。

这可能不是设计意图 — area melee 是持续性伤害但不是传统意义上的 DoT（毒、火焰、闪电）。需要确认这是否是有意为之。

---

## 测试契约检查

| 测试契约 | 状态 | 覆盖质量 |
|----------|------|----------|
| CDamage.bypass_invincible 字段存在且默认 false | ✅ 已覆盖 | `test_c_damage.gd:6-11` — 测试默认值 ✅ |
| SDamage._take_damage 在 bypass_invincible=true 时跳过 invincible_time | ✅ 已覆盖 | `test_damage_system.gd:72-82` — 测试 HP 从 25 降到 15，验证伤害实际应用 ✅ |
| SAreaEffectModifier._add_damage_to_target 创建的 CDamage 带 bypass_invincible=true | ✅ 已覆盖 | `test_area_effect_modifier.gd:398-407` — 新建路径 + 累积路径都有覆盖 ✅ |
| SElementalAffliction._queue_damage 创建的 CDamage 带 bypass_invincible=true | ✅ 已覆盖 | `test_elemental_affliction_system.gd:116-146` — 新建路径 + 累积路径都有覆盖 ✅ |
| E2E 验证：毒丧尸毒伤害实际 DPS | ❌ 未覆盖 | 需要 AI Debug Bridge，标注为 post-merge 验证 |
| E2E 验证：毒丧尸近战攻击正常 | ❌ 未覆盖 | 需要 AI Debug Bridge，标注为 post-merge 验证 |
| 回归测试：普通丧尸近战攻击不受影响 | ❌ 未覆盖 | — |
| 回归测试：元素 DoT 伤害仍然正常 | ❌ 未覆盖 | — |

**测试质量评估**：

单元测试覆盖了新增代码的 happy path（bypass_invincible 的创建和传递）。但存在以下盲区：

1. **未测试 bypass_invincible 不影响默认行为**：缺少一个测试验证 `_add_damage_to_target` 之外创建的 CDamage（如 `SMeleeAttack` 或 `ServiceConsole`）bypass_invincible 保持 false。
2. **未测试 CDamage 累积时的标记冲突**（对应 Issue 2）：没有测试验证当 `SMeleeAttack` 和 `SAreaEffectModifier` 同时向同一实体累积 CDamage 时，`bypass_invincible` 标记不会泄漏。
3. **未测试 bypass 伤害后 invincible_time 的行为**（对应 Issue 1）：没有测试验证 `bypass_invincible=true` 造成伤害后，`invincible_time` 是否被设置，以及这是否影响了后续非 bypass 伤害。
4. **E2E 测试全部缺失**：4 项 E2E 测试契约均未覆盖。虽然 coder 文档说明了依赖 AI Debug Bridge，但这意味着关键的运行时行为（DoT + 近战同时作用、invincible_time 刷新）完全没有自动化验证。

---

## 结论

**`rework`**

发现 1 个 Critical 问题和 1 个 Important 问题，必须在合并前修复：

1. **Critical — invincible_time 被持续刷新**：`bypass_invincible` 的 DoT 伤害每帧重置 `invincible_time`，导致同时作用于同一目标的非 DoT 伤害（近战、子弹）被完全阻断。修复方案：当 `bypass_invincible=true` 时，不设置 `invincible_time`。

2. **Important — CDamage 累积导致 bypass 标记泄漏**：同一帧内多个系统向同一 CDamage 累积伤害时，`bypass_invincible` 标记会被污染。近战伤害可能意外绕过 invincible_time。需要评估修复方案（最小改动：`SMeleeAttack` 累积时显式设置 `bypass_invincible = false`）。
