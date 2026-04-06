# Orchestration — Issue #238

## Issue
**Title:** feat(crosshair): 在准心 UI 展示当前元素伤害类型
**Labels:** topic:gameplay, topic:visual, feature, foreman:assign
**Body:**
## 功能描述

当玩家拥有 `CElementalAttack` 组件（即捡到了带元素属性的武器）时，准心 UI 应显示当前元素伤害类型的视觉提示，告知玩家「你现在拥有元素伤害，类型是 XX」。

## 目标效果

在准心附近（如准心下方或右下角）展示一个元素图标或文字标签，例如：
- 🔥 FIRE
- 💧 WET
- ❄️ COLD
- ⚡ ELECTRIC

玩家未拥有元素伤害时，该提示不显示。

## 涉及系统

- **数据来源**：`CElementalAttack.element_type`（枚举：FIRE / WET / COLD / ELECTRIC）
- **展示层**：`CrosshairView` / `CrosshairViewModel`（位于 `scripts/ui/crosshair.gd` 和 `scripts/ui/crosshair_view_model.gd`）
- **建议实现**：在 `CrosshairViewModel` 中新增 `elemental_type` ObservableProperty，绑定玩家实体的 `CElementalAttack` 组件；`CrosshairView._on_draw()` 中读取该属性并绘制对应颜色/图标

## 参考

- `CElementalAttack`：`scripts/components/c_elemental_attack.gd`
- `CrosshairView` 当前已有电击特效颜色（`ELECTRIC_COLOR`），可参考此模式扩展其他元素颜色

---

## Decision Log
| # | Action | Summary |
|---|--------|--------|
| 1 | spawn @planner | 首次调度。Issue 描述清晰：需要在准心 UI 展示玩家当前的元素伤害类型（FIRE/WET/COLD/ELECTRIC），数据来源为 `CElemental |
| 2 | spawn @coder | 计划质量良好。Planner 分析了现有 Crosshair MVVM 链路、CElementalAttack 组件结构、元素颜色体系（elemental_ut |
| 3 | spawn @reviewer | Coder 已按计划完成全部 4 个文件修改：`c_elemental_attack.gd`（observable setter）、`crosshair_vie |
| 4 | spawn @coder | Reviewer 完成了第 1 轮全量审查，结论为 **rework**（需修复后重新审查）。发现 3 个问题： |
| 5 | spawn @reviewer | Coder 已完成第 2 轮修复（rework），针对 Reviewer 报告的问题做了如下处理： |
| 6 | verify | 第 2 轮 Rework-Review 审查完成。Reviewer 对 Coder 第 2 轮修复做了逐项验证： |
