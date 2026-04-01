# Foreman Prompt Architecture Redesign

**Date:** 2026-03-31
**Scope:** Prompt template layering, task polymorphism, worktree reuse, TL-driven context routing
**Out of scope:** Codebuddy client internals (不可控的7层), agent model selection, CI/CD, LLM summary pipeline

## Overview

Replace the current 5 monolithic prompt templates with a layered, composable architecture using Nunjucks includes. Introduce task polymorphism so the TL selects specific task templates per spawn action. Fix the workspace lifecycle to reuse worktrees across iterations. Shift context injection from daemon mechanical concatenation to TL intelligent routing — TL reads all handoff documents and writes precisely what the downstream agent needs.

**Motivation:**

1. **Rule duplication** — "禁止 gh issue close" repeated across all 5 templates, easy to desync
2. **No task polymorphism** — planner re-analysis and initial analysis use the same prompt
3. **Context bloat via mechanical injection** — daemon concatenates planDoc + prevHandoff full text into coder prompt (~26-63KB on multi-iteration issues). The agent that needs the context (TL) already has it; the downstream agent (coder) receives it blindly.
4. **Workspace churn** — daemon destroys and recreates worktrees on every coder spawn, losing git state and forcing full re-checkout
5. **Tight coupling** — identity, rules, workflow, and output format mixed in one file

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Layer model | 5-layer include assembly | Clear separation of concerns |
| Assembly mode | Pure include (no extends) | Simpler, each entry is a readable "bill of materials" |
| Rule reuse | 2-level: shared.md + readonly/write | Catches all duplication without over-abstracting |
| Task polymorphism | TL Decision adds `Task` field | Enables differentiated prompts per scenario |
| Task fallback | Default mapping table | Graceful degradation when TL omits Task field |
| Output format location | Embedded in task template | Each task may have slightly different output requirements |
| TL Context | Free text (no schema) | Flexibility, rely on TL prompt examples |
| TL context injection | Index table + latest doc full | Adequate for decision-making without bloat |
| Context routing | TL writes what downstream needs | TL reads all docs, writes targeted context; daemon does NOT inject handoff full text |
| Workspace lifecycle | Reuse worktree across iterations | No destroy+recreate; coder works on same branch with accumulated commits |
| Summary pipeline | Deferred | Not needed with TL-driven context routing; can add later if needed |
| Migration | One-time replacement | No version coexistence complexity |

---

## 1. Prompt Layer Model

The prompt passed to `-p` (user message) is assembled from 5 layers in order:

```
┌──────────────────────────────────────────────────┐
│  Layer 1: Identity        │ 角色身份 (1 file/role) │
├──────────────────────────────────────────────────┤
│  Layer 2: Shared Rules    │ shared.md + 权限级     │
├──────────────────────────────────────────────────┤
│  Layer 3: Task Template   │ TL 选择的任务模板       │
├──────────────────────────────────────────────────┤
│  Layer 4: TL Context      │ TL 自由文本指导         │
├──────────────────────────────────────────────────┤
│  Layer 5: Runtime Facts   │ daemon 注入的事实数据   │
└──────────────────────────────────────────────────┘
```

Layers 1-2 are static (seldom change). Layer 3 is polymorphic (TL selects). Layer 4 is dynamic per decision — **this is where all handoff context flows**, written by TL after reading all documents. Layer 5 is injected from daemon state.

### Key principle: TL is the context router

The TL agent reads **all documents** (orchestration history + latest doc full text). When it decides to spawn a downstream agent, it writes **TL Context** that contains precisely what that agent needs — extracted from its understanding of all the documents.

```
TL reads: orchestration (index) + latestDoc (full) + all previous docs (via Read tool)
           ↓
TL understands: what happened, what went wrong, what needs to happen next
           ↓
TL writes TL Context: targeted, concise guidance for the specific agent
           ↓
Downstream agent receives: TL Context (smart) + docDir path (to Read if needed)
```

**Daemon does NOT inject planDoc, prevHandoff, or any document full text into non-TL agent prompts.** Only TL gets full documents; downstream agents get TL Context + file paths.

---

## 2. Directory Structure

