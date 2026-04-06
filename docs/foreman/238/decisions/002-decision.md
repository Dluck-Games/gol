# Decision 2 — 2026-04-06 01:21
**Trigger:** planner 完成交接文档 `01-planner-handoff-crosshair-element-type.md`，产出完整实现计划
**Assessment:** 计划质量良好。Planner 分析了现有 Crosshair MVVM 链路、CElementalAttack 组件结构、元素颜色体系（elemental_utils.gd），产出 3 文件修改方案（c_elemental_attack.gd / crosshair_view_model.gd / crosshair.gd）。包含具体伪代码、风险点（R2 组件动态增删）、测试契约（T1-T5）、分步实施顺序。计划可直接交付 coder 执行。
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**Guidance:** 按计划 Phase 1→Phase 2→Phase 3 顺序实现，严格遵循 MVVM 模式。
**TL Context for @coder:**
> ## Issue #238 — 准心 UI 展示元素伤害类型：实现任务
>
> ### 核心目标
> 当玩家持有带 CElementalAttack 组件的武器时，在准心下方绘制对应元素类型的脉冲颜色指示器横线。
>
> ### 必读文件（按顺序）
>
> | 文件 | 看什么 |
> |------|--------|
> | `gol-project/scripts/components/c_elemental_attack.gd` | ElementType 枚举、需添加 observable setter |
> | `gol-project/scripts/ui/crosshair_view_model.gd` | 现有绑定模式，新增 element_type 字段 |
> | `gol-project/scripts/ui/crosshair.gd` | View 绘制逻辑，_on_draw() 是核心修改点 |
> | `gol-project/scripts/components/c_aim.gd:24-29` | **参考模式**：spread_ratio 的 observable setter 写法 |
>
> 参考文件：
> - `gol-project/docs/foreman/238/plans/01-planner-crosshair-element-type.md` — 完整计划（含伪代码、步骤、风险点）
> - `gol-project/docs/foreman/238/iterations/01-planner-handoff-crosshair-element-type.md` — planner 交接摘要
>
> ### 实施步骤（严格按序）
>
> **Phase 1 — 数据层**
> 1. 修改 `scripts/components/c_elemental_attack.gd`：为 `element_type` 添加 setter + `element_type_observable`（参考 c_aim.gd 模式）
> 2. 修改 `scripts/ui/crosshair_view_model.gd`：新增 `element_type: ObservableProperty` 字段，更新 setup()/teardown()/bind_to_entity()/unbind()
>    - bind_to_entity 中用 `has_component(CElementalAttack)` 做安全检查，无则设 -1
>
> **Phase 2 — 视图层**
> 3. 修改 `scripts/ui/crosshair.gd`：
>    - 新增 `ELEMENT_COLORS` 字典常量（4 种元素颜色）
>    - `_ready()` 中订阅 element_type 变化
>    - 新增 `_on_element_type_changed()` 回调 → queue_redraw
>    - 新增 `_draw_element_indicator(pos, gap, thick)` 方法：在准心下方绘制脉冲横线（element_type < 0 不绘制）
>    - 在 `_on_draw()` 中调用 `_draw_element_indicator()`
>    - 处理 R2 风险：增强 `_try_bind_entity()` 支持 CElementalAttack 动态增删（推荐方案 A：检查组件存在性变化）
>
> **Phase 3 — 测试**
> 4. 通过 `gol-test-dispatch` skill 委派子代理编写单元测试（T1-T3：ViewModel 绑定/无组件/unbind 重置）
>
> ### 关键约束
> - **MVVM 单向数据流**：View 只读 ViewModel，不修改数据
> - **ObservableProperty 模式**：Component setter 调用 `xxx_observable.set_value(value)`
>   ViewModel 用 `bind_component(entity, CompClass, "prop_name")` 自动查找 `{prop}_observable`
> - **哨兵值 -1 表示无元素攻击**（ElementType 枚举范围 0-3）
> - **不引入新文件**，只修改上述 3 个文件
> - **复用项目既有模式**：CAim 的 observable setter、view_hp_bar 的配色方案
