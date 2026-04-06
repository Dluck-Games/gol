# Rework 增量审查报告：Issue #238 — 准心 UI 展示元素伤害类型

**审查者角色**: 对抗性代码审查员（Reviewer）
**审查日期**: 2026-04-06
**目标 PR**: #243
**审查轮次**: 第 2 轮（Rework Review）
**审查范围**: 仅验证问题 #1 和问题 #2 的修复质量 + 回归检查

---

## 逐项验证

| # | 原问题 | 修复状态 | 验证方式 |
|---|--------|---------|---------|
| #1 | `bind_to_entity` else 分支缺少 `element_type.unbind()`，导致残留绑定 | **已修复** | 源码逐行确认 + 不变量验证 |
| #2 | 重绑定 aim_position/spread_ratio 产生冗余 Warning 日志 | **已修复** | 调用链追踪 + 功能等价性分析 |

---

## 问题 #1 详细验证：`crosshair_view_model.gd:32-34`

### 修复内容确认

源码实际状态（`crosshair_view_model.gd:32-34`）：
```gdscript
else:
	element_type.unbind()       # 先断开旧绑定
	element_type.set_value(-1)  # 无元素组件时设为 NONE
```

与 reviewer 建议的修复方案**完全一致**。`unbind()` 在 `set_value(-1)` 之前调用。

### `unbind()` 安全性验证

读取 `observable_property.gd:72-77` 的 `unbind()` 实现：

```gdscript
func unbind() -> void:
	if _bound_other:                                    # 空值安全守卫
		if not _bound_callable.is_null() and _bound_other._changed.is_connected(_bound_callable):
			_bound_other._changed.disconnect(_bound_callable)  # 断开信号
	_bound_other = null                                 # 清空引用
	_bound_callable = Callable()
```

关键发现：
- **空值安全**：第 73 行 `if _bound_other:` 保证对已 unbound 的对象再次调用 `unbind()` 是无操作的（no-op），不会崩溃或产生副作用
- **完整清理**：信号断开 + 引用置空 + callable 清零，三步全部执行

### 不变量验证

**不变量声明**：「当 `has_component` 返回 false 时，`element_type` 应处于 unbound 状态」

验证路径：
1. `has_component(CElementalAttack)` 返回 `false` → 进入 else 分支
2. `element_type.unbind()` 执行后：
   - `element_type._bound_other == null` → `is_bound()` 返回 `false` ✅
3. `element_type.set_value(-1)` 执行后：
   - 值为 `-1`（NONE）✅

**结论：不变量满足。残留绑定问题已消除。**

### 边界场景：首次绑定时的 else 分支

当实体首次绑定时（`setup()` 后第一次 `bind_to_entity()`），如果实体无 `CElementalAttack`：
- `element_type` 初始状态：值为 `-1`，`_bound_other == null`（未绑定）
- `unbind()` 调用 → 因 `_bound_other` 为 null 直接返回（no-op）
- `set_value(-1)` 调用 → 因值相等在 `observable_property.gd:30` 早期返回（no-op）

**结果：首次进入 else 分支完全无害。** ✅

---

## 问题 #2 详细验证：`crosshair.gd:97-105`（`_try_bind_entity` 方法）

### 修复内容确认

源码实际状态：
```gdscript
if has_elemental != _had_elemental_attack:
	# 组件存在性发生变化，只重新绑定 element_type 避免重复绑定警告
	_had_elemental_attack = has_elemental
	if has_elemental:
		_view_model.element_type.unbind()
		_view_model.element_type.bind_component(_bound_entity, CElementalAttack, "element_type")
	else:
		_view_model.element_type.unbind()
		_view_model.element_type.set_value(-1)
	return  # ← 关键：此处 return，不继续执行后续代码
```

采用方案 A（最小改动），与 reviewer 推荐方案一致。

### 分支逐一验证

#### 分支 A：`has_elemental == true`（获得组件）

操作序列：
1. `_view_model.element_type.unbind()` — 断开旧绑定（如有）
2. `_view_model.element_type.bind_component(_bound_entity, CElementalAttack, "element_type")` — 绑定到新组件

