# Foreman Multi-Phase Resume Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace single-spawn agent execution with a daemon-controlled multi-phase resume pipeline that separates core work from handoff documentation, using codebuddy's `--resume` session mechanism.

**Architecture:** Each agent role (planner, coder, reviewer, tester) gets a full-prompt spawn for core work, then a resume with just the task body for handoff doc writing. The coder additionally gets daemon-controlled commit/CI/CI-fix phases between core work and handoff. The daemon owns the phase transitions internally — the TL only sees the final result.

**Tech Stack:** Node.js (ESM), Nunjucks templates, codebuddy CLI (`--resume`, `--output-format stream-json`), node:child_process, node:readline

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/process-manager.mjs` | Modify | Session ID capture via stream-json interception; new `resume()` method; `spawn()` returns `{ pid, sessionId }` |
| `lib/doc-manager.mjs` | Modify | Remove `REQUIRED_SECTIONS` + `validateRequiredSections`; add `getPlansDir()` + `validateDocExists()` |
| `lib/prompt-builder.mjs` | Modify | Add `buildTaskOnly()` method |
| `lib/state-manager.mjs` | Modify | Add `sessionId` + `ci_fix_attempts` fields to task |
| `foreman-daemon.mjs` | Modify | Add `#runAgentPipeline`, `#resumeAndWait`, `#pendingResume`; rewrite `#onProcessExit` |
| `prompts/tasks/coder/implement.md` | Modify | Remove "产出格式" section |
| `prompts/tasks/coder/rework.md` | Modify | Remove doc output section |
| `prompts/tasks/coder/ci-fix.md` | Modify | Remove doc output section (resume injects CI context) |
| `prompts/tasks/planner/initial-analysis.md` | Modify | Change output path to `plans/` |
| `prompts/tasks/shared/handoff-doc.md` | Create | Base handoff doc template |
| `prompts/tasks/shared/handoff-doc/planner.md` | Create | Planner-specific handoff additions |
| `prompts/tasks/shared/handoff-doc/coder.md` | Create | Coder-specific handoff additions |
| `prompts/tasks/shared/handoff-doc/reviewer.md` | Create | Reviewer-specific handoff additions |
| `prompts/tasks/shared/handoff-doc/tester.md` | Create | Tester-specific handoff additions |
| `prompts/tasks/tl/decision.md` | Modify | Replace `doc_validation_failed` with `doc_missing` + `resume_failed`; add CI-fix note |
| `tests/process-manager.test.mjs` | Modify | Add session ID capture + `resume()` tests |
| `tests/doc-manager.test.mjs` | Modify | Update for removed `validateRequiredSections` and new `getPlansDir` + `validateDocExists` |

---

## Task 0: Pre-Validation — Verify `--resume` + `-p` Combination

**Files:**
- Create: `docs/reports/2026-04-04-codebuddy-resume-verification.md`

This is a manual verification task delegated to a subagent. It must pass before any code changes begin.

- [ ] **Step 1: Run a codebuddy session and capture the session ID**

```bash
cd /tmp
codebuddy -p --output-format stream-json "echo hello" 2>/dev/null | head -5
```

Look for the init message containing `session_id`. Record the value.

- [ ] **Step 2: Resume the session with a new prompt**

```bash
codebuddy --resume <captured-session-id> -p --output-format stream-json "What was the previous task you performed?" 2>/dev/null | head -20
```

Verify:
- The process starts without error
- The model has context from the previous session
- A new init message with a (possibly different) session_id is emitted

- [ ] **Step 3: Document results**

Write findings to `docs/reports/2026-04-04-codebuddy-resume-verification.md` with:
- Exact CLI invocations used
- Captured output snippets
- Whether `-p` + `--resume` combination works
- Any caveats discovered

If the combination does NOT work, document the failure and flag `--continue` as the fallback approach. The remaining tasks assume it works.

- [ ] **Step 4: Commit**

```bash
git add docs/reports/2026-04-04-codebuddy-resume-verification.md
git commit -m "docs: add codebuddy resume verification report"
```

---

## Task 1: Doc-Manager Simplification

**Files:**
- Modify: `lib/doc-manager.mjs`
- Modify: `tests/doc-manager.test.mjs`

- [ ] **Step 1: Write failing tests for new methods**

In `tests/doc-manager.test.mjs`, add tests for the new `getPlansDir` and `validateDocExists` methods, and a test that `validateRequiredSections` no longer exists:

```js
describe('getPlansDir', () => {
    it('returns plans subdirectory path', () => {
        assert.strictEqual(
            docManager.getPlansDir(42),
            join(tempDir, '42', 'plans')
        );
    });
});

describe('validateDocExists', () => {
    it('returns false when iterations dir is empty', () => {
        docManager.ensureIssueDir(42);
        mkdirSync(join(tempDir, '42', 'iterations'), { recursive: true });
        assert.strictEqual(docManager.validateDocExists(42, '01'), false);
    });

    it('returns true when a doc with matching seq exists', () => {
        docManager.ensureIssueDir(42);
        const iterDir = join(tempDir, '42', 'iterations');
        mkdirSync(iterDir, { recursive: true });
        writeFileSync(join(iterDir, '03-coder-fix-bullet.md'), '# Work done');
        assert.strictEqual(docManager.validateDocExists(42, '03'), true);
    });

    it('returns true when a doc with higher seq exists', () => {
        docManager.ensureIssueDir(42);
        const iterDir = join(tempDir, '42', 'iterations');
        mkdirSync(iterDir, { recursive: true });
        writeFileSync(join(iterDir, '05-coder-fix-bullet.md'), '# Work done');
        assert.strictEqual(docManager.validateDocExists(42, '03'), true);
    });

    it('returns false when only older docs exist', () => {
        docManager.ensureIssueDir(42);
        const iterDir = join(tempDir, '42', 'iterations');
        mkdirSync(iterDir, { recursive: true });
        writeFileSync(join(iterDir, '01-planner-analysis.md'), '# Old doc');
        assert.strictEqual(docManager.validateDocExists(42, '03'), false);
    });
});

describe('REQUIRED_SECTIONS removal', () => {
    it('no longer exports REQUIRED_SECTIONS', async () => {
        const mod = await import('../lib/doc-manager.mjs');
        assert.strictEqual(mod.REQUIRED_SECTIONS, undefined);
    });

    it('no longer has validateRequiredSections method', () => {
        assert.strictEqual(typeof docManager.validateRequiredSections, 'undefined');
    });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node --test tests/doc-manager.test.mjs
```

