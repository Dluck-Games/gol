# Orchestration — Issue #193

## Issue
**Title:** 角色死亡后无法复活
**Labels:** bug, topic:gameplay, foreman:assign
**Body:**
**Bug 描述：**
角色在被攻击致死后无法正常复活。

**具体场景（基于观察）：**
1. 角色首先正常掉落了身上的可掉落组件。
2. 随后被怪物攻击致死。
3. 鼠标失去对准心的控制。
4. 屏幕短暂停留后，摄像机被重置到了某个地图无人的位置。

**期望行为：**
角色死亡后，倒计时 5s，然后角色在出生点复活，如同游戏刚刚开始一般，并且重新获得控制权。

**实际行为：**
角色死亡后失去控制，摄像机瞬移到错误位置，且没有复活流程。

---

## Decision Log

### Decision 1 — 2026-03-29 16:36
**Trigger:** New issue assigned
**Assessment:** 新 bug issue，涉及角色死亡/复活流程，需要先分析影响面和根因
**Action:** spawn @planner
**Model:** glm-5.0-turbo-ioa
**Guidance:** 分析死亡/复活流程的现状，追踪影响面，制定修复方案和测试契约
**TL Context for Planner:**
> **Issue #193 — 角色死亡后无法复活**
>
> 这是一个 gameplay bug，角色死亡后出现三个异常现象：
> 1. 鼠标失去对准心的控制
> 2. 摄像机被重置到地图无人位置
> 3. 没有复活流程（无 5s 倒计时、无出生点重生）
>
> **期望行为：** 死亡 → 5s 倒计时 → 出生点复活 → 重新获得控制权（如同游戏刚开始）
>
> **分析要求：**
> 1. 追踪角色死亡处理的完整链路：HP 归零后发生了什么？哪个系统负责死亡事件？是否有现有的死亡/复活系统？
> 2. 追踪摄像机控制系统：死亡后摄像机为什么被重置？是哪个系统触发了摄像机位置改变？
> 3. 追踪玩家输入控制：死亡后为什么失去控制？控制权在哪个 system 中管理？
> 4. 确认是否存在任何复活相关的代码（搜索 respawn、revive、death 等关键字）
> 5. 评估影响面：修复涉及哪些组件和系统
>
> **产出要求：**
> - 详细的根因分析（为什么死亡后无法复活）
> - 影响面追踪（涉及哪些组件/系统/场景）
> - 修复方案（具体到要修改哪些文件的哪些函数）
> - 测试契约（至少覆盖：死亡触发、倒计时、复活重生、控制权恢复、摄像机行为）
>
> **关键文件参考：**
> - 先读 `gol-project/AGENTS.md` 了解项目结构
> - 重点看 `scripts/systems/` 中的 health/death 相关系统
> - 重点看 `scripts/components/` 中的 player/camera 相关组件
> - 查看 `scripts/services/` 中是否有 respawn 相关 service

### Decision 2 — 2026-03-29 16:45
**Trigger:** @planner completed (01-planner-death-respawn-analysis.md)
**Assessment:** Plan 质量充分。根因分析清晰——Bug B（Camera2D queue_free 竞态导致无 current camera）直接解释摄像机瞬移症状，Bug C（animation_finished 信号依赖）直接解释无复活流程。修复方案 4 步，每步有明确文件和函数定位，测试契约 7 项覆盖关键路径。风险点标注诚实。批准进入实现阶段。
**Action:** spawn @coder
**Model:** glm-5.0-turbo-ioa
**Guidance:** 按 planner 的 4 步修复方案实现，同步更新单元测试
**TL Context for Coder:**
> **Issue #193 — 角色死亡后无法复活 — 实现任务**
>
> 请先阅读 `01-planner-death-respawn-analysis.md` 了解完整分析。以下是具体实现要求：
>
> **工作树路径**: `/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260329083635._beaea84a/gol-project/`
>
> **实现步骤（严格按顺序）：**
>
> 1. **修改 `scripts/systems/s_dead.gd`**：
>    - 重写 `_initialize_player_death()` 函数：移除对 `animation_finished` 信号的依赖，改为直接创建 timeout tween（使用 `Config.PLAYER_RESPAWN_DELAY` 秒）
>    - 死亡动画仍然播放，但作为纯视觉效果，不阻塞复活流程
>    - 删除 `_on_player_death_animation_finished()` 函数（不再需要）
>    - 注意：tween 应存储在 `dead` 组件或系统上，确保 `_complete_death` 中能终止它
>
> 2. **修改 `scripts/systems/s_camera.gd`**：
>    - `_on_component_removed()`: 将 `component.camera.queue_free()` 改为 `component.camera.free()`（消除竞态）
>    - `_on_component_created()`: 添加 `if not entity.component_removed.is_connected(_on_component_removed):` 检查防止信号重复连接
>
> 3. **修改 `scripts/systems/s_damage.gd`**：
>    - 删除未使用的 `_kill_entity()` 函数（约 lines 549-568）
>
> 4. **更新测试 `tests/unit/system/test_dead_system.gd`**：
>    - 更新现有测试以反映新的死亡流程（不再依赖 animation_finished 信号触发）
>    - 新增测试覆盖测试契约中的关键项：
>      - `test_player_death_completes_within_timeout` — 验证 5s 后 _complete_death 被调用
>      - `test_camera_signal_no_duplicate` — 验证信号不重复连接
>      - `test_death_animation_plays_but_not_blocking` — 验证动画不阻塞复活
>
> **注意事项：**
> - 不要修改 `CDead` 组件的字段定义，除非 tween 需要存储在组件上（此时加 `_tween` 字段即可）
> - 不要修改 `gol_game_state.gd` 中的 `_respawn_player()` 函数，该函数逻辑正确
> - 不要修改 `resources/recipes/player.tres`
> - 实现完成后运行单元测试确认通过
> - 将产出文档命名为 `02-coder-death-respawn-fix.md`

