# AI Debug 工具链测试覆盖计划

> **目标：** 为 ai-debug 工具链的三层架构（CLI → Bridge → Console）建立全面的自动化测试，覆盖单元测试、集成测试和端到端测试。

## 现状分析

| 组件 | 文件 | 现有测试 | 覆盖率 |
|------|------|----------|--------|
| Console 命令服务 | `gol-project/scripts/services/impl/service_console.gd` | 仅 `cmd_dmg` 有测试（foreman workspace） | ~5% |
| AIDebugBridge IPC | `gol-project/scripts/debug/ai_debug_bridge.gd` | 2 个 E2E bash 脚本 | E2E 覆盖主路径 |
| CLI 工具 | `gol-tools/ai-debug/ai-debug.mjs` | 无 | 0% |

## 架构层次与测试策略

```
┌─────────────────────────────────────────────────┐
│  ai-debug.mjs (CLI)                             │  ← Node.js 单元测试
│  parseFlags / buildScreenshotOpts / routing      │
├─────────────────────────────────────────────────┤
│  ai_debug_bridge.gd (IPC + Screenshot)          │  ← GdUnit4 集成测试
│  JSON 解析 / 文件协议 / 截图编排 / capture 生命周期│
├─────────────────────────────────────────────────┤
│  service_console.gd (命令框架)                   │  ← GdUnit4 单元测试
│  execute() / 命令注册 / 参数解析 / 各 cmd_* 方法  │
└─────────────────────────────────────────────────┘
```

## 运行方式

```bash
# GdUnit4 单元/集成测试（CI 自动运行）
cd gol-project
~/godot/godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add res://tests/ --ignoreHeadlessMode --verbose

# Node.js CLI 单元测试
cd gol-tools/ai-debug
node --test tests/**/*.test.mjs

# E2E 测试（需要游戏运行）
bash gol-tools/ai-debug/e2e_test_screenshot_upgrade.sh
bash gol-tools/ai-debug/e2e_test_script_injection.sh
```

---

## Task 1: Console 命令框架单元测试

**文件：** `gol-project/tests/unit/service/test_service_console.gd`
**模式：** 参考 `tests/unit/service/test_service_ui.gd` — 服务实例化 + auto_free

### 1.1 核心框架测试

- [ ] **命令注册** — setup() 后 `_commands` 包含所有 `cmd_*` 方法
- [ ] **get_command_names()** — 返回排序后的命令列表，与 `_commands.keys()` 一致
- [ ] **get_completions()** — 空字符串返回全部、"he" 匹配 "heal"/"help"、"zzz" 返回空

### 1.2 execute() 参数解析测试

- [ ] **空输入** — `execute("")` 返回空字符串
- [ ] **未知命令** — `execute("nonexistent")` 返回 "Unknown command: ..."
- [ ] **无参数命令** — `execute("hp")` 正确调用 `cmd_hp()`
- [ ] **单参数命令** — `execute("heal full")` 正确传入 "full"
- [ ] **双参数命令** — `execute("tp 100 200")` 正确传入 "100", "200"
- [ ] **多余 token 合并到最后参数** — `execute("eval 1 + 1")` 传入 "1 + 1"（非 "1", "+", "1"）
- [ ] **大小写不敏感** — `execute("HELP")` 等同于 `execute("help")`
- [ ] **前后空白** — `execute("  heal  full  ")` 正确解析

### 1.3 各命令功能测试

需要 ECS World 的命令需要 `GOL.setup()` / `GOL.teardown()` 配合测试实体。

**不依赖 ECS 的命令：**
- [ ] **cmd_help()** — 无参数返回所有命令列表、带参数返回指定命令帮助
- [ ] **cmd_help("nonexistent")** — 返回 "Unknown command: ..."
- [ ] **cmd_eval("1 + 1")** — 返回 "2"（注：eval 是 debug-only 命令，仅在开发环境使用）
- [ ] **cmd_eval("")** — 返回错误信息
- [ ] **cmd_eval("invalid expression ===")** — 返回 "Parse error: ..."
- [ ] **cmd_refresh("all")** — 返回包含 "reloaded" 的结果（需 ServiceContext.recipe() 可用）

