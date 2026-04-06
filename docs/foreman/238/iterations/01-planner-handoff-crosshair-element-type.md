# Issue #238 交接文档：准心 UI 展示元素伤害类型

## 本轮结论摘要

Issue #238 目标是在准心（CrosshairView）附近展示玩家当前武器/攻击的元素伤害类型（FIRE/WET/COLD/ELECTRIC）视觉提示。

经代码探索，**实现路径清晰且改动范围小**：只需修改 3 个现有文件，无需新建文件。核心方案是扩展现有 MVVM 数据链路——在 `CElementalAttack` 组件上添加 ObservableProperty setter，在 `CrosshairViewModel` 上新增 `element_type` 字段并绑定，在 `CrosshairView` 上新增绘制逻辑。

项目中已有完备的元素颜色体系（`elemental_utils.gd` 的 4 色常量 + `view_hp_bar.gd` 的颜色映射方法），可直接复用。`CrosshairView` 已有 `ELECTRIC_COLOR` 常量和 `_draw_shock_effect()` 方法作为电击特效参考，新功能将在此基础上扩展为支持全部 4 种元素类型。

**主要风险点**：玩家实体的 `CElementalAttack` 组件可能动态增删（换武器），当前 `_try_bind_entity()` 不检测组件变化。计划中提供了两种缓解方案，推荐方案 A（最小改动：在绑定检查中加入组件存在性判断）。

---

## 推荐 coder 先看的文件/函数

### 必读（按顺序）

| 序号 | 文件 | 关键行 | 看什么 |
|------|------|--------|--------|
| 1 | `scripts/components/c_elemental_attack.gd` | 全文 (50行) | ElementType 枚举定义、element_type 属性、**需要添加 observable setter** |
| 2 | `scripts/ui/crosshair_view_model.gd` | 全文 (32行) | 现有 MVVM 绑定模式（aim_position + spread_ratio），**需要新增 element_type 字段** |
| 3 | `scripts/ui/crosshair.gd` | 全文 (110行) | CrosshairView 完整绘制逻辑，**_on_draw() 是核心修改点** |
| 4 | `scripts/components/c_aim.gd` | 24-29 行 | **参考模式**：CAim 的 spread_ratio observable setter 写法 |
| 5 | `scripts/ui/observable_property.gd` | 全文 | bind_component 的实现机制（查找 `{prop}_observable`） |

### 参考文件（不需要改，但值得看）

| 文件 | 用途 |
|------|------|
| `scripts/utils/elemental_utils.gd:6-9` | 4 种元素的 VISUAL_COLOR 常量定义 |
| `scripts/ui/views/view_hp_bar.gd:229-240` | `_get_element_color()` 颜色映射方法（复用配色） |
| `scripts/ui/views/view_hp_bar.gd:35` | preload CElementalAttack 的写法参考 |
| `scripts/ui/AGENTS.md` | MVVM 模式规范和反模式清单 |
| `scripts/components/AGENTS.md` | Component Observable setter 模式说明 |

---

## 关键风险与测试契约摘要

### 核心风险
1. **R2 — 组件动态增删**：玩家换武器时 CElementalAttack 可能被添加/移除/替换，但 `_try_bind_entity()` 只检查 entity 有效性不检测组件变化 → **需增强绑定逻辑**（见计划 Phase 2 Step 3 最后一点）
2. **R1 — 安全绑定**：玩家不一定有 CElementalAttack → `bind_to_entity` 中先 has_component 再 bind，无则设 -1
3. **R3 — 跨层引用**：Component 引用 ui/ 的 ObservableProperty → 项目既有模式（CAim 已这样做），保持一致

### 测试契约（5 项）
- **T1**：ViewModel 绑定后 element_type 值正确同步 FIRE → COLD 切换
- **T2**：无 CElementalAttack 时 element_type == -1（NONE）
- **T3**：unbind 后 element_type 重置为 -1
- **T4（Visual）**：持元素武器时准心下方出现对应颜色的脉冲指示器
- **T5（Visual）**：普通武器时准心外观不变，无额外图形

---

## 详细方案位置

完整的需求分析、影响面分析、实现方案（含伪代码）、架构约束、测试契约、风险点和分步实施计划详见：

**`/Users/dluckdu/Documents/Github/gol/docs/foreman/238/plans/01-planner-crosshair-element-type.md`**
