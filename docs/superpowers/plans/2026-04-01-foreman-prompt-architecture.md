# Implementation Plan: Foreman Prompt Architecture Redesign (v4)

**Date:** 2026-04-01
**Spec:** `docs/superpowers/specs/2026-03-31-foreman-prompt-architecture-design.md` (v4)
**Scope:** 21 new template files, 6 modified `.mjs` files, 5 deleted flat templates
**Root:** `gol-tools/foreman/` (all paths relative unless otherwise stated)

---

## Summary of Changes

| Type | Count | Description |
|------|-------|-------------|
| Create | 21 | New layered prompt templates |
| Delete | 5 | Old flat monolithic templates |
| Modify | 6 | `.mjs` source files |

---

## Task 1 — Create base templates

**Files:**
- `prompts/_base.md` (NEW)
- `prompts/identity/_shared-rules.md` (NEW)

**Action:** Create the two foundation files. All entry templates extend `_base.md`; all identity files include `_shared-rules.md`.

### `prompts/_base.md`

```jinja2
{# ============================================================ #}
{# 提示词总骨架 — 所有 entry 模板 extends 此文件              #}
{# ============================================================ #}

{% block identity %}{% endblock %}

---

{% block task %}{% endblock %}

---

{% block tl_context %}{% endblock %}

---

{% block environment %}{% endblock %}
```

### `prompts/identity/_shared-rules.md`

```markdown
{# 通用行为准则 — 所有角色 include 此文件 #}
- 始终以 AGENTS.md 为最高技术指导
- 所有文档产出使用中文
- **禁止**假设 — 如果不清楚，明确说明
```

**Commands:**
```bash
mkdir -p gol-tools/foreman/prompts/identity
```

**Expected output:** directories created, no error.

---

## Task 2 — Create identity templates (5 files)

**Files:**
- `prompts/identity/tl.md` (NEW)
- `prompts/identity/planner.md` (NEW)
- `prompts/identity/coder.md` (NEW)
- `prompts/identity/reviewer.md` (NEW)
- `prompts/identity/tester.md` (NEW)

Each identity file includes `_shared-rules.md` then appends role-specific rules inline.

### `prompts/identity/tl.md`

```jinja2
## 角色
你是 GOL 项目的 Team Leader。你阅读工作文档，决定下一步由哪个 Agent 接手，并为其编写精准的任务上下文。
你不直接读代码（通过 explorer 子代理），不实现功能，只做调度决策。

## 行为准则
{% include "identity/_shared-rules.md" %}
- 决策完全基于文档内容，不猜测
- 每次只做一个决策
- 所有内部迭代对用户不可见，不发中间评论
```

### `prompts/identity/planner.md`

```jinja2
## 角色
你是一个规划代理。你分析 issue、探索代码库、制定实现方案。
你**不写代码**，**不修改文件**（除了产出文档）。

## 行为准则
{% include "identity/_shared-rules.md" %}
- **禁止**使用 Edit、Write、NotebookEdit（文档文件除外）
- **禁止**执行 git 操作
- **禁止**使用 `gh issue close`、`gh pr close`、`gh issue comment`、`gh issue edit`、`gh pr edit` — GitHub 交互由框架处理
- **禁止**过度规划简单任务
- 计划必须引用探索中找到的精确文件路径
```

### `prompts/identity/coder.md`

```jinja2
## 角色
你是 GOL 项目的实现工程师。你根据 Team Leader 提供的任务上下文实现代码并编写测试。

## 行为准则
{% include "identity/_shared-rules.md" %}
- **禁止**删除文件（不可使用 rm、trash）
- **禁止**修改 `.github/` 工作流
- git add/commit/push 由框架管理，不要执行
- **禁止**使用 `gh issue close`、`gh pr close`、`gh issue comment`、`gh issue edit`、`gh pr edit` — GitHub 交互由框架处理
```

### `prompts/identity/reviewer.md`

```jinja2
## 角色
你是一个**对抗性**代码审查员。你的目标是**找到会破坏系统的地方**。
你不是形式审查 — 你要真正阅读代码，追踪调用链，验证边界条件。
你通过 Read/Grep/Glob 访问代码库。

## 行为准则
{% include "identity/_shared-rules.md" %}
- **禁止**使用 Edit、Write、NotebookEdit（审查文档除外）
- **禁止**执行 git 操作
- 必须实际读取代码，不能只看 diff
- 问题报告必须具体 — 包含文件名、行号、原因
```

### `prompts/identity/tester.md`

```jinja2
## 角色
你是一个 E2E 测试代理。你通过在**运行中的游戏实例**内注入诊断脚本来验证核心功能是否实现。
你**不修改**游戏代码，只在 `/tmp/` 下编写临时诊断脚本。

## 行为准则
{% include "identity/_shared-rules.md" %}
- **禁止**使用 `gh issue close`、`gh pr close`、`gh issue comment`、`gh issue edit` — GitHub 交互由框架处理
- **禁止**修改任何游戏代码
- **禁止**对游戏文件使用 Edit/Write（仅 /tmp/ 和测试文档）
- **必须**包含截图视觉描述
- 诊断脚本失败 2 次后立即跳转截图验证
```

---

## Task 3 — Create task templates (9 files)

**Files:**
- `prompts/tasks/tl/decision.md` (NEW)
- `prompts/tasks/planner/initial-analysis.md` (NEW)
- `prompts/tasks/planner/re-analysis.md` (NEW)
- `prompts/tasks/coder/implement.md` (NEW)
- `prompts/tasks/coder/rework.md` (NEW)
- `prompts/tasks/coder/ci-fix.md` (NEW)
- `prompts/tasks/reviewer/full-review.md` (NEW)
- `prompts/tasks/reviewer/rework-review.md` (NEW)
- `prompts/tasks/tester/e2e-acceptance.md` (NEW)

All task templates are plain markdown with Nunjucks variables — no `extends`, no inheritance.
Convention-based structure: `## 任务` → `### 工作步骤` → `### 完成标准` → `### 产出格式`.

**Commands:**
```bash
mkdir -p gol-tools/foreman/prompts/tasks/tl
mkdir -p gol-tools/foreman/prompts/tasks/planner
mkdir -p gol-tools/foreman/prompts/tasks/coder
mkdir -p gol-tools/foreman/prompts/tasks/reviewer
mkdir -p gol-tools/foreman/prompts/tasks/tester
```

### `prompts/tasks/tl/decision.md`

````jinja2
## 任务：调度决策

### 工作步骤
1. Read `{{ docDir }}/` 目录了解所有工作文档
2. Read orchestration 历史了解之前的决策和进展
3. 如果有最新文档，Read 全文评估其质量
4. 评估当前触发事件和系统状态
5. 决定下一步 Action 和 Task
6. 为下游 agent 编写 TL Context

