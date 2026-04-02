# Decision 4 — 2026-04-02 08:30
**Trigger:** doc_validation_failed + commit_failed — 上轮 coder(Decision 003, implement) 产出验证失败
**Assessment:** Commit `14c1a38` 仅包含 `AGENTS.md` 和 `CLAUDE.md` 的文档变更，无任何实际游戏代码实现（无 `c_bullet.gd`、`s_bullet_vfx.gd`、`s_damage.gd`、`s_fire_bullet.gd`、测试文件）。分支 `foreman/issue-226-vfx` 从未创建（commit 在 detached HEAD 上），push 失败。这是 coder 的第 2 次尝试（Decision 002 首次派发、Decision 003 重新派发），两次均未产生有效代码产出。当前为调度轮次 1/3，尚未到 abandon 阈值，但已用掉 2/3 的 coder 重试机会。Planner 产出质量已确认（Decision 002），方案本身无问题。重新派发 coder(implement)，使用 kimi-k2.5-ioa 模型，强化 TL Context 中对代码产出的要求。
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**Guidance:** 工作区当前有 commit 14c1a38 在 detached HEAD（仅含文档变更，可忽略）。你需要：(1) 先 `git checkout -b foreman/issue-226-vfx` 创建分支（基于 main，`git checkout main && git checkout -b foreman/issue-226-vfx`）；(2) 严格按计划文档的 6 个步骤实现代码变更；(3) 编写迭代文档。**关键：不要修改 AGENTS.md 或 CLAUDE.md，只写游戏代码和测试**。
**TL Context for Coder:**
> ## 任务：实现 Issue #226 — 元素子弹 VFX 特效（第 3 次尝试）
>
> ### 前置操作
> 1. `git checkout main && git pull origin main` — 切回 main 并拉取最新
> 2. `git checkout -b foreman/issue-226-vfx` — 创建工作分支
>
> ### 计划文档
> 实现方案详见 `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/01-planner-bullet-vfx-analysis.md`，请完整 Read 后按步骤执行。
>
> ### 实现顺序（严格遵循）
> 1. **修改 `gol-project/scripts/components/c_bullet.gd`** — 新增 `var element_type: int = -1`
> 2. **修改 `gol-project/scripts/systems/s_fire_bullet.gd`** — `_create_bullet()` 中从发射者 `CElementalAttack` 复制 `element_type`，顶部新增 `COMPONENT_ELEMENTAL_ATTACK` preload
> 3. **新建 `gol-project/scripts/systems/s_bullet_vfx.gd`** — render 组系统，飞行拖尾粒子。参考 `gol-project/scripts/systems/s_elemental_visual.gd` 的代码生成 GPUParticles2D 模式，参考 `gol-project/scripts/systems/s_area_effect_modifier_render.gd` 的 `_cleanup_stale_views()` 清理模式
> 4. **修改 `gol-project/scripts/systems/s_damage.gd`** — 在 `_process_bullet_collision()` 的 `remove_entity` 前新增 `_spawn_elemental_hit_particles()` 方法（one_shot，自清理）
> 5. **编写测试** — 单元测试 `gol-project/tests/unit/system/test_bullet_vfx.gd`，集成测试 `gol-project/tests/integration/test_bullet_vfx.gd` 和 `gol-project/tests/integration/test_bullet_hit_vfx.gd`
> 6. **更新 `gol-project/scripts/systems/AGENTS.md`** — 在 Render Group 表格新增 SBulletVFX 条目
>
> ### 关键约束
> - **禁止修改** 根目录的 `AGENTS.md` 和 `CLAUDE.md` — 只修改 `gol-project/` 下的文件
> - 所有 VFX 使用代码生成 `GPUParticles2D`，不使用场景文件
> - 颜色常量从 `gol-project/scripts/utils/elemental_utils.gd` 复用
> - SBulletVFX 必须有 `_cleanup_stale_views()` 防护
> - 命中粒子添加到 `get_tree().current_scene`，finished 信号 queue_free
> - `element_type = -1` 表示无元素，VFX 系统自动跳过
>
> ### 必读文件
> - `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/01-planner-bullet-vfx-analysis.md` — 完整方案和粒子参数表
> - `gol-project/AGENTS.md` — 项目架构和命名规范
> - `gol-project/scripts/systems/AGENTS.md` — 系统模板和分组规则
> - `gol-project/tests/AGENTS.md` — 测试模式规范
> - `gol-project/scripts/systems/s_elemental_visual.gd` — VFX 参考实现
> - `gol-project/scripts/systems/s_area_effect_modifier_render.gd` — 清理模式参考