Expected: new tests fail (methods don't exist yet; `REQUIRED_SECTIONS` still exported).

- [ ] **Step 3: Implement changes in doc-manager.mjs**

In `lib/doc-manager.mjs`:

1. Delete the `REQUIRED_SECTIONS` export (lines 10–15).
2. Delete the `validateRequiredSections` method (lines 98–114).
3. Add `getPlansDir`:

```js
getPlansDir(issueNumber) {
    return join(this.getDocDir(issueNumber), 'plans');
}
```

4. Add `validateDocExists`:

```js
validateDocExists(issueNumber, expectedSeq) {
    const docs = this.listDocs(issueNumber);
    const seqNum = Number.parseInt(expectedSeq, 10);
    return docs.some(filename => {
        const match = filename.match(/^(\d{2})-/);
        return match && Number.parseInt(match[1], 10) >= seqNum;
    });
}
```

- [ ] **Step 4: Remove old tests that reference deleted API**

In `tests/doc-manager.test.mjs`:

1. Remove the `validateRequiredSections` describe block (the one testing pass/fail/unknown-role behavior).
2. Remove the `keeps worker prompt headings aligned with validator expectations` test.
3. Remove the `import { REQUIRED_SECTIONS } from '../lib/doc-manager.mjs'` if present.

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node --test tests/doc-manager.test.mjs
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add lib/doc-manager.mjs tests/doc-manager.test.mjs
git commit -m "refactor(doc-manager): remove section validation, add plans dir and doc existence check"
```

---

## Task 2: State-Manager — Add sessionId and ci_fix_attempts Fields

**Files:**
- Modify: `lib/state-manager.mjs`

- [ ] **Step 1: Add fields to createTask**

In `lib/state-manager.mjs`, find the `createTask` method (around line 86). Add to the task object:

```js
sessionId: null,
ci_fix_attempts: 0,
```

Place them after `worker_spawn_counts`.

- [ ] **Step 2: Add fields to #normalizeTask**

Find `#normalizeTask` and add defaults for the new fields so existing persisted tasks get them:

```js
if (!('sessionId' in task)) task.sessionId = null;
if (!('ci_fix_attempts' in task)) task.ci_fix_attempts = 0;
```

- [ ] **Step 3: Run existing state-manager tests**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node --test tests/state-manager.test.mjs
```

Expected: all existing tests pass (new fields are additive).

- [ ] **Step 4: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add lib/state-manager.mjs
git commit -m "feat(state-manager): add sessionId and ci_fix_attempts to task schema"
```

---

## Task 3: PromptBuilder — Add buildTaskOnly Method

**Files:**
- Modify: `lib/prompt-builder.mjs`
- Modify: `tests/prompt-builder.test.mjs` (if exists, otherwise add inline verification)

- [ ] **Step 1: Add the method**

In `lib/prompt-builder.mjs`, add after the `buildPrompt` method:

```js
/**
 * Render only the task template body (no identity/env layers).
 * Used for resume injection where system prompt is already loaded.
 * @param {string} role - 'shared' | 'coder' | 'planner' | 'reviewer' | 'tester'
 * @param {string} taskTemplate - template path (e.g. 'handoff-doc/coder', 'ci-fix')
 * @param {object} context - template variables
 * @returns {string} rendered task body
 */
buildTaskOnly(role, taskTemplate, context) {
    return this.#render(`tasks/${role}/${taskTemplate}.md`, context);
}
```

- [ ] **Step 2: Run existing prompt-builder tests**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node --test tests/prompt-builder.test.mjs 2>/dev/null || echo "No dedicated test file — will be verified in Task 7"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add lib/prompt-builder.mjs
git commit -m "feat(prompt-builder): add buildTaskOnly for resume task injection"
```

---

## Task 4: Handoff Doc Templates

**Files:**
- Create: `prompts/tasks/shared/handoff-doc.md`
- Create: `prompts/tasks/shared/handoff-doc/planner.md`
- Create: `prompts/tasks/shared/handoff-doc/coder.md`
- Create: `prompts/tasks/shared/handoff-doc/reviewer.md`
- Create: `prompts/tasks/shared/handoff-doc/tester.md`

- [ ] **Step 1: Create the shared directory**

```bash
mkdir -p /Users/dluckdu/Documents/Github/gol/gol-tools/foreman/prompts/tasks/shared/handoff-doc
```

- [ ] **Step 2: Create base handoff-doc template**

Create `prompts/tasks/shared/handoff-doc.md`:

```markdown
## 任务：编写交接文档

你刚才完成了一阶段工作。现在需要编写交接文档，供团队其他成员和 Team Leader 了解你的工作成果并做出后续决策。

写入路径：`{{ docDir }}/iterations/{{ seq }}-{{ role }}-<主题描述>.md`
<主题描述>：3-5 个英文单词，kebab-case。

### 读者意识
- 你的读者是**不了解你工作细节**的同事和领导
- 他们需要快速理解：你做了什么、为什么这么做、现在什么状态、接下来该怎么办
- 用清晰简洁的语言，避免只有你自己能看懂的缩写或引用

### 基本内容（所有角色通用）
1. 工作概述——做了什么，达成了什么目标
2. 关键决策——做出的重要取舍及理由
3. 当前状态——交付物的状态（branch、commit、测试结果等）
4. 后续建议——下一步该做什么，需要注意什么（无则写"无"）

{% block role_specific %}{% endblock %}
```

- [ ] **Step 3: Create planner handoff template**

Create `prompts/tasks/shared/handoff-doc/planner.md`:

```markdown
{% extends "shared/handoff-doc.md" %}
{% block role_specific %}
### Planner 补充
- 方案选型理由和被排除的备选方案
- 风险点和缓解措施
- 给 coder 的实现注意事项
{% endblock %}
```

- [ ] **Step 4: Create coder handoff template**

Create `prompts/tasks/shared/handoff-doc/coder.md`:

```markdown
{% extends "shared/handoff-doc.md" %}
{% block role_specific %}
### Coder 补充
- 列出修改/新增的文件及变更原因
- 对照 planner 测试契约，说明覆盖状态
- 与原计划的偏差及原因
{% endblock %}
```

- [ ] **Step 5: Create reviewer handoff template**

Create `prompts/tasks/shared/handoff-doc/reviewer.md`:

```markdown
{% extends "shared/handoff-doc.md" %}
{% block role_specific %}
### Reviewer 补充
- 审查通过/不通过的判断依据
- 发现的问题清单（含文件名和行号）
- 代码质量和架构合规性评估
{% endblock %}
```

- [ ] **Step 6: Create tester handoff template**

Create `prompts/tasks/shared/handoff-doc/tester.md`:

```markdown
{% extends "shared/handoff-doc.md" %}
{% block role_specific %}
### Tester 补充
- 测试用例和执行结果
- 截图或日志证据
- 未覆盖的场景和已知局限
{% endblock %}
```

- [ ] **Step 7: Verify templates render**

Quick smoke test using Node REPL to confirm Nunjucks resolves the inheritance:

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node -e "
const { PromptBuilder } = await import('./lib/prompt-builder.mjs');
const pb = new PromptBuilder('./prompts');
const result = pb.buildTaskOnly('shared', 'handoff-doc/coder', {
    docDir: 'docs/foreman/42', seq: '03', role: 'coder'
});
console.log(result);
console.log('---');
console.log(result.includes('读者意识') ? 'PASS: base inherited' : 'FAIL: base missing');
console.log(result.includes('Coder 补充') ? 'PASS: role block rendered' : 'FAIL: role block missing');
console.log(result.includes('iterations/03-coder') ? 'PASS: vars interpolated' : 'FAIL: vars missing');
"
```

Expected: all three `PASS` lines.

- [ ] **Step 8: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add prompts/tasks/shared/
git commit -m "feat(prompts): add handoff doc base template with role-specific extensions"
```

---

## Task 5: Prompt Modifications — Strip Doc Requirements from Worker Prompts

**Files:**
- Modify: `prompts/tasks/coder/implement.md`
- Modify: `prompts/tasks/coder/rework.md`
- Modify: `prompts/tasks/coder/ci-fix.md`
- Modify: `prompts/tasks/planner/initial-analysis.md`

- [ ] **Step 1: Strip implement.md doc section**

Replace `prompts/tasks/coder/implement.md` with:

```markdown
## 任务：实现功能

### 工作步骤
1. 阅读 AGENTS.md 了解项目规范
2. 确认在 `{{ branch }}` 分支上
3. 根据 TL Context 实现功能/修复
4. 如需查看完整计划文档，Read `{{ docDir }}/plans/01-planner-*.md`
5. 编写/更新测试
6. 仅通过 `{{ repoRoot }}/gol-tools/foreman/bin/coder-run-tests.sh` 运行测试并确认通过

### 完成标准
- 所有相关测试通过
- 代码符合 AGENTS.md 架构约束
- 无未处理的编译错误
```

Note: the plan doc path changed from `{{ docDir }}/01-planner-*.md` to `{{ docDir }}/plans/01-planner-*.md`.

- [ ] **Step 2: Strip rework.md doc section**

Replace `prompts/tasks/coder/rework.md` with:

```markdown
## 任务：Review 修复

### 工作步骤
1. 根据 TL Context 中 reviewer 提出的问题逐项修复
2. **只修复指出的问题，不做额外重构**
3. 如需查看审查文档，Read `{{ docDir }}/iterations/` 下对应的 reviewer 文档
4. 仅通过 `{{ repoRoot }}/gol-tools/foreman/bin/coder-run-tests.sh` 运行测试并确认通过

### 完成标准
- Reviewer 指出的每个问题都已修复
- 无新增回归
- 测试通过
```

- [ ] **Step 3: Strip ci-fix.md doc section**

Replace `prompts/tasks/coder/ci-fix.md` with:

```markdown
## 任务：CI 修复

### 工作步骤
1. 根据 TL Context 中的 CI 失败摘要定位问题
2. 优先修复代码 bug，**不要通过修改测试来通过**
3. 仅通过 `{{ repoRoot }}/gol-tools/foreman/bin/coder-run-tests.sh` 运行测试并确认通过

### 完成标准
- CI 中失败的测试全部通过
- 无新增回归
```

- [ ] **Step 4: Modify planner initial-analysis.md output path**

Replace `prompts/tasks/planner/initial-analysis.md` with:

```markdown
## 任务：初始分析

### 工作步骤
1. 验证 Issue 描述（空白/不清晰 → 文档标记 BLOCKED）
2. 阅读 AGENTS.md 了解项目架构
3. 使用 Glob/Grep/Read 搜索相关代码
4. 如需查看工作树状态，仅使用只读 git 查询（`git status` / `git diff` / `git log` / `git show`）
5. 追踪执行路径和调用链
6. 撰写分析文档

### 完成标准
- 需求分析完整
- 影响面追踪到所有相关文件
- 测试契约明确且可验证
- 每个实现步骤足够具体，让另一个 agent 无需猜测就能执行

### 产出格式
写入 `{{ docDir }}/plans/{{ seq }}-planner-<主题描述>.md`

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

- [ ] **Step 5: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add prompts/tasks/coder/implement.md prompts/tasks/coder/rework.md prompts/tasks/coder/ci-fix.md prompts/tasks/planner/initial-analysis.md
git commit -m "refactor(prompts): strip doc output from worker tasks, update planner output to plans/"
```

---

## Task 6: Process-Manager — Session ID Capture + Resume

**Files:**
- Modify: `lib/process-manager.mjs`
- Modify: `tests/process-manager.test.mjs`

- [ ] **Step 1: Write failing tests for session ID capture**

In `tests/process-manager.test.mjs`, add a new describe block:

```js
describe('session ID capture', () => {
    it('spawn returns { pid, sessionId } where sessionId is a Promise', () => {
        const { pid, sessionId } = pm.spawn(1, tmpDir, 'test prompt', 'test-log', defaultRoleConfig);
        assert.strictEqual(typeof pid, 'number');
        assert.ok(sessionId instanceof Promise);
    });

    it('sessionId resolves when init message is emitted on stdout', async () => {
        const { sessionId } = pm.spawn(1, tmpDir, 'test prompt', 'test-log', defaultRoleConfig);
        // Emit a stream-json init message on the mock stdout
        const child = getLastSpawnedChild();
        child.stdout.push(JSON.stringify({
            type: 'system', subtype: 'init', session_id: 'abc-123'
        }) + '\n');
        const id = await sessionId;
        assert.strictEqual(id, 'abc-123');
    });

    it('sessionId rejects if process exits before init message', async () => {
        const { sessionId } = pm.spawn(1, tmpDir, 'test prompt', 'test-log', defaultRoleConfig);
        const child = getLastSpawnedChild();
        child.emit('exit', 0, null);
        await assert.rejects(sessionId, /no init message/i);
    });
});
```

- [ ] **Step 2: Write failing tests for resume method**

```js
describe('resume', () => {
    it('spawns with --resume flag and session ID', () => {
        const { pid } = pm.resume(1, 'sess-xyz', 'new task body', 'resume-log', defaultRoleConfig);
        assert.strictEqual(typeof pid, 'number');
        const args = getLastSpawnArgs();
        assert.ok(args.includes('--resume'));
        assert.ok(args.includes('sess-xyz'));
        assert.ok(args.includes('new task body'));
    });

    it('resume returns sessionId Promise like spawn', async () => {
        const { sessionId } = pm.resume(1, 'sess-xyz', 'task', 'log', defaultRoleConfig);
        assert.ok(sessionId instanceof Promise);
    });
});
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node --test tests/process-manager.test.mjs
```

Expected: new tests fail.

- [ ] **Step 4: Implement session ID capture in #spawnProcess**

In `lib/process-manager.mjs`, add `import { createInterface } from 'node:readline';` at the top.

Replace the stdout pipe section (lines 144–146) in `#spawnProcess`:

```js
// --- Session ID capture via stream-json interception ---
let sessionIdResolve, sessionIdReject;
const sessionId = new Promise((resolve, reject) => {
    sessionIdResolve = resolve;
    sessionIdReject = reject;
});
let sessionIdResolved = false;

const rl = createInterface({ input: child.stdout, crlfDelay: Infinity });
rl.on('line', (line) => {
    // Transparently write to log
    logStream.write(line + '\n');
    // Try to extract session ID from init message
    if (!sessionIdResolved) {
        try {
            const msg = JSON.parse(line);
            if (msg.type === 'system' && msg.subtype === 'init' && msg.session_id) {
                sessionIdResolved = true;
                sessionIdResolve(msg.session_id);
            }
        } catch { /* not JSON, ignore */ }
    }
});
child.stderr.pipe(logStream, { end: false });
```

In the `child.on('exit', ...)` handler, add before `logStream.end()`:

```js
if (!sessionIdResolved) {
    sessionIdResolved = true;
    sessionIdReject(new Error(`#${issueNumber}: process exited with no init message`));
}
```

Change the return value from `return child.pid;` to:

```js
return { pid: child.pid, sessionId };
```

- [ ] **Step 5: Update spawn() public method signature**

The public `spawn()` method (line 88) currently returns `this.#spawnProcess(...)`. Since `#spawnProcess` now returns `{ pid, sessionId }`, `spawn()` automatically passes through the new shape. Update the JSDoc:

```js
/**
 * Spawn an agent process for any role.
 * @param {number} issueNumber
 * @param {string} cwd
 * @param {string} prompt
 * @param {string} logPrefix
 * @param {object} roleConfig
 * @returns {{ pid: number, sessionId: Promise<string> }}
 */
```

- [ ] **Step 6: Implement resume() method**

Add after the `spawn()` method:

```js
/**
 * Resume an existing session with a new task body.
 * @param {number} issueNumber
 * @param {string} sessionId - session ID from a previous spawn
 * @param {string} taskBody - new task prompt to inject
 * @param {string} logPrefix
 * @param {object} roleConfig
 * @returns {{ pid: number, sessionId: Promise<string> }}
 */
resume(issueNumber, sessionId, taskBody, logPrefix, roleConfig) {
    return this.#resumeProcess(issueNumber, sessionId, taskBody, logPrefix, roleConfig);
}

#resumeProcess(issueNumber, sessionId, taskBody, logPrefix, roleConfig) {
    const key = String(issueNumber);

    if (this.#children.has(key)) {
        warn(COMPONENT, `#${issueNumber}: killing existing process before resume`);
        this.kill(issueNumber);
    }

    const logStream = createProcessLog(`${logPrefix}.log`);

    const clientName = roleConfig.client;
    const spec = PROVIDER_SPECS[clientName];
    if (!spec) {
        throw new Error(`Unknown client: ${clientName}. Known clients: ${Object.keys(PROVIDER_SPECS).join(', ')}`);
    }

    const env = { ...process.env };
    for (const k of spec.stripEnvKeys) delete env[k];
    Object.assign(env, spec.extraEnv);
    env.LANG = 'en_US.UTF-8';
    env.LC_ALL = 'en_US.UTF-8';

    const binary = spec.binary;
    const args = [
        '--resume', sessionId,
        '-p',
        ...spec.permissionFlags,
        ...spec.extraArgs,
        '--output-format', 'stream-json',
        taskBody,
    ];

    info(COMPONENT, `Resuming [${clientName}]: ${binary} --resume ${sessionId.slice(0, 8)}... in cwd`);

    const child = this.#spawn(binary, args, {
        cwd: process.cwd(),
        env,
        stdio: ['ignore', 'pipe', 'pipe'],
        detached: true,
    });

    // Session ID capture (same as #spawnProcess)
    let sessionIdResolve, sessionIdReject;
    const newSessionId = new Promise((resolve, reject) => {
        sessionIdResolve = resolve;
        sessionIdReject = reject;
    });
    let sessionIdResolved = false;

    const rl = createInterface({ input: child.stdout, crlfDelay: Infinity });
    rl.on('line', (line) => {
        logStream.write(line + '\n');
        if (!sessionIdResolved) {
            try {
                const msg = JSON.parse(line);
                if (msg.type === 'system' && msg.subtype === 'init' && msg.session_id) {
                    sessionIdResolved = true;
                    sessionIdResolve(msg.session_id);
                }
            } catch { /* not JSON */ }
        }
    });
    child.stderr.pipe(logStream, { end: false });

    const startLine = `\n[${new Date().toISOString()}] === Resume started (PID: ${child.pid}, session: ${sessionId.slice(0, 8)}...) ===\n`;
    logStream.write(startLine);

    child.on('exit', (code, signal) => {
        if (!sessionIdResolved) {
            sessionIdResolved = true;
            sessionIdReject(new Error(`#${issueNumber}: resumed process exited with no init message`));
        }
        const endLine = `\n[${new Date().toISOString()}] === Process exited (code: ${code}, signal: ${signal}) ===\n`;
        logStream.write(endLine);
        logStream.end();
        this.#children.delete(key);

        if (this.#killedPids.has(child.pid)) {
            this.#killedPids.delete(child.pid);
            info(COMPONENT, `#${issueNumber}: PID ${child.pid} exited (killed, suppressing callback)`);
            return;
        }

        info(COMPONENT, `#${issueNumber}: PID ${child.pid} exited (code=${code}, signal=${signal})`);
        this.#onExit(issueNumber, code, signal);
    });

    child.on('error', (err) => {
        error(COMPONENT, `#${issueNumber}: resume spawn error: ${err.message}`);
        if (!sessionIdResolved) {
            sessionIdResolved = true;
            sessionIdReject(err);
        }
        logStream.write(`\n[${new Date().toISOString()}] === Spawn error: ${err.message} ===\n`);
        logStream.end();
        this.#children.delete(key);
        this.#onExit(issueNumber, 1, null);
    });

    child.unref();

    this.#children.set(key, { process: child, logStream, pid: child.pid, client: clientName });
    info(COMPONENT, `#${issueNumber}: resumed PID ${child.pid} [${clientName}]`);
    return { pid: child.pid, sessionId: newSessionId };
}
```

- [ ] **Step 7: Fix existing tests that expect spawn() to return a number**

Search all existing tests for `pm.spawn(...)` calls that expect a bare number. Update them:

```js
// Before:
const pid = pm.spawn(...);
assert.strictEqual(typeof pid, 'number');

