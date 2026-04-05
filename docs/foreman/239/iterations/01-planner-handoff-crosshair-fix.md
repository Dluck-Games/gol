# 交接文档：#239 准心 Bug 修复

> **来源**: @planner 分析轮次
> **目标**: @coder / @TL 实施参考
> **详细方案**: `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/plans/01-planner-crosshair-no-weapon-fix.md`

---

## 结论摘要

**Bug 根因已确认为双重缺失**：

1. **System 层** (`s_crosshair.gd:45`)：`_update_display_aim()` 在检查 `CWeapon` 是否存在之前就无条件将 `aim.display_aim_position` 设为了鼠标坐标。当 `weapon == null` 时函数 early return，但 `display_aim_position` 已被污染为有效屏幕坐标。
2. **View 绑定层** (`crosshair.gd:89`)：`_try_bind_entity()` 的 query 条件为 `with_all([CPlayer, CAim])`，缺少 `CWeapon` 要求。玩家始终拥有 `CAim`（由 recipe + AuthoringPlayer 保证），所以即使无武器也会绑定成功。

**推荐方案**：路径 A（绑定层拦截）+ 路径 C（System 层清洁）双重防御。具体来说：(a) `crosshair.gd` 的 query 加上 `CWeapon` 条件 + 每帧武器丢失检测 + `_on_draw()` 守卫；(b) `s_crosshair.gd` 将 `display_aim_position` 赋值移到 weapon null check 之后。同时建议对 `s_track_location.gd` 施加同样的修复（相同 bug pattern）。

**CWeapon → CShooterWeapon 重命名影响约 35+ 文件，列为 optional task，不阻塞主修复。**

---

## Coder 应优先阅读的文件（按顺序）

| 序号 | 文件路径 | 关注点 |
|------|---------|--------|
| 1 | `scripts/ui/crosshair.gd` | **主要修改目标** — 重点看 `_try_bind_entity()` (L78-95) 和 `_on_draw()` (L44-63) |
| 2 | `scripts/systems/s_crosshair.gd` | **第二修改目标** — 重点看 `_update_display_aim()` (L44-88)，注意 L45 的无条件赋值和 L51 的 weapon null check |
| 3 | `scripts/systems/s_track_location.gd` | **同步修复** — 找到类似的 `_update_display_aim` 方法，应用相同的修复 pattern |
| 4 | `scripts/ui/crosshair_view_model.gd` | 只读了解 — 数据绑定层，不需修改 |
| 5 | `scripts/components/c_weapon.gd` | 只读了解 — CWeapon 组件定义，不需修改 |
| 6 | `scripts/systems/s_dialogue.gd` | 只读验证 — 看 `_set_crosshair_visible()` 如何控制 CrosshairView.visible |

---

## 关键代码片段索引

### Bug 位置 1：crosshair.gd:89 — query 缺少 CWeapon
```gdscript
# 当前（有 bug）
var entities: Array = ECS.world.query.with_all([CPlayer, CAim]).execute()

# 修复后
var entities: Array = ECS.world.query.with_all([CPlayer, CAim, CWeapon]).execute()
```

### Bug 位置 2：s_crosshair.gd:45 — 无条件赋值
```gdscript
# 当前（有 bug）— display_aim_position 在 weapon check 之前就被设置了
func _update_display_aim(entity: Entity, aim: CAim, delta: float) -> void:
    aim.display_aim_position = aim.aim_position    # ← L45: 无条件！
    aim.spread_ratio = 0.0
    var weapon: CWeapon = entity.get_component(CWeapon)
    # ...
    if weapon == null or transform == null or viewport == null:
        # ... reset spread fields ...
        return    # ← L55: display_aim_position 已经是鼠标坐标了！
```

### Bug 位置 3：crosshair.gd:37-41 — 无武器丢失重检
```gdscript
# 当前：只在 bound_entity 失效时才重新查询
func _process(_delta: float) -> void:
    _try_bind_entity()
    _draw_node.queue_redraw()

# 修复后：增加武器丢失检测
func _process(_delta: float) -> void:
    _try_bind_entity()
    if _bound_entity and is_instance_valid(_bound_entity):
        if not _bound_entity.has_component(CWeapon):
            _view_model.unbind()
            _bound_entity = null
    _draw_node.queue_redraw()
```

---

## 关键风险与测试契约摘要

### 风险

1. **对话系统时序**（中）：`SDialogue` 控制 `CrosshairView.visible`。需确保对话结束后 `_try_bind_entity()` 能正确 rebind。缓解：`_process()` 每帧调用天然支持重试。
2. **STrackLocation 同样的问题**（低）：AI 自动瞄准系统有相同 bug pattern，建议一并修复但不阻塞主修复。
3. **无既有 crosshair 测试**（中）：当前零测试覆盖，必须新建 unit tests 作为修复的一部分。

### 测试契约（必须通过）

- **T1-T5**（`test_crosshair_view.gd`）：绑定/解绑/绘制守卫的单元测试
- **T6-T8**（`test_crosshair.gd`）：System 层 weapon-null 分支的单元测试
- **回归**：所有现有 CWeapon 相关测试（`test_fire_bullet.gd` 等）不受影响

详见主计划文档「测试契约」章节。

---

## 实现步骤速查

1. **`s_crosshair.gd`**：将 L45 的 `display_aim_position` 赋值移到 weapon null check 之后；null 分支置无效坐标
2. **`crosshair.gd`**：query 加 `CWeapon`；`_process()` 加武器丢失检测；`_on_draw()` 加 null 守卫
3. **`s_track_location.gd`**：应用与 step 1 相同的 pattern
4. **新建测试文件**：`test_crosshair_view.gd` + `test_crosshair.gd`
5. **验证对话系统**：进入/退出对话框后准心行为正确
6. *(Optional)* **CWeapon 重命名**：独立 task，~35+ 文件

---

## 架构约束提醒

- **数据流单向**: System → Component → ViewModel → View，不要在 View 里直接查 Component
- **组件纯数据**: 不要给 CWeapon / CAim 加逻辑
- **命名规范**: 文件和类名遵循 AGENTS.md 的 c_/s_/viewmodel_/View_ 前缀
- **测试目录**: Unit → `tests/unit/`，Integration → `tests/integration/`
