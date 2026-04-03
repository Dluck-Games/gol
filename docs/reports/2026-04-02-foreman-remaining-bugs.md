# Foreman 遗留 Bug 分析报告

> **日期**: 2026-04-02
> **范围**: foreman daemon (`gol-tools/foreman/`)
> **触发**: foreman prompt architecture v4 code review 后的遗留项分析
> **状态**: 仅分析，未修复

---

## 概览

在 foreman prompt architecture v4 的 code review 和路径约束修复完成后，识别出 3 个遗留问题。按严重度排序：

| # | 问题 | 严重度 | 根因类型 | 修复复杂度 |
|---|------|--------|---------|-----------|
| 1 | 并发重复处理同一 issue | HIGH | 竞态条件 | 中 |
| 2 | Worktree 销毁后仍 spawn 进程 | MEDIUM | 状态管理 | 低 |
| 3 | doc-manager.test.mjs 测试失败 | LOW | 过时引用 | 低 |

---

## Bug #1: 并发重复处理同一 issue

### 症状

Issue #193 被两个 coder 同时处理（PID 20996 和 PID 21038），分别运行在不同 worktree 上但都提交到同一 `foreman/issue-193` 分支，导致分支历史混乱。

### 根因

两个独立代码路径可以**顺序地**（非并发地）为同一 issue 触发 `#requestTLDecision`。`#decisionPending` 守卫只防止**同时**的调用，不防止有时间差的顺序调用。

### 竞态时序

```
T1: coder 退出 → child.on('exit') → #onProcessExit
T2:   → #requestTLDecision → #decisionPending.add("193") → spawn TL#1
T3: 30s 定时器 #runProcessCheck 触发 → 发现 PID 已死 → void #onProcessExit (fire-and-forget)
T4: TL#1 完成 → #executeTLDecision → spawn coder#1 → #decisionPending.delete("193")
T5: 第二个 #onProcessExit 恢复 → #decisionPending.has("193") = FALSE → 通过守卫
T6: → #requestTLDecision → spawn TL#2 → TL#2 也决定 spawn coder → coder#2
结果: 两个 coder 同时运行在两个 worktree 上，都提交到同一分支
```

### 关键代码位置

| 文件 | 行号 | 代码 | 问题 |
|------|------|------|------|
| `foreman-daemon.mjs` | 893 | `void this.#onProcessExit(task.issue_number, 1, null)` | fire-and-forget，不 await |
| `foreman-daemon.mjs` | 907 | `void this.#onProcessExit(task.issue_number, 1, 'SIGTERM')` | rate limit kill 后也 fire-and-forget |
| `foreman-daemon.mjs` | 918 | `void this.#onProcessExit(task.issue_number, 1, 'SIGTERM')` | stale kill 后也 fire-and-forget |
| `foreman-daemon.mjs` | 130 | `task.pid = null` | 在 async 链中间赋值，存在窗口 |
| `foreman-daemon.mjs` | 208-213 | `#decisionPending` 检查 | 只防并发，不防顺序重复 |

### 现有守卫分析

| 守卫 | 位置 | 为什么不够 |
|------|------|-----------|
| `#decisionPending` | daemon:55, 208-213 | 只防并发调用；T3 的 void 调用在 T4 清除后才到达检查点 |
| `#syncRunning` | daemon:53, 807 | 只保护 `#runGithubSync()` 互斥，不保护 process exit |
| `#recentlyCompleted` | daemon:56, 1108-1126 | 5 分钟 TTL，只检查 GitHub sync 的 orphan 路径 |
| `createTask` 重复检查 | state-manager:80-83 | 防重复创建 task，不防重复处理 |
| `maxActiveAgents=1` | config:default.json | 在 `#runGithubSync` 检查，不影响已存在的 task 被重复处理 |
| ProcessManager.kill() PID suppression | process-manager:164-168 | 只适用于通过 kill() 终止的进程，不适用于自然退出 |

### 修复方向

**方案 A（最简）**: `#runProcessCheck()` 中不再调用 `void #onProcessExit()`，改为只设置 `task.pid = null`，让 `child.on('exit')` 回调作为 exit handling 的唯一入口。

```js
// 改前 (line 893)
void this.#onProcessExit(task.issue_number, 1, null);

// 改后
task.pid = null;
```

**方案 B（加固）**: 添加 `#processingExit = new Set()`，覆盖从 "exit 检测" 到 "新 agent PID 记录" 的完整管道。

**方案 C（根治）**: 给 `#onProcessExit` 加 per-issue mutex，确保同一 issue 的 exit → decision → spawn 是原子的。

### 推荐方案

方案 A — 最小改动，最大效果。`#runProcessCheck` 的职责应该是"检测并终止不健康进程"，而非"执行完整的退出处理管道"。

---

## Bug #2: Worktree 销毁后仍 spawn 进程

### 症状

日志显示 worktree 在 14:33:59 被销毁，随后立即有进程以已销毁路径为 cwd 被 spawn。

