# 旧 Controller 清理与新架构迁移

> **目标：** 将旧的 Debug Controller 测试场景完全迁移到 SceneConfig 架构，同时将有价值的 PCG 调试工具并入主 DebugPanel，清理遗留代码。
> **前置条件：** `002-config-driven-scene-loading.md` 已完成实施
> **工作目录：** 所有文件路径相对于 `gol-project/`

## 待处理的旧文件

| 文件 | 行数 | 处置 |
|------|:---:|------|
| `scripts/debug/area_effect_test_controller.gd` | 184 | 删除，迁移到 SceneConfig |
| `scripts/debug/pcg_phase_debug_controller.gd` | 647 | 删除，Tile 检视功能并入 DebugPanel |
| `scripts/debug/pcg_phase_inspector.gd` | 224 | 重构为 MapDebugger，并入 DebugPanel |
| `scenes/tests/l_test_area_effect.tscn` | 46 | 删除 |
| `scenes/tests/l_test_pcg.tscn` | 11 | 删除 |

## 依赖顺序

```
Task 1 (AreaEffect 迁移) ──┐
Task 2 (PCG 测试迁移)    ──┼── Task 5 (删除旧文件) ── Task 6 (提交)
Task 3 (MapDebugger)     ──┤
Task 4 (l_test Camera)   ──┘
```

Task 1/2/3/4 可并行执行。

---

## Task 1: 迁移 AreaEffectTestController

**新建：** `tests/integration/test_area_effect.gd`
**参考：** `area_effect_test_controller.gd` 中的系统列表和实体 spawn 逻辑

### 迁移映射

| 原 Controller 行为 | SceneConfig 等价 |
|---|---|
| `ServiceContext.static_setup(root)` | `test_main.gd` 中 `GOL.setup()` 自动完成 |
| `World.new()` + `ECS.world = world` | `switch_scene(config)` 加载 `l_test.tscn` |
| 手动 `add_system(SRenderView.new())` 等 5 个 | `systems()` 返回路径数组 |
| 手动 `_process()` 调用 `ECS.process()` | `GOLWorld._process()` 已内置 |
| `create_entity_by_id("enemy_poison")` + position | `entities()` 中 recipe + CTransform 覆盖 |

### 需要确认的系统路径

在编写 `systems()` 前，先确认这 5 个系统的实际文件路径：
- `SRenderView` → `res://scripts/systems/render/s_render_view.gd`（需确认）
- `SAnimation` → `res://scripts/systems/render/s_animation.gd`（需确认）
- `SAreaEffect` → `res://scripts/systems/gameplay/s_area_effect.gd`（需确认）
- `SDamage` → `res://scripts/systems/gameplay/s_damage.gd`（需确认）
- `SUI_HPBar` → `res://scripts/systems/ui/s_ui_hp_bar.gd`（需确认）

用 `grep -r "class_name SRenderView" scripts/systems/` 等命令确认正确路径。

### 实体定义

从 `_spawn_test_entities()` 提取 4 组测试场景的实体配置：

1. **毒僵尸测试区**：1 个 `enemy_poison` + 3 个 `enemy_basic`（半径 30-60 内随机分布）
2. **治疗者测试区**：1 个 `survivor_healer` + 2 个 `survivor`
3. **玩家位置**：1 个 `player`（治疗者范围内）
4. **混合阵营**：1 个 `survivor_healer` + 1 个 `enemy_basic` + 1 个 `enemy_poison`

注意：原 controller 使用 `get_viewport_rect().size / 2` 计算 center，SceneConfig 中需要用固定坐标值。可参考原场景的 Camera2D 位置 (480, 270) 作为 center。

### test_run（可选）

原 controller 是纯可视化验收，无自动断言。两种选择：
- **A)** `test_run()` 返回 null（仅可视化，用 `--no-exit` 启动人工观察）
- **B)** 添加基础断言（等待 2 秒后验证：毒僵尸附近敌人 HP 降低，治疗者附近盟友 HP 不低于 max）

建议先 A，后续按需补充断言。

### 验收
- [ ] `--no-exit` 模式启动后，能看到实体正确渲染和范围效果生效
- [ ] 毒僵尸伤害附近敌人，治疗者治疗附近盟友
- [ ] 行为与旧 `l_test_area_effect.tscn` 一致

---

## Task 2: 迁移 PCG 测试场景到 SceneConfig

**新建：** `tests/integration/test_pcg_map.gd`
**设计思路：** 走完整 PCG 流程 + SMapRender 渲染地图，作为集成测试用例

### SceneConfig 实现

```gdscript
# tests/integration/test_pcg_map.gd
extends SceneConfig

func scene_name() -> String:
    return "test"

func systems() -> Variant:
    return [
        "res://scripts/systems/render/s_map_render.gd",  # 需确认路径
    ]

func enable_pcg() -> bool:
    return true  # 走完整 PCG 流程

func entities() -> Variant:
    return []  # 不 spawn 任何游戏实体，纯地图

func test_run(world: GOLWorld) -> Variant:
    await world.get_tree().create_timer(0.5).timeout
    var result := TestResult.new()
    var map_entities = ECS.world.query.with_all([CMapData]).execute()
    result.assert_true(map_entities.size() > 0, "Map entity exists")
    if map_entities.size() > 0:
        var map_data: CMapData = map_entities[0].get_component(CMapData)
        result.assert_true(map_data.pcg_result != null, "PCG result is not null")
        result.assert_true(map_data.pcg_result.is_valid(), "PCG result is valid")
    return result
```

