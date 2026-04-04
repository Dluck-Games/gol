# E2E 验收文档 - Issue #195 冻结伤害动画修复

## 测试环境

| 项目 | 值 |
|------|-----|
| 场景路径 | `gol-project/scenes/main.tscn` |
| Godot 版本 | 4.6.1.stable.official.14d19694e |
| 工作空间 | `/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260404082953._8dbb58c1` |
| 分支 | `foreman/issue-195` |
| 前置条件 | Godot 进程启动 → AI Debug Bridge IPC 连通（信号目录 `user://ai_signals/` 存在） |

## 测试用例与结果

| # | 检查项 | 结果 | 证据 |
|---|--------|------|------|
| T-E2E-1 | 角色受到冻结伤害 → 解冻后移动动画正常恢复 | **无法执行** | 权限受限，无法启动游戏进程 |
| T-E2E-2 | 怪物受到冻结伤害 → 解冻后移动动画正常恢复 | **无法执行** | 权限受限，无法启动游戏进程 |
| T-E2E-3 | 连续多次冻融循环不出现动画丢失 | **无法执行** | 权限受限，无法注入诊断脚本 |
| T-E2E-4 | 无冻结时移动行为不受影响（回归测试） | **无法执行** | 权限受限，无法注入诊断脚本 |

## 截图证据

- 截图文件路径：无
- 视觉描述：无 — 无法执行截图命令

## 发现的非阻塞问题

无

## 排障记录

### 步骤 1：首次启动尝试

使用 `tester-start-godot.sh` 启动游戏：
```bash
tester-start-godot.sh /Users/dluckdu/Documents/Github/gol gol-project/scenes/main.tscn --headless
```

**结果**：Godot 进程成功创建（PID: 30529），进程在运行。但等待 17 秒后调试桥超时：
```
Error: Timeout after 10s. Is the game running?
```

### 步骤 2：诊断分析

1. **日志检查** (`/tmp/godot_e2e.log`)：仅输出 Godot 版本行，无错误信息
2. **进程确认**：`ps aux` 确认 Godot 进程运行中
3. **信号目录检查**：`~/Library/Application Support/Godot/app_userdata/Godot of Lego/ai_signals/` **不存在**

### 步骤 3：根因定位

通过阅读 `ai-debug.mjs` 和 `ai_debug_bridge.gd` 源码，确认：

- AIDebugBridge 是 Autoload 单例，依赖 `project.godot` 正确加载
- `tester-start-godot.sh` 使用 `--path <workspace>` 即 `--path /Users/dluckdu/Documents/Github/gol`
- 但 `project.godot` 实际位于 `/Users/dluckdu/Documents/Github/gol/gol-project/project.godot`
- **`--path` 指向管理仓库根目录而非游戏项目目录，导致 Autoload 未加载**

正确启动命令应为：
```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/dluckdu/Documents/Github/gol/gol-project \
  gol-project/scenes/main.tscn --headless
```

### 步骤 4：权限阻塞

在尝试使用修正后的命令重新启动时，Bash 工具权限被拒绝：

> PermissionDeniedError: Permission to use Bash has been denied because this tool requires approval but permission prompts are not available in non-interactive mode.

这是非交互模式下不可恢复的权限限制。

## 结论

**`abort`**

### 具体理由

**无法完成可信的运行时 E2E 验收**，原因如下：

1. **环境初始化失败**：首次启动使用了错误的 `--path` 参数（指向管理仓库根目录而非 `gol-project/`），导致 AIDebugBridge Autoload 未被加载，IPC 信号目录未创建
2. **权限受限无法修复**：发现根因后需要重新启动游戏进程，但 Bash 工具权限被系统拒绝且处于非交互模式（无法弹出审批提示）
3. **无任何运行时证据**：未能获取诊断脚本输出、截图、或任何来自运行中游戏实例的数据
4. **不降级为静态分析验收**：遵循 E2E 行为准则，不给出 pass 或"基本通过"结论

### 建议

在具备 Bash 权限的环境下重新执行此验收任务。首次启动应确保 `--path` 参数指向 `gol-project/` 目录。
