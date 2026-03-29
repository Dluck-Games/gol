# 06 — Adversarial Review R2: bypass_invincible invincible_time fix

## 审查范围

### 审查文件（全部完整阅读）

| 文件 | 角色 |
|------|------|
| `scripts/components/c_damage.gd` | 新增 `bypass_invincible` 字段（R1） |
| `scripts/systems/s_damage.gd` | R1: bypass 参数 + R2: 条件化 invincible_time/hit_blink |
| `scripts/systems/s_area_effect_modifier.gd` | R1: 设置 `bypass_invincible = true` |
| `scripts/systems/s_elemental_affliction.gd` | R1: 设置 `bypass_invincible = true` |
| `scripts/systems/s_melee_attack.gd` | **未修改**，验证兼容性（CDamage 创建不设 bypass） |
| `scripts/services/impl/service_console.gd` | **未修改**，验证兼容性（CDamage 创建不设 bypass） |
| `resources/recipes/enemy_poison.tres` | R1: `damage_per_sec` 3.0 → 8.0 |
| `tests/unit/test_c_damage.gd` | R1: CDamage 默认值 + 自定义值测试 |
| `tests/unit/system/test_damage_system.gd` | R1+R2: bypass 逻辑 + invincible_time 行为测试 |
| `tests/unit/system/test_area_effect_modifier.gd` | R1: bypass_invincible 创建 + 累积测试 |
| `tests/unit/system/test_elemental_affliction_system.gd` | R1: bypass_invincible 创建 + 累积测试 |

### 审查代码路径

1. `_take_damage()` 的全部调用者 — grep `_take_damage\(` 找到 2 个源码调用点（`s_damage.gd:37`, `s_damage.gd:98`）
2. `CDamage.new()` 的全部创建点 — grep 找到 8 个创建点（4 个系统/服务 + 4 个测试）
3. `_add_damage_to_target()` 的全部调用者（grep 确认仅 `s_area_effect_modifier.gd` 内部调用）
4. `_queue_damage()` 的全部调用者（grep 确认仅 `s_elemental_affliction.gd` 内部调用）
5. `_play_hit_blink()` 的全部调用点 — grep 找到 3 个：console invincibility 调试路径（`s_damage.gd:230`）、主路径（`s_damage.gd:262`，已条件化）
6. `_apply_knockback()` 在 bypass 路径下的行为 — 确认 DoT 的 `knockback_direction=Vector2.ZERO` 被 `_apply_knockback` 内部检查跳过（`s_damage.gd:548`）
7. bypass 泄漏场景追踪 — 验证 DoT + 近战同帧累积时的完整执行路径

### 验证手段

- `grep -n "_take_damage\("` — 找到所有调用点，验证向后兼容
- `grep -n "CDamage\.new\(\)"` — 找到所有 CDamage 创建点，验证 bypass_invincible 赋值
- `grep -n "bypass_invincible"` — 全局搜索所有引用
- `grep -n "_play_hit_blink"` — 确认 hit_blink 调用点数量和位置
- 完整读取 `s_damage.gd` 588 行 — 逐行验证 _take_damage 完整逻辑
- 完整读取 `s_area_effect_modifier.gd` 172 行 — 验证 _add_damage_to_target 新建和累积两个路径
- 完整读取 `s_elemental_affliction.gd` 237 行 — 验证 _queue_damage 新建和累积两个路径
- 完整读取 `s_melee_attack.gd:130-154` — 验证 _apply_melee_hit 不设置 bypass_invincible
- 完整读取 `service_console.gd:525-538` — 验证 cmd_damage 不设置 bypass_invincible
- `gh pr checks 225` — 确认 CI 通过状态

---

## 验证清单

### R1 修复验证（第一轮 reviewer 03 发现的问题已修复确认）

- [x] **Critical Issue 1 已修复：bypass_invincible 的 DoT 不再刷新 invincible_time**
  - 动作：读取 `s_damage.gd:238-239`，确认 `hp.invincible_time = HURT_INVINCIBLE_TIME` 包裹在 `if not bypass_invincible:` 块中
  - 动作：读取 `s_damage.gd:261-262`，确认 `_play_hit_blink(target_entity)` 包裹在 `if not bypass_invincible:` 块中
  - 动作：追踪 DoT 伤害的完整执行路径（line 233 → 238 → 249 → 261 → 265 → 267），确认 invincible_time 和 hit_blink 被正确跳过

- [x] **Important Issue 2 决策复核：接受 bypass 泄漏作为架构权衡**
  - 动作：读取 `s_damage.gd:206-212` 的架构注释，确认内容准确描述了 CDamage 单实例 + bypass 泄漏的权衡
  - 动作：验证推理正确性：bypass 不设 invincible_time → 泄漏导致的近战绕过无害（下一帧无 invincible_time 阻挡）
  - 动作：确认 `_apply_knockback` 不在 bypass 块内（`s_damage.gd:265`），DoT + 近战累积时 knockback 仍正常应用（近战覆盖 knockback_direction）

### 核心逻辑验证