**决策规则：**
- Planner 永远先跑，你决定 plan 质量是否足够往下走
- CI 是硬性 gate，不可跳过
- 内部迭代超过 3 次必须 abandon（参考环境信息中的调度轮次）
- 当 reviewer 发现架构问题时，回退 planner 而不是让 coder 修补
- 当 CI 失败时，评估原因决定是让 coder 修测试还是回退 planner

**可用动作：**

| Action | 可选 Task | 默认 Task | 使用场景 |
|--------|----------|----------|----------|
| spawn @planner | initial-analysis, re-analysis | initial-analysis | 新issue / 方案需重设计 |
| spawn @coder | implement, rework, ci-fix | implement | 首次实现 / review修复 / CI修复 |
| spawn @reviewer | full-review, rework-review | full-review | 首次审查 / rework后审查 |
| spawn @tester | e2e-acceptance | e2e-acceptance | E2E验收 |
| verify | — | — | 任务通过 |
| abandon | — | — | 放弃 |

**必须 abandon 的场景：**
- 内部迭代超过 3 次仍未解决
- Planner 报告 issue 需求不清晰
- Reviewer 发现需求本身有矛盾

### 完成标准
- Decision 格式完整（见产出格式）
- TL Context 具体可操作（包含文件路径、修改点、约束）
- 终态决策（verify/abandon）包含 GitHub Comment

### 产出格式
将 Decision 写入 `{{ docDir }}/decisions/{{ decisionSeq }}-<phase>.md`

```markdown
# Decision N — YYYY-MM-DD HH:MM
**Trigger:** <触发事件描述>
**Assessment:** <对当前状态的评估>
**Action:** <spawn @planner | spawn @coder | spawn @reviewer | spawn @tester | verify | abandon>
**Task:** <task-template-name>
**Model:** <使用的模型名称>
**Guidance:** <给 agent 的简要指导>
**TL Context for <Agent>:**
> <给对应 agent 的详细任务指导段落，多行 markdown>
```

终态（verify/abandon）追加：
```markdown
**GitHub Comment:**
<面向用户的中文总结>
```

**TL Context 质量要求：**
- **具体可操作** — 写具体的文件、函数、修改点，不泛泛而谈
- **包含路径** — 告诉下游 agent 哪些文档值得 Read
- **包含约束** — 列出必须遵守的限制
- **简洁** — 几百字足够，下游 agent 有能力自己 Read 细节

同时更新 `{{ docDir }}/orchestration.md` 的索引表。
````

### `prompts/tasks/planner/initial-analysis.md`

```jinja2
## 任务：初始分析

### 工作步骤
1. 验证 Issue 描述（空白/不清晰 → 文档标记 BLOCKED）
2. `cd {{ wsPath }}` 进入工作目录
3. 阅读 AGENTS.md 了解项目架构
4. 使用 Glob/Grep/Read 搜索相关代码
5. 追踪执行路径和调用链
6. 撰写分析文档

### 完成标准
- 需求分析完整
- 影响面追踪到所有相关文件
- 测试契约明确且可验证
- 每个实现步骤足够具体，让另一个 agent 无需猜测就能执行

### 产出格式
写入 `{{ docDir }}/{{ seq }}-planner-<主题描述>.md`

<主题描述>：3-5 个英文单词，kebab-case。

**文档必须包含：**

## 需求分析
## 影响面分析
## 实现方案
## 架构约束
- 涉及的 AGENTS.md 文件
- 引用的架构模式
- 文件归属层级
- 测试模式
## 测试契约
## 风险点
## 建议的实现步骤
```

### `prompts/tasks/planner/re-analysis.md`

```jinja2
## 任务：方案重设计

### 工作步骤
1. `cd {{ wsPath }}` 进入工作目录
2. Read TL Context 中提到的审查文档了解问题
3. Read 原始计划文档了解之前的方案
4. 分析问题根因
5. 设计新方案，规避已发现的问题

### 完成标准
- 明确说明与前一版方案的差异
- 新方案解决了 reviewer 指出的问题
- 不引入新的架构风险

### 产出格式
写入 `{{ docDir }}/{{ seq }}-planner-<主题描述>.md`

**文档必须包含：**

## 问题回顾
## 修正后的方案
## 与前版差异
## 测试契约（更新）
## 风险点
```

### `prompts/tasks/coder/implement.md`

```jinja2
## 任务：实现功能

### 工作步骤
1. `cd {{ wsPath }}` 确认工作目录
2. 阅读 AGENTS.md 了解项目规范
3. 确认在 `{{ branch }}` 分支上
4. 根据 TL Context 实现功能/修复
5. 如需查看完整计划文档，Read `{{ docDir }}/01-planner-*.md`
6. 编写/更新测试
7. 运行测试确认通过

### 完成标准
- 所有相关测试通过
- 代码符合 AGENTS.md 架构约束
- 无未处理的编译错误

### 产出格式
完成后写交接文档到 `{{ docDir }}/{{ seq }}-coder-<主题描述>.md`

<主题描述>：3-5 个英文单词，kebab-case。
例如：`02-coder-fix-bullet-target-filter.md`

**文档必须包含：**

## 完成的工作
- 修改/新增了哪些文件及原因

## 测试契约覆盖
- 对照 planner 的测试契约，标注覆盖状态

## 决策记录
- 实现过程中的关键决策
- 与计划有偏差的地方及原因

## 仓库状态
- branch 名称、commit SHA、测试结果摘要

## 未完成事项
- 如果全部完成，写"无"
```

### `prompts/tasks/coder/rework.md`

```jinja2
## 任务：Review 修复

### 工作步骤
1. `cd {{ wsPath }}` 确认工作目录
2. 根据 TL Context 中 reviewer 提出的问题逐项修复
3. **只修复指出的问题，不做额外重构**
4. 如需查看审查文档，Read `{{ docDir }}/` 下对应的 reviewer 文档
5. 运行测试确认通过

### 完成标准
- Reviewer 指出的每个问题都已修复
- 无新增回归
- 测试通过

### 产出格式
完成后写交接文档到 `{{ docDir }}/{{ seq }}-coder-<主题描述>.md`

**文档必须包含：**

## 逐项修复记录
- 每个 reviewer 问题的修复方式

## 测试结果

## 仓库状态

## 未完成事项
```

### `prompts/tasks/coder/ci-fix.md`

```jinja2
## 任务：CI 修复

### 工作步骤
1. `cd {{ wsPath }}` 确认工作目录
2. 根据 TL Context 中的 CI 失败摘要定位问题
3. 优先修复代码 bug，**不要通过修改测试来通过**
4. 运行测试确认通过

### 完成标准
- CI 中失败的测试全部通过
- 无新增回归

### 产出格式
完成后写交接文档到 `{{ docDir }}/{{ seq }}-coder-<主题描述>.md`

**文档必须包含：**

## 修复记录
- 失败原因分析
- 修复方式

## 测试结果

## 仓库状态
```

