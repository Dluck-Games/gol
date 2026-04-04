# Decision 3 — 2026-04-03 18:25
**Trigger:** @coder 完成 `02-coder-element-bullet-vfx.md` — 实现阶段交付
**Assessment:** Coder 按 planner 方案完成了全部 7 个步骤，产出 8 个文件（3 修改 + 1 新系统 + 2 新测试 + 2 AGENTS.md 更新）。测试覆盖：11 个单元测试（含 3 个扩展）+ 3 个集成测试，其中 2 个 impact 相关测试为部分覆盖（需 World 环境）。无未完成事项。实现决策与 planner 方案一致。下一步进入 review 阶段，验证代码质量、架构合规性和测试充分性。
**Action:** spawn @reviewer
**Task:** full-review
**Model:** glm-5.0-turbo-ioa
**Guidance:** 对照 planner 方案逐项验证 coder 产出。重点关注：1) SBulletVfx 系统架构是否合规（render group、query 模式、_trails 缓存、component_removed 清理）；2) SDamage 中 impact 触发时机是否正确（remove_entity 之前）；3) 测试覆盖是否充分（特别是 spawn_impact 的部分覆盖是否可接受）；4) AGENTS.md 命名规范和代码风格是否一致。

**TL Context for @reviewer:**
> ## Issue #226: 元素子弹添加 VFX 特效 — 全量审查
>
> **规划文档：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/01-planner-element-bullet-vfx.md`
> **实现文档：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/02-coder-element-bullet-vfx.md`
>
> **审查范围（8 个文件）：**
>
> ### 修改文件
> 1. `scripts/components/c_bullet.gd` — 新增 `element_type: int = -1`，验证纯数据原则
> 2. `scripts/systems/s_fire_bullet.gd` — 新增元素类型拷贝逻辑，验证 preload 模式和时机
> 3. `scripts/systems/s_damage.gd` — 新增 `SBulletVfx.spawn_impact()` 调用，验证在 `remove_entity` 之前
>
> ### 新建文件
> 4. `scripts/systems/s_bullet_vfx.gd` — **核心审查目标**：
>    - `class_name SBulletVfx extends System`，group = `"render"`
>    - query: `CBullet + CTransform`，排除 `CDead`
>    - `_trails` Dictionary 缓存 + `component_removed` 信号清理
>    - 4 种元素 trail 配置（FIRE/WET/COLD/ELECTRIC）
>    - `spawn_impact()` 静态方法，CPUParticles2D one_shot，挂载到 `ECS.world`
> 5. `tests/unit/system/test_bullet_vfx.gd` — 8 契约测试 + 3 扩展 = 11 个测试
> 6. `tests/integration/test_bullet_vfx.gd` — 3 个集成测试（1 个 impact 为部分覆盖）
>
> ### 文档更新
> 7. `scripts/components/AGENTS.md` — CBullet 描述更新
> 8. `scripts/systems/AGENTS.md` — Render Group 新增 SBulletVfx
>
> **审查重点：**
> - **架构合规**：SBulletVfx 是否正确放入 render group？query 模式是否与 AGENTS.md 一致？
> - **数据流**：SFireBullet(gameplay) → CBullet.element_type → SBulletVfx(render) 的 group 顺序是否保证正确？
> - **清理逻辑**：`component_removed` 信号处理是否完善？子弹超时移除（SLife）时 trail 是否正确清理？
> - **Impact 粒子**：挂在 `ECS.world` 是否合理？`spawn_impact()` 静态方法设计是否会导致初始化问题？
> - **测试充分性**：spawn_impact 的部分覆盖是否可接受？集成测试场景是否足够验证端到端行为？
> - **代码风格**：static typing、Tab 缩进、class_name、文件命名
>
> **参考架构文件：**
> - `gol-project/AGENTS.md`
> - `gol-project/scripts/components/AGENTS.md`
> - `gol-project/scripts/systems/AGENTS.md`
> - `gol-project/tests/AGENTS.md`
>
> **参考实现文件（对比审查）：**
> - `gol-project/scripts/systems/s_elemental_visual.gd` — trail 粒子创建模式
> - `gol-project/scripts/systems/s_dead.gd` — impact 粒子（CPUParticles2D one_shot）+ ECS.world 挂载
> - `gol-project/scripts/systems/s_area_effect_modifier_render.gd` — _views Dictionary 缓存模式
>
> **约束：**
> - Component 必须纯数据
> - System 必须设置 group
> - 必须声明 class_name
> - 静态类型 everywhere
> - 不依赖外部美术资产，粒子代码生成
>
> **产出要求：** 审查报告需包含：1) 每个文件的逐项审查结果（pass/fail + 原因）；2) 架构合规性总结；3) 测试覆盖评估；4) 结论：approve / rework（附具体修复清单）。