```
prompts/
├── _base/
│   ├── identity/
│   │   ├── tl.md
│   │   ├── planner.md
│   │   ├── coder.md
│   │   ├── reviewer.md
│   │   └── tester.md
│   └── rules/
│       ├── shared.md           # 全角色通用禁令
│       ├── readonly-agent.md   # TL/Planner/Reviewer
│       └── write-agent.md      # Coder/Tester
│
├── tasks/
│   ├── tl/
│   │   └── decision.md
│   ├── planner/
│   │   ├── initial-analysis.md
│   │   └── re-analysis.md
│   ├── coder/
│   │   ├── implement.md
│   │   ├── rework.md
│   │   └── ci-fix.md
│   ├── reviewer/
│   │   ├── full-review.md
│   │   └── rework-review.md
│   └── tester/
│       └── e2e-acceptance.md
│
└── entry/                      # Assembly entry points (Nunjucks main templates)
    ├── tl.md
    ├── planner.md
    ├── coder.md
    ├── reviewer.md
    └── tester.md
```

旧的单体模板文件（`prompts/tl-decision.md`, `prompts/planner-task.md` 等）全部删除。

---

## 3. Entry Templates

### 3.1 `entry/planner.md`

```jinja2
{# === Layer 1: Identity === #}
{% include "_base/identity/planner.md" %}

---

{# === Layer 2: Rules === #}
{% include "_base/rules/shared.md" %}
{% include "_base/rules/readonly-agent.md" %}

---

{# === Layer 3: Task === #}
{% include "tasks/planner/" + taskTemplate + ".md" %}

---

{# === Layer 4: TL Context === #}
{% if tlContext %}
## 任务上下文（来自 Team Leader）
{{ tlContext }}
{% endif %}

---

{# === Layer 5: Runtime Facts === #}
## 运行时信息
- **Issue**: #{{ issueId }} - {{ issueTitle }}
- **Workspace**: {{ wsPath }}
- **文档目录**: {{ docDir }}
{% if issueBody %}

## Issue 描述
{{ issueBody }}
{% endif %}
```

### 3.2 `entry/coder.md` (no document injection)

```jinja2
{% include "_base/identity/coder.md" %}

---

{% include "_base/rules/shared.md" %}
{% include "_base/rules/write-agent.md" %}

---

{% include "tasks/coder/" + taskTemplate + ".md" %}

---

{% if tlContext %}
## 任务上下文（来自 Team Leader）
{{ tlContext }}
{% endif %}

---

## 运行时信息
- **Workspace**: {{ wsPath }}
- **Branch**: {{ branch }}
- **文档目录**: {{ docDir }}
- **文档序号**: {{ seq }}

## 工作文档
所有工作文档位于: `{{ docDir }}`
如需查阅计划文档或前序交接文档，请用 Read 工具读取对应文件。
```

**Key change:** No `planDoc`, no `prevHandoff`, no `planSummary`, no `issueId`/`issueTitle`. Coder gets:
- TL Context (what TL decided it needs to know)
- docDir path (to Read any document if needed)
- Everything else is in the worktree's git history (since we reuse worktrees)

### 3.3 `entry/tl.md`

TL is the only agent that receives full documents from daemon:

```jinja2
{% include "_base/identity/tl.md" %}

---

{% include "_base/rules/shared.md" %}
{% include "_base/rules/readonly-agent.md" %}

---

{% include "tasks/tl/" + taskTemplate + ".md" %}

---

## Issue 上下文
{{ issueContext }}

## 当前触发事件
{{ triggerEvent }}

{% if systemAlerts and systemAlerts != "None" %}
## System Alerts
{{ systemAlerts }}
{% endif %}

## Orchestration 历史
{{ orchestrationContent }}

## 工作目录文档列表
{{ docListing }}

## 最新文档内容
{{ latestDocContent }}

## Latest Decision
{{ latestDecision }}

## 可用模型
{{ availableModels }}
```

### 3.4 `entry/reviewer.md`

```jinja2
{% include "_base/identity/reviewer.md" %}

---

{% include "_base/rules/shared.md" %}
{% include "_base/rules/readonly-agent.md" %}

---

{% include "tasks/reviewer/" + taskTemplate + ".md" %}

---

{% if tlContext %}
## 任务上下文（来自 Team Leader）
{{ tlContext }}
{% endif %}

---

## 运行时信息
- **PR**: #{{ prId }}
- **Repository**: {{ repo }}
- **文档目录**: {{ docDir }}
- **文档序号**: {{ seq }}

## 工作文档
所有工作文档位于: `{{ docDir }}`
请 Read 相关文档了解实现细节和测试契约。
```

### 3.5 `entry/tester.md`