### `prompts/tasks/reviewer/full-review.md`

```jinja2
## 任务：完整代码审查

### 工作步骤
1. Read 工作文档（`{{ docDir }}/` 下的 planner 和 coder 文档）了解实现意图
2. 使用 Read 读取修改文件的**完整内容**（不只看 diff 片段）
3. 使用 Grep 追踪修改函数的**所有调用者** — 确认修改不破坏上游
4. 检查**边界条件** — null、空值、极端输入
5. 验证**测试质量** — 测试是否真正验证了行为
6. 检查**副作用** — 修改是否影响了非目标代码路径

### 完成标准
- 每个验证项有实际执行的验证动作（不能只写"已检查"）
- 架构一致性全部通过
- 结论明确（verified / rework）

### 产出格式
写入 `{{ docDir }}/{{ seq }}-reviewer-<主题描述>.md`

**文档必须包含：**

## 审查范围

## 验证清单
- [ ] 验证项（描述 + 实际执行的动作）

### 架构一致性对照（固定检查项）
- [ ] 新增代码是否遵循 planner 指定的架构模式
- [ ] 新增文件是否放在正确目录，命名符合 AGENTS.md 约定
- [ ] 是否存在平行实现——功能和已有代码重叠但没有复用
- [ ] 测试是否使用正确的测试模式
- [ ] 测试是否验证了真实行为

> 架构违规 severity = Important

## 发现的问题
- 严重程度（Critical/Important/Minor）、置信度、文件位置、建议修复

## 测试契约检查

## 结论
- `verified` — 所有检查通过
- `rework` — 发现需要修复的问题
```

### `prompts/tasks/reviewer/rework-review.md`

```jinja2
## 任务：Rework 增量审查

### 工作步骤
1. Read 上一轮审查文档了解之前指出的问题
2. Read coder 的 rework 交接文档了解修复内容
3. 逐项验证之前指出的问题是否已修复
4. 检查修复是否引入新问题

### 完成标准
- 每个之前的问题都有明确的验证结果
- 无新增问题

### 产出格式
写入 `{{ docDir }}/{{ seq }}-reviewer-<主题描述>.md`

**文档必须包含：**

## 逐项验证
| # | 原问题 | 修复状态 | 验证方式 |
|---|--------|---------|---------|

## 新发现（如有）

## 结论
```

### `prompts/tasks/tester/e2e-acceptance.md`

```jinja2
## 任务：E2E 功能验收

### 工作步骤
1. Read `{{ docDir }}/` 下的 planner 文档提取测试契约
2. 启动游戏：
   ```bash
   cd {{ wsPath }}/gol-project
   /Applications/Godot.app/Contents/MacOS/Godot --scene <场景路径> 2>&1 | tee /tmp/godot_e2e.log &
   ```
3. 等待初始化（~12秒），验证调试桥：
   ```bash
   node gol-tools/ai-debug/ai-debug.mjs get entity_count
   ```
4. 执行前置条件
5. 逐项执行验收标准：
   - 编写诊断脚本到 `/tmp/e2e_check_*.gd`
   - 注入执行：`node gol-tools/ai-debug/ai-debug.mjs script /tmp/e2e_check_*.gd`
   - 完整记录原始输出
6. 截图取证（**必须**）：
   ```bash
   node gol-tools/ai-debug/ai-debug.mjs screenshot
   ```
   使用 Read 读取截图 → 文字描述（≥3句）→ 写入报告
7. 清理：
   ```bash
   rm -f /tmp/e2e_*.gd
   kill $(pgrep -f "Godot") 2>/dev/null
   ```

### 完成标准
- 核心功能正常 = 通过，即使存在小问题
- 每个测试项有完整证据链（脚本 → 输出 → 截图）
- 截图有文字描述

### 产出格式
写入 `{{ docDir }}/{{ seq }}-tester-<主题描述>.md`

**文档必须包含：**

## 测试环境
- 场景路径、Godot 版本、前置条件

## 测试用例与结果
| # | 检查项 | 结果 | 证据 |
|---|--------|------|------|

## 截图证据
- 截图文件路径
- 视觉描述

## 发现的非阻塞问题
- 如果没有：写"无"

## 结论
- `pass` — 核心功能正常
- `fail` — 核心功能不可用（附理由）
```

---

## Task 4 — Create entry templates (5 files)

**Files:**
- `prompts/entry/tl.md` (NEW)
- `prompts/entry/planner.md` (NEW)
- `prompts/entry/coder.md` (NEW)
- `prompts/entry/reviewer.md` (NEW)
- `prompts/entry/tester.md` (NEW)

Entry templates are the only files using `extends _base.md`. They assemble the 4 layers.

**Commands:**
```bash
mkdir -p gol-tools/foreman/prompts/entry
```

### `prompts/entry/tl.md`

```jinja2
{% extends "_base.md" %}

{% block identity %}
{% include "identity/tl.md" %}
{% endblock %}

{% block task %}
{% include "tasks/tl/" + taskTemplate + ".md" %}
{% endblock %}

{% block tl_context %}
{# TL 不接收 TL Context — TL 是 context 的源头 #}
{% endblock %}

{% block environment %}
## 环境信息
- **Issue**: #{{ issueId }} — {{ issueTitle }}
- **Workspace**: {{ wsPath }}
- **Branch**: {{ branch }}
- **文档目录**: {{ docDir }}
- **调度轮次**: {{ iteration }} / 3
- **上一轮 Agent**: {{ prevAgent }}
- **处理时长**: {{ totalDuration }}

## Issue 上下文
{{ issueContext }}

## 触发事件
{{ triggerEvent }}

{% if systemAlerts and systemAlerts != "None" %}
## 系统警报
{{ systemAlerts }}
{% endif %}

## 可用资源
{{ availableModels }}
{% endblock %}
```

### `prompts/entry/planner.md`

```jinja2
{% extends "_base.md" %}

{% block identity %}
{% include "identity/planner.md" %}
{% endblock %}

{% block task %}
{% include "tasks/planner/" + taskTemplate + ".md" %}
{% endblock %}

{% block tl_context %}
{% if tlContext %}
## 任务上下文（来自 Team Leader）
{{ tlContext }}
{% endif %}
{% endblock %}

{% block environment %}
## 环境信息
- **Issue**: #{{ issueId }} — {{ issueTitle }}
- **Workspace**: {{ wsPath }}
- **文档目录**: {{ docDir }}
{% if issueBody %}

## Issue 描述
{{ issueBody }}
{% endif %}
{% endblock %}
```

### `prompts/entry/coder.md`

