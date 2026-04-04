# Remove Handoff Document Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除 foreman daemon 中 handoff 文档的机械验证系统（REQUIRED_SECTIONS 字符串匹配），消除 ~75% 误报率导致的无效 coder rework 循环。

**Architecture:** 纯删除 — 移除 `validateRequiredSections()` 验证器、3 个 runtime guard 函数、daemon 中的 alert/bypass 链路和对应测试。所有角色完成时无条件生成 `agent_completed` trigger（文档缺失的硬失败检测保留）。文档格式约束回归 prompt 模板定义。

**Tech Stack:** Node.js (ESM), node:test, GOL Foreman daemon

**Spec:** `docs/superpowers/specs/2026-04-04-remove-handoff-validation-design.md`

---

### Task 1: 删除 `lib/doc-manager.mjs` 中的验证器

**Files:**
- Modify: `gol-tools/foreman/lib/doc-manager.mjs`

- [ ] **Step 1: 删除 `REQUIRED_SECTIONS` 常量**

删除 L10-15：

```javascript
export const REQUIRED_SECTIONS = {
    planner: ['## 需求分析', '## 影响面分析', '## 实现方案', '## 架构约束', '## 测试契约', '## 风险点', '## 建议的实现步骤'],
    coder: ['## 完成的工作', '## 测试契约覆盖', '## 决策记录', '## 仓库状态', '## 未完成事项'],
    reviewer: ['## 审查范围', '## 验证清单', '## 发现的问题', '## 测试契约检查', '## 结论'],
    tester: ['## 测试环境', '## 测试用例与结果', '## 发现的非阻塞问题', '## 结论'],
};
```

- [ ] **Step 2: 删除 `validateRequiredSections()` 方法**

删除 L130-146 整个方法：

```javascript
validateRequiredSections(filename, role) {
    const requiredSections = REQUIRED_SECTIONS[role];
    if (!requiredSections) {
        throw new Error(`Unknown role for document validation: ${role}`);
    }

    const content = readFileSync(filename, 'utf-8');
    const missingSections = requiredSections.filter(section => !content.includes(section));
    if (missingSections.length > 0) {
        warn(COMPONENT, `Document ${filename} is missing required sections for ${role}: ${missingSections.join(', ')}`);
    }

    return {
        valid: missingSections.length === 0,
        missingSections,
    };
}
```

- [ ] **Step 3: 验证文件无语法错误**

Run: `node -c gol-tools/foreman/lib/doc-manager.mjs`
Expected: 无输出（语法正确）

- [ ] **Step 4: Commit**

```bash
cd gol-tools && git add lib/doc-manager.mjs && git commit -m "refactor(foreman): remove REQUIRED_SECTIONS and validateRequiredSections from doc-manager"
```

---

### Task 2: 删除 `lib/daemon-runtime-utils.mjs` 中的 3 个 guard 函数

**Files:**
- Modify: `gol-tools/foreman/lib/daemon-runtime-utils.mjs`

- [ ] **Step 1: 删除 `shouldTreatValidationAsWarning()` 函数（L38-40）**

```javascript
export function shouldTreatValidationAsWarning(agentRole, missingSections) {
    return agentRole !== 'planner' && Array.isArray(missingSections) && missingSections.length > 0;
}
```

- [ ] **Step 2: 删除 `reviewerDocIndicatesApproval()` 函数（L42-52）**

```javascript
export function reviewerDocIndicatesApproval(content) {
    if (!content) return false;

    const conclusionMatch = content.match(/##\s*结论([\s\S]*)$/);
    const scope = (conclusionMatch?.[1] || content).toLowerCase();

    const positive = /\bverified\b|已通过|通过|建议\s*verify|可以\s*verify/;
    const negative = /\brework\b|不通过|未通过|blocker|阻塞|需返工|必须返工/;

    return positive.test(scope) && !negative.test(scope);
}
```

- [ ] **Step 3: 删除 `shouldBypassCoderReworkForDocWarning()` 函数（L54-62）**

```javascript
export function shouldBypassCoderReworkForDocWarning(trigger, decision) {
    return trigger?.agent === 'reviewer'
        && trigger?.handoffValidationFailed === true
        && trigger?.reviewApproved === true
        && decision?.action === 'spawn @coder'
        && !trigger?.commitFailed
        && !trigger?.prFailed
        && !trigger?.ciFailed
        && !trigger?.testerAborted;
}
```

- [ ] **Step 4: 验证剩余函数仍可导入**

Run: `node -e "import('./gol-tools/foreman/lib/daemon-runtime-utils.mjs').then(m => { console.log('OK exports:', Object.keys(m).join(', ')) })"`
Expected: `OK exports: clearTrackedTimeout, shouldReuseRespawnCwd, remapPathConstraintsForRespawn`（3 个保留函数）

- [ ] **Step 5: Commit**

