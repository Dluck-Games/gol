# Foreman Team Leader — 实现计划

Date: 2026-03-28
Spec: `docs/superpowers/specs/2026-03-28-foreman-team-leader-design.md`
Scope: `gol-tools/foreman/`

## 依赖关系

```
Phase 1 (Foundation)
  └── Phase 2 (TL Infrastructure)
        ├── Phase 3 (Prompt Templates) — 可与 Phase 4 并行
        └── Phase 4 (Daemon Rewire) — 可与 Phase 3 并行
              └── Phase 5 (Config & Cleanup)
                    └── Phase 6 (Integration Test)
```

---

## Phase 1: Foundation — 文档管理模块

### 1.1 新建 `lib/doc-manager.mjs`

文档目录管理器，负责序号分配、文件名校验、文档读写。

```js
// class DocManager
// constructor(baseDir)  — baseDir = config.workDir + '/docs/foreman'

// 公开方法：
// ensureIssueDir(issueNumber) → 创建 docs/foreman/{issueNumber}/
// getDocDir(issueNumber) → 返回路径
// nextSeq(issueNumber) → 读目录取最大序号 +1，返回 "01"-"99"
// validateFilename(filename) → /^\d{2}-\w+-[a-z0-9-]+\.md$/
// validateRequiredSections(filename, role) → 检查必填 heading
// listDocs(issueNumber) → 目录内 .md（排除 orchestration.md），按序号排序
// readDoc(issueNumber, filename) → 读单个文档
// readAllDocs(issueNumber) → 读所有（含 orchestration.md）
// readLatestDoc(issueNumber) → 序号最大的文档
// getOrchestrationPath(issueNumber) → orchestration.md 路径
// readOrchestration(issueNumber) → 读 orchestration.md
// appendOrchestration(issueNumber, content) → 追加
// initOrchestration(issueNumber, issueTitle, issueLabels, issueBody) → 初始化 Issue 段落
```

**必填段落常量：**

```js
const REQUIRED_SECTIONS = {
  planner: ['## 需求分析', '## 影响面分析', '## 实现方案', '## 测试契约', '## 风险点', '## 建议的实现步骤'],
  coder:   ['## 完成的工作', '## 测试契约覆盖', '## 决策记录', '## 仓库状态', '## 未完成事项'],
  reviewer:['## 审查范围', '## 验证清单', '## 发现的问题', '## 测试契约检查', '## 结论'],
  tester:  ['## 测试环境', '## 测试用例与结果', '## 发现的非阻塞问题', '## 结论'],
};
```

- [ ] 创建 `lib/doc-manager.mjs`
- [ ] 单元测试：序号分配、文件名校验、必填段落校验

### 1.2 精简 `lib/state-manager.mjs`

**从 task 对象删除的字段：**
- `feedback`、`rework_requirements`、`rework_count`、`failure_count`、`ci_retry_count`、`last_failure_reason`（全部迁移到文档）
- `issue_body`、`issue_labels`（在 orchestration.md 中）
- `coder_id`（运行时管理，不持久化）

**新增字段：**
- `doc_dir` — 文档目录路径
- `doc_seq` — 当前最大序号（缓存）

**删除方法：** `appendReworkRequirement()`、`getReworkRequirements()`

**修改方法：**
- `createTask()` — 简化字段
- `transition()` — 移除 failure_count/rework_count 自增

**state.json 版本：** v2 → v3，添加迁移

**TRANSITIONS map 更新：** 移除 `escalated`（不再需要），其余保留

- [ ] 精简 state-manager.mjs
- [ ] v2→v3 迁移逻辑
- [ ] 简化 `createTask()` 和 `transition()`

---

## Phase 2: TL Infrastructure — 调度器与决策解析

### 2.1 新建 `lib/tl-dispatcher.mjs`

替代 `scheduler.mjs`。

```js
// class TLDispatcher
// constructor(config, stateManager, processManager, docManager, promptBuilder, workspaceManager)

// async requestDecision(issueNumber, trigger)
//   1. 读 orchestration.md + 所有文档 + 最新文档
//   2. 组装 TL prompt
//   3. spawn TL agent，等待退出
//   4. 重新读 orchestration.md（TL 已追加）
//   5. parseLatestDecision() 解析
//   6. 返回决策对象

// parseLatestDecision(content)
//   解析最后一个 ### Decision N 块
//   提取：Action, Model, TL Context for {Agent}, Assessment, Guidance, GitHub Comment
//   Action 必须在 VALID_ACTIONS 内，否则返回 { action: 'abandon' }
```

