# Foreman Multi-Phase Resume Pipeline Design

**日期**: 2026-04-04
**状态**: Draft
**触发**: Issue #226 E2E 测试报告暴露 coder 文档问题（P0）和 AGENTS.md 误修改（P1）

---

## 一、问题背景

### 1.1 直接问题

Issue #226 E2E 测试中发现：

- **P0**: kimi-k2.5-ioa coder 连续 3 次无法补齐交接文档的必填章节（`## 完成的工作`、`## 测试契约覆盖`、`## 决策记录`），导致无意义 rework 循环浪费 ~10 分钟。此问题已第二次导致 dead letter。
- **P1**: coder 修改了 `AGENTS.md` 文件，违反 TL decision 中的明确禁止。

### 1.2 根因分析

当前每个 agent 角色（planner、coder、reviewer、tester）在一次 spawn 中同时承担**核心工作**和**文档编写**两个职责。模型的注意力窗口有限——coder 在完成 263 行 VFX 系统实现后，文档要求已在注意力边缘。这不是偶发问题，而是"一次 spawn 做所有事"架构的系统性弱点。

### 1.3 设计目标

1. 将核心工作与文档编写分离为独立阶段，每阶段专注单一任务
2. 利用 codebuddy 的 session resume 机制实现阶段续接，保留完整上下文
3. 多阶段由 daemon 内部控制，对 TL 透明
4. 建立通用的 handoff doc 机制，所有角色复用
5. 简化 doc-manager，移除阻碍流程的硬格式校验

---

## 二、核心设计：多阶段 Resume 架构

### 2.1 概念

将当前"一次 spawn 完成所有工作"的模式改为 **daemon 内部控制的多阶段 resume 链**。每个角色的工作被拆分为：**核心工作阶段（全量 prompt spawn）** → **后续阶段（resume 注入 task body）**。阶段间不回流 TL，由 daemon 直接续接。

Resume 时只注入 task body，不重复 identity、rules、environment 等系统提示词层（首次 spawn 已加载）。

### 2.2 各角色阶段定义

#### Coder（最复杂）

```
spawn(全量 prompt: identity + implement-task + tlContext + env)
  → exit, capture sessionId
  → daemon: #runCommitStep + #runCiGate
  → [CI fail?] resume(sessionId, ci-fix task body), 最多 3 轮
  → [CI 3轮仍失败?] 不再 resume，整体 trigger 交 TL
  → resume(sessionId, handoff-doc task body)
  → exit → 文档存在性检查 → trigger TL
```

- CI-fix resume 轮次有独立计数器 `ci_fix_attempts`，不消耗 `internal_rework_count`
- 3 轮 CI-fix 用尽后，daemon 将完整 CI 失败详情交 TL 决策

#### Planner

```
spawn(全量 prompt: identity + analysis-task + tlContext + env)
  → exit, capture sessionId
  → resume(sessionId, handoff-doc task body)
  → exit → 文档存在性检查 → trigger TL
```

#### Reviewer / Tester

```
spawn(全量 prompt: identity + review/test-task + tlContext + env)
  → exit, capture sessionId
  → resume(sessionId, handoff-doc task body)
  → exit → 文档存在性检查 → trigger TL
```

### 2.3 关键约束

- 多阶段是 daemon 内部控制，**对 TL 透明**——TL 只看到 `agent_completed`、`doc_missing` 或 `resume_failed`
- CI-fix resume 轮次独立计数，不消耗 rework 预算
- Session ID 持久化到 task state，daemon restart 后总是尝试 resume
- Resume 异常（程序异常，非 session 过期）时记录异常情况，交 TL 决策是否重新 spawn

---

## 三、Session ID 捕获与 Resume 机制

### 3.1 Codebuddy Resume CLI 接口

```bash
# 恢复指定会话
codebuddy --resume <sessionId> -p <taskBody> --output-format stream-json

# 相关 flag
-c, --continue              # 继续最近的会话
-r, --resume [sessionId]    # 恢复指定会话
--session-id <uuid>         # 使用特定 session ID
```

