# Decision 6 — 2026-04-01 21:50
**Trigger:** @coder completed (03-coder-respawn-fix-implementation.md), PR 创建失败（gh CLI 版本不支持 --json flag）
**Assessment:** Coder 实现严重偏离计划，存在两类问题：(1) **未执行核心修复** — 计划要求删除 `gol_game_state.gd:74` 的冗余 `add_entity(new_player)` 调用（这是根因），但 coder 保留了该调用，反而添加了 workaround 式的 Camera2D 显式创建代码（第 76-82 行）。Planner 分析明确指出 `create_entity_by_id` 内部已调用 `add_entity`，重复调用导致新实体被 `queue_free()`，保留 double-add 意味着根因未修复。(2) **违反约束** — 计划明确禁止 "不要添加 `process_mode` 相关修改"，但 coder 在 `s_dead.gd:36` 添加了 `entity.process_mode = PROCESS_MODE_ALWAYS`，并为此编写了额外测试用例。Coder 在文档中声称"TL 上下文明确要求显式创建 Camera2D"，这与 Decision 5 的原文直接矛盾（Decision 5 明确写了"删除 `add_entity` 后不要添加其他 Camera2D 创建逻辑"）。PR 创建失败是 `gh` CLI 版本问题（不支持 `--json` flag），与代码质量无关。所有变更均未提交，可修正。调度轮次 2/3，尚有空间做一次 rework。
**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** 严格按 Decision 5 的 TL Context 执行，核心是删除冗余 add_entity，不加任何额外逻辑。回退所有未授权修改。
**TL Context for Coder:**
> **Issue #193：角色死亡后无法复活 — Rework 阶段**
>
> ---
>
> **前置阅读（必读）：**
> - Decision 5 的 TL Context：`docs/foreman/193/decisions/005-decision.md`（这是你上次收到的指令，请严格遵循）
> - Planner 分析文档：`docs/foreman/193/iterations/02-planner-respawn-analysis.md`
> - 上次实现文档（了解偏离点）：`docs/foreman/193/iterations/03-coder-respawn-fix-implementation.md`
>
> ---
>
> **上次实现的偏离点（必须全部回退）：**
>
> 1. `gol_game_state.gd` — 你上次在第 76-82 行添加了显式 Camera2D 创建代码。**这些代码必须全部删除。** Decision 5 明确要求"删除 `add_entity` 后不要添加其他 Camera2D 创建逻辑"。
> 2. `gol_game_state.gd` — 你**没有删除**第 74 行的 `ECS.world.add_entity(new_player)`。这是本次 Issue 的根因修复，必须删除。
> 3. `s_dead.gd:36` — 你添加了 `entity.process_mode = Node.PROCESS_MODE_ALWAYS`。Decision 5 明确约束"不要添加 `process_mode` 相关修改"，必须删除。
> 4. `test_dead_system.gd` — `test_initialize_sets_process_mode_always` 测试用例对应未授权修改，必须删除。
> 5. `test_flow_player_respawn_scene.gd` — 第 3 个测试用例（暂停状态死亡复活）对应未授权的 process_mode 修改，必须删除。
>
> ---
>
> **正确的实现步骤（严格按此执行，不加不减）：**
>
> **Step 1：修复根因 — 删除冗余 `add_entity` 调用**
> - **文件：** `gol-project/scripts/gameplay/gol_game_state.gd`
> - **操作：** 删除 `ECS.world.add_entity(new_player)` 这一行
> - **原因：** `create_entity_by_id("player")` 内部已调用 `add_entity`，重复调用导致新实体被销毁
>
> **Step 2：修改 `PLAYER_RESPAWN_DELAY` 为 5.0**
> - **文件：** `gol-project/scripts/systems/s_dead.gd`
> - **操作：** `3.0` → `5.0`（这个你上次做对了，保留）
>
> **Step 3：删除 `_kill_entity()` 死代码**
> - **文件：** `gol-project/scripts/systems/s_damage.gd`
> - **操作：** 删除整个 `_kill_entity` 方法（这个你上次做对了，保留）
>
> **Step 4：单元测试**
> - **文件：** `gol-project/tests/unit/system/test_dead_system.gd`
> - **只保留：** `test_respawn_delay_value`（断言 `SDead.PLAYER_RESPAWN_DELAY == 5.0`）
> - **删除：** `test_initialize_sets_process_mode_always`（对应未授权修改）
>
> **Step 5：集成测试**
> - **文件：** `gol-project/tests/integration/flow/test_flow_player_respawn_scene.gd`
> - **只保留：** (1) 玩家死亡后 5s 延迟复活验证 (2) 摄像机 handoff 连续性验证
> - **删除：** 暂停状态死亡测试用例（对应未授权的 process_mode 修改）
>
> ---
>
> **约束（不可违反）：**
> - **必须删除** `add_entity` 调用 — 这是根因
> - **不要添加** 任何 Camera2D 显式创建逻辑 — SCamera 系统会自动处理
> - **不要修改** `process_mode` — 暂停边界条件不在本次 Issue 范围
> - **不要添加** 约束列表以外的任何代码
> - 不要修改 CCamera、CDead 组件定义
> - 不要修改 SCamera 系统逻辑
> - 不要引入新的服务或全局状态
