# Handoff: Foreman 产出代码架构一致性保障

Date: 2026-03-28
Session focus: 设计 Foreman agent 产出代码的架构一致性保障机制

## User Requests (Verbatim)

- "foreman 的架构决策，和代码一致性保证是谁在负责？比如单元测试规范是否符合项目？代码是否尽可能在已有架构上进行拓展？"
- "我说的不是 foreman 本身，这个只需要加一个待办更新 AGENTS md就可以了。是 foreman 产出代码的质量。因为之前出现的问题是，产出的代码不遵循项目的设计规范。"
- 确认不需要引入架构师角色，通过强化 planner + reviewer 闭环解决
- 覆盖范围：全部（架构模式、分层约定、文件组织、测试模式）

## Goal

实现 spec 方案（3 个文件改动），并处理遗留事项（更新 gol-tools/AGENTS.md）。

## Work Completed

- 分析了 Foreman TL 架构中产出代码质量的治理缺口
- 讨论并否决了引入架构师角色的方案（增加调度复杂度，与 planner 职责重叠）
- 确定方案：强化 @planner 产出架构约束 + @reviewer 对照验证的闭环
- 撰写并提交了 spec 文档：`docs/superpowers/specs/2026-03-28-foreman-architecture-compliance-design.md`

## Current State

- Foreman TL 架构重设计已完成 Phase 1-5（5 个 commits in gol-tools），Issue #206 做了首次端到端验证
- Spec 文档已写入但未 commit
- `gol-tools/AGENTS.md` 仍是旧架构描述（引用已删除的 scheduler.mjs、旧标签等），需要更新
- `docs/foreman/206/` 下有 Issue #206 的 TL 流程验证产出文档（orchestration.md + planner 分析）

## Pending Tasks

### Task 1: 实现 spec 方案（3 个文件改动）

Spec 路径：`docs/superpowers/specs/2026-03-28-foreman-architecture-compliance-design.md`

具体改动：

1. **`gol-tools/foreman/prompts/planner-task.md`** — 在「实现方案」和「测试契约」之间插入 `### 架构约束` 必填段落，要求 planner：
   - 列出涉及的 AGENTS.md 文件
   - 引用具体架构模式并说明理由
   - 标注文件归属层级
   - 标注测试模式
   - 无现有模式时显式说明

2. **`gol-tools/foreman/prompts/reviewer-task.md`** — 在「验证清单」段落的检查项后追加「架构一致性对照」固定检查项（5 项），架构违规 severity 标为 Important

3. **`gol-tools/foreman/lib/doc-manager.mjs`** — `REQUIRED_SECTIONS.planner` 数组新增 `'## 架构约束'`，插入在 `'## 实现方案'` 之后

### Task 2: 更新 gol-tools/AGENTS.md（遗留事项）

当前 AGENTS.md 描述的是旧架构，需要同步 TL 架构改动：
- `scheduler.mjs` → `tl-dispatcher.mjs`
- `worker-task.md` → `coder-task.md`，新增 `tl-decision.md`
- 标签列表更新为 4 个（assign/progress/done/blocked）
- Lifecycle 更新为 TL 驱动的文档流
- 新增 `doc-manager.mjs` 模块描述
- 删除 `scheduler.mjs` 相关描述

## Key Files

- `docs/superpowers/specs/2026-03-28-foreman-architecture-compliance-design.md` — 架构一致性 spec（完整方案）
- `docs/superpowers/specs/2026-03-28-foreman-team-leader-design.md` — TL 架构 spec（背景参考）
- `gol-tools/foreman/prompts/planner-task.md` — 待改动：planner prompt 模板
- `gol-tools/foreman/prompts/reviewer-task.md` — 待改动：reviewer prompt 模板
- `gol-tools/foreman/lib/doc-manager.mjs` — 待改动：必填段落常量
- `gol-tools/AGENTS.md` — 待更新：过时的架构描述

## Important Decisions

- **不引入架构师角色**：planner 已有代码库访问权和需求理解上下文，拆出独立角色会增加调度复杂度且信息重叠
- **planner 定义 → reviewer 验证的闭环**：架构约束由 planner 在 plan 中显式产出，reviewer 对照检查，coder 无需额外 prompt 改动（读 plan 即可）
- **架构违规 severity = Important**：不是 Minor，因为架构偏离的修复成本随时间增长
- **覆盖全部层面**：ECS/GECS、MVVM、GOAP、分层约定、文件组织、测试模式

## Constraints

- gol-tools 是 git submodule，改动需先 push submodule 再更新 parent repo
- Foreman 使用纯 ESM（.mjs）、node:test、node:assert，无外部依赖
- 不要改动 coder-task.md、tester-task.md、tl-decision.md

## Context for Continuation

- 先读 spec 文档了解完整方案，再读当前 3 个待改文件的内容
- planner-task.md 和 reviewer-task.md 已在 TL 架构重设计中被重写过（commit 5cee4c8），基于当前版本改动即可
- doc-manager.mjs 是新模块（commit a29c66f），REQUIRED_SECTIONS 常量在文件顶部附近
- AGENTS.md 更新可参考 TL 架构 spec 中的模块变化表和标签定义
- Issue #206 的 orchestration.md（`docs/foreman/206/orchestration.md`）是 TL 流程的实际运行记录，可作为 AGENTS.md lifecycle 描述的参考

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