```jinja2
{% extends "_base.md" %}

{% block identity %}
{% include "identity/coder.md" %}
{% endblock %}

{% block task %}
{% include "tasks/coder/" + taskTemplate + ".md" %}
{% endblock %}

{% block tl_context %}
{% if tlContext %}
## 任务上下文（来自 Team Leader）
{{ tlContext }}
{% endif %}
{% endblock %}

{% block environment %}
## 环境信息
- **Workspace**: {{ wsPath }}
- **Branch**: {{ branch }}
- **文档目录**: {{ docDir }}
- **文档序号**: {{ seq }}
- **调度轮次**: {{ iteration }}
- **上一轮 Agent**: {{ prevAgent }}
{% endblock %}
```

### `prompts/entry/reviewer.md`

```jinja2
{% extends "_base.md" %}

{% block identity %}
{% include "identity/reviewer.md" %}
{% endblock %}

{% block task %}
{% include "tasks/reviewer/" + taskTemplate + ".md" %}
{% endblock %}

{% block tl_context %}
{% if tlContext %}
## 任务上下文（来自 Team Leader）
{{ tlContext }}
{% endif %}
{% endblock %}

{% block environment %}
## 环境信息
- **PR**: #{{ prId }}
- **Repository**: {{ repo }}
- **文档目录**: {{ docDir }}
- **文档序号**: {{ seq }}
- **调度轮次**: {{ iteration }}
{% endblock %}
```

### `prompts/entry/tester.md`

```jinja2
{% extends "_base.md" %}

{% block identity %}
{% include "identity/tester.md" %}
{% endblock %}

{% block task %}
{% include "tasks/tester/" + taskTemplate + ".md" %}
{% endblock %}

{% block tl_context %}
{% if tlContext %}
## 任务上下文（来自 Team Leader）
{{ tlContext }}
{% endif %}
{% endblock %}

{% block environment %}
## 环境信息
- **Issue**: #{{ issueId }}
- **Workspace**: {{ wsPath }}
- **文档目录**: {{ docDir }}
- **文档序号**: {{ seq }}
{% endblock %}
```

---

## Task 5 — Update `lib/prompt-builder.mjs`

**File:** `lib/prompt-builder.mjs` (MODIFY)

Replace the 5 separate `buildXxxPrompt()` methods with a single unified `buildPrompt(role, taskTemplate, context)`.
Add `DEFAULT_TASK` and `VALID_TASKS` constants as named exports.

**Complete new file:**

```javascript
// lib/prompt-builder.mjs — Nunjucks-based template renderer

import nunjucks from 'nunjucks';

export const DEFAULT_TASK = {
    'spawn @planner':  'initial-analysis',
    'spawn @coder':    'implement',
    'spawn @reviewer': 'full-review',
    'spawn @tester':   'e2e-acceptance',
};

export const VALID_TASKS = {
    'spawn @planner':  ['initial-analysis', 're-analysis'],
    'spawn @coder':    ['implement', 'rework', 'ci-fix'],
    'spawn @reviewer': ['full-review', 'rework-review'],
    'spawn @tester':   ['e2e-acceptance'],
};

export class PromptBuilder {
    #env;

    constructor(promptsDir) {
        this.#env = new nunjucks.Environment(
            new nunjucks.FileSystemLoader(promptsDir, { noCache: true }),
            {
                autoescape: false,
                throwOnUndefined: true,
                trimBlocks: true,
                lstripBlocks: true,
            }
        );
    }

    /**
     * Build a prompt for any role.
     * @param {string} role - 'tl' | 'planner' | 'coder' | 'reviewer' | 'tester'
     * @param {string} taskTemplate - task template name (e.g. 'implement', 'decision')
     * @param {object} context - template variables
     * @returns {string} rendered prompt
     */
    buildPrompt(role, taskTemplate, context) {
        return this.#render(`entry/${role}.md`, { taskTemplate, ...context });
    }

    #render(templateFile, context) {
        return this.#env.render(templateFile, context);
    }
}
```

**Diff summary from current `lib/prompt-builder.mjs` (89 lines):**
- Remove: `buildTLPrompt`, `buildPlannerPrompt`, `buildCoderPrompt`, `buildReviewerPrompt`, `buildTesterPrompt`
- Add: `DEFAULT_TASK` (exported), `VALID_TASKS` (exported), `buildPrompt(role, taskTemplate, context)`

---

## Task 6 — Update `lib/tl-dispatcher.mjs`

**File:** `lib/tl-dispatcher.mjs` (MODIFY)

Three targeted changes:

### 6.1 — `parseDecisionFile()`: add `task` field, fix contextMatch regex

**Current regex (line 204):**
```javascript
const contextMatch = content.match(/\*\*TL Context for \w+:\*\*\s*\n([\s\S]*?)(?=\*\*|\n#|$)/);
```

**Problem:** The lookahead `(?=\*\*|...)` can match immediately (zero-width), capturing nothing from the `>` blockquote lines that start the TL context.

**Full replacement for `parseDecisionFile()` (per spec §11.2):**

```javascript
parseDecisionFile(content) {
    if (!content) return null;

    const actionMatch = content.match(/\*\*Action:\*\*\s*(.+)/);
    const action = actionMatch?.[1]?.trim();
    if (!action || !VALID_ACTIONS.has(action)) {
        return null;
    }

    const modelMatch = content.match(/\*\*Model:\*\*\s*(.+)/);
    const taskMatch = content.match(/\*\*Task:\*\*\s*(.+)/);
    const contextMatch = content.match(/\*\*TL Context for \w+:\*\*\s*\n([\s\S]+?)(?=\n\*\*|\n#|$)/);
    const assessmentMatch = content.match(/\*\*Assessment:\*\*\s*(.+)/);
    const guidanceMatch = content.match(/\*\*Guidance:\*\*\s*(.+)/);
    const commentMatch = content.match(/\*\*GitHub Comment:\*\*\s*\n([\s\S]*?)(?=\*\*|\n#|$)/);

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

**Key changes:** Added `taskMatch` + `task` field. Changed contextMatch regex: `[\s\S]*?` → `[\s\S]+?` (requires at least 1 char); `(?=\*\*|\n#|$)` → `(?=\n\*\*|\n#|$)` (requires newline before lookahead).

### 6.2 — `requestDecision()`: slim prompt context (remove doc injection, add env vars)

**Replace the doc-building and prompt-building block** (current lines 51–85) with:

```javascript
const isLegacy = this.#docManager.isLegacyFormat(issueNumber);

// Slim TL prompt — TL reads documents itself via path-scoped Read permissions
const decisionSeq = isLegacy
    ? String(this.#countDecisions(this.#docManager.readOrchestration(issueNumber)) + 1).padStart(2, '0')
    : String(this.#docManager.getDecisionCount(issueNumber) + 1).padStart(2, '0');

const branch = task.branch || '';
const docDir = this.#docManager.getIterationsDir(issueNumber);
const iteration = String(task.worker_spawn_counts
    ? Object.values(task.worker_spawn_counts).reduce((a, b) => a + b, 0)
    : 0);
const prevAgent = task.last_agent || 'none';
const startedAt = task.created_at ? new Date(task.created_at).getTime() : Date.now();
const totalDuration = `${Math.round((Date.now() - startedAt) / 60000)}m`;

const prompt = this.#promptBuilder.buildPrompt('tl', 'decision', {
    issueId: String(issueNumber),
    issueTitle: task.issue_title,
    issueContext: `Issue #${issueNumber}: ${task.issue_title}`,
    triggerEvent: JSON.stringify(trigger, null, 2),
    systemAlerts: systemAlerts || 'None',
    availableModels: this.#getAvailableModels(),
    wsPath: task.workspace || this.#config.workDir,
    branch,
    docDir,
    iteration,
    prevAgent,
    totalDuration,
    decisionSeq,
});
```

**Removed variables:** `orchestration`, `docs`, `latestDoc`, `docListing`, `latestDecision`, `orchestrationContent`, `latestDocContent`, `decisionPath`, `orchestrationPath`.

**Added variables:** `wsPath`, `branch`, `docDir`, `iteration`, `prevAgent`, `totalDuration`, `decisionSeq`.

### 6.3 — `#resolveTLConfig()`: allowedTools + agents