Session ID 从 `--output-format stream-json` 的 init 消息中获取：
```json
{ "type": "system", "subtype": "init", "session_id": "uuid-here" }
```

### 3.2 Stream-JSON 拦截

当前 `process-manager.mjs` 将 stdout 直接 `pipe` 到日志文件，不解析内容。改为**拦截 + 透传**模式：

```
stdout → line splitter → parse JSON → 提取 session_id → 写入日志文件
                                     ↓
                              resolve sessionIdPromise
```

实现方式：在 stdout 和 logStream 之间插入一个 Transform stream，逐行解析 JSON。仅在收到 init 消息时提取 session_id，其余数据原样透传到日志。

### 3.3 spawn 返回值变化

```js
// 现有
spawn(...) → pid (number)

// 改为
spawn(...) → { pid, sessionId }
// sessionId 是 Promise<string>，init 消息解析到时 resolve
// 进程退出前未收到 init 消息则 reject
```

### 3.4 新增 resume 方法

```js
resume(issueNumber, sessionId, taskBody, logPrefix, roleConfig) → { pid, sessionId }
// 构建: codebuddy --resume <sessionId> -p <taskBody> --output-format stream-json
// 返回值同 spawn（resume 可能产生新 session ID）
// resume 失败时抛出异常，由 daemon 捕获后交 TL
```

### 3.5 Task State 扩展

```js
// task 新增字段
{
  sessionId: string | null,       // 当前会话 session ID
  ci_fix_attempts: number,        // CI 自修轮次（独立于 internal_rework_count）
}
```

Session ID 持久化到 `state.json`，daemon restart 后可恢复。

### 3.6 `-p` + `--resume` 组合验证

在实施前需验证 `codebuddy --resume <sessionId> -p <taskBody>` 的组合是否正常工作。通过委派子代理进行 headless 模式实测验证（参考 `2026-04-03-codebuddy-permission-verification.md` 的验证方式），产出验证报告到 `docs/reports/`。

---

## 四、Doc-Manager 简化

### 4.1 现有行为

```js
// 硬匹配 5 个标题字符串
validateRequiredSections(filename, role)
// → 缺失 → trigger doc_validation_failed → TL rework
```

`REQUIRED_SECTIONS` 常量定义了 planner/coder/reviewer/tester 各自的必填标题列表，daemon 在 agent 退出后用 `content.includes(section)` 做精确字符串匹配。

### 4.2 改为：纯文档管理 + 存在性检查

**删除内容：**
- `REQUIRED_SECTIONS` 常量
- `validateRequiredSections()` 方法
- daemon 中 `doc_validation_failed` trigger 类型

**保留/新增：**
- 所有目录管理方法（`ensureIssueDir`、`getDocDir`、`getIterationsDir`、`getDecisionsDir`）
- 文件列表和读取方法（`listDocs`、`readDoc`、`readAllDocs`、`readLatestDoc`）
- 决策文档管理（`writeDecisionFromDaemon`、`readDecision` 等）
- Orchestration 管理
- 文件名校验（`validateFilename`）
- **新增** `getPlansDir(issueNumber)` — 返回 `docs/foreman/<issueNumber>/plans/`
- **新增** `validateDocExists(issueNumber)` — 检查 iterations/ 下是否有 agent 产出的最新文档

### 4.3 硬门控

唯一阻塞流程的检查：**文档不存在**。

```js
validateDocExists(issueNumber, expectedSeq) → boolean
// 检查 iterations/ 下是否存在序号 >= expectedSeq 的文档
// expectedSeq 由 daemon 在 resume handoff-doc 前分配，确保检查的是本轮产出
// 不存在 → trigger { type: 'doc_missing', agent: role } → TL 决策
// 存在 → 继续流程
```

文档格式、章节、内容质量均不校验。TL 自己阅读文档内容做判断。

---

## 五、文档目录结构调整

### 5.1 现有结构

```
docs/foreman/<issueNumber>/
├── orchestration.md
├── decisions/
│   └── NNN-<slug>.md
└── iterations/
    ├── 01-planner-xxx.md       ← planner 计划文档 + 交接混在一起
    ├── 02-coder-xxx.md
    ├── 03-reviewer-xxx.md
    └── 04-tester-xxx.md
```

