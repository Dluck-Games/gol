# Handoff: Foreman Prompt Architecture Redesign

Date: 2026-03-31
Session focus: 设计 foreman 提示词架构重构方案，包括分层模板、Task 多态、TL 作为上下文路由器、worktree 复用等核心设计决策。

## User Requests (Verbatim)

- "分析下 foreman 目前的提示词框架"
- "我有一份 obsidian 笔记《Foreman 提示词结构》设计了一份新的提示词结构，比较粗略。以及，刚刚我使用 Jinja2 重构了提示词模板。还有一份研究，说明了 codebuddy 客户端如何处理提示词拼接。结合这些资料与我的意向设计，我希望重构这个提示词结构，使其可以更加可靠及可以复用。/brainstroming 请你和我一起设计一份新的提示词架构。"
- "我想继续聊一下，为什么我们需要摘要策略，以及为何如此设计"
- "我好奇的是，为什么会 handoff 全文注入 coder 的提示词里呢？"
- "好，这是一个问题，所有工作应该复用 worktree，这个设计需要更新到 spec 中。然后，handoff 全文注入的设计是错误的，要改正，应该由 tl 根据所有 doc 的全文情况来理解问题，将 coder 需要的 context 给他。也就是通过 tl 的 task 模板 + 自由 tl context 注入的形式，先让 tl 读 handoff 理解情况，做出 coder 需要什么样上下文的决策，然后把需要的上下文给 coder。更新 spec 改正这里的设计。"
- "现在讨论下一个问题，prompt 中任何'和当前任务无关'的上下文都可以被剔除，越短越好。审查目前设计中每个角色最终收到的提示词，有哪些是不需要的，或者说，单轮次中涉及到的任务完成所多余的部分。"
- "第一步就错了，planner 从 tl 那里或通过 foreman 系统注入获取issue 的上下文，而不是自己命令行获取 issue 内容。当提示词进入的时候它已经知道了 issue body，包括标题、描述、所有评论。coder 需要知道自己的分支，但是不需要知道 issue，它已经从 tl 拿到了问题需要的上下文，commit 可能需要讨论下是 foreman 负责还是 coder 自己提交。reviewer 同理，不给 bash 权限，只通过读代码 diff 审查内容。tester 可以不关心 pr，但是需要留下 playtest 截图证据，交给 tl 负责是否需要上传 Github。tl 应该屏蔽代码读取权限，但是给它安排一个 explore 子代理，禁止 tl 直接读取代码，通过手下了解项目上下文。"
- "把我们今天的讨论记录到交接文档"

## Goal

完成 spec 定稿（用户尚未正式 approve），然后进入 implementation plan 阶段。

## Work Completed

- 分析了 foreman 当前 5 个单体提示词模板的完整架构（identity + rules + task + output 格式全耦合在 1 个文件中）
- 分析了 doc-manager 完整 API（27 个方法，无摘要能力，无截断逻辑）
- 分析了 CodeBuddy 客户端的 7 层提示词架构（全不可控，只有 `-p` 的 user message 可控）
- 验证了 Nunjucks 支持所有需要的能力：动态 include、ignore missing、macros、trimBlocks/lstripBlocks
- 确认了用户已有的 Jinja2 → Nunjucks 重构已完成（prompt-builder.mjs 已迁移）
- 读取了 Obsidian 笔记《Foreman 提示词结构》和《CBC 提示词架构》两份设计参考
- 读取了 CodeBuddy 子代理文档（https://www.codebuddy.ai/docs/zh/cli/sub-agents）
- 完成了多轮 brainstorming，确立了所有设计决策
- 写入了 spec v1 → 用户反馈后修正为 v2（TL context routing 替代摘要管线）
- 进行了逐角色 prompt 精简审查，识别了每个角色不需要的注入项和权限变化
- 写入了 spec v2 → `docs/superpowers/specs/2026-03-31-foreman-prompt-architecture-design.md`

## Current State

