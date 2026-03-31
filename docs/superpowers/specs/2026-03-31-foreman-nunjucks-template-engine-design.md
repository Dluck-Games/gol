# Foreman Template Engine: Nunjucks Migration

**Date:** 2026-03-31
**Scope:** `gol-tools/foreman/` — prompt template engine only
**Approach:** 方案 B — 引擎替换 + 语法升级，文件结构不动

## Background

Foreman 的 `PromptBuilder` 使用 `.replace()` 链做 `{{PLACEHOLDER}}` 替换。5 个模板、21 个变量、4 个消费者。当前无法做条件渲染、循环、过滤器，模板复用能力为零。

### Current State

- `prompt-builder.mjs` — 5 个 `build*` 方法，每个方法是一串 `.replace(/\{\{VAR\}\}/g, value)` 调用
- `prompts/*.md` — 5 个模板文件，纯 `{{UPPER_SNAKE_CASE}}` 占位符
- 消费者：`foreman-daemon.mjs`（实例化 + 4 个 spawn 方法）、`tl-dispatcher.mjs`（buildTLPrompt）
- 测试：`tl-dispatcher.test.mjs` mock 了 `buildTLPrompt`，不依赖内部实现
- 零运行时依赖（package.json 无 dependencies）

### Problems

1. **无条件渲染** — `issueBody` 为空时仍渲染空占位符；`prevHandoff`、`planDoc` 为空时留下空段落
2. **无循环/过滤器** — 所有格式化在 JS 侧完成后注入，模板无法自主处理数据
3. **可维护性差** — 每新增一个变量需要在 `build*` 方法中加一行 `.replace()`，容易遗漏
4. **无模板复用** — 5 个模板中的公共结构（规则段、文档产出格式）全部复制粘贴

## Design

### 1. PromptBuilder Architecture

替换内部实现为 Nunjucks，对外 API 不变。

**Before:**
```
PromptBuilder
  ├── #readTemplate(filename) → readFileSync → raw string
  ├── buildTLPrompt(params) → template.replace().replace()...
  ├── buildPlannerPrompt(params) → ...
  ├── buildCoderPrompt(params) → ...
  ├── buildReviewerPrompt(params) → ...
  └── buildTesterPrompt(params) → ...
```

**After:**
```
PromptBuilder
  ├── #env: nunjucks.Environment (FileSystemLoader)
  ├── constructor(promptsDir) → 初始化 nunjucks env
  ├── #render(templateFile, context) → env.render(templateFile, context)
  ├── buildTLPrompt(params) → #render('tl-decision.md', params)
  ├── buildPlannerPrompt(params) → #render('planner-task.md', params)
  ├── buildCoderPrompt(params) → #render('coder-task.md', params)
  ├── buildReviewerPrompt(params) → #render('reviewer-task.md', params)
  └── buildTesterPrompt(params) → #render('tester-task.md', params)
```

**Key decisions:**
- 5 个 `build*` 方法签名完全不变 — 消费者零改动
- 变量名直接等于 `build*` 方法的参数名 — 无映射层
- 每个 `build*` 方法内部仍做空值兜底（`|| ''`），然后将整个参数对象传给 `#render()`

### 2. Nunjucks Configuration

```javascript
import nunjucks from 'nunjucks';

const env = new nunjucks.Environment(
    new nunjucks.FileSystemLoader(promptsDir, { noCache: false }),
    {
        autoescape: false,        // Markdown prompt，不是 HTML
        throwOnUndefined: true,   // 未定义变量立即报错
        trimBlocks: true,         // {% %} 后的换行符自动去除
        lstripBlocks: true,       // {% %} 前的空白自动去除
    }
);
```

| 配置项 | 值 | 理由 |
|--------|-----|------|
| `autoescape` | `false` | 输出是 Markdown prompt，不是 HTML |
| `throwOnUndefined` | `true` | 防止遗漏变量，未定义时立即报错 |
| `trimBlocks` | `true` | `{% %}` 标签不产生多余换行 |
| `lstripBlocks` | `true` | `{% %}` 标签前的缩进空白自动去除 |
| `noCache` | `false` | 启用模板缓存，daemon 长期运行 |

**空值处理规则：**
- `build*` 方法中 `|| ''` 兜底 → 传给模板的值永远有定义
- 模板中 `{% if var %}` 对空字符串返回 false（Jinja2 truthiness）
- 未传入的变量 → `throwOnUndefined` 报错（而非静默空字符串）

### 3. Template Syntax Migration

**变量语法：** `{{UPPER_SNAKE}}` → `{{ camelCase }}`

完整映射表：