```jinja2
{% include "_base/identity/tester.md" %}

---

{% include "_base/rules/shared.md" %}
{% include "_base/rules/write-agent.md" %}

---

{% include "tasks/tester/" + taskTemplate + ".md" %}

---

{% if tlContext %}
## 任务上下文（来自 Team Leader）
{{ tlContext }}
{% endif %}

---

## 运行时信息
- **Issue**: #{{ issueId }}
- **Workspace**: {{ wsPath }}
- **文档目录**: {{ docDir }}
- **文档序号**: {{ seq }}
```

---

## 4. Base Layer Files

### 4.1 `_base/identity/planner.md`

```markdown
## 角色定义
你是一个规划代理。你分析 issue、探索代码库、制定实现方案。
你**不写代码**，**不修改文件**（除了产出文档）。
```

(Each identity file is 3-5 lines. Minimal, focused.)

### 4.2 `_base/rules/shared.md`

```markdown
## 通用规则
- **禁止**使用 `gh issue close`、`gh pr close` — Issue 和 PR 由人工关闭
- **禁止**使用 `gh issue comment`、`gh issue edit`、`gh pr edit` — GitHub 交互由框架处理
- **禁止**假设 — 如果不清楚，明确说明
- 始终以 AGENTS.md 为最高技术指导
- 所有文档产出使用中文
```

### 4.3 `_base/rules/readonly-agent.md`

```markdown
## 只读约束
- **禁止**使用 Edit、Write、NotebookEdit（文档文件除外）
- **禁止**执行 git 操作
- Bash 权限因角色而异（参见权限矩阵），受 disallowedTools 控制
```

### 4.4 `_base/rules/write-agent.md`

```markdown
## 写操作约束
- **禁止**删除文件（不可使用 rm、trash）
- **禁止**修改 `.github/` 工作流
- git add/commit/push 由框架管理，不要执行
```

---

## 5. Task Templates

### 5.1 Task Default Mapping

When TL's Decision omits the `Task` field, use this mapping:

```javascript
const DEFAULT_TASK = {
    'spawn @planner':  'initial-analysis',
    'spawn @coder':    'implement',
    'spawn @reviewer': 'full-review',
    'spawn @tester':   'e2e-acceptance',
};
```

Daemon resolves: `task = decision.task || DEFAULT_TASK[decision.action]`.

Non-spawn actions (`verify`, `abandon`) skip task resolution entirely — no agent is spawned. Truly unknown actions (not in `DEFAULT_TASK` and not `verify`/`abandon`) are logged as errors and treated as `abandon`.

### 5.2 Task Valid Registry

All valid `(action, task)` pairs. Daemon validates before rendering:

```javascript
const VALID_TASKS = {
    'spawn @planner':  ['initial-analysis', 're-analysis'],
    'spawn @coder':    ['implement', 'rework', 'ci-fix'],
    'spawn @reviewer': ['full-review', 'rework-review'],
    'spawn @tester':   ['e2e-acceptance'],
};
```

Invalid task → warn + fall back to default.

### 5.3 Task Template Content

Each task template contains:

1. **Task heading** — `## 任务：XXX`
2. **Workflow steps** — numbered steps with `{{ wsPath }}` / `{{ branch }}` references
3. **Quality requirements** — specific to the task type
4. **Output format** — required sections for the handoff document (embedded, not separate)

Example — `tasks/coder/rework.md` vs `tasks/coder/implement.md`:

- `implement.md`: "根据 TL Context 中的计划实现功能/修复。如需查看完整计划文档，Read `{{ docDir }}/01-planner-*.md`。"
- `rework.md`: "根据 TL Context 中 reviewer 提出的问题逐项修复。只修复指出的问题，不做额外重构。如需查看审查文档，Read `{{ docDir }}/03-reviewer-*.md`。"
- `ci-fix.md`: "根据 TL Context 中的 CI 失败摘要定位问题。优先修复代码 bug，不要通过修改测试来通过。"

**Reviewer task notes:**
- `full-review.md` and `rework-review.md`: **不使用 `gh` 命令**。Reviewer 通过 Read/Grep/Glob 读取源码审查，TL Context 会指定重点审查的文件路径。

**Tester task notes:**
- `e2e-acceptance.md`: **删除 Step 7 提 Bug Issue**。截图证据留在测试报告文档中，TL 决定是否需要上传 GitHub。

---

## 6. Context Routing: TL as the Intelligence Layer

### 6.1 Problem with current design