```bash
cd gol-tools && git add lib/daemon-runtime-utils.mjs && git commit -m "refactor(foreman): remove handoff validation guard functions from daemon-runtime-utils"
```

---

### Task 3: 简化 `foreman-daemon.mjs` 的 trigger 构造逻辑

**Files:**
- Modify: `gol-tools/foreman/foreman-daemon.mjs`

- [ ] **Step 1: 清理 imports（L22-29）**

将：
```javascript
import {
    clearTrackedTimeout,
    shouldReuseRespawnCwd,
    remapPathConstraintsForRespawn,
    shouldTreatValidationAsWarning,
    reviewerDocIndicatesApproval,
    shouldBypassCoderReworkForDocWarning,
} from './lib/daemon-runtime-utils.mjs';
```
替换为：
```javascript
import {
    clearTrackedTimeout,
    shouldReuseRespawnCwd,
    remapPathConstraintsForRespawn,
} from './lib/daemon-runtime-utils.mjs';
```

- [ ] **Step 2: 简化 trigger 构造（L199-243）**

将整个 `if (agentRole === 'planner') ... else if (latestDoc) ... else` 块替换为：

```javascript
if (agentRole === 'planner') {
    const latestIterationDoc = this.#docs.readLatestPlannerIterationDoc(issueNumber);
    if (!latestDoc || !latestIterationDoc) {
        const missing = [
            !latestDoc ? 'planner plan doc in plans/' : null,
            !latestIterationDoc ? 'planner handoff doc in iterations/' : null,
        ].filter(Boolean);
        trigger = {
            type: 'doc_validation_failed',
            document: latestDoc?.filename || latestIterationDoc?.filename || null,
            errors: missing,
        };
    } else {
        trigger = { type: 'agent_completed', agent: agentRole, document: latestIterationDoc.filename };
    }
} else if (latestDoc) {
    trigger = { type: 'agent_completed', agent: agentRole, document: latestDoc.filename };
} else {
    trigger = { type: 'agent_completed', agent: agentRole, document: null };
}
```

关键变化：planner 分支删除了 `validateRequiredSections` 调用（L217-220），非 planner 分支删除了整个验证/warning 分支（L222-240）。

- [ ] **Step 3: 删除 alert 构造（L315-317）**

删除：
```javascript
if (trigger.handoffValidationFailed) {
    alerts.push(`⚠ Non-blocking handoff doc gaps (${trigger.agent}): ${trigger.handoffMissingSections.join(', ')}`);
}
```

- [ ] **Step 4: 删除 bypass 逻辑（L341-349）**