- Spec v2 已写入但**尚未经过最新一轮精简审查的更新**。最后一轮讨论（user 的修正反馈）产生了以下尚未写入 spec 的变更：

### 尚未写入 spec 的变更（来自最后一轮审查）

1. **Planner**: 删掉 `seq`（永远是 `01`）、`repo`（issue body 由 daemon 注入，planner 不调 `gh`）
2. **Coder**: 删掉 `issueId`、`issueTitle`（所有上下文在 TL Context 里）；保留 `branch`
3. **Reviewer**: 删掉 `issueId`、`issueTitle`、`wsPath`；**新增 `prDiff`（daemon 注入 diff 全文）**；**disallowedTools 加入 `Bash`**（reviewer 不调 `gh`，代码读取通过 Read/Grep/Glob + daemon 注入的 diff）
4. **Tester**: 删掉 `issueTitle`、`prId`、`repo`；**task 模板删除 Step 7 提 Bug Issue**（截图证据交给 TL 决定是否上传 GitHub）
5. **TL**: **disallowedTools 加入 `Read`, `Grep`, `Glob`, `LS`, `Bash`**；**新增 `explorer` 子代理**（通过 `--agents` CLI 标志注入，tools: Read/Grep/Glob/LS，model: gemini-3.0-flash）

### Spec 中已有的核心设计（v2）

- 5 层分层模型：Identity → Rules → Task → TL Context → Runtime Facts
- 纯 include 组装（不用 extends）
- 两级规则复用：shared.md + readonly-agent.md / write-agent.md
- Task 多态：TL Decision 新增 `Task` 字段，planner 2 / coder 3 / reviewer 2 / tester 1
- 默认 Task 映射表兜底
- TL 作为上下文路由器（daemon 不再注入 planDoc/prevHandoff 全文）
- Worktree 复用（`workspace-manager.getOrCreate()`）
- 摘要管线已移除（TL Context 就是最好的摘要）
- PromptBuilder 统一接口 `buildPrompt(role, task, ctx)`
- TL Decision 格式增加 `Task` 字段

### Spec 中需要同步更新的部分（最后一轮审查后）

- §3 Entry Templates: 每个角色的 Runtime Facts 需要按上述精简方案更新
- §5 Task Templates: reviewer 的 task 模板需要去掉 `gh` 命令步骤，改为 Read diff 注入的内容
- §6 Context Routing: reviewer 部分需要更新（新增 daemon 注入 prDiff）
- §10 File Change Summary: 需要新增 `lib/workspace-manager.mjs` 的 `getOrCreate()` 变更描述
- 新增 § TL Explorer 子代理: 描述 `--agents` 注入机制和 TL 的权限限制
- 新增 § 权限矩阵: 总结每个角色的 allowedTools/disallowedTools 变化
- config/default.json: reviewer 的 disallowedTools 需要加 Bash；TL 的 disallowedTools 需要加 Read/Grep/Glob/LS/Bash

## Pending Tasks

- **将最后一轮审查的变更写入 spec v3**（上述 5 个角色的变更 + explorer 子代理 + 权限矩阵）
- 用户 review spec v3
- 用户 approve 后 → 调用 writing-plans skill 创建 implementation plan
- 实现分层模板重构

## Key Files

- `docs/superpowers/specs/2026-03-31-foreman-prompt-architecture-design.md` — 主 spec 文档（当前 v2，需更新到 v3）
- `gol-tools/foreman/prompts/tl-decision.md` — TL 当前单体模板（参考源）
- `gol-tools/foreman/prompts/planner-task.md` — Planner 当前单体模板（参考源）
- `gol-tools/foreman/prompts/coder-task.md` — Coder 当前单体模板（参考源）
- `gol-tools/foreman/prompts/reviewer-task.md` — Reviewer 当前单体模板（参考源）
- `gol-tools/foreman/prompts/tester-task.md` — Tester 当前单体模板（参考源）
- `gol-tools/foreman/lib/prompt-builder.mjs` — Nunjucks 模板引擎（已迁移，需改 API）
- `gol-tools/foreman/lib/tl-dispatcher.mjs` — Decision 解析（需加 task 字段）
- `gol-tools/foreman/lib/process-manager.mjs` — 进程管理（TL 需加 `--agents` 参数）
- `gol-tools/foreman/lib/workspace-manager.mjs` — Workspace 生命周期（需加 `getOrCreate()`）