// After:
const { pid } = pm.spawn(...);
assert.strictEqual(typeof pid, 'number');
```

Apply this pattern to every test case in `tests/process-manager.test.mjs` that calls `pm.spawn`.

- [ ] **Step 8: Run all tests**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node --test tests/process-manager.test.mjs
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add lib/process-manager.mjs tests/process-manager.test.mjs
git commit -m "feat(process-manager): add session ID capture and resume method"
```

---

## Task 7: Daemon — Multi-Phase Pipeline Controller

**Files:**
- Modify: `foreman-daemon.mjs`

This is the largest task. It rewires `#onProcessExit` and adds the pipeline controller.

- [ ] **Step 1: Add #pendingResume Map to constructor**

In the daemon constructor (or class field declarations), add:

```js
#pendingResume = new Map(); // issueNumber → { resolve, reject }
```

- [ ] **Step 2: Update all spawn() call sites to destructure { pid, sessionId }**

Search `foreman-daemon.mjs` for all calls to `this.#processes.spawn(...)`. Each currently expects a bare PID return. Update them. There are calls in:

- `#spawnTracked` (the main one — all spawn paths go through here)

In `#spawnTracked`, update:

```js
// Before:
const pid = this.#processes.spawn(issueNumber, cwd, prompt, logPrefix, scopedConfig);

// After:
const { pid, sessionId } = this.#processes.spawn(issueNumber, cwd, prompt, logPrefix, scopedConfig);
// Persist session ID to task state
sessionId.then(id => {
    this.#state.updateTask(issueNumber, { sessionId: id, pid });
}).catch(err => {
    warn(COMPONENT, `#${issueNumber}: failed to capture session ID: ${err.message}`);
});
```

- [ ] **Step 3: Implement #resumeAndWait**

Add after `#onProcessExit`:

```js
async #resumeAndWait(issueNumber, sessionId, taskBody, logPrefix, roleConfig) {
    return new Promise((resolve, reject) => {
        this.#pendingResume.set(String(issueNumber), { resolve, reject });

        try {
            const { pid, sessionId: newSessionId } = this.#processes.resume(
                issueNumber, sessionId, taskBody, logPrefix, roleConfig
            );
            this.#state.updateTask(issueNumber, { pid });
            newSessionId.then(id => {
                this.#state.updateTask(issueNumber, { sessionId: id });
            }).catch(err => {
                warn(COMPONENT, `#${issueNumber}: failed to capture resume session ID: ${err.message}`);
            });
        } catch (err) {
            this.#pendingResume.delete(String(issueNumber));
            reject(err);
        }
    });
}
```

- [ ] **Step 4: Implement #runAgentPipeline**

Add after `#resumeAndWait`:

```js
async #runAgentPipeline(issueNumber, role) {
    const task = this.#state.getTask(issueNumber);
    if (!task) {
        warn(COMPONENT, `#${issueNumber}: task disappeared during pipeline`);
        return;
    }

    const roleConfig = this.#resolveRoleConfig(role === 'planner' ? 'planner' : role === 'coder' ? 'coder' : role === 'reviewer' ? 'reviewer' : 'tester');
    const logPrefix = this.#logPrefix(issueNumber, role);

    // --- Coder-specific: commit + CI + CI-fix loop ---
    if (role === 'coder') {
        const commitResult = this.#runCommitStep(task);
        if (!commitResult.success && !commitResult.skipped) {
            return this.#requestTLDecision(issueNumber, {
                type: 'agent_completed', agent: 'coder',
                commitFailed: true, commitError: commitResult.error,
            });
        }

        if (commitResult.success) {
            const prResult = await this.#ensureTaskPR(task);
            if (!prResult.success) {
                warn(COMPONENT, `#${issueNumber}: PR creation failed: ${prResult.error}`);
            }
        }

        const ci = await this.#runCiGate(task);
        if (ci !== null && !ci.passed) {
            let ciPassed = false;
            let lastCiResult = ci;

            for (let attempt = 0; attempt < 3; attempt++) {
                this.#state.updateTask(issueNumber, { ci_fix_attempts: attempt + 1 });
                info(COMPONENT, `#${issueNumber}: CI-fix resume attempt ${attempt + 1}/3`);

                try {
                    const ciFixBody = this.#prompts.buildTaskOnly('coder', 'ci-fix', {
                        repoRoot: task.workspace,
                        ciOutput: lastCiResult.output,
                        ciSummary: lastCiResult.summary,
                    });
                    await this.#resumeAndWait(issueNumber, task.sessionId, ciFixBody, logPrefix, roleConfig);
                } catch (err) {
                    return this.#requestTLDecision(issueNumber, {
                        type: 'resume_failed', agent: 'coder', error: err.message,
                    });
                }

                this.#runCommitStep(task);
                lastCiResult = await this.#runCiGate(task);
                if (lastCiResult === null || lastCiResult.passed) {
                    ciPassed = true;
                    break;
                }
            }

            if (!ciPassed) {
                return this.#requestTLDecision(issueNumber, {
                    type: 'ci_completed', passed: false,
                    ci_fix_attempts: 3,
                    output: lastCiResult.output,
                    summary: lastCiResult.summary,
                });
            }
        }
    }

    // --- All roles: resume for handoff doc ---
    const handoffSeq = this.#docs.nextSeq(issueNumber);
    try {
        const docBody = this.#prompts.buildTaskOnly(
            'shared', `handoff-doc/${role}`,
            { docDir: task.doc_dir, seq: handoffSeq, role }
        );
        await this.#resumeAndWait(issueNumber, task.sessionId, docBody, logPrefix, roleConfig);
    } catch (err) {
        return this.#requestTLDecision(issueNumber, {
            type: 'resume_failed', agent: role, error: err.message,
        });
    }

    // --- Hard gate: doc must exist ---
    if (!this.#docs.validateDocExists(issueNumber, handoffSeq)) {
        return this.#requestTLDecision(issueNumber, {
            type: 'doc_missing', agent: role,
        });
    }

    // --- Hand off to TL ---
    const latestDoc = this.#docs.readLatestDoc(issueNumber);
    await this.#requestTLDecision(issueNumber, {
        type: 'agent_completed', agent: role, document: latestDoc?.filename ?? null,
    });
}
```

- [ ] **Step 5: Rewrite #onProcessExit to use pipeline**

Replace the body of `#onProcessExit` (lines 111–207) with:

```js
async #onProcessExit(issueNumber, code, signal) {
    const key = String(issueNumber);
    this.#clearRetryTimer(key);

    if (this.#decisionPending.has(key)) {
        info(COMPONENT, `#${issueNumber}: ignoring TL process exit while decision is pending`);
        return;
    }

    // --- If this is a resume phase exit, resolve the pending promise ---
    const pendingResume = this.#pendingResume.get(key);
    if (pendingResume) {
        this.#pendingResume.delete(key);
        pendingResume.resolve({ code, signal });
        return;
    }

    const task = this.#state.getTask(issueNumber);
    if (!task) {
        warn(COMPONENT, `Exit event for unknown task #${issueNumber} (already removed/verified)`);
        return;
    }

    const reason = signal ? `signal ${signal}` : `exit code ${code}`;
    info(COMPONENT, `Process exited for #${issueNumber}: ${reason} (state: ${task.state})`);

    const activeStates = ['planning', 'building', 'reviewing', 'testing'];
    if (!activeStates.includes(task.state)) {
        warn(COMPONENT, `#${issueNumber}: ignoring exit event - task is in '${task.state}', not an active process state`);
        return;
    }

    this.#progress.append(issueNumber, `Process exited: ${reason}`);
    task.pid = null;
    task.updated_at = new Date().toISOString();

    // Check if rate-limited
    const logFile = this.#coderLogPath(task);
    const clientName = task.client || 'codebuddy';
    if (logFile && existsSync(logFile)) {
        try {
            if (this.#detectRateLimit(logFile, clientName)) {
                const retried = this.#handleRateLimitRetry(issueNumber, task);
                if (retried) return;
            }
        } catch { /* detection failed, proceed normally */ }
    }

    // Not rate-limited — clear retry state
    this.#retryState.delete(String(issueNumber));
    this.#spawnContext.delete(String(issueNumber));
    try { this.#state.clearRuntimeContext(issueNumber); } catch (e) { warn(COMPONENT, `#${issueNumber}: failed to clear runtime context: ${e.message}`); }

    const agentRole = {
        planning: 'planner',
        building: 'coder',
        reviewing: 'reviewer',
        testing: 'tester',
    }[task.state];

    // Enter the multi-phase pipeline
    await this.#runAgentPipeline(issueNumber, agentRole);
}
```

- [ ] **Step 6: Run full daemon test suite**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node --test tests/
```

