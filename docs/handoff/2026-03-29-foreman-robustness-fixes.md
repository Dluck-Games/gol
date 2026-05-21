# Handoff: Foreman Robustness Fixes

Date: 2026-03-29
Session focus: 排查并修复 foreman daemon 多个流程缺陷 — 限流处理、CI 门控、worktree 清理、模型分散、禁止 agent 关闭 issue/PR

## User Requests (Verbatim)

- "请帮我排查，#193 issue 安排给 foreman 自动化修复后，为何没有生成对应 PR 却报告说通过了？"
- "当触发限流时，使用 kimi-k2.5-ioa 作为 fallback，第二 fallback 是 minimax m2.7。"
- "同时再加个设计，限制 foreman 的流量，不允许同时进行多个 issue 的开发。"
- "还有个问题，197 issue 给出了 CI 失败的 PR，但被标记为 done 了。"
- "限流可以从 4-8-16-32-64 五个档位去重试，最多 64 分钟。目前所有模型都是 codebuddy client 的模型。"
- "tester 的 fallback 只有 minimax"
- "coder 的也只有 minimax"
- "219 issue 的 PR 和 issue 单都被 foreman 自动关闭了，关闭任何单据的行为必须由人工处理"

## Goal

Foreman daemon 现在应该能稳健处理限流、CI 失败、worktree 冲突，且不会自行关闭 issue 或 PR。持续观察 #193 和 #196 的自动化处理是否正常。

## Work Completed

### Bug 1: #193 无 PR 却标记 done
- **根因**: `#handleVerify()` 没有检查 PR 是否存在就直接标记 done
- **修复**: 在 `#handleVerify()` 添加 PR 存在性检查，无 PR 则 fallback 到 abandon

### Bug 2: #197 CI 失败却标记 done
- **根因**: `#handleVerify()` 没有检查 GitHub Actions CI 状态
- **修复**: 添加 `getPRChecks()` 到 `github-sync.mjs`，在 `#handleVerify()` 添加 CI 门控，CI 未通过时触发 TL 重新调度

### Bug 3: TL 限流导致 abandon
- **根因**: TL agent 遇到 429 后 session 崩溃，无 Decision 写入，`parseLatestDecision` 默认返回 abandon
- **修复**: `tl-dispatcher.mjs` 重写为 fallback 模型链 + 指数退避（4-8-16-32-64 分钟）

### Bug 4: 多 issue 并发导致限流
- **修复**: 添加 `maxActiveAgents: 1` 配置 + `#countActiveAgents()` 并发守卫 + label hygiene（progress → assign 降级）

### Bug 5: git worktree "already used" 错误
- **根因**: 旧 worktree 目录被 `rm -rf` 但 git 元数据未清理
- **修复**: `workspace-manager.mjs` 的 `create()` 方法开头添加 `git worktree prune`

### Feature: 每角色模型分散 + 通用限流重试
- **设计**: 将不同模型分配给不同角色，分散 API 压力
- **模型分配**: TL/planner/reviewer=glm, coder/tester=kimi
- **Fallback 链**: 每个角色独立 fallback（TL: kimi→minimax, coder: minimax, tester: minimax 等）
- **通用重试**: daemon 的 `#onProcessExit` 检测限流后自动 fallback → 退避（4-8-16-32-64 min）
- **实现**: `#spawnTracked()` 存储 spawn 上下文，`#handleRateLimitRetry()` 管理重试状态

### Bug 6: TL agent 自行关闭 issue 和 PR
- **根因**: TL agent 有 Bash 权限，prompt 说"你是唯一和 GitHub 交互的角色"被理解为可直接用 `gh` CLI
- **修复**:
  - TL prompt: 明确禁止 `gh issue close`/`gh pr close`/`gh issue comment`/`gh issue edit`
  - Coder prompt: `Closes #` → `Refs #`（防止合并时 GitHub 自动关闭 issue），明确允许/禁止的 gh 命令
  - 所有 agent prompts: 添加禁止关闭 issue/PR 的显式规则

