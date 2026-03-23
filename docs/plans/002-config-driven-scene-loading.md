# Config-Driven Scene Loading 实施计划

> **目标：** 将 GOLWorld 的场景加载重构为配置驱动，统一生产关卡和集成测试的启动流程。
> **设计文档：** `docs/superpowers/specs/2026-03-21-integration-test-scene-loading-design.md`
> **工作目录：** 所有文件路径相对于 `gol-project/`

## 前置知识

- 设计文档包含所有代码细节和完整实现，实施时以设计文档为准
- `ECS.world = scene` 赋值会触发 `add_child()` → `_ready()` → `initialize()`，config 必须在此之前注入
- `null` 返回值 = 走默认行为（全量加载）
- 改动仅影响 3 个现有文件，其余为新增

## 依赖顺序

```
Task 1 (SceneConfig) ──┐
                        ├── Task 3 (GOLWorld 重构) ── Task 4 (Service_Scene) ── Task 5 (GOL.start_game)
Task 2 (TestResult)  ──┘                                                              │
                                                                                       ▼
                                                          Task 6 (test_main + l_test.tscn)
                                                                       │
                                                                       ▼
                                                          Task 7 (示例测试 + 验证)
                                                                       │
                                                                       ▼
                                                          Task 8 (Skill 更新)
                                                                       │
                                                                       ▼
                                                          Task 9 (收尾)
```

---

## Task 1: 创建 SceneConfig 基类

**文件：** `scripts/gameplay/ecs/scene_config.gd`（新建）
**依赖：** 无
**参考：** 设计文档 "SceneConfig — Universal Level Descriptor" 一节

### 要点
- `class_name SceneConfig extends RefCounted`
- 方法：`scene_name()`, `scene_path()`, `systems()`, `enable_pcg()`, `pcg_config()`, `entities()`, `test_run()`
- `pcg_config()` 必须缓存实例（`var _pcg_config`），避免多次调用返回不同对象导致 seed 丢失
- `test_run()` 默认返回 `null`，表示非测试场景

### 验收
- [ ] 文件存在，类名注册正确
- [ ] `pcg_config()` 多次调用返回同一实例
- [ ] 默认值：`systems()` → null, `enable_pcg()` → true, `entities()` → null, `test_run()` → null

---

## Task 2: 创建 TestResult 断言工具

**文件：** `scripts/tests/test_result.gd`（新建）
**依赖：** 无
**参考：** 设计文档 "TestResult" 一节

### 要点
- `class_name TestResult extends RefCounted`
- 方法：`assert_true()`, `assert_equal()`, `passed()`, `exit_code()`, `print_report()`
- `print_report()` 输出格式：`[PASS]` / `[FAIL]` 前缀，末尾统计 `=== N/M passed ===`
- `exit_code()` 返回 0（全通过）或 1（有失败）

### 验收
- [ ] 文件存在，类名注册正确
- [ ] stdout 输出格式便于 AI 和 CI 解析

---

## Task 3: 重构 GOLWorld.initialize() 为配置驱动

**文件：** `scripts/gameplay/ecs/gol_world.gd`（修改）
**依赖：** Task 1
**参考：** 设计文档 "GOLWorld.initialize()" 一节

### 改动清单

1. **新增** `var _config: SceneConfig = null` 和 `func set_config(config: SceneConfig)`
2. **重写** `initialize()`：按 config 分支走不同路径（详见设计文档）
3. **抽取** 现有硬编码逻辑到私有方法：
   - `_spawn_default_entities()` — 移入当前 `_spawn_player()`, `_spawn_campfire()`, `_spawn_initial_rifle()`, `_spawn_guards_at_campfire()`, `_spawn_enemy_spawners_at_pois()`, `_spawn_loot_boxes_at_building_pois()` 的调用
   - `_setup_pcg_map()` — 移入当前 PCG result → CMapData 实体创建逻辑（约 6 行）
