# 审查文档：#239 准心 Bug 修复 — 测试质量 Rework（第 2 轮审查）

**审查者**: Reviewer
**日期**: 2026-04-05
**审查范围**: 测试代码改进（第 2 次 Rework）
**审查结论**: **pass**

---

## 逐项验证

| # | 原问题（来自 03-reviewer-review.md） | 修复状态 | 验证方式 |
|---|------|---------|---------|
| **P0** | 全部测试不调用被测方法，复制生产代码逻辑 | ✅ **已修复** | 逐行代码审查：T6/T7/T9/T10 现在调用 `system._update_display_aim()` |
| **P1** | 断言仅验证前置条件，不验证方法执行后实际状态 | ✅ **已修复** | 逐行代码审查：断言改为验证组件字段实际值（`display_aim_position`, `spread_angle_degrees` 等）|
| **P2** | T1-T3 缺少限制说明和 TODO 标注 | ✅ **已修复** | 文件头部 + 每个函数均有详细注释说明纯单元测试限制 |

---

## P0 详细验证：真实方法调用

### SubViewport 方式评估

Coder 采用 `SubViewport` 构造最小场景树环境，使 `entity.get_viewport()` 返回有效值。

**代码模式**（以 T6 为例，`test_crosshair.gd:33-67`）：
```gdscript
var viewport := SubViewport.new()
viewport.size = Vector2i(800, 600)
add_child(viewport)          # 添加到测试套件场景树
viewport.add_child(entity)   # entity 进入场景树

system._update_display_aim(entity, aim, 0.016)  # 调用真实生产方法
```

**判定**：这是 Godot 4.x 标准的测试模式。`SubViewport` 是 `Viewport` 的子类，添加到场景树后，其子节点的 `get_viewport()` 会返回有效对象。✅ 符合项目标准。

### 生产代码路径覆盖验证

对照 `s_crosshair.gd:44-89` 的 `_update_display_aim()` 实现：

| 测试 | 触发的生产代码路径 | 行号覆盖 |
|------|------------------|---------|
| **T6** | weapon==null → 第50行 guard → 设置无效坐标+重置 spread | 45, 47-55 ✅ |
| **T7** | weapon!=null → 通过 guard → 第57行赋值 → 完整计算 | 45, 47-57, 59-89 ✅ |
| **T9** | weapon==null → spread 字段重置为 0 | 52-54 ✅ |
| **T10** | 双场景对比：无武器 vs 有武器的分支差异 | 50-55 vs 57-89 ✅ |

**关键确认**：T6 和 T9 现在真正测试了本次 Bug 修复的核心逻辑——weapon 为 null 时 `display_aim_position` 应设为 `Vector2(-99999, -99999)` 且 spread 字段应重置。如果未来有人回滚修复（将赋值移回 weapon check 前），这些测试会失败。✅ 回归防护有效。

---

## P1 详细验证：断言质量

### 修复前后对比

**修复前（问题 A 中描述的旧模式）**：
```gdscript
# 在测试内复制生产逻辑
var weapon: CWeapon = entity.get_component(CWeapon)
assert_object(weapon).is_null()
if weapon == null:
    aim.display_aim_position = Vector2(-99999, -99999)  # 复制！
```

**修复后（当前代码）**：
```gdscript
# T6: 直接调用生产方法后验证实际状态
system._update_display_aim(entity, aim, 0.016)
assert_vector2(aim.display_aim_position).is_equal(Vector2(-99999, -99999))
assert_float(aim.spread_angle_degrees).is_equal(0.0)

# T7: 验证有武器时输出非无效值
system._update_display_aim(entity, aim, 0.016)
var is_invalid := (aim.display_aim_position == Vector2(-99999, -99999))
assert_bool(is_invalid).is_false()
```

**判定**：不再复制生产代码逻辑。断言验证的是 `_update_display_aim()` 执行后的组件实际状态值。✅

### 关于 T7 断言"弱"的说明

T7 仅断言 `display_aim_position != Vector2(-99999, -99999)`，而非精确值。这是**合理降级**：

1. 完整计算涉及 `canvas_transform.affine_inverse()`、世界坐标转换、spread 抖动等复杂逻辑
2. 精确值依赖运行时状态（鼠标位置、transform、canvas 配置）
3. 本次 Bug 修复的核心是 weapon-null 分支处理，由 T6/T9/T10 充分覆盖
4. T7 的目的是确保有武器时方法不会进入 invalid 分支——当前断言已满足此目标