**VALID_ACTIONS：**
```js
const VALID_ACTIONS = new Set([
  'spawn @planner', 'spawn @coder', 'spawn @reviewer', 'spawn @tester',
  'verify', 'abandon'
]);
```

**Trigger event 类型：**
```js
{ type: 'new_issue' }
{ type: 'agent_completed', agent: 'planner', document: '01-planner-xxx.md' }
{ type: 'ci_completed', passed: false, output: '...' }
{ type: 'doc_validation_failed', document: '02-coder-xxx.md', errors: [...] }
```

- [ ] 创建 `lib/tl-dispatcher.mjs`
- [ ] 实现 `parseLatestDecision()` 解析
- [ ] 单元测试：Decision 解析、无效 action 兜底

### 2.2 新建 `prompts/tl-decision.md`

**Placeholder：** `{{ISSUE_CONTEXT}}`、`{{TRIGGER_EVENT}}`、`{{ORCHESTRATION_CONTENT}}`、`{{DOC_LISTING}}`、`{{LATEST_DOC_CONTENT}}`、`{{AVAILABLE_MODELS}}`

**静态内容：**
- 角色定义（不读代码，只做调度）
- 决策规则（planner 先跑、CI 硬性 gate、3 次迭代 abandon、零中间评论）
- 可用动作：spawn @planner / @coder / @reviewer / @tester / verify / abandon
- Decision 格式模板
- 产出要求（追加 Decision，仅终态撰写 GitHub 评论）

- [ ] 创建 `prompts/tl-decision.md`

### 2.3 更新 `lib/prompt-builder.mjs`

**新增：** `buildTLPrompt({ issueContext, triggerEvent, orchestrationContent, docListing, latestDocContent, availableModels })`

**改造所有 worker build 方法：**

`buildCoderPrompt()`:
- 新增参数：`tlContext`、`planDoc`、`prevHandoff`、`docDir`、`seq`
- 新增 placeholder：`{{TL_CONTEXT}}`、`{{PLAN_DOC}}`、`{{PREV_HANDOFF}}`、`{{DOC_DIR}}`、`{{SEQ}}`
- 移除：`{{MODE}}`、`{{REWORK_SECTION}}`、`{{RETRY_SECTION}}`、`{{PLAN_SECTION}}`

`buildPlannerPrompt()`:
- 新增：`tlContext`、`docDir`、`seq`
- 新增 placeholder：`{{TL_CONTEXT}}`、`{{DOC_DIR}}`、`{{SEQ}}`
- 移除：`{{PLAN_OUTPUT}}`（产出改为 .md）

`buildReviewerPrompt()`:
- 新增：`tlContext`、`wsPath`、`docDir`、`seq`
- 新增 placeholder：`{{TL_CONTEXT}}`、`{{WS_PATH}}`、`{{DOC_DIR}}`、`{{SEQ}}`
- 移除：`{{REVIEW_OUTPUT}}`、`{{REWORK_SECTION}}`

`buildTesterPrompt()`:
- 新增：`tlContext`、`docDir`、`seq`
- 新增 placeholder：`{{TL_CONTEXT}}`、`{{DOC_DIR}}`、`{{SEQ}}`
- 移除：`{{TEST_OUTPUT}}`、`{{USER_INSTRUCTIONS}}`、`{{REWORK_SECTION}}`

**删除所有 fallback prompt 方法**（模板缺失应报错）

- [ ] 新增 `buildTLPrompt()`
- [ ] 改造 4 个 worker build 方法
- [ ] 删除 fallback 方法

---

## Phase 3: Prompt Templates — 重写

所有模板重写为：静态骨架 + `{{TL_CONTEXT}}` + 框架注入 + 文档产出要求。

### 3.1 重写 `prompts/planner-task.md`

- 产出改为 .md 文档（非 JSON）
- 移除 GitHub comment 发布
- 增加必填段落列表
- 保留代码库探索权限
- 保留 Edit/Write 禁用

