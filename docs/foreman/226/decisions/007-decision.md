# Decision 7 — 2026-04-03 19:20
**Trigger:** `doc_validation_failed` — reviewer rework-review 文档 `06-reviewer-rework-fix-verify.md` 缺少 `## 验证清单`、`## 发现的问题`、`## 测试契约检查` 三个标准审查章节
**Assessment:** Reviewer rework-review 实质内容完整且质量高：逐项验证了 2 个 Important 修复（集成测试 impact 验证 + 空单元测试 skip() 标记），验证点覆盖全面（函数调用链、CPUParticles2D 类型检查、await 处理、skip 标记），结论明确 approve 并建议进入 e2e-acceptance。缺少的三个章节是文档格式问题而非实质内容缺失。回顾历史：Decision 5 已对 coder 文档做过一次文档格式修补（消耗了一次迭代），当前调度轮次 2/3，不应再浪费在格式修补上。reviewer approve 结论实质有效，应推进到 e2e-acceptance。
**Action:** spawn @tester
**Task:** e2e-acceptance
**Model:** glm-5.0-turbo-ioa
**Guidance:** E2E 验收：在真实游戏环境中验证元素子弹 VFX（飞行轨迹 + 命中 impact）是否正确表现。

**TL Context for @tester:**
> ## Issue #226: 元素子弹 VFX — E2E 验收
>
> **实现方案：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/01-planner-element-bullet-vfx.md`
> **实现文档：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/02-coder-element-bullet-vfx.md`
> **审查报告：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/03-reviewer-element-bullet-vfx.md`（全量审查，架构全部通过）
> **修复验证：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/06-reviewer-rework-fix-verify.md`（rework approve）
>
> ### 验收要点
>
> 在真实游戏环境中验证以下场景：
>
> 1. **元素子弹飞行轨迹**：使用 4 种元素武器（火/水/冰/电）射击，观察子弹飞行时是否有对应的粒子轨迹效果
> 2. **命中 impact 特效**：元素子弹命中目标时，是否产生对应的命中爆发粒子效果
> 3. **普通子弹无 VFX**：使用无元素的普通武器射击，确认无任何 VFX 粒子
> 4. **视觉表现**：粒子效果是否挂载到正确位置、是否随子弹移动、命中后是否正确自清理
>
> ### 涉及的系统文件
> - `scripts/systems/s_bullet_vfx.gd` — 核心 VFX 系统（render group）
> - `scripts/systems/s_fire_bullet.gd` — 子弹创建（传递 element_type）
> - `scripts/systems/s_damage.gd` — 命中时调用 spawn_impact()
> - `scripts/components/c_bullet.gd` — 新增 element_type 字段
>
> ### 技术说明
> - 当前为代码框架层实现，粒子使用 CPUParticles2D 占位参数
> - VFX 配置在 `s_bullet_vfx.gd` 中以方法形式硬编码（4 种元素各有独立的 trail/impact 配置）
> - Trail 粒子在 `_create_trail()` 中创建，跟随 entity 位置同步
> - Impact 粒子在 `SDamage._process_bullet_collision()` 命中路径中调用 `SBulletVfx.spawn_impact()` 触发