---

## P2 详细验证：注释和文档质量

### 文件头部注释（`test_crosshair_view.gd:6-28`）

```gdscript
# ============================================================================
# 测试说明：纯单元测试限制
# ============================================================================
# 1. 无法 mock ECS.world.query - GECS 框架需要完整的 World 初始化
#    - _try_bind_entity() 方法依赖 ECS.world.query.with_all([CPlayer, CAim, CWeapon])
#    ...
# 2. 无法完整测试 _on_draw() - 依赖 _draw_node 和 Godot 渲染管线
#    ...
#
# TODO: 真实代码路径覆盖依赖 SceneConfig 集成测试（T9/T10 在 Planner 契约中定义）
#       - _try_bind_entity() 的完整 ECS query 路径：需 GOLWorld + 真实玩家实体
#       - _on_draw() 的实际绘制调用：需渲染管线 + 截图验证
#       - 武器拾取/丢失的完整流程：需 ComponentDrop 系统交互
# ============================================================================
```

**信息量评估**：
- ✅ 明确说明了两个固有限制的原因（ECS World 依赖、渲染管线依赖）
- ✅ 解释了为何无法直接测试 `_try_bind_entity()` 和 `_on_draw()`
- ✅ TODO 清晰指向了未来需要补充的集成测试类型
- ✅ 后续开发者能理解为什么 T1-T5 采用"行为契约文档"策略

### 函数级注释示例

每个 T1-T5 函数都有：
- 测试目的说明
- 为什么无法调用真实方法的解释
- 行为契约描述（期望的生产代码行为）
- TODO 标记指向集成测试

**判定**：注释充分且实用。✅

---

## 新发现

无新增问题。

本轮 rework 仅修改了测试文件，未引入任何新缺陷。所有改进均针对之前指出的问题，且改动范围合理。

---

## 边界情况检查

### 1. SubViewport 资源泄漏风险？

检查代码中每个使用 SubViewport 的测试：
- T6: `auto_free(viewport)` ✅
- T7: `auto_free(viewport)` ✅
- T9: `auto_free(viewport)` ✅
- T10: 两个 viewport 均 `auto_free()` ✅

### 2. Entity 同时属于 viewport 和 auto_free？

```gdscript
var entity: Entity = auto_free(Entity.new())
viewport.add_child(entity)  # entity 现在是 viewport 的子节点
```

Godot 中 `auto_free` 会在测试结束时释放对象，即使它已被添加到场景树。这是 gdUnit4 的标准用法，不会造成 double-free。✅

### 3. T8 未改进是否可接受？

T8 (`test_query_includes_caim`) 仍然只验证接口契约而非实际 query 执行。

**判定：可接受。**
- 原因：`QueryBuilder.execute()` 需要完整的 ECS World 环境，这在纯单元测试中不可用
- T8 的价值在于记录 System 层的设计决策（query 只包含 CAim，不含 CWeapon）
- 这与 03-reviewer-review.md 中的 T8 偏差分析一致

---

## 结论

### 判决：**PASS**

**P0 — 真实方法调用**: ✅ 满足
- T6/T7/T9/T10 现在通过 SubViewport 环境调用真实的 `_update_display_aim()` 方法
- SubViewport 使用方式符合 Godot 4.x 标准测试模式
- 测试确实覆盖了本次 Bug 修复的核心路径（weapon-null 分支）

**P1 — 断言质量**: ✅ 满足
- 不再复制生产代码逻辑
- 断言验证方法执行后的组件实际状态值
- T7 的弱断言是合理降级，不影响回归防护能力

**P2 — 注释文档**: ✅ 满足
- 文件头部详细说明了纯单元测试的两个固有限制及原因
- 每个测试函数都有清晰的注释说明测试策略
- TODO 标记明确指向未来需要的集成测试类型

### 后续建议（非阻塞）

1. 当团队建立 SceneConfig 集成测试基础设施时，优先补充以下场景：
   - 玩家无武器时 CrosshairView 不显示
   - 玩家拾取武器后 CrosshairView 绑定并显示
   - 武器丢失后 CrosshairView 解绑并隐藏

2. 可考虑将 SubViewport 环境构建抽取为辅助函数，减少 T6/T7/T9/T10 中的重复代码（低优先级）