- [ ] 重写 planner-task.md

### 3.2 重写 `prompts/coder-task.md`

- 统一由 TL_CONTEXT 提供任务指导（移除 MODE/REWORK/RETRY 分支）
- 增加交接文档产出要求和必填段落
- 保留 git push + PR 创建
- 移除 GitHub comment 权限

- [ ] 重写 coder-task.md

### 3.3 重写 `prompts/reviewer-task.md`

- 升级为对抗性审查（带代码库访问）
- 产出改为 .md 文档
- 增加验证清单和测试契约检查要求
- 移除 GitHub comment 权限
- 新增 {{WS_PATH}}

- [ ] 重写 reviewer-task.md

### 3.4 重写 `prompts/tester-task.md`

- 产出改为 .md 文档
- 移除 GitHub comment 权限
- 保留 AI Debug Bridge 使用流程

- [ ] 重写 tester-task.md

---

## Phase 4: Daemon Rewire — 核心改造

### 4.1 替换 scheduler

**导入变更：**
- 移除 `Scheduler`
- 新增 `TLDispatcher`、`DocManager`

**构造函数：**
- 移除 `this.#scheduler`
- 新增 `this.#docs = new DocManager(...)`
- 新增 `this.#tlDispatcher = new TLDispatcher(...)`

- [ ] 替换导入和初始化

### 4.2 改造 `#onProcessExit` — 统一 TL 调度

```js
async #onProcessExit(issueNumber, code, signal) {
  const task = this.#state.getTask(issueNumber);
  if (!task) return;
  const activeStates = ['planning', 'building', 'reviewing', 'testing'];
  if (!activeStates.includes(task.state)) return;

  const agentRole = { planning:'planner', building:'coder', reviewing:'reviewer', testing:'tester' }[task.state];

  // 文档校验
  const latestDoc = this.#docs.readLatestDoc(issueNumber);
  let trigger;
  if (latestDoc) {
    const errors = this.#docs.validateRequiredSections(latestDoc.filename, agentRole);
    trigger = errors.length > 0
      ? { type: 'doc_validation_failed', document: latestDoc.filename, errors }
      : { type: 'agent_completed', agent: agentRole, document: latestDoc.filename };
  } else {
    trigger = { type: 'agent_completed', agent: agentRole, document: null };
  }

  // coder 完成后先跑 CI（框架硬性规则）
  if (agentRole === 'coder') {
    const ci = await this.#runCiGate(task);
    if (ci !== null) {
      trigger = { type: 'ci_completed', passed: ci.passed, output: ci.output };
    }
  }

  await this.#requestTLDecision(issueNumber, trigger);
}
```

- [ ] 改造 `#onProcessExit`

### 4.3 新增 `#requestTLDecision` 和 `#executeTLDecision`

```js
async #requestTLDecision(issueNumber, trigger) {
  const decision = await this.#tlDispatcher.requestDecision(issueNumber, trigger);
  await this.#executeTLDecision(issueNumber, decision);
}

async #executeTLDecision(issueNumber, decision) {
  const task = this.#state.getTask(issueNumber);
  switch (decision.action) {
    case 'spawn @planner': await this.#spawnPlanner(task, decision); break;
    case 'spawn @coder':   await this.#spawnCoder(task, decision);   break;
    case 'spawn @reviewer': await this.#spawnReviewer(task, decision); break;
    case 'spawn @tester':  await this.#spawnTester(task, decision);  break;
    case 'verify':  await this.#handleVerify(task, decision);  break;
    case 'abandon': await this.#handleAbandon(task, decision); break;
  }
}
```

- [ ] 实现 `#requestTLDecision()`
- [ ] 实现 `#executeTLDecision()`

### 4.4 改造 spawn 方法

所有 spawn 方法接收 `decision` 对象，提取 `tlContext` 和 `model`。

**`#spawnPlanner(task, decision)`：**
- 保留 worktree 创建
- `buildPlannerPrompt()` 新增 tlContext
- decision.model 覆盖 roleConfig.model

**`#spawnCoder(task, decision)`：**
- 保留 worktree/分支管理
- docManager 读 planner 文档作为 planDoc
- docManager 读前序文档作为 prevHandoff
- `buildCoderPrompt()` 使用新参数

