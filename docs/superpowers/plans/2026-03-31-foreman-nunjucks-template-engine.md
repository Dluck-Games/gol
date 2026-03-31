# Foreman Nunjucks Template Engine Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace foreman's `.replace()` template engine with Nunjucks, add conditional rendering to prompt templates.

**Architecture:** `PromptBuilder` internal implementation switches from `.replace()` chains to `nunjucks.Environment.render()`. All 5 `build*` method signatures stay identical — zero consumer changes. Templates migrate from `{{UPPER_SNAKE}}` to `{{ camelCase }}` with `{% if %}` blocks for optional sections.

**Tech Stack:** Nunjucks 3.2.4 (CJS, ESM interop verified on Node 25), Node.js `node:test` for testing.

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `foreman/package.json` | Modify | Add `nunjucks` dependency |
| `foreman/lib/prompt-builder.mjs` | Rewrite | Nunjucks Environment + `#render()` replacing `.replace()` chains |
| `foreman/prompts/reviewer-task.md` | Modify | Variable syntax migration (6 vars) |
| `foreman/prompts/tester-task.md` | Modify | Variable syntax migration (6 vars) |
| `foreman/prompts/planner-task.md` | Modify | Variable syntax + `{% if issueBody %}` conditional |
| `foreman/prompts/coder-task.md` | Modify | Variable syntax + `{% if planDoc %}` / `{% if prevHandoff %}` conditionals |
| `foreman/prompts/tl-decision.md` | Modify | Variable syntax + `{% if systemAlerts %}` conditional |
| `foreman/tests/prompt-builder.test.mjs` | Create | Unit tests for all 5 build methods + edge cases |

---

### Task 1: Install Nunjucks Dependency

**Files:**
- Modify: `foreman/package.json`

- [ ] **Step 1: Install nunjucks**

```bash
cd gol-tools/foreman && npm install nunjucks@^3.2.4
```

Expected: `package.json` gains `"dependencies": { "nunjucks": "^3.2.4" }`, `node_modules/nunjucks/` created, `package-lock.json` created.

- [ ] **Step 2: Verify ESM import works**

```bash
cd gol-tools/foreman && node -e "import nunjucks from 'nunjucks'; const env = new nunjucks.Environment(null, { autoescape: false }); console.log(env.renderString('Hello {{ name }}', { name: 'World' }))"
```

Expected output: `Hello World`

- [ ] **Step 3: Commit**

```bash
cd gol-tools/foreman && git add package.json package-lock.json && git commit -m "chore(foreman): add nunjucks dependency for template engine migration"
```

---

### Task 2: Rewrite PromptBuilder

**Files:**
- Rewrite: `foreman/lib/prompt-builder.mjs`

- [ ] **Step 1: Replace prompt-builder.mjs with Nunjucks implementation**

Write the complete new file:

```javascript
// lib/prompt-builder.mjs — Nunjucks-based template renderer

import nunjucks from 'nunjucks';

export class PromptBuilder {
    #env;

    constructor(promptsDir) {
        this.#env = new nunjucks.Environment(
            new nunjucks.FileSystemLoader(promptsDir, { noCache: false }),
            {
                autoescape: false,
                throwOnUndefined: true,
                trimBlocks: true,
                lstripBlocks: true,
            }
        );
    }

    buildTLPrompt({ issueContext, triggerEvent, orchestrationContent, docListing, latestDocContent, availableModels, latestDecision, decisionPath, systemAlerts }) {
        return this.#render('tl-decision.md', {
            issueContext,
            triggerEvent,
            orchestrationContent,
            docListing,
            latestDocContent,
            availableModels,
            latestDecision: latestDecision || 'No previous decisions',
            decisionPath: decisionPath || '',
            systemAlerts: systemAlerts || 'None',
        });
    }

    buildPlannerPrompt({ issueId, issueTitle, issueBody, repo, wsPath, tlContext, docDir, seq }) {
        return this.#render('planner-task.md', {
            issueId: String(issueId),
            issueTitle,
            issueBody: issueBody || '',
            repo,
            wsPath,
            tlContext: tlContext || '',
            docDir: docDir || '',
            seq: seq || '01',
        });
    }

    buildCoderPrompt({ issueId, issueTitle, wsPath, branch, tlContext, planDoc, prevHandoff, docDir, seq }) {
        return this.#render('coder-task.md', {
            issueId: String(issueId),
            issueTitle,
            wsPath,
            branch: branch || `foreman/issue-${issueId}`,
            tlContext: tlContext || '',
            planDoc: planDoc || '',
            prevHandoff: prevHandoff || '',
            docDir: docDir || '',
            seq: seq || '01',
        });
    }

    buildReviewerPrompt({ issueId, prId, repo, wsPath, tlContext, docDir, seq }) {
        return this.#render('reviewer-task.md', {
            issueId: String(issueId),
            prId: String(prId),
            repo,
            wsPath,
            tlContext: tlContext || '',
            docDir: docDir || '',
            seq: seq || '01',
        });
    }

    buildTesterPrompt({ issueId, prId, repo, wsPath, tlContext, docDir, seq }) {
        return this.#render('tester-task.md', {
            issueId: String(issueId),
            prId: String(prId),
            repo,
            wsPath,
            tlContext: tlContext || '',
            docDir: docDir || '',
            seq: seq || '01',
        });
    }

    #render(templateFile, context) {
        return this.#env.render(templateFile, context);
    }
}
```