### 根因

`task.workspace` 在 worktree 销毁后**从不被清空**。`#respawnCurrentAgent` 直接使用 `#spawnContext` 中存储的 `cwd`，不验证路径有效性，也不经过 `WorkspaceManager.getOrCreate()` 的路径校验。

### 触发路径分析

**理论路径（已被守卫阻断）**:

```
1. Coder 被 rate limit → #onProcessExit → #handleRateLimitRetry → 设置 setTimeout backoff
2. backoff 期间，另一个流程触发 worktree 销毁
3. setTimeout 回调 → #respawnCurrentAgent → ctx.cwd 已失效
```

实际上 `#handleAbandon` 在 line 798 清除了 `#spawnContext`，所以 setTimeout 回调中 `#spawnContext.get(key)` 返回 `null`，`#respawnCurrentAgent` 在 line 1214 安全返回。**这条路径已被守卫。**

**更可能的真实触发**: 两个 issue 的处理交错时，`cleanOrphans()` 在错误的时机销毁了正在使用的 worktree，或者 abandon 流程中 cleanup step 执行后、task 状态尚未完全转换时，另一个异步流程读取了旧的 `task.workspace`。

### 关键代码位置

| 文件 | 行号 | 代码 | 问题 |
|------|------|------|------|
| `foreman-daemon.mjs` | 1220 | `this.#processes.spawn(issueNumber, ctx.cwd, ...)` | 直接用存储的 cwd，不验证存在性 |
| `foreman-daemon.mjs` | 1196-1203 | `setTimeout(() => { #respawnCurrentAgent(...) }, ...)` | backoff 不跟踪/不取消 |
| `foreman-daemon.mjs` | 711-712 | `this.#workspaces.destroy(ctx.workspace)` | 销毁后不清空 `task.workspace` |
| `foreman-daemon.mjs` | 796-798 | `#handleAbandon` 清除 context | 清除了 spawnContext 但不取消已排队的 setTimeout |
| `workspace-manager.mjs` | 163-176 | `getOrCreate()` | 会验证路径并重建，但 `#respawnCurrentAgent` 不调用它 |
| `state-manager.mjs` | 151-163 | `abandon()` | 移入 dead_letter，保留 workspace 字段 |

### 修复方向

1. **`#respawnCurrentAgent` 加路径校验**: `existsSync(ctx.cwd)` 失败时 fallback 到 `getOrCreate`
2. **cleanup 后清空 workspace**: `#executeStep` 的 `case 'cleanup'` 执行后设置 `task.workspace = null`
3. **跟踪 backoff setTimeout**: 存储 timeout ID，在 abandon/cancel 时 `clearTimeout`

### 推荐方案

三项全部实施，作为防御性加固。工作量小，但能彻底消除此类风险。

---

## Bug #3: doc-manager.test.mjs 测试失败

### 症状

```
✖ keeps worker prompt headings aligned with validator expectations
  Error: ENOENT: no such file or directory, open '.../prompts/planner-task.md'
ℹ tests 22 | pass 21 | fail 1
```

### 根因

测试硬编码了 4 个在 v4 迁移中已删除的旧 flat template 路径：

```js
// doc-manager.test.mjs:123-128
const promptFiles = {
    planner: join(promptsDir, 'planner-task.md'),   // 已删除
    coder:   join(promptsDir, 'coder-task.md'),     // 已删除
    reviewer: join(promptsDir, 'reviewer-task.md'),  // 已删除
    tester:  join(promptsDir, 'tester-task.md'),    // 已删除
};
```

### 影响范围

- `doc-manager.mjs` 生产代码 **完全干净** — `validateRequiredSections()` 接受任意文件路径参数
- `prompt-builder.mjs` **完全干净** — 已迁移到 Nunjucks 分层架构
- `gol-tools/AGENTS.md` 目录结构描述 **过时** — 仍列出旧 flat template 文件

### 修复方向

1. 更新测试的 `promptFiles` 指向新的分层模板文件（`entry/`, `tasks/`）
2. 同步更新 `gol-tools/AGENTS.md` 的目录结构描述

---

## 关联性分析

Bug #1 和 Bug #2 存在关联：

- Bug #1 的修复（将 `#runProcessCheck` 的 `void #onProcessExit` 改为只清 `task.pid`）会间接降低 Bug #2 的触发概率，因为减少了多余的 exit 处理路径
- 但 Bug #2 的防御性加固仍应独立实施，因为 `#respawnCurrentAgent` 的 cwd 不校验问题不依赖于竞态条件

## 优先级

| 优先级 | Bug | 理由 |
|--------|-----|------|
| **P0** | #1 并发重复处理 | 可直接导致生产环境数据损坏（分支历史混乱） |
| **P1** | #2 Worktree spawn | 防御性风险，当前守卫可能覆盖多数场景但不够健壮 |
| **P2** | #3 测试失败 | 不影响生产，但会降低测试套件的可信度 |
