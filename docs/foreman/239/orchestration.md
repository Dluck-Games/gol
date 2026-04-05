# Orchestration — Issue #239

## Issue
**Title:** bug(crosshair): 玩家无远程武器时不应显示准心
**Labels:** bug, topic:gameplay, topic:visual, foreman:assign
**Body:**
## Bug 描述

当玩家不拥有任何远程武器（即无 `CWeapon` 组件）时，游戏中仍然显示远程武器准心（`CrosshairView`），与当前玩家状态不符。

## 期望行为

玩家没有 `CWeapon` 组件时，准心应完全隐藏（不渲染）。当玩家捡到远程武器后准心重新出现。

## 实际行为

准心始终可见，即使玩家没有任何远程武器。

## 可能原因

`CrosshairView` 在 `_try_bind_entity()` 中只检查 `CPlayer` + `CAim`，未检查 `CWeapon` 是否存在。建议绑定实体时额外判断 `CWeapon`，或在 `_on_draw()` 中当 weapon == null 时跳过绘制。

## 顺带建议（重命名）

`CWeapon` 语义较宽泛，可考虑更名为 `CShooterWeapon`，以明确表示该组件专指远程射击武器，与近战逻辑区分。

## 涉及文件

- `scripts/ui/crosshair.gd`（`CrosshairView`）
- `scripts/ui/crosshair_view_model.gd`（`CrosshairViewModel`）
- `scripts/systems/s_crosshair.gd`（`SCrosshair`，query 条件为 `CAim`）
- `scripts/components/c_weapon.gd`（`CWeapon`）

---

## Decision Log
| # | Action | Summary |
|---|--------|--------|
| 1 | spawn @planner | 新 issue，无历史决策、计划或迭代记录。Issue 描述清晰，包含 Bug 复现路径、期望行为、可能原因分析及涉及文件列表。需要 @planner 先进行代 |
| 2 | spawn @coder | 计划质量优秀。根因定位精确（`s_crosshair.gd:45` 无条件赋值 + `crosshair.gd:89` query 缺 `CWeapon`），方 |
| 3 | spawn @reviewer | Coder 已完成全部计划实施。修改 3 个文件（`s_crosshair.gd`、`crosshair.gd`、`s_track_location.gd`）， |
| 4 | spawn @reviewer | Reviewer agent 执行完成但未按预期写入审查结论文档。iterations 目录中仅有 `01-planner-handoff-crosshair- |
| 5 | spawn @coder | Reviewer 对生产代码给出明确 PASS 判定——三处源码修复（`s_crosshair.gd`、`crosshair.gd`、`s_track_loca |
| 6 | spawn @reviewer | Coder 第 2 次 rework（基于 Decision 5 的测试质量要求）产出质量显著优于第 1 次尝试（`04-coder-rework-test-q |
| 7 | verify | Reviewer 对第 2 次 test-quality rework 给出明确 PASS 判定： |