- [ ] **Step 2: Commit**

```bash
cd gol-tools/foreman && git add lib/prompt-builder.mjs && git commit -m "refactor(foreman): rewrite PromptBuilder to use Nunjucks engine"
```

---

### Task 3: Migrate reviewer-task.md

**Files:**
- Modify: `foreman/prompts/reviewer-task.md`

- [ ] **Step 1: Replace all `{{UPPER_SNAKE}}` with `{{ camelCase }}`**

Apply these substitutions to `reviewer-task.md`:

| Find | Replace |
|------|---------|
| `{{ISSUE_ID}}` | `{{ issueId }}` |
| `{{PR_ID}}` | `{{ prId }}` |
| `{{REPO}}` | `{{ repo }}` |
| `{{WS_PATH}}` | `{{ wsPath }}` |
| `{{TL_CONTEXT}}` | `{{ tlContext }}` |
| `{{DOC_DIR}}` | `{{ docDir }}` |
| `{{SEQ}}` | `{{ seq }}` |

No conditional blocks needed — all 6 variables are always present.

The resulting file should start with:

```markdown
# TASK: 对抗性代码审查
**Issue**: #{{ issueId }}
**PR**: #{{ prId }}
**Repository**: {{ repo }}
**Workspace**: {{ wsPath }}
```

And all other occurrences throughout the file (e.g. in `gh issue view {{ issueId }} -R {{ repo }}`, `{{ docDir }}/{{ seq }}-reviewer-<主题描述>.md`) should also use the new syntax.

- [ ] **Step 2: Verify rendering**

```bash
cd gol-tools/foreman && node -e "
import { PromptBuilder } from './lib/prompt-builder.mjs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const __dirname = dirname(fileURLToPath(import.meta.url));
const pb = new PromptBuilder(join(__dirname, 'prompts'));
const result = pb.buildReviewerPrompt({ issueId: 42, prId: 7, repo: 'Dluck-Games/god-of-lego', wsPath: '/tmp/ws', tlContext: 'Review the PR', docDir: '/tmp/docs', seq: '03' });
console.log(result.includes('#42'));
console.log(result.includes('#7'));
console.log(result.includes('Dluck-Games/god-of-lego'));
console.log(result.includes('Review the PR'));
"
```

Expected: four `true` lines.

- [ ] **Step 3: Commit**

```bash
cd gol-tools/foreman && git add prompts/reviewer-task.md && git commit -m "refactor(foreman): migrate reviewer-task.md to Nunjucks syntax"
```

---

### Task 4: Migrate tester-task.md

**Files:**
- Modify: `foreman/prompts/tester-task.md`

- [ ] **Step 1: Replace all `{{UPPER_SNAKE}}` with `{{ camelCase }}`**

Apply these substitutions to `tester-task.md`:

| Find | Replace |
|------|---------|
| `{{ISSUE_ID}}` | `{{ issueId }}` |
| `{{PR_ID}}` | `{{ prId }}` |
| `{{REPO}}` | `{{ repo }}` |
| `{{WS_PATH}}` | `{{ wsPath }}` |
| `{{TL_CONTEXT}}` | `{{ tlContext }}` |
| `{{DOC_DIR}}` | `{{ docDir }}` |
| `{{SEQ}}` | `{{ seq }}` |

No conditional blocks needed. The resulting file should start with:

```markdown
# TASK: E2E 功能验收测试
**Issue**: #{{ issueId }}
**PR**: #{{ prId }}
**Repository**: {{ repo }}
**Workspace**: {{ wsPath }}
```

All other occurrences throughout the file (e.g. `docs/foreman/{{ issueId }}/`, `cd {{ wsPath }}/gol-project`, `{{ docDir }}/{{ seq }}-tester-<主题描述>.md`) should also use the new syntax.

- [ ] **Step 2: Verify rendering**

```bash
cd gol-tools/foreman && node -e "
import { PromptBuilder } from './lib/prompt-builder.mjs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const __dirname = dirname(fileURLToPath(import.meta.url));
const pb = new PromptBuilder(join(__dirname, 'prompts'));
const result = pb.buildTesterPrompt({ issueId: 99, prId: 12, repo: 'Dluck-Games/god-of-lego', wsPath: '/tmp/ws', tlContext: 'Test it', docDir: '/tmp/docs', seq: '05' });
console.log(result.includes('#99'));
console.log(result.includes('#12'));
console.log(result.includes('/tmp/ws/gol-project'));
"
```

Expected: three `true` lines.

- [ ] **Step 3: Commit**

```bash
cd gol-tools/foreman && git add prompts/tester-task.md && git commit -m "refactor(foreman): migrate tester-task.md to Nunjucks syntax"
```

---

### Task 5: Migrate planner-task.md (with conditional)

**Files:**
- Modify: `foreman/prompts/planner-task.md`

- [ ] **Step 1: Replace all `{{UPPER_SNAKE}}` with `{{ camelCase }}`**

Apply these substitutions to `planner-task.md`:

| Find | Replace |
|------|---------|
| `{{ISSUE_ID}}` | `{{ issueId }}` |
| `{{ISSUE_TITLE}}` | `{{ issueTitle }}` |
| `{{REPO}}` | `{{ repo }}` |
| `{{WS_PATH}}` | `{{ wsPath }}` |
| `{{TL_CONTEXT}}` | `{{ tlContext }}` |
| `{{DOC_DIR}}` | `{{ docDir }}` |
| `{{SEQ}}` | `{{ seq }}` |

- [ ] **Step 2: Add `{% if issueBody %}` conditional block**

Replace the current ISSUE_BODY section (lines 13-15):

```markdown
## ISSUE 描述（请仔细阅读）

{{ISSUE_BODY}}
```

With:

```markdown
## ISSUE 描述（请仔细阅读）
{% if issueBody %}

{{ issueBody }}
{% else %}

*Issue 描述请通过 `gh issue view {{ issueId }} -R {{ repo }}` 自行获取*
{% endif %}
```

- [ ] **Step 3: Verify rendering — with issueBody**

```bash
cd gol-tools/foreman && node -e "
import { PromptBuilder } from './lib/prompt-builder.mjs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const __dirname = dirname(fileURLToPath(import.meta.url));
const pb = new PromptBuilder(join(__dirname, 'prompts'));
const result = pb.buildPlannerPrompt({ issueId: 42, issueTitle: 'Fix bug', issueBody: 'Detailed description here', repo: 'Dluck-Games/god-of-lego', wsPath: '/tmp/ws', tlContext: '', docDir: '/tmp/docs', seq: '01' });
console.log(result.includes('Detailed description here'));
console.log(!result.includes('自行获取'));
"
```

Expected: two `true` lines.

- [ ] **Step 4: Verify rendering — without issueBody**