删除：
```javascript
if (shouldBypassCoderReworkForDocWarning(trigger, decision)) {
    warn(COMPONENT, `#${issueNumber}: overriding coder rework because reviewer approved the work and only non-blocking handoff doc issues remain`);
    decision = {
        ...decision,
        action: 'verify',
        task: null,
        guidance: `${decision.guidance ? `${decision.guidance}\n` : ''}Reviewer approved the substantive work; handoff doc formatting gaps are non-blocking and should not trigger coder rework.`,
    };
}
```

- [ ] **Step 5: 验证无语法错误且无残留引用**

Run: `node -c gol-tools/foreman/foreman-daemon.mjs`
Expected: 无输出

Run: `grep -n 'validateRequired\|handoffValidation\|handoffMissing\|shouldTreatVal\|shouldBypass\|reviewerDocIndicates\|REQUIRED_SECTIONS' gol-tools/foreman/foreman-daemon.mjs`
Expected: 无匹配（确认零残留）

- [ ] **Step 6: Commit**

```bash
cd gol-tools && git add foreman-daemon.mjs && git commit -m "refactor(foreman): remove handoff validation from daemon trigger construction"
```

---

### Task 4: 清理 TL decision prompt 中的 handoff 规则

**Files:**
- Modify: `gol-tools/foreman/prompts/tasks/tl/decision.md`

- [ ] **Step 1: 删除两条 handoff 反 rework 规则（L19-20）**

删除：
```
- **如果 trigger / systemAlerts 表示只是 handoff 文档章节不完整（non-blocking handoff doc gaps），不要仅因文档格式/交接文字质量不足而派发 coder rework。先判断代码、测试、review 结论是否已经满足 issue 目标；若实质工作已完成，应优先 verify 或保持在当前专业角色处理，而不是重新打开实现工作。**
- **只有当 reviewer/tester/planner 指出实质性缺陷（代码行为错误、测试契约未满足、实现与 issue 目标不符）时，才允许 spawn @coder rework。handoff 文档改进本身不算"实现未完成"。**
```

同时确认决策规则表中没有其他 handoff 引用。

- [ ] **Step 2: Commit**

```bash
cd gol-tools && git add prompts/tasks/tl/decision.md && git commit -m "refactor(foreman): remove handoff doc rules from TL decision prompt"
```

---

### Task 5: 更新测试文件

**Files:**
- Modify: `gol-tools/foreman/tests/doc-manager.test.mjs`
- Modify: `gol-tools/foreman/tests/daemon-runtime-utils.test.mjs`

- [ ] **Step 1: 清理 doc-manager test — 删除 import 和测试套件**

在 `tests/doc-manager.test.mjs` 中：

a) L8：从 import 中删除 `REQUIRED_SECTIONS`：
   ```javascript
   // Before:
   import { DocManager, REQUIRED_SECTIONS } from '../lib/doc-manager.mjs';
   // After:
   import { DocManager } from '../lib/doc-manager.mjs';
   ```

b) 删除整个 `describe('validateRequiredSections', ...)` 块（L90-176），包含以下 4 个 test case：
   - "passes when all required sections are present"（L91-108）
   - "reports missing required sections"（L110-122）
   - "throws for an unknown role"（L124-128）
   - "keeps worker prompt headings aligned with validator expectations"（L130-175）

- [ ] **Step 2: 清理 daemon-runtime-utils test — 删除 import 和测试套件**

在 `tests/daemon-runtime-utils.test.mjs` 中：

a) 从 import 中删除 3 个函数（L9-11）：
   ```javascript
   // Before:
   import {
       clearTrackedTimeout,
       shouldReuseRespawnCwd,
       remapPathConstraintsForRespawn,
       shouldTreatValidationAsWarning,
       reviewerDocIndicatesApproval,
       shouldBypassCoderReworkForDocWarning,
   } from '../lib/daemon-runtime-utils.mjs';
   // After:
   import {
       clearTrackedTimeout,
       shouldReuseRespawnCwd,
       remapPathConstraintsForRespawn,
   } from '../lib/daemon-runtime-utils.mjs';
   ```

b) 删除以下 3 个 test case：
   - "shouldTreatValidationAsWarning only downgrades non-planner handoff validation failures"（L85-89）
   - "reviewerDocIndicatesApproval recognizes verified conclusions"（L91-97）
   - "shouldBypassCoderReworkForDocWarning only fires for reviewer-approved non-blocking handoff failures"（L99-114）

- [ ] **Step 3: 运行全部测试确认通过**

Run: `cd gol-tools/foreman && node --test tests/doc-manager.test.mjs tests/daemon-runtime-utils.test.mjs`
Expected: 全部 PASS（总测试数减少约 7 个）

- [ ] **Step 4: Commit**

```bash
cd gol-tools && git add tests/ && git commit -m "test(foreman): remove handoff validation tests matching deleted code"
```

---

### Task 6: 最终验证 & 推送

**Files:** 无新文件（仅验证）

- [ ] **Step 1: 运行完整测试套件**

Run: `cd gol-tools/foreman && node --test tests/**/*.test.mjs`
Expected: 所有测试通过，无 import 错误

- [ ] **Step 2: grep 残留扫描**

在整个 `gol-tools/foreman/` 目录中运行：
```
grep -rn 'validateRequiredSections\|REQUIRED_SECTIONS\|handoffValidationFailed\|handoffMissingSections\|shouldTreatValidationAsWarning\|reviewerDocIndicatesApproval\|shouldBypassCoderReworkForDocWarning' --include="*.mjs" --include="*.md"
```
预期结果：仅在 `docs/foreman/` 历史决策文件中出现（那些是运行时产物，不需要修改）。源代码中应**零匹配**。

- [ ] **Step 3: Daemon 启动检查**

Run: `node -e "import('./gol-tools/foreman/foreman-daemon.mjs').then(() => console.log('Daemon loads OK')).catch(e => console.error('FAIL:', e.message))"`
Expected: `Daemon loads OK`（daemon 可正常加载，无模块解析错误）

- [ ] **Step 4: Push submodule + parent repo**

```bash
# Push submodule
cd gol-tools && git push

# Update parent
cd .. && git add gol-tools && git commit -m "chore(foreman): update gol-tools submodule — remove handoff doc validation" && git push
```

---

## Self-Review

**Spec coverage:**
- ✅ Task 1: 删除 `REQUIRED_SECTIONS` + `validateRequiredSections` (Spec § Changes #1)
- ✅ Task 2: 删除 3 个 guard 函数 (Spec § Changes #2)
- ✅ Task 3: daemon trigger 构造简化 + import 清理 + alert 删除 + bypass 删除 (Spec § Changes #3)
- ✅ Task 4: TL prompt handoff 规则清理 (Spec § Changes #4)
- ✅ Task 5: 对应测试删除 (Spec § Changes #5)
- ✅ Task 6: 残留扫描 + 集成验证 (Spec § Verification)

**Placeholder scan:** 无 TBD/TODO/fill-in。每步有确切代码或命令。

**Type consistency:** 函数名在各 task 中一致（`validateRequiredSections`, `shouldTreatValidationAsWarning` 等）。文件路径使用绝对路径前缀 `gol-tools/foreman/`。