### Decision 3 — 2026-03-29 16:46
**Trigger:** doc_validation_failed (01-planner-death-respawn-analysis.md)
**Assessment:** 验证失败的 5 个缺失段落（完成的工作、测试契约覆盖、决策记录、仓库状态、未完成事项）属于完成报告模板，不适用于分析文档。Planner 文档已包含等价内容：需求分析、影响面分析、实现方案、测试契约（7 项）、风险点。这是模板类型不匹配，非内容缺失。Decision 2 已基于实质内容质量批准方案，不影响 coder 实现指导。
**Action:** spawn @coder
**Model:** glm-5.0-turbo-ioa
**Guidance:** 文档验证失败为模板不匹配误报，忽略。继续按 Decision 2 的指导实现。
**TL Context for Coder:**
> **Issue #193 — 角色死亡后无法复活 — 实现任务（继续）**
>
> Planner 文档的框架验证失败是模板类型不匹配（分析文档 vs 完成报告），内容质量已在 Decision 2 中确认充分。请忽略此验证结果，继续按以下指导实现。
>
> **工作树路径**: `/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260329083635._beaea84a/gol-project/`
>
> **实现步骤（严格按顺序）：**
>
> 1. **修改 `scripts/systems/s_dead.gd`**：
>    - 重写 `_initialize_player_death()` 函数：移除对 `animation_finished` 信号的依赖，改为直接创建 timeout tween（使用 `Config.PLAYER_RESPAWN_DELAY` 秒）
>    - 死亡动画仍然播放，但作为纯视觉效果，不阻塞复活流程
>    - 删除 `_on_player_death_animation_finished()` 函数（不再需要）
>    - tween 应存储在 `dead` 组件或系统上，确保 `_complete_death` 中能终止它
>
> 2. **修改 `scripts/systems/s_camera.gd`**：
>    - `_on_component_removed()`: 将 `component.camera.queue_free()` 改为 `component.camera.free()`（消除竞态）
>    - `_on_component_created()`: 添加 `if not entity.component_removed.is_connected(_on_component_removed):` 检查防止信号重复连接
>
> 3. **修改 `scripts/systems/s_damage.gd`**：
>    - 删除未使用的 `_kill_entity()` 函数（约 lines 549-568）
>
> 4. **更新测试 `tests/unit/system/test_dead_system.gd`**：
>    - 更新现有测试以反映新的死亡流程（不再依赖 animation_finished 信号触发）
>    - 新增测试覆盖测试契约中的关键项：
>      - `test_player_death_completes_within_timeout` — 验证 5s 后 _complete_death 被调用
>      - `test_camera_signal_no_duplicate` — 验证信号不重复连接
>      - `test_death_animation_plays_but_not_blocking` — 验证动画不阻塞复活
>
> **注意事项：**
> - 不要修改 `CDead` 组件的字段定义，除非 tween 需要存储在组件上（此时加 `_tween` 字段即可）
> - 不要修改 `gol_game_state.gd` 中的 `_respawn_player()` 函数，该函数逻辑正确
> - 不要修改 `resources/recipes/player.tres`
> - 实现完成后运行单元测试确认通过
> - 将产出文档命名为 `02-coder-death-respawn-fix.md`
