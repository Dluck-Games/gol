# Decision 3 — 2026-04-02 08:00
**Trigger:** orphan_state — Decision 002 派发 coder(implement) 但未产生任何实现产出（无 commit、无迭代文档），流水线停滞
**Assessment:** Planner 产出已完成且质量高（Decision 002 确认），工作区无任何代码变更。coder 未成功执行，属于调度故障而非方案问题。计划文档完整可操作，无需回退 planner，直接重新派发 coder(implement)。
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**Guidance:** 严格按计划文档步骤 1-6 顺序实现。工作区当前为干净状态，无前置修改。先完整 Read 计划文档和参考文件，再动手写代码。每完成一个步骤确保代码可编译。
**TL Context for Coder:**
> ## 任务：实现 Issue #226 — 元素子弹 VFX 特效
>
> ### 计划文档
> 实现方案详见 `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/01-planner-bullet-vfx-analysis.md`，请完整 Read 后按步骤执行。
>
> ### 实现顺序（严格遵循）
> 1. **修改 `gol-project/scripts/components/c_bullet.gd`** — 新增 `var element_type: int = -1`
> 2. **修改 `gol-project/scripts/systems/s_fire_bullet.gd`** — `_create_bullet()` 中从发射者 `CElementalAttack` 复制 `element_type`
> 3. **新建 `gol-project/scripts/systems/s_bullet_vfx.gd`** — render 组系统，飞行拖尾粒子。参考 `gol-project/scripts/systems/s_elemental_visual.gd` 的代码生成 GPUParticles2D 模式，参考 `gol-project/scripts/systems/s_area_effect_modifier_render.gd` 的 `_cleanup_stale_views()` 清理模式
> 4. **修改 `gol-project/scripts/systems/s_damage.gd`** — 在 `_process_bullet_collision()` 的 `remove_entity` 前生成命中粒子爆发（one_shot，自清理）
> 5. **编写测试** — 单元测试 `gol-project/tests/unit/system/test_bullet_vfx.gd`，集成测试 `gol-project/tests/integration/test_bullet_vfx.gd` 和 `gol-project/tests/integration/test_bullet_hit_vfx.gd`
> 6. **更新 `gol-project/scripts/systems/AGENTS.md`** — 在 Render Group 表格新增 SBulletVFX 条目
>
> ### 关键约束
> - 所有 VFX 使用代码生成 `GPUParticles2D`，不使用场景文件
> - 颜色常量从 `gol-project/scripts/utils/elemental_utils.gd` 复用
> - SBulletVFX 必须有 `_cleanup_stale_views()` 防护（子弹可能通过 `remove_entity()` 直接移除）
> - 命中粒子添加到 `get_tree().current_scene`（非实体子节点），finished 信号 queue_free
> - `element_type = -1` 表示无元素，VFX 系统自动跳过
> - `preload` 声明：`SFireBullet` 需要新增 `COMPONENT_ELEMENTAL_ATTACK`，`SDamage` 已有
> - 新建系统文件放在 `gol-project/scripts/systems/` 目录下会被 `GOLWorld._load_all_systems()` 自动发现
>
> ### 必读文件
> - 计划文档（上方路径）— 完整方案和粒子参数表
> - `gol-project/AGENTS.md` — 项目架构和命名规范
> - `gol-project/scripts/systems/AGENTS.md` — 系统模板和分组规则
> - `gol-project/tests/AGENTS.md` — 测试模式规范
> - `gol-project/scripts/systems/s_elemental_visual.gd` — VFX 参考实现
> - `gol-project/scripts/systems/s_area_effect_modifier_render.gd` — 清理模式参考