- [x] **CDamage.bypass_invincible 默认值 = false** — 读取 `c_damage.gd:13`，确认 `var bypass_invincible: bool = false`。测试 `test_c_damage.gd:11` 断言 `is_false()`。
- [x] **_take_damage 签名变更向后兼容** — 读取 `s_damage.gd:213`，确认 `bypass_invincible: bool = false` 默认参数。验证所有调用者：
  - `s_damage.gd:37`（_process_pending_damage） — 传 4 个参数 ✅
  - `s_damage.gd:98`（_process_bullet_collision） — 传 3 个参数，使用默认 false ✅
  - `s_melee_attack.gd` — 不直接调用 `_take_damage`，通过 CDamage 间接触发 ✅
- [x] **invincible_time 检查逻辑正确** — 读取 `s_damage.gd:222`，确认为 `if hp.invincible_time > 0 and not bypass_invincible`
- [x] **_process_pending_damage 正确传递 bypass_invincible** — 读取 `s_damage.gd:37`，确认 `damage.bypass_invincible` 传给 `_take_damage`

### CDamage 创建点验证

- [x] **s_area_effect_modifier._add_damage_to_target()** — 新建路径（`line 168-171`）和累积路径（`line 164-166`）都设置 `bypass_invincible = true` ✅
- [x] **s_elemental_affliction._queue_damage()** — 新建路径（`line 164-167`）和累积路径（`line 169-170`）都设置 `bypass_invincible = true` ✅
- [x] **s_melee_attack._apply_melee_hit()** — 读取 `s_melee_attack.gd:138-147`，**不设置 `bypass_invincible`**，CDamage 默认 false ✅
- [x] **service_console.cmd_damage()** — 读取 `service_console.gd:533-536`，**不设置 `bypass_invincible`** ✅
- [x] **integration test CDamage 创建** — `test_flow_component_drop_scene.gd:73` 和 `test_flow_blueprint_drop_scene.gd:58` 不设置 bypass ✅

### 副作用追踪

- [x] **Console invincibility 仍正常工作** — 读取 `s_damage.gd:226-231`，console invincibility 检查在 bypass 之后、damage application 之前，仍正确阻断伤害。hit_blink 在 console 路径独立调用（`line 230`），与 bypass guard（`line 261`）是不同代码路径，不会冲突。
- [x] **Spawner enrage 不受影响** — 读取 `s_damage.gd:241-247`，`damage_enraged` 标志确保仅触发一次 ✅
- [x] **Fire intensity reduction** — `s_damage.gd:249-257` 对所有伤害生效（包括 bypass），但这是 pre-existing 逻辑，bypass 放大了效果（DoT 每帧而非每 0.3s 减少火强度），幅度极小（~0.096/sec），不构成实际问题
- [x] **Death check** — `s_damage.gd:267-268` 在 bypass 路径正常工作，DoT 致死正确触发 ✅
- [x] **_apply_knockback 不在 bypass 块内** — `s_damage.gd:265` 在 bypass 条件块外，DoT 的 direction=ZERO 被 `_apply_knockback` 内部检查跳过（`s_damage.gd:548`）✅

### 架构一致性对照（固定检查项）

- [x] **新增代码是否遵循 planner 指定的架构模式** — `CDamage.bypass_invincible` 是纯数据字段（Component 层），所有逻辑在 System 层修改。符合 ECS "Component = pure data, System = logic" 约束。
- [x] **新增文件是否放在 planner 指定的目录，命名是否符合 AGENTS.md 约定** — 新增文件 `tests/unit/test_c_damage.gd`，位于 `tests/unit/` 目录，命名符合 unit test 约定（`test_<component_name>.gd`）。
- [x] **是否存在平行实现** — 不存在。所有 DoT 来源统一使用 `_add_damage_to_target`（area effect）或 `_queue_damage`（elemental）设置 bypass，无重复逻辑。
- [x] **测试是否使用 planner 指定的测试模式** — 使用 gdUnit4 `GdUnitTestSuite`，通过 `auto_free` 管理生命周期。符合 `tests/AGENTS.md` 约定。
- [x] **测试是否验证了真实行为** — 所有 10 个新增测试断言具体状态值（hp、invincible_time、amount、bypass_invincible flag），非空壳 `assert_true(true)`。详见下方"测试契约检查"。

---

## 发现的问题

未发现问题。

**补充观察（非阻塞，已记录的已知行为）：**

1. **bypass 泄漏导致近战 hit_blink 缺失**（已接受的权衡）：当 DoT + 近战同帧命中同一目标时，bypass=true 泄漏到近战伤害，导致近战的 `_play_hit_blink` 也不触发。这是 `if not bypass_invincible` 包裹 hit_blink 的直接后果。planner 04 文档和 `s_damage.gd:206-212` 的注释已记录此权衡。此时目标已在持续 DoT 中（有独立的视觉反馈：毒雾、火焰特效等），hit_blink 缺失的影响极小。

2. **Fire intensity reduction 频率提升**（pre-existing 设计问题）：`s_damage.gd:253` 的火强度减少逻辑对所有伤害生效。bypass 使 DoT 不再被 invincible_time 节流，导致火强度减少频率从 ~3.3次/秒 提升到 60次/秒。但每次减少量极小（`amount * 0.02`，毒 AoE 每帧仅减少 0.0016），总增幅 ~0.096/sec，远小于火强度的自然衰减（0.15/sec），不构成平衡性问题。

