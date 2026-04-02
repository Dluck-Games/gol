# Handoff: Foreman 调试 & Issue #226 分析
**日期**: 2026-04-02  
**时间段**: 昨晚 ~ 上午 09:20  
**状态**: 进行中，需继续分析

---

## 一、今天干了什么（按时间顺序）

### 1. 修复两个 Foreman daemon bug（commit 3c4a03c）

**Bug 1：PID 单例锁缺失**  
- 根因：launchd keep-alive 在 crash 后自动重启，但旧代码没有单例锁，导致多个 daemon 并发存活
- 修复：启动时写 `/tmp/foreman-daemon.pid`，检测同 PID 进程存活则退出；SIGTERM/SIGINT 时 releaseSingletonLock() 清理 PID 文件

**Bug 2：blocked 路径未清除 foreman:done 标签**  
- 根因：issue 同时出现 `foreman:done` + `foreman:blocked` 标签，产生矛盾状态
- 修复：`label_swap` case 内，切到 blocked/cancelled 时额外 remove 掉已存在的 doneLabel

**Commit**: `3c4a03c`，已推送到 `Dluck-Games/gol-tools` main 分支

---

### 2. 手动清理遗留状态

- Issue #193 标签异常（done + blocked 并存）→ 手动重置为 `foreman:assign`
- state.json 里两个卡死的 #193 pendingOps（`verify_193_*`）→ 反复清理（坑：运行中的 daemon 持有内存状态，改文件无效，必须在 SIGTERM 后、launchd 重启前的窗口期写入）
- 教训：**清 state.json 的正确时序是 kill → 等 pid 文件消失 → 写文件 → launchd 自动拉起**

---

### 3. foreman-ctl 新增 reset 和 reload 命令（PR #6，已合入 main）

**`foreman-ctl reset <issueNumber>`**  
- 清 state.json 里该 issue 的 pendingOps + task
- GitHub 标签重置为 `foreman:assign`（移除所有 `foreman:*`）
- 如果 daemon 在跑，发 SIGUSR1 触发 sync

**`foreman-ctl reload`**  
- SIGTERM → 等 pid 文件消失（最多 10s）→ spawn 新 daemon → 等新 pid 文件出现
- 解决"改了代码要立刻生效"的需求

**已同步到 foreman OpenClaw skill**（~/.openclaw/workspace/skills/foreman/SKILL.md）

---

### 4. Issue #226 连续失败调查

**背景**: #226「元素子弹添加 VFX 特效」，被 Foreman 接单后 coder 连续 3 次失败，最终 TL decision 005 abandon，标签变为 `foreman:blocked`

**失败时间线**:
| 决策 | 结果 | 现象 |
|------|------|------|
| Decision 002 | orphan | coder 进程启动，完全无输出 |
| Decision 003 | orphan | 同上 |
| Decision 004 | 错误修改 | 只改了 AGENTS.md/CLAUDE.md，未建分支，commit 在 detached HEAD，push 失败 |

**OC systematic-debug 分析结论**（`docs/foreman/226/debug-report.md`）:  
主要根因定为"工作目录路径混淆"——coder 在管理仓库根（`ws_.../`）操作，而非 `gol-project/` 子模块。

**Shiori 的补充质疑**:  
Decision 002/003 是 orphan（完全没输出），和 decision 004 的"做错了地方"是两种不同表现。报告把它们归成同一根因可能不准确。orphan 的真实原因（API 超时？模型问题？prompt 太长？）尚未深入验证。

---

## 二、当前状态

| 事项 | 状态 |
|------|------|
| daemon 单例锁 | ✅ 已修复，PID 95966 在跑 |
| #193 状态清理 | ✅ 已重置，待 foreman 处理（人工判断可能不需要重处理） |
| foreman-ctl reset/reload | ✅ PR #6 已合入 main |
| Issue #226 | ⚠️ foreman:blocked，根因分析初稿完成，仍有疑点 |
| Issue #195（测试 issue） | 🟡 foreman:assign，等待 daemon 拾取 |

---

## 三、遗留问题 & 建议后续方向

### 高优先级

1. **#226 orphan 根因未确认**  
   Decision 002/003 的 orphan 是否和 004 是同一个根因？建议检查：
   - coder 的 prompt 是否过长导致模型无响应
   - kimi-k2.5-ioa 模型在特定 prompt 结构下是否有已知问题
   - daemon 是否有超时机制让 orphan 的 coder 没有写任何文件就退出

2. **`gh pr create --json` 不支持的 bug**  
   现有代码里 `gh pr create` 带了 `--json` flag，但这个版本的 gh CLI 不支持，导致 create_pr pendingOp 永远失败重试。需要修复 `github-sync.mjs` 里的 PR 创建逻辑。

3. **#226 是否需要重新处理**  
   Planner 方案（`docs/foreman/226/iterations/01-planner-bullet-vfx-analysis.md`）质量没问题，可以直接拿来用。建议：
   - 修复工作目录路径问题后，用 `foreman-ctl reset 226` 重试
   - 或者直接人工实现（方案文档已完整）

### 低优先级

4. foreman-ctl reset 命令目前对"运行中 daemon 内存状态"无效（因为没有让 daemon reload state），实际上应该配合 reload 一起用。考虑 reset 命令内部自动触发 reload，或者文档里说清楚。

---

## 四、关键文件路径

```
gol-tools/foreman/foreman-daemon.mjs          # daemon 主体
gol-tools/foreman/bin/foreman-ctl.mjs         # 控制命令
gol-tools/foreman/lib/github-sync.mjs         # GitHub 操作（含 gh pr create bug）
docs/foreman/226/iterations/01-planner-*.md   # #226 planner 方案（质量可用）
docs/foreman/226/decisions/001-005.md         # #226 全部 TL 决策记录
docs/foreman/226/debug-report.md              # OC 调试报告
logs/foreman/daemon-20260402.log              # 今天的 daemon 日志
/tmp/foreman-daemon.pid                       # 当前 daemon PID 文件
```
