# Foreman 多客户端集成调研更新

**日期**: 2026-05-05  
**范围**: `gol-tools/foreman/` 的客户端接入策略，重点覆盖 `cc-glm` / `cc-kimi` / `codex` / `opencode`  
**输入材料**:
- 既有报告: `docs/reports/2026-05-05-foreman-codex-client-research.md`（本文件前一版）
- Foreman 产出文档: `gol-tools/foreman/docs/client-integration-research.md`
- 本地 Foreman 源码
- 本机 Codex CLI 真实运行验证
- OpenAI Codex 官方文档与上游 issue

**状态**: 已完成

---

## 一、执行摘要

这次更新后的结论比上一版更明确：

1. **`cc-glm` / `cc-kimi` 已经是 Foreman 的稳定支持路径**  
   这部分不是待设计能力，而是现有能力。需要的是文档澄清和少量配置整理，不是新架构。

2. **`codex` 可以接，而且应作为新的第一类 client 接入**  
   最优先路径是 `codex exec` 的无头 CLI 模式，不是 ACP，也不是先上 SDK / app-server。

3. **`opencode` 目前不适合继续作为默认 client 心智**  
   仓库里已有大量权限、hook 兼容、测试运行时限制的补丁和报告；再加上你明确说明当前有 bug、稳定性一般。更合理的定位是“实验性 / 兼容性 fallback”，不是默认主力。

4. **前一份 `client-integration-research.md` 对 Codex 有几处关键误判**  
   包括认证方式、日志格式、工作目录理解、resume 假设、以及“当前 `buildClientArgs()` 模式已经足够”的结论。

5. **最合适的架构不是重 OO Provider/Adapter，也不是继续靠 `binary === ...` 的 `if` 分支硬撑**  
   更好的中间态是一个**薄的、声明式的 client family launch spec**。  
   这和 Codex 自己的内部设计风格是一致的：配置分层、显式 trust、明确 sandbox/approval、结构化线程状态，而不是用一大堆 provider class。

---

## 二、对前一份调研的修正

下表专门修正 `gol-tools/foreman/docs/client-integration-research.md` 中最重要的偏差。

| 主题 | 前文说法 | 更新结论 |
|---|---|---|
| Codex 身份 | “Codex (GitHub Copilot)” | **错误**。这里讨论的是 OpenAI Codex CLI / runtime，不是 GitHub Copilot CLI |
| Codex 认证 | `GITHUB_TOKEN` | **错误**。本机默认是 `ChatGPT` 登录；CLI 也支持 API key 登录 |
| Codex JSONL | 假设 `{"type":"suggestion","content":"..."}` | **错误**。本机 `0.128.0` 实测是 `thread.started` / `turn.started` / `item.completed` / `turn.completed` |
| `workDir` 语义 | “通常是 worktree 路径” | **错误**。Foreman 当前是从管理仓库根目录启动 client，worktree 路径通过 prompt 传给 agent |
| Resume | “待确认” | **已确认**。`codex exec resume <thread-id>` 可用；但 `--ephemeral` 会让会话不可续跑 |
| 抽象结论 | “现有 buildClientArgs() 足够，不推荐抽象” | **不成立**。Codex 带来不止 argv 差异，还带来 config layering、summary source、session persistence、skill root、hook mode 差异 |
| ACP 路线 | 与 CLI 做对比，CLI 优先 | **结论保留，但理由需改写**。这里不是 GitHub Copilot ACP，而是 OpenAI Codex 的 CLI / SDK / app-server 体系 |

---

## 三、Foreman 当前真实运行模型

### 3.1 当前 cwd 不是 worktree，而是管理仓库根

这是本次调研中非常重要的一个更正。

根据 `gol-tools/foreman/bin/foreman.mts`：

- `resolveWorkDir()` 取当前管理仓库根目录
- `resolveRepoDir(workDir)` 固定为 `join(workDir, 'gol-project')`
- client 进程最终由 `runner.mts` 使用 `cwd: opts.workDir` 拉起
- 真正的 `workspace` / `worktree` 路径是单独创建后，通过 prompt 中的 `{{workspace_path}}` 和 `{{worktree_instruction}}` 传给 agent

