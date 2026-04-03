# CodeBuddy CLI `-p` 模式权限系统分析

> 日期：2026-04-03
> 基于：CLI 官方文档 + OpenCode 源码（`opencode/packages/opencode/src/`）
> 源码版本：opencode submodule (dev branch)

---

## 1. 概述

CodeBuddy CLI 提供 `-p`（`--print`）参数进入无头模式（Headless Mode），适用于 CI/CD、脚本自动化和 agent 集成场景。在此模式下，工具权限的评估与交互模式（TUI）有本质区别——**没有用户交互界面，所有权限确认请求要么被预授权规则放行，要么被自动拒绝**。

本文档基于以下资料交叉验证：

- CLI 参考文档（cli-reference、headless、iam、sdk-permissions）
- OpenCode 源码中的权限模块实现
- `-p` 模式的运行入口（`cli/cmd/run.ts`）

---

## 2. 权限系统架构

### 2.1 分层结构

```
CLI 参数 (allowedTools / disallowedTools / permission-mode / -y)
    │
    │  合并优先级（高 → 低）
    ▼
1. 命令行参数 (CLI args)
2. 本地项目设置 (.codebuddy/settings.local.json)
3. 共享项目设置 (.codebuddy/settings.json)
4. 用户设置 (~/.codebuddy/settings.json)
    │
    ▼
PermissionNext.Ruleset
  [{permission: string, pattern: string, action: "allow"|"deny"|"ask"}]
    │
    ▼
evaluate(permission, pattern, ...rulesets) → Rule
    │
    ├─ action: "allow"  → 直接放行
    ├─ action: "deny"   → 抛出 DeniedError（工具调用失败）
    └─ action: "ask"    → 挂起 Promise，等待外部 reply
```

### 2.2 核心数据结构

```typescript
// permission/next.ts
export const Action = z.enum(["allow", "deny", "ask"])

export const Rule = z.object({
  permission: z.string(),   // 工具类型：bash, edit, read, glob, ...
  pattern: z.string(),      // 匹配模式：支持通配符 *
  action: Action,           // allow | deny | ask
})

export type Ruleset = Rule[]
```

### 2.3 设置文件中的权限配置格式

在 `settings.json` 中，权限以如下格式声明：

```json
{
  "permissions": {
    "allow": ["Read", "Edit(src/**)", "Bash(git:*)"],
    "ask": ["WebFetch", "Bash(docker:*)"],
    "deny": ["Bash(rm:*)", "Bash(sudo:*)", "Edit(**/*.env)"]
  }
}
```

`permissions` 对象中每个 key 是 `permission`（工具类型），value 是 `action` 或 `{pattern: action}` 的映射。

---

## 3. `-p` 模式的特殊行为

### 3.1 硬编码注入的 deny 规则

**源码位置**：`cli/cmd/run.ts` 第 353-369 行

```typescript
const rules: PermissionNext.Ruleset = [
  { permission: "question",  action: "deny", pattern: "*" },
  { permission: "plan_enter", action: "deny", pattern: "*" },
  { permission: "plan_exit",  action: "deny", pattern: "*" },
]
```

在 `-p` 模式下，无论用户如何配置 `--allowedTools`，以下工具始终被禁止：

| 工具 | permission 标识 | 效果 |
|------|----------------|------|
| AskUserQuestion | `question` | AI 无法向用户提问，所有提问请求直接失败 |
| 进入 plan 模式 | `plan_enter` | 无法切换到只读规划模式 |
| 退出 plan 模式 | `plan_exit` | 无法从规划模式退出 |

这些规则随 session 创建时注入：

```typescript
const result = await sdk.session.create({ title: name, permission: rules })
```

### 3.2 `permission.asked` 事件的自动拒绝

**源码位置**：`cli/cmd/run.ts` 第 540-552 行

```typescript
if (event.type === "permission.asked") {
  const permission = event.properties
  if (permission.sessionID !== sessionID) continue
  UI.println(
    `! permission requested: ${permission.permission} (${permission.patterns.join(", ")}); auto-rejecting`
  )
  await sdk.permission.reply({
    requestID: permission.id,
    reply: "reject",
  })
}
```

**核心行为**：在 `-p` 模式的事件循环中，监听到 `permission.asked` 事件后，立即以 `"reject"` 回复。这意味着：

