# Foreman Agent 权限约束分析报告

**日期**: 2026-04-03  
**作者**: Shiori (调查) + OpenClaw subagent (实验验证)  
**状态**: 待修复

---

## 问题描述

foreman daemon 在 spawn codebuddy agent 前，会将 `writePaths` / `readPaths` / `bashAllow` 写入 worktree 的 `.codebuddy/settings.local.json`，然后以 `--permission-mode bypassPermissions` 启动 codebuddy。

预期行为：agent 只能写入 `writePaths` 指定的目录。  
实际行为：路径约束完全无效，agent 可写任意路径。

---

## 实验验证

### 实验一：bypassPermissions vs default 模式对比

**测试环境**：`/tmp/test-perm-verify/`  
**settings.local.json**：
```json
{
  "permissions": {
    "allow": ["Read(**)", "Write(allowed_dir/**)", "Edit(allowed_dir/**)"],
    "deny": []
  }
}
```

| 模式 | forbidden_dir 写入 | allowed_dir 写入 |
|---|---|---|
| `bypassPermissions` | ✅ 成功（无视限制） | ✅ 成功 |
| `default` | ❌ 被拦截 | ✅ 成功 |

**结论**：`bypassPermissions` 会完全无视 `settings.local.json` 的 `permissions.allow/deny` 配置，路径约束在该模式下形同虚设。

---

### 实验二：default 模式下 Bash 工具绕过问题

在 `default` 模式下，仅设 `Write(forbidden/**)` deny：

- Write 工具写 forbidden 目录 → ❌ 被拦截
- Bash 工具 `echo > forbidden/file` → ✅ 绕过成功

**根因**：`permissions.deny` 里的规则按工具类型匹配，`Write()` 的 deny 不覆盖 `Bash` 工具，Bash 可以通过 shell 命令绕过文件写入限制。

---

### 实验三：default 模式可行方案验证

**变体 A**：显式 deny Bash 特定路径
```json
{
  "permissions": {
    "allow": ["Read(**)", "Write(allowed_dir/**)", "Edit(allowed_dir/**)", "Bash(*)"],
    "deny": ["Write(forbidden_dir/**)", "Edit(forbidden_dir/**)", "Bash(*forbidden_dir*)"]
  }
}
```
结果：✅ 不 ask、forbidden 被拦截（Write + Bash 双拦）

**变体 B**：白名单模式，不给 Bash 授权（推荐）
```json
{
  "permissions": {
    "allow": ["Read(**)", "Write(allowed_dir/**)", "Edit(allowed_dir/**)"],
    "deny": []
  }
}
```
结果：✅ 不 ask、forbidden 被拦截、Bash 默认被拒绝

---

## 当前 foreman 的影响

由于 `bypassPermissions` 无视路径约束，以下 foreman 的安全边界实际上均未生效：

| Agent | 预期写入范围 | 实际写入范围 |
|---|---|---|
| Planner | `docDir` 只读 | 无限制 |
| Coder | `scripts/` `tests/` `resources/` + `docDir` | 无限制 |
| Reviewer | `docDir` 只读 | 无限制 |
| Tester | `docDir` + `/tmp` | 无限制 |

已知影响：coder 在 issue #226 处理过程中多次修改了 `AGENTS.md`（管理仓库根目录文件），而不是游戏代码文件。虽然最终结果正确，但这些越界操作本应被拦截。

---

## 修复方案

### 推荐方案：改用 `default` 模式 + 白名单 permissions

**原则**：
- 启动参数改为 `--permission-mode default`
- `settings.local.json` 的 `allow` 列表精确列出允许的路径和工具
- 不给 `Bash` 通配 allow；需要 Bash 的 agent（coder/tester）改为逐条列出允许的脚本

**各 agent 配置示意**：

```js
// Planner（只读 + 写 docDir，无 Bash）
{
  allow: ["Read(**)", `Write(${docDir}/**)`, `Edit(${docDir}/**)`],
  deny: []
}

// Coder（写 scripts/tests/resources + docDir，Bash 只允许测试脚本）
{
  allow: [
    "Read(**)",
    `Write(${wsPath}/scripts/**)`, `Edit(${wsPath}/scripts/**)`,
    `Write(${wsPath}/tests/**)`,   `Edit(${wsPath}/tests/**)`,
    `Write(${wsPath}/resources/**)`, `Edit(${wsPath}/resources/**)`,
    `Write(${docDir}/**)`,         `Edit(${docDir}/**)`,
    `Bash(${coderRunTestsScript})`,
    `Bash(${coderRunTestsScript}:*)`,
  ],
  deny: []
}

// Reviewer / Tester（类似，按需调整）
```

**`#writeAgentSettings` 需同步修改**：从写 `pathConstraints` 对象改为直接写 `permissions.allow` 数组。

### 备选方案：OS 级沙箱

通过 macOS sandbox-exec 或 Docker 容器从文件系统层面隔离，不依赖 codebuddy 应用层权限，彻底解决绕过问题。成本较高，适合后期加固。

---

## 临时缓解措施（修复前）

1. **AGENTS.md 保护**：worktree 中的 `AGENTS.md` 已通过之前的修复（移除 WorkspaceManager 的 copy 逻辑）不再被覆盖——但 coder 仍可修改它，只是现在来自 gol-project 的正确版本
2. **Prompt 层约束**：在 coder prompt 中明确写"禁止修改 AGENTS.md、CLAUDE.md 等框架文件"
3. **Pre-commit hook**：在 gol-project 仓库加 hook，拒绝修改 AGENTS.md 的 commit

---

## 相关代码位置

| 文件 | 相关函数 | 行号（约） |
|---|---|---|
| `foreman/foreman-daemon.mjs` | `#writeAgentSettings` | ~1270 |
| `foreman/foreman-daemon.mjs` | `#spawnTracked` | ~1234 |
| `foreman/foreman-daemon.mjs` | `#spawnCoder` / `#spawnReviewer` 等 | ~490, ~547 |
| `foreman/lib/process-manager.mjs` | `spawn()` | - |

---

## 待办

- [ ] 修改 `#writeAgentSettings` 输出 `permissions.allow` 格式（而非 `pathConstraints`）
- [ ] 各 agent spawn 函数改用 `--permission-mode default`
- [ ] coder/tester 的 bashAllow 改为逐条 `Bash(script_path)` allow 条目
- [ ] 验证修改后 agent 正常运行（不卡死 ask）
- [ ] 可选：gol-project 加 pre-commit hook 保护 AGENTS.md
