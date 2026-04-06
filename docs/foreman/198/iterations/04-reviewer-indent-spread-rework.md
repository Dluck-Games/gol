# Issue #198 Rework 审查报告：缩进修复与 Spread Clamp 验证

> **审查者**: Reviewer Agent（对抗性代码审查 — Rework 增量轮）
> **日期**: 2026-04-05
> **PR**: #240
> **分支**: foreman/issue-198
> **审查基准**: `02-reviewer-electric-pickup-hit-fix.md` + `03-coder-fix-indent-and-spread.md`

---

## 逐项验证

| # | 原问题 | 修复状态 | 验证方式 |
|---|--------|---------|---------|
| #1 | `[Critical]` `s_elemental_affliction.gd:103` ELECTRIC case 缩进不足（2 tab → 应为 3 tab），导致 ELECTRIC 分支脱离 match 块，每次 tick 无条件执行 | **已修复** | Read 第 100-107 行源码：第 103 行 `ELECTRIC:` 现为 3 tab（与第 101 行 `FIRE:` 同级）；第 104-107 行内容体现为 4 tab。`git diff HEAD~1` 确认 diff 为每行精确 +1 tab（共 5 行）。GDScript 解析器将 ELECTRIC 视为合法 match case。FIRE/COLD/WET 等 case 不受影响（各自缩进未变） |
| #2 | `[Important]` `s_fire_bullet.gd:_get_visual_spread_angle()` clamp 上限仅用 `weapon.spread_degrees`，不含 `electric_affliction_jitter`，导致准星视觉抖动与实际弹道散布不一致 | **已修复** | Read 第 107-115 行源码：新增 `effective_max_spread` 变量，先赋值 `weapon.spread_degrees`，再通过 `if aim_comp:` 安全读取 `aim_comp.electric_affliction_jitter` 并累加。null 安全检查正确（`aim_comp` 为空时不崩溃）。else 分支（无 CAim 组件时）行为未被改变——仍返回 `randf_range(-weapon.spread_degrees, weapon.spread_degrees)` |

---

## 回归检查

### C-A: 缩进修复回归验证

| 检查项 | 结果 |
|--------|------|
| 语法正确性 — GDScript 对缩进敏感，ELECTRIC case 现在是 match 的合法子句 | 通过 |
| FIRE case 未受影响 — 第 101-102 行缩进不变 | 通过 |
| match 块之后的代码（第 109 行空行 + 第 110 行 `_propagate_if_ready`）位置正确 | 通过 |
| 不存在多余/缺失的 tab 导致解析歧义 | 通过 |

### C-B: Spread Clamp 修复回归验证

| 场景 | 预期行为 | 结果 |
|------|----------|------|
| 无 Electric affliction（`jitter=0`） | `effective_max_spread = weapon.spread_degrees + 0`，等同于修复前 | 通过 — 与原始行为一致 |
| 有 CAim 组件但无 affliction | 同上 | 通过 |
| 无 CAim 组件（else 分支） | 返回 `randf_range(-weapon.spread_degrees, weapon.spread_degrees)`，不含 jitter | 通过 — 未被修改 |

### C-D: 测试契约复核

对照 `02-reviewer` 测试契约表：

| 测试断言 | 修复后是否仍应成立 | 说明 |
|----------|-------------------|------|
| `test_electric_applies_aim_disturbance` → jitter > 0 | Pass | 构造 Electric payload 调用 system.process() → match 正确命中 ELECTRIC case → `_apply_electric_aim_disturbance` 被调用 |
| `test_electric_no_jitter_without_aim` → 不崩溃 | Pass | `_apply_electric_aim_disturbance` 内部有 `if aim == null: return` 保护 |
| `test_non_electric_no_jitter` → Fire = 0 | Pass | Fire payload 走 FIRE case（不包含 `_apply_electric_aim_disturbance`），不再因缩进错误而误执行 ELECTRIC 逻辑 |
| `test_clearing_electric_resets_jitter` → 归零 | Pass | `_clear_afflictions` 中 CAim 重置逻辑未被修改（第 229-232 行） |
| Crosshair / Tracker 叠加测试 | Pass | 消费端逻辑未被本次 rework 触及 |
| Spread Conflict 阵营测试 | Pass | P1 逻辑未被本次 rework 触及 |

**关键变化说明**：修复前 `test_non_electric_no_jitter` 等测试"碰巧能通过"的原因是 ELECTRIC case 因缩进错误而成为无条件执行的独立代码块——即使传入 Fire/Wet/Cold 类型也会执行 Electric 逻辑。但这不影响这些特定测试的 pass/fate，因为它们直接构造了正确的 payload 类型并检查结果。修复后这些测试的**通过原因变得语义正确**（Electric 只在匹配 ELECTRIC type 时才触发），断言本身无需修改。

---

## 新发现

### 问题 #N1 — [Minor] `_get_visual_spread_angle()` 存在冗余的组件查询

**置信度**: 100%（直接读取源码确认）

**文件**: `scripts/systems/s_fire_bullet.gd:108-113`

**描述**:

```gdscript
func _get_visual_spread_angle(entity: Entity, weapon: CWeapon) -> float:
	var aim: CAim = entity.get_component(CAim)      # ← 第 108 行：第一次查询
	if aim != null:
		var effective_max_spread := weapon.spread_degrees
		var aim_comp: CAim = entity.get_component(CAim)   # ← 第 111 行：第二次查询同一组件！
		if aim_comp:
			effective_max_spread += aim_comp.electric_affliction_jitter
		return clampf(aim.spread_angle_degrees, -effective_max_spread, effective_max_spread)
```

第 108 行已经获取了 `aim` 并确认非 null；进入 if 分支后，第 111 行又对同一个 entity 再次调用 `get_component(CAim)` 得到 `aim_comp`。两者指向完全相同的组件实例。

**影响**: 纯代码质量问题，无功能 bug。`get_component()` 在 GECS 中是 O(1) hash lookup，性能损耗可忽略。但在同一函数内重复查询相同组件违反 DRY 原则，且增加了维护者阅读时的认知负担。

**建议**（Non-blocking，本轮不阻塞）：将第 111-112 行简化为直接使用已有的 `aim` 变量：
```gdscript
if aim:
    effective_max_spread += aim.electric_affliction_jitter
```

---

## 结论

**`pass`**

两个问题均已按 `02-reviewer` 建议方案正确修复：

1. **[Critical] 缩进修复** — `s_elemental_affliction.gd:103-107` 精确增加 1 tab，ELECTRIC case 现为 match 的合法子句。diff 确认变更范围精确、无副作用。
2. **[Important] Spread Clamp 修复** — `s_fire_bullet.gd:_get_visual_spread_angle()` 新增 `effective_max_spread` 计算含 `electric_affliction_jitter`，null 安全、else 分支保持原行为、无 affliction 时等效于修复前。

回归检查全部通过：缩进修复不引入语法错误，spread 修改不影响无 affliction 场景原始行为，测试契约表所有断言仍应成立。

发现一个 Minor 级别的代码冗余问题（重复 `get_component(CAim)` 查询），不阻塞当前轮次。

可以进入 tester/E2E 阶段。

---

*审查完成时间: 2026-04-05*