**Replace current method:**

```javascript
#resolveTLConfig() {
    const defaults = this.#config.defaults || {};
    const tlRole = this.#config.roles?.tl || {};
    const config = {
        client: tlRole.client || defaults.client,
        model: tlRole.model || defaults.model,
        maxTurns: tlRole.maxTurns ?? defaults.maxTurns,
    };
    if (tlRole.allowedTools) {
        config.allowedTools = tlRole.allowedTools;
        config.disallowedTools = [];
    } else {
        config.allowedTools = null;
        config.disallowedTools = tlRole.disallowedTools || defaults.disallowedTools || [];
    }
    if (tlRole.agents) {
        config.agents = tlRole.agents;
    }
    return config;
}
```

---

## Task 7 — Update `lib/workspace-manager.mjs`

**File:** `lib/workspace-manager.mjs` (MODIFY)

Two changes:

### 7.1 — Add `execSync` to import

**Current line 6:**
```javascript
import { execFileSync } from 'node:child_process';
```

**Replace with:**
```javascript
import { execFileSync, execSync } from 'node:child_process';
```

### 7.2 — Add `getOrCreate()` method

Insert after the `destroy()` method (before `cleanOrphans()`):

```javascript
/**
 * Get existing workspace if valid, or create a new one.
 *
 * Reuse pattern: if task.workspace is a valid git repo, return it unchanged.
 * This avoids the destroy+recreate cycle that loses git state on every coder spawn.
 *
 * @param {object} task - Task object with optional .workspace and .issue_number
 * @param {object} [options] - { branch } branch name to use for new worktree creation
 * @returns {Promise<string>} workspace path
 */
async getOrCreate(task, options = {}) {
    if (task.workspace) {
        try {
            execSync('git rev-parse --show-toplevel', { cwd: task.workspace, timeout: 5000 });
            return task.workspace;
        } catch {
            warn(COMPONENT, `#${task.issue_number}: workspace corrupted, recreating`);
        }
    }
    if (options.branch) {
        return this.create({ newBranch: options.branch });
    }
    return this.create();
}
```

---

## Task 8 — Update `lib/process-manager.mjs`

**File:** `lib/process-manager.mjs` (MODIFY)

Add `--agents` CLI flag support. One change in `#spawnProcess()`.

### Change: args construction block (current lines 125–135)

**Current:**
```javascript
const allowed = roleConfig.allowedTools || [];
const disallowed = roleConfig.disallowedTools || [];
const args = ['-p', spec.permissionFlag, ...spec.extraArgs, '--model', model, '--output-format', 'stream-json'];
if (maxTurns) args.push('--max-turns', String(maxTurns));
args.push(prompt);
// --disallowedTools/--allowedTools are variadic (<tools...>), so they must
// come AFTER the positional prompt argument to avoid consuming the prompt.
if (disallowed.length > 0) args.push('--disallowedTools', ...disallowed);
if (allowed.length > 0) args.push('--allowedTools', ...allowed);

info(COMPONENT, `Spawning [${clientName}]: ${binary} --model ${model}${maxTurns ? ` --max-turns ${maxTurns}` : ''}${disallowed.length ? ` --disallowedTools ${disallowed.join(',')}` : ''}${allowed.length ? ` --allowedTools ${allowed.join(',')}` : ''} in ${cwd}`);
```

**Replace with:**
```javascript
const allowed = roleConfig.allowedTools || [];
const disallowed = roleConfig.disallowedTools || [];
const agents = roleConfig.agents || null;
const args = ['-p', spec.permissionFlag, ...spec.extraArgs, '--model', model, '--output-format', 'stream-json'];
if (maxTurns) args.push('--max-turns', String(maxTurns));
args.push(prompt);
// --disallowedTools/--allowedTools/--agents are variadic, so they must
// come AFTER the positional prompt argument to avoid consuming the prompt.
if (disallowed.length > 0) args.push('--disallowedTools', ...disallowed);
if (allowed.length > 0) args.push('--allowedTools', ...allowed);
if (agents) args.push('--agents', JSON.stringify(agents));

info(COMPONENT, `Spawning [${clientName}]: ${binary} --model ${model}${maxTurns ? ` --max-turns ${maxTurns}` : ''}${disallowed.length ? ` --disallowedTools ${disallowed.join(',')}` : ''}${allowed.length ? ` --allowedTools ${allowed.join(',')}` : ''}${agents ? ' --agents [...]' : ''} in ${cwd}`);
```

---

## Task 9 — Update `foreman-daemon.mjs`

**File:** `foreman-daemon.mjs` (MODIFY)

Seven changes:

### 9.1 — Add `writeFileSync` to fs import and update PromptBuilder import

**Current line 4:**
```javascript
import { readFileSync, existsSync, mkdirSync, unlinkSync, statSync, openSync, readSync, closeSync, readdirSync } from 'node:fs';
```

**Replace with:**
```javascript
import { readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync, statSync, openSync, readSync, closeSync, readdirSync } from 'node:fs';
```

**Current line 17:**
```javascript
import { PromptBuilder } from './lib/prompt-builder.mjs';
```

**Replace with:**
```javascript
import { PromptBuilder, DEFAULT_TASK, VALID_TASKS } from './lib/prompt-builder.mjs';
```

### 9.2 — Add `#writeTLSettings()` helper method

Add to `ForemanDaemon` class (near other private helpers, e.g. before `#spawnPlanner`):

