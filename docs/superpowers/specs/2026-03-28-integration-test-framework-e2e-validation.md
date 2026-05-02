# 集成测试框架端到端验证方案

> Current usage note (2026-05-02): this historical validation plan predates the `gol` CLI wrapper. For current AI workflows, use `gol test integration`, `gol run game`, `gol stop`, and `gol debug ...` instead of direct Godot binary or raw `node ai-debug.mjs` commands.

> **目标：** 从用户视角全面验证新的 Config-Driven 集成测试框架的功能、边界和健壮性。
> **性质：** 纯测试方案，不涉及代码编写。按测试场景执行并记录结果。
> **前置条件：** `002` 和 `003` 计划均已完成实施。

## 测试环境

- 工作目录：`gol-project/`
- Godot 路径：`/Applications/Godot.app/Contents/MacOS/Godot`
- 测试入口：`scenes/tests/test_main.tscn`
- 可用配置：`tests/integration/test_combat.gd`、`tests/integration/test_area_effect.gd`、`tests/integration/test_pcg_map.gd`

---

## Phase 1: 基本启动验证

### T1.1 正常启动（自动模式）

```bash
godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_combat.gd
```

**预期：**
- [ ] stdout 输出 `[test_main] Loaded config: ...`
- [ ] stdout 输出 `=== TEST RESULTS ===`
- [ ] 所有断言显示 `[PASS]`
- [ ] 进程自动退出，exit code = 0

**验证 exit code：**
```bash
godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_combat.gd; echo "Exit: $?"
```

### T1.2 --no-exit 模式

```bash
godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_combat.gd --no-exit
```

**预期：**
- [ ] 测试结果正常输出
- [ ] 进程不退出，场景持续运行
- [ ] 窗口中可以看到渲染的实体
- [ ] 手动关闭窗口后进程正常退出

### T1.3 缺少 --config 参数

```bash
godot --path . --scene scenes/tests/test_main.tscn; echo "Exit: $?"
```

**预期：**
- [ ] stdout 输出 `[FAIL] Missing --config= argument`
- [ ] exit code = 1

### T1.4 无效 config 路径

```bash
godot --path . --scene scenes/tests/test_main.tscn -- --config=res://nonexistent.gd; echo "Exit: $?"
```

**预期：**
- [ ] stdout 输出 `[FAIL] Config script not found: ...`
- [ ] exit code = 1

### T1.5 config 不继承 SceneConfig

创建一个临时文件验证（如果有 `/tmp` 访问）。或用一个已知不继承 SceneConfig 的脚本路径。

**预期：**
- [ ] stdout 输出 `[FAIL] Config script does not extend SceneConfig`
- [ ] exit code = 1

---

## Phase 2: 各测试配置验证

### T2.1 test_combat.gd — 战斗系统测试

```bash
godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_combat.gd
```

**检查项：**
- [ ] 加载了指定的系统子集（不是全部系统）
- [ ] Player 和 Enemy 实体存在
- [ ] 测试断言通过
- [ ] PCG 未执行（`enable_pcg() = false`）

### T2.2 test_area_effect.gd — 范围效果测试

```bash
godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_area_effect.gd --no-exit
```

**检查项：**
- [ ] 5 个系统正确加载（SRenderView, SAnimation, SAreaEffect, SDamage, SUI_HPBar）
- [ ] 毒僵尸、治疗者、玩家、普通敌人等实体全部出现
- [ ] 毒僵尸附近的敌人 HP 在下降（范围效果生效）
- [ ] 治疗者附近的盟友 HP 保持/恢复
- [ ] PCG 未执行

### T2.3 test_pcg_map.gd — PCG 地图测试

```bash
godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_pcg_map.gd
```

**检查项（自动模式）：**
- [ ] PCG 执行成功
- [ ] CMapData 实体存在
- [ ] PCG result 有效
- [ ] 测试通过，exit code = 0

```bash
godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_pcg_map.gd --no-exit
```

**检查项（可视化模式）：**
- [ ] 等距地图正确渲染
- [ ] Camera2D 可用（场景不是黑屏）

---

## Phase 3: 生产流程回归

### T3.1 正式关卡启动

```bash
godot --path . --scene scenes/main.tscn
```