### Bug 7: `#handleVerify` re-entrancy
- **根因**: `#handleVerify` 在 `#decisionPending` guard 内被调用，再次调用 `#requestTLDecision` 会被 guard 阻止
- **修复**: CI 门控触发重新调度前先 `this.#decisionPending.delete()`

## Current State

- Daemon 运行中 (PID 91579)，使用新代码
- #193: `foreman:assign`，等待 daemon 拾取（在 dead letter 中需要被 revive）
- #196: `foreman:assign`，PR #219 已重新打开，等待 daemon 拾取
- #197: `foreman:done`，PR #220 已合并（用户手动合并）
- #200: 用户另外处理
- #214: 之前成功完成

## Pending Tasks

- 观察 #193 和 #196 是否能在新代码下正常完成全流程
- #193 和 #200 仍在 dead letter 中，需要 `foreman:assign` 标签触发 revive
- 如果 TL agent 仍然尝试 `gh` 操作，可能需要将 Bash 从 TL 的工具中移除（但 TL 需要 Bash 写 orchestration.md，因为 Edit/Write 被禁用）

## Key Files

- `gol-tools/foreman/foreman-daemon.mjs` — 主 daemon：添加了 PR 门控、CI 门控、并发限制、label hygiene、通用限流重试
- `gol-tools/foreman/lib/tl-dispatcher.mjs` — TL 调度器：fallback 模型链 + 指数退避
- `gol-tools/foreman/lib/github-sync.mjs` — GitHub API 封装：新增 `getPRChecks()`
- `gol-tools/foreman/lib/workspace-manager.mjs` — Worktree 管理：create() 前自动 prune
- `gol-tools/foreman/config/default.json` — 配置：每角色模型分配、fallbackModels、retryBackoffMinutes
- `gol-tools/foreman/lib/config-utils.mjs` — 配置工具：移除旧 rate_limited fallback 机制
- `gol-tools/foreman/prompts/tl-decision.md` — TL prompt：禁止直接 GitHub 操作
- `gol-tools/foreman/prompts/coder-task.md` — Coder prompt：Refs 替代 Closes，明确 gh 权限
- `gol-tools/foreman/prompts/reviewer-task.md` — Reviewer prompt：禁止 GitHub 写操作
- `gol-tools/foreman/prompts/tester-task.md` — Tester prompt：禁止 GitHub 写操作

## Important Decisions

- **模型分散策略**: glm 给轻量决策角色（TL/planner/reviewer），kimi 给重量实现角色（coder/tester），minimax 作为通用 fallback
- **退避档位 4-8-16-32-64 分钟**: 用户指定，最长等待 64 分钟后放弃
- **`Refs #` 替代 `Closes #`**: 防止 PR 合并时 GitHub 自动关闭 issue，issue 关闭权留给人工
- **Daemon 侧重试 vs Agent 侧重试**: 选择在 daemon 的 `#onProcessExit` 中处理重试，利用 `#spawnContext` 存储的上下文直接 respawn，避免重走 TL 决策流程
- **TL 保留 Bash 权限**: TL 需要 Bash 来追加 orchestration.md（因为 Edit/Write 被禁），通过 prompt 约束而非工具禁用来防止滥用

## Constraints

- "关闭任何单据的行为必须由人工处理"
- "tester 的 fallback 只有 minimax"
- "coder 的也只有 minimax"
- "目前所有模型都是 codebuddy client 的模型"
- `maxActiveAgents: 1` — 同一时间只处理一个 issue

## Context for Continuation

- `gh pr checks` 返回的 JSON 使用 `bucket` 字段（pass/fail/pending），不是 `conclusion`
- `#decisionPending` Set 是 re-entrancy guard，在 `#handleVerify` 中触发重新调度前必须先 delete
- `#retryState` 和 `#spawnContext` 是纯内存状态，daemon 重启后丢失（但这是可接受的，因为重启后 orphan recovery 会处理）
- 旧的 `defaults.fallback` / `task.last_failure_reason` 机制已移除，被 `fallbackModels` + daemon 重试系统替代
- 如果未来 TL agent 仍然尝试 `gh issue close`，终极方案是给 TL 重新启用 Edit/Write（仅限 orchestration.md 路径）并禁用 Bash

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