### 注意事项

1. **PCG 在 test_main.gd 中执行**：`enable_pcg() = true` 触发 `ServiceContext.pcg().generate()`，结果缓存在 `ServiceContext.pcg().last_result`
2. **_setup_pcg_map() 自动创建 CMapData**：GOLWorld.initialize() 检测到 PCG 结果后自动创建 map entity
3. **SMapRender 需要完整 PCG 结果**：确认 `pcg_result.is_valid()` 在 grid 存在时返回 true

### 验收
- [ ] 自动模式：PCG 生成成功，测试通过，exit code = 0
- [ ] `--no-exit` 模式：能看到完整的等距地图渲染
- [ ] 行为等价于旧 controller 执行 `run_all_phases()` 后的最终效果

---

## Task 3: 创建 MapDebugger — 将 PCG Tile 检视并入主 DebugPanel

**核心思路：** 将 `pcg_phase_inspector.gd` 中的 Tile 信息检视功能提取为正式的 `MapDebugger`，遵循 DebugPanel 现有架构模式（RefCounted + `draw()` 方法），作为生产环境的通用地图调试工具。

### 架构模式参考

DebugPanel 已有的模式：
```
DebugPanel (autoload, Node)
├── ECSDebugger (RefCounted) — draw() 渲染 ImGui 内容
├── GoapDebugger (RefCounted) — draw() 渲染 ImGui 内容
├── ConsolePanel (RefCounted) — draw() 渲染 ImGui 内容
└── [新增] MapDebugger (RefCounted) — draw() 渲染 Tile 检视
```

### 从旧代码保留的能力

| 功能 | 来源 | 保留原因 |
|---|---|---|
| **Tile 信息检视**（鼠标 hover 显示 tile 数据） | `pcg_phase_inspector.gd` 的 `_draw_hovered_tile_info()` | 核心调试价值：查看任意 tile 的 road type、terrain、zone、POI |
| **Crosswalk 验证 overlay**（彩色标记显示 crosswalk 正确/错误） | `pcg_phase_debug_controller.gd` 的 crosswalk overlay 逻辑 | PCG 调试必备，快速发现 crosswalk 放置问题 |

### 放弃的能力

| 功能 | 原因 |
|---|---|
| ~~逐 phase 步进~~ | 正式环境中 PCG 已完整生成，无需步进 |
| ~~phase 列表和导航按钮~~ | 同上 |
| ~~seed/grid_size 控制~~ | 正式环境通过 PCGConfig 配置 |
| ~~键盘快捷键（方向键步进、R 重置、G 重新生成）~~ | PCG 调试专用，不属于通用工具 |
| ~~独立 ImGui 窗口~~ | 并入 DebugPanel，不再独立 |
| ~~POI markers（ColorRect 节点）~~ | Tile 检视已包含 POI 信息，无需额外可视化 |
| ~~Camera 控制（WASD）~~ | 正式游戏已有 camera 跟随逻辑 |

### 新建文件

**`scripts/debug/map_debugger.gd`** — RefCounted，内容渲染器

核心职责：
1. **Tile 信息面板**：从 `ECS.world` 查询 `CMapData`，根据鼠标位置获取对应 tile 的 `PCGCell` 数据，在 ImGui 中显示：
   - Grid 坐标
   - Road type（NONE / ROAD / JUNCTION 等）
   - Terrain type
   - Zone type（WILDERNESS / SUBURBS / URBAN）
   - POI type（如果有）
   - Tile ID 和 variant
2. **Crosswalk overlay 开关**：提供一个 ImGui Checkbox，切换 crosswalk 验证 overlay 的显示

实现要点：
- `draw()` 方法：渲染 ImGui 内容（tile info + overlay 开关）
- 需要引用屏幕坐标到 grid 坐标的转换逻辑（从 `pcg_phase_debug_controller.gd` 的 `_update_tile_highlight` 提取）
- Crosswalk overlay 的渲染需要一个 TileMapLayer 节点 — 可由 DebugPanel 在 `_ensure_debuggers_initialized()` 中创建并作为 child 管理

### 修改文件

**`scripts/debug/debug_panel.gd`** — 注册 MapDebugger

改动点（遵循 ECSDebugger/GoapDebugger 的相同模式）：
1. 新增 `_map_debugger` 变量和 `_map_debugger_visible` 状态
2. `_ensure_debuggers_initialized()` 中懒加载 `MapDebugger`
3. 主面板中添加 "Map" toggle 按钮（与 "ECS" / "GOAP" 按钮并列）
4. 新增 `_draw_map_debugger_window()` 管理 ImGui 窗口
5. 窗口位置/大小持久化到 `debug_panel.cfg`