**依赖 ECS 的命令（before_test 创建测试 World + 实体）：**
- [ ] **cmd_hp()** — 返回 "Player HP: {hp}/{max_hp}"
- [ ] **cmd_hp() 无玩家** — 返回 "Error: Player not found"
- [ ] **cmd_pos()** — 返回 "Player position: (x, y)"
- [ ] **cmd_heal("full")** — 将 HP 恢复到 max_hp
- [ ] **cmd_heal("50")** — HP 增加 50，不超过 max_hp
- [ ] **cmd_heal("invalid")** — 返回 "Invalid amount: ..."
- [ ] **cmd_god()** — 切换无敌模式，HP 变为 99999
- [ ] **cmd_god() 再次调用** — 关闭无敌，HP 恢复正常值
- [ ] **cmd_count()** — 返回实体总数
- [ ] **cmd_count("enemy")** — 返回匹配实体数
- [ ] **cmd_kill("enemy")** — 匹配实体添加 CDead 组件
- [ ] **cmd_kill("nonexistent")** — 返回 "No entities matched..."
- [ ] **cmd_list()** — 返回实体列表（最多 20 个）
- [ ] **cmd_tp("100", "200")** — 玩家位置更新
- [ ] **cmd_tp("", "")** — 返回 "Usage: tp <x> <y>"
- [ ] **cmd_time()** — 返回当前时间
- [ ] **cmd_time("12")** — 设置到正午
- [ ] **cmd_time("25")** — 返回 "Hour must be between 0 and 24"
- [ ] **cmd_night() / cmd_day()** — 设置时间

### 1.4 测试辅助工具

```gdscript
# tests/unit/service/console_test_utils.gd
class_name ConsoleTestUtils

static func create_player_entity(hp: int = 100, max_hp: int = 100, pos: Vector2 = Vector2.ZERO) -> Entity:
    var entity := Entity.new()
    var player := CPlayer.new()
    entity.add_component(player)
    var camp := CCamp.new()
    camp.camp = CCamp.CampType.PLAYER
    entity.add_component(camp)
    var hp_comp := CHP.new()
    hp_comp.hp = hp
    hp_comp.max_hp = max_hp
    entity.add_component(hp_comp)
    var transform := CTransform.new()
    transform.position = pos
    entity.add_component(transform)
    return entity

static func create_enemy_entity(name_str: String = "Goblin") -> Entity:
    var entity := Entity.new()
    entity.name = name_str
    var agent := CGoapAgent.new()
    entity.add_component(agent)
    var camp := CCamp.new()
    camp.camp = CCamp.CampType.ENEMY
    entity.add_component(camp)
    var hp := CHP.new()
    hp.hp = 50
    hp.max_hp = 50
    entity.add_component(hp)
    return entity
```

---

## Task 2: CLI 纯函数单元测试

**文件：** `gol-tools/ai-debug/tests/ai-debug.test.mjs`
**框架：** `node:test` + `node:assert`（与 foreman 测试保持一致）

需要先创建 `gol-tools/ai-debug/package.json`:

```json
{
  "name": "ai-debug",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "test": "node --test tests/**/*.test.mjs"
  }
}
```

### 2.1 parseFlags() 测试

- [ ] **空数组** — 返回 `{ flags: {}, positional: [] }`
- [ ] **纯 positional** — `["heal", "full"]` → `positional: ["heal", "full"]`
- [ ] **--screenshot** — 设置 `flags.screenshot = true`
- [ ] **-s 短标记** — 等同于 `--screenshot`
- [ ] **--delay 3** — `flags.delay = 3`
- [ ] **-d 3 短标记** — 等同于 `--delay 3`
- [ ] **--count 5** — `flags.count = 5`
- [ ] **--interval 0.5** — `flags.interval = 0.5`
- [ ] **混合参数** — `["heal", "full", "--screenshot", "--delay", "2"]` → positional + flags 均正确
- [ ] **非法 delay 值** — `--delay abc` → `flags.delay = 0`（parseFloat fallback）

### 2.2 buildScreenshotOpts() 测试

- [ ] **空 flags** — 返回空对象 `{}`
- [ ] **有 delay** — 返回 `{ delay: N }`
- [ ] **全部参数** — `{ delay, count, interval }` 均传递
- [ ] **无 screenshot 标记的 flags** — 不含截图参数时返回空

### 2.3 calculateTimeout() 测试

- [ ] **默认值** — `{}` → `DEFAULT_TIMEOUT`（10s）
- [ ] **带 delay** — `{ delay: 5 }` → `5 + 0 + 10 = 15`
- [ ] **多帧** — `{ count: 3, interval: 2 }` → `0 + 2*2 + 10 = 14`
- [ ] **完整参数** — `{ delay: 2, count: 5, interval: 1 }` → `2 + 4*1 + 10 = 16`