```bash
cd gol-tools/foreman && node -e "
import { PromptBuilder } from './lib/prompt-builder.mjs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const __dirname = dirname(fileURLToPath(import.meta.url));
const pb = new PromptBuilder(join(__dirname, 'prompts'));
const result = pb.buildPlannerPrompt({ issueId: 42, issueTitle: 'Fix bug', issueBody: '', repo: 'Dluck-Games/god-of-lego', wsPath: '/tmp/ws', tlContext: '', docDir: '/tmp/docs', seq: '01' });
console.log(result.includes('自行获取'));
console.log(result.includes('gh issue view 42'));
"
```

Expected: two `true` lines.

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman && git add prompts/planner-task.md && git commit -m "refactor(foreman): migrate planner-task.md to Nunjucks syntax with issueBody conditional"
```

---

### Task 6: Migrate coder-task.md (with conditionals)

**Files:**
- Modify: `foreman/prompts/coder-task.md`

- [ ] **Step 1: Replace all `{{UPPER_SNAKE}}` with `{{ camelCase }}`**

Apply these substitutions to `coder-task.md`:

| Find | Replace |
|------|---------|
| `{{ISSUE_ID}}` | `{{ issueId }}` |
| `{{ISSUE_TITLE}}` | `{{ issueTitle }}` |
| `{{WS_PATH}}` | `{{ wsPath }}` |
| `{{BRANCH}}` | `{{ branch }}` |
| `{{TL_CONTEXT}}` | `{{ tlContext }}` |
| `{{DOC_DIR}}` | `{{ docDir }}` |
| `{{SEQ}}` | `{{ seq }}` |

- [ ] **Step 2: Add `{% if %}` conditionals for planDoc and prevHandoff**

Replace the current planDoc/prevHandoff sections (lines 12-16):

```markdown
## 计划文档
{{PLAN_DOC}}

## 前序交接文档
{{PREV_HANDOFF}}
```

With:

```markdown
{% if planDoc %}
## 计划文档
{{ planDoc }}
{% endif %}

{% if prevHandoff %}
## 前序交接文档
{{ prevHandoff }}
{% endif %}
```

- [ ] **Step 3: Verify rendering — with planDoc and prevHandoff**

```bash
cd gol-tools/foreman && node -e "
import { PromptBuilder } from './lib/prompt-builder.mjs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const __dirname = dirname(fileURLToPath(import.meta.url));
const pb = new PromptBuilder(join(__dirname, 'prompts'));
const result = pb.buildCoderPrompt({ issueId: 42, issueTitle: 'Fix bug', wsPath: '/tmp/ws', branch: 'foreman/issue-42', tlContext: '', planDoc: 'The plan content', prevHandoff: 'Previous handoff', docDir: '/tmp/docs', seq: '02' });
console.log(result.includes('## 计划文档'));
console.log(result.includes('The plan content'));
console.log(result.includes('## 前序交接文档'));
console.log(result.includes('Previous handoff'));
"
```

Expected: four `true` lines.

- [ ] **Step 4: Verify rendering — without planDoc and prevHandoff**

```bash
cd gol-tools/foreman && node -e "
import { PromptBuilder } from './lib/prompt-builder.mjs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const __dirname = dirname(fileURLToPath(import.meta.url));
const pb = new PromptBuilder(join(__dirname, 'prompts'));
const result = pb.buildCoderPrompt({ issueId: 42, issueTitle: 'Fix bug', wsPath: '/tmp/ws', branch: 'foreman/issue-42', tlContext: '', planDoc: '', prevHandoff: '', docDir: '/tmp/docs', seq: '02' });
console.log(!result.includes('## 计划文档'));
console.log(!result.includes('## 前序交接文档'));
"
```

Expected: two `true` lines.

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman && git add prompts/coder-task.md && git commit -m "refactor(foreman): migrate coder-task.md to Nunjucks syntax with planDoc/prevHandoff conditionals"
```

---

### Task 7: Migrate tl-decision.md (with conditional)

**Files:**
- Modify: `foreman/prompts/tl-decision.md`

- [ ] **Step 1: Replace all `{{UPPER_SNAKE}}` with `{{ camelCase }}`**

Apply these substitutions to `tl-decision.md`:

| Find | Replace |
|------|---------|
| `{{AVAILABLE_MODELS}}` | `{{ availableModels }}` |
| `{{ISSUE_CONTEXT}}` | `{{ issueContext }}` |
| `{{TRIGGER_EVENT}}` | `{{ triggerEvent }}` |
| `{{SYSTEM_ALERTS}}` | `{{ systemAlerts }}` |
| `{{ORCHESTRATION_CONTENT}}` | `{{ orchestrationContent }}` |
| `{{DOC_LISTING}}` | `{{ docListing }}` |
| `{{LATEST_DOC_CONTENT}}` | `{{ latestDocContent }}` |
| `{{LATEST_DECISION}}` | `{{ latestDecision }}` |
| `{{DECISION_PATH}}` | `{{ decisionPath }}` |

- [ ] **Step 2: Add `{% if %}` conditional for systemAlerts**

Replace the current System Alerts section (lines 42-43):

```markdown
## System Alerts
{{SYSTEM_ALERTS}}
```

With:

```markdown
{# tl-dispatcher.mjs 传入 systemAlerts || 'None'，所以需要同时检查非空和非 'None' #}
{% if systemAlerts and systemAlerts != 'None' %}
## System Alerts
{{ systemAlerts }}
{% endif %}
```

- [ ] **Step 3: Verify rendering — with systemAlerts**

```bash
cd gol-tools/foreman && node -e "
import { PromptBuilder } from './lib/prompt-builder.mjs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const __dirname = dirname(fileURLToPath(import.meta.url));
const pb = new PromptBuilder(join(__dirname, 'prompts'));
const result = pb.buildTLPrompt({ issueContext: 'Issue #42: Fix bug', triggerEvent: '{\"type\":\"new_issue\"}', orchestrationContent: '', docListing: '(no documents yet)', latestDocContent: '(no documents yet)', availableModels: 'glm-5.0-turbo-ioa (default)', latestDecision: '', decisionPath: '/tmp/decisions/001-decision.md', systemAlerts: 'Rate limit warning on kimi' });
console.log(result.includes('## System Alerts'));
console.log(result.includes('Rate limit warning on kimi'));
"
```

Expected: two `true` lines.

- [ ] **Step 4: Verify rendering — without systemAlerts (default 'None')**

```bash
cd gol-tools/foreman && node -e "
import { PromptBuilder } from './lib/prompt-builder.mjs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const __dirname = dirname(fileURLToPath(import.meta.url));
const pb = new PromptBuilder(join(__dirname, 'prompts'));
const result = pb.buildTLPrompt({ issueContext: 'Issue #42: Fix bug', triggerEvent: '{\"type\":\"new_issue\"}', orchestrationContent: '', docListing: '(no documents yet)', latestDocContent: '(no documents yet)', availableModels: 'glm-5.0-turbo-ioa (default)', latestDecision: '', decisionPath: '/tmp/decisions/001-decision.md', systemAlerts: '' });
console.log(!result.includes('## System Alerts'));
"
```

Expected: one `true` line.

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman && git add prompts/tl-decision.md && git commit -m "refactor(foreman): migrate tl-decision.md to Nunjucks syntax with systemAlerts conditional"
```

---

### Task 8: Write Tests

**Files:**
- Create: `foreman/tests/prompt-builder.test.mjs`

- [ ] **Step 1: Create the test file**

```javascript
import { describe, it } from 'node:test';
import assert from 'node:assert';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PromptBuilder } from '../lib/prompt-builder.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROMPTS_DIR = join(__dirname, '..', 'prompts');

function createBuilder() {
    return new PromptBuilder(PROMPTS_DIR);
}

