# Decision 4 — 2026-04-05 07:28
**Trigger:** Reviewer agent 完成 full-review，结论为 `rework`。审查报告 `02-reviewer-electric-pickup-hit-fix.md` 发现了 4 个问题，其中 Critical 1 个、Important 1 个、Minor 2 个。
**Assessment:** Reviewer 对 Issue #198 的实现进行了全面审查（10 个源码/测试文件），P1/P2/P3 三个 Phase 的核心逻辑基本符合计划设计。但发现两个必须修复的问题：

1. **[Critical] `s_elemental_affliction.gd:103` 缩进错误**：ELECTRIC case 仅 2 tab（应在 match 块内为 3 tab），导致 ELECTRIC 效果无条件执行（脱离 match 分支），所有 affliction 类型实体都会被错误施加 Electric DoT + aim disturbance。
2. **[Important] `s_fire_bullet.gd:_get_visual_spread_angle()` clamp 未包含 `electric_affliction_jitter`**：准星视觉显示 total_jitter（weapon + affliction），但实际弹道散布只 clamp 到 weapon.spread_degrees，视觉反馈与实际命中率严重不符。

这两个问题都是代码实现层面的 bug，不是架构缺陷，无需回退 planner 重设计。调度轮次 0/3，远未达 abandon 阈值。
**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** 修复 Reviewer 报告中的 Critical 和 Important 问题。Minor 问题本轮不处理。
**TL Context for @coder:**
> ## 任务：Rework Issue #198 — 修复 Reviewer 审查发现的关键问题
>
> ### 工作空间
> - **代码目录**: `/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260405062557._7a2c1d10`
> - **分支**: `foreman/issue-198`
>
> ### 必读文档
> 1. `/Users/dluckdu/Documents/Github/gol/docs/foreman/198/plans/01-planner-electric-pickup-hit-fix.md` — 计划基准（4.3 节和 4.4 节是修复参考）
> 2. `/Users/dluckdu/Documents/Github/gol/docs/foreman/198/iterations/02-reviewer-electric-pickup-hit-fix.md` — **审查报告全文，问题描述和修复建议都在此文件中**
>
> ### 必须修复的问题（按优先级）
>
> **问题 #1 [Critical] — `scripts/systems/s_elemental_affliction.gd:103` 缩进错误**
>
> `_apply_tick_effect()` 函数中 match 语句的 ELECTRIC case 当前只有 **2 tab** 缩进，位于 match 块外部（与 `match element_type:` 同级）。正确位置应在 match 内部（与 FIRE case 的 3 tab 同级）。
>
> **根因**：原 main 分支此位置就有缩进缺陷，本次 PR 在其基础上修改时未修正，反而将内容体从 4 tab 改为 3 tab，进一步偏离。
>
> **修复动作**：
> - 将第 103 行 `COMPONENT_ELEMENTAL_ATTACK.ElementType.ELECTRIC:` 从 2 tab 改为 **3 tab**
> - 将第 104-106 行 ELECTRIC case 内容体从 3 tab 改为 **4 tab**
> - 使其与 FIRE case（第 101-102 行）保持完全一致的缩进层级
>
> **修复后验证**：
> - 确认 GDScript 解析器将 ELECTRIC 视为 match 的合法 case 而非独立语句
> - 确认现有单元测试 `test_electric_applies_aim_disturbance` 等仍通过（缩进修复后行为应更正确）
>
> **问题 #2 [Important] — `scripts/systems/s_fire_bullet.gd` 的 `_get_visual_spread_angle()` 函数**
>
> 当前代码：
> ```gdscript
> return clampf(aim.spread_angle_degrees, -weapon.spread_degrees, weapon.spread_degrees)
> ```
>
> 问题：`weapon.spread_degrees` 不包含 `electric_affliction_jitter`，导致实际弹道散布范围小于准星视觉显示的抖动范围。
>
> **采用方案 A（推荐）**：修改 clamp 上限使其包含 affliction jitter：
> ```gdscript
> var effective_max_spread := weapon.spread_degrees
> var aim_comp: CAim = entity.get_component(CAim)
> if aim_comp:
>     effective_max_spread += aim_comp.electric_affliction_jitter
> return clampf(aim.spread_angle_degrees, -effective_max_spread, effective_max_spread)
> ```
>
> ### 本轮不处理的问题（明确跳过）
> - Minor #3：SCrosshair/STrackLocation 每帧重置 jitter 的数据竞争模式（当前执行顺序已保证安全）
> - Minor #4：集成测试缺 Tracker 共存场景编排（后续迭代补充即可）
>
> ### 约束
> - 只修改上述两个问题的相关文件和行，不做额外功能添加或重构
> - 保持现有测试通过，如有必要可更新受影响的测试断言
> - 遵循 AGENTS.md 命名规范和代码风格（tab 缩进、静态类型、class_name）
> - 不要执行 git add / git commit / git push / gh pr create 等操作
>
> ### 产出要求
> 完成修复后输出 handoff 文档到 `docs/foreman/198/iterations/` 目录，说明每个问题的修复内容和涉及的文件/行号变更。
