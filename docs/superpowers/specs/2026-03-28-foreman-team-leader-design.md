# Foreman Team Leader 架构重设计

Date: 2026-03-28
Status: Approved
Scope: gol-tools/foreman

## 背景与动机

当前 Foreman 使用硬编码状态机（scheduler.mjs + completion handlers）进行 agent 调度。从 PR #187/#188/#189 的审核中发现系统性质量问题：

- Coder 不做影响面分析，修改函数时不追踪调用方
- 测试是空壳占位，不验证实际系统行为
- CI 失败后 pipeline 继续流转（"CI retries exhausted — proceeding to reviewer despite test failures"）
- Reviewer 无代码库访问权限，只能读 diff
- E2E Tester 无结果 = 自动通过

根本原因：流水线式架构缺乏智能决策能力，每个 issue 不管难度、类型、风险走同一条路径。

## 核心设计理念

**Foreman 必须一次性交付正确的结果，对用户完全无需人工干预。** 所有内部迭代（planner ↔ coder ↔ reviewer 之间的反复）发生在后台，用户不感知。用户只看到两个状态：正在处理、已完成。没有"打回"、没有"rework"、没有中间状态标签。

## 设计目标

1. 引入 Team Leader (@tl) 角色替代硬编码状态机，实现智能调度
2. 从 JSON artifact 通信改为文档驱动通信，所有 agent 产出可追溯的 .md 文档
3. 原 @planner 的编排调度职责剥离给 @tl，@planner 专注需求分析和实现规划
4. TL 拥有 GitHub 交互独占权，worker agent 零外部交互
5. Prompt 模板 = 静态骨架 + TL 动态段落，由 Foreman 框架组装
6. 用户视角极简：`foreman:assign` → `foreman:progress` → `foreman:done` / `foreman:blocked`，内部迭代完全透明

## 角色与职责

### 5 个角色定义

| 角色 | 职责 | 产出 | GitHub 权限 |
|------|------|------|------------|
| @tl | 读所有文档 → 决策下一步谁来 → 填写 prompt 动态段落 → 追加 orchestration.md | orchestration.md（追加） | 评论、标签、通知 — 独占 |
| @planner | 读 issue + 代码库 → 需求分析 + 影响面追踪 + 测试契约 + 实现方案 | {seq}-planner-{desc}.md | 无 |
| @coder | 读 plan + TL 动态指导 → 实现代码 + 写测试 | {seq}-coder-{desc}.md | 无 |
| @reviewer | 读 PR diff + 代码库 → 对抗性审查（尝试找到会破坏的东西） | {seq}-reviewer-{desc}.md | 无 |
| @tester | 读 test spec → AI Debug Bridge 黑盒测试 → 带证据的测试报告 | {seq}-tester-{desc}.md | 无 |

### 与当前架构的关键变化

- 原 @planner 的"编排调度"职责剥离给 @tl
- @reviewer 从"读 diff"升级为"带代码库访问的对抗性验证"
- 所有 worker agent 零 GitHub 交互，TL 是唯一对外声音
- @planner 永远先跑，自行决定产出深度（TL 不跳过 planner，而是由 planner 自行判断轻量/完整计划）

## 文档驱动的信息流

### 核心原则

Agent 之间不传递 JSON artifact，不传递 session 记录，只通过 .md 文档通信。

### 文档目录结构

```
docs/foreman/{issue-number}/
  ├── orchestration.md                          ← TL 持久文档，每次追加
  ├── 01-planner-bullet-hp-analysis.md          ← @planner 产出
  ├── 02-coder-fix-bullet-target-filter.md      ← @coder 产出
  ├── 03-reviewer-chp-side-effect-found.md      ← @reviewer 产出
  ├── 04-coder-rework-preserve-box-blocking.md  ← @coder rework 产出
  └── 05-tester-bullet-collision-verified.md    ← @tester 产出
```

### 文件命名规则

- 格式：`{seq}-{agent}-{kebab-case-desc}.md`
- seq：两位数字序号，由 Foreman 框架分配（读目录内已有文件取最大序号 +1）
- agent：角色名称（planner / coder / reviewer / tester）
- desc：3-5 个英文单词，kebab-case，由 agent 自行命名，描述本次工作的核心内容
- 框架校验正则：`/^\d{2}-\w+-[a-z0-9-]+\.md$/`

### Agent 输入/输出