| 当前 | 迁移后 | 所属模板 |
|------|--------|---------|
| `{{ISSUE_ID}}` | `{{ issueId }}` | planner, coder, reviewer, tester |
| `{{ISSUE_TITLE}}` | `{{ issueTitle }}` | planner, coder |
| `{{ISSUE_BODY}}` | `{{ issueBody }}` | planner |
| `{{REPO}}` | `{{ repo }}` | planner, reviewer, tester |
| `{{WS_PATH}}` | `{{ wsPath }}` | planner, coder, reviewer, tester |
| `{{BRANCH}}` | `{{ branch }}` | coder |
| `{{DOC_DIR}}` | `{{ docDir }}` | planner, coder, reviewer, tester |
| `{{SEQ}}` | `{{ seq }}` | planner, coder, reviewer, tester |
| `{{TL_CONTEXT}}` | `{{ tlContext }}` | planner, coder, reviewer, tester |
| `{{PLAN_DOC}}` | `{{ planDoc }}` | coder |
| `{{PREV_HANDOFF}}` | `{{ prevHandoff }}` | coder |
| `{{PR_ID}}` | `{{ prId }}` | reviewer, tester |
| `{{ISSUE_CONTEXT}}` | `{{ issueContext }}` | tl |
| `{{TRIGGER_EVENT}}` | `{{ triggerEvent }}` | tl |
| `{{ORCHESTRATION_CONTENT}}` | `{{ orchestrationContent }}` | tl |
| `{{DOC_LISTING}}` | `{{ docListing }}` | tl |
| `{{LATEST_DOC_CONTENT}}` | `{{ latestDocContent }}` | tl |
| `{{AVAILABLE_MODELS}}` | `{{ availableModels }}` | tl |
| `{{LATEST_DECISION}}` | `{{ latestDecision }}` | tl |
| `{{DECISION_PATH}}` | `{{ decisionPath }}` | tl |
| `{{SYSTEM_ALERTS}}` | `{{ systemAlerts }}` | tl |

**条件渲染升级（首批）：**

planner-task.md:
```jinja2
## ISSUE 描述（请仔细阅读）
{% if issueBody %}
{{ issueBody }}
{% else %}
*Issue 描述请通过 `gh issue view {{ issueId }} -R {{ repo }}` 自行获取*
{% endif %}
```

coder-task.md:
```jinja2
{% if planDoc %}
## 计划文档
{{ planDoc }}
{% endif %}

{% if prevHandoff %}
## 前序交接文档
{{ prevHandoff }}
{% endif %}
```

tl-decision.md:
```jinja2
{# tl-dispatcher.mjs 传入 systemAlerts || 'None'，所以需要同时检查非空和非 'None' #}
{% if systemAlerts and systemAlerts != 'None' %}
## System Alerts
{{ systemAlerts }}
{% endif %}
```

**不做的事：**
- 不引入 `{% for %}` — 当前无数组数据需要循环
- 不引入 custom filters — 当前无需求
- 不引入 `{% extends %}` / `{% include %}` — 文件结构不动

### 4. Dependency

```json
{
  "dependencies": {
    "nunjucks": "^3.2.4"
  }
}
```

Foreman 的第一个运行时依赖。Nunjucks 是 CJS 包，在 `"type": "module"` 项目中通过 Node.js CJS interop 导入（已在 Node 25 上验证 `import nunjucks from 'nunjucks'` 正常工作）。

### 5. Testing

**现有测试影响：** 零。`tl-dispatcher.test.mjs` mock 了 `buildTLPrompt`，不依赖内部实现。

**新增 `tests/prompt-builder.test.mjs`：**

| 测试用例 | 验证内容 |
|---------|---------|
| 基本渲染 | 每个 `build*` 方法能正确渲染所有变量 |
| 空值兜底 | 可选参数传 `''` 时，`{% if %}` 条件块正确跳过 |
| undefined 报错 | 缺少必需变量时抛出错误（`throwOnUndefined` 生效） |
| 模板文件缺失 | 模板文件不存在时抛出明确错误 |
| 输出无多余空行 | `trimBlocks` + `lstripBlocks` 生效，控制标签不产生额外空白 |

**迁移验证：** 对每个模板，用相同输入参数分别跑旧引擎和新引擎，对比输出。差异应仅限于条件块跳过的段落和空白处理。

### 6. Migration Steps

从最简单到最复杂，逐个迁移：

```
Step 1: npm install nunjucks → package.json 新增依赖
Step 2: 重写 prompt-builder.mjs → nunjucks Environment + #render()
Step 3: 逐个迁移模板文件语法（按复杂度排序）
  3a. reviewer-task.md — 6 个变量，无可选段落
  3b. tester-task.md — 6 个变量，无可选段落
  3c. planner-task.md — 8 个变量，新增 {% if issueBody %} 条件块
  3d. coder-task.md — 9 个变量，新增 {% if prevHandoff %} 和 {% if planDoc %} 条件块
  3e. tl-decision.md — 11 个变量，新增 {% if systemAlerts %} 条件块
Step 4: 新增 prompt-builder.test.mjs
Step 5: 运行全量测试 → 确认无回归
```

### 7. Risks

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| `{{ }}` 与模板内容冲突 | 零 | — | 已验证：47 处 `{{` 全部是变量占位符，无字面 `{{ }}` 文本 |
| `trimBlocks` 改变输出空白 | 低 | prompt 微调 | 对比测试验证输出差异 |
| Nunjucks CJS 在未来 Node 版本 interop 变化 | 低 | 导入失败 | 已在 Node 25 验证，锁定 nunjucks 版本 |

**回滚：** `git checkout -- lib/prompt-builder.mjs prompts/` + `npm uninstall nunjucks`

## Out of Scope

- 模板文件结构重组（`{% extends %}` / `{% include %}`）— 后续按需
- `{% for %}` 循环 — 当前无数组数据需求
- Custom filters — 当前无需求
- doc-manager / notifier 等其他模块的模板化 — 不在本次范围
- `issueBody` 空字符串 bug 的根因修复（daemon 侧未传入真实值）— 本次仅在模板侧做优雅降级
