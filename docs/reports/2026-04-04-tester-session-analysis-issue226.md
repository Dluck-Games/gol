# Foreman Tester 会话分析报告 — Issue #226 E2E 验收

**日期**: 2026-04-04
**分析对象**: `logs/foreman/issues/issue-226/tester.log`
**会话时长**: 14:58:22 → 15:00:34（~2 分钟）
**模型**: glm-5.0-turbo-ioa
**Turns**: 92（含工具调用往返）
**Token 消耗**: 1,589,834 input / 4,747 output（input/output 比 335:1）

---

## 一、概述

本次分析基于 Issue #226（元素子弹 VFX 特效）Foreman pipeline 中 tester 阶段的完整 JSONL 会话记录。Tester 在 E2E 验收过程中遭遇一系列权限、环境和 prompt 层面的问题，导致 **E2E 测试完全降级为静态代码分析**，没有任何运行时验证发生。

---

## 二、问题清单（按严重程度）

### P0 — 权限系统半途失效：Bash 和 Read 被拒绝后无法恢复

**严重程度**: 🔴 Critical

**现象**: Tester 前 6 次 Bash 调用全部成功，但从第 7 次开始，**所有 Bash 和 Read 调用被永久拒绝**，直到会话结束。

**时间线**:

| 时间 | 调用 | 结果 | 行号 |
|------|------|------|------|
| 14:58:47 | `Bash(tester-start-godot.sh ...)` | ✅ 成功 | 31 |
| 14:58:49 | `Bash(sleep 12 && tester-ai-debug.sh get entity_count)` | ✅ 成功（但超时） | 33 |
| 14:59:21 | `Bash(tail -30 /tmp/godot_e2e.log)` | ❌ PermissionDenied | 36 |
| 14:59:23 | `Bash(tail -30 /tmp/godot_e2e.log)` retry | ❌ PermissionDenied | 38-39 |
| 14:59:28-33 | `Bash(ls addons/)` × 2 | ❌ PermissionDenied | 43, 48 |
| 14:59:39-42 | `Bash(pkill Godot)` × 3 | ❌ PermissionDenied | 55-60 |
| 14:59:44 | `Read(tester-start-godot.sh)` × 3 | ❌ PermissionDenied | 62-67 |
| 14:59:49 | `Bash(pkill Godot)` | ❌ PermissionDenied | 69 |

**根因分析**:

1. **Bash 白名单过窄**: tester 的 `bashAllow` 只包含 3 个脚本的精确路径：
   - `tester-start-godot.sh`
   - `tester-ai-debug.sh`
   - `tester-cleanup.sh`

   通过 `expandBashAllow` 展开为 `command` + `command:*` 两种模式。但 tester 自行决定调用的 `tail`, `ls`, `pkill`, `sleep` 等命令**不在白名单中**，被 `--permission-mode default` 自动拒绝。

2. **Read 路径范围不足**: tester 的 `readPaths` 配置为 `[worktree, docDir, '/tmp']`。Tester 在第 62 行尝试读取 `gol-tools/foreman/bin/tester-start-godot.sh`，这个路径**不在 readPaths 范围内**，Read 也被拒绝。

3. **第一个 Bash 为什么成功？**: Prompt 模板中明确指示调用 `tester-start-godot.sh`，这个精确路径在白名单中。后续 `tail`, `pkill` 是 tester 自行决定的命令，不在白名单。

4. **无法清理**: `tester-cleanup.sh` 虽在白名单中，但 tester 因连续 Bash 拒绝而放弃了所有 Bash 调用尝试。

**影响**: E2E 测试完全降级为静态代码分析，Godot 僵尸进程（PID 22789）残留。

---

### P1 — 模型不遵循指令反复重试被拒操作

**严重程度**: 🟠 High

**现象**: Bash 被拒后，tester **连续 5 次重试**相同或类似的 Bash 命令，每次收到相同的 `PermissionDeniedError`，消耗约 30 秒和大量 token。

| 行号 | 尝试 | 变化 | 结果 |
|------|------|------|------|
| 55 | `pkill -f "Godot.*headless"` | 原始 | ❌ |
| 57 | 完全相同命令 | 无 | ❌ |
| 59 | `pkill -f "Godot"` | 去掉 headless | ❌ |
| 69 | `pkill -f "Godot" 2>/dev/null \|\| true` | 加错误抑制 | ❌ |

**问题**: CodeBuddy 的错误信息明确说了"Permission to use Bash has been denied"和"you should only try to work around this restriction in reasonable ways"，但模型没有从错误中学习。Read 被拒后也连续发了 3 个并行 Read（行 62-64），全部被拒。

---

### P2 — E2E 验收名不副实：实际零运行时验证

**严重程度**: 🟠 High

**现象**: Tester 产出报告声称"E2E 验收 pass"，但实际验证情况：

| 验证要素 | 状态 | 说明 |
|----------|------|------|
| 游戏运行 | ❌ | Godot 启动但 AI Debug Bridge 不可用 |
| 运行时检查 | ❌ | 无任何诊断脚本执行 |
| 截图 | ❌ | 报告明确写了"无法获取运行时截图" |
| AI Debug Bridge 交互 | ❌ | 只有 1 次 `get entity_count` 超时 |

