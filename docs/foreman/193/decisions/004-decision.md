# Decision 4 — 2026-04-01 21:34
**Trigger:** 新一轮调度，重新接手 #193（上一轮在 Decision 3 因 Planner 连续两轮未覆盖 camera 生命周期分析而 abandon）
**Assessment:** 上一轮的核心教训是 Planner 两次忽略 camera 相关分析，持续将"游戏暂停"作为唯一根因。Issue 的最突出症状是"摄像机被重置到了某个地图无人的位置"，这更符合 respawn 流程已触发但 camera handoff 失败的模式。新一轮需要用更精确的约束确保 Planner 覆盖所有关键分析维度。上一轮 Decision 1 的 TL Context 方向正确（双重死亡路径、Camera 生命周期、组件移除影响、复活流程），可复用其框架。
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5.0-turbo-ioa
**Guidance:** 聚焦于 Issue 报告的实际症状而非假设场景，必须逐一回应以下分析维度，不得遗漏任何一个
**TL Context for Planner:**
> **Issue #193：角色死亡后无法复活（新一轮 Round 1）**
>
> 上一轮 Planner 两次未能产出合格的分析文档（已在 Decision 3 abandon）。本轮必须逐一回应以下 4 个分析维度，每个维度缺一不可。如果你无法完成某个维度，明确说明原因而不是跳过。
>
> ---
>
> **前置阅读：**
> - `gol-project/scripts/systems/AGENTS.md` — 系统目录和模式
> - `gol-project/scripts/components/AGENTS.md` — 组件目录
> - `gol-project/scripts/gameplay/AGENTS.md` — Gameplay 层（GOAP、ECS Authoring）
> - `gol-project/scripts/services/AGENTS.md` — 服务层
> - `gol-project/tests/AGENTS.md` — 测试分层规则
> - 上一轮 Planner 产出：`docs/foreman/193/iterations/01-planner-player-respawn-flow.md`（可参考其调用链分析，但注意其根因分析方向有偏差）
>
> ---
>
> **Issue 症状（必须基于此分析，不要自行假设其他场景）：**
> 1. 角色正常掉落可掉落组件
> 2. 随后被怪物攻击致死
> 3. 鼠标失去对准心控制
> 4. 屏幕短暂停留后，摄像机被重置到了某个地图无人的位置
> 5. 没有复活流程
>
> **期望行为：** 死亡后倒计时 5s，在出生点复活，重新获得控制权。
>
> ---
>
> **必须逐一回应的 4 个分析维度：**
>
> **维度 1：死亡调用链追踪**
> 从 `SDamage._on_no_hp()` 开始，追踪到 `_complete_death()` → `handle_player_down()` → `_respawn_player()` 的完整调用链。明确标注每个关键函数的文件路径和行号。
> - 特别关注 `_start_death()` 中可掉落组件为空时 vs 非空时的两条路径是否都会正确触发 `SDead._initialize()`
> - 验证 `_complete_death()` 对有 `CPlayer` 的实体是否确实调用了 `handle_player_down()`
>
> **维度 2：Camera 生命周期分析（上一轮遗漏的核心维度）**
> Issue 最突出的症状是"摄像机被重置到了某个地图无人的位置"。请分析：
> - `SCamera` 系统如何管理 Camera2D（创建、make_current、销毁）
> - 当旧 player entity 被 `ECSUtils.remove_entity()` 移除时，其 Camera2D 子节点何时被销毁（queue_free 的帧末时机）
> - `_respawn_player()` 创建新 player entity 后，新 Camera2D 何时被 SCamera 系统 `make_current()`
> - 旧 Camera2D 销毁和新 Camera2D 激活之间是否存在帧间隙，导致 Godot 使用默认 camera（即"瞬移到无人位置"）
> - 如果 respawn 根本未触发，camera 不应移动——所以"摄像机瞬移"这一症状说明 `_complete_death` 很可能**已经执行**，问题出在 respawn 后的 camera handoff
>
> **维度 3：`_kill_entity()` 死代码验证**
> `SDamage._kill_entity()` (s_damage.gd:549-568) 看起来有类似复活逻辑但可能从未被调用。
> - 使用 Grep 工具搜索 `_kill_entity` 在整个代码库中的所有调用点
> - 如果确实无调用，将其纳入删除方案
> - 如果有调用，分析其与 `SDead._complete_death()` 的关系
>
> **维度 4：PLAYER_RESPAWN_DELAY 差异**
> Issue 期望 5s 倒计时，当前代码中 `PLAYER_RESPAWN_DELAY` 的实际值是多少？是否需要修改？
>
> ---
>
> **根因判断框架：**
> 基于以上 4 个维度，判断最可能的故障模式：
> - **模式 A：`_complete_death` 从未触发** → entity 不被移除，camera 不变，玩家卡在死亡状态（与"摄像机瞬移"矛盾，除非有其他因素导致 camera 被重置）
> - **模式 B：`_complete_death` 触发，`handle_player_down` 未执行** → `is_game_over` 检查阻止了复活
> - **模式 C：`_complete_death` 触发，`_respawn_player` 执行，但 camera handoff 失败** → 旧 entity 被移除（camera 销毁），新 entity 创建但 camera 未生效
>
> 请基于代码证据判断哪个模式最符合 Issue 症状。
>
> ---
>
> **产出要求：**
> 1. 以上 4 个维度每个维度都必须有独立的分析段落，包含文件路径和行号
> 2. 根因判断需引用代码证据
> 3. 实现方案必须覆盖所有发现的问题（不仅是根因）
> 4. 测试契约至少 3 个用例
> 5. 新增/修改文件列表
>
> **产出文档：** 存放到 `docs/foreman/193/iterations/02-planner-respawn-analysis.md`
