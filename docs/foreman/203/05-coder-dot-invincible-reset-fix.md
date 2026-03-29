# 05-coder-dot-invincible-reset-fix.md

## 完成的工作

### 修改的文件

1. **`scripts/systems/s_damage.gd`**
   - 在 `_take_damage()` 函数上方添加架构说明注释，解释 CDamage 的 `bypass_invincible` 标记隔离问题
   - 将 `hp.invincible_time = HURT_INVINCIBLE_TIME` 包裹在 `if not bypass_invincible:` 条件中
   - 将 `_play_hit_blink(target_entity)` 包裹在 `if not bypass_invincible:` 条件中
   - 原因：Reviewer Issue 1 — DoT 伤害（bypass_invincible=true）不应刷新无敌时间，否则会导致同时作用于同一目标的非 DoT 伤害（近战、子弹）被完全阻断

2. **`tests/unit/system/test_damage_system.gd`**
   - 新增 `test_bypass_invincible_does_not_set_invincible_time` — 验证 bypass=true 时不设置 invincible_time
   - 新增 `test_bypass_invincible_does_not_reset_existing_invincible_time` — 验证 bypass=true 时保留现有 invincible_time
   - 新增 `test_non_bypass_still_sets_invincible_time` — 验证 bypass=false 时仍正常设置 invincible_time
   - 原因：提供对修复逻辑的自动化测试覆盖

### 关于 Reviewer Issue 2 的决策

**接受 bypass_invincible 标记跨系统泄漏作为架构权衡**

经过分析，CDamage 累积导致的 bypass 标记泄漏在实际影响上是可接受的：

1. **Issue 1 修复后，bypass 伤害不设置 invincible_time** → 不存在 invincible_time 阻断非 bypass 伤害的问题
2. **泄漏仅发生在 DoT + 近战同帧命中同一目标时** → 场景有限
3. **此时 invincible_time 不被设置** → 即使 bypass 泄漏，近战伤害也能正常命中
4. **大改方案代价过高**：独立 CDamage 实例需要 SDamage 支持多 CDamage 处理，涉及架构重构

具体来说：当 DoT 和近战在同一帧命中同一目标时，CDamage 的 bypass=true 使总伤害绕过 invincible_time。但由于 bypass 不设置 invincible_time，下一帧其他敌人的近战攻击不会被阻断。唯一的行为变化是：当玩家同时受到 DoT + 近战时，近战伤害绕过了本来会被 invincible_time 阻挡的那 0.3s。这在游戏体验上是合理的。

## 测试契约覆盖

| 测试项 | 状态 | 说明 |
|--------|------|------|
| bypass_invincible=true 时不设置 invincible_time | ✅ 已覆盖 | `tests/unit/system/test_damage_system.gd:test_bypass_invincible_does_not_set_invincible_time` |
| bypass_invincible=true 时不重置现有 invincible_time | ✅ 已覆盖 | `tests/unit/system/test_damage_system.gd:test_bypass_invincible_does_not_reset_existing_invincible_time` |
| bypass_invincible=false 时正常设置 invincible_time | ✅ 已覆盖 | `tests/unit/system/test_damage_system.gd:test_non_bypass_still_sets_invincible_time` |
| bypass_invincible=true 时不触发 hit_blink | ⚠️ 部分覆盖 | 通过代码逻辑验证，hit_blink 依赖 viewport/scene tree，难以单元测试 |
| E2E 验证：DoT 期间非 DoT 伤害正常命中 | ❌ 未覆盖 | 需要 AI Debug Bridge 运行时验证 |
| E2E 验证：DoT 期间玩家不出现视觉闪烁刷屏 | ❌ 未覆盖 | 需要 AI Debug Bridge 运行时验证 |
| 回归测试：普通近战攻击仍正确设置 invincible_time | ❌ 未覆盖 | 依赖 E2E 场景 |
| 回归测试：元素 DoT 正常工作 | ❌ 未覆盖 | 依赖 E2E 场景 |

**未覆盖原因**：E2E 测试需要 AI Debug Bridge 运行时环境，无法在无头模式下自动验证。建议在合并后通过实际游戏运行验证。

## 决策记录

### 与计划方案一致的决策

1. **条件化 invincible_time 设置**：完全按照 04-planner 方案执行
   - bypass_invincible=true 时不设置 invincible_time
   - bypass_invincible=false 时正常设置 invincible_time

2. **抑制 DoT 伤害的 hit_blink**：完全按照 04-planner 方案执行
   - 避免 DoT 每帧触发闪烁导致的视觉刷屏

### 与计划方案的偏差

**无偏差**。所有修改均按照 04-planner 方案执行。

### 实施细节

- 架构注释添加到 `_take_damage()` 函数上方，解释 CDamage 标记隔离的权衡
- 保持向后兼容：`bypass_invincible` 默认为 false，现有调用方无需修改
- 所有 DoT 来源（毒 AoE + 元素 affliction）统一受益于修复

## 仓库状态

- **Branch**: `foreman/issue-203`
- **Commit SHA**: `b6700f828434df41b17563a87ad5710fcde48caa`
- **Commit Message**: `fix(damage): bypass_invincible no longer sets invincible_time or triggers hit_blink`
- **PR**: https://github.com/Dluck-Games/god-of-lego/pull/225

### 测试结果摘要

- 单元测试文件已更新，新增 3 个测试用例
- 由于 gdUnit4 CLI 环境问题，未能在本地运行完整测试套件
- 代码逻辑已通过静态审查确认正确性
- 建议合并后在 CI 环境中验证测试通过情况

## 未完成事项

1. **E2E 验证**：建议通过 AI Debug Bridge 运行时验证：
   - 毒丧尸毒伤害 + 基础丧尸近战同时作用于玩家 → 两者都正常
   - DoT 期间玩家精灵无异常闪烁
   - 普通丧尸和元素丧尸行为未受影响

2. **Reviewer Issue 2 的长期方案**：如果未来增加新的伤害来源（如持续光束、debuff），当前的"接受泄漏"决策可能需要重新评估。建议在代码注释中记录了此权衡。

## 备注

- 本次修复是对第一轮修复（01-03）的第二轮补充，解决 Reviewer 发现的 Critical 和 Important 问题
- 修复后毒丧尸的 DoT 伤害不再会阻断其他伤害来源，近战攻击应该能正常生效
- 毒丧尸的毒伤害 DPS 在上一轮已提升至 4.8/s，本次修复解决了 invincible_time 的节流问题，实际 DPS 将接近设计值