等价性对比原始 `bind_to_entity()` 的 if 分支：
- 原始：`element_type.bind_component(entity, CElementalAttack, "element_type")`
- 修复：先 `unbind()` 再 `bind_component(...)`
- 差异：多了一次显式 `unbind()`。但 `bind_observable()` 内部（`observable_property.gd:61-62`）已有 `if is_bound(): unbind()` 自动处理，所以此处的显式 `unbind()` 是冗余但无害的操作
- **功能等价**：最终效果一致 ✅

#### 分支 B：`has_elemental == false`（失去组件）

操作序列：
1. `_view_model.element_type.unbind()` — 断开旧绑定
2. `_view_model.set_value(-1)` — 重置为 NONE

与 `bind_to_entity()` else 分支**完全一致** ✅

### Warning 日志消除验证

**原问题根因**：`_view_model.bind_to_entity(_bound_entity)` 会重新调用 `aim_position.bind_component()` 和 `spread_ratio.bind_component()`，而底层 CAim 组件实例未变，触发 `observable_property.gd:58-59` 的重复绑定警告。

**修复后的控制流追踪**：
1. 进入 `_try_bind_entity()`，实体有效（line 94）
2. 检测到组件变化（line 97）
3. 执行选择性重绑定 element_type（lines 100-105）
4. **`return` 于 line 106** ← 此处提前返回
5. `aim_position` 和 `spread_ratio` 的 `bind_component()` 永远不会被执行

**结论：Warning 日志消除确认。每次组件切换不再产生冗余日志。** ✅

### 完整场景矩阵

| 场景 | 触发路径 | aim_position | spread_ratio | element_type | Warning 数量 |
|------|----------|-------------|-------------|-------------|-------------|
| 首次绑定（有组件） | line 114→121 | bind | bind | bind | 0 |
| 首次绑定（无组件） | line 114→121 | bind | bind | unbind+set(-1) | 0 |
| 组件动态添加 | line 94→97→100 | **不重绑** | **不重绑** | unbind+bind | **0** |
| 组件动态移除 | line 94→97→103 | **不重绑** | **不重绑** | unbind+set(-1) | **0** |
| 实体失效重建 | line 108→121 | unbind+rebind | unbind+rebind | full rebind | 0 |

所有场景均正确处理。 ✅

---

## 回归检查

### 测试契约 T1-T3 覆盖验证

| 契约 | 描述 | 文件修改状态 | 影响评估 |
|------|------|------------|---------|
| T1 | ViewModel 绑定 CElementalAttack.element_type 同步 | 未在第 2 轮被修改 | 无影响 ✅ |
| T2 | 无 CElementalAttack 时返回 NONE (-1) | 未在第 2 轮被修改 | 无影响 ✅ |
| T3 | unbind 后值重置为 NONE (-1) | 未在第 2 轮被修改 | 无影响 ✅ |

Git 提交历史确认：`test_crosshair_view_model.gd` 仅在 iteration 1（e2fa54c）中被创建/修改，iteration 2（2b82c70）未触碰该文件。测试逻辑未被改动。 ✅

### 其他文件完整性检查

| 文件 | 修改状态 | 说明 |
|------|---------|------|
| `scripts/components/c_elemental_attack.gd` | 仅 iteration 1 修改 | iteration 2 未变更 ✅ |
| `tests/unit/test_crosshair_view_model.gd` | 仅 iteration 1 新增 | iteration 2 未变更 ✅ |

Iteration 2（2b82c70）仅修改了 2 个文件（`+8 -2` 行）：
- `scripts/ui/crosshair.gd`
- `scripts/ui/crosshair_view_model.gd`

**无意外修改、无框架文件污染、无无关副作用。** ✅

---

## 新发现

**无新发现问题。** 两个修复均为精确靶向修改，未引入新的架构违规或边界条件缺陷。

---

## 结论

**`pass`** — 所有本轮审查项均已正确修复，无阻塞问题，无回归风险。

### 修复质量总结

| 问题 | 原严重度 | 修复精准度 | 代码质量 | 状态 |
|------|---------|-----------|---------|------|
| #1 `unbind()` 缺失 | Important/阻塞 | 与建议方案完全一致 | 1 行插入，清晰注释 | 通过 |
| #2 冗余 Warning | Minor/推荐 | 采用推荐方案 A | 选择性重绑定，逻辑等价 | 通过 |

### 合并建议

PR #243 可合并。剩余事项（问题 #3：R2 检测逻辑 Integration 测试覆盖）按 TL 指示归入后续迭代。