describe('PromptBuilder', () => {
    describe('buildReviewerPrompt', () => {
        it('renders all variables correctly', () => {
            const pb = createBuilder();
            const result = pb.buildReviewerPrompt({
                issueId: 42,
                prId: 7,
                repo: 'Dluck-Games/god-of-lego',
                wsPath: '/tmp/test-ws',
                tlContext: 'Review the changes carefully',
                docDir: '/tmp/test-docs',
                seq: '03',
            });

            assert.ok(result.includes('#42'), 'should contain issueId');
            assert.ok(result.includes('#7'), 'should contain prId');
            assert.ok(result.includes('Dluck-Games/god-of-lego'), 'should contain repo');
            assert.ok(result.includes('/tmp/test-ws'), 'should contain wsPath');
            assert.ok(result.includes('Review the changes carefully'), 'should contain tlContext');
            assert.ok(result.includes('/tmp/test-docs'), 'should contain docDir');
            assert.ok(result.includes('03-reviewer-'), 'should contain seq in doc path');
        });
    });

    describe('buildTesterPrompt', () => {
        it('renders all variables correctly', () => {
            const pb = createBuilder();
            const result = pb.buildTesterPrompt({
                issueId: 99,
                prId: 12,
                repo: 'Dluck-Games/god-of-lego',
                wsPath: '/tmp/test-ws',
                tlContext: 'Run E2E tests',
                docDir: '/tmp/test-docs',
                seq: '05',
            });

            assert.ok(result.includes('#99'), 'should contain issueId');
            assert.ok(result.includes('#12'), 'should contain prId');
            assert.ok(result.includes('/tmp/test-ws/gol-project'), 'should contain wsPath in cd command');
            assert.ok(result.includes('Run E2E tests'), 'should contain tlContext');
        });
    });

    describe('buildPlannerPrompt', () => {
        it('renders with issueBody present', () => {
            const pb = createBuilder();
            const result = pb.buildPlannerPrompt({
                issueId: 42,
                issueTitle: 'Fix bullet logic',
                issueBody: 'Detailed bug description here',
                repo: 'Dluck-Games/god-of-lego',
                wsPath: '/tmp/test-ws',
                tlContext: '',
                docDir: '/tmp/test-docs',
                seq: '01',
            });

            assert.ok(result.includes('Detailed bug description here'), 'should contain issueBody');
            assert.ok(!result.includes('自行获取'), 'should NOT contain fallback text');
        });

        it('renders fallback when issueBody is empty', () => {
            const pb = createBuilder();
            const result = pb.buildPlannerPrompt({
                issueId: 42,
                issueTitle: 'Fix bullet logic',
                issueBody: '',
                repo: 'Dluck-Games/god-of-lego',
                wsPath: '/tmp/test-ws',
                tlContext: '',
                docDir: '/tmp/test-docs',
                seq: '01',
            });

            assert.ok(result.includes('自行获取'), 'should contain fallback text');
            assert.ok(result.includes('gh issue view 42'), 'should contain gh command with issueId');
        });
    });

    describe('buildCoderPrompt', () => {
        it('renders planDoc and prevHandoff when present', () => {
            const pb = createBuilder();
            const result = pb.buildCoderPrompt({
                issueId: 42,
                issueTitle: 'Fix bug',
                wsPath: '/tmp/test-ws',
                branch: 'foreman/issue-42',
                tlContext: 'Implement the fix',
                planDoc: 'The plan content here',
                prevHandoff: 'Previous handoff notes',
                docDir: '/tmp/test-docs',
                seq: '02',
            });

            assert.ok(result.includes('## 计划文档'), 'should contain planDoc heading');
            assert.ok(result.includes('The plan content here'), 'should contain planDoc content');
            assert.ok(result.includes('## 前序交接文档'), 'should contain prevHandoff heading');
            assert.ok(result.includes('Previous handoff notes'), 'should contain prevHandoff content');
        });

        it('omits planDoc and prevHandoff sections when empty', () => {
            const pb = createBuilder();
            const result = pb.buildCoderPrompt({
                issueId: 42,
                issueTitle: 'Fix bug',
                wsPath: '/tmp/test-ws',
                branch: 'foreman/issue-42',
                tlContext: '',
                planDoc: '',
                prevHandoff: '',
                docDir: '/tmp/test-docs',
                seq: '02',
            });

            assert.ok(!result.includes('## 计划文档'), 'should NOT contain planDoc heading');
            assert.ok(!result.includes('## 前序交接文档'), 'should NOT contain prevHandoff heading');
        });
    });

    describe('buildTLPrompt', () => {
        it('renders all variables correctly', () => {
            const pb = createBuilder();
            const result = pb.buildTLPrompt({
                issueContext: 'Issue #42: Fix bullet logic',
                triggerEvent: '{"type":"new_issue"}',
                orchestrationContent: 'Decision log here',
                docListing: '- 01-planner-analysis.md',
                latestDocContent: '### 01-planner-analysis.md\n\nContent here',
                availableModels: 'glm-5.0-turbo-ioa (default)',
                latestDecision: 'No previous decisions',
                decisionPath: '/tmp/decisions/001-decision.md',
                systemAlerts: 'None',
            });

            assert.ok(result.includes('Issue #42: Fix bullet logic'), 'should contain issueContext');
            assert.ok(result.includes('new_issue'), 'should contain triggerEvent');
            assert.ok(result.includes('Decision log here'), 'should contain orchestrationContent');
            assert.ok(result.includes('glm-5.0-turbo-ioa'), 'should contain availableModels');
            assert.ok(result.includes('/tmp/decisions/001-decision.md'), 'should contain decisionPath');
        });

        it('renders System Alerts section when alerts present', () => {
            const pb = createBuilder();
            const result = pb.buildTLPrompt({
                issueContext: 'Issue #42',
                triggerEvent: '{}',
                orchestrationContent: '',
                docListing: '',
                latestDocContent: '',
                availableModels: '',
                latestDecision: '',
                decisionPath: '',
                systemAlerts: 'Rate limit warning on kimi-k2.5',
            });

            assert.ok(result.includes('## System Alerts'), 'should contain System Alerts heading');
            assert.ok(result.includes('Rate limit warning on kimi-k2.5'), 'should contain alert text');
        });

        it('omits System Alerts section when systemAlerts is None', () => {
            const pb = createBuilder();
            const result = pb.buildTLPrompt({
                issueContext: 'Issue #42',
                triggerEvent: '{}',
                orchestrationContent: '',
                docListing: '',
                latestDocContent: '',
                availableModels: '',
                latestDecision: '',
                decisionPath: '',
                systemAlerts: '',
            });

            assert.ok(!result.includes('## System Alerts'), 'should NOT contain System Alerts heading');
        });
    });

    describe('error handling', () => {
        it('throws on missing template file', () => {
            const pb = new PromptBuilder('/tmp/nonexistent-prompts-dir');
            assert.throws(
                () => pb.buildReviewerPrompt({ issueId: 1, prId: 1, repo: 'r', wsPath: '/w', tlContext: '', docDir: '/d', seq: '01' }),
                /template not found|ENOENT|not found/i,
            );
        });
    });

    describe('whitespace handling', () => {
        it('does not produce consecutive blank lines from conditional blocks', () => {
            const pb = createBuilder();
            const result = pb.buildCoderPrompt({
                issueId: 42,
                issueTitle: 'Fix bug',
                wsPath: '/tmp/test-ws',
                branch: 'foreman/issue-42',
                tlContext: '',
                planDoc: '',
                prevHandoff: '',
                docDir: '/tmp/test-docs',
                seq: '02',
            });

            // Check that there are no runs of 3+ consecutive newlines
            // (which would indicate {% if %} blocks leaving blank lines)
            const tripleNewlines = result.match(/\n{4,}/g);
            assert.ok(!tripleNewlines, `should not have 4+ consecutive newlines, found: ${tripleNewlines?.length || 0} occurrences`);
        });
    });
});
```

- [ ] **Step 2: Run the tests**

```bash
cd gol-tools/foreman && node --test tests/prompt-builder.test.mjs
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
cd gol-tools/foreman && git add tests/prompt-builder.test.mjs && git commit -m "test(foreman): add PromptBuilder unit tests for Nunjucks migration"
```

---

### Task 9: Run Full Test Suite & Verify

**Files:** None (verification only)

- [ ] **Step 1: Run all foreman tests**

```bash
cd gol-tools/foreman && node --test tests/**/*.test.mjs
```

Expected: all tests pass, including existing `tl-dispatcher.test.mjs` (which mocks `buildTLPrompt` and should be unaffected).

- [ ] **Step 2: Verify no `{{UPPER_SNAKE}}` patterns remain in templates**

```bash
cd gol-tools/foreman && grep -rn '{{[A-Z_]*}}' prompts/
```

Expected: no output (zero matches).

- [ ] **Step 3: Commit all remaining changes (if any)**

If any files were missed:

```bash
cd gol-tools/foreman && git status && git add -A && git commit -m "refactor(foreman): complete Nunjucks template engine migration"
```