Expected: all tests pass. If there are integration tests that mock `#onProcessExit` behavior and check for `doc_validation_failed`, they will need updating — fix them to expect `agent_completed` with `doc_missing` or the pipeline flow.

- [ ] **Step 7: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add foreman-daemon.mjs
git commit -m "feat(daemon): add multi-phase resume pipeline controller"
```

---

## Task 8: TL Decision Prompt Update

**Files:**
- Modify: `prompts/tasks/tl/decision.md`

- [ ] **Step 1: Update trigger types in decision rules**

In `prompts/tasks/tl/decision.md`, make these changes:

1. Remove any reference to `doc_validation_failed` trigger handling.

2. Add to the decision rules section (after the CI hard gate rule):

```markdown
- CI-fix（最多 3 轮）由 daemon 内部 resume 处理，超过 3 轮 CI 失败才会上报。收到 `ci_completed` + `passed: false` + `ci_fix_attempts: 3` 时，评估是否 abandon 或换模型
- 收到 `doc_missing` 时，agent 的核心工作可能完成但交接文档缺失。评估是否重新 spawn 该 agent
- 收到 `resume_failed` 时，表示 session resume 异常。评估是否重新 spawn 该 agent（全新会话）
```

3. Update the TL 工作步骤 to read from both `iterations/` and `plans/`:

```markdown
1. Read `{{ docDir }}/decisions/` 了解之前的决策
2. Read `{{ docDir }}/orchestration.md` 了解决策索引
3. Read `{{ docDir }}/iterations/` 目录下的交接文档
4. 如需查看详细计划，Read `{{ docDir }}/plans/` 下的 planner 文档
5. 如果有最新文档，Read 全文评估其质量
6. 评估当前触发事件和系统状态
7. 决定下一步 Action 和 Task
8. 为下游 agent 编写 TL Context
```

- [ ] **Step 2: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add prompts/tasks/tl/decision.md
git commit -m "refactor(tl-prompt): adapt to multi-phase pipeline triggers"
```

---

## Task 9: Planner Spawn — Ensure plans/ Directory Creation

**Files:**
- Modify: `foreman-daemon.mjs` (in `#spawnPlanner`)

- [ ] **Step 1: Add plans dir creation to #spawnPlanner**

In `#spawnPlanner`, after the existing `docDir` setup, add creation of the plans subdirectory:

```js
const plansDir = this.#docs.getPlansDir(issueNumber);
mkdirSync(plansDir, { recursive: true });
```

Also update the path constraints so the planner can write to `plans/`:

```js
// Update writePaths to include plans dir
writePaths: [plansDir, docDir],
```

- [ ] **Step 2: Run full test suite**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node --test tests/
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add foreman-daemon.mjs
git commit -m "feat(daemon): create plans/ dir for planner output"
```

---

## Task 10: Integration Smoke Test

- [ ] **Step 1: Run the full test suite**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node --test tests/
```

All tests must pass.

- [ ] **Step 2: Verify template rendering end-to-end**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
node -e "
const { PromptBuilder } = await import('./lib/prompt-builder.mjs');
const pb = new PromptBuilder('./prompts');

// Test all 4 handoff templates render
for (const role of ['planner', 'coder', 'reviewer', 'tester']) {
    const result = pb.buildTaskOnly('shared', \`handoff-doc/\${role}\`, {
        docDir: 'docs/foreman/42', seq: '03', role
    });
    const hasBase = result.includes('读者意识');
    const hasRole = result.includes(role.charAt(0).toUpperCase() + role.slice(1) + ' 补充');
    console.log(\`\${role}: base=\${hasBase}, role=\${hasRole} → \${hasBase && hasRole ? 'PASS' : 'FAIL'}\`);
}

// Test ci-fix renders without doc section
const ciFix = pb.buildTaskOnly('coder', 'ci-fix', { repoRoot: '/tmp' });
console.log(\`ci-fix no doc section: \${!ciFix.includes('产出格式') ? 'PASS' : 'FAIL'}\`);
"
```

Expected: all `PASS`.

- [ ] **Step 3: Commit any fixes**

If any fixes were needed, commit them:

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools/foreman
git add -A
git commit -m "fix: address integration test findings"
```

---

## Task 11: Final Commit and Push

- [ ] **Step 1: Push submodule**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools
git push origin main
```

- [ ] **Step 2: Update parent repo submodule pointer**

```bash
cd /Users/dluckdu/Documents/Github/gol
git add gol-tools
git commit -m "chore(foreman): update gol-tools submodule for multi-phase resume pipeline"
git push origin main
```
