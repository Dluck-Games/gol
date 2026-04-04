# Decision 2 — 2026-04-03 18:10
**Trigger:** planner 完成 `01-planner-element-bullet-vfx.md`
**Assessment:** Planner 文档质量优秀。需求分析准确识别了关键架构问题（元素信息传递断层），影响面清晰（修改 3 文件 + 新建 1 系统 + 2 测试），实现方案具体可操作（含代码示例、粒子配置、参考文件路径），测试契约完备（8 单元 + 3 集成），风险点均有缓解方案。方案完全遵循 AGENTS.md 的 ECS/MVVM 架构规范。无需迭代，可直接进入实现阶段。
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**Guidance:** 按 planner 文档的 Step 1-7 顺序实现。重点关注：1) CBullet.element_type 字段扩展；2) SFireBullet 元素类型传递；3) SBulletVfx 系统（render group）的 trail + impact 粒子逻辑；4) SDamage 命中 VFX 触发；5) 单元测试和集成测试；6) AGENTS.md 更新。粒子效果使用代码生成（参照 s_elemental_visual.gd 和 s_dead.gd 模式），不依赖美术资产。

**TL Context for @coder:**
> ## Issue #226: 元素子弹添加 VFX 特效 — 实现阶段
>
> **规划文档（必读）：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/01-planner-element-bullet-vfx.md`
>
> **实现步骤（按顺序）：**
>
> ### Step 1: 扩展 CBullet 组件
> **文件**：`scripts/components/c_bullet.gd`
> - 新增 `@export var element_type: int = -1`（-1 = 无元素）
> - 遵循 Component 纯数据原则
>
> ### Step 2: 修改 SFireBullet 传递元素类型
> **文件**：`scripts/systems/s_fire_bullet.gd`
> - 在 `_create_bullet()` 中，创建子弹后拷贝射击者 `CElementalAttack.element_type` 到子弹的 `CBullet.element_type`
> - 注意 preload `CElementalAttack`，参照 `s_damage.gd` 的 const 模式
>
> ### Step 3: 新建 SBulletVfx 系统（核心）
> **文件**：`scripts/systems/s_bullet_vfx.gd`
> - `class_name SBulletVfx extends System`，group = `"render"`
> - query: `q.with_all([CBullet, CTransform]).with_none([CDead])`
> - Trail 粒子：GPUParticles2D，使用 `_trails: Dictionary` 缓存，参照 `SElementalVisual` 模式
> - Impact 粒子：CPUParticles2D，`one_shot = true`，static 方法 `spawn_impact()`，参照 `s_dead.gd:_spawn_debris()` 模式
> - 4 种元素配置（FIRE/WET/COLD/ELECTRIC），参数见 planner 文档表格
> - `component_removed` 信号清理 trail 数据
>
> ### Step 4: 修改 SDamage 触发命中 VFX
> **文件**：`scripts/systems/s_damage.gd`
> - 在 `_process_bullet_collision()` 中，`remove_entity` 前调用 `SBulletVfx.spawn_impact()`
>
> ### Step 5: 单元测试
> **文件**：`tests/unit/system/test_bullet_vfx.gd`（新建）
> - 8 个测试用例，见 planner 文档"测试契约"节
>
> ### Step 6: 集成测试
> **文件**：`tests/integration/test_bullet_vfx.gd`（新建）
> - 3 个测试用例，见 planner 文档"测试契约"节
>
> ### Step 7: 更新 AGENTS.md
> - `scripts/components/AGENTS.md`：CBullet 描述加入 element_type
> - `scripts/systems/AGENTS.md`：Render Group 新增 SBulletVfx 条目
>
> **关键参考文件：**
> - `scripts/systems/s_elemental_visual.gd` — trail 粒子创建模式
> - `scripts/systems/s_dead.gd:186-208` — impact 粒子（CPUParticles2D one_shot）
> - `scripts/systems/s_area_effect_modifier_render.gd` — _views Dictionary 缓存模式
> - `tests/unit/system/test_area_effect_modifier_render.gd` — 单元测试参考
> - `tests/AGENTS.md` — 测试框架指南
>
> **约束：**
> - Component 纯数据，逻辑全在 System
> - 静态类型 everywhere
> - Tab 缩进，class_name 必须声明
> - 文件命名：`s_bullet_vfx.gd` / `test_bullet_vfx.gd`
> - 粒子效果代码生成，不依赖外部资产
> - `element_type = -1`（默认）的子弹不产生任何 VFX
> - Impact 粒子挂载到 `ECS.world`（非 entity），确保子弹移除后仍存活
>
> **提交要求：**
> - 完成后 `git add` 所有新建和修改的文件
> - 提交 message：`feat: add VFX effects for elemental bullets (#226)`
