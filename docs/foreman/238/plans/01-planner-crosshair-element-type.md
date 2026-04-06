# Issue #238 计划：准心 UI 展示元素伤害类型

## 需求分析

### 目标
当玩家实体拥有 `CElementalAttack` 组件时，在准心（CrosshairView）附近显示当前元素伤害类型的视觉提示。

### 数据源
- **组件**：`scripts/components/c_elemental_attack.gd`
- **枚举** `ElementType`：FIRE(0) / WET(1) / COLD(2) / ELECTRIC(3)
- **关键字段**：`element_type: ElementType` — 当前武器/攻击的元素类型

### 现有视觉参考
项目中已有完整的元素颜色体系：
- `scripts/utils/elemental_utils.gd` 定义了 4 种元素的 `*_VISUAL_COLOR` 常量
- `scripts/ui/views/view_hp_bar.gd:229-240` 有 `_get_element_color()` 方法，将 ElementType 映射到 Color
- `scripts/ui/crosshair.gd:4` 已有 `ELECTRIC_COLOR` 常量用于准心着色

### 核心问题
当前 `CrosshairViewModel` 只绑定 `CAim` 组件的两个属性（aim_position、spread_ratio），**不感知 `CElementalAttack`**。需要扩展数据绑定以暴露玩家的元素类型给 View 层渲染。

---

## 影响面分析

### 必须修改的文件

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `scripts/components/c_elemental_attack.gd` | **修改** | 为 `element_type` 添加 ObservableProperty setter 模式 |
| `scripts/ui/crosshair_view_model.gd` | **修改** | 新增 `element_type` ObservableProperty 字段 + bind/unbind |
| `scripts/ui/crosshair.gd` | **修改** | 新增元素颜色常量、订阅 element_type 变化、绘制元素图标 |

### 可选修改的文件

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| 无新增文件 | — | 复用现有 MVVM 结构，无需新建 ViewModel/View |

### 受影响但不需改动的文件

| 文件 | 原因 |
|------|------|
| `scripts/utils/elemental_utils.gd` | 颜色常量已完备，直接引用即可 |
| `scripts/ui/views/view_hp_bar.gd` | 参考其颜色映射模式，不改其代码 |
| `scripts/systems/s_*.gd` | 元素系统逻辑层不受 UI 变更影响 |

### 调用链追踪

```
玩家实体 (Entity)
  ├── CPlayer (标记组件, _try_bind_entity 查询条件)
  ├── CAim (已绑定: display_aim_position, spread_ratio)
  └── CElementalAttack (★ 新增绑定: element_type)
        └── element_type → element_type_observable (★ 需新增)
              └── CrosshairViewModel.element_type (★ 新增 ObservableProperty)
                    └── CrosshairView._on_element_type_changed() → 重绘准心 + 元素图标
```

---

## 实现方案

### 方案概述：扩展现有 MVVM 链路

遵循项目已有的 `Component → ObservableProperty → ViewModel → View` 单向数据流模式，在现有 CrosshairViewModel/CrosshairView 上增加一个数据通道。

### 步骤 1：为 CElementalAttack 添加 ObservableProperty

**文件**：`scripts/components/c_elemental_attack.gd`

在 `element_type` 属性上添加 setter + observable，与 CAim 组件的模式一致：

```gdscript
@export var element_type: ElementType = ElementType.FIRE:
    set(value):
        element_type = value
        element_type_observable.set_value(value)
var element_type_observable: ObservableProperty = ObservableProperty.new(element_type)
```

需要在文件顶部添加引用：`const COMPONENT_OBSERVABLE_PROPERTY = preload("res://scripts/ui/observable_property.gd")`

**参考模式**：`scripts/components/c_aim.gd:24-29`（CAim 的 spread_ratio observable 模式）

### 步骤 2：扩展 CrosshairViewModel

**文件**：`scripts/ui/crosshair_view_model.gd`

新增字段和方法：

```gdscript
var element_type: ObservableProperty   # 新增

func setup() -> void:
    # ... 现有代码 ...
    element_type = ObservableProperty.new(-1)  # -1 = NONE（无元素攻击）

func teardown() -> void:
    # ... 现有代码 ...
    element_type.teardown()

func bind_to_entity(entity: Entity) -> void:
    # ... 现有代码 ...
    # 安全绑定：只有当实体拥有 CElementalAttack 时才绑定
    if entity.has_component(CElementalAttack):
        element_type.bind_component(entity, CElementalAttack, "element_type")
    else:
        element_type.set_value(-1)  # 无元素组件时设为 NONE

func unbind() -> void:
    # ... 现有代码 ...
    element_type.unbind()
    element_type.set_value(-1)
```

**关键点**：
- 使用 `-1` 作为"无元素"的哨兵值（ElementType 枚举范围是 0-3）
- `bind_to_entity` 中用 `has_component` 做安全检查——玩家不一定总有 CElementalAttack
- 当玩家切换武器（换掉 CElementalAttack 或 element_type 变化），observable 自动通知

### 步骤 3：扩展 CrosshairView 渲染

**文件**：`scripts/ui/crosshair.gd`