4. **新增** `_load_systems_from_list(paths: Array)` — 按路径加载指定系统，包含 `ResourceLoader.exists()` 和 `can_instantiate()` 校验
5. **新增** `_spawn_entities_from_config(defs: Array)` — 从 recipe + component 覆盖创建实体
6. **新增** `_find_component_by_class_name(entity, class_name_str)` — 通过 `get_script().get_global_name()` 匹配组件

### 关键约束
- 当 `_config == null` 时，`initialize()` 行为必须和重构前完全一致
- 现有的 `_spawn_player()` / `_spawn_campfire()` 等方法保留不删，由 `_spawn_default_entities()` 调用
- `_load_all_systems()` 和 `_scan_system_scripts()` 保留不动

### 验收
- [ ] 不传 config 时行为不变（回归测试：启动生产关卡正常）
- [ ] `_spawn_entities_from_config` 能正确从 recipe 创建实体并覆盖组件属性
- [ ] `_load_systems_from_list` 能按路径加载指定系统

---

## Task 4: 重构 Service_Scene 统一 config 接口

**文件：** `scripts/services/impl/service_scene.gd`（修改）
**依赖：** Task 1, Task 3
**参考：** 设计文档 "Service_Scene" 一节

### 改动清单

1. **删除** `_pending_scene: String` 字段
2. **新增** `_pending_config: SceneConfig` 字段
3. **重写** `switch_scene(config: SceneConfig)` — 替代原来的 `switch_scene(scene_name: String)`
4. **新增** `_load_with_config(config: SceneConfig)` — 替代原来的 `_load()` 和 `_load_from_path()`
5. **修改** `_on_world_unloaded()` — 使用 `_pending_config` 而非 `_pending_scene`
6. **修改** `teardown()` — 清理 `_pending_config`
7. **保留** `scene_exist()`, `at_scene()`, `_unload()`, `_pop_ui_layers()` 基本不变

### 关键约束（CRITICAL）
- `_load_with_config()` 中：`scene.set_config(config)` 必须在 `ECS.world = scene` 之前
- `_on_world_unloaded()` 必须调用 `_load_with_config(_pending_config)`，不能调用旧的 `_load()`
- `_load_with_config()` 需先 `ResourceLoader.exists(scene_path)` 验证

### 验收
- [ ] `switch_scene(config)` 能正常加载场景
- [ ] 从已有场景切换到新场景（async unload 路径）正常工作
- [ ] teardown 清理干净，无泄漏

---

## Task 5: 修改 GOL.start_game() 使用 ProceduralConfig

**文件：** `scripts/gol.gd`（修改），`scripts/gameplay/configs/procedural_config.gd`（新建）
**依赖：** Task 1, Task 4
**参考：** 设计文档 "Production Config" 和 "GOL.start_game() Change" 两节

### 改动清单

1. **新建** `procedural_config.gd`：
   - `class_name ProceduralConfig extends SceneConfig`
   - `scene_name()` → `"procedural"`
   - `systems()` → null, `enable_pcg()` → true, `entities()` → null
2. **修改** `gol.gd` 的 `start_game()`：
   - 创建 `ProceduralConfig` 实例
   - `config.pcg_config().pcg_seed = randi()`（注意：利用 pcg_config() 缓存特性）
   - `ServiceContext.pcg().generate(config.pcg_config())`
   - `ServiceContext.scene().switch_scene(config)`

### 验收（关键回归测试点）
- [ ] 从 `main.tscn` 启动游戏，完整流程正常（PCG → 场景加载 → 玩家/敌人/篝火出现）
- [ ] `main.gd` 不需要任何改动

---

## Task 6: 创建测试入口和空白测试关卡

**文件：** `scripts/tests/test_main.gd`（新建），`scenes/tests/test_main.tscn`（新建），`scenes/maps/l_test.tscn`（新建）
**依赖：** Task 2, Task 5
**参考：** 设计文档 "Test Entry Point" 和 "Empty Test World Scene" 两节

