# Issue #193: 角色死亡后无法复活 — Round 2 分支评估

## 需求分析

**Issue 症状：** 角色死亡后摄像机被重置到无人位置，玩家卡死无法操作，无复活流程。

**期望行为：** 死亡后倒计时，在出生点复活，重新获得控制权。

**根因（前一轮确认）：** `_respawn_player()` 中 `create_entity_by_id` + `add_entity` 的 double-add bug，导致新实体被 `queue_free()`，Camera2D 随之销毁。

---

## 分支变更摘要

**分支：** `foreman/issue-193`
**相对 main 的 commit 数：** 4 个

| Commit | 描述 |
|--------|------|
| `f2da2b0` | fix(player): fix death respawn camera bug and add 5s countdown UI (#193) |
| `617e805` | fix(player): replace animation-gated death with timeout-based respawn (#193) |
| `7a16f50` | fix(s_dead, view_death_countdown): fix Critical runtime bugs from PR #221 review |
| `13c2384` | feat(#193): 角色死亡后无法复活 — iteration 1 |

**变更规模：** 33 个文件，+722 / -552 行

---

## 核心修复验证（3 项逐项确认）

### 修复 1：`_respawn_player()` 删除冗余 `add_entity` 调用

**状态：✅ 已修复**

`scripts/gameplay/gol_game_state.gd` 中当前 `_respawn_player()` 不包含 `ECS.world.add_entity(new_player)` 调用。`_respawn_player()` 现在仅有：
- `_pop_death_countdown_ui()` 调用
- `_find_campfire_position()`
- `create_entity_by_id("player")` 创建新实体
- 设置 `transform.position` 和 `hp.invincible_time`

前一轮 rework（04-coder-review-fixes.md）已确认删除，当前分支保持该修复。

### 修复 2：`PLAYER_RESPAWN_DELAY` 改为 5.0

**状态：✅ 已修复（移至 Config）**

`s_dead.gd` 中原 `const PLAYER_RESPAWN_DELAY: float = 3.0` 已删除。常量已迁移至 `scripts/configs/config.gd`：

```gdscript
const PLAYER_RESPAWN_DELAY: float = 5.0
```

`s_dead.gd` 现在通过 `Config.PLAYER_RESPAWN_DELAY` 引用。值正确为 5.0。

### 修复 3：`_kill_entity()` 删除

**状态：✅ 已删除**

`s_damage.gd` 中 `_kill_entity()` 方法（原 549-568 行）已完全删除。

---

## 额外变更评估

前一轮修复范围仅 3 个文件。当前分支有 33 个文件变更，额外 30 个文件的变更分类评估如下：

### A. 与 Issue #193 直接相关的合理变更（6 个文件）

| 文件 | 变更 | 评估 |
|------|------|------|
| `scripts/systems/s_camera.gd` | 添加 entity not-in-tree 检查清理 Camera2D；`component_removed` 信号去重（`is_connected` 检查）；`_on_component_removed` 中 `queue_free()` → `free()` | **合理。** 解决 Camera2D handoff 竞争条件——实体移除后旧 Camera2D 未及时释放，与新实体的 Camera2D 冲突。属于 Issue #193 根因关联修复。 |
| `scripts/systems/s_dead.gd`（额外改动） | 动画不再阻塞复活（移除 `animation_finished` 信号连接）；Tween safety timeout 作为独立机制；`_complete_death` 中 `remove_entity` 提前到 `handle_player_down` 之前 | **合理。** 将死亡动画改为 non-blocking，避免动画未播放完成时复活流程卡住。`remove_entity` 提前执行防止 Camera2D 冲突。 |
| `scripts/gameplay/gol_game_state.gd`（额外改动） | 添加 `_pop_death_countdown_ui()` 方法；`_respawn_player()` 中调用该方法 | **合理。** 复活前清理死亡倒计时 UI，配合新增的死亡倒计时功能。 |
| `scripts/configs/config.gd` | 新增 `PLAYER_RESPAWN_DELAY` 常量 | **合理。** 从 SDead 移至全局 Config，便于多模块引用。 |
| `scripts/ui/views/view_death_countdown.gd` | **新增。** 死亡倒计时 View，显示剩余秒数 | **合理。** Issue 要求 5 秒倒计时 UI。 |
| `scenes/ui/death_countdown.tscn` | **新增。** 死亡倒计时场景文件 | **合理。** 配合 view_death_countdown.gd。 |

### B. 与 PR #221 review 修复相关的变更（代码质量改进）

| 文件 | 变更 | 评估 |
|------|------|------|
| `scripts/services/impl/service_ui.gd` | `push_view`/`pop_view` 返回类型 `bool` → `void`；删除 `_is_tearing_down` 标志；简化 teardown 逻辑 | **合理但需确认。** 这是 commit `7a16f50`（PR #221 review 修复）的一部分。返回类型变更会影响调用者——需确认所有调用者不再依赖返回值。 |
| `scripts/ui/observable_property.gd` | `bind_component`/`bind_observable` 默认参数 `Callable()` → `set_value`；`unbind()` 重置为 `Callable(self, "set_value")`；`_init` 中初始化 `_bound_callable` | **合理。** 修复了默认空 Callable 导致的潜在问题。 |
| `scripts/services/service_context.gd` | 删除冗余 null 检查和 `root_node = null` 赋值 | **合理。** 代码清理。 |
| `scripts/debug/ai_debug_bridge.gd` | 内联 `_report_stale_command_guard`；使用 `JSON.parse_string` 替代 `JSON.new().parse()` | **合理。** Godot 4.x API 现代化。 |

### C. 与 Issue #193 无关的功能变更（4 个文件）

| 文件 | 变更 | 评估 |
|------|------|------|
| `scripts/components/c_melee.gd` | `on_merge()` 从 keep-best 策略改为 replace 策略 | **⚠️ 不属于 Issue #193 范围。** 武器合成策略变更是独立功能决策，应通过独立 Issue 跟踪。 |
| `scripts/components/c_weapon.gd` | `on_merge()` 同上，从 keep-best 改为 replace | **⚠️ 同上。** 应拆分为独立 PR。 |
| `scripts/systems/s_fire_bullet.gd` | 删除 `bullet_movement.friction = 0.0` 行 | **⚠️ 不属于 Issue #193 范围。** 删除了子弹摩擦力显式设置，改变了子弹物理行为。应拆分为独立 PR。 |
| `scripts/systems/s_elemental_visual.gd` | 删除冗余 `is_instance_valid` 检查；未使用的 `components` 参数重命名；简化逻辑 | **合理（代码清理）。** 但混入 Issue #193 分支增加了 review 负担。 |

### D. 测试变更评估

| 文件 | 变更 | 评估 |
|------|------|------|
| `tests/unit/system/test_dead_system.gd` | 大量扩充（+211 行）：新增 10 个测试用例覆盖 s_camera 修复、tween 安全、动画非阻塞等 | **合理。** 覆盖了分支中的修复。但部分测试是"代码审查式测试"（`assert_true(true, "verified in code review")`），价值有限。 |
| `tests/unit/test_death_countdown_view.gd` | **新增。** 测试死亡倒计时 View | **合理。** |
| `tests/integration/flow/test_flow_death_respawn_scene.gd` | **新增。** 替代前一轮 ABORT 的 `test_flow_player_respawn_scene` | **合理。** 重新设计了集成测试，使用 `await` 等待延迟。 |
| `tests/integration/flow/test_flow_player_respawn_scene.gd` | **已删除。** 前一轮 ABORT 的测试文件 | **合理。** 用新测试替代。 |
| `tests/integration/test_bullet_flight.gd` | **已删除。** 子弹飞行集成测试 | **⚠️ 对应 `s_fire_bullet.gd` 的 `friction = 0` 删除。** 测试删除合理但该测试本身验证了一个有效的子弹物理行为，删除后缺少覆盖。 |
| `tests/unit/system/test_s_move.gd` | **已删除。** SMove 摩擦力测试 | **⚠️ 同上。** 与 `friction = 0` 删除配套。 |
| `tests/unit/test_reverse_composition.gd` | 大幅缩减，对应 `c_weapon`/`c_melee` 的 `on_merge` 策略变更 | **合理。** 测试与代码变更匹配。 |
| `tests/unit/system/test_cold_rate_conflict.gd` | 调整测试数据，对应 `c_melee.on_merge` 策略变更 | **合理。** |
| `tests/unit/test_flow_combat.gd` | 添加 `after_test` 手动清理 entity，替代 `auto_free` | **合理。** 可能是修复实体泄漏问题。 |
| `tests/unit/service/test_service_console.gd` | `auto_free` 适配；teardown 清理方式变更 | **合理。** 代码质量改进。 |
| `tests/unit/service/test_service_ui.gd` | `push_view`/`pop_view` 测试适配 void 返回类型 | **合理。** 对应 service_ui.gd 的 API 变更。 |
| `tests/unit/service/console_test_utils.gd` | `setup_world` 类型签名变更；`add_entities` 传递 `null, false` 参数 | **合理。** 适配 API 变更。 |

### E. 非代码文件

| 文件 | 变更 | 评估 |
|------|------|------|
| `AGENTS.md` | 从 game-code-only 版本更新为 monorepo 版本（包含 foreman rules） | **合理。** 项目文档更新。 |
| `CLAUDE.md` | **新增。** 符号链接指向 AGENTS.md | **合理。** |
| `project.godot` | autoload 路径从 `res://` 改为 `uid://` | **合理。** Godot 最佳实践。 |

---

## 集成测试状态评估

前一轮 `test_flow_player_respawn_scene`（SceneConfig）ABORT（Abort trap:6）。

**当前状态：**
- 旧文件 `tests/integration/flow/test_flow_player_respawn_scene.gd` **已删除**
- 新文件 `tests/integration/flow/test_flow_death_respawn_scene.gd` **已创建**

**新集成测试设计评估：**
- `extends SceneConfig` ✅ 正确使用集成测试基类
- 注册了必要系统（s_hp, s_damage, s_dead, s_camera）✅
- `enable_pcg() -> false` ✅ 避免依赖 PCG
- 使用 `await` 等待 6 秒（PLAYER_RESPAWN_DELAY 5.0 + buffer）✅
- 手动初始化 `GOL.Game` 并设置 `campfire_position` 和 `is_game_over` ✅
- 验证项：旧实体移除、新实体创建、HP 正值、invincible_time、campfire 位置、Camera2D 存在、Config.PLAYER_RESPAWN_DELAY 值 ✅

**风险点：**
- 前一轮 ABORT 的根因未明（可能是 SceneConfig 框架问题，也可能是测试场景配置问题）
- 新测试结构合理，但**尚未验证是否能通过运行**——前一轮 ABORT 可能是环境问题，也可能是框架 bug

---

## 架构约束

### 涉及的 AGENTS.md 文件
- `scripts/systems/AGENTS.md` — SDead、SDamage、SCamera、SElementalVisual 系统修改
- `scripts/components/AGENTS.md` — CMelee、CWeapon 组件修改（on_merge 策略变更）
- `scripts/gameplay/AGENTS.md` — GOLGameState 复活流程修改
- `scripts/services/AGENTS.md` — Service_UI、ServiceContext 修改
- `tests/AGENTS.md` — 测试分层规则

### 引用的架构模式
- **System 模式**：SDead 改为 timeout-based（非 animation-gated）
- **MVVM UI**：View_DeathCountdown 遵循 ViewBase 模式
- **Service Recipe 模式**：`create_entity_by_id` 返回实体已在世界中
- **Config 集中管理**：`PLAYER_RESPAWN_DELAY` 移至 Config.gd

### 文件归属层级
- 系统修改 → `scripts/systems/`
- 组件修改 → `scripts/components/`
- 游戏状态 → `scripts/gameplay/`
- UI → `scripts/ui/views/` + `scenes/ui/`
- 单元测试 → `tests/unit/`
- 集成测试 → `tests/integration/flow/`

### 测试模式
- 单元测试：`extends GdUnitTestSuite`（test_dead_system 扩充至 ~15 个用例）
- 集成测试：`extends SceneConfig`（test_flow_death_respawn_scene 新增）

---

## 测试契约

| # | 测试类型 | 文件 | 验证内容 | 状态 |
|---|---------|------|---------|------|
| 1 | 单元 | `test_dead_system.gd` | `Config.PLAYER_RESPAWN_DELAY == 5.0` | ✅ 已覆盖 |
| 2 | 单元 | `test_dead_system.gd` | 动画非阻塞（无 signal 连接） | ✅ 已覆盖 |
| 3 | 单元 | `test_dead_system.gd` | SCamera 信号去重 + free() 非 queue_free() | ✅ 已覆盖 |
| 4 | 单元 | `test_dead_system.gd` | 实体不在树时 Camera2D 清理 | ✅ 已覆盖 |
| 5 | 单元 | `test_death_countdown_view.gd` | View_DeathCountdown 存在且显示正确数字 | ✅ 已覆盖 |
| 6 | 集成 | `test_flow_death_respawn_scene.gd` | 完整死亡→复活流程 + Camera handoff | ✅ 已覆盖（未运行验证） |

---

## 风险点

1. **分支范围膨胀**：33 个文件远超 Issue #193 所需的 3-5 个文件。`c_melee.on_merge`、`c_weapon.on_merge`、`s_fire_bullet` friction 删除是不相关功能变更，应拆分为独立 PR。这增加了 review 难度和回退风险。

2. **集成测试未验证**：新测试 `test_flow_death_respawn_scene.gd` 未运行。前一轮同类型测试 ABORT，需确认新测试能通过。

3. **`on_merge` 策略变更是破坏性变更**：`c_melee` 和 `c_weapon` 从 keep-best 改为 replace，改变了游戏核心合成机制。这不是 Issue #193 的修复范围，缺乏设计讨论和独立 Issue 追踪。

4. **`s_fire_bullet` friction 删除缺少替代方案**：删除 `bullet_movement.friction = 0.0` 后，子弹摩擦力依赖 recipe 默认值。如果 recipe 中 friction 不为 0，子弹会减速，行为与之前不同。

5. **Service_UI API 变更**：`push_view`/`pop_view` 返回类型从 `bool` 改为 `void`，如果有外部代码依赖返回值会编译失败。从测试变更来看适配已完成。

---

## 建议的实现步骤

### 结论：spawn @coder 做 rework

分支上的核心修复（3 项）完整且正确，但包含大量不属于 Issue #193 范围的变更。建议从 main 创建新分支，仅 cherry-pick 或重新应用核心修复。

### 具体修改点

**Step 1：从 main 创建新分支**

**Step 2：应用核心修复（仅 Issue #193 范围）**
- `scripts/gameplay/gol_game_state.gd` — 删除冗余 `add_entity`（main 上可能已不存在）+ 添加 `_pop_death_countdown_ui()` 逻辑
- `scripts/systems/s_dead.gd` — timeout-based 死亡流程 + `Config.PLAYER_RESPAWN_DELAY` 引用
- `scripts/systems/s_damage.gd` — 删除 `_kill_entity()`
- `scripts/configs/config.gd` — 新增 `PLAYER_RESPAWN_DELAY` 常量
- `scripts/systems/s_camera.gd` — Camera2D 生命周期修复（entity not-in-tree 清理 + 信号去重 + free() 替代 queue_free()）
- `scripts/ui/views/view_death_countdown.gd` — 新增死亡倒计时 View
- `scenes/ui/death_countdown.tscn` — 新增死亡倒计时场景

**Step 3：应用必要的基础设施修复（与 Issue #193 正确运行直接相关）**
- `scripts/services/impl/service_ui.gd` — `push_view`/`pop_view` API 变更（death countdown UI 依赖此 API）
- `scripts/ui/observable_property.gd` — 默认参数修复（death countdown View 可能依赖）

**Step 4：添加测试**
- `tests/unit/system/test_dead_system.gd` — 仅追加与死亡复活直接相关的测试（Config 值、动画非阻塞、tween 安全）
- `tests/unit/test_death_countdown_view.gd` — 新增
- `tests/integration/flow/test_flow_death_respawn_scene.gd` — 新增

**Step 5：运行全部测试确认无回归**

**Step 6：移除不属于本 Issue 的变更（不要 cherry-pick）**
- `scripts/components/c_melee.gd` — on_merge 策略变更
- `scripts/components/c_weapon.gd` — on_merge 策略变更
- `scripts/systems/s_fire_bullet.gd` — friction 删除
- `scripts/systems/s_elemental_visual.gd` — 冗余检查清理
- `tests/unit/test_reverse_composition.gd` — on_merge 测试变更
- `tests/unit/system/test_cold_rate_conflict.gd` — on_merge 测试变更
- `tests/integration/test_bullet_flight.gd` — 删除
- `tests/unit/system/test_s_move.gd` — 删除
- `tests/unit/test_flow_combat.gd` — entity 清理变更
- `tests/unit/service/test_service_console.gd` — auto_free 适配
- `tests/unit/service/console_test_utils.gd` — API 适配
- `AGENTS.md` / `CLAUDE.md` / `project.godot` — 项目配置变更
