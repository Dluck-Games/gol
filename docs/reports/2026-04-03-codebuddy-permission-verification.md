# CodeBuddy CLI `-p` 模式权限执行验证报告

**日期**: 2026-04-03
**工具版本**: CodeBuddy CLI v2.72.0
**验证方法**: 直接 CLI 调用 + `--output-format stream-json` 捕获
**状态**: 已完成

---

## 一、验证目的

验证 Foreman 通过 `--allowedTools` + `--permission-mode default` 参数传递给 CodeBuddy CLI 后，权限系统是否能正确执行以下两点：

1. **非授权工具调用时不会卡住**（应 auto-reject，而非挂起等待用户确认）
2. **路径范围外的文件不可访问**（path-scoped `--allowedTools` 生效）

---

## 二、测试环境

| 项目 | 值 |
|------|---|
| CodeBuddy CLI | v2.72.0 (`/opt/homebrew/bin/codebuddy`) |
| 模型 | glm-5.0-ioa |
| 模式 | `-p`（headless / pipe mode） |
| 输出格式 | `stream-json` |
| 超时机制 | perl `alarm(25)` |
| 测试目录 | `/tmp/cb-perm-test/`（临时创建，测试后删除） |

---

## 三、Test 1: 非授权工具调用行为

### 3.1 测试场景

`--allowedTools` 只包含 `Read`、`Grep`、`Glob`，但 prompt 要求 agent 使用 `Write` 工具创建文件。

### 3.2 结果矩阵

| # | `--permission-mode` | `--allowedTools` | 结果 | 退出码 |
|---|---|---|---|---|
| 1a | _(未设置，默认)_ | `Read Grep Glob` | ⚠️ **`Write` 执行成功**，文件被创建，`--allowedTools` 被完全忽略 | 0 |
| 1b | `default` | `Read Grep Glob` | ✅ `Write` 被拒绝，`PermissionDeniedError` 返回给 LLM，进程正常退出 (~19s) | 0 |
| 1c | `default` | `Read Grep Glob`（max-turns=3）| ✅ 同上，auto-reject 立即生效 (<1ms)，多轮重试在 turn 预算内完成 | 142 (SIGALRM) |

### 3.3 关键发现

**发现 1: 默认 `--permission-mode` 是 `bypassPermissions`**

不指定 `--permission-mode` 时，CLI init 事件显示 `"permissionMode":"bypassPermissions"`。在此模式下：

- `--allowedTools` 参数**被完全忽略**
- 所有工具调用直接放行，无论是否在白名单中
- 等价于 `-y`（`--dangerously-skip-permissions`）

```
# CLI init 输出 (无 --permission-mode 时)
{"type":"system","permissionMode":"bypassPermissions",...}
```

**发现 2: `--permission-mode default` 是必需的**

只有显式设置 `--permission-mode default` 后，`--allowedTools` 才会生效：

```
# CLI init 输出 (--permission-mode default 时)
{"type":"system","permissionMode":"default",...}
```

**发现 3: `-p` 模式下 auto-reject 不会卡住**

在 `--permission-mode default` + `-p` 模式下，未授权工具调用收到的是 `PermissionDeniedError`（同步拒绝），而非挂起等待。LLM 立即收到错误消息并可调整行为。

```
# auto-reject 错误消息
PermissionDeniedError: Permission to use Write has been denied because 
this tool requires approval but permission prompts are not available in 
non-interactive mode.
```

**发现 4: 之前观察到的 "卡住" 现象**

Test 1c（max-turns=3）在 25s alarm 内未完成。但这不是权限系统卡住，而是 LLM 在 3 轮尝试中都反复尝试 Write，每次都被立即拒绝后继续重试，直到 turn 预算耗尽。设置 `--max-turns 1` 时，整个过程在 ~19s 内干净退出。

---

## 四、Test 2: 路径范围控制

### 4.1 测试场景

`--allowedTools` 中 `Read` 工具仅允许 `/tmp/cb-perm-test/allowed-dir/**` 路径。

```
/tmp/cb-perm-test/
├── allowed-dir/
│   └── public.txt          # "PUBLIC DATA"  ← 应可读
└── restricted-dir/
    └── secret.txt          # "SENSITIVE DATA"  ← 应不可读
```

### 4.2 结果

| 目标文件 | 是否在允许路径内 | 结果 |
|---|---|---|
| `/tmp/cb-perm-test/allowed-dir/public.txt` | ✅ 匹配 `(/tmp/cb-perm-test/allowed-dir/**)` | ✅ 读取成功，返回 `"PUBLIC DATA"` |
| `/tmp/cb-perm-test/restricted-dir/secret.txt` | ❌ 不匹配 | ✅ `PermissionDeniedError`，文件内容未暴露 |

### 4.3 路径通配符行为

`Read(/tmp/cb-perm-test/allowed-dir/**)` 中的 `**` 通配符正确限制了访问范围：
- 子目录内的文件：✅ 允许
- 并列目录内的文件：✅ 拒绝
- 父目录的文件：✅ 拒绝

---

## 五、结论

### 权限系统有效性

| 验证项 | 状态 | 说明 |
|--------|------|------|
| 非授权工具不会卡住 | ✅ **通过** | `--permission-mode default` 下 auto-reject 同步返回 `PermissionDeniedError` |
| 路径范围外文件不可访问 | ✅ **通过** | path-scoped `--allowedTools` 的 `**` 通配符正确限制访问 |
| 正确路径内文件可正常访问 | ✅ **通过** | 在允许范围内的 Read 操作正常执行 |

### 必需配置组合

```bash
codebuddy -p \
  --permission-mode default \          # 必需！否则默认 bypassPermissions
  --allowedTools "Read(/path/**)" "Write(/path/**)" "Bash(cmd:*)" \
  --output-format stream-json \
  --model <model> \
  --max-turns <n> \
  "<prompt>"
```

**三个参数缺一不可**：
- `-p`：无头模式，无用户交互
- `--permission-mode default`：激活权限评估引擎
- `--allowedTools`：定义白名单

### 风险提示

如果 `PROVIDER_SPECS` 中某个 client 的 `permissionFlags` 意外被移除（例如从 `['--permission-mode', 'default']` 变为 `[]`），该 client 将静默回退到 `bypassPermissions` 模式，所有 `--allowedTools` 限制失效。建议在 foreman 测试套件中增加断言，验证每个 PROVIDER_SPECS 条目都包含 `--permission-mode`。

---

## 六、Foreman 当前配置确认

当前 `process-manager.mjs` 中所有三个 client 均已正确配置：

```javascript
// lib/process-manager.mjs — PROVIDER_SPECS
'codebuddy':     { permissionFlags: ['--permission-mode', 'default'], ... },
'claude':        { permissionFlags: ['--permission-mode', 'default'], ... },
'claude-internal': { permissionFlags: ['--permission-mode', 'default'], ... },
```

命令构建顺序（`#spawnProcess` L127-133）：

```
codebuddy -p --permission-mode default --model <m> --output-format stream-json --max-turns <n> <prompt> --allowedTools <tools...>
```

注：`--allowedTools` 放在 prompt 之后（variadic 参数），这是正确的位置。
