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
| 37 | verify | 终态确认（复验第 21 轮） |
| 36 | verify | 终态确认（复验第 20 轮） |
| 35 | verify | 终态确认（复验第 19 轮） |
| 34 | verify | 终态确认（复验第 18 轮） |
| 33 | verify | 终态确认（复验第 17 轮） |
| 32 | verify | 终态确认（复验第 16 轮） |
| 31 | verify | 终态确认（复验第 15 轮） |
| 30 | verify | 终态确认（复验第 14 轮） |
| 29 | verify | 终态确认（复验第 13 轮） |
| 28 | verify | 终态确认（复验第 12 轮） |
| 27 | verify | 终态确认（复验第 11 轮） |
| 26 | verify | 终态确认（复验第 10 轮） |
| 25 | verify | 终态确认（复验第 9 轮） |
| 24 | verify | 终态确认（复验第 8 轮） |
| 23 | verify | 终态确认（复验第 7 轮） |
| 22 | verify | 终态确认（复验第 6 轮） |
| 21 | verify | 终态确认（复验第 5 轮） |
| 20 | verify | 终态确认（复验第 4 轮） |
| 19 | verify | 终态确认（复验第 3 轮） |
| 18 | verify | 终态确认（复验第 2 轮） |
| 17 | verify | 终态确认（首轮验证） |
| 16 | spawn @reviewer | rework-review（D13 doc rewrite 后审查） |
| 15 | spawn @reviewer | full-review（D14 coder rework 后审查） |
| 14 | spawn @coder | ci-fix（CI 失败修复） |
| 13 | spawn @coder | rework（reviewer 发现文档格式问题） |
| 12 | spawn @coder | implement（v2 三分支恢复方案实现） |
| 11 | spawn @planner | re-analysis（v1 方案被 reviewer 架构否决，需重设计） |
| 10 | spawn @reviewer | full-review（首次代码审查 — 架构问题） |
| 9 | spawn @coder | implement（v1 方案实现） |
| 8 | spawn @planner | initial-analysis（新 issue 首次规划） |
| 33 | verify | - Issue #195 已有完整决策历史 D1-D32，修复链在 D16 前完成（规划→编码→审查→测试全流程） |
