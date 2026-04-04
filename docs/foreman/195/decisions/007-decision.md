# Decision 7 — 2026-04-04 07:55
**Trigger:** 新调度周期启动，上一周期（D1-D6）因环境权限问题 abandon 终止。文档 `02-coder-git-workflow-completion.md` 未通过格式验证（缺少"完成的工作""测试契约覆盖""决策记录"章节）。
**Assessment:**
- 上一个调度周期已完成全部技术工作：v2 方案、代码实现（3 文件）、测试（T1-T7），但因 Bash 权限连续失败导致无法 commit/push，最终 D6 以 abandon 终止
- 当前是**全新调度周期**（轮次 0/3），使用新 workspace `ws_20260404075451._10253156`
- 触发事件为文档格式验证失败，但根本原因仍是：**git 工作流未完成，变更未提交到分支**
- 新 workspace 是全新的 worktree checkout，旧 workspace 的**未提交变更可能不会自动携带**——coder 必须先验证文件是否存在
- 符合"文件未提交/git diff 缺失"场景 → 强制 spawn @coder rework

**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** 新周期首轮。代码可能需要重新实现或从旧 workspace 搬运。第一步必须执行 git diff 自验。

**TL Context for @coder:**
> ## 任务：在新 workspace 完成冻结伤害动画修复的 git 提交推送 + PR
>
> ### 背景
> Issue #195 的上一个调度周期（D1-D6）已 abandon。v2 方案和代码实现均已完成但因环境权限问题未能 commit/push。
> 现在是**全新调度周期**，workspace 已切换为新路径。
>
> ### 第一步强制自验（必须最先执行）
>
> 在 workspace 根目录 `/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260404075451._10253156` 执行：
> ```bash
> git diff main...HEAD --name-only
> git status --short
> ```
>
> **根据结果分支处理：**
>
> #### 分支 A：diff 为空且文件不存在（最可能）
> 新 worktree 不包含旧 workspace 的未提交变更。你需要**重新实现以下 3 个文件**：
>
> 1. **`gol-project/scripts/components/c_animation.gd`** — 在现有 CAnimation 组件中新增字段：
>    - `animation_was_paused: bool = false`（放在 `animated_sprite_node` 字段之后）
>
> 2. **`gol-project/scripts/systems/s_animation.gd`** — 两处修改：
>    - **修改 A**：在 `sprite.pause()` 之后添加 `anim_comp.animation_was_paused = true`
>    - **修改 B**：将原来的简单动画切换守卫替换为三分支恢复逻辑：
>      - 同名动画 + `animation_was_paused == true` → `sprite.paused = false`（续播不重置帧）
>      - 异名动画 → `sprite.play(next_animation)`（正常切换）
>      - 两种情况都清理 `animation_was_paused = false`
>
> 3. **`gol-project/tests/unit/systems/test_animation_freeze_recovery.gd`**（新建）— T1-T7 共 7 个测试用例：
>    - T1: walk 冻结→解冻保持帧位置
>    - T2: idle 冻结→解冻保持帧位置
>    - T3: 冻结后状态变化切换动画
>    - T4: 无冻结时正常行为不变
>    - T5: 恢复后标记被清理
>    - T6: 多次冻结-解冻循环
>    - T7: 目标动画缺失时的健壮性
>
> 方案参考文档：先 Read `docs/superpowers/plans/2026-04-04-issue195-freeze-animation-loss-v2-redesign.md` 获取完整设计细节和行号指引。
>
> #### 分支 B：diff 有内容或文件已存在
> 直接进入 git 工作流步骤。
>
> ### 第二步：Git 工作流
>
> ```bash
> # 确认当前分支应为 foreman/issue-195
> git branch --show-current
>
> # 暂存并提交
> git add gol-project/scripts/components/c_animation.gd \
>        gol-project/scripts/systems/s_animation.gd \
>        gol-project/tests/unit/systems/test_animation_freeze_recovery.gd
> git commit -m "fix(#195): freeze damage animation recovery - add paused state tracking"
>
> # 推送 submodule
> git push -u origin foreman/issue-195
> ```
>
> ### 第三步：运行测试
>
> ```bash
> /Users/dluckdu/Documents/Github/gol/gol-tools/foreman/bin/coder-run-tests.sh
> ```
> 记录测试结果到迭代文档。
>
> ### 第四步：创建 PR
>
> ```bash
> gh pr create --base main \
>   --title "fix(#195): freeze damage animation recovery" \
>   --body "添加冻结伤害时动画状态追踪（animation_was_paused），解冻后恢复播放而不重置帧位置，消除视觉跳跃"
> ```
>
> ### 迭代文档要求
>
> 输出迭代文档到 `/Users/dluckdu/Documents/Github/gol/docs/foreman/195/iterations/03-coder-new-cycle-completion.md`，**必须包含以下章节**（上次因此处缺失被拒）：
> - ## 完成的工作（列出每个文件的修改点）
> - ## 测试契约覆盖（T1-T7 覆盖表格）
> - ## 决策记录（遵循了哪些方案决策）
> - ## 仓库状态（branch、commit SHA、修改文件列表）
>
> ### 约束
> - 遵守 monorepo 工作流：在 gol-project submodule 内操作，先 push submodule
> - 不要修改方案文档，只实现和提交
> - 如果测试失败，修复后再提交，不要跳过 CI gate
