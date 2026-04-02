# Decision 2 — 2026-03-30 09:36
**Trigger:** @planner completed (01-planner-player-respawn-flow.md)
**Assessment:** Plan 质量不足，存在三个关键缺陷：(1) Camera 生命周期分析完全缺失——issue 明确报告"摄像机被重置到了某个地图无人的位置"，且 TL 上下文明确要求分析 Camera2D 销毁/创建时序，planner 完全未回应；(2) 根因假设未经验证——planner 断言"游戏暂停导致 Tween 冻结"是核心问题，但 issue 未提及暂停，且摄像机瞬移到错误位置更符合 respawn 流程已触发但 camera handoff 失败的症状；(3) 5s 延迟修复未纳入实现步骤。暂停场景可作为边界条件保留，但不能作为唯一根因。需要重新分析。
**Action:** spawn @planner
**Model:** glm-5.0-turbo-ioa
**Guidance:** 补全 camera 生命周期分析，重新评估根因，完善实现方案
**TL Context for Planner:**
> **Issue #193：角色死亡后无法复活 — Round 2**
>
> 上轮分析有三个关键遗漏，请在本轮补全：
>
> **1. Camera 生命周期分析（必须补全）**
> Issue 报告"摄像机被重置到了某个地图无人的位置"。请深入分析：
> - `SCamera._on_component_removed()` 中 Camera2D 的销毁方式（queue_free vs free）
> - `ECSUtils.remove_entity()` 移除旧 entity 时，Camera2D 子节点的销毁时机
> - `_respawn_player()` 创建新 entity 后，新 Camera2D 的 `make_current()` 调用时序
> - 旧 Camera2D 被 queue_free 后，是否在同一帧内就有可能没有 active camera？Godot 4.x 中 queue_free 在帧末执行，如果新 entity 的 Camera2D 在同一帧 add_entity，SCamera 应该会在 `_process_entity` 中 make_current——但需验证 SCamera 的系统执行顺序是否保证在 `add_entity` 当帧生效
> - 如果存在帧间隙（旧 camera 已 queue_free 但尚未真正销毁，新 camera 尚未 make_current），Godot 的默认相机行为是什么？
>
> **2. 重新评估根因（暂停假设需要验证）**
> 上轮将"游戏暂停导致 Tween 冻结"作为核心问题，但：
> - Issue 未提及暂停状态，"角色首先正常掉落了身上的可掉落组件。随后被怪物攻击致死"描述的是正常游戏流程
> - 摄像机瞬移到错误位置更符合 respawn 流程**已经触发**（旧 entity 被移除导致旧 camera 销毁）但 camera handoff 失败
> - 请区分两个可能的故障模式：
>   - **模式 A：`_complete_death` 从未触发** → entity 不被移除，camera 不变，玩家卡在死亡状态（与"摄像机瞬移"矛盾）
>   - **模式 B：`_complete_death` 触发但 camera handoff 失败** → 旧 entity 被移除（camera 销毁），新 entity 的 camera 未生效（摄像机瞬移），符合所有症状
> - 请验证 `_complete_death` → `handle_player_down` → `_respawn_player` 链路中哪一步可能出问题导致模式 B
>
> **3. `_kill_entity()` 是否真的是死代码**
> 请通过 grep 验证 `_kill_entity` 在整个代码库中是否有调用点，而不是仅凭阅读推测。如果确实无调用，说明理由并纳入删除方案。
>
> **4. 5s 延迟修复**
> Issue 期望 5s 倒计时，当前 `PLAYER_RESPAWN_DELAY = 3.0`。请将此修复明确纳入实现方案和文件列表。
>
> **5. 重新设计实现方案**
> 基于以上分析，重新设计覆盖以下所有问题的方案：
> - Camera handoff 保证（可能的修复：在 `_respawn_player` 中显式调用新 camera 的 `make_current()`，或调整 SCamera 系统优先级）
> - 暂停场景的 Tween 处理（作为边界条件修复，不是唯一根因）
> - `_kill_entity()` 清理
> - `PLAYER_RESPAWN_DELAY` 改为 5.0
>
> **产出文档：** 存放到 `docs/foreman/193/02-planner-respawn-analysis-v2.md`