### Crosswalk Overlay 渲染方案

Crosswalk overlay 需要在游戏世界中渲染 TileMapLayer（不是 ImGui 内容）。两种方案：

**A) DebugPanel 管理 overlay 节点**
- DebugPanel 在初始化 MapDebugger 时创建 TileMapLayer 并 add_child 到 scene tree
- MapDebugger 持有引用，在 `draw()` 中通过 Checkbox 控制 visible
- Teardown 时清理

**B) MapDebugger 自身管理节点**（需要改为 extends Node）
- 不符合现有 RefCounted 模式，不推荐

建议 A — 保持 RefCounted 模式一致性。DebugPanel 已经有管理 `EntityHighlight` (Node2D) 的先例。

### Tile 坐标转换

从 `pcg_phase_debug_controller.gd` 提取的关键逻辑：
- 等距坐标转换：`_world_to_iso()` / TileMapLayer 的 `local_to_map()`
- 需要 TileSet 配置：`tile_shape = ISOMETRIC`, `tile_layout = DIAMOND_DOWN`, `tile_size = Vector2i(64, 32)`
- Highlight overlay 也是一个 TileMapLayer，跟随鼠标高亮当前 tile

MapDebugger 可以复用 SMapRender 已有的 TileMapLayer（如果可访问），或创建一个透明的 overlay layer 用于 highlight + crosswalk 标记。

### 安全约束

- MapDebugger 必须检查 `ECS.world` 和 `CMapData` 是否存在，不存在时显示 "No map data"
- ImGui 可用性检查：`ClassDB.class_exists("ImGuiController")`（DebugPanel 已统一处理）
- Release 构建中 DebugPanel 和 MapDebugger 通过 `scripts/debug/*` 排除规则一并排除

### 验收
- [ ] 正式游戏中按 `~` 打开 DebugPanel，能看到 "Map" 按钮
- [ ] 点击 "Map" 打开 MapDebugger 窗口
- [ ] 鼠标悬停地图上的 tile 时，ImGui 面板实时显示该 tile 的 PCGCell 信息
- [ ] Crosswalk overlay checkbox 能切换 crosswalk 验证标记的显示
- [ ] 无 CMapData 时（如非 PCG 关卡）显示 "No map data"，不崩溃
- [ ] 窗口位置/大小跨会话持久化

---

## Task 4: l_test.tscn 补充 Camera2D

**文件：** `scenes/maps/l_test.tscn`（修改）

在通用测试关卡中添加默认 Camera2D：
- Position: `Vector2(0, 0)`
- Zoom: `Vector2(1, 1)`（默认）
- 不影响自动测试（Camera 只在有渲染时生效）
- 为 `--no-exit` 可视化模式提供基础视角

### 验收
- [ ] 所有现有集成测试不受影响
- [ ] `--no-exit` 模式能正常显示场景内容

---

## Task 5: 删除旧文件

**依赖：** Task 1、2、3 验收通过后执行

### 删除清单

```bash
# Debug Controllers（测试场景 controller）
rm scripts/debug/area_effect_test_controller.gd
rm scripts/debug/pcg_phase_debug_controller.gd

# pcg_phase_inspector.gd — 核心功能已迁移到 map_debugger.gd，删除旧文件
rm scripts/debug/pcg_phase_inspector.gd

# 旧测试场景
rm scenes/tests/l_test_area_effect.tscn
rm scenes/tests/l_test_pcg.tscn
```

### 检查引用

删除前确认无其他代码引用这些文件：

```bash
grep -r "area_effect_test_controller\|AreaEffectTestController" scripts/ scenes/ tests/
grep -r "pcg_phase_debug_controller\|PCGPhaseDebugController" scripts/ scenes/ tests/
grep -r "pcg_phase_inspector\|PCGPhaseInspector" scripts/ scenes/ tests/
grep -r "l_test_area_effect\|l_test_pcg" scripts/ scenes/ tests/
```

已知引用需更新：
- `crosswalk_layout_integration_test.gd` 注释中提及 PCGPhaseDebugController → 更新注释引用 MapDebugger
- `tile_set_builder.gd` 注释中提及 PCGPhaseDebugController → 更新注释

### 验收
- [ ] 所有旧文件已删除
- [ ] `grep` 确认无残留引用（注释引用已更新）
- [ ] Godot 编辑器打开项目无报错
- [ ] 生产流程（从 main.tscn 启动）正常
- [ ] GdUnit4 单元测试全部通过
- [ ] MapDebugger 在正式游戏中正常工作

---

## Task 6: 提交

- 在 `gol-project` 子模块内提交所有改动
  - 新增：`tests/integration/test_area_effect.gd`、`tests/integration/test_pcg_map.gd`、`scripts/debug/map_debugger.gd`
  - 修改：`scripts/debug/debug_panel.gd`、`scenes/maps/l_test.tscn`
  - 删除：5 个旧文件
  - 更新：相关注释引用
- 更新主仓库子模块引用
- 遵循原子推送原则