也就是说，Foreman 当前模型是：

```text
client cwd = gol/ 管理仓库根
实际编码目录 = gol/.worktrees/ws_xxx 或 gol/gol-project
```

这件事对 Codex 集成有两个直接好处：

1. 根目录下的 `.claude/skills`、未来的 `.agents/skills`、`.codex/config.toml` 都能稳定被发现
2. 当前 GOL 的 `.worktrees/` 布局仍然在管理仓库根之下，不会越出 project trust / project config 边界

### 3.2 现有 client 抽象其实已经开始“超出 argv 映射”

表面上 Foreman 现在只有一个：

```ts
buildClientArgs(binary, prompt): string[]
```

但真实系统已经不止在做 argv 拼装。当前 Foreman 还同时承担：

- env file 注入
- log parser 选择
- summary 抽取
- worktree 指令注入
- retry 判定
- state 持久化

Codex 接入后，这些差异会继续增加，因此再把所有差异都塞回一个 `if (binary === ...)` 函数，已经不合理了。

---

## 四、Codex 能力确认

### 4.1 本机环境

本机确认到：

```bash
codex --version
# codex-cli 0.128.0
```

```bash
codex login status
# Logged in using ChatGPT
```

本机 `~/.codex/config.toml` 还显示了几个关键默认值：

```toml
model = "gpt-5.5"
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

这说明 Codex runtime 是明显的**配置分层设计**：

- 用户级全局 config
- 每项目 trust 配置
- plugin / marketplace 配置
- repo-local `.codex/` 层

这正是这次更新报告里“参考 happy code / Codex 内部设计”的关键切入点：  
**Foreman 不能假设自己运行在一个空白 CLI 上，它必须决定是否继承用户个人的 Codex 默认配置。**

### 4.2 官方文档确认的无头模式能力

OpenAI 官方文档明确说明：

- `codex exec` 是非交互模式
- 默认是 `read-only sandbox`
- 写工作区应显式传 `--sandbox workspace-write`
- `--dangerously-bypass-approvals-and-sandbox` 可完全跳过 approvals 和 sandbox
- `--output-last-message` 可把最终消息写入文件
- `--ignore-user-config` 可以忽略 `$CODEX_HOME/config.toml`
- `--ignore-rules` 只忽略 user / project execpolicy `.rules`

来源：

- `Non-interactive mode`
- `CLI reference`
- `Config reference`

### 4.3 本机真实 `codex exec` JSONL 事件

我直接在本机跑了最小验证：

```bash
codex exec --json --sandbox read-only --output-last-message /tmp/codex-foreman-last.txt "Reply with exactly OK."
```

真实输出是：

```json
{"type":"thread.started","thread_id":"019df8ce-51a4-77a3-8715-f1a037b26050"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}
{"type":"turn.completed","usage":{"input_tokens":17296,"cached_input_tokens":11136,"output_tokens":23,"reasoning_output_tokens":16}}
```

`--output-last-message` 写出的文件内容是：

```text
OK
```

但注意：**文件末尾没有换行**。  
这意味着如果 Foreman 用 `wc -l` 或按行读取来判断内容，可能得到误导结果。读取方式应该是“整个文件内容 + trim”。

### 4.4 `resume` 能力已确认

我又做了两组验证：

#### A. `--ephemeral` 的会话不会被 `resume --last` 选中

先跑：

```bash
codex exec --json --ephemeral ...
```

再跑：

```bash
codex exec resume --last ...
```

结果没有续到刚才那次短会话，而是跳到了一个别的历史会话。  
这说明：**Foreman 如果要支持 resume，就不能默认开 `--ephemeral`。**

#### B. 显式 thread id 续跑成功

先跑一个非 ephemeral 会话，拿到：

```text
thread_id = 019df8cf-0704-74b1-a9f5-b06326902e74
```

再执行：

```bash
codex exec resume 019df8cf-0704-74b1-a9f5-b06326902e74 --json ...
```

结果输出：

```json
{"type":"thread.started","thread_id":"019df8cf-0704-74b1-a9f5-b06326902e74"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"EXPLICIT"}}
{"type":"turn.completed","usage":{"input_tokens":34702,"cached_input_tokens":28416,"output_tokens":43,"reasoning_output_tokens":26}}
```

结论：

- `resume` 可用
- Foreman 应把 `thread_id` 作为一等状态存起来
- `--ephemeral` 与 resume 需求互斥

### 4.5 `review` 子命令是额外价值点

本机 `codex exec review --help` 明确存在，并支持：

- `--uncommitted`
- `--base`
- `--commit`
- `--json`
- `--output-last-message`

这意味着 Foreman 后续不只可以把 Codex 当 generic coder，还可以加独立任务类型，例如：

- `review-uncommitted`
- `review-branch`
- `review-commit`

---

## 五、Codex 接入对 Foreman 的真实影响面

### 5.1 不是只多一个 `binary: codex`

如果只从 `buildClientArgs()` 看，Codex 好像只是：

```ts
['exec', prompt, '--json']
```

但真实差异远不止这一层。至少还有：

1. **binary 级参数与 subcommand 级参数分层**  
   本机验证到：

   ```bash
   codex exec --ask-for-approval never --help
   # 报 unexpected argument
   ```

   但：

   ```bash
   codex --ask-for-approval never exec --help
   ```

   可以解析。  
   这已经证明“一个平面 argv builder”不够表达 Codex。

2. **summary source 差异**  
   Codex 有 `--output-last-message`，优先级应该高于从 JSONL 硬解析。

3. **session persistence 差异**  
   Codex 的线程是显式 thread id，值得落 state；现有 Foreman 对 session 没有统一模型。

4. **config inheritance 风险**  
   用户 `~/.codex/config.toml` 可能带来全局 `danger-full-access` / `approval_policy=never` 默认值。

5. **skills / hooks / trust 机制差异**  
   Codex 认 `.agents/skills`、`.codex/hooks.json`、`.codex/config.toml`，并受 `projects.<path>.trust_level` 影响。

### 5.2 `--ignore-user-config` 应该成为 Foreman 的默认思路

这是这次更新里最重要的新建议之一。

因为本机全局 Codex 配置就是：

- `approval_policy = "never"`
- `sandbox_mode = "danger-full-access"`

如果 Foreman 不隔离用户配置，那么不同开发者机器上，同一条 `foreman run task ... --client codex` 可能在不同的 sandbox / approval 模式下运行。

对自动化系统来说，这不可接受。

**建议：**

Foreman 的 Codex client 默认使用：

```bash
codex exec \
  --ignore-user-config \
  --json \
  --sandbox workspace-write \
  --output-last-message <file> \
  "<prompt>"
