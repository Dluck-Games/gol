# 交接文档：冻结伤害后移动动画丢失

> **Issue:** #195
> **角色:** Planner → Coder
> **日期:** 2026-04-04

---

## 本轮结论摘要

Issue #195（冻结伤害后移动动画丢失）已完成根因分析。**确认存在 3 个 Bug**，其中 **Bug-1（CRITICAL）是主因**：`SAnimation._update_animation()` 中无敌帧的 early-return 位于解冻恢复逻辑之前，导致冻结在无敌帧期间结束时，sprite 永远无法取消暂停。

典型触发场景：实体处于冻结状态时受到火/电元素 DoT 持续伤害 → `invincible_time=0.3s` 被设置 → 冻结计时器恰好在此期间耗尽 → `forbidden_move=false` 但 `_update_animation()` 在 line 71 处 return，跳过了 line 100-102 的 `paused=false` 恢复代码 → 视觉上"滑行"。

另有 **Bug-2（MODERATE）**：解冻时 `max_speed` 未恢复到 base_speed，导致速度持续偏低、velocity 难以建立，间接造成动画停留在 idle。**Bug-3（MINOR）**：冻结时 velocity 被归零但解冻时不处理，配合 Bug-2 加剧问题。

修复方案涉及 **2 个文件各改 ~5 行 + 补充 3 个测试用例**，改动量极小且风险可控。

---

## 推荐 coder 先看的文件/函数

### 必读（按顺序）

1. **`scripts/systems/s_animation.gd:55-108`** — `_update_animation()` 完整方法
   - 这是 Bug-1 所在位置，理解 line 68-77 的三个检查优先级链是关键

2. **`scripts/systems/s_elemental_affliction.gd:171-208`** — `_apply_movement_modifiers()` 方法
   - 这是 Bug-2 所在位置，重点看 line 186-195（已冻结路径）vs line 206-208（比例减速路径）的区别

3. **`tests/unit/system/test_animation_freeze_recovery.gd`** — 现有 7 个测试用例
   - 理解现有测试覆盖范围和 mock 模式，新增用例需保持一致风格

### 可选参考

4. **`scripts/systems/s_damage.gd:226-229`** — 理解 `invincible_time = 0.3` 的设置点
5. **`scripts/components/c_animation.gd`** — `animation_was_paused` 字段定义
6. **`scripts/components/c_movement.gd`** — `forbidden_move`, `max_speed`, `base_max_speed` 字段定义

---

## 关键风险与测试契约摘要

### 风险
- Fix-1 将解冻恢复逻辑提升到无敌帧 return 之前——仅做 `sprite.paused = false`，不改变动画选择或翻转向量，影响面最小
- 死亡流程不受影响（CDead 检查在最前面）
- Fix-2 的 max_speed 恢复是状态转换点的合理行为

### 测试契约
- 现有 T1-T7 测试 **必须全部通过**（回归保护）
- 新增 T8/T9/T10 覆盖无敌帧+冻结交叉场景（详见主计划第 5 章）
- 不需要集成/E2E 测试（此 bug 是系统间时序问题，单元测试可完整模拟）

---

## 详细方案

完整实现方案、代码 diff、架构约束、风险分析见：
**`/Users/dluckdu/Documents/Github/gol/docs/foreman/195/plans/01-planner-freeze-animation-loss.md`**