Currently daemon mechanically concatenates `planDoc` + `prevHandoff` into coder prompt:

```javascript
// CURRENT (wrong) — foreman-daemon.mjs #spawnCoder()
const planDoc = docs.find(doc => doc.startsWith('01-planner'));
const prevHandoff = docs.filter(doc => !doc.startsWith('01-planner'))
    .map(doc => `### ${doc}\n\n${this.#docs.readDoc(issue_number, doc)}`)
    .join('\n\n---\n\n');
// → 26-63KB of full document text injected into every coder prompt
```

This is wrong because:
1. **Coder doesn't need full history** — it needs to know "what to fix" and "what constraints exist", not every detail of every previous iteration
2. **Wastes context window** — 17K-42K tokens of history that dilutes attention on the actual task
3. **Noise** — commit SHAs, test output, step-by-step logs from previous coders are irrelevant to the current coder
4. **Violates separation of concerns** — daemon is making content routing decisions that should be TL's job

### 6.2 New design: TL routes context

TL already reads all documents (orchestration + latestDoc). When TL decides to spawn a downstream agent, it writes **TL Context** that contains:

1. **What happened** — brief summary of the current situation
2. **What to do** — specific, actionable guidance
3. **What to reference** — which documents to Read for details (file paths, not full content)

Example TL Context for coder rework:

```markdown
Reviewer 发现 3 个问题需要修复：
1. CHP 过滤遗漏了 loot 实体 — `is_valid_bullet_target()` 需要额外检查 `ComponentHealthPool`
2. 测试用例没覆盖空 HP 场景 — 需要新增 `test_bullet_no_damage_on_zero_hp`
3. 函数命名不符合 AGENTS.md 约定 — `check_hit` 应改为 `is_valid_bullet_target`

计划文档: `{docDir}/01-planner-entity-purge-freed-ref.md`
审查文档: `{docDir}/03-reviewer-side-effect-found.md`

注意：不要修改 is_valid_bullet_target 的签名，只修改内部逻辑。
```

The coder receives this focused context (a few hundred bytes) and knows where to find details if needed.

> （注：TL 在实际输出中使用真实路径，如 `iterations/42/01-planner-*.md`，此处 `{{ docDir }}` 仅为示意。）

### 6.3 TL Context for planner re-analysis

```markdown
Reviewer 发现当前方案的副作用：修改 CHP 过滤会导致 SpawnerLoot 行为改变。
Planner 的原始方案: `{docDir}/01-planner-*.md`
Reviewer 的发现: `{docDir}/03-reviewer-*.md`

请重新设计方案，保持 SpawnerLoot 的现有行为。可以考虑给 is_valid_bullet_target 增加一个参数来区分 CHP 实体。
```

### 6.4 TL Context for coder ci-fix

```markdown
CI 失败摘要:
- test_bullet_damage: 预期 10 HP 扣除，实际扣了 0 — `scripts/components/bullet_damage.gd` 第 45 行的 `max()` 应为 `min()`
- test_spawn_loot: 空引用崩溃 — `SpawnerLoot._ready()` 没有检查 entity validity

只修复这两个测试指向的代码 bug。不要修改测试。
```

### 6.5 Daemon changes for context routing

`#spawnCoder()` simplifies dramatically:

```javascript
async #spawnCoder(task, decision) {
    const { issue_number, issue_title, branch: existingBranch } = task;

    // NO planDoc reading, NO prevHandoff concatenation
    // TL Context already contains everything the coder needs

    let branch = existingBranch || await this.#findPRBranch(issue_number);
    if (!branch) branch = this.#generateBranchName(issue_number, issue_title);

    const workspace = await this.#workspaces.getOrCreate(task, { branch });

    const prompt = this.#prompts.buildPrompt('coder', task, {
        wsPath: workspace,
        branch,
        tlContext: decision.tlContext || '',
        docDir: this.#docs.getIterationsDir(issue_number),
        seq: this.#docs.nextSeq(issue_number),
    });

    // ... spawn process
}
```

Same simplification applies to `#spawnPlanner()`, `#spawnReviewer()`, `#spawnTester()`.

#### Spawner Context Variables

Each `#spawnXxx()` passes these template variables to `buildPrompt()`:

| Spawner | Template Variables |
|---------|-------------------|
| `#spawnTl()` | `taskTemplate='decision'`（硬编码）, `issueContext`, `triggerEvent`, `systemAlerts`, `orchestrationContent`, `docListing`, `latestDocContent`, `latestDecision`, `availableModels` |
| `#spawnPlanner()` | `taskTemplate`, `tlContext`, `issueId`, `issueTitle`, `wsPath`, `docDir`, `issueBody` |
| `#spawnCoder()` | `taskTemplate`, `tlContext`, `wsPath`, `branch`, `docDir`, `seq` |
| `#spawnReviewer()` | `taskTemplate`, `tlContext`, `prId`, `repo`, `docDir`, `seq` |
| `#spawnTester()` | `taskTemplate`, `tlContext`, `issueId`, `wsPath`, `docDir`, `seq` |

**Reviewer note:** Reviewer 不需要 daemon 注入 diff — reviewer 通过 Read/Grep/Glob 自行读取源码，TL Context 指导重点文件。

### 6.6 TL prompt update

TL prompt must make clear that it is responsible for writing good downstream context. Add to `tasks/tl/decision.md`:

```markdown
## TL Context 质量要求
- **具体可操作** — 不要写泛泛而谈的指导，写具体的文件、函数、修改点
- **包含路径** — 告诉下游 agent 哪些文档值得 Read（用 `{{ docDir }}/XX-*.md` 格式）
- **包含约束** — 列出必须遵守的约束（如"不要修改签名"、"只修复指出的问题"）
- **简洁** — 几百字足够，不需要复述文档全文。下游 agent 有能力自己 Read
```

### 6.7 Permission Matrix

Summary of tool permissions per role. Changes from current config marked with ⚠️.

| Role | Client | disallowedTools | allowedTools | Notes |
|------|--------|----------------|--------------|-------|
| TL | codebuddy | AskUserQuestion, EnterPlanMode, Edit, NotebookEdit, ⚠️ Read, ⚠️ Grep, ⚠️ Glob, ⚠️ LS, ⚠️ Bash | — | 代码读取通过 explorer 子代理 |
| Planner | codebuddy | AskUserQuestion, EnterPlanMode | — | 只读分析，通过 Bash(gh/ls/cat) 探索代码 |
| Coder | codebuddy | — | Read, Write, Edit, Grep, Glob, LS, Bash, Agent, WebFetch, WebSearch, TodoWrite, NotebookEdit | 白名单模式不变 |
| Reviewer | codebuddy | AskUserQuestion, EnterPlanMode, Edit, ⚠️ Bash | — | 通过 Read/Grep/Glob 审查源码，不执行命令 |
| Tester | codebuddy | AskUserQuestion, EnterPlanMode | — | 需要 Bash 运行测试 |

### 6.8 TL Explorer Sub-agent

TL is prohibited from Read/Grep/Glob/LS/Bash to prevent it from going down code rabbit holes. Instead, TL has an `explorer` sub-agent for occasional file verification.

**Injection mechanism:** `--agents` CLI flag (JSON string) added by process-manager.mjs when spawning TL.

```json
[{
    "name": "explorer",
    "description": "探索代码库文件结构和内容，用于验证路径和快速了解项目上下文",
    "tools": ["Read", "Grep", "Glob", "LS"],
    "model": "gemini-3.0-flash"
}]
```

**process-manager.mjs change:** When spawning TL, append `--agents '<json>'` to the CLI args. This is a new parameter path in `buildArgs()`.

**config/default.json change:** Add `agents` field to TL role config:
```json
{
    "tl": {
        "agents": [{
            "name": "explorer",
            "description": "探索代码库文件结构和内容",
            "tools": ["Read", "Grep", "Glob", "LS"],
            "model": "gemini-3.0-flash"
        }]
    }
}
```

**Usage pattern:** TL asks explorer to verify file existence, check directory structure, or read specific file contents when making decisions. TL itself focuses on orchestration and context routing.

---

## 7. Worktree Reuse

### 7.1 Current problem

`#spawnCoder()` destroys the old worktree and creates a new one on every spawn:

```javascript
// CURRENT (wrong)
if (task.workspace) {
    this.#workspaces.destroy(task.workspace);  // ← destroys git state
}
const workspace = await this.#workspaces.create({ newBranch: branch });  // ← full re-checkout
```

This means:
1. Each coder starts from a clean checkout → **loses all previous commits** on the branch
2. The coder can't see its own previous work via `git log` (only what's pushed)
3. On rework, coder has to re-read plan docs to understand what was already done

### 7.2 New design: reuse worktree