```

这样做的效果是：

- 不继承用户个人的 `model` / `sandbox_mode` / `approval_policy`
- 仍然保留认证能力
- 仍然允许 repo-local `.codex/` 配置参与运行

我已经本机验证过：

```bash
codex exec --ignore-user-config --sandbox read-only ...
```

可以正常运行并返回结果。

### 5.3 `--ignore-rules` 不应默认开启

`--ignore-user-config` 和 `--ignore-rules` 不能混为一谈。

- `--ignore-user-config`: 推荐默认开，避免用户 home 目录污染 Foreman
- `--ignore-rules`: **不推荐默认开**，否则会跳过 repo-local execpolicy `.rules`

如果未来 GOL 用 `.codex/` 做仓库级 guardrail，默认忽略 rules 会把它们直接绕过去。

### 5.4 `.agents/skills` 应与 `.claude/skills` 建立桥接

Codex 官方 skill 目录是：

- `<repo>/.agents/skills`
- `~/.agents/skills`
- `/etc/codex/skills`

官方文档还明确说支持 symlinked skill folders。

因此 GOL 最省事的方案不是复制一份 skills，而是：

```text
.agents/skills -> .claude/skills
```

与此同时，Foreman 预检查也要从：

```text
.claude/skills/<skill>/SKILL.md
```

升级为按 client family 选择 skill root。

### 5.5 `.claude/hooks` 不能原样搬到 Codex

当前 GOL 的 hook 体系是 `.claude/settings.json` + `.claude/hooks/*.sh`。  
Codex 的入口则是：

- `~/.codex/hooks.json`
- `~/.codex/config.toml`
- `<repo>/.codex/hooks.json`
- `<repo>/.codex/config.toml`

更关键的是：Codex 文件编辑 hook 主要围绕 `apply_patch` 的 patch DSL，而不是 Claude 常见的 `file_path` + `content` 结构。

所以：

- 基于 Bash 命令文本的规则容易迁
- 基于“写入哪个文件、正文包含什么”的 Claude hook，需要改造成 patch-aware parser

---

## 六、对现有客户端的重新分级

### 6.1 `cc-glm` / `cc-kimi`

状态：**稳定支持**

理由：

- `config.yaml` 已有现成 client
- `buildClientArgs()` 已覆盖 `claude`
- `log-parser.mts` 已覆盖 Claude 流式 JSON
- Foreman 现有 task 默认大量指向 `cc-kimi`

建议：

- 不再把这部分写成“新集成方案”，而应写成“现有支持矩阵”
- 只补齐文档、测试和命名一致性

### 6.2 `opencode`

状态：**建议降级为 experimental / fallback**

理由不是单一 bug，而是系统性信号已经很多：

1. 当前 `opencode` 启动参数直接写了：

```ts
['run', prompt, '--format', 'json', '--dangerously-skip-permissions']
```

这本身就表明它在 Foreman 里的权限路径不是保守默认值。

2. 仓库里已有大量 opencode / OMO 兼容研究和修复工作：

- `docs/reports/2026-04-05-test-harness-v2-research.md`
- `docs/reports/2026-04-05-opencode-subagent-config-strategy.md`
- `docs/reports/2026-04-03-codebuddy-cli-permission-analysis.md`
- `docs/reports/2026-04-03-codebuddy-permission-verification.md`

3. 这些材料共同说明：

- hook 兼容要依赖 OMO bridge
- tools / permissions 语义与 Claude 不完全同构
- 测试与运行时常常需要额外 deny / allow 修补

4. 你现在又明确指出：**当前 opencode 有 bug，虽然可用，但不够稳定。**

这对产品决策的意义是：

- `opencode` 不应该继续承担“默认主力 client”的角色
- 更合适的是保留为：
  - fallback client
  - 兼容性保底
  - 某些特定任务的备用路径

### 6.3 `codex`

状态：**建议新增为 first-class client**

推荐定位：

- 初期：beta / opt-in
- 通过 smoke tasks 验证后：作为 `generic` / `fix-issue` 的优先候选

---

## 七、推荐的架构方向

### 7.1 不要重 Provider/Adapter OO 层

前一份调研对这一点的直觉是对的：  
**没必要为了 3-4 个 client 引入大而重的 class hierarchy。**

### 7.2 但也不能继续停留在 `if (binary === ...)`

前一份调研在这里走过头了。  
Codex 证明了 client 差异不止是 argv 拼装，还包括：

- summary source
- session mode
- user config isolation
- skills root
- hooks mode
- sandbox default
- trust dependency

### 7.3 推荐“client family launch spec”

建议引入一个非常薄的中间层，不是 OO provider，而是声明式 spec。

示意：

```ts
type ClientFamily = 'claude' | 'codex' | 'opencode'

interface ClientConfig {
  family: ClientFamily
  binary: string
  envFile?: string
}

interface LaunchSpec {
  binary: string
  args: string[]
  summaryMode: 'parse-log' | 'last-message-file'
  sessionMode: 'none' | 'thread'
  skillRoot: '.claude/skills' | '.agents/skills'
  ignoreUserConfig?: boolean
}
```

然后：

```ts
buildLaunchSpec(clientConfig, prompt, runOpts) -> LaunchSpec
```

这层的好处：

- 足够轻，不引入复杂对象系统
- 足够强，能表达 Codex 的多维差异
- 符合 Codex 自己“配置分层 + 显式 trust + 显式 sandbox”的内部风格

### 7.4 为什么说这参考了 happy code / Codex 内部设计

从本机 `~/.codex/config.toml` 和官方文档可以看出，Codex runtime 的核心设计不是“按 provider 写很多逻辑分支”，而是：

- 全局 / 项目 / repo-local 多层配置
- trust 决定是否加载 project-local hooks / rules / config
- plugins / MCP / skills 作为可插拔层
- thread id 作为持久状态
- CLI / SDK / app-server 是不同自动化入口

Foreman 若要接好 Codex，最好的方法不是照搬 UI 行为，而是**吸收这套 runtime 分层思想**：

- 用户级配置默认隔离
- 仓库级策略显式启用
- 会话状态显式持久化
- client family 差异配置化，而不是散落在各处

---

## 八、MVP 实现建议

### Step 1: 调整 `config.yaml`

建议新增 `family` 字段，而不是仅靠 client name / binary 猜。

```yaml
clients:
  cc-glm:
    family: claude
    binary: claude
    envFile: .env.ccg
  cc-kimi:
    family: claude
    binary: claude
    envFile: .env.cck
  codex:
    family: codex
    binary: codex
  opencode:
    family: opencode
    binary: opencode
```

### Step 2: `buildClientArgs()` 升级为 `buildLaunchSpec()`

至少把下面这几个维度收进去：

- argv
- 是否 `--ignore-user-config`
- summary source
- session mode
- skill root

### Step 3: Codex 默认命令

建议默认：

```bash
codex exec \
  --ignore-user-config \
  --json \
  --sandbox workspace-write \
  --output-last-message <file> \
  "<prompt>"
```

不建议默认：

- `--ephemeral`
- `--dangerously-bypass-approvals-and-sandbox`
- `--ignore-rules`

### Step 4: 扩展 state

给 `state.json` 新增：

- `threadId`
- `lastMessageFile`
- `usageSummary`
- `sessionFamily`

其中 `threadId` 从：

```json
{"type":"thread.started","thread_id":"..."}
```

解析得到。

### Step 5: `log-parser.mts` 支持 Codex

Codex parser 不要再猜 `suggestion`。  
MVP 直接支持：

- `item.completed` + `item.type === "agent_message"` -> 摘要正文
- `turn.completed.usage` -> 统计信息

但通知摘要的第一来源应是 `--output-last-message` 文件。

### Step 6: skills bridge

新增：

```text
.agents/skills -> .claude/skills
```

并把 `preRunCheck()` 改成按 family 选 skill root。

### Step 7: 先不迁完整 hook，只迁最关键 guardrail

优先级建议：

1. Bash 级禁止危险 git / env 操作
2. 再考虑 patch-aware 文件规则
3. 最后再考虑 PostToolUse 自动副作用脚本

### Step 8: 给 Codex 单独加 smoke 任务

至少新增一个低风险 task，例如：

- `generic --client codex`
- `scan-etc --client codex`

先验证：

- 日志写入
- summary 提取
- state threadId
- detached mode
- retry 行为

---

## 九、建议延后到第二阶段的能力

### 9.1 `codex exec review`

价值很高，但不是 MVP 必需。  
建议在 Codex coding path 跑通后，再加独立 review task。

### 9.2 repo-local `.codex/` 完整策略层

例如：

- `.codex/config.toml`
- `.codex/hooks.json`
- `.codex/*.rules`

这些很值得做，但它们属于“仓库策略层建设”，不该阻塞 Codex client 接入本身。

### 9.3 SDK / app-server

这条路只有在需要下面能力时才值得上：

- 程序化多轮控制
- thread fork
- 更细的事件和 turn control
- 更稳定的长期会话 orchestration

官方文档明确指出：

- TypeScript SDK 比 non-interactive mode 更全面、更灵活
- app-server 原生有 `thread/start`、`thread/resume`、`thread/fork`

所以中长期路线很清楚，但不该作为 MVP 前提。

---

## 十、已知风险

### 10.1 `codex exec fork` 仍不存在

截至 2026-05-05，公开 issue 仍开着：

- #11750
- #17568

因此：

- CLI 模式可新建会话
- 可 resume
- **不能 headless fork**

### 10.2 `codex exec` 的 MCP 路径有公开回归

截至 2026-05-05，公开 issue #16685 报告 exec 模式的 MCP tool call 被取消。

结论：

- MVP 不要依赖 Codex MCP
- 先把基础 coding path 跑稳

### 10.3 嵌套外部 sandbox 下的只读边界有风险

公开 issue #15524 指出：

- `codex exec -s read-only`
- 在某些外层 sandbox 环境下
- 仍可能出现文件写入

结论：

- 不把 Codex sandbox 当唯一安全边界
- 仓库级 hook / policy / Foreman orchestration 仍然必要

### 10.4 用户级配置污染是现实风险，不是理论风险

本机已经存在：

- `approval_policy = "never"`
- `sandbox_mode = "danger-full-access"`

这说明如果 Foreman 不主动隔离 user config，客户端行为会随开发者机器漂移。

---

## 十一、最终建议

### 建议的支持矩阵

| 客户端 | 结论 | 定位 |
|---|---|---|
| `cc-glm` | 继续支持 | 稳定 |
| `cc-kimi` | 继续支持 | 稳定 |
| `codex` | 尽快接入 | 新的一等 client |
| `opencode` | 保留但降级 | experimental / fallback |

### 建议的实现顺序

1. 把 Foreman 的 client 抽象从“binary 分支”升级为“family launch spec”
2. 接入 `codex exec --ignore-user-config --json --sandbox workspace-write --output-last-message`
3. 持久化 `threadId`
4. 打通 `.agents/skills -> .claude/skills`
5. 让 Codex 先跑通 `generic` / `scan-*` / `fix-issue`
6. 再考虑 review、repo-local `.codex/`、SDK / app-server

### 最终判断

**应该支持 Codex，而且不是“以后再看”的级别。**

当前材料已经足够说明：

- CCG / CCK 已经有稳定路径
- Opencode 当前不适合继续当默认主力
- Codex 在本机和官方文档层面都已经具备无头接入 Foreman 的核心条件

真正应该做的，不是继续争论“要不要抽象”，而是尽快把 Foreman 提升到能正确表达多 client family 差异的那一层。

---

## 参考资料

### 本地代码与配置

- `gol-tools/foreman/docs/client-integration-research.md`
- `gol-tools/foreman/config.yaml`
- `gol-tools/foreman/lib/client-args.mts`
- `gol-tools/foreman/lib/log-parser.mts`
- `gol-tools/foreman/lib/runner.mts`
- `gol-tools/foreman/lib/worktree.mts`
- `gol-tools/foreman/bin/foreman.mts`
- `~/.codex/config.toml`
- `codex --version`
- `codex login status`
- `codex exec --help`
- `codex exec resume --help`
- `codex exec review --help`
- `codex mcp-server --help`
- `codex features list`

### 本机实测命令

- `codex exec --json --sandbox read-only --output-last-message ...`
- `codex exec resume <thread-id> --json --output-last-message ...`
- `codex exec --ignore-user-config --sandbox read-only --json ...`

### OpenAI 官方文档

- Non-interactive mode  
  https://developers.openai.com/codex/noninteractive
- CLI reference  
  https://developers.openai.com/codex/cli/reference
- Authentication  
  https://developers.openai.com/codex/auth
- Skills  
  https://developers.openai.com/codex/skills
- Hooks  
  https://developers.openai.com/codex/hooks
- SDK  
  https://developers.openai.com/codex/sdk
- App Server  
  https://developers.openai.com/codex/app-server
- Config reference  
  https://developers.openai.com/codex/config-reference

### 上游 issue

- #11750 `codex exec fork` 缺失  
  https://github.com/openai/codex/issues/11750
- #15524 nested sandbox 下 read-only 仍可写  
  https://github.com/openai/codex/issues/15524
- #16685 exec 模式 MCP tool call 被取消  
  https://github.com/openai/codex/issues/16685
- #17568 non-interactive session forking  
  https://github.com/openai/codex/issues/17568

### 项目内既有相关报告

- `docs/reports/2026-04-03-codebuddy-cli-permission-analysis.md`
- `docs/reports/2026-04-03-codebuddy-permission-verification.md`
- `docs/reports/2026-04-05-test-harness-v2-research.md`
- `docs/reports/2026-04-05-opencode-subagent-config-strategy.md`
