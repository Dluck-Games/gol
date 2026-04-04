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
| 1 | spawn @planner | 初始分析 |
| 2 | spawn @planner | 重分析 |
| 3 | spawn @coder | 实现 v1 |
| 4 | spawn @reviewer | 全量审查 |
| 5 | spawn @reviewer | rework 审查 |
| 6 | spawn @coder | rework |
| 7 | spawn @reviewer | rework 审查 |
| 8 | spawn @reviewer | rework 审查（D11 规则） |
| 9 | spawn @reviewer | rework 审查（D13 规则） |
| 10 | spawn @tester | E2E 验收 |
| 11 | spawn @reviewer | 文档格式验证 |
| 12-16 | (历史迭代) | 规划→编码→审查→测试完成 |
| 17-27 | verify | 终态确认（连续十一轮复验通过） |
| 23 | verify | - Issue #195 的修复工作已在之前的完整调度周期中完成并经六轮独立决策确认终态为 verify（D17 → D18 → D19 → D20 → D21 |