### 2.4 命令路由测试

测试 main() 中 switch 路由逻辑。需要提取为可测试的纯函数（见 Task 4）。

- [ ] **screenshot** — `{ type: "bridge", payload: { cmd: "screenshot", args: {...} } }`
- [ ] **fetch cap_123** — `{ type: "bridge", payload: { cmd: "fetch", args: { capture_id: "cap_123" } } }`
- [ ] **script foo.gd** — `{ type: "script", path: "foo.gd" }`
- [ ] **reimport** — `{ type: "reimport" }`
- [ ] **heal full** — `{ type: "bridge", payload: { cmd: "heal", args: ["full"] } }`
- [ ] **console heal full（向后兼容）** — 解包为 `{ cmd: "heal", args: ["full"] }`
- [ ] **console（无参数）** — 错误
- [ ] **time --screenshot** — payload 包含 `screenshot` 字段

### 2.5 formatResult() 测试

- [ ] **字符串** — 直接输出
- [ ] **JSON 带 result** — 输出 result 值
- [ ] **JSON 带数组 result** — 逐行输出
- [ ] **JSON 带 capture_id** — 输出 `capture_id:xxx`
- [ ] **JSON 带 pending status** — 输出 pending + progress
- [ ] **JSON 带 error** — 输出错误信息
- [ ] **result 为 null** — 不输出 result 行

---

## Task 3: Bridge IPC 集成测试

**文件：** `gol-project/tests/unit/debug/test_ai_debug_bridge.gd`
**性质：** 集成测试 — 需要 SceneTree 运行（bridge 使用 `get_tree().create_timer()`）

Bridge 的核心逻辑是文件 I/O + 异步截图编排，直接在 GdUnit4 中测试有限制（截图依赖渲染帧）。
可测试部分聚焦于 JSON 协议解析和 capture 生命周期管理。

### 3.1 JSON 协议解析测试

测试 `_execute_command_json()` 的分发逻辑（mock 掉 sendCommand 和 screenshot）：

- [ ] **空 cmd 字段** — 返回 error JSON
- [ ] **screenshot cmd** — 调用截图路径（验证不走 console）
- [ ] **fetch cmd** — 调用 fetch 路径
- [ ] **普通命令转发** — `{cmd: "help", args: []}` → 构建 "help" 传给 console
- [ ] **带 args 的命令** — `{cmd: "heal", args: ["full"]}` → 构建 "heal full"
- [ ] **piggyback screenshot** — 命令带 `screenshot` 字段时返回 capture_id

### 3.2 Capture 生命周期测试

- [ ] **_generate_capture_id()** — 返回 `cap_` 前缀 + 毫秒时间戳
- [ ] **_parse_screenshot_opts()** — delay/count/interval 范围 clamp 正确
- [ ] **_parse_screenshot_opts() 超限值** — delay > 30 被 clamp 到 30，count > 20 被 clamp 到 20
- [ ] **_schedule_piggyback_screenshot()** — 创建 pending capture entry
- [ ] **_handle_fetch_json() pending 状态** — 返回 `{status: "pending", progress: "0/N"}`
- [ ] **_handle_fetch_json() ready 状态** — 返回 `{status: "ready", result: [paths]}`
- [ ] **_handle_fetch_json() 不存在的 id** — 返回 error
- [ ] **_cleanup_expired_captures()** — 过期 ready capture 被移除
- [ ] **_cleanup_expired_captures()** — 卡住的 pending capture 在超时后被移除

### 3.3 IPC 文件协议测试

- [ ] **_ensure_signal_dir()** — 创建 ai_signals 目录
- [ ] **_cleanup_stale_files()** — 清理残留文件
- [ ] **_write_result()** — 写入结果文件
- [ ] **_write_json_result()** — JSON 序列化后写入
- [ ] **命令守卫超时** — `_command_in_progress` 超过 240s 后自动重置

---

## Task 4: 重构 CLI 以支持可测试性

当前 `ai-debug.mjs` 的 `main()` 将路由逻辑和 I/O 耦合在一起。需要提取纯函数才能进行有效的单元测试。

**文件修改：** `gol-tools/ai-debug/ai-debug.mjs`

### 4.1 提取纯函数

- [ ] 将 `parseFlags`、`buildScreenshotOpts`、`calculateTimeout`、`formatResult` 导出为 named export
- [ ] 新增 `resolveCommand(cmd, positional, flags)` 纯函数，返回 `{ type, payload }` 对象
- [ ] `main()` 调用 `resolveCommand()` 然后根据 type 执行 I/O