**`#spawnReviewer(task, decision)`：**
- 新增 wsPath 传递
- 移除 reworkRequirements 传递

**`#spawnTester(task, decision)`：**
- 移除 userInstructions 参数

- [ ] 改造 `#spawnPlanner()`
- [ ] 改造 `#spawnCoder()`
- [ ] 改造 `#spawnReviewer()`
- [ ] 改造 `#spawnTester()`

### 4.5 简化 CI Gate

- 移除重试逻辑（重试由 TL 决定）
- 只执行一次 CI，返回 `{ passed, output, summary }` 或 `null`
- 不再直接 spawn coder 修复

- [ ] 简化 `#runCiGate()`

### 4.6 新增终态处理

**`#handleVerify(task, decision)`：**
- 发 GitHub 评论（decision.githubComment）
- `foreman:progress` → `foreman:done`
- Telegram 通知
- 清理 worktree
- state.removeTask()

**`#handleAbandon(task, decision)`：**
- 发 GitHub 评论（含原因说明）
- `foreman:progress` → `foreman:blocked`
- 通知
- 清理 worktree
- state.abandon()

- [ ] 实现 `#handleVerify()`
- [ ] 实现 `#handleAbandon()`

### 4.7 改造 GitHub Sync

**Inbound 保留：**
- 轮询 `foreman:assign` 发现新 issue
- 创建 task 时调用 `docManager.ensureIssueDir()` + `docManager.initOrchestration()`
- 立即替换标签 `foreman:assign` → `foreman:progress`
- 触发 `#requestTLDecision(issueNumber, { type: 'new_issue' })`

**移除：**
- `foreman:testing` 手动触发入口
- 中间状态标签映射（所有内部状态统一为 `foreman:progress`）
- 用户评论获取用于 rework（`getLatestUserComment()` 不再在 rework 流中调用）

**Orphan recovery 简化：**
- 只从 `foreman:assign` 和 `foreman:progress` 恢复
- 重建 task 后通过 `docs/foreman/{N}/orchestration.md` 恢复上下文

- [ ] 改造 `#runGithubSync()`
- [ ] 简化 orphan recovery
- [ ] 移除 `foreman:testing` 触发

### 4.8 删除废弃方法

| 方法 | 替代 |
|------|------|
| `#handlePlanned()` | TL 决策 |
| `#handleEvaluated()` | TL 决策 |
| `#handleTested()` | TL 决策 |
| `#runScheduler()` | tl-dispatcher |
| `#executeAction()` | `#executeTLDecision()` |
| `#validateReworkChecks()` | TL 读 reviewer 文档 |
| `#readReviewResult()` / `#readPlanResult()` / `#readTestResult()` | docManager |
| `#reviewPath()` / `#planPath()` / `#testPath()` | docManager |
| `#ensureReviewsDir()` / `#ensurePlansDir()` / `#ensureTestsDir()` | docManager |
| `#buildVerifiedSummary()` | TL 撰写评论 |
| `#cleanupPlanFile()` | 文档永久保留 |
| `#readPlanContent()` | docManager |

- [ ] 删除废弃方法
- [ ] 验证无残留引用

---

## Phase 5: Config & Cleanup

### 5.1 更新 `config/default.json`

```json
{
  "roles": {
    "tl": {
      "client": "codebuddy",
      "model": "glm-5.0-turbo-ioa",
      "maxTurns": 30,
      "disallowedTools": ["AskUserQuestion", "EnterPlanMode", "Edit", "Write", "NotebookEdit"]
    },
    "planner": {
      "maxTurns": 50,
      "disallowedTools": ["AskUserQuestion", "EnterPlanMode", "Edit", "Write", "NotebookEdit"]
    },
    "reviewer": {
      "disallowedTools": ["AskUserQuestion", "EnterPlanMode", "Edit", "Write", "NotebookEdit"]
    },
    "tester": {
      "model": "kimi-k2.5-ioa",
      "maxTurns": 80,
      "disallowedTools": ["AskUserQuestion", "EnterPlanMode"]
    }
  },
  "labels": {
    "assign": "foreman:assign",
    "progress": "foreman:progress",
    "done": "foreman:done",
    "blocked": "foreman:blocked"
  }
}
```

