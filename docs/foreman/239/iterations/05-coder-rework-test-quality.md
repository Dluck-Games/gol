# 交接文档：#239 准心 Bug 修复 — 测试质量 Rework

## 任务概述

根据 Reviewer 第3轮审查的 Rework 要求，改进测试代码质量，确保测试真正调用被测方法的核心逻辑，而非仅复制生产代码进行断言。

---

## 逐项修复记录

### 核心问题（Reviewer 指出）

**原问题**：全部10个测试（T1-T10）均不调用被测方法，而是在测试内部复制生产代码逻辑再断言。如果未来有人回滚修复代码，这些测试仍会通过。

**根因**：`_update_display_aim()` 依赖 `entity.get_viewport()`，在纯 gdUnit4 环境中返回 null，导致方法在 guard 条件处提前返回，无法测试 weapon-null 分支的核心逻辑。

---

### P0 — 真实方法调用测试

**解决方案**：使用 `SubViewport` 创建最小场景树环境

| 测试 | 修改内容 |
|------|---------|
| **T6** | 使用 `SubViewport` 作为实体父节点，使 `entity.get_viewport()` 返回有效值。现在测试真正执行了 `_update_display_aim()` 的 weapon-null 分支，验证 `display_aim_position` 被设为 `Vector2(-99999, -99999)` |
| **T7** | 同样使用 `SubViewport` 环境，验证有 weapon 时 `display_aim_position` 不再是无效值 |
| **T9** | 使用 `SubViewport` 环境，验证 weapon-null 时 spread 相关字段被重置为 0 |
| **T10** | 使用 `SubViewport` 环境，创建两个测试场景（无 weapon/有 weapon），验证赋值顺序正确性 |

**关键改进代码示例**（T6）：
```gdscript
# 创建 SubViewport 环境使 entity.get_viewport() 有效
var viewport := SubViewport.new()
viewport.size = Vector2i(800, 600)
add_child(viewport)
auto_free(viewport)

# ... 创建 entity 和组件 ...

# 将 entity 添加到 viewport 使 get_viewport() 有效
viewport.add_child(entity)

# 调用生产方法 - 现在 viewport 有效，会执行完整逻辑
system._update_display_aim(entity, aim, 0.016)

# 验证：无 weapon 时 display_aim_position 应被设为无效值
assert_vector2(aim.display_aim_position).is_equal(Vector2(-99999, -99999))
```

---

### P1 — T6/T7/T9/T10 优先改善

**原问题**：这些测试在内部复制 `_update_display_aim()` 的 weapon-null 分支逻辑再断言，没有真正调用生产方法。

**修复方式**：

1. **验证实际状态值**：不再断言前置条件（如 `assert_bool(has_weapon).is_false()`），而是调用 `_update_display_aim()` 后验证组件实际值：
   - `assert_vector2(aim.display_aim_position).is_equal(Vector2(-99999, -99999))`
   - `assert_float(aim.spread_angle_degrees).is_equal(0.0)`

2. **验证方法返回值的影响**：通过调用前后对比组件状态，确认生产方法确实执行了预期逻辑

---

### P2 — T1-T3 绑定测试

**原问题**：无法测试真实的 `_try_bind_entity()` 路径，因为依赖 `ECS.world.query`。

**改进**：更新注释说明限制原因，并标注 TODO

**T1-T3 的测试限制说明**（已更新注释）：
```gdscript
# ============================================================================
# 测试说明：纯单元测试限制
# ============================================================================
# 1. 无法 mock ECS.world.query - GECS 框架需要完整的 World 初始化
#    - _try_bind_entity() 方法依赖 ECS.world.query.with_all([CPlayer, CAim, CWeapon])
#    - 已尝试：直接使用 mock(ECS) 或手动设置 ECS.world，但 GECS 框架内部依赖复杂
#
# 2. 无法完整测试 _on_draw() - 依赖 _draw_node 和 Godot 渲染管线
#
# TODO: 真实代码路径覆盖依赖 SceneConfig 集成测试（T9/T10 在 Planner 契约中定义）
#       - _try_bind_entity() 的完整 ECS query 路径：需 GOLWorld + 真实玩家实体
#       - _on_draw() 的实际绘制调用：需渲染管线 + 截图验证
# ============================================================================
```

---

## 测试结果

| 测试文件 | 测试数量 | 状态 |
|---------|---------|------|
| `tests/unit/ui/test_crosshair_view.gd` | T1-T5 (5个) | 全部通过 |
| `tests/unit/system/test_crosshair.gd` | T6-T10 (5个) | 全部通过 |

**测试运行结果**：
```
Total: 506    Passed: 506    Failed: 0      Skipped: 0
RESULT: ALL TESTS PASSED
```

**关键改进验证**：
- T6: `display_aim_position` 在无 weapon 时被正确设为 `Vector2(-99999, -99999)`
- T7: 有 weapon 时 `display_aim_position` 不再是无效值
- T9: spread 相关字段在 weapon-null 时被重置为 0
- T10: 验证 weapon-null 和 weapon-valid 两个分支的正确性

---

## 仓库状态

| 项目 | 状态 |
|------|------|
| **Branch** | `foreman/issue-239-bugcrosshair` |
| **修改文件** | `tests/unit/ui/test_crosshair_view.gd` |
| **修改文件** | `tests/unit/system/test_crosshair.gd` |
| **生产代码** | 未修改（按约束要求） |
| **测试状态** | 全部通过 |

### 文件变更摘要

**`tests/unit/system/test_crosshair.gd`**：
- 添加 `SubViewport` 环境构建，使 `_update_display_aim()` 能完整执行
- T6, T7, T9, T10 现在验证实际组件状态值而非前置条件
- 更新注释说明测试限制和 TODO

**`tests/unit/ui/test_crosshair_view.gd`**：
- 更新注释，明确说明纯单元测试限制
- 标注 TODO 指向 SceneConfig 集成测试

---

## 未完成事项

| 事项 | 说明 | 建议方案 |
|------|------|---------|
| `_try_bind_entity()` 完整路径测试 | 依赖 `ECS.world.query` | 需 SceneConfig 集成测试 |
| `_on_draw()` 实际绘制验证 | 依赖渲染管线 | 需 SceneConfig + AI Debug Bridge 截图验证 |
| spread 计算逻辑完整验证 | 依赖完整游戏帧更新 | 需集成测试验证 |

---

## 回归风险

- 无回归风险：仅修改测试文件，生产代码未变更
- 所有既有测试仍通过（506/506）

---

## 代码审查建议

1. **生产代码**：无需审查（未修改）
2. **测试代码**：重点审查 `SubViewport` 使用方式是否为项目标准做法
3. **SceneConfig 集成测试**：建议后续补充 T9/T10 的集成测试以覆盖完整代码路径
