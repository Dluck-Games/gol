# Decision 8 — 2026-04-04 08:03
**Trigger:** 文档验证失败 — `02-coder-git-workflow-completion.md` 缺少必需章节（"完成的工作"、"测试契约覆盖"、"决策记录"）
**Assessment:**
- 当前是**新调度周期**（轮次 1/3），workspace 已切换为新路径 `ws_20260404075451._10253156`
- Decision 7 已 spawn @coder rework 要求其在新 workspace 核对代码并产出格式合规的迭代文档
- 触发事件表明：coder 的输出文档未通过格式验证，具体缺失三个必需章节
- 检查 iterations 目录发现**无 `03-*` 新文档存在** — 说明 D7 分配的 coder 要么未能产出文档，要么产出的文档仍沿用旧名称且格式不合格
- 根因判断：coder 未在新 workspace 完成工作，或完成了但未按要求格式输出迭代文档
- 符合"文件未提交/git diff 缺失"类场景的延伸 — 需要 coder 重新核对并补全交付物

**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** 新周期第 1 次 rework。核心问题是迭代文档格式不合规 + 需确认新 workspace 中代码文件实际状态。不要执行任何 git 提交命令。

**TL Context for @coder:**
> ## 任务：核对代码文件 + 输出格式合规的迭代文档
>
> ### 背景
> 你是新调度周期的首轮 coder（轮次 1/3）。上一周期的迭代文档 `02-coder-git-workflow-completion.md` 因缺少必需章节被拒。你需要在新 workspace 中完成工作。
>
> ### Workspace 信息
> - **当前路径**: `/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260404075451._10253156`
> - **分支**: `foreman/issue-195`
>
> ### 第一步：核对代码文件是否存在（必须最先执行）
>
> 使用 Read 工具逐一检查以下 3 个文件的**实际内容**：
>
> 1. `gol-project/scripts/components/c_animation.gd` — 确认是否包含 `animation_was_paused: bool = false` 字段
> 2. `gol-project/scripts/systems/s_animation.gd` — 确认是否包含暂停标记设置和三分支恢复逻辑
> 3. `gol-project/tests/unit/systems/test_animation_freeze_recovery.gd` — 确认 T1-T7 测试用例是否存在
>
> **如果文件不存在或内容不完整**：
> - 先 Read 方案文档获取完整设计：`docs/superpowers/plans/2026-04-04-issue195-freeze-animation-loss-v2-redesign.md`
> - 再 Read 原始源文件了解当前代码结构
> - 重新实现缺失的修改（使用 Edit 工具精确修改，不要用 Write 覆盖整个文件）
>
> ### 第二步：运行测试（如可执行）
>
> 如有权限，运行测试脚本确认通过：
> ```bash
> /Users/dluckdu/Documents/Github/gol/gol-tools/foreman/bin/coder-run-tests.sh
> ```
> 记录结果。
>
> ### 第三步：输出迭代文档（关键 — 必须严格遵循格式）
>
> 写入 `/Users/dluckdu/Documents/Github/gol/docs/foreman/195/iterations/03-coder-new-cycle-rework.md`
>
> **必须包含以下章节标题（完全匹配）：**
>
> ```markdown
> # Coder 迭代文档 - Issue #195 新周期 Rework
>
> ## 完成的工作
> （列出每个文件的修改点，包括文件路径、修改位置、修改内容）
>
> ## 测试契约覆盖
> （T1-T7 表格，每行包含：用例编号、名称、覆盖状态）
>
> ## 决策记录
> （说明遵循了哪些方案决策，引用方案文档）
>
> ## 仓库状态
> （branch 名称、修改文件列表、当前 git 状态描述）
> ```
>
> **注意**：以上四个 `##` 章节标题必须一字不差，否则会再次触发验证失败。
>
> ### 约束
> - **禁止** 执行 `git add`、`git commit`、`git push`、`gh pr create` — 这些由框架处理
> - **禁止** 修改方案文档（plans 目录下的 .md 文件）
> - 所有代码修改仅限上述 3 个文件
> - 如果测试失败，先修复代码再记录，不要跳过
