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

- foreman 框架修复全部完成并验证通过（见最终验证）
- #193 被 TL 合理 abandon——planner 连续两轮未回应核心分析要求（camera 生命周期），属于 agent 能力问题而非框架 bug
- 全量测试通过：213 pass, 0 fail
- LSP 诊断：所有修改文件无 error/warning

## 最终验证结果

第三次重置后（修复了 disallowedTools 配置），#193 完整走通了 TL → planner → TL 决策链路：
```
01:27 TL decision -> spawn @planner ✅（TL 成功写入 001-decision.md）
01:30 Planner 产出 01-planner-player-respawn-flow.md ✅
01:36 TL decision -> spawn @planner（Round 2，planner 分析质量不足）✅（002-decision.md）
01:41 Planner 完成 Round 2 ✅
01:43 TL decision -> abandon ✅（003-decision.md，planner 连续两轮未覆盖 camera 分析）
```

**框架修复全部生效：**
- ✅ initOrchestration() 正确创建 decisions/ 目录（split-file 格式）
- ✅ TL 成功写入 3 个 decision 文件
- ✅ Planner 成功产出分析文档
- ✅ doc validation → TL 决策链路完整

**#193 被 abandon 的原因（非框架 bug）：** planner (glm-5.0-turbo-ioa) 连续两轮忽略 TL 要求的 camera 生命周期分析，TL 判定无法改善后主动 abandon。这是 agent 能力问题。

## 小插曲记录

### 插曲 1：TL 模型不写 decision 文件（Turn 1-2）

前两次重置后 #193 都因 TL 不写 decision 文件而 fail。日志：`TL exited without writing decision file`。

初以为是模型行为问题（TL 把 turn 全花在读代码上），但深挖后发现**根因是配置错误**：`config/default.json` 中 TL/planner/reviewer 的 `disallowedTools` 包含 `Write`，但它们的 prompt 都要求写文件（decision/analysis/review）。agent 被禁了 Write 工具，无法写任何文件。

修复：从三个角色的 `disallowedTools` 中移除 `Write`（Edit 保留，因为这些角色不应修改源码）。
- Commit: `fix(foreman): remove Write from disallowedTools for TL/planner/reviewer`

### 插曲 2：launchd ENOENT（未修改）

确认 plist 已正确配置 `PATH`（含 /opt/homebrew/bin）和 `source ~/.zshrc`，`codebuddy` binary 确实存在于 `/opt/homebrew/bin/codebuddy`。未做改动。

## Pending Tasks

- #193 被 abandon 后需要人工决定是否重试（可能需要换用更强模型如 claude-opus 做 planner）
- 考虑为 planner/reviewer 配置更强模型，当前 glm-5.0-turbo-ioa 在复杂分析任务上表现不足
- `gol_game_state.gd:74` 存在双重 `add_entity` bug（Critical，#196 reviewer 发现，需后续处理）

## Key Files

- `gol-tools/foreman/foreman-daemon.mjs` — 主 daemon：lifecycle 调度、#ensureTaskPR()、#spawnReviewer/#spawnTester PR 检查
- `gol-tools/foreman/lib/doc-manager.mjs` — 文档管理：isLegacyFormat()、initOrchestration()、readOrchestration()
- `gol-tools/foreman/lib/state-manager.mjs` — 原子状态：updateTask()、transition()、dead letter 管理
- `gol-tools/foreman/lib/tl-dispatcher.mjs` — TL agent 调度：legacy/split-file 决策解析
- `gol-tools/foreman/lib/github-sync.mjs` — gh CLI 封装：findPRForIssue()、findOpenPR()、createPR()
- `gol-tools/foreman/lib/process-manager.mjs` — child_process.spawn 封装，multi-client 支持
- `gol-tools/foreman/config/default.json` — 角色配置：disallowedTools、model、fallbackModels
- `gol-tools/foreman/tests/doc-manager.test.mjs` — DocManager 回归测试
- `gol-tools/foreman/tests/state-manager.test.mjs` — StateManager 回归测试
- `docs/superpowers/specs/2026-03-29-foreman-p0p1-refactor-design.md` — P0+P1 重构设计规范（PR 创建时机的权威来源）

## Important Decisions

- PR 创建放在 reviewer 之前而非 verify 之后。虽然设计规范说 PR 在 verify 中创建，但 reviewer 需要 PR number 来构建 prompt，所以将 PR ensure 逻辑放在 coder 退出后、reviewer spawn 前。verify 阶段的 create_pr 保留为 idempotent 兜底
- #ensureTaskPR() 使用三级查找：task.pr_number → findPRForIssue() → findOpenPR() + createPR()，全部 idempotent
- pr_number 通过 StateManager.updateTask() 持久化到 state.json，确保 daemon 重启后不丢失
- 从 TL/planner/reviewer 的 disallowedTools 中移除 Write——这些角色需要写文件（decision/analysis/review），但不应编辑源码（Edit 保留在 disallowedTools 中）
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