### test_main.gd 要点
- 解析 `--config=` 和 `--no-exit` 命令行参数
- 加载配置脚本并验证类型（`is SceneConfig`）
- 调用 `GOL.setup()`，按 config 决定是否跑 PCG
- 调用 `ServiceContext.scene().switch_scene(config)`
- 等两帧后执行 `config.test_run(ECS.world)`
- 根据 `--no-exit` 决定是否 `get_tree().quit(exit_code)`
- `_exit_tree()` 调用 `GOL.teardown()`

### test_main.tscn
- 极简场景：一个 Node 根节点，挂载 `test_main.gd` 脚本
- 放在 `scenes/tests/` 目录

### l_test.tscn
- 根节点：`GOLWorld`（挂载 `gol_world.gd`）
- 子节点：空的 `Entities` 和 `Systems` 节点
- `entity_nodes_root` 和 `system_nodes_root` 指向对应子节点
- 无 Authoring 节点，无预置系统
- 放在 `scenes/maps/` 目录（遵循 `l_{name}.tscn` 命名约定）

### 验收
- [ ] 命令行启动：`godot --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/test_combat.gd` 正常执行
- [ ] 缺少 `--config` 参数时打印错误并退出 code=1
- [ ] `--no-exit` 参数使场景保持运行

---

## Task 7: 编写示例集成测试并端到端验证

**文件：** `tests/integration/test_combat.gd`（新建）
**依赖：** Task 6
**参考：** 设计文档 "Example Integration Test" 一节

### 示例测试内容
- `scene_name()` → `"test"`
- 加载 3 个战斗相关系统
- 不启用 PCG
- Spawn player 和 enemy_basic，指定位置
- `test_run()` 等待 1 秒后验证 player 存在且存活

### 端到端验证步骤
1. 生产流程回归：从 `main.tscn` 启动游戏，确认一切正常
2. 集成测试自动模式：运行示例测试，确认 stdout 输出测试报告，exit code 正确
3. 集成测试调试模式：加 `--no-exit`，确认场景保持运行
4. 错误处理：用无效 config 路径启动，确认优雅退出

### 验收
- [ ] 示例测试通过，输出 `=== 2/2 passed ===`
- [ ] exit code 为 0
- [ ] 生产流程回归通过

---

## Task 8: 更新 Skill 定义

**依赖：** Task 7
**参考：** 设计文档 "Skill Updates" 一节

### 8a: 更新 gol-e2e skill

**文件：** `.claude/skills/gol-e2e/SKILL.md`（修改）

改动要点：
- 新增集成测试场景作为 E2E 测试的可选启动方式
- 启动命令适配：`--scene scenes/tests/test_main.tscn -- --config=... --no-exit`
- 说明在集成测试场景中使用 AI Debug Bridge 的方式

### 8b: 新建 gol-integration skill

**文件：** `.claude/skills/gol-integration/SKILL.md`（新建）

内容：
- 集成测试的定位（与 GdUnit4 单元测试和 E2E 的关系）
- SceneConfig 文件的编写指南（配置字段说明、示例）
- 启动命令（自动模式 / 调试模式）
- 测试结果输出格式和 exit code 含义
- 常用 system 路径列表（方便 AI 快速选取）
- 常用 recipe ID 列表

### 验收
- [ ] gol-e2e skill 更新后兼容新旧两种启动方式
- [ ] gol-integration skill 内容完整，AI agent 能据此编写集成测试

---

## Task 9: 收尾

**依赖：** Task 7, Task 8

### 9a: 更新 AGENTS.md 文档

**文件：** `scripts/services/AGENTS.md`
- 更新 `switch_scene` 文档为 config-based API

### 9b: Release 排除配置

确认 `export_presets.cfg` 的 `exclude_filter` 包含：
```
tests/*, scripts/tests/*, scripts/debug/*, scenes/tests/*
```
如果文件不存在或尚未配置，记录为 TODO 待正式打包时处理。

### 9c: 提交和推送

- 在 `gol-project` 子模块内提交所有改动
- 更新主仓库的子模块引用
- 遵循原子推送原则：先推子模块，再推主仓库

### 验收
- [ ] AGENTS.md 文档准确反映新 API
- [ ] 所有测试/调试文件在 release 排除列表中
- [ ] git 状态干净，提交信息清晰