**检查项：**
- [ ] 游戏正常启动，无报错
- [ ] PCG 生成地图
- [ ] 玩家、篝火、守卫、敌人 spawner、宝箱全部出现
- [ ] ECS 系统正常运行（移动、战斗、AI）
- [ ] 行为与重构前完全一致

### T3.2 GdUnit4 单元测试

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ -c --ignoreHeadlessMode
```

**检查项：**
- [ ] 所有现有单元测试通过（ai/, flow/, system/, service/, pcg/）
- [ ] 无新增的测试失败
- [ ] integration/ 目录下的新测试文件不被 GdUnit4 扫描（它们 extends SceneConfig，不是 GdUnitTestSuite）

---

## Phase 4: AI Debug Bridge 兼容性

### T4.1 集成测试 + AI Debug Bridge

1. 启动集成测试（--no-exit 模式）：
```bash
godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_area_effect.gd --no-exit &
```

2. 等待场景加载后，通过 AI Debug Bridge 交互：
```bash
cd ../gol-tools/ai-debug
node ai-debug.mjs screenshot
node ai-debug.mjs get entity_count
node ai-debug.mjs eval "ECS.world.query.with_all([CHP]).execute().size()"
```

**检查项：**
- [ ] screenshot 成功捕获
- [ ] entity_count 返回正确数量
- [ ] eval 表达式执行成功
- [ ] AI Debug Bridge 与集成测试场景完全兼容

### T4.2 脚本注入

```bash
node ai-debug.mjs script /tmp/test_diag.gd
```

其中 `/tmp/test_diag.gd`：
```gdscript
extends Node
func run():
    var entities = ECS.world.query.with_all([CHP]).execute()
    var output = "entity_count=%d" % entities.size()
    for e in entities:
        output += "\n%s hp=%s" % [e.name, e.get_component(CHP).hp]
    return output
```

**检查项：**
- [ ] 脚本注入成功执行
- [ ] 返回了正确的实体信息

---

## Phase 5: 边界和健壮性

### T5.1 空系统列表

创建临时配置（或已有测试）：`systems()` 返回 `[]`

**预期：**
- [ ] 场景加载成功，但无系统处理
- [ ] 不崩溃

### T5.2 空实体列表

`entities()` 返回 `[]`

**预期：**
- [ ] 场景加载成功，无实体
- [ ] 不崩溃

### T5.3 无效 recipe ID

`entities()` 中包含 `{"recipe": "nonexistent_recipe"}`

**预期：**
- [ ] 输出 `push_error` 信息
- [ ] 跳过该实体，继续加载其他实体
- [ ] 不崩溃

### T5.4 无效系统路径

`systems()` 中包含 `"res://scripts/systems/nonexistent.gd"`

**预期：**
- [ ] 输出 `push_error` 信息
- [ ] 跳过该系统，继续加载其他系统
- [ ] 不崩溃

### T5.5 无效组件名

`entities()` 中包含不存在的组件覆盖：`{"recipe": "player", "components": {"CNonexistent": {"foo": 1}}}`

**预期：**
- [ ] 输出 `push_warning` 信息
- [ ] 实体正常创建（忽略无效覆盖）
- [ ] 不崩溃

### T5.6 headless 模式

```bash
godot --headless --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_combat.gd; echo "Exit: $?"
```

**预期：**
- [ ] headless 模式下测试正常执行
- [ ] 输出测试结果
- [ ] exit code 正确
- [ ] 这是 CI 的典型运行方式

---

## Phase 6: E2E Skill 集成

### T6.1 通过 gol-e2e skill 启动集成测试场景

模拟 E2E 测试流程：
1. 使用 `--no-exit` 启动某个集成测试配置
2. 通过 AI Debug Bridge 注入诊断脚本
3. 截图并验证
4. 关闭游戏

**检查项：**
- [ ] 完整 E2E 流程适配新的启动方式
- [ ] gol-e2e skill 文档中的命令可以正确启动集成测试场景

---

## 结果记录模板

每个测试项记录：

| 编号 | 状态 | 备注 |
|------|:---:|------|
| T1.1 | PASS/FAIL | |
| T1.2 | PASS/FAIL | |
| ... | ... | ... |

总结：
- 通过：N / 总计
- 失败项及原因：
- 需要修复的问题：