- 所有未被 `allow` 规则覆盖的工具调用，一旦触发 `ask` 级别，**自动被拒绝**
- LLM 会收到 `RejectedError` 错误消息，得知用户拒绝了该操作

### 3.3 `-y` 参数的影响

`-y`（`--dangerously-skip-permissions`）会跳过权限检查，使所有工具直接放行。但：
- `deny` 规则仍然生效（deny 优先级最高）
- 上述硬编码的 `question`/`plan_enter`/`plan_exit` deny 规则也会被绕过（取决于实现）

> **文档明确警告**：`-y` 仅应在受信任的环境和明确的任务场景下使用。

---

## 4. `--allowedTools` 参数解析

### 4.1 参数格式

`--allowedTools` 接受空格分隔或逗号分隔的字符串，支持模式匹配：

```bash
# 空格分隔
codebuddy -p "查询" --allowedTools "Bash" "Read" "Edit"

# 逗号分隔
codebuddy -p "查询" --allowedTools "Bash,Read,Edit"

# 带模式匹配
codebuddy -p "查询" --allowedTools "Bash(git log:*)" "Read" "Bash(npm test:*)"
```

### 4.2 转换为 Ruleset

每个 `allowedTools` 条目被转换为 `action: "allow"` 规则：

```
输入: --allowedTools "Bash(git log:*)" "Read" "Bash(npm test:*)"

等价 Ruleset:
[
  {permission: "Bash", pattern: "git log:*", action: "allow"},
  {permission: "Read",  pattern: "*",        action: "allow"},
  {permission: "Bash", pattern: "npm test:*", action: "allow"}
]
```

同样，`--disallowedTools` 转换为 `action: "deny"` 规则。

### 4.3 工具模式匹配语法

| 格式 | 含义 | 示例 |
|------|------|------|
| `Tool` | 匹配该工具的任何使用 | `Bash` → 允许所有 Bash 命令 |
| `Tool(specifier)` | 精确匹配 | `Bash(npm run build)` |
| `Tool(prefix:*)` | 前缀匹配 | `Bash(npm run test:*)` |
| `Tool(domain:name)` | MCP 工具匹配 | `mcp__github__get_issue` |
| `mcp__server` | MCP 服务器所有工具 | `mcp__puppeteer` |

**Bash 模式的重要限制**（来自官方文档警告）：

1. 使用**前缀匹配**，不是正则或 glob
2. 通配符 `:*` 仅在模式末尾有效
3. CodeBuddy 能识别 shell 操作符（如 `&&`），`Bash(safe-cmd:*)` 不会授权 `safe-cmd && other-cmd`
4. `Bash(curl http://github.com/:*)` 可以通过多种方式绕过（`-X GET`、`https://`、变量等）

**Read/Edit 路径模式**：

| 模式 | 含义 | 示例 |
|------|------|------|
| `//path` | 绝对路径（从文件系统根） | `Read(//Users/alice/secrets/**)` |
| `~/path` | 家目录路径 | `Read(~/Documents/*.pdf)` |
| `/path` | 相对于设置文件 | `Edit(/src/**/*.ts)` |
| `path` 或 `./path` | 相对于当前目录 | `Read(*.env)` |

---

## 5. 权限评估逻辑（evaluate）

### 5.1 评估函数

**源码位置**：`permission/next.ts` 第 236-243 行

```typescript
export function evaluate(permission: string, pattern: string, ...rulesets: Ruleset[]): Rule {
  const merged = merge(...rulesets)  // 合并所有规则集
  const match = merged.findLast(
    (rule) => Wildcard.match(permission, rule.permission) && Wildcard.match(pattern, rule.pattern),
  )
  // 无匹配时默认返回 ask
  return match ?? { action: "ask", permission, pattern: "*" }
}
```

**关键行为**：

1. **`findLast`**：从后往前匹配，后添加的规则优先级更高
2. **双重通配符匹配**：`permission` 和 `pattern` 都支持通配符
3. **默认兜底**：无任何匹配时返回 `action: "ask"`（不是 `deny`）

### 5.2 `ask()` 方法

**源码位置**：`permission/next.ts` 第 131-161 行

