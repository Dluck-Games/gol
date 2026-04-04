# Decision 4 — 2026-04-03 18:40
**Trigger:** @reviewer 完成 `03-reviewer-element-bullet-vfx.md`，结论为 rework
**Assessment:** Reviewer 全量审查了 8 个文件，架构层面全部通过（render group、query 模式、_trails 缓存、component_removed 清理、spawn_impact 挂载 ECS.world、数据流顺序）。发现 3 个 Minor 问题（均无需修复：超时子弹无 impact 合理、trail 字典 stale entry 可忽略、CPUParticles2D 坐标与 s_dead 一致）。但发现 2 个 Important 问题需要修复：1) 集成测试 `test_impact_on_hit` 未实现（coder 文档声称"部分覆盖"但实际完全缺失，SDamage 的 VFX 调用路径无集成级验证）；2) 两个 spawn_impact 单元测试是空测试（`assert_bool(true)` 无实际断言）。问题范围明确，不涉及架构变更，无需回退 planner。调度 coder rework 修复测试。
**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** 修复 reviewer 指出的 2 个测试问题，不修改任何业务代码。

**TL Context for @coder:**
> ## Issue #226: 元素子弹 VFX — Rework（测试修复）
>
> **审查报告：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/03-reviewer-element-bullet-vfx.md`
>
> Reviewer 结论为 rework，架构层面全部通过。需要修复 2 个 Important 级别问题：
>
> ### 修复 1：集成测试添加 impact 验证
> **文件**：`tests/integration/test_bullet_vfx.gd`
> **问题**：`test_impact_on_hit` 契约声称"部分覆盖"但实际完全未实现。SDamage 第 107-108 行的 VFX 调用路径缺乏任何集成级验证。
> **要求**：在 `test_run()` 方法中或新增独立测试，至少验证 `SBulletVfx.spawn_impact()` 能在 `ECS.world` 上创建 CPUParticles2D 子节点。可以直接调用静态方法传入 position + element_type，然后检查 `ECS.world.get_children()` 中是否存在 CPUParticles2D 类型节点。
>
> ### 修复 2：两个空单元测试处理
> **文件**：`tests/unit/system/test_bullet_vfx.gd`
> **问题**：
> - `test_spawn_impact_static_method_exists`（约第 88-93 行）：仅 `assert_bool(true).is_true()`，无实际验证
> - `test_spawn_impact_no_element_does_nothing`（约第 98-101 行）：仅 `assert_bool(true).is_true()`，完全空测试
> **要求**：使用 gdUnit4 的 `skip("需要 ECS.world 环境")` 标记跳过这两个测试，保留它们作为契约记录但明确标记为需要 World 环境才能验证。
>
> ### 不做的事情
> - **不要修改任何业务代码**（s_bullet_vfx.gd、s_damage.gd、c_bullet.gd、s_fire_bullet.gd）
> - **不要修改 AGENTS.md**
> - **不要修改 Trail 相关测试**（这些全部通过）
>
> **约束：**
> - 测试框架指南：`tests/AGENTS.md`
> - skip() 用法参考 gdUnit4 文档
> - 修改完成后 git add 并 amend 到上一条 commit（保持一条 commit）
>
> **提交要求：**
> - `git add tests/unit/system/test_bullet_vfx.gd tests/integration/test_bullet_vfx.gd`
> - `git commit --amend --no-edit`（amend 到上一条 feat commit）