**变更：**
- 新增 `roles.tl`（maxTurns: 30，禁止编辑工具）
- 新增 `roles.reviewer`（禁止编辑工具）
- 标签精简为 4 个（移除 plan/build/rework/testing/cancelled/escalate）
- 移除 `ci.maxRetries`（重试由 TL 决定）
- 移除 `backoff` 配置段（退避由 TL 决定）

- [ ] 更新 config/default.json
- [ ] 更新 config-utils.mjs migrateConfig()

### 5.2 删除 `lib/scheduler.mjs`

- [ ] 删除文件
- [ ] 移除导入

### 5.3 清理 `.foreman/` 目录

不再使用：`.foreman/plans/`、`.foreman/reviews/`、`.foreman/tests/`

保留：`.foreman/state.json`、`.foreman/logs/`、`.foreman/cancel/`、`.foreman/progress/`、`.foreman/workspaces/`

- [ ] 移除 daemon start() 中的目录创建
- [ ] 适配 `bin/foreman-ctl.mjs` 显示新状态

### 5.4 GitHub 标签清理

在仓库中创建 `foreman:progress` 标签，移除不再使用的标签：

- [ ] `gh label create "foreman:progress" -R Dluck-Games/god-of-lego`
- [ ] 移除 `foreman:plan`、`foreman:build`、`foreman:rework`、`foreman:testing` 标签

---

## Phase 6: Integration Test

### 6.1 端到端验证

手动创建测试 issue + `foreman:assign`，验证：

- [ ] orchestration.md 包含完整 Decision 链
- [ ] 所有文档文件名符合格式
- [ ] 所有文档包含必填段落
- [ ] 用户只看到 foreman:assign → foreman:progress → foreman:done
- [ ] GitHub 评论只在终态出现（非中间步骤）
- [ ] state.json 只包含精简字段
- [ ] worktree 清理正常
- [ ] docs/foreman/{N}/ 永久保留

### 6.2 异常路径验证

- [ ] CI 失败 → TL 内部决策 rework → 用户不感知
- [ ] Reviewer 发现架构问题 → TL 回 planner → 用户不感知
- [ ] 文档校验失败 → TL 收到 trigger 并决策
- [ ] 内部迭代超过 3 次 → TL abandon → 用户看到 foreman:blocked + 评论
- [ ] TL 返回无效 action → 自动 abandon 兜底
- [ ] daemon 重启后从 foreman:progress 标签恢复

---

## 文件变更清单

### 新增
| 文件 | 描述 |
|------|------|
| `lib/doc-manager.mjs` | 文档目录管理器 |
| `lib/tl-dispatcher.mjs` | TL 调度器 |
| `prompts/tl-decision.md` | TL prompt 模板 |

### 删除
| 文件 | 替代 |
|------|------|
| `lib/scheduler.mjs` | tl-dispatcher.mjs |

### 重写
| 文件 | 描述 |
|------|------|
| `prompts/planner-task.md` | 新模板（.md 产出 + TL_CONTEXT） |
| `prompts/coder-task.md` | 新模板（统一 TL_CONTEXT） |
| `prompts/reviewer-task.md` | 新模板（对抗性审查 + 代码库访问） |
| `prompts/tester-task.md` | 新模板（.md 产出） |

### 改造
| 文件 | 幅度 |
|------|------|
| `foreman-daemon.mjs` | 大 — 替换调度核心、改造 spawn/handle |
| `lib/state-manager.mjs` | 中 — 精简字段、v2→v3 迁移 |
| `lib/prompt-builder.mjs` | 中 — 新增 TL、改造 worker 方法 |
| `lib/github-sync.mjs` | 小 — 移除中间标签、简化 outbound |
| `config/default.json` | 小 — TL 配置、标签精简 |
| `lib/config-utils.mjs` | 小 — migrateConfig 适配 |
| `bin/foreman-ctl.mjs` | 小 — 显示新状态 |

### 不变
| 文件 | 原因 |
|------|------|
| `lib/process-manager.mjs` | 接口不变 |
| `lib/workspace-manager.mjs` | 接口不变 |
| `lib/notifier.mjs` | 触发方式变但接口不变 |
| `lib/logger.mjs` | 不变 |
| `lib/progress-writer.mjs` | 不变 |
