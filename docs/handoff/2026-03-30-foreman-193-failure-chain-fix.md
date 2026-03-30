# Handoff: Foreman #193 失败链修复

Date: 2026-03-30
Session focus: 修复 foreman 重构后 #193 八轮失败的问题，涵盖四个根因

## User Requests (Verbatim)

- "请修复因 foreman 重构带来的新问题：[Pasted ~67 lines of complete failure chain for #193]"
- "重新部署foreman。然后把刚刚出错的issue给恢复成初始状态，重新让foreman拾取。我将再次做端到端验证。"

## Goal

确认 #193 端到端验证通过（当前正在进行中，daemon 已拾取 #193 并进入 TL 决策阶段）。

## Work Completed

- 分析了 #193 的完整八轮失败链条，识别出四个根因（P0×1 + P1）
- **根因 1（致命）**：lifecycle 设计 bug — reviewer 前无 PR。P0+P1 重构将 coder 的 git/GitHub 能力移除（commit 69a4eff + 5a4c38d），framework committer 只做 commit+push+CI，PR 创建只在 verify path 中，但 reviewer 在 verify 之前
- **根因 2（严重）**：isLegacyFormat 误判。initOrchestration() 不创建 decisions/ 目录，但 isLegacyFormat() 靠它判断格式，全新 issue 在第一次 decision 写入前永远被判为 legacy
- **根因 3（中等）**：TL 进程 abort（codebuddy 收到 abort 信号，可能是 timeout 或上游 API 中断）
- **根因 4（中等）**：launchd PATH / codebuddy ENOENT（确认 plist 已正确配置 PATH 和 source ~/.zshrc，实际 binary 存在于 /opt/homebrew/bin/codebuddy，未做改动）
- 实现了以下修复：
  - `gol-tools/foreman/lib/doc-manager.mjs` — initOrchestration() 立即创建 decisions/ 目录；readOrchestration() 缺失文件时返回空字符串而非抛错
  - `gol-tools/foreman/foreman-daemon.mjs` — 新增 #ensureTaskPR() 方法（idempotent：findPRForIssue → findOpenPR → createPR），在 coder 退出后 commit/push 成功时调用、在 reviewer/tester spawn 前调用；persisted pr_number 到 state via StateManager.updateTask()；清理了 dead #transitionToCancelled helper 和 CI trigger 类型噪声
  - `gol-tools/foreman/lib/state-manager.mjs` — 新增 updateTask(issueNumber, extra) 方法用于持久化 task 字段更新
  - 新增回归测试：split-file init、缺失 orchestration 读取、PR 持久化
- 提交推送 submodule → parent，验证全量 213 测试通过，LSP 诊断干净
- 重置 #193 为初始状态：从 dead_letter 移除、清理 docs/foreman/193/ 下所有残留文档、foreman:blocked → foreman:assign
- 重启 foreman daemon（PID 53457），确认日志显示 #193 被重新拾取并进入 TL 决策

## Current State

- foreman daemon 运行中（PID 62715），#193 已重新拾取（TL agent PID 62912）
- 全量测试通过：213 pass, 0 fail
- LSP 诊断：所有修改文件无 error/warning
- Parent repo 有未提交的 docs 变更（#193 残留 docs 被 git 追踪为 deleted，#196 有新迭代文档），这些是 foreman 运行时产生的文档，不需要手动处理

## 小插曲：TL 模型行为问题

第一次重置后 #193 再次失败，日志如下：
```
00:47:08 Created task #193
00:47:10 Spawning TL agent (glm-5.0-turbo-ioa, PID 53859)
00:50:51 TL exited (code=0) — no decision file written
00:50:52 TL exited without writing decision file
00:50:52 TL model glm-5.0-turbo-ioa failed without writing a decision (not rate-limited)
00:50:57 labels foreman:progress -> foreman:blocked
```