## Important Decisions

- **TL 作为上下文路由器（而非 daemon 机械拼接）**: daemon 不再读取 planDoc/prevHandoff 全文注入 coder prompt。TL 读所有文档，写 TL Context 给下游。这是架构层面最根本的变化。
- **Worktree 复用**: 不再 destroy+create，coder 在同一个 worktree 上累积 commits。
- **LLM 摘要管线被移除**: 既然 TL 已经在读完所有文档后写 TL Context，摘要管线是多余的。
- **Planner 的 issue body 必须由 daemon 注入**: 不是让 planner 自己 `gh issue view`。
- **Reviewer 不给 Bash 权限**: diff 由 daemon 注入到 prompt 中，reviewer 用 Read/Grep/Glob 读完整源码。
- **Tester 不提 Bug Issue**: 截图证据留在测试报告里，TL 决定是否需要上传 GitHub。
- **TL 屏蔽代码读取权限**: 通过 disallowedTools 禁止 Read/Grep/Glob/LS/Bash，注入 explorer 子代理（gemini-3.0-flash）用于偶尔验证文件路径。
- **Commit 由框架管理**: coder 不执行 git add/commit/push，保持现有设计。
- **Task 缺失时用默认映射表兜底**: 每个 Action 有 default task，TL 忘了写也不崩溃。
- **一次性替换旧模板**: 不做版本并存。

## Constraints

- "所有工作应该复用 worktree"
- "handoff 全文注入的设计是错误的，应该由 tl 根据所有 doc 的全文情况来理解问题，将 coder 需要的 context 给他"
- "planner 从 tl 那里或通过 foreman 系统注入获取issue 的上下文，而不是自己命令行获取 issue 内容"
- "coder 需要知道自己的分支，但是不需要知道 issue"
- "reviewer 同理，不给 bash 权限，只通过读代码 diff 审查内容"
- "tester 可以不关心 pr，但是需要留下 playtest 截图证据，交给 tl 负责是否需要上传 Github"
- "tl 应该屏蔽代码读取权限，但是给它安排一个 explore 子代理，禁止 tl 直接读取代码，通过手下了解项目上下文"
- CodeBuddy 子代理能力参考：https://www.codebuddy.ai/docs/zh/cli/sub-agents

## Context for Continuation

- Spec 当前是 v2，**最后一轮审查的变更尚未写入**。下一步应该先更新 spec 到 v3（逐角色精简 + explorer 子代理 + 权限矩阵），然后让 user review。
- 用户 approve 后调用 writing-plans skill 创建 implementation plan。
- 用户的思考方式是"每多一个 token 就多一分噪声"——他会在每次审查中追问"这个真的需要吗？"。更新 spec 时要确保每个注入项都有明确的存在理由。
- 用户对 foreman 的设计有很强的主见和清晰的方向感。实现时要严格遵循 spec，不要自作主张"改进"设计。
- `--agents` CLI 标志的格式是 JSON 字符串，传入 codebuddy CLI 作为参数。process-manager.mjs 需要在 spawn TL 时特殊处理。
- reviewer 的 diff 注入需要 daemon 在 `#spawnReviewer()` 前调用 `gh pr diff` 获取全文，然后作为 template 变量传入。这是一个新的 daemon 职责。
- 角色权限变化（尤其是 reviewer 失去 Bash）需要同步更新 config/default.json 和各 role 的 disallowedTools/allowedTools。
- 用户的 Obsidian vault（Notes）中有两份参考笔记：《Foreman 提示词结构》和《CBC 提示词架构》。读取方式：`notesmd-cli print "笔记路径" -v "Notes"`。

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
