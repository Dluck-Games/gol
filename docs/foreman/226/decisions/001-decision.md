# Decision 1 — 2026-04-02 00:00
**Trigger:** 新 issue #226 — 元素子弹添加 VFX 特效，调度轮次 0/3，无历史决策
**Assessment:** 全新 issue，需求清晰度中等。Issue 描述了期望行为（不同元素类型子弹的粒子/特效，覆盖飞行轨迹和命中）但备注提到"具体特效风格和资产待设计确认"。项目已有成熟的 VFX 实现模式（代码生成 GPUParticles2D，见 SElementalVisual、SAreaEffectModifierRender），且元素系统完整支持 4 种元素（FIRE/WET/COLD/ELECTRIC）。所有元素武器共用同一个 bullet_recipe（bullet_normal.tres），子弹本身不含元素信息——元素来源是发射者的 CElementalAttack 组件，通过 SDamage._apply_bullet_effects() 传递给目标。因此子弹 VFX 需要在 render 系统中读取子弹发射者的元素类型来决定特效样式。这是一个纯新增功能，不涉及既有逻辑变更，Planner 可以完整规划。
**Action:** spawn @planner
**Task:** initial-analysis
**Model:** glm-5.0-turbo-ioa
**Guidance:** 这是一个新增 render 系统，为飞行中的元素子弹添加粒子拖尾特效。重点关注：(1) 如何从子弹实体获取其发射者的元素类型（可能需要在 CBullet 中新增 owner_element_type 字段，或在 render 时向上查找）；(2) 参考 SElementalVisual 的代码生成粒子模式，为 4 种元素设计飞行拖尾粒子参数；(3) 命中特效是否在本 issue 范围内（Issue 要求覆盖"飞行轨迹和命中时的表现"，但命中已有 hit_flash shader，需评估是否还需额外粒子）。Issue 备注"资产待设计确认"意味着需要使用代码生成粒子而非美术资源。
**TL Context for Planner:**
> ## 任务：为 Issue #226 编写 initial-analysis 计划
>
> ### Issue 需求
> 为元素子弹（FIRE/WET/COLD/ELECTRIC）添加 VFX 特效，覆盖飞行轨迹和命中表现。
>
> ### 关键架构约束
> 1. **子弹不含元素信息**：`bullet_normal.tres` 是所有武器共用的子弹配方，组件为 `CBullet(CMovement, CTransform, CSprite, CBullet, CCollision, CLifetime)`，无元素字段
> 2. **元素来源**：发射者的 `CWeapon` 引用的武器配方（如 `weapon_fire.tres`）带 `CElementalAttack` 组件，通过 `SFireBullet` 创建子弹时仅设置了 `CBullet.owner_entity`
> 3. **元素传递**：`SDamage._apply_bullet_effects()` 从子弹的 `owner_entity` 读取 `CElementalAttack`，调用 `ElementalUtils.apply_attack()`
> 4. **VFX 模式**：项目全部使用代码生成 `GPUParticles2D`，不使用场景文件。参考 `SElementalVisual`（`gol-project/scripts/systems/s_elemental_visual.gd`）的粒子配置风格
> 5. **Render 系统**：VFX 系统归 `render` 组。现有 render 系统：`SElementalVisual`（ affliction 粒子）、`SAreaEffectModifierRender`（区域雾效）、`SAnimation`（精灵渲染+元素光效）、`SRenderView`（渲染层）
>
> ### 需要决策的设计问题
> - 子弹如何知道自己携带什么元素？选项：A) 在 CBullet 新增 element_type 字段，SFireBullet 创建时从发射者复制；B) render 系统通过 owner_entity 实时查询
> - 命中特效范围：Issue 要求命中表现，但 SDamage 已有 hit_flash shader 效果。是否需要为元素子弹额外添加命中粒子爆发？
> - 是否需要为 4 种元素分别创建子弹配方，还是继续共用 bullet_normal？
>
> ### 必读文件
> - `gol-project/scripts/systems/s_elemental_visual.gd` — 粒子 VFX 参考实现
> - `gol-project/scripts/systems/s_fire_bullet.gd` — 子弹创建流程
> - `gol-project/scripts/systems/s_damage.gd` — 命中处理和 hit_flash
> - `gol-project/scripts/components/c_bullet.gd` — 子弹组件定义
> - `gol-project/scripts/components/c_elemental_attack.gd` — 元素类型枚举
> - `gol-project/scripts/utils/elemental_utils.gd` — 元素工具类
> - `gol-project/resources/recipes/bullet_normal.tres` — 子弹配方
> - `gol-project/resources/recipes/weapon_fire.tres` — 元素武器示例
> - `gol-project/AGENTS.md` — 项目架构和命名规范
>
> ### 产出要求
> 计划文档写入 `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/01-planner-bullet-vfx-analysis.md`，包含：方案设计、影响文件列表、修改点、测试策略。使用中文。