### 5.2 新结构

```
docs/foreman/<issueNumber>/
├── orchestration.md              ← TL 决策索引（不变）
├── decisions/                    ← TL 决策记录（不变）
│   ├── 001-planning.md
│   ├── 002-building.md
│   └── ...
├── plans/                        ← 【新】planner 计划文档（核心工作产物）
│   └── 01-planner-xxx.md
└── iterations/                   ← 所有角色的 handoff doc（交接文档）
    ├── 02-planner-handoff-xxx.md
    ├── 03-coder-xxx.md
    ├── 04-reviewer-xxx.md
    └── 05-tester-xxx.md
```

### 5.3 职责分离

| 目录 | 用途 | 写入者 | 读取者 |
|------|------|--------|--------|
| `plans/` | 深度计划文档 | planner Phase 1 | coder（实现参考） |
| `iterations/` | 交接文档（handoff） | 所有角色 Phase 最终阶段 | TL（决策依据） |
| `decisions/` | TL 决策记录 | daemon（代写 TL 决策） | 所有角色（上下文） |

TL 决策时只需要读 `iterations/` 和 `decisions/` 就能掌握全貌，`plans/` 是深度参考资料。

---

## 六、Handoff Doc 模板体系

### 6.1 设计理念

Handoff doc 是**面向团队其他成员和 Team Leader 的交接文档**，不是个人笔记。所有 agent 需要具备读者意识——读者不了解工作细节，需要快速理解：做了什么、为什么、什么状态、下一步。

### 6.2 模板继承结构

沿用现有 Nunjucks `{% extends %}` + `{% block %}` 继承模式：

```
prompts/tasks/shared/
├── handoff-doc.md              ← base 模板（通用部分）
└── handoff-doc/
    ├── planner.md              ← planner 专属补充
    ├── coder.md                ← coder 专属补充
    ├── reviewer.md             ← reviewer 专属补充
    └── tester.md               ← tester 专属补充
```

### 6.3 Base 模板 — `shared/handoff-doc.md`

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

### 6.4 角色专属模板

#### `handoff-doc/planner.md`

```markdown
{% extends "shared/handoff-doc.md" %}
{% block role_specific %}
### Planner 补充
- 方案选型理由和被排除的备选方案
- 风险点和缓解措施
- 给 coder 的实现注意事项
{% endblock %}
```

#### `handoff-doc/coder.md`

```markdown
{% extends "shared/handoff-doc.md" %}
{% block role_specific %}
### Coder 补充
- 列出修改/新增的文件及变更原因
- 对照 planner 测试契约，说明覆盖状态
- 与原计划的偏差及原因
{% endblock %}
```

#### `handoff-doc/reviewer.md`

```markdown
{% extends "shared/handoff-doc.md" %}
{% block role_specific %}
### Reviewer 补充
- 审查通过/不通过的判断依据
- 发现的问题清单（含文件名和行号）
- 代码质量和架构合规性评估
{% endblock %}
```

#### `handoff-doc/tester.md`

```markdown
{% extends "shared/handoff-doc.md" %}
{% block role_specific %}
### Tester 补充
- 测试用例和执行结果
- 截图或日志证据
- 未覆盖的场景和已知局限
{% endblock %}
```

---

## 七、Daemon 阶段控制器

### 7.1 新增 #runAgentPipeline

替代当前各角色退出后直接交 TL 的逻辑。