```javascript
// NEW — reuse existing workspace, only create if needed
const workspace = await this.#workspaces.getOrCreate(task, { branch });
```

`workspace-manager.mjs` new method:

```javascript
async getOrCreate(task, options = {}) {
    // If workspace exists and is valid, reuse it
    if (task.workspace) {
        try {
            execSync('git rev-parse --show-toplevel', { cwd: task.workspace, timeout: 5000 });
            return task.workspace;
        } catch {
            // Workspace corrupted, create new
            warn(COMPONENT, `#${task.issue_number}: workspace corrupted, recreating`);
        }
    }

    // Create new workspace
    if (options.branch) {
        return this.create({ newBranch: options.branch });
    }
    return this.create();
}
```

当 `options.branch` 未提供时，`create()` 使用默认行为：基于 submodule 当前 HEAD 创建 worktree。

### 7.3 Benefits

- Coder has access to **all previous commits** on the branch via `git log`
- Coder can `git diff` against previous commit to see what was changed
- No redundant checkout time
- Worktree accumulates the full implementation history

---

## 8. PromptBuilder Unified Interface

### 8.1 New API

```javascript
class PromptBuilder {
    // Unified entry point — replaces all buildXxxPrompt() methods
    buildPrompt(role, taskTemplate, context) {
        return this.#render(`entry/${role}.md`, { taskTemplate, ...context });
    }
}
```

### 8.2 Removed API

```javascript
// DELETED — all replaced by buildPrompt(role, task, ctx)
buildTLPrompt(...)
buildPlannerPrompt(...)
buildCoderPrompt(...)
buildReviewerPrompt(...)
buildTesterPrompt(...)
buildSummaryPrompt(...)  // LLM summary pipeline deferred
```

### 8.3 Caller Changes

All 5 `#spawnXxx()` methods in `foreman-daemon.mjs` change from:

```javascript
// Before
const prompt = this.#prompts.buildPlannerPrompt({ issueId, ... });
```

To:

```javascript
// After
const taskTemplate = decision.task || DEFAULT_TASK[decision.action];
const prompt = this.#prompts.buildPrompt('planner', taskTemplate, { issueId, ... });
```

### 8.4 Nunjucks Configuration

`prompt-builder.mjs` already configured correctly:

```javascript
new nunjucks.Environment(
    new nunjucks.FileSystemLoader(promptsDir, { noCache: true }),
    {
        autoescape: false,      // Don't escape markdown content
        throwOnUndefined: true, // Catch missing variables early
        trimBlocks: true,       // Clean output after block tags
        lstripBlocks: true,     // Remove leading whitespace before block tags
    }
);
```

Note: `throwOnUndefined: true` means any missing variable will throw. All variables passed to `buildPrompt()` must be defined (even if empty string).

---

## 9. TL Decision Format Change

### 9.1 New Field: Task

TL's Decision output adds a `Task` field between `Action` and `Model`:

```markdown
# Decision N — YYYY-MM-DD HH:MM
**Trigger:** <触发事件描述>
**Assessment:** <对当前状态的评估>
**Action:** <spawn @planner | spawn @coder | spawn @reviewer | spawn @tester | verify | abandon>
**Task:** <task-template-name>        ← NEW
**Model:** <使用的模型名称>
**Guidance:** <给 agent 的简要指导>
**TL Context for <Agent>:**
> <给对应 agent 的详细任务指导段落>
```

### 9.2 Updated TL Prompt

`tasks/tl/decision.md` available actions table:

```markdown
| Action | 可选 Task | 默认 Task | 使用场景 |
|--------|----------|----------|----------|
| spawn @planner | initial-analysis, re-analysis | initial-analysis | 新issue / 方案需重设计 |
| spawn @coder | implement, rework, ci-fix | implement | 首次实现 / review修复 / CI修复 |
| spawn @reviewer | full-review, rework-review | full-review | 首次审查 / rework后审查 |
| spawn @tester | e2e-acceptance | e2e-acceptance | E2E验收 |
| verify | — | — | 任务通过 |
| abandon | — | — | 放弃 |
```

### 9.3 Decision Parsing Update

`tl-dispatcher.mjs` `parseDecisionFile()` adds `task` field:

```javascript
parseDecisionFile(content) {
    // ... existing parsing ...
    const taskMatch = content.match(/\*\*Task:\*\*\s*(.+)/);
    const contextMatch = content.match(/\*\*TL Context for \w+:\*\*\s*\n([\s\S]+?)(?=\n\*\*|\n#|$)/);
    return {
        action,
        task: taskMatch?.[1]?.trim() || null,
        model: modelMatch?.[1]?.trim() || null,
        tlContext: contextMatch?.[1]?.trim() || '',
        assessment: assessmentMatch?.[1]?.trim() || '',
        guidance: guidanceMatch?.[1]?.trim() || '',
        githubComment: commentMatch?.[1]?.trim() || '',
    };
}
```

Daemon resolves task with fallback:

```javascript
const task = decision.task || DEFAULT_TASK[decision.action];
if (task && !VALID_TASKS[decision.action]?.includes(task)) {
    warn(COMPONENT, `#${issueNumber}: invalid task "${task}" for ${decision.action}, using default`);
    task = DEFAULT_TASK[decision.action];
}
```

### 9.4 TL Prompt Examples Update

All Decision examples in `tasks/tl/decision.md` updated to include `**Task:**` field:

```markdown
### 新 issue → spawn planner
# Decision 1 — 2026-03-28 10:30
**Trigger:** New issue assigned
**Assessment:** 新 issue 需要先分析
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5.0-turbo-ioa
**Guidance:** 分析 issue 需求，追踪影响面，制定测试契约
```

```markdown
### Planner 完成 → spawn coder
# Decision 2 — 2026-03-28 10:45
**Assessment:** Plan 质量充分——影响面追踪到了 boxes/loot，测试契约完整
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**TL Context for Coder:**
> 实现子弹消耗逻辑修复：
> 1. `scripts/components/bullet_damage.gd` — 添加 CHP 检查，跳过无HP实体
> 2. 新增测试: `tests/unit/test_bullet_no_damage_on_zero_hp.tscn`
> 3. 测试契约在 `{docDir}/01-planner-*.md` 的"测试契约"段落
>
> 计划文档: `{docDir}/01-planner-*.md`
```

```markdown
### Reviewer 发现问题 → 回退 planner
# Decision 3 — 2026-03-28 11:20
**Assessment:** Reviewer 发现方案有架构副作用，需要重新设计
**Action:** spawn @planner
**Task:** re-analysis
**Model:** glm-5.0-turbo-ioa
**TL Context for Planner:**
> Reviewer 发现当前方案的副作用：修改 CHP 过滤会导致 SpawnerLoot 行为改变。
> 请重新设计方案，保持 SpawnerLoot 的现有行为。
>
> 审查文档: `{{ docDir }}/03-reviewer-*.md`
```

---

## 10. File Change Summary

### Files to Create (22 new)

#### Base layer (8)
| Path | Purpose |
|------|---------|
| `prompts/_base/identity/tl.md` | TL role identity |
| `prompts/_base/identity/planner.md` | Planner role identity |
| `prompts/_base/identity/coder.md` | Coder role identity |
| `prompts/_base/identity/reviewer.md` | Reviewer role identity |
| `prompts/_base/identity/tester.md` | Tester role identity |
| `prompts/_base/rules/shared.md` | Universal prohibitions |
| `prompts/_base/rules/readonly-agent.md` | Read-only agent constraints |
| `prompts/_base/rules/write-agent.md` | Write agent constraints |

#### Task templates (9)
| Path | Purpose |
|------|---------|
| `prompts/tasks/tl/decision.md` | TL decision task |
| `prompts/tasks/planner/initial-analysis.md` | First-time analysis |
| `prompts/tasks/planner/re-analysis.md` | Post-review redesign |
| `prompts/tasks/coder/implement.md` | First implementation |
| `prompts/tasks/coder/rework.md` | Review-driven fix |
| `prompts/tasks/coder/ci-fix.md` | CI failure fix |
| `prompts/tasks/reviewer/full-review.md` | Full code review |
| `prompts/tasks/reviewer/rework-review.md` | Incremental rework review |
| `prompts/tasks/tester/e2e-acceptance.md` | E2E acceptance test |

#### Entry templates (5)
| Path | Purpose |
|------|---------|
| `prompts/entry/tl.md` | TL assembly entry |
| `prompts/entry/planner.md` | Planner assembly entry |
| `prompts/entry/coder.md` | Coder assembly entry |
| `prompts/entry/reviewer.md` | Reviewer assembly entry |
| `prompts/entry/tester.md` | Tester assembly entry |

### Files to Delete (5 old)

| Path | Replacement |
|------|-------------|
| `prompts/tl-decision.md` | `entry/tl.md` + layered files |
| `prompts/planner-task.md` | `entry/planner.md` + layered files |
| `prompts/coder-task.md` | `entry/coder.md` + layered files |
| `prompts/reviewer-task.md` | `entry/reviewer.md` + layered files |
| `prompts/tester-task.md` | `entry/tester.md` + layered files |

### Files to Modify (6)

| Path | Changes |
|------|---------|
| `lib/prompt-builder.mjs` | Replace 5 build methods with `buildPrompt(role, task, ctx)`; remove `buildSummaryPrompt()` |
| `lib/tl-dispatcher.mjs` | Add `task` to `parseDecisionFile()`, `parseLegacyDecision()` |
| `lib/workspace-manager.mjs` | Add `getOrCreate()` method for worktree reuse |
| `foreman-daemon.mjs` | Remove planDoc/prevHandoff concatenation from `#spawnCoder()`; use `getOrCreate()` instead of destroy+create; simplify all `#spawnXxx()` to use unified `buildPrompt()` |
| `lib/process-manager.mjs` | Add `--agents` parameter support for TL sub-agents; read agents config from role config |
| `config/default.json` | Add `agents` field to TL config; Update TL `disallowedTools` to include Read/Grep/Glob/LS/Bash; Update Reviewer `disallowedTools` to include Bash |