3. **materia_damage area melee 绕过 invincible_time**（已评估为合理行为）：`_apply_melee_damage`（`s_area_effect_modifier.gd:128-134`）通过 `_add_damage_to_target` 创建 bypass=true 的 CDamage。Area melee 是持续性范围伤害，bypass 行为合理。

---

## 测试契约检查

### R1 测试契约（来自 01-planner）

| 测试契约 | 状态 | 验证 |
|----------|------|------|
| CDamage.bypass_invincible 字段存在且默认 false | ✅ 已覆盖 | `test_c_damage.gd:6-11` — 断言 3 个字段默认值 ✅ |
| SDamage._take_damage 在 bypass_invincible=true 时跳过 invincible_time | ✅ 已覆盖 | `test_damage_system.gd:72-82` — invincible_time=1.0 时 HP 从 25 降到 15 ✅ |
| SAreaEffectModifier._add_damage_to_target 创建的 CDamage 带 bypass_invincible=true | ✅ 已覆盖 | `test_area_effect_modifier.gd:399-407` — 新建路径 ✅ |
| SElementalAffliction._queue_damage 创建的 CDamage 带 bypass_invincible=true | ✅ 已覆盖 | `test_elemental_affliction_system.gd:116-128` — 新建路径 ✅ |
| E2E：毒丧尸持续可感知毒伤害 | ❌ 未覆盖 | 需 AI Debug Bridge，post-merge 验证 |
| E2E：毒丧尸近战攻击正常 | ❌ 未覆盖 | 需 AI Debug Bridge，post-merge 验证 |
| 回归：普通丧尸近战不受影响 | ❌ 未覆盖 | 需 E2E 场景 |
| 回归：元素 DoT 仍然正常 | ❌ 未覆盖 | 需 E2E 场景 |

### R2 测试契约（来自 04-planner）

| 测试契约 | 状态 | 验证 |
|----------|------|------|
| bypass_invincible=true 时不设置 invincible_time | ✅ 已覆盖 | `test_damage_system.gd:85-96` — invincible_time 从 0.0 保持 0.0 ✅ |
| bypass_invincible=true 时保留现有 invincible_time | ✅ 已覆盖 | `test_damage_system.gd:99-110` — invincible_time 从 0.5 保持 0.5 ✅ |
| bypass_invincible=false 时正常设置 invincible_time | ✅ 已覆盖 | `test_damage_system.gd:113-124` — invincible_time 设为 HURT_INVINCIBLE_TIME ✅ |
| bypass_invincible=true 时不触发 hit_blink | ⚠️ 代码已覆盖 | `s_damage.gd:261` — `_play_hit_blink` 在 `if not bypass_invincible:` 块内。hit_blink 依赖 scene tree，难以单元测试，但代码逻辑已验证正确 |
| E2E：DoT 期间非 DoT 伤害正常命中 | ❌ 未覆盖 | 需 AI Debug Bridge |
| E2E：DoT 期间无视觉闪烁刷屏 | ❌ 未覆盖 | 需 AI Debug Bridge |
| E2E：普通近战仍正确设置 invincible_time | ❌ 未覆盖 | 需 AI Debug Bridge |
| E2E：元素 DoT 正常工作 | ❌ 未覆盖 | 需 AI Debug Bridge |

### 测试质量评估

**单元测试（10 个新增用例）质量良好：**
- 所有测试验证具体状态值（hp、invincible_time、amount、bypass_invincible），非空壳断言
- 覆盖了新建路径和累积路径两个分支
- 回归测试（`test_take_damage_returns_true_for_invincible_hp_target`）确认默认行为未变
- `test_bypass_invincible_does_not_reset_existing_invincible_time` 测试了边界条件（已有 invincible_time 被保留）

**测试盲区（已记录，可接受）：**
- bypass 泄漏场景（DoT + 近战同帧累积）— 已文档化为架构权衡，无独立测试
- hit_blink 抑制 — 代码逻辑已包含在 bypass 条件块中，但无 mock 验证
- 4 项 E2E 契约依赖 AI Debug Bridge，无法在无头模式下自动验证

### CI 状态

- **Unit Tests**: ✅ pass (50s)
- **Integration Tests**: ✅ pass (39s)

---

## 结论

**`verified`**

所有检查通过，实现正确。具体确认：

1. R1 reviewer 03 发现的 Critical 问题（invincible_time 持续刷新阻断非 DoT 伤害）已通过 `if not bypass_invincible:` 条件块正确修复（`s_damage.gd:238-239`, `s_damage.gd:261-262`）
2. R1 reviewer 03 发现的 Important 问题（bypass 泄漏）已被 planner 正确评估并接受为架构权衡，代码注释准确记录了决策理由
3. 所有 `_take_damage` 调用者使用正确的参数，CDamage 创建点的 bypass_invincible 赋值均正确
4. 10 个新增单元测试验证真实行为，CI 全部通过
5. 未发现新的 Critical/Important/Minor 问题
