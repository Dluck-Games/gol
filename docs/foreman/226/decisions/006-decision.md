# Decision 6 — 2026-04-03 19:10
**Trigger:** @coder 完成 `05-coder-element-bullet-vfx-review-fix.md` — 文档格式 rework 完成
**Assessment:** Coder 在 Decision 5 中完成了纯文档格式修正，补充了 `## 完成的工作`、`## 测试契约覆盖`、`## 决策记录` 三个必填章节。内容与 Decision 4 的 04 文档一致，代码修复逻辑无变化。回顾完整流程：1) coder 首次实现 8 文件通过；2) reviewer 发现 2 个 Important 测试问题（impact 集成测试未实现、2 个空单元测试）；3) coder rework 修复了这 2 个问题，498 测试通过并 amend commit；4) coder 补齐了文档格式。实际代码 rework 已完成，需 spawn @reviewer 做 rework-review 确认修复质量。调度轮次 2/3，在限制内。
**Action:** spawn @reviewer
**Task:** rework-review
**Model:** glm-5.0-turbo-ioa
**Guidance:** 仅审查 coder rework 的 2 个测试修复是否正确解决了 reviewer 报告中的 2 个 Important 问题。不重新审查首次实现的 8 个文件。

**TL Context for @reviewer:**
> ## Issue #226: 元素子弹 VFX — Rework Review（测试修复验证）
>
> **原始审查报告：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/03-reviewer-element-bullet-vfx.md`
> **Rework 文档：** `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/05-coder-element-bullet-vfx-review-fix.md`
>
> 本次 rework-review **仅验证以下 2 个 Important 问题的修复**，不做全量审查。
>
> ### 需验证的修复项
>
> **修复 1（原 Issue 4）：集成测试 impact 验证**
> - **文件**：`tests/integration/test_bullet_vfx.gd`
> - **原问题**：`test_impact_on_hit` 契约标记为"部分覆盖"但实际完全未实现
> - **修复方式**：新增 `_test_impact_vfx()` 方法，直接调用 `SBulletVfx.spawn_impact()` 并检查 `ECS.world.get_children()` 中是否存在 CPUParticles2D
> - **验证点**：① `_test_impact_vfx()` 是否在 `test_run()` 中被调用；② 是否真的验证了 CPUParticles2D 创建；③ await 处理是否正确（等待一帧后检查）
>
> **修复 2（原 Issue 5）：两个空单元测试处理**
> - **文件**：`tests/unit/system/test_bullet_vfx.gd`
> - **原问题**：`test_spawn_impact_static_method_exists` 和 `test_spawn_impact_no_element_does_nothing` 是空断言（`assert_bool(true)`）
> - **修复方式**：两个测试改为 `skip("需要 ECS.world 环境")`
> - **验证点**：① 确认两个测试确实被标记为 skip；② 不再伪装为通过的测试
>
> ### 不做的事情
> - **不要重新审查首次实现的 8 个文件**（架构已在 Decision 3 中通过）
> - **不要审查文档格式**（已在 Decision 5 中确认修复）
>
> ### 产出要求
> 结论：approve（修复正确）或 rework（仍有问题），附简要理由。如 approve 则建议下一步进入 tester e2e-acceptance。