```js
async #runAgentPipeline(issueNumber, role) {
    const task = this.#state.getTask(issueNumber);

    // --- Coder 专属：commit + CI + CI-fix ---
    if (role === 'coder') {
        const commitResult = this.#runCommitStep(task);
        if (!commitResult.success) {
            return this.#requestTLDecision(issueNumber, {
                type: 'agent_completed', agent: 'coder',
                commitFailed: true, commitError: commitResult.error
            });
        }

        await this.#ensureTaskPR(task);

        // CI gate + resume 自修循环
        let ciPassed = false;
        let lastCiResult;
        for (let attempt = 0; attempt < 3; attempt++) {
            lastCiResult = this.#runCiGate(task);
            if (lastCiResult.passed) { ciPassed = true; break; }

            task.ci_fix_attempts = attempt + 1;
            this.#state.updateTask(issueNumber, { ci_fix_attempts: task.ci_fix_attempts });

            const ciFixBody = this.#prompts.buildTaskOnly('coder', 'ci-fix', {
                ciOutput: lastCiResult.output, ciSummary: lastCiResult.summary
            });
            await this.#resumeAndWait(issueNumber, task.sessionId, ciFixBody);
            this.#runCommitStep(task); // 重新提交修复
        }

        if (!ciPassed) {
            return this.#requestTLDecision(issueNumber, {
                type: 'ci_completed', passed: false,
                ci_fix_attempts: 3,
                output: lastCiResult.output,
                summary: lastCiResult.summary
            });
        }
    }

    // --- 所有角色通用：resume handoff doc ---
    const handoffSeq = this.#docs.nextSeq(issueNumber);
    try {
        const docBody = this.#prompts.buildTaskOnly(
            'shared', `handoff-doc/${role}`,
            { docDir: task.doc_dir, seq: handoffSeq, role }
        );
        await this.#resumeAndWait(
            issueNumber, task.sessionId, docBody, logPrefix, roleConfig
        );
    } catch (err) {
        // resume 异常，记录并交 TL
        return this.#requestTLDecision(issueNumber, {
            type: 'resume_failed', agent: role, error: err.message
        });
    }

    // --- 文档存在性硬门控（检查本轮产出）---
    if (!this.#docs.validateDocExists(issueNumber, handoffSeq)) {
        return this.#requestTLDecision(issueNumber, {
            type: 'doc_missing', agent: role
        });
    }

    // --- 交 TL ---
    const latestDoc = this.#docs.readLatestDoc(issueNumber);
    this.#requestTLDecision(issueNumber, {
        type: 'agent_completed', agent: role, document: latestDoc.filename
    });
}
```

### 7.2 新增 #resumeAndWait

```js
async #resumeAndWait(issueNumber, sessionId, taskBody, logPrefix, roleConfig) {
    return new Promise((resolve, reject) => {
        // 注册 pending resume，使 #onProcessExit 知道这是多阶段内退出
        this.#pendingResume.set(String(issueNumber), { resolve, reject });

        try {
            const { pid, sessionId: newSessionId } = this.#processes.resume(
                issueNumber, sessionId, taskBody, logPrefix, roleConfig
            );
            // 更新 task 中的 sessionId（resume 可能产生新 ID）
            newSessionId.then(id => {
                this.#state.updateTask(issueNumber, { sessionId: id });
            });
        } catch (err) {
            this.#pendingResume.delete(String(issueNumber));
            reject(err);
        }
    });
}
```

### 7.3 #onProcessExit 改造

```
#onProcessExit(issueNumber, code, signal):
  → rate limit check（保持不变）
  → 检查 #pendingResume 中是否有该 issueNumber
    → [有] resolve pending Promise，return（不触发 TL）
    → [无] 确定角色 → 调用 #runAgentPipeline(issueNumber, role)
```

Phase 1（核心工作）退出时走 `[无]` 路径进入 `#runAgentPipeline`。后续阶段（CI-fix、handoff-doc）退出时走 `[有]` 路径仅 resolve Promise。

---

## 八、提示词改造

### 8.1 implement.md — 删除文档要求

删除第 17-39 行"产出格式"整个段落。保留工作步骤和完成标准，coder 只管写代码。

### 8.2 rework.md — 删除文档要求

删除第 15-26 行"产出格式"整个段落。保留修复步骤和完成标准。

### 8.3 ci-fix.md — 保持不变

已经只关注修 CI，且会被 resume 注入。

### 8.4 initial-analysis.md — 写入路径改为 plans/

Planner Phase 1 计划文档写入路径从 `{{ docDir }}/iterations/` 改为 `{{ docDir }}/plans/`。文档内容要求不变——这是 planner 的核心工作产物。

### 8.5 PromptBuilder 扩展

