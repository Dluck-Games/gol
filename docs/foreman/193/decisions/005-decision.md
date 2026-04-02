# Decision 5 — 2026-04-01 21:41
**Trigger:** @planner completed (02-planner-respawn-analysis.md)
**Assessment:** 本轮 Planner（Round 2）质量合格，4 个维度全部覆盖：(1) 死亡调用链完整追踪，含两条路径验证；(2) Camera 生命周期分析到位——发现根因是 `_respawn_player()` 中 `create_entity_by_id` + `add_entity` 的 double-add bug，导致新实体被 `queue_free()`，新 Camera2D 随之销毁，完美解释"摄像机瞬移到无人位置"；(3) `_kill_entity()` 确认为死代码（零外部调用）；(4) `PLAYER_RESPAWN_DELAY` 当前 3.0，需改为 5.0。根因判断为模式 C 变体，代码证据链完整（`service_recipe.gd:130` 内部已 `add_entity`，`gol_game_state.gd:74` 重复调用触发 ID 碰撞 → `world.gd:296-304` 自我移除）。实现方案简洁：删除一行冗余 `add_entity` 即可修复根因。测试契约 4 个用例覆盖正常复活、camera handoff、常量值、死代码清理。Plan 可以推进。
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**Guidance:** 按 planner 文档的 Step 1-3 实现代码修复，Step 4-5 实现测试。核心修复是删除 gol_game_state.gd 中一行冗余的 add_entity 调用
**TL Context for Coder:**
> **Issue #193：角色死亡后无法复活 — 实现阶段**
>
> ---
>
> **前置阅读（必读）：**
> - Planner 分析文档：`docs/foreman/193/iterations/02-planner-respawn-analysis.md`（完整分析、根因、实现方案、测试契约、风险点）
> - `gol-project/tests/AGENTS.md` — 测试分层规则
> - `gol-project/scripts/gameplay/AGENTS.md` — Gameplay 层约定
> - `gol-project/scripts/systems/AGENTS.md` — System 层约定
>
> **参考文件（实现时 Read）：**
> - `gol-project/scripts/gameplay/gol_game_state.gd` — 复活逻辑，根因所在
> - `gol-project/scripts/systems/s_dead.gd` — 死亡系统，修改延迟常量
> - `gol-project/scripts/systems/s_damage.gd` — 伤害系统，删除死代码
> - `gol-project/scripts/services/impl/service_recipe.gd` — 理解 `create_entity_by_id` 语义
>
> ---
>
> **根因摘要：**
> `_respawn_player()` 调用 `create_entity_by_id("player")` 创建新实体（内部已 `add_entity`），然后又调了一次 `ECS.world.add_entity(new_player)`。第二次 `add_entity` 检测到 ID 已存在，触发 `remove_entity` → `queue_free`，新实体（含新 Camera2D）在帧末被销毁。旧实体也随后被移除。结果：无活跃 Camera2D → 视口回退默认位置。
>
> ---
>
> **实现步骤（按顺序）：**
>
> **Step 1：修复根因 — 删除冗余 `add_entity` 调用**
> - **文件：** `gol-project/scripts/gameplay/gol_game_state.gd`
> - **操作：** 删除第 74 行的 `ECS.world.add_entity(new_player)`
> - **原因：** `ServiceContext.recipe().create_entity_by_id("player")` 在 `service_recipe.gd:130` 内部已调用 `ECS.world.add_entity(entity)`，重复调用导致新实体被 `queue_free()`
> - **注意：** 删除后，`transform.position = campfire_position` 和 `hp.invincible_time = 1.5` 仍在 `add_entity` 之后设置。由于这些是运行时属性（非 @export），修改是安全的
>
> **Step 2：修改 `PLAYER_RESPAWN_DELAY` 为 5.0**
> - **文件：** `gol-project/scripts/systems/s_dead.gd`
> - **操作：** 第 10 行，`3.0` → `5.0`
>
> **Step 3：删除 `_kill_entity()` 死代码**
> - **文件：** `gol-project/scripts/systems/s_damage.gd`
> - **操作：** 删除第 549-568 行的整个 `_kill_entity` 方法
>
> **Step 4：新增/追加单元测试**
> - **文件：** `gol-project/tests/unit/system/test_dead_system.gd`（追加）
> - **操作：** 追加 `test_respawn_delay_value` 用例，断言 `SDead.PLAYER_RESPAWN_DELAY == 5.0`
>
> **Step 5：新增集成测试**
> - **文件：** `gol-project/tests/integration/flow/test_flow_player_respawn_scene.gd`（新增）
> - **操作：** `extends SceneConfig`，实现用例：
>   1. 玩家死亡后正确复活（5s 延迟后新 player 在 campfire 位置生成，CHP.invincible_time > 0）
>   2. 摄像机在复活后正确跟随新玩家（新实体 CCamera.camera != null）
>
> **Step 6：运行测试确认无回归**
>
> ---
>
> **约束：**
> - 不要修改 CCamera、CDead 等组件定义
> - 不要修改 SCamera 系统的逻辑
> - 不要引入新的服务或全局状态
> - 不要添加 `process_mode` 相关修改（暂停状态死亡是边界条件，不在本次 Issue 范围内）
> - 测试遵循 AGENTS.md 中的分层规则：unit 用 `GdUnitTestSuite`，integration 用 `SceneConfig`
> - `_respawn_player` 中删除 `add_entity` 后不要添加其他 Camera2D 创建逻辑——SCamera 系统会在下一帧自动为新实体创建 Camera2D（`s_camera.gd:33-35`）