```javascript
/**
 * Write path-level TL permissions into the workspace.
 * Allows TL to Read doc directories but blocks code file access.
 * Written before every TL spawn; not committed (in .gitignore).
 */
#writeTLSettings(wsPath) {
    const settingsDir = join(wsPath, '.codebuddy');
    mkdirSync(settingsDir, { recursive: true });
    const settingsPath = join(settingsDir, 'settings.local.json');
    const settings = {
        permissions: {
            allow: [
                'Read(docs/**)',
                'Read(iterations/**)',
                'Read(decisions/**)',
                'Read(orchestration.md)',
            ],
        },
    };
    writeFileSync(settingsPath, JSON.stringify(settings, null, 4), 'utf-8');
    info(COMPONENT, `TL settings.local.json written: ${settingsPath}`);
}
```

### 9.3 — Call `#writeTLSettings()` from `#requestTLDecision()`

In `#requestTLDecision()`, after `this.#decisionPending.add(key)` (current line ~210), insert:

```javascript
// Write TL path-level permissions before TL spawns
const tlTask = this.#state.getTask(issueNumber);
if (tlTask?.workspace && existsSync(tlTask.workspace)) {
    this.#writeTLSettings(tlTask.workspace);
}
```

### 9.4 — `#executeTLDecision()`: add task resolution before switch

After the internal rework limit check block (after the `return;` inside `if (!limitCheck.allowed)`), insert:

```javascript
// Resolve task template: use TL-specified task or default
let taskTemplate = decision.task || DEFAULT_TASK[decision.action];
if (taskTemplate && VALID_TASKS[decision.action] && !VALID_TASKS[decision.action].includes(taskTemplate)) {
    warn(COMPONENT, `#${issueNumber}: invalid task "${taskTemplate}" for ${decision.action}, using default`);
    taskTemplate = DEFAULT_TASK[decision.action];
}
decision.taskTemplate = taskTemplate;
```

### 9.5 — `#spawnPlanner()`: use `buildPrompt()`

**Replace prompt-building in `#spawnPlanner()` (current lines ~298–307):**

Old:
```javascript
const prompt = this.#prompts.buildPlannerPrompt({
    issueId: issue_number,
    issueTitle: issue_title,
    issueBody: '',
    repo: this.#config.repo,
    wsPath: workspace,
    tlContext: decision.tlContext || '',
    docDir,
    seq,
});
```

New:
```javascript
const taskTemplate = decision.taskTemplate || DEFAULT_TASK['spawn @planner'];
info(COMPONENT, `Spawning planner for #${issue_number} (task: ${taskTemplate})`);

const prompt = this.#prompts.buildPrompt('planner', taskTemplate, {
    issueId: String(issue_number),
    issueTitle: issue_title,
    issueBody: task.issue_body || '',
    wsPath: workspace,
    tlContext: decision.tlContext || '',
    docDir,
    seq,
});
```

Remove the old `info(COMPONENT, ...)` line for planner (it's replaced inline above).

### 9.6 — `#spawnCoder()`: `getOrCreate()`, remove doc concatenation, `buildPrompt()`

**Full replacement of `#spawnCoder()` (current lines 324–373):**

```javascript
async #spawnCoder(task, decision) {
    const { issue_number, issue_title, branch: existingBranch } = task;
    const seq = this.#docs.nextSeq(issue_number);
    const docDir = this.#docs.getIterationsDir(issue_number);
    const taskTemplate = decision.taskTemplate || DEFAULT_TASK['spawn @coder'];

    let branch = existingBranch || await this.#findPRBranch(issue_number);
    if (!branch) branch = this.#generateBranchName(issue_number, issue_title);

    // Reuse existing worktree if valid — avoids destroy+recreate losing git state
    const workspace = await this.#workspaces.getOrCreate(task, { branch });

    const iteration = String(task.worker_spawn_counts?.coder || 1);
    const prevAgent = task.last_agent || 'none';

    info(COMPONENT, `Spawning coder for #${issue_number} (task: ${taskTemplate}, iteration: ${iteration})`);

    const prompt = this.#prompts.buildPrompt('coder', taskTemplate, {
        wsPath: workspace,
        branch,
        tlContext: decision.tlContext || '',
        docDir,
        seq,
        iteration,
        prevAgent,
    });

    let roleConfig = resolveRoleConfig(this.#config, 'coder');
    if (decision.model) roleConfig = { ...roleConfig, model: decision.model };

    const logPrefix = `issues/issue-${issue_number}/coder`;
    const pid = this.#spawnTracked(issue_number, workspace, prompt, logPrefix, roleConfig);

    this.#transitionForSpawn(issue_number, 'building', 'coder started', {
        pid,
        workspace,
        branch,
        client: roleConfig.client,
    });

    this.#progress.append(issue_number, `Coder started (PID: ${pid}, task: ${taskTemplate})${decision.model ? ` [model: ${decision.model}]` : ''}`);
}
```

### 9.7 — `#spawnReviewer()` and `#spawnTester()`: use `buildPrompt()`

**In `#spawnReviewer()`, replace prompt-building (current ~lines 394–403):**

Old:
```javascript
const cwd = workspace || this.#config.workDir;
const prompt = this.#prompts.buildReviewerPrompt({
    issueId: issue_number,
    prId: prNumber,
    repo: this.#config.repo,
    wsPath: cwd,
    tlContext: decision.tlContext || '',
    docDir,
    seq,
});
```

New:
```javascript
const cwd = workspace || this.#config.workDir;
const taskTemplate = decision.taskTemplate || DEFAULT_TASK['spawn @reviewer'];
const iteration = String(task.worker_spawn_counts?.reviewer || 1);

const prompt = this.#prompts.buildPrompt('reviewer', taskTemplate, {
    prId: String(prNumber),
    repo: this.#config.repo,
    wsPath: cwd,
    tlContext: decision.tlContext || '',
    docDir,
    seq,
    iteration,
});
```

**In `#spawnTester()`, replace prompt-building (current ~lines 440–448):**

Old:
```javascript
const prompt = this.#prompts.buildTesterPrompt({
    issueId: issue_number,
    prId: ensuredPrNumber,
    repo: this.#config.repo,
    wsPath: cwd,
    tlContext: decision.tlContext || '',
    docDir,
    seq,
});
```

New:
```javascript
const taskTemplate = decision.taskTemplate || DEFAULT_TASK['spawn @tester'];

const prompt = this.#prompts.buildPrompt('tester', taskTemplate, {
    issueId: String(issue_number),
    wsPath: cwd,
    tlContext: decision.tlContext || '',
    docDir,
    seq,
});
```

---

## Task 10 — Update `config/default.json`

**File:** `config/default.json` (MODIFY)

**Complete new file** (switch all roles to `allowedTools` whitelist; add TL `agents` array):