#### 3a. 新增颜色常量

```gdscript
const ELEMENT_COLORS := {
    CElementalAttack.ElementType.FIRE:     Color(1.0, 0.45, 0.2, 0.9),    # 橙红
    CElementalAttack.ElementType.WET:      Color(0.35, 0.7, 1.0, 0.9),     # 蓝
    CElementalAttack.ElementType.COLD:     Color(0.7, 0.95, 1.0, 0.9),     # 冰蓝
    CElementalAttack.ElementType.ELECTRIC: Color(1.0, 0.95, 0.35, 0.9),    # 黄
}
```

复用 `view_hp_bar.gd:229-240` 的配色方案，保持 UI 一致性。保留原有 `ELECTRIC_COLOR` 用于 shock effect 的电击特效色。

#### 3b. _ready() 中订阅

```gdfunc
_view_model.element_type.subscribe(_on_element_type_changed)
```

#### 3c. 新增回调

```gdscript
func _on_element_type_changed(new_type: int) -> void:
    _draw_node.queue_redraw()
```

#### 3d. 修改 `_on_draw()` — 在准心四线旁绘制元素图标

在现有四线绘制之后（第 60 行之后），添加元素指示器绘制：

```gdscript
# 在 _on_draw() 末尾，shock effect 之前或之后
_draw_element_indicator(pos, draw_gap, draw_thickness)
```

#### 3e. 新增 `_draw_element_indicator()` 方法

设计建议：在准心下方绘制一个小型元素指示器：

- **位置**：准心中心正下方 `draw_gap + 4px` 处
- **形态**：一条短横线（类似下划线）+ 脉冲发光效果
- **颜色**：根据 `ELEMENT_COLORS[element_type]` 选择
- **大小**：宽度约 `line_length * 0.6`，厚度 `thickness * 0.8`
- **脉冲**：使用已有的 `pulse` 变量做透明度/亮度呼吸
- **隐藏条件**：`element_type == -1` 时不绘制

伪代码：

```gdscript
func _draw_element_indicator(pos: Vector2, gap: float, thick: float) -> void:
    var etype: int = _view_model.element_type.value
    if etype < 0:
        return
    var elem_color: Color = ELEMENT_COLORS.get(etype, Color.WHITE)
    var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
    var alpha: float = 0.5 + pulse * 0.5
    var draw_color: Color = Color(elem_color.r, elem_color.g, elem_color.b, alpha)
    var indicator_y: float = pos.y + gap + 5.0
    var indicator_width: float = line_length * 0.6
    _draw_node.draw_line(
        pos + Vector2(-indicator_width / 2, indicator_y),
        pos + Vector2(indicator_width / 2, indicator_y),
        draw_color, maxf(1.0, thick * 0.8)
    )
```

#### 3f. （可选增强）让准心主线颜色也受元素类型影响

当前 `draw_color` 已使用 `color.lerp(ELECTRIC_COLOR, spread_ratio * ...)` 来混合电击色。可扩展为根据 `element_type` 动态选择混合目标色：

```gdscript
# 替换原有的 ELECTRIC_COLOR 硬编码
var element_tint: Color = _get_element_tint_color()
var draw_color: Color = color.lerp(element_tint, spread_ratio * (0.6 + pulse * 0.4))
```

其中 `_get_element_tint_color()` 根据 element_type 返回对应颜色，无元素时返回 WHITE（即不 tint）。

---

## 架构约束

### 涉及的 AGENTS.md 文件
- **`gol-project/scripts/ui/AGENTS.md`** — MVVM 模式规范，ObservableProperty 绑定机制
- **`gol-project/scripts/components/AGENTS.md`** — 组件 Observable setter 模式
- **`gol-project/AGENTS.md`** — 项目整体命名规范和架构原则

### 引用的架构模式
1. **单向数据流**：System → Component → ViewModel → View（View 不修改数据）
2. **ObservableProperty 绑定**：`viewModel.prop.bind_component(entity, CompClass, "prop_name")` 自动查找 `{prop_name}_observable`
3. **Component setter 模式**：属性 setter 中调用 `xxx_observable.set_value(value)`
4. **CanvasLayer 自绘**：CrosshairView 使用 Node2D.draw 信号做自定义绘制

### 文件归属层级
- `scripts/components/` — ECS 纯数据组件层
- `scripts/ui/` — MVVM UI 层（ViewModel + View）
- `scripts/utils/` — 工具类（不修改，仅引用）

### 测试模式
按照 AGENTS.md 规定，测试通过 `gol-test-dispatch` skill 委托子代理执行：
- **Unit 测试**（`tests/unit/`）：验证 ViewModel 绑定逻辑、element_type observable 值传递
- **Integration 测试**（`tests/integration/`）：场景级验证完整数据流

---

## 测试契约

### T1：ViewModel 绑定 CElementalAttack.element_type
- **前置**：创建 Entity，添加 CPlayer + CAim + CElementalAttack(FIRE)
- **操作**：`CrosshairViewModel.bind_to_entity(entity)`
- **断言**：`element_type.value == CElementalAttack.ElementType.FIRE`
- **操作**：修改 `entity.get_component(CElementalAttack).element_type = COLD`
- **断言**：`element_type.value == CElementalAttack.ElementType.COLD`（通过 observable 自动同步）