新增方法，只渲染 task body，用于 resume 注入：

```js
buildTaskOnly(role, taskTemplate, context) {
    return this.#env.render(`tasks/${role}/${taskTemplate}.md`, context);
}
```

用法：
- `buildTaskOnly('shared', 'handoff-doc/coder', ctx)` — coder 的 handoff doc
- `buildTaskOnly('coder', 'ci-fix', ctx)` — CI 修复任务

---

## 九、TL Prompt 适配

### 9.1 新增 Trigger 类型

| Trigger 类型 | 含义 | TL 预期行为 |
|-------------|------|-------------|
| `doc_missing` | Agent 未产出交接文档 | 判断是否需要重新 spawn |
| `resume_failed` | Resume 异常（程序错误） | 判断是否需要重新 spawn |

### 9.2 废除 Trigger 类型

| Trigger 类型 | 原因 |
|-------------|------|
| `doc_validation_failed` | 不再做内容格式校验 |

### 9.3 TL Decision 模板更新

在 `prompts/tasks/tl/decision.md` 中：
- 移除对 `doc_validation_failed` 的处理规则
- 新增 `doc_missing` 和 `resume_failed` 的处理指导
- 说明 CI-fix 由 daemon 内部处理最多 3 轮，超出后才会上报

---

## 十、涉及的改动文件汇总

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `lib/process-manager.mjs` | 修改 | stream-json 拦截捕获 session ID；新增 `resume()` 方法；`spawn` 返回 `{ pid, sessionId }` |
| `lib/prompt-builder.mjs` | 修改 | 新增 `buildTaskOnly()` 方法 |
| `lib/doc-manager.mjs` | 修改 | 删除 `REQUIRED_SECTIONS`、`validateRequiredSections`；新增 `getPlansDir`、`validateDocExists`；简化为纯文档管理 |
| `lib/state-manager.mjs` | 修改 | task 新增 `sessionId`、`ci_fix_attempts` 字段 |
| `foreman-daemon.mjs` | 修改 | 新增 `#runAgentPipeline`、`#resumeAndWait`、`#pendingResume` Map；改造 `#onProcessExit` |
| `prompts/tasks/coder/implement.md` | 修改 | 删除"产出格式"段落 |
| `prompts/tasks/coder/rework.md` | 修改 | 删除文档要求 |
| `prompts/tasks/planner/initial-analysis.md` | 修改 | 写入路径改为 `plans/` 目录 |
| `prompts/tasks/shared/handoff-doc.md` | 新建 | 通用 handoff doc base 模板 |
| `prompts/tasks/shared/handoff-doc/planner.md` | 新建 | planner 专属补充 |
| `prompts/tasks/shared/handoff-doc/coder.md` | 新建 | coder 专属补充 |
| `prompts/tasks/shared/handoff-doc/reviewer.md` | 新建 | reviewer 专属补充 |
| `prompts/tasks/shared/handoff-doc/tester.md` | 新建 | tester 专属补充 |
| `prompts/tasks/tl/decision.md` | 修改 | 适配新 trigger 类型 |
| `tests/doc-manager.test.mjs` | 修改 | 更新测试用例匹配新 API |
| `tests/process-manager.test.mjs` | 修改 | 新增 resume、session ID 捕获测试 |

### 前置验证任务

| 任务 | 说明 |
|------|------|
| `codebuddy -p + --resume` 组合验证 | 委派子代理实测验证 headless 模式下的 resume 行为，产出报告到 `docs/reports/` |

---

## 十一、风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| `--resume` + `-p` 组合不支持 | 整个 resume 方案不可行 | 前置验证任务；备选方案：`--continue` + stdin pipe |
| Resume session 上下文丢失 | handoff doc 质量下降 | codebuddy session 设计为持久化上下文，不预期丢失 |
| Daemon restart 后 resume 失败 | 单个 issue pipeline 中断 | 异常交 TL 决策，TL 可选择重新 spawn |
| CI-fix 3 轮仍失败 | 消耗时间但未解决问题 | 3 轮硬上限后交 TL，TL 可选择 abandon 或换模型 |