```json
{
  "repo": "Dluck-Games/god-of-lego",
  "workDir": "/Users/dluckdu/Documents/Github/gol",
  "dataDir": "/Users/dluckdu/Documents/Github/gol/.foreman",
  "mainRepo": "https://github.com/Dluck-Games/god-of-lego",
  "localRepo": "/Users/dluckdu/Documents/Github/gol/gol-project",
  "maxCoders": 4,
  "maxActiveAgents": 1,
  "notifyTarget": "1682807251",
  "labels": {
    "assign": "foreman:assign",
    "progress": "foreman:progress",
    "done": "foreman:done",
    "blocked": "foreman:blocked",
    "cancelled": "foreman:cancelled"
  },
  "intervals": {
    "githubSyncMs": 300000,
    "processCheckMs": 30000,
    "schedulerMs": 15000
  },
  "ci": {
    "enabled": true,
    "testCommand": "/Applications/Godot.app/Contents/MacOS/Godot --headless --path \"{{WS_PATH}}\" -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/ -a res://tests/integration/ -c --ignoreHeadlessMode",
    "timeoutMs": 180000
  },
  "defaults": {
    "client": "codebuddy",
    "model": "glm-5.0-turbo-ioa",
    "maxTurns": 200,
    "disallowedTools": ["AskUserQuestion", "EnterPlanMode"]
  },
  "retryBackoffMinutes": [4, 8, 16, 32, 64],
  "roles": {
    "tl": {
      "client": "codebuddy",
      "model": "glm-5.0-turbo-ioa",
      "fallbackModels": ["kimi-k2.5-ioa", "minimax-m2.7-ioa"],
      "maxTurns": 30,
      "allowedTools": [
        "Read", "Grep", "Glob", "LS",
        "Write", "TodoWrite", "Task", "TaskOutput"
      ],
      "agents": [{
        "name": "explorer",
        "description": "探索代码库文件结构和内容，用于验证路径和快速了解项目上下文",
        "tools": ["Read", "Grep", "Glob", "LS"],
        "model": "gemini-3.0-flash"
      }]
    },
    "planner": {
      "model": "glm-5.0-turbo-ioa",
      "fallbackModels": ["kimi-k2.5-ioa"],
      "maxTurns": 50,
      "allowedTools": [
        "Read", "Grep", "Glob", "LS",
        "Bash", "Write", "TodoWrite", "Task", "TaskOutput"
      ]
    },
    "coder": {
      "model": "kimi-k2.5-ioa",
      "fallbackModels": ["minimax-m2.7-ioa"],
      "allowedTools": [
        "Read", "Write", "Edit", "Grep", "Glob", "LS",
        "Bash", "Task", "TaskOutput", "WebFetch", "WebSearch",
        "TodoWrite", "NotebookEdit"
      ]
    },
    "reviewer": {
      "model": "glm-5.0-turbo-ioa",
      "fallbackModels": ["kimi-k2.5-ioa"],
      "allowedTools": [
        "Read", "Grep", "Glob", "LS",
        "Write", "TodoWrite", "Task", "TaskOutput"
      ]
    },
    "tester": {
      "model": "kimi-k2.5-ioa",
      "fallbackModels": ["minimax-m2.7-ioa"],
      "maxTurns": 80,
      "allowedTools": [
        "Read", "Write", "Edit", "Grep", "Glob", "LS",
        "Bash", "TodoWrite", "Task", "TaskOutput"
      ]
    }
  },
  "staleTimeoutMs": 600000,
  "limits": {
    "internalReworkLimit": 3
  },
  "promptsDir": null
}
```

---

## Task 11 — Update `lib/config-utils.mjs`

**File:** `lib/config-utils.mjs` (MODIFY)

`migrateConfig()` currently hard-codes `disallowedTools` for TL and reviewer (lines 77–95).
Replace with `allowedTools` whitelists per spec §8.1.

**Replace the role normalization block (lines 75–95):**

Old:
```javascript
if (shouldNormalizeRoles) {
    config.roles ||= {};
    config.roles.tl = {
        client: 'codebuddy',
        model: 'glm-5.0-turbo-ioa',
        maxTurns: 30,
        disallowedTools: ['AskUserQuestion', 'EnterPlanMode', 'Edit', 'Write', 'NotebookEdit'],
        ...config.roles.tl,
    };
    config.roles.reviewer = {
        disallowedTools: ['AskUserQuestion', 'EnterPlanMode', 'Edit', 'Write', 'NotebookEdit'],
        ...config.roles.reviewer,
    };

    if (config.roles.tester) {
        config.roles.tester = {
            ...config.roles.tester,
            disallowedTools: config.roles.tester.disallowedTools || ['AskUserQuestion', 'EnterPlanMode'],
        };
    }
}
```

New:
```javascript
if (shouldNormalizeRoles) {
    config.roles ||= {};

    // TL defaults — allowedTools whitelist (no Bash, no Edit/Write except docs)
    const tlDefaults = {
        client: 'codebuddy',
        model: 'glm-5.0-turbo-ioa',
        maxTurns: 30,
        allowedTools: [
            'Read', 'Grep', 'Glob', 'LS',
            'Write', 'TodoWrite', 'Task', 'TaskOutput',
        ],
    };
    config.roles.tl = { ...tlDefaults, ...config.roles.tl };
    // allowedTools wins: drop any legacy disallowedTools
    if (config.roles.tl.allowedTools) {
        delete config.roles.tl.disallowedTools;
    }

    // Reviewer defaults — allowedTools whitelist (no Bash, read-only + review docs)
    const reviewerDefaults = {
        allowedTools: [
            'Read', 'Grep', 'Glob', 'LS',
            'Write', 'TodoWrite', 'Task', 'TaskOutput',
        ],
    };
    config.roles.reviewer = { ...reviewerDefaults, ...config.roles.reviewer };
    if (config.roles.reviewer.allowedTools) {
        delete config.roles.reviewer.disallowedTools;
    }

    // Tester: preserve config; drop legacy disallowedTools if allowedTools is set
    if (config.roles.tester?.allowedTools) {
        delete config.roles.tester.disallowedTools;
    }
}
```

---

## Task 12 — Delete old flat templates

**Files to delete:**
- `prompts/tl-decision.md`
- `prompts/planner-task.md`
- `prompts/coder-task.md`
- `prompts/reviewer-task.md`
- `prompts/tester-task.md`

**Commands:**
```bash
cd gol-tools/foreman
rm prompts/tl-decision.md prompts/planner-task.md prompts/coder-task.md prompts/reviewer-task.md prompts/tester-task.md
```

**Expected output:** no error.

**Verify remaining structure:**
```bash
ls gol-tools/foreman/prompts/
```

**Expected output:**
```
_base.md
entry/
identity/
tasks/
```

---

## Task 13 — Smoke test: render all entry templates

**Purpose:** Verify all 9 role/task combinations render without error via Nunjucks.

**Create test script at `gol-tools/foreman/test-prompts.mjs`:**

