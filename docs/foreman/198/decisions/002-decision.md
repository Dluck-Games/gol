# Decision 2 — 2026-04-05 06:35
**Trigger:** doc_validation_failed — 计划文档 01-planner-electric-pickup-hit-fix.md 未通过框架验证（缺失标准章节头匹配）
**Assessment:** Planner 已完成技术分析并产出了高质量计划文档（452 行）。文档实质包含全部 7 个必需章节（需求分析/影响面分析/实现方案/架构约束/测试契约/风险点/建议的实现步骤），每个章节均有具体的文件路径、行号、代码片段和测试断言。验证失败原因为章节标题使用了中文序号前缀（`## 一、需求分析`）而非框架期望的纯标题格式（`## 需求分析`），属于格式问题而非内容缺陷。计划质量足够进入实现阶段，无需回退 Planner 重做。
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**Guidance:** 按计划文档分 Phase 实现，先改 P1（spread conflict 阵营判断），再改 P2+P3（affliction aim disturbance），最后补测试。每步完成后运行 gdUnit4 验证。
**TL Context for @coder:**
> ## 任务：实现 Issue #198 — 雷属性组件拾取/受击效果优化
>
> ### 工作空间
> - **代码目录**: `/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260405062557._7a2c1d10` （gol-project 子模块 worktree）
> - **所有代码修改在此 worktree 内完成**
>
### 必读文档（按顺序）
> 1. `/Users/dluckdu/Documents/Github/gol/docs/foreman/198/plans/01-planner-electric-pickup-hit-fix.md` — **主计划文档，你的唯一实现依据**
> 2. `/Users/dluckdu/Documents/Github/gol/docs/foreman/198/iterations/01-planner-handoff-electric-pickup-hit-fix.md` — 交接文档，含必读文件清单和快速索引
> 3. `gol-project/AGENTS.md` — 项目架构和命名规范
>
> ### 实现要求（严格按计划的 Phase 顺序）
>
> **Phase 1 — P1 修复：SElectricSpreadConflict 排除玩家**
> - 修改 `scripts/systems/s_electric_spread_conflict.gd` 的 `_process_entity()`：增加 CCamp 判断，PLAYER 跳过 spread 惩罚
> - 更新 `tests/unit/system/test_electric_spread_conflict.gd`：添加 player 不受 spread 的测试用例
> - 运行 gdUnit4 验证
>
> **Phase 2 — P2+P3：Electric Affliction Aim Disturbance**
> - 扩展 `scripts/components/c_aim.gd`：新增 `electric_affliction_jitter` 字段 + ObservableProperty
> - 修改 `scripts/systems/s_elemental_affliction.gd`：
>   - Electric 分支调用 `_apply_electric_aim_disturbance()`
>   - `_clear_afflictions()` 中重置 jitter
>   - 新增常量
> - 修改 `scripts/systems/s_crosshair.gd:_update_display_aim`：叠加 affliction jitter
> - 修改 `scripts/systems/s_track_location.gd:_update_display_aim`：同步叠加 + Tracker 衰减逻辑
> - 编写新单元测试（affliction system 扩展 + crosshair + tracker interaction）
> - 运行全量测试
>
> **Phase 3 — 集成测试**
> - 创建 `tests/integration/flow/test_flow_electric_pickup_hit_scenario.gd`
> - 运行全部测试套件确认通过
>
> ### 关键约束
> - **不要重命名 system 文件** — 字母序决定 gameplay 组内执行顺序（s_elemental_affliction < s_crosshair < s_track_location），写入 jitter 必须在读取之前
> - Component 是 pure data，ObservableProperty setter pattern 参照现有字段写法
> - 所有 `.gd` 文件必须有 `class_name`，使用 tab 缩进，静态类型标注
> - 测试文件放在正确目录：unit 在 `tests/unit/system/`，integration 在 `tests/integration/flow/`
> - 文档和注释使用中文
> - **禁止执行 git add / git commit / git push / gh pr create** — 这些由框架处理
>
> ### 验收标准（必须全部通过）
> - P1: PLAYER+Electric 武器 → spread 不变；ENEMY+Electric → spread+15°
> - P2: 有 CAim+ELECTRIC affliction → electric_affliction_jitter > 0；清除后归零
> - P3: CTracker 存在时 affliction jitter 受衰减（推荐 ×0.5）
> - 回归: Cold freeze / Electric DoT / 传播链不受影响
> - gdUnit4 全量测试通过（无失败/错误）
