# Decision 1 — 2026-03-30 09:28
**Trigger:** New issue assigned
**Assessment:** Bug 涉及玩家死亡/复活完整流程，存在多条 death path 可能导致重复调用和状态不一致。需要 planner 深入分析死亡数据流、camera 生命周期、以及复活后的状态恢复。
**Action:** spawn @planner
**Model:** glm-5.0-turbo-ioa
**Guidance:** 追踪玩家死亡到复活的完整数据流，识别死亡路径冲突和 camera 生命周期问题，制定修复方案和测试契约
**TL Context for Planner:**
> **Issue #193：角色死亡后无法复活**
>
> Bug 核心问题：玩家被怪物攻击致死后，鼠标失去控制，摄像机瞬移到错误位置，没有复活流程。
> 期望行为：死亡后倒计时 5s，在出生点复活，重新获得控制权。
>
> 初步代码分析发现了几个关键可疑点，请深入验证：
>
> **1. 双重死亡处理路径**
> `SDamage._kill_entity()` (s_damage.gd:549-568) 和 `SDead._complete_death()` (s_dead.gd:211-227) 都会调用 `GOL.Game.handle_player_down()`。
> - `SDamage._kill_entity()` 对 PLAYER 阵营非 campfire 实体：直接调用 `handle_player_down()` 然后 return（不添加 CDead）
> - `SDead._complete_death()` 对有 CPlayer 的实体：调用 `handle_player_down()` 然后调用 `ECSUtils.remove_entity()`
>
> 请验证：这两个路径在什么情况下会分别触发？是否存在 `_kill_entity` 不走 early return 的场景（比如 CDead 已经在另一个地方被添加）？
>
> **2. Camera 生命周期问题**
> `SCamera` (s_camera.gd) 在 entity 上创建 Camera2D 子节点。当 entity 被 `ECSUtils.remove_entity()` 移除时，`_on_component_removed` 会 `queue_free` 相机。
> `_respawn_player()` 创建新 player entity 时带有 CCamera，但旧 entity 的 Camera2D 被 queue_free 后，新 Camera2D 可能未能正确 become current。
>
> **3. 死亡时组件移除的影响**
> `Config.DEATH_REMOVE_COMPONENTS` 包含 CAnimation、CCollision、CGoapAgent、CPerception、CWeapon、CHP、CMelee、CTracker、CAim、CComponentElementalAffliction、CSpawner。
> 注意：CCamera **不在**移除列表中，CPlayer 也不在。但 CHP 被移除了——这意味着 `_respawn_player()` 中 `hp.invincible_time = 1.5` 是设置在新 entity 上，不受影响。
>
> **4. 复活流程 (`GOLGameState._respawn_player()`)**
> gol_game_state.gd:54-75：创建新 player entity，设置 campfire position，设 invincible 1.5s，add_entity。
> 请验证：新 entity 是否完整获得了所有必需组件（CCamera、CPlayer、CAim 等）？recipe "player" 是否包含这些？
>
> **请完成以下分析：**
> 1. **完整死亡数据流**：从 HP 降到 0 → 添加 CDead / _kill_entity → 死亡动画 → _complete_death → handle_player_down → _respawn_player 的每一步调用链
> 2. **双重路径冲突**：确认 SDamage._kill_entity 和 SDead._complete_death 是否可能对同一个 entity 各调用一次 handle_player_down
> 3. **Camera 生命周期**：分析旧 entity 移除时 Camera2D 的销毁时序 vs 新 entity 创建 Camera2D 的时序，是否存在帧间隙导致"摄像机被重置到无人位置"
> 4. **预期行为差距**：当前 PLAYER_RESPAWN_DELAY=3.0s（s_dead.gd:10），但 issue 期望 5s 倒计时——这也是一个需要修复的点
> 5. **修复方案**：提出消除双重调用、保证 camera 连续性、实现 5s 倒计时的方案
> 6. **测试契约**：定义至少 3 个测试用例覆盖核心场景
>
> 产出文档存放到 `docs/foreman/193/01-planner-respawn-analysis.md`