```javascript
// test-prompts.mjs — smoke test for all entry templates
import { PromptBuilder } from './lib/prompt-builder.mjs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const promptsDir = join(__dirname, 'prompts');
const pb = new PromptBuilder(promptsDir);

const sampleCtx = {
    issueId: '42',
    issueTitle: 'Fix bullet target filter',
    issueBody: 'Bullets are hitting loot entities',
    issueContext: 'Issue #42: Fix bullet target filter',
    triggerEvent: '{"type":"new_issue"}',
    systemAlerts: 'None',
    availableModels: 'glm-5.0-turbo-ioa (tl)',
    wsPath: '/tmp/ws_test',
    branch: 'foreman/issue-42',
    docDir: '/tmp/docs/42',
    iteration: '1',
    prevAgent: 'none',
    totalDuration: '0m',
    decisionSeq: '01',
    seq: '02',
    tlContext: 'Fix the is_valid_bullet_target function in bullet_system.gd',
    prId: '17',
    repo: 'Dluck-Games/god-of-lego',
};

const tests = [
    ['tl', 'decision'],
    ['planner', 'initial-analysis'],
    ['planner', 're-analysis'],
    ['coder', 'implement'],
    ['coder', 'rework'],
    ['coder', 'ci-fix'],
    ['reviewer', 'full-review'],
    ['reviewer', 'rework-review'],
    ['tester', 'e2e-acceptance'],
];

let passed = 0;
let failed = 0;

for (const [role, task] of tests) {
    try {
        const result = pb.buildPrompt(role, task, sampleCtx);
        if (!result || result.length < 100) {
            throw new Error(`Output too short: ${result.length} chars`);
        }
        console.log(`✓ ${role}/${task} (${result.length} chars)`);
        passed++;
    } catch (e) {
        console.error(`✗ ${role}/${task}: ${e.message}`);
        failed++;
    }
}

console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
```

**Run:**
```bash
cd gol-tools/foreman
node test-prompts.mjs
```

**Expected output:**
```
✓ tl/decision (NNNN chars)
✓ planner/initial-analysis (NNNN chars)
✓ planner/re-analysis (NNNN chars)
✓ coder/implement (NNNN chars)
✓ coder/rework (NNNN chars)
✓ coder/ci-fix (NNNN chars)
✓ reviewer/full-review (NNNN chars)
✓ reviewer/rework-review (NNNN chars)
✓ tester/e2e-acceptance (NNNN chars)

9 passed, 0 failed
```

**Cleanup:**
```bash
rm gol-tools/foreman/test-prompts.mjs
```

---

## Task 14 — Verify config resolution

**Purpose:** Confirm all roles resolve `allowedTools` correctly after migration.

**Run inline node script:**
```bash
cd gol-tools/foreman
node -e "
import('./lib/config-utils.mjs').then(({ migrateConfig, resolveRoleConfig }) => {
  import('./config/default.json', { assert: { type: 'json' } }).then(({ default: cfg }) => {
    migrateConfig(cfg);
    for (const role of ['tl', 'planner', 'coder', 'reviewer', 'tester']) {
      const r = resolveRoleConfig(cfg, role);
      const ok = r.allowedTools?.length > 0 && !(r.disallowedTools?.length > 0);
      console.log((ok ? '✓' : '✗') + ' ' + role + ': allowedTools=' + JSON.stringify(r.allowedTools));
    }
  });
});
"
```

**Expected output:** All 5 roles show `✓` with non-empty `allowedTools`.

---

## Task 15 — Commit

**Stage all changes (from `gol-tools/` submodule root):**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools
git add \
  foreman/prompts/ \
  foreman/lib/prompt-builder.mjs \
  foreman/lib/tl-dispatcher.mjs \
  foreman/lib/workspace-manager.mjs \
  foreman/lib/process-manager.mjs \
  foreman/lib/config-utils.mjs \
  foreman/foreman-daemon.mjs \
  foreman/config/default.json
git status
```

**Expected staged files (32 total):**
- 21 new `prompts/` files
- 5 deleted old `prompts/*.md` files
- 6 modified `.mjs` + 1 modified `.json`

**Commit:**
```bash
git commit -m "feat(foreman): layered prompt architecture v4 (spec 2026-03-31)

- Replace 5 flat templates with 21 layered files (_base, identity, tasks, entry)
- Unified buildPrompt(role, task, ctx) API replacing 5 separate build methods
- DEFAULT_TASK / VALID_TASKS constants for task polymorphism
- TL slim context: TL reads docs via path-scoped settings.local.json
- Worktree reuse: getOrCreate() replaces destroy+create in spawnCoder
- All roles switch to allowedTools whitelist; TL explorer sub-agent via --agents
- parseDecisionFile: add Task field parsing, fix contextMatch regex"
```

**Update parent repo:**
```bash
cd /Users/dluckdu/Documents/Github/gol
git add gol-tools
git commit -m "chore: update gol-tools (foreman prompt architecture v4)"
git push
```

---

## Quick Reference: New Template Tree

```
foreman/prompts/
├── _base.md                           # Task 1
├── identity/
│   ├── _shared-rules.md               # Task 1
│   ├── tl.md                          # Task 2
│   ├── planner.md                     # Task 2
│   ├── coder.md                       # Task 2
│   ├── reviewer.md                    # Task 2
│   └── tester.md                      # Task 2
├── tasks/
│   ├── tl/
│   │   └── decision.md                # Task 3
│   ├── planner/
│   │   ├── initial-analysis.md        # Task 3
│   │   └── re-analysis.md             # Task 3
│   ├── coder/
│   │   ├── implement.md               # Task 3
│   │   ├── rework.md                  # Task 3
│   │   └── ci-fix.md                  # Task 3
│   ├── reviewer/
│   │   ├── full-review.md             # Task 3
│   │   └── rework-review.md           # Task 3
│   └── tester/
│       └── e2e-acceptance.md          # Task 3
└── entry/
    ├── tl.md                          # Task 4
    ├── planner.md                     # Task 4
    ├── coder.md                       # Task 4
    ├── reviewer.md                    # Task 4
    └── tester.md                      # Task 4
```

## Quick Reference: Modified Files

| File | Task | Key Change |
|------|------|-----------|
| `lib/prompt-builder.mjs` | 5 | 5 methods → `buildPrompt()` + export `DEFAULT_TASK`/`VALID_TASKS` |
| `lib/tl-dispatcher.mjs` | 6 | Add `task` parse; slim context; `allowedTools`+`agents` in config |
| `lib/workspace-manager.mjs` | 7 | Add `getOrCreate()`; add `execSync` import |
| `lib/process-manager.mjs` | 8 | Add `--agents` JSON flag after `--allowedTools` |
| `foreman-daemon.mjs` | 9 | `writeFileSync` import; `#writeTLSettings()`; task resolution; all spawners use `buildPrompt()` |
| `lib/config-utils.mjs` | 11 | `migrateConfig()`: `allowedTools` whitelists for TL+reviewer |
| `config/default.json` | 10 | All roles: `allowedTools`; TL: `agents` sub-agent config |