| Agent | 输入 | 输出 |
|-------|------|------|
| @tl | issue 上下文 + orchestration.md + 目录内所有 .md | 追加 orchestration.md + 结构化决策 |
| @planner | issue 上下文 + TL 动态段落 + 代码库访问 | {seq}-planner-{desc}.md |
| @coder | planner 文档 + TL 动态段落 + 代码库访问 | {seq}-coder-{desc}.md |
| @reviewer | PR diff + 相关 agent 文档 + TL 动态段落 + 代码库访问 | {seq}-reviewer-{desc}.md |
| @tester | test spec（从 planner 文档提取）+ TL 动态段落 + 游戏运行时 | {seq}-tester-{desc}.md |

### JSON 退化

当前的 plans/*.json、reviews/*.json、tests/*.json 全部替换为 .md 文档。JSON 只保留 state.json 用于 daemon 的调度状态。

## TL 决策机制

### TL 生命周期

每个决策点 spawn 一个新的 TL 会话（无状态，文档即记忆）：

**orchestration.md 初始化：** 新 issue 进入时，daemon 创建 `docs/foreman/{issue-number}/` 目录并初始化 orchestration.md（写入 Issue 段落：title、labels、body）。orchestration.md 不遵循 `{seq}-{agent}-{desc}.md` 命名规则，它是 TL 的持久文档，固定名称。

**决策触发流程：**

1. Daemon 检测到需要决策（agent 退出、CI 完成、新 issue 进来）
2. Daemon 组装 TL prompt：静态模板 + issue 上下文 + orchestration.md + 目录内所有 .md 文档
3. Spawn TL agent 进程
4. TL 读文档 → 产出两样东西：追加内容写入 orchestration.md；结构化决策输出给 daemon
5. TL 退出，daemon 执行决策

### orchestration.md 结构

```markdown
# Orchestration — Issue #188

## Issue
**Title:** 子弹被无HP实体消耗
**Labels:** bug, combat
**Body:** （原文）

---

## Decision Log

### Decision 1 — 2026-03-28 10:30
**Trigger:** New issue assigned
**Action:** spawn @planner
**Guidance:** 需要分析 _is_valid_bullet_target() 的所有调用方和受影响实体类型
**Model:** glm-5-turbo

### Decision 2 — 2026-03-28 10:45
**Trigger:** @planner completed (01-planner-bullet-hp-analysis.md)
**Assessment:** Plan 质量充分——影响面追踪到了 boxes/loot，测试契约完整
**Action:** spawn @coder
**Model:** glm-5-turbo
**TL Context for Coder:**
> Planner 发现 CHP 过滤会影响 ComponentDrop 和 SpawnerLoot...
> 测试契约：1) 无CHP实体不消耗子弹 2) 箱子仍可拦截子弹...
```

### 决策输出解析

TL 的结构化决策从 orchestration.md 最新 Decision 条目中提取固定字段（Action、Model 等），不需要额外的 JSON 输出通道。

### TL 动作词汇表

| Action | 含义 |
|--------|------|
| spawn @planner | 启动 planner 分析 |
| spawn @coder | 启动 coder 实现/rework |
| spawn @reviewer | 启动 reviewer 审查 |
| spawn @tester | 启动 tester E2E 验收 |
| verify | 任务通过，关闭流程 |
| abandon | 放弃任务（TL 在评论中说明原因：能力不足、需求不清、超出重试限制等） |

### TL 决策边界

**可以决定：**
- 下一步 spawn 谁
- 用什么模型/客户端
- 给 worker 的动态 prompt 内容（TL Context）
- 是否重试、放弃

**不能决定：**
- 修改需求范围（必须 abandon 并说明）
- 跳过 CI（CI 是框架层硬性 gate）
- 直接修改代码

**必须 abandon 的场景：**
- 内部迭代超过 3 次仍未解决
- Planner 报告 issue 需求不清晰
- Reviewer 发现需求本身有矛盾

### 用户可见标签（仅 4 个）

| 标签 | 含义 |
|------|------|
| `foreman:assign` | 用户输入：交给 Foreman |
| `foreman:progress` | 正在处理（合并所有内部状态） |
| `foreman:done` | 完成交付 |
| `foreman:blocked` | 无法完成（含需求不清、能力不足、需人类介入等所有失败场景） |

内部状态（planning、building、reviewing 等）只存在于 state.json 和 orchestration.md 中，不映射到 GitHub 标签。

## Prompt 模板架构

### 模板文件

```
prompts/
  ├── tl-decision.md
  ├── planner-task.md
  ├── coder-task.md
  ├── reviewer-task.md
  └── tester-task.md
```

### 模板内部结构（以 coder-task.md 为例）

```markdown
## 角色定义（静态）
你是 GOL 项目的实现工程师。你的工作是根据计划文档实现代码并编写测试。

## 工作规则（静态）
- 在 {{BRANCH}} 分支上工作
- 遵循 AGENTS.md 中的代码规范
- 完成后 git push origin {{BRANCH}}
- ...

## 任务上下文（TL 动态生成）
{{TL_CONTEXT}}

## 计划文档（框架注入）
{{PLAN_DOC}}

## 前序交接文档（框架注入，可选）
{{PREV_HANDOFF}}

## 产出要求（静态）
完成后写交接文档到 {{DOC_DIR}}/{{SEQ}}-coder-{你的主题描述}.md

文档必须包含对应角色的必填段落。
文件名 desc 部分：3-5 个英文单词，kebab-case，描述本次核心工作。
```

### TL 模板特殊性

tl-decision.md 接收所有历史文档而非单个前序文档：

```markdown
## 角色定义（静态）
你是 GOL 项目的 Team Leader。你负责阅读所有工作文档，
决定下一步由哪个 Agent 接手，并为其编写任务指导。
你不直接读代码，不实现功能，只做调度决策。

## 决策规则（静态）
- Planner 永远先跑，你决定 plan 质量是否足够往下走
- CI 是硬性 gate，不可跳过
- 内部迭代超过 3 次必须 abandon
- 你是唯一和 GitHub 交互的角色
- 所有内部迭代对用户不可见，不发中间评论

## 可用动作（静态）
spawn @planner | spawn @coder | spawn @reviewer | spawn @tester
verify | abandon

## 可用模型（静态，随配置更新）
- glm-5-turbo（默认，免费）
- kimi-k2.5-ioa（多模态场景）

## Issue 上下文（框架注入）
{{ISSUE_CONTEXT}}

## 当前触发事件（框架注入）
{{TRIGGER_EVENT}}

## Orchestration 历史（框架注入）
{{ORCHESTRATION_CONTENT}}

## 工作目录文档列表（框架注入）
{{DOC_LISTING}}

## 最新文档内容（框架注入）
{{LATEST_DOC_CONTENT}}

## 产出要求（静态）
1. 追加一条 Decision 到 orchestration.md
2. 仅在终态（verify / abandon）时撰写 GitHub 评论摘要，中间决策不发评论
```

### 框架组装流程

```
Daemon 收到触发事件
  → 读 orchestration.md + 文档目录
  → 填充 tl-decision.md 模板 → spawn TL
  → TL 返回 → 解析 orchestration.md 最新 Decision
  → 根据 Action 填充对应 worker 模板（TL Context 注入 {{TL_CONTEXT}}）
  → spawn worker
```

TL 不直接组装 worker prompt。TL 只产出 TL Context for {Agent} 文本，由 Foreman 框架注入到 worker 模板的 {{TL_CONTEXT}} 槽位。

## Worker Agent 文档产出规范

### @planner 必填段落

- 需求分析
- 影响面分析（受影响的文件/函数、调用链追踪、受影响的实体/组件类型）
- 实现方案
- 测试契约（checkbox 列表）
- 风险点
- 建议的实现步骤

### @coder 必填段落

- 完成的工作（修改/新增了哪些文件，为什么）
- 测试契约覆盖（对照 planner 的契约，标注已覆盖/未覆盖及原因）
- 决策记录
- 仓库状态（branch、commit SHA、测试结果）
- 未完成事项

### @reviewer 必填段落

- 审查范围
- 验证清单（实际执行的验证动作：grep 了什么、追踪了哪些调用链）
- 发现的问题（含严重程度、置信度、文件位置、建议）
- 测试契约检查
- 结论（verified / rework 附理由）

### @tester 必填段落

- 测试环境
- 测试用例与结果（每个 case 含操作、预期、实际、证据、结果）
- 发现的非阻塞问题
- 结论（pass / fail 附理由）

### 框架层校验

Agent 退出后 daemon 检查产出文档：
1. 文件名格式校验：`/^\d{2}-\w+-[a-z0-9-]+\.md$/`
2. 必填段落校验：检查对应角色的必填 heading 是否存在
3. 校验失败处理：作为 trigger event 传给 TL 决策（不自动重试）

## Daemon 改造

### 模块变化

| 模块 | 变化 |
|------|------|
| scheduler.mjs | 删除，由 tl-dispatcher.mjs 替代 |
| tl-dispatcher.mjs | 新增，每个决策点调用 TL |
| doc-manager.mjs | 新增，文档目录管理（序号分配、文件名校验、读写） |
| prompt-builder.mjs | 改造，增加 TL Context 注入能力 |
| state-manager.mjs | 精简，只保留机械状态 |
| process-manager.mjs | 保留不变 |
| workspace-manager.mjs | 保留不变 |
| github-sync.mjs | 精简为只做 inbound（发现 issue），outbound 交给 TL |
| notifier.mjs | 保留，由 TL 决策触发 |

### state.json 精简

```json
{
  "version": 3,
  "tasks": {
    "188": {
      "state": "building",
      "issue_id": 188,
      "issue_title": "子弹被无HP实体消耗",
      "branch": "foreman/issue-188-bullet-consumed",
      "workspace": "/path/to/worktree",
      "pr_number": null,
      "current_process_pid": 12345,
      "doc_dir": "docs/foreman/188",
      "doc_seq": 3,
      "created_at": "2026-03-28T10:00:00Z",
      "updated_at": "2026-03-28T11:20:00Z"
    }
  }
}
```

删除的字段：rework_requirements、feedback、plan（全部在文档里）、rework_count、failure_count（TL 从 orchestration.md 的 Decision 历史中自行判断）。

### CI Gate 处理

- CI 仍由 daemon 执行（gdUnit4 --headless），不经过 TL
- CI 结果作为 trigger event 传给 TL
- TL 读 CI 输出决定下一步（修复当前"CI 失败后盲目继续"的问题）
- CI 不可跳过是框架层硬性规则

### GitHub 交互改造

**用户可见标签仅 4 个：** `foreman:assign`、`foreman:progress`、`foreman:done`、`foreman:blocked`

- Inbound（保留在 daemon）：github-sync.mjs 轮询 `foreman:assign` 发现新 issue
- 进入处理时：daemon 立即将 `foreman:assign` 替换为 `foreman:progress`
- 终态时由 daemon 执行 TL Decision 中的 GitHub 操作：
  - verify → 发 TL 撰写的评论 + 将 `foreman:progress` 替换为 `foreman:done`
  - abandon → 发 TL 撰写的评论 + 将 `foreman:progress` 替换为 `foreman:blocked`
- 内部迭代期间不变更标签、不发评论
- 移除 `foreman:testing` 手动触发入口（E2E 测试由 TL 内部决策）
- 移除外部 rework 机制（`foreman:rework` 标签删除）
- Orphan recovery 只从 `foreman:assign` 和 `foreman:progress` 恢复

## 完整流程走读（Issue #188）

### 用户视角

```
用户给 issue #188 打上 foreman:assign 标签
  → 标签变为 foreman:progress（自动）
  → （后台工作，用户不感知任何中间状态）
  → 标签变为 foreman:done + GitHub 评论总结 + PR 就绪
```

### 内部流程（正常路径）

```
1. github-sync 发现 issue #188 + foreman:assign
   → daemon 创建 docs/foreman/188/，初始化 orchestration.md
   → 标签替换为 foreman:progress
2. TL 决策：spawn @planner → 追加 Decision 1
3. @planner 产出 01-planner-bullet-hp-analysis.md
4. TL 评估 plan → 决策：spawn @coder → 追加 Decision 2
5. @coder 产出 02-coder-fix-bullet-target-filter.md
6. daemon 运行 CI → 通过
7. TL 决策：spawn @reviewer → 追加 Decision 3
8. @reviewer 产出 03-reviewer-chp-filter-verified.md，结论 verified
9. TL 决策：verify → 追加 Decision 4
10. daemon 发 GitHub 评论 + 标签替换为 foreman:done + 清理 worktree
11. docs/foreman/188/ 永久保留
```

### 内部流程（CI 失败 — 用户不感知）

```
6b. CI 失败 → trigger event 传给 TL
7b. TL 判断是编译错误 → 决策：spawn @coder
    → TL Context: "只修测试文件中的 NEUTRAL 引用，不动实现代码"
8b. @coder 修复 → 产出 03-coder-fix-neutral-enum-ref.md
9b. CI 重跑 → 通过 → 继续正常流程
    （用户始终看到 foreman:progress，不知道内部发生了迭代）
```

### 内部流程（Reviewer → Planner 回退 — 用户不感知）

```
8c. @reviewer 发现方案有副作用 → 产出 03-reviewer-chp-side-effect-found.md
9c. TL 评估：方案层面的问题
    → 决策：spawn @planner（不是回 coder）
    → TL Context: "Reviewer 发现当前方案的副作用，需要重新设计"
10c. @planner 重新分析 → 产出 04-planner-revised-bullet-approach.md
11c. 流程继续...
     （用户始终看到 foreman:progress）
```

### 内部流程（超过迭代限制 — abandon）

```
多次迭代未能解决 → TL 判断已超过 3 次内部迭代
  → 决策：abandon
  → TL 撰写评论说明无法完成的原因和已尝试的方案
  → daemon 发 GitHub 评论 + 标签替换为 foreman:blocked
```