```typescript
export const ask = async (input) => {
  const s = await state()
  const { ruleset, ...request } = input

  for (const pattern of request.patterns ?? []) {
    const rule = evaluate(request.permission, pattern, ruleset, s.approved)

    if (rule.action === "deny")
      throw new DeniedError(ruleset.filter(...))  // 直接抛异常，工具调用失败

    if (rule.action === "ask") {
      // 挂起为 Promise，发布事件等待外部回复
      const id = input.id ?? Identifier.ascending("permission")
      return new Promise<void>((resolve, reject) => {
        s.pending[id] = { info, resolve, reject }
        Bus.publish(Event.Asked, info)
      })
    }

    if (rule.action === "allow") continue  // 继续检查下一个 pattern
  }
}
```

### 5.3 `reply()` 方法

**源码位置**：`permission/next.ts` 第 163-233 行

```typescript
export const reply = async (input) => {
  // ...
  if (input.reply === "reject") {
    existing.reject(input.message ? new CorrectedError(input.message) : new RejectedError())
    // 同时拒绝该 session 下所有其他 pending 的权限请求（级联拒绝）
    return
  }
  if (input.reply === "once") {
    existing.resolve()  // 仅本次放行
    return
  }
  if (input.reply === "always") {
    // 将规则写入 approved 缓存（会话级有效）
    for (const pattern of existing.info.always) {
      s.approved.push({ permission: existing.info.permission, pattern, action: "allow" })
    }
    existing.resolve()
    // 自动放行该 session 下所有现在能被 approve 覆盖的 pending 请求
    return
  }
}
```

**三种回复类型**：

| Reply | 行为 | `-p` 模式下 |
|-------|------|------------|
| `once` | 仅本次放行 | 不会触发（自动 reject） |
| `always` | 写入 approved 缓存，会话内永久放行 | 不会触发（自动 reject） |
| `reject` | 拒绝并终止，级联拒绝同 session 其他 pending | **这是默认行为** |

---

## 6. 错误类型

```typescript
// 自动拒绝（配置规则）
class DeniedError extends Error {
  // "The user has specified a rule which prevents you from using this specific tool call."
  // LLM 收到此消息后可以尝试其他方式
}

// 用户拒绝（无反馈）
class RejectedError extends Error {
  // "The user rejected permission to use this specific tool call."
  // LLM 收到后知道被拒绝，可换参数重试
}

// 用户拒绝（有反馈消息）
class CorrectedError extends Error {
  // "The user rejected permission ... with the following feedback: <message>"
  // LLM 收到用户的纠正意见，可据此调整
}
```

**`-p` 模式下的实际行为**：auto-reject 时没有附加 message，所以 LLM 收到的是 `RejectedError`。

---

## 7. 完整流程图

```
LLM 发起工具调用 (e.g., Bash("npm test"))
         │
         ▼
  ask({permission: "bash", patterns: ["npm test"], ruleset})
         │
         ▼
  evaluate("bash", "npm test", cliRules, configRules, approved)
         │
         ├─────────────────────────────────────────────────┐
         │                                                 │
    匹配到规则                                      无匹配（默认）
         │                                                 │
    ┌────┼────────┐                                  action: "ask"
    │    │        │                                       │
 allow  deny    ask                              ┌────────┴────────┐
    │    │        │                            │                 │
  放行  抛出    挂起 Promise                  TUI 模式          -p 模式
  继续  Denied  等待 reply                   │                 │
  执行  Error                               显示              自动
                                               Permission       reply:
                                               Prompt UI        "reject"
                                               │                 │
                                          用户选择:              │
                                          ┌────────┤          RejectedError
                                          │        │          LLM 收到拒绝
                                        once    always/reject   可换参数重试
                                        │        │
                                      resolve  resolve
                                               +写入approved
```

---

## 8. 场景矩阵

### 8.1 不同模式下的权限行为

| 场景 | `allowedTools` 有匹配 | `allowedTools` 无匹配 | `disallowedTools` 有匹配 |
|------|----------------------|----------------------|------------------------|
| **TUI 交互模式** | 直接放行 | 弹出权限确认对话框 | 直接拒绝（DeniedError） |
| **`-p` 模式（无 `-y`）** | 直接放行 | **自动拒绝 (auto-reject)** | 直接拒绝（DeniedError） |
| **`-p` 模式（有 `-y`）** | 直接放行 | 直接放行（bypass） | 直接拒绝（deny 规则仍生效） |

