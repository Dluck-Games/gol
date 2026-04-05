# 审查文档：#239 准心 Bug 修复实现（第3轮）

**审查者**: Reviewer
**日期**: 2026-04-05
**审查范围**: s_crosshair.gd / crosshair.gd / s_track_location.gd 修复 + 新增测试
**审查结论**: **rework**

---

## 逐项验证

| # | 原问题（来自 Planner T1-T8） | 修复状态 | 验证方式 |
|---|------|---------|---------|
| 1 | `s_crosshair.gd:45` display_aim_position 在 weapon check 前无条件赋值 | ✅ 已修复 — 赋值移到第57行，在 `if weapon == null` (第50行) 之后 | 逐行代码审查 |
| 2 | `s_crosshair.gd:51` weapon==null 时未清除 display_aim_position | ✅ 已修复 — 第51行设置 `Vector2(-99999, -99999)` | 逐行代码审查 |
| 3 | `crosshair.gd:89` query 不含 CWeapon 导致无武器时绑定成功 | ✅ 已修复 — `_try_bind_entity()` 第119行改为 `with_all([CPlayer, CAim, CWeapon])` | 逐行代码审查 |
| 4 | 武器丢失后绑定不更新导致准心残留 | ✅ 已修复 — `_process()` 第73-76行增加每帧武器存在性检测 | 逐行代码审查 + 时序分析 |
| 5 | `_on_draw()` 无守卫，即使无绑定也绘制 | ✅ 已修复 — 第82行添加 `if _bound_entity == null: return` | 逐行代码审查 |
| 6 | `s_track_location.gd` 相同 bug pattern 未同步修复 | ✅ 已修复 — 与 s_crosshair 完全对称的修改模式 | 逐行对比两文件 |
| 7 | T8 偏差：System 层 query 保持 `with_all([CAim])` 不加 CWeapon | ✅ 合理偏差 — SCrosshair 需处理所有 CAim 实体；UI 层已加 CWeapon 过滤 | 架构分析确认符合"System 处理宽、UI 过滤窄"原则 |

---

## 新发现

### 问题 A：测试质量结构性缺陷（严重程度：高）

**全部10个测试（T1-T10）均不调用被测方法，而是在测试内部复制生产代码逻辑再断言。**

具体表现：

| 测试文件 | 测试ID | 问题 |
|----------|--------|------|
| test_crosshair_view.gd | T1-T3 | 手动操作 `_bound_entity` / `_view_model`，未调用 `_try_bind_entity()` 或 `_process()` |
| test_crosshair_view.gd | T4-T5 | 手动检查布尔条件或数据值，未调用 `_on_draw()` |
| test_crosshair.gd | T6, T9, T10 | 在测试内完整复制 `_update_display_aim()` 的 weapon-null 分支逻辑再断言 |
| test_crosshair.gd | T7 | 手动赋值 `display_aim_position = aim.aim_position`，未通过系统方法 |
| test_crosshair.gd | T8 | 只断言 `has_component(CAim)` 布尔值，未验证 QueryBuilder 行为 |

**影响**：如果未来有人回滚 `s_crosshair.gd` 的修复代码（例如将赋值移回 weapon check 之前），T6/T9/T10 仍会通过——因为它们验证的是测试自身的逻辑副本，而非生产代码路径。

**根因**：`_update_display_aim()` 依赖 `entity.get_viewport()`、`_try_bind_entity()` 依赖 `ECS.world.query`——这些在纯 gdUnit4 环境中不可用。这是 Godot ECS 测试的固有限制。

**建议**：当前测试作为行为契约文档可接受（清楚记录了期望），但应在 CI 中补充 SceneConfig 集成测试（Planner 定义的 T9/T10）以覆盖真实代码路径。本次 rework 不阻塞合入。

### 问题 B：对话系统兼容性（严重程度：信息/已验证安全）

**结论：无冲突。** 详细分析：

`SDialogue._set_crosshair_visible()` (`s_dialogue.gd:186-197`) 只操作 `CrosshairView.visible` 属性：
- 进入对话：`node.visible = false`
- 退出对话：`node.visible = true`

修复后的 `crosshair.gd._process()` 每帧运行（CanvasLayer 不受 UI 交互模式影响）：
- 对话期间若检测到武器丢失 → unbind（正确）
- 退出对话后 `_set_crosshair_visible(true)` 恢复可见性
- 下一帧 `_try_bind_entity()` 根据实际武器状态决定是否重绑

两者操作不同状态维度（visible vs _bound_entity），互不干扰。

### 无回归风险

- 无既有 crosshair 相关测试受影响（此前零测试）
- `test_fire_bullet.gd` 不引用任何 crosshair 代码
- `SDialogue` 通过场景树查找 CrosshairView 节点的方式不受 query 条件变更影响
- `SFireBullet` / 其他 System 的 query 条件未被修改

---

## 结论

### 判决：rework（但仅针对测试质量）

**生产代码修改部分：PASS**
- 三处源码修复完全符合 Planner 方案（路径A+C双重防御）
- STrackLocation 同步修复对称完整
- T8 偏差决策合理且有明确架构依据
- 对话系统兼容性经时序走查确认为安全
- 无回归风险

**测试部分：REWORK 要求**
- 当前测试作为行为契约文档有价值，但不具备回归防护能力
- 要求补充至少一个调用 `_update_display_aim()` 的集成级测试（或解释为何不可行）
- T1-T3 应尝试 mock ECS.world.query 以测试真实的 `_try_bind_entity()` 路径

---

## TL Context for Rework

如需重新提交测试：

1. **优先修复 T6/T7/T9/T10**：这些测试应直接或间接调用 `system._update_display_aim(entity, aim, delta)` 而非复制其内部逻辑
2. 如果 gdUnit4 无法提供 viewport mock，请在测试顶部注释说明限制原因并标注 TODO
3. T1-T3 可考虑使用 `mock(ECS)` 模式（如果 GECS 框架支持）或在测试文档中说明纯单元测试的限制并指向未来的 T9/T10 SceneConfig 集成测试