### T2：ViewModel 无 CElementalAttack 时返回 NONE
- **前置**：创建 Entity，添加 CPlayer + CAim（无 CElementalAttack）
- **操作**：`CrosshairViewModel.bind_to_entity(entity)`
- **断言**：`element_type.value == -1`

### T3：unbind 后值重置
- **前置**：已绑定的 ViewModel（element_type == FIRE）
- **操作**：`CrosshairViewModel.unbind()`
- **断言**：`element_type.value == -1`

### T4：View 绘制元素指示器（Visual / 手动验证）
- **前置**：运行游戏，玩家持有带 CElementalAttack(FIRE) 的武器
- **预期**：准心下方出现橙色脉冲横线指示器
- **操作**：切换到 COLD 类型武器
- **预期**：指示器变为冰蓝色

### T5：无元素攻击时不绘制指示器
- **前置**：运行游戏，玩家持有普通武器（无 CElementalAttack）
- **预期**：准心外观与改动前完全一致，无额外图形

---

## 风险点

| # | 风险 | 影响 | 缓解措施 |
|---|------|------|----------|
| R1 | **玩家实体可能没有 CElementalAttack** | `bind_component` 会打印 Warning 日志 | 在 `bind_to_entity` 中先检查 `has_component(CElementalAttack)`，无则设为 -1 |
| R2 | **元素类型动态切换（换武器）** | on_merge 可能替换整个组件 | ObservableProperty 绑定的是组件实例引用；如果组件被 replace（非同一实例），需要 `_try_bind_entity` 重新绑定。当前 `_try_bind_entity` 只检查 entity 有效性，**不检测组件变化**。需评估是否需要增强 |
| R3 | **CElementalAttack 引入 ui/ 循环依赖风险** | Component 层引用了 ui/ 的 ObservableProperty | CAim 组件已有同样模式（引用 ObservableProperty），这是项目既有的跨层引用约定。保持一致即可 |
| R4 | **绘制性能**：每帧多一次 draw_line | 可忽略（单条线段，GPU 开销极低） | — |
| R5 | **ELECTRIC_COLOR 与新 ELEMENT_COLORS 可能不一致** | 视觉上电击特效色和指示器色可能不协调 | 两者用途不同（shock effect vs indicator），允许细微差异；如需统一可直接复用同一套颜色 |

### R2 详细分析

当前 `_try_bind_entity()` (`crosshair.gd:78-95`) 的逻辑：
1. 如果 `_bound_entity` 有效 → 直接 return（不再重新绑定）
2. 这意味着**一旦绑定成功，即使玩家更换了 CElementalAttack 组件（或移除又添加），ViewModel 不会重新绑定**

**场景**：玩家从普通武器切换到元素武器 → 实体新增 CElementalAttack → 但 ViewModel 已绑定，不会重新读取。

**缓解方案**（二选一）：
- **方案 A（推荐，最小改动）**：在 `_try_bind_entity` 中，除了检查 entity 有效性外，额外检查 CElementalAttack 组件的存在性是否发生变化。如果之前没绑定 element_type（值为 -1）但现在实体有了该组件，调用 `_view_model.bind_to_entity(_bound_entity)` 重新绑定。
- **方案 B（更彻底）**：每次 `_process` 都尝试重新绑定 element_type（轻量操作，只是 has_component + 条件性 bind_component）

---

## 建议的实现步骤

### Phase 1：数据层（Component + ViewModel）
1. **修改** `scripts/components/c_elemental_attack.gd`：添加 `element_type_observable` 和 setter
2. **修改** `scripts/ui/crosshair_view_model.gd`：新增 `element_type` ObservableProperty，更新 `setup()/teardown()/bind_to_entity()/unbind()`

### Phase 2：视图层（CrosshairView）
3. **修改** `scripts/ui/crosshair.gd`：
   - 添加 `ELEMENT_COLORS` 字典常量和 `CElementalAttack` preload
   - 在 `_ready()` 订阅 `element_type` 变化
   - 添加 `_on_element_type_changed()` 回调
   - 添加 `_draw_element_indicator()` 绘制方法
   - 修改 `_on_draw()` 调用新的绘制方法
   - （可选）修改主线颜色的 tint 逻辑，使其基于当前 element_type 而非硬编码 ELECTRIC_COLOR
   - 处理 R2 风险：增强 `_try_bind_entity()` 以支持 CElementalAttack 组件的动态增删

### Phase 3：测试
4. 通过 `gol-test-dispatch` skill 委托测试子代理编写并执行单元测试（T1-T3）
5. Integration/E2E 测试（T4-T5）由人工验证或 AI Debug Bridge 截图对比

### 实施顺序依赖
```
Step 1 (Component observable) → Step 2 (ViewModel binding) → Step 3 (View rendering) → Step 4 (Tests)
```
Step 1-3 有严格依赖关系（下层必须先就绪）。Step 4 可并行于 Step 3 之后启动。
