# Decision 2 — 2026-04-02 00:04
**Trigger:** Planner 完成 initial-analysis，产出 `01-planner-bullet-vfx-analysis.md`
**Assessment:** Planner 产出质量高。方案完整覆盖 Issue 两个阶段（飞行拖尾 + 命中爆发），3 个设计决策均有充分理由（CBullet 新增 element_type 字段解耦发射者、命中粒子补充 hit_flash、共用 bullet_normal 配方）。影响面分析清晰，直接修改 3 个文件、新增 1 个文件、测试契约 6 条覆盖单元和集成。架构约束引用正确（render 组、ECS 数据驱动、代码生成 VFX）。风险识别合理（性能、清理时序、scene tree 残留）。计划可操作，交给 coder 实现。
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**Guidance:** 严格按 Planner 实现步骤 1-6 顺序执行。先读参考文件（SElementalVisual、SAreaEffectModifierRender）理解代码生成 VFX 模式，再动手写代码。粒子参数按计划文档中的表格设置，颜色常量复用 ElementalUtils。
**TL Context for Coder:**
> ## 任务：实现 Issue #226 — 元素子弹 VFX 特效
>
> ### 计划文档
> 实现方案详见 `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/01-planner-bullet-vfx-analysis.md`，请完整 Read 后按步骤执行。
>
> ### 实现顺序（严格遵循）
> 1. **修改 `scripts/components/c_bullet.gd`** — 新增 `var element_type: int = -1`
> 2. **修改 `scripts/systems/s_fire_bullet.gd`** — `_create_bullet()` 中从发射者 `CElementalAttack` 复制 `element_type`
> 3. **新建 `scripts/systems/s_bullet_vfx.gd`** — render 组系统，飞行拖尾粒子。参考 `scripts/systems/s_elemental_visual.gd` 的代码生成 GPUParticles2D 模式，参考 `scripts/systems/s_area_effect_modifier_render.gd` 的 `_cleanup_stale_views()` 清理模式
> 4. **修改 `scripts/systems/s_damage.gd`** — 在 `_process_bullet_collision()` 的 `remove_entity` 前生成命中粒子爆发（one_shot，自清理）
> 5. **编写测试** — 单元测试 `tests/unit/system/test_bullet_vfx.gd`，集成测试 `tests/integration/test_bullet_vfx.gd` 和 `tests/integration/test_bullet_hit_vfx.gd`
> 6. **更新 `scripts/systems/AGENTS.md`** — 在 Render Group 表格新增 SBulletVFX 条目
>
> ### 关键约束
> - 所有 VFX 使用代码生成 `GPUParticles2D`，不使用场景文件
> - 颜色常量从 `scripts/utils/elemental_utils.gd` 复用
> - SBulletVFX 必须有 `_cleanup_stale_views()` 防护（子弹可能通过 `remove_entity()` 直接移除）
> - 命中粒子添加到 `get_tree().current_scene`（非实体子节点），finished 信号 queue_free
> - `element_type = -1` 表示无元素，VFX 系统自动跳过
> - `preload` 声明：`SDamage` 已有 `COMPONENT_ELEMENTAL_ATTACK`，`SFireBullet` 需要新增
>
> ### 必读文件
> - 计划文档（上方路径）— 完整方案和粒子参数表
> - `gol-project/scripts/systems/s_elemental_visual.gd` — VFX 参考实现
> - `gol-project/scripts/systems/s_area_effect_modifier_render.gd` — 清理模式参考
> - `gol-project/scripts/systems/s_fire_bullet.gd` — 子弹创建逻辑（修改点在第 113-135 行）
> - `gol-project/scripts/systems/s_damage.gd` — 命中处理（修改点在第 60-105 行）
> - `gol-project/scripts/systems/AGENTS.md` — 系统模板和分组规则
> - `gol-project/tests/AGENTS.md` — 测试模式规范