```javascript
// 从 main() switch 提取的纯路由逻辑
export function resolveCommand(cmd, positional, flags) {
    switch (cmd) {
        case 'screenshot':
            return { type: 'bridge', payload: { cmd: 'screenshot', args: buildScreenshotOpts(flags) } };
        case 'fetch':
            if (positional.length === 0) return { type: 'error', message: 'capture_id required' };
            return { type: 'bridge', payload: { cmd: 'fetch', args: { capture_id: positional[0] } } };
        case 'script':
            if (positional.length === 0) return { type: 'error', message: 'script file required' };
            return { type: 'script', path: positional[0] };
        case 'reimport':
            return { type: 'reimport' };
        default: {
            let actualCmd = cmd;
            let actualArgs = positional;
            if (cmd === 'console') {
                if (positional.length === 0) return { type: 'error', message: 'console command required' };
                actualCmd = positional[0];
                actualArgs = positional.slice(1);
            }
            const payload = { cmd: actualCmd, args: actualArgs };
            if (flags.screenshot) payload.screenshot = buildScreenshotOpts(flags);
            return { type: 'bridge', payload };
        }
    }
}
```

### 4.2 添加 package.json 和测试脚本

- [ ] 创建 `gol-tools/ai-debug/package.json`
- [ ] 创建 `gol-tools/ai-debug/tests/` 目录
- [ ] 验证 `npm test` 可以运行

---

## Task 5: E2E 测试增强

**文件：** `gol-tools/ai-debug/e2e_test_refactoring.sh`
**前提：** 游戏必须运行

现有 E2E 测试覆盖截图功能。需要为重构后的新架构增加验证。

### 5.1 直接命令测试

- [ ] **help** — 返回命令列表
- [ ] **hp** — 返回 "Player HP: ..."
- [ ] **pos** — 返回 "Player position: ..."
- [ ] **time** — 返回 "Current time: ..."
- [ ] **time 12** — 返回 "Time set to 12.0:00"
- [ ] **heal full** — 返回 "Healed player to full ..."
- [ ] **count** — 返回 "Entities: N"
- [ ] **eval 1+1** — 返回 "2"
- [ ] **eval 2 * 3** — 返回 "6"（多词表达式）

### 5.2 向后兼容测试

- [ ] **console heal full** — 等同于 `heal full`
- [ ] **console time** — 等同于 `time`

### 5.3 错误处理测试

- [ ] **nonexistent_cmd** — 返回 "Unknown command: ..."
- [ ] **fetch（无参数）** — CLI 报错退出
- [ ] **script nonexistent.gd** — CLI 报错 "Script not found"

---

## Task 6: CI 集成

### 6.1 GdUnit4（已有 CI）

现有 `run-tests.yml` 会自动发现 `tests/` 下的新测试文件，无需额外配置。

- [ ] 确认新增的 `test_service_console.gd` 和 `test_ai_debug_bridge.gd` 在 CI 中被发现并运行

### 6.2 Node.js CLI 测试（新增）

- [ ] 在 `run-tests.yml` 或新 workflow 中添加 Node.js 测试步骤：

```yaml
- name: Run AI Debug CLI Tests
  working-directory: gol-tools/ai-debug
  run: npm test
```

---

## 执行顺序

| 顺序 | Task | 投入产出比 | 依赖 |
|------|------|-----------|------|
| 1 | Task 4: 重构 CLI 可测试性 | 高 — 解锁 Task 2 | 无 |
| 2 | Task 2: CLI 纯函数单元测试 | 高 — 无需游戏运行 | Task 4 |
| 3 | Task 1: Console 命令单元测试 | 高 — 核心逻辑覆盖 | 无 |
| 4 | Task 3: Bridge 集成测试 | 中 — 部分逻辑需要 SceneTree | 无 |
| 5 | Task 5: E2E 测试增强 | 中 — 需要游戏运行 | Task 1-4 |
| 6 | Task 6: CI 集成 | 低 — GdUnit4 已自动发现 | Task 1-3 |

## 预期成果

完成后测试覆盖从 ~5% 提升至：
- **Console 命令框架：** ~90%（核心解析 + 大部分命令）
- **CLI 纯函数：** ~95%（parseFlags / routing / formatResult）
- **Bridge 协议层：** ~60%（JSON 解析 + capture 生命周期，截图渲染依赖跳过）
- **端到端：** 覆盖所有用户可见的命令和错误路径
