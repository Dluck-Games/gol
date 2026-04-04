# Spec: 切除 Handoff 文档机械验证系统

**Date:** 2026-04-04
**Status:** Approved
**Scope:** `gol-tools/foreman/` — 删除 handoff 文档的 REQUIRED_SECTIONS 字符串验证链路

## Background

Foreman daemon 对每个 agent 产出的 handoff 文档执行 `validateRequiredSections()` 验证 — 精确匹配 H2 标题字符串。缺失任何必需章节时触发 `handoffValidationFailed` 警报，写入 TL 的 systemAlerts。

### 问题

| 指标 | 数据 |
|------|------|
| 误报率 | ~75%（8 次触发中 6 次内容完整但标题不精确匹配） |
| 造成的 harm | #193 因此 contribute to abandon；#194 浪费 3 轮纯文档 spawn；#226 多一轮无意义 rework |
| 信息增量 | ≈0（TL step 5 已全文评估，比字面量匹配更准确） |
| 防护矛盾 | daemon 有 bypass 逻辑强制 override 此类 rework，等于承认警报本身不该存在 |

根因：`content.includes(section)` 是 naive 子串匹配，不理解同义标题、角色差异、语义完整性。

## Decision

**方案 A — 纯删除。** 移除所有角色的 handoff 文档格式验证代码、alert 构造、bypass 逻辑和对应测试。

文档格式约束回归到 prompt 模板的"产出格式"定义（`implement.md` / `full-review.md` 等），TL 通过 step 5 全文评估做语义级质量判断。

## Changes

### 1. `lib/doc-manager.mjs`

- 删除 `REQUIRED_SECTIONS` 常量（L10-15）
- 删除 `validateRequiredSections()` 方法（L130-146）
- 其余不变

### 2. `lib/daemon-runtime-utils.mjs`

- 删除 `shouldTreatValidationAsWarning()`（L38-40）
- 删除 `reviewerDocIndicatesApproval()`（L42-52）
- 删除 `shouldBypassCoderReworkForDocWarning()`（L54-62）
- 其余 3 个函数保留不变

### 3. `foreman-daemon.mjs`

**Imports（L26-28）：** 删除 `shouldTreatValidationAsWarning`, `reviewerDocIndicatesApproval`, `shouldBypassCoderReworkForDocWarning` 的 import。

**Trigger 构造（L199-243）：** 简化为无条件 `agent_completed`：

```javascript
// Planner: 仅检测文档是否存在（非格式验证）
if (agentRole === 'planner') {
    const latestIterationDoc = this.#docs.readLatestPlannerIterationDoc(issueNumber);
    if (!latestDoc || !latestIterationDoc) {
        // 文件缺失 = 真实错误，保留
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
// 非 planner: 无条件通过
} else if (latestDoc) {
    trigger = { type: 'agent_completed', agent: agentRole, document: latestDoc.filename };
} else {
    trigger = { type: 'agent_completed', agent: agentRole, document: null };
}
```

**Alert 构造（L315-317）：** 删除 `if (trigger.handoffValidationFailed)` 块。

**Bypass 逻辑（L341-349）：** 删除 `if (shouldBypassCoderReworkForDocWarning...)` 块。

### 4. `prompts/tasks/tl/decision.md`

- 删除 L19-20 两条 handoff 反 rework 规则：
  - "如果 trigger / systemAlerts 表示只是 handoff 文档章节不完整..."
  - "只有当 reviewer/tester/planner 指出实质性缺陷..."

### 5. Tests

**`tests/doc-manager.test.mjs`：**
- 删除 `REQUIRED_SECTIONS` import（L8）
- 删除整个 `describe('validateRequiredSections', ...)` 块（L90-176，含 4 个 test case）

**`tests/daemon-runtime-utils.test.mjs`：**
- 删除 3 个函数 import（L9-11）
- 删除对应 3 个 test case（L85-114）

## Preserved (unchanged)

| Item | Reason |
|------|--------|
| Planner 文档不存在的硬失败检测 | 文件缺失 ≠ 格式不对，是真实错误 |
| 所有角色 `latestDoc === null` fallback | 同上 |
| TL decision prompt step 5 ("Read 全文评估") | 替代语义级质量门禁 |
| Coder/reviewer/tester/planner task prompt 中的产出格式定义 | 格式标准仍由 prompt 定义 |
| DocManager 其余所有方法 | CRUD、序列管理、orchestration 不受影响 |

## Verification

1. `node --test foreman/tests/` 全部通过（测试数量减少 ~7 个）
2. daemon 启动无 import 错误
3. 手动确认：trigger 构造不再包含 `handoffValidationFailed` / `handoffMissingSections`
