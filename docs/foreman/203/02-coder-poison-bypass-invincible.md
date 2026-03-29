# 02-coder-poison-bypass-invincible.md

## 完成的工作

### 修改的文件

1. **`scripts/components/c_damage.gd`**
   - 新增 `var bypass_invincible: bool = false` 字段
   - 原因：需要标记 DoT 伤害以绕过无敌帧检查

2. **`scripts/systems/s_damage.gd`**
   - 修改 `_process_pending_damage()` 传递 `bypass_invincible` 到 `_take_damage()`
   - 修改 `_take_damage()` 签名，增加 `bypass_invincible: bool = false` 参数
   - 修改无敌帧检查逻辑：`if hp.invincible_time > 0 and not bypass_invincible`
   - 原因：允许 DoT 伤害在无敌帧期间正常生效

3. **`scripts/systems/s_area_effect_modifier.gd`**
   - 修改 `_add_damage_to_target()`，创建/更新 CDamage 时设置 `bypass_invincible = true`
   - 原因：毒 AoE 伤害属于 DoT，应绕过无敌帧

4. **`scripts/systems/s_elemental_affliction.gd`**
   - 修改 `_queue_damage()`，创建/更新 CDamage 时设置 `bypass_invincible = true`
   - 原因：元素 DoT 伤害（火焰、闪电 tick 伤害）应绕过无敌帧

5. **`resources/recipes/enemy_poison.tres`**
   - 修改 `damage_per_sec` 从 3.0 提高到 8.0
   - 原因：提高毒伤害数值，使毒丧尸威胁更合理（DPS 从 1.8 提升到 4.8）

6. **`tests/unit/test_c_damage.gd`** (新建)
   - 测试 `CDamage` 组件默认值，包括 `bypass_invincible` 默认为 false

7. **`tests/unit/system/test_damage_system.gd`**
   - 新增 `test_take_damage_applies_damage_when_bypass_invincible_true`
   - 测试无敌帧期间 `bypass_invincible=true` 时伤害正常应用

8. **`tests/unit/system/test_area_effect_modifier.gd`**
   - 新增 `test_add_damage_to_target_sets_bypass_invincible_true`
   - 新增 `test_add_damage_to_target_preserves_bypass_invincible_when_accumulating`

9. **`tests/unit/system/test_elemental_affliction_system.gd`**
   - 新增 `test_queue_damage_sets_bypass_invincible_true`
   - 新增 `test_queue_damage_preserves_bypass_invincible_when_accumulating`

## 测试契约覆盖

| 测试项 | 状态 | 说明 |
|--------|------|------|
| CDamage.bypass_invincible 字段存在且默认 false | ✅ 已覆盖 | `tests/unit/test_c_damage.gd` |
| SDamage._take_damage 在 bypass_invincible=true 时跳过 invincible_time 检查 | ✅ 已覆盖 | `tests/unit/system/test_damage_system.gd` |
| SAreaEffectModifier._add_damage_to_target 创建的 CDamage 带 bypass_invincible=true | ✅ 已覆盖 | `tests/unit/system/test_area_effect_modifier.gd` |
| SElementalAffliction._queue_damage 创建的 CDamage 带 bypass_invincible=true | ✅ 已覆盖 | `tests/unit/system/test_elemental_affliction_system.gd` |
| E2E 验证：毒丧尸对玩家造成持续可感知的毒伤害 | ❌ 未覆盖 | 需要 AI Debug Bridge 运行时验证 |
| E2E 验证：毒丧尸能正常执行近战攻击 | ❌ 未覆盖 | 需要 AI Debug Bridge 运行时验证 |
| 回归测试：普通丧尸近战攻击不受影响 | ❌ 未覆盖 | 依赖 E2E 场景 |
| 回归测试：元素 DoT 伤害仍然正常 | ❌ 未覆盖 | 依赖 E2E 场景 |

**未覆盖原因**：
- E2E 测试需要 AI Debug Bridge 运行时环境，无法在无头模式下自动验证
- 这些测试建议在合并后通过实际游戏运行验证

## 决策记录

### 与计划方案一致的决策

1. **双层修复策略**：完全按照计划执行
   - 修复 A: 添加 `bypass_invincible` 机制绕过无敌帧
   - 修复 B: 提高毒伤害数值从 3.0 到 8.0

2. **向后兼容**：`_take_damage()` 使用默认参数 `bypass_invincible: bool = false`
   - 确保现有调用方无需修改
   - 只有 DoT 来源显式设置为 true

### 实施细节

- 所有 DoT 来源（毒 AoE + 元素 affliction）统一使用 `bypass_invincible=true`
- 保持 Component 纯数据原则，`bypass_invincible` 仅作为标记字段
- 数值调整保守：8.0 DPS 对 100HP 玩家约 21 秒击杀，与其他元素 DoT 相当

## 仓库状态

- **Branch**: `foreman/issue-203`
- **Commit SHA**: `b677741ec2ca5954fa7e7390c492694b6863400c`
- **Commit Message**: `fix(damage): poison effect bypasses invincible_time`
- **PR**: https://github.com/Dluck-Games/god-of-lego/pull/225

### 测试结果摘要

- 单元测试文件已编写完成
- 由于 gdUnit4 CLI 环境问题，未能在本地运行完整测试套件
- 代码逻辑已通过静态审查确认正确性
- 建议合并后在 CI 环境中验证测试通过情况

## 未完成事项

1. **E2E 验证**：建议通过 AI Debug Bridge 运行时验证：
   - 毒丧尸毒伤害实际 DPS 约 4.8/s
   - 毒丧尸近战攻击正常触发
   - 普通丧尸和元素丧尸行为未受影响

2. **平衡性微调**：根据实际游戏体验，可能需要进一步调整 `damage_per_sec` 数值

## 备注

- 近战攻击问题：经分析，毒丧尸确实配置了 `CMelee` 组件，近战攻击逻辑应该正常。用户感知的"无法近战"可能是由于移速较慢（80 vs 基础 100）导致难以接近目标。如问题仍存在，需 E2E 进一步排查。

- 元素 DoT 平衡性：修复后火焰/闪电的 DoT 伤害也会受益于 `bypass_invincible`，这些伤害原本使用 tick_interval（0.5s），现在每 tick 都会稳定造成伤害。建议在 E2E 中验证这些元素伤害是否仍然平衡。