---

## 11. What Changed from Previous Version

1. **Removed LLM summary pipeline** — replaced with TL-driven context routing. TL already reads all docs and writes targeted guidance; no need for a separate summarization layer. Can be added later if data shows it's needed.
2. **Removed `_internal/summarize.md`** — no longer needed.
3. **Removed `lib/summarizer.mjs`** — no longer needed.
4. **Removed `config/default.json` summary section** — no longer needed.
5. **Removed `doc-manager.mjs` `readDocSummary()`** — no longer needed.
6. **Added context routing design (§6)** — TL as the intelligence layer that reads all docs and writes targeted downstream context.
7. **Added worktree reuse design (§7)** — `getOrCreate()` replaces destroy+create.
8. **Simplified coder entry template** — no `planSummary`/`prevHandoffSummary`/`planDocPath` variables. Just `docDir` path + TL Context.

---

## 12. Implementation Order

1. **Create base files** — identity + rules (pure content extraction from existing templates)
2. **Create task templates** — extract workflow-specific content, add rework/ci-fix variants
3. **Create entry templates** — assemble layers via include
4. **Update prompt-builder.mjs** — unified `buildPrompt()` interface
5. **Update tl-dispatcher.mjs** — parse `Task` field from decisions
6. **Update workspace-manager.mjs** — add `getOrCreate()` for worktree reuse
7. **Update foreman-daemon.mjs** — remove handoff concatenation, use `getOrCreate()`, use unified `buildPrompt()`
8. **Delete old templates** — remove 5 monolithic files
9. **Test** — render all entry templates with sample data, verify output matches expected structure
10. **Commit** — one atomic commit for the full refactor

---

## 13. What Changed from v2 to v3

1. **Planner Runtime Facts**: Removed `seq` (always 01) and `repo` (issue body injected by daemon, planner doesn't call `gh`)
2. **Coder Runtime Facts**: Removed `issueId` and `issueTitle` (all context flows through TL Context)
3. **Reviewer Runtime Facts**: Removed `issueId`, `issueTitle`, `wsPath`; **no `prDiff` injection** — reviewer reads source code via Read/Grep/Glob, TL Context guides which files to focus on
4. **Tester Runtime Facts**: Removed `issueTitle`, `prId`, `repo`
5. **Tester task template**: Removed Step 7 (提 Bug Issue) — screenshot evidence stays in test report, TL decides GitHub upload
6. **Reviewer task templates**: Removed `gh` command steps — reviewer uses Read/Grep/Glob only
7. **TL Permission**: Added Read, Grep, Glob, LS, Bash to disallowedTools — code access via explorer sub-agent only
8. **Reviewer Permission**: Added Bash to disallowedTools
9. **TL Explorer sub-agent**: New `--agents` JSON injection via CLI, model: gemini-3.0-flash, tools: Read/Grep/Glob/LS
10. **Permission Matrix**: New section documenting all role permissions
11. **process-manager.mjs**: New `--agents` parameter support
12. **config/default.json**: TL gets `agents` config + expanded disallowedTools; Reviewer gets Bash in disallowedTools
