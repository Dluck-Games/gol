# Issue #198 交接文档：雷属性组件拾取/受击效果优化

> **日期**: 2026-04-05
> **来源**: Planner Agent
> **接收**: TL / Coder
> **状态**: 规划完成，待实现

---

## 一、本轮结论摘要

Issue #198 的三个问题根因已全部定位：

**P1（拾取后准星颤抖）**：`SElectricSpreadConflict` 对所有持武者无差别施加 +15° 散射惩罚。玩家拾取 Electric 武器后被误伤。

**P2（被击中无准星干扰）**：`SElementalAffliction` 的 Electric 分支只做 DoT 伤害 `_queue_damage()`，缺少对 CAim 组件的副作用写入。Cold 元素有完整的 movement modifier 系统（冻结/减速），但 Electric 没有对应的 aim disturbance 系统。

**P3（Tracker 与 Electric 交互空白）**：两系统各自独立运行无交叉感知。STrackLocation 的 `_update_display_aim()` 会读取被 SElectricSpreadConflict 放大的 `weapon.spread_degrees`，导致追踪准星也抖动。

**核心设计纠正**：Electric 的瞄准干扰应从"主动持有代价"改为"被动 affliction 效果"。即——拾取 Electric 武器不应自我惩罚；被敌人 Electric 命中后才应出现准星干扰。

详细方案见：`/Users/dluckdu/Documents/Github/gol/docs/foreman/198/plans/01-planner-electric-pickup-hit-fix.md`

---

## 二、推荐 Coder 先看的文件/函数

### 必读（按阅读顺序）

| 序号 | 文件 | 行号/函数 | 看什么 |
|------|------|-----------|--------|
| 1 | `scripts/systems/s_electric_spread_conflict.gd` | `16-32` `_process_entity()` | **P1 根因**：无条件施加 spread |
| 2 | `scripts/systems/s_elemental_affliction.gd` | `87-97` `_apply_tick_effect()` | **P2 根因**：Electric 只有 _queue_damage |
| 3 | `scripts/systems/s_elemental_affliction.gd` | `171-209` `_apply_movement_modifiers()` | **参考模式**：Cold 是怎么写 movement 副作用的，Electric 的 aim disturbance 应参照此模式 |
| 4 | `scripts/components/c_aim.gd` | 全文件 | **数据层**：需扩展新字段 `electric_affliction_jitter` |
| 5 | `scripts/systems/s_crosshair.gd` | `44-87` `_update_display_aim()` | **消费端**：jitter 计算逻辑，需叠加 affliction 值 |
| 6 | `scripts/systems/s_track_location.gd` | `110-153` `_update_display_aim()` | **消费端2**：与 SCrosshair 几乎同构的 jitter 逻辑 |

### 参考阅读

| 文件 | 理由 |
|------|------|
| `scripts/systems/s_cold_rate_conflict.gd` | 另一个 cost system 的阵营判断写法（如有） |
| `tests/unit/system/test_electric_spread_conflict.gd` | 现有测试，需要更新断言 |
| `tests/unit/system/test_elemental_affliction_system.gd` | 现有测试，需要扩展新 case |
| `scripts/configs/config.gd: ELECTRIC_SPREAD_DEGREES` | 现有常量位置，新增常量放旁边 |

---

## 三、关键风险与测试契约摘要

### 风险要点

1. **执行顺序依赖**: SElementalAffliction（写入 jitter）必须在 SCrosshair/STrackLocation（读取 jitter）之前执行。当前字母序 `s_elemental_affliction < s_crosshair < s_track_location` 满足要求。**不要重命名文件破坏此顺序**。
2. **Config 数值待调优**: `ELECTRIC_AIM_DISTURBANCE_BASE_DEGREES=8.0`, `MAX_DEGREES=20.0` 是初始建议值，需 E2E 微调。
3. **Tracker 衰减方案可选**: 推荐半衰减（×0.5），但 TL 可能选择完全免疫。切换只需改 STrackLocation 一处 if。
4. **旧测试必断言失效**: `test_electric_adds_spread` 当前隐含"所有实体都受 spread"假设，修改后必须区分 player/enemy。

### 测试契约（必须通过的断言）

**P1 修复验证**:
- [ ] `CCamp=PLAYER` + `CWeapon` + `CElementalAttack[ELECTRIC]` → `spread_degrees == base_spread_degrees`
- [ ] `CCamp=ENEMY` + 同上 → `spread_degrees == base + 15°` (capped at 30°)
- [ ] 无 CCamp 组件 → 保持原行为（防御性）

**P2 新功能验证**:
- [ ] 有 `CAim` + `CElementalAffliction[ELECTRIC]` intensity > 0 → `electric_affliction_jitter > 0`
- [ ] jitter 与 intensity 成正比，有上限
- [ ] 无 CAim → 不崩溃
- [ ] Electric entry 清除/过期 → jitter 归零
- [ ] Fire/Wet/Cold → jitter = 0

**P3 共存验证**:
- [ ] CTracker + Electric 武器 → 无来自 weapon 的 spread（P1 成果）
- [ ] CTracker + Electric affliction → jitter 受衰减（或完全免疫，按 TL 决策）
- [ ] SCrosshair 和 STrackLocation 都正确叠加 jitter

**回归验证**:
- [ ] 现有 Cold freeze 功能不受影响
- [ ] Electric DoT 伤害不变
- [ ] Electric 传播链不变
- [ ] CrosshairView 电击渲染正常响应 spread_ratio 变化

---

## 四、实现步骤概要

详见 plans 目录下的主计划文档。简述如下：

| Phase | 内容 | 改动文件数 | 复杂度 |
|-------|------|-----------|--------|
| Phase 1 | P1 修复：SElectricSpreadConflict 加阵营判断 | 2 个文件（系统+测试） | 低 |
| Phase 2 | P2+P3：新增 affliction-driven aim disturbance | ~7 个文件 | 中 |
| Phase 3 | 集成测试 + E2E 验证 | 新建 ~2 个测试文件 | 中 |

总改动约 **5 个源文件 + 4~5 个测试文件**，无新文件创建（除测试）。