### 8.2 `-p` 模式下 `AskUserQuestion` 的处理

| 配置 | 结果 |
|------|------|
| 任何配置 | **始终被拒绝**（硬编码 `deny` 规则，优先级高于 `allowedTools`） |

LLM 无法在 `-p` 模式下向用户提问。如果 AI 需要用户决策，必须在调用前通过其他方式（如环境变量、配置文件）获取。

---

## 9. 实践建议

### 9.1 安全的 `-p` 模式配置

```bash
codebuddy -p "分析代码并运行测试" \
  --allowedTools "Bash,Read,Grep,Glob" \
  --output-format json
```

### 9.2 限定 Bash 命令范围

```bash
codebuddy -p "运行测试" \
  --allowedTools "Bash(npm test:*)" "Bash(npm run build:*)" "Read" "Grep" "Glob"
```

### 9.3 使用 `permission-mode` 配合

```bash
# plan 模式：只允许只读操作
codebuddy -p "分析项目结构" \
  --permission-mode plan

# acceptEdits 模式：自动接受文件编辑
codebuddy -p "重构代码" \
  --permission-mode acceptEdits \
  --allowedTools "Bash(git:*)"
```

### 9.4 SDK 中的 `canUseTool` 回调（编程控制）

在 SDK（Python/TypeScript）中，可以通过 `canUseTool` 回调实现自定义权限逻辑：

```python
async def can_use_tool(tool_name, input_data, options):
    # 只读工具自动允许
    if tool_name in ["Read", "Glob", "Grep"]:
        return PermissionResultAllow(updated_input=input_data)

    # 危险命令拒绝
    if tool_name == "Bash" and "rm -rf" in input_data.get("command", ""):
        return PermissionResultDeny(message="危险命令被拒绝", interrupt=True)

    # AskUserQuestion 处理
    if tool_name == "AskUserQuestion":
        questions = input_data.get("questions", [])
        answers = {}
        for q in questions:
            # 从环境变量或配置中获取答案
            answers[q["question"]] = get_preconfigured_answer(q)
        return PermissionResultAllow(updated_input={**input_data, "answers": answers})

    return PermissionResultAllow(updated_input=input_data)
```

### 9.5 `--permission-prompt-tool`（当前不支持）

官方文档明确标注：

> `--permission-prompt-tool` 功能当前不支持。

该参数设计用于在 `-p` 模式下通过 MCP 工具处理权限提示，但目前尚未实现。

---

## 10. 源码文件索引

| 文件 | 作用 |
|------|------|
| `packages/opencode/src/permission/next.ts` | 核心权限评估引擎（evaluate、ask、reply） |
| `packages/opencode/src/permission/index.ts` | 旧版权限系统（Plugin 集成、session 级 approved） |
| `packages/opencode/src/permission/arity.ts` | 权限规则解析辅助 |
| `packages/opencode/src/cli/cmd/run.ts` | `-p` 模式入口（硬编码 deny 规则、auto-reject 逻辑） |
| `packages/opencode/src/cli/cmd/tui/routes/session/permission.tsx` | TUI 权限确认 UI |
| `packages/opencode/src/server/routes/permission.ts` | HTTP API 权限回复端点 |

---

## 11. 关键结论

1. **`-p` 模式没有交互能力**：所有 `ask` 级别的权限请求被自动拒绝，LLM 收到 `RejectedError`
2. **`AskUserQuestion` 在 `-p` 下永远不可用**：被硬编码 deny 规则禁止
3. **`--allowedTools` 是 `-p` 模式下授权工具的唯一方式**：必须在启动时预声明所有需要的工具权限
4. **规则评估使用 `findLast`**：后合并的规则优先级更高，CLI 参数 > 项目配置 > 用户配置
5. **无匹配默认为 `ask`（不是 `deny`）**：这意味着未配置的工具在交互模式下会弹出确认，在 `-p` 下会自动拒绝
6. **`-y` 绕过权限但不绕过 deny 规则**：`--dangerously-skip-permissions` 使 `ask` 变为 `allow`，但 `deny` 仍然生效
7. **`always` 回复写入会话级缓存**：在 TUI 模式下，用户选择 "Allow always" 后，同类请求在当前会话内不再提示
8. **`reject` 会级联**：拒绝一个权限请求时，同 session 下所有 pending 的权限请求也会被级联拒绝
