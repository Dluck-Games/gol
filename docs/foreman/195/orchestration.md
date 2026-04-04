# Orchestration — Issue #195

## Issue
**Title:** 角色/怪物受到冻结伤害后偶现丢失移动动画
**Labels:** bug, topic:visual, foreman:assign
**Body:**
**Bug 描述：**
当角色或怪物受到冻结伤害（冰冻效果）后，有时会出现移动时丢失动画的问题。

**具体场景（基于观察）：**
1. 角色或怪物受到冰冻/冻结相关的伤害效果。
2. 效果触发/结束后，实体在移动时没有播放正常的移动（行走/跑动）动画。
3. 角色/怪物像是在地上"平移"滑行。

**期望行为：**
受到冻结伤害且解除或过程中，实体的移动动画状态机应能正常过渡回移动动画。

**实际行为：**
偶现状态机卡死或动画未恢复，导致移动动画丢失。

**环境：**
- 游戏版本：最新开发版本
- 影响对象：Player & Monsters

---

## Decision Log
| # | Action | Summary |
|---|--------|--------|
| D1 | spawn @planner | initial-analysis — 首次规划 |
| D2 | spawn @coder | implement — 首次实现 v1 |
| D3 | spawn @reviewer | full-review — 首次审查 |
| D4 | spawn @coder | rework — 审查后修复 |
| D5 | spawn @reviewer | full-review | rework 后审查 |
| D6 | spawn @coder | ci-fix — CI 修复 |
| D7 | spawn @reviewer | full-review | CI fix 后审查 |
| D8 | spawn @coder | rework — 文档格式修复 |
| D9 | spawn @reviewer | full-review | 文档格式审查 |
| D10 | spawn @coder | rework | 新周期重做 |
| D11 | spawn @reviewer | full-review | 重做后完整审查 |
| D12 | spawn @coder | rework | 测试契约补充修复 |
| D13 | spawn @reviewer | full-review | 契约补充审查 |
| D14 | spawn @coder | rework | 文档重写修复 |
| D15 | spawn @reviewer | full-review | 文档重写审查 |
| D16 | spawn @tester | e2e-acceptance | E2E 验收测试 |
| D17-D25 (×9) | verify | 连续九轮终态确认 — 交付完成 |
| 21 | verify | - **技术状态：已全部完成且经五轮独立决策确认（D17 → D18 → D19 → D20 → D21）** |