**实际做了什么**: 读了 4 个源码文件 + 2 个审查报告 → 基于代码静态分析 + reviewer 报告信任链 → 直接写 `pass`。

**问题**: 这不是 E2E 测试，而是代码审查的二次确认。TL 和 downstream verify 信任了 `pass` 结论，但该结论没有运行时证据支撑。

---

### P3 — 权限拒绝未被正确记录和上报

**严重程度**: 🟡 Medium

**现象**: tester.log 最终 `type: "result"` 中 `permission_denials: []` 为空数组，但会话中实际发生了 **≥10 次权限拒绝**（Bash × 7+, Read × 3）。

**影响**: Foreman daemon 无法通过 process exit 结果检测到权限问题，无法触发 retry 或 fallback 机制，问题在报告层面不可见。

---

### P4 — Prompt 模板缺少降级/失败处理指导

**严重程度**: 🟡 Medium

**现象**: `e2e-acceptance.md` 模板只描述了正常流程（启动游戏 → 验证调试桥 → 执行测试 → 截图 → 清理），**没有任何 fallback 指导**：

- AI Debug Bridge 不可用怎么办？
- Bash 权限不够怎么办？
- 降级为静态分析时，产出格式应该怎么标注？

**结果**: Tester 自行决定降级为静态分析并直接给 `pass`。Prompt 缺少约束，理论上 tester 应该报告"环境不可用，无法完成 E2E 验收"。

---

### P5 — Read 路径范围与 Prompt 指令矛盾

**严重程度**: 🟡 Medium

**现象**: Prompt 模板告诉 tester "运行 `${repoRoot}/gol-tools/foreman/bin/tester-start-godot.sh`"，但 `readPaths` 配置为 `[worktree, docDir, '/tmp']`，不包含 `gol-tools/` 路径。

```
prompt 指令: 运行 ${repoRoot}/gol-tools/foreman/bin/tester-start-godot.sh
readPaths:   [worktree, docDir, '/tmp']  ← 不包含 gol-tools/
```

Tester 无法读取它被告知要执行的脚本，也无法 `tail /tmp/godot_e2e.log`（Bash 被拒）。

---

### P6 — Godot 僵尸进程未清理

**严重程度**: 🟡 Medium

**现象**: 行 31 启动 Godot（PID 22789）后，AI Debug Bridge 超时，tester 无法执行 `tester-cleanup.sh`，会话结束时进程仍在运行。Tester 最后一次 `pkill` 尝试也被权限拒绝。Daemon 的退出回调没有进程清理逻辑。

---

### P7 — Token 浪费严重

**严重程度**: 🟢 Low

**现象**: 92 turns，1,589,834 input tokens / 4,747 output tokens。

- **input/output 比 335:1** — 大部分 token 消耗在反复传递完整上下文（包含工具结果中的完整源码文件）
- 权限拒绝循环（行 36-70）消耗约 35 轮，产出为零
- 源码文件内容在 tool_result 中被多次完整传递

---

## 三、因果关系

```
P5 (Read 路径不足) + Bash 白名单过窄
  → P0 (权限半途失效)
    → P1 (模型盲目重试)     ← token 浪费
    → P6 (Godot 僵尸进程)
    → P2 (E2E 名不副实)     ← 最严重后果
      → 无运行时验证，pass 结论不可靠

P4 (prompt 无降级指导)
  → P2 (tester 自行降级为 pass)

P3 (权限拒绝不上报)
  → daemon 盲区，无法触发修复机制
```

**根因**: Tester 的权限系统（Bash 白名单 + Read 路径范围）与其实际工作流需求不匹配，且缺少失败处理和上报机制。

---

## 四、建议修复

| # | 问题 | 建议 | 优先级 |
|---|------|------|--------|
| 1 | Bash 白名单过窄 | 扩展 tester 的 `bashAllow`，加入必要的调试命令（`tail`, `pkill`, `sleep`, `ls`），或改为 `Bash(**)` 后依赖 prompt 约束行为 | P0 |
| 2 | Read 路径不足 | 将 `gol-tools/foreman/bin/` 加入 tester 的 `readPaths`，或确保 prompt 中引用的所有路径均在允许范围内 | P0 |
| 3 | 模型盲目重试 | 在 prompt 中加入明确指令："工具权限被拒后立即停止重试，转用替代方案或直接报告失败" | P1 |
| 4 | 权限拒绝不上报 | 检查 CodeBuddy `permission_denials` 字段的填充逻辑，确保拒绝事件被正确记录 | P1 |
| 5 | 缺少降级指导 | 在 `e2e-acceptance.md` 中增加环境故障处理流程，明确：降级时必须报告 `fail` 或 `inconclusive`，禁止在无运行时证据时给出 `pass` | P1 |
| 6 | 僵尸进程 | Daemon 的 tester exit 回调中增加 Godot 进程清理（`pkill -f Godot`），不依赖 tester 自行清理 | P2 |
| 7 | Token 浪费 | 长期考虑：限制 tool_result 中的文件内容长度，或在上下文窗口接近上限时触发 compact | P3 |