根因：TL agent (glm-5.0-turbo-ioa) 把 maxTurns=30 全花在读源码上（读了 gol_game_state.gd、gol_world.gd、world.gd、s_dead.gd、s_camera.gd 等），到 turn 上限就退出了，**从未写 decision 文件**。这不是我们修复的代码 bug——`tl-decision.md` 明确说"你不直接读代码"，但模型没遵守。

操作：二次重置 #193（从 dead_letter 移除、清理 docs、foreman:blocked → foreman:assign）、重启 daemon。

## Pending Tasks

- 等待 #193 端到端验证结果（第二次重置后正在进行）
- 如果 TL 模型继续不写 decision，可能需要考虑：降低 maxTurns 限制让模型更快收敛、或在 prompt 中更强地约束读代码行为、或换用更守规矩的模型

## Key Files

- `gol-tools/foreman/foreman-daemon.mjs` — 主 daemon：lifecycle 调度、#ensureTaskPR()、#spawnReviewer/#spawnTester PR 检查
- `gol-tools/foreman/lib/doc-manager.mjs` — 文档管理：isLegacyFormat()、initOrchestration()、readOrchestration()
- `gol-tools/foreman/lib/state-manager.mjs` — 原子状态：updateTask()、transition()、dead letter 管理
- `gol-tools/foreman/lib/tl-dispatcher.mjs` — TL agent 调度：legacy/split-file 决策解析
- `gol-tools/foreman/lib/github-sync.mjs` — gh CLI 封装：findPRForIssue()、findOpenPR()、createPR()
- `gol-tools/foreman/lib/process-manager.mjs` — child_process.spawn 封装，multi-client 支持
- `gol-tools/foreman/com.dluckdu.foreman-daemon.plist` — launchd 配置
- `gol-tools/foreman/tests/doc-manager.test.mjs` — DocManager 回归测试
- `gol-tools/foreman/tests/state-manager.test.mjs` — StateManager 回归测试
- `docs/superpowers/specs/2026-03-29-foreman-p0p1-refactor-design.md` — P0+P1 重构设计规范（PR 创建时机的权威来源）

## Important Decisions

- PR 创建放在 reviewer 之前而非 verify 之后。虽然设计规范说 PR 在 verify 中创建，但 reviewer 需要 PR number 来构建 prompt，所以将 PR ensure 逻辑放在 coder 退出后、reviewer spawn 前。verify 阶段的 create_pr 保留为 idempotent 兜底
- #ensureTaskPR() 使用三级查找：task.pr_number → findPRForIssue() → findOpenPR() + createPR()，全部 idempotent
- pr_number 通过 StateManager.updateTask() 持久化到 state.json，确保 daemon 重启后不丢失
- 未修改 launchd plist PATH（已确认 codebuddy 在 /opt/homebrew/bin/codebuddy，plist 已包含该路径）
- 未清理 dead letter 中的其他 item（#171 等），只处理了 #193

## Constraints

- "尽可能避免使用 oracle 和 deep 以及 unspecific-high 因为它们的模型额度几乎耗尽"
- "ALWAYS Push the submodule first, then update the main repo reference"
- "NEVER create game files (scripts/, assets/, scenes/) at this root"
- "NEVER run Godot from this directory"

## Context for Continuation

- foreman state.json 位于 `.foreman/state.json`（非 gol-tools/foreman 内）
- foreman docs 位于 `docs/foreman/{issue_number}/`
- foreman logs 位于 `logs/foreman/daemon-YYYYMMDD.log`
- 查看 daemon 实时日志：`tail -f logs/foreman/daemon-20260330.log`
- 查看 daemon 状态：`launchctl list | grep foreman`
- 重启 daemon：`launchctl kickstart -k gui/$(id -u)/com.dluckdu.foreman-daemon`
- #193 之前的 PR #221 已被关闭（ CLOSED 状态），所以 coder 完成后需要创建新 PR
- gol-project submodule 有 foreman/issue-193 分支（本地和远程都存在），新 coder 应该会复用或重建这个分支

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
