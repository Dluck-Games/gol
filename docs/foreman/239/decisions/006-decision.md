# Decision 6 — 2026-04-05 14:05
**Trigger:** @coder 完成 rework（第 2 次尝试），产出迭代文档 `05-coder-rework-test-quality.md`
**Assessment:** Coder 第 2 次 rework（基于 Decision 5 的测试质量要求）产出质量显著优于第 1 次尝试（`04-coder-rework-test-quality.md`）：

**关键改进：**
- **P0 已达成** — 使用 `SubViewport` 创建最小场景树环境，使 `entity.get_viewport()` 返回有效值，T6/T7/T9/T10 现在**真正调用** `_update_display_aim()` 并验证实际组件状态值（如 `display_aim_position == Vector2(-99999, -99999)`），不再是"证明尝试过就放弃"
- **P1 已达成** — 断言从验证前置条件改为验证方法调用后的组件实际值
- **P2 已达成** — 文件头部和函数级注释清晰说明了 gdUnit4 纯单元测试的固有限制，标注 TODO 指向 SceneConfig 集成测试
- **全部 506 测试通过**，无新增回归风险

**与第 1 次 rework（文档 04）的核心差异：**
| 维度 | 第 1 次（04） | 第 2 次（05） |
|------|-------------|-------------|
| Viewport 处理 | 接受 null 提前返回，仅注释说明限制 | 创建 `SubViewport` 环境使方法完整执行 |
| 断言策略 | 验证"已调用方法"（间接） | 验证方法执行后的**实际状态值**（直接） |
| 回归防护能力 | 弱（依赖代码审查发现回滚） | 强（回滚修复代码会导致断言失败） |

调度轮次为 2/3，未超限。生产代码已在 Decision 5 前被 Reviewer 判定 PASS。本次仅需 Reviewer 验证测试改进是否满足其 Rework 要求。
**Action:** spawn @reviewer
**Task:** rework-review
**Model:** glm-5v-turbo-ioa
**Guidance:** 本次是针对 coder 第 2 次 test-quality rework 的审查。重点验证 P0（SubViewport 真实方法调用）、P1（断言改进）、P2（注释完整性）是否达到 Reviewer 在 `03-reviewer-review.md` 中提出的要求。生产代码无需再审。
**TL Context for @reviewer:**
> ## 任务：审查 #239 准心 Bug 修复 — 测试质量 Rework（第 2 轮）
>
> ### 背景
> 你在 `03-reviewer-review.md` 中对生产代码判定 **PASS**，对测试代码判定 **REWORK**，提出了 P0/P1/P2 三级改进要求。
>
> Coder 已完成 **第 2 次 rework**（第 1 次见文档 `04`，本次为文档 `05`）。请评估本轮是否满足你的 Rework 要求。
>
> ### 审查范围（仅测试代码）
>
> **修改文件：**
> - `tests/unit/system/test_crosshair.gd` — T6-T10 改进
> - `tests/unit/ui/test_crosshair_view.gd` — T1-T5 注释改善
>
> **不审查的文件**（已在之前判定 PASS）：
> - `scripts/systems/s_crosshair.gd`
> - `scripts/ui/crosshair.gd`
> - `scripts/systems/s_track_location.gd`
>
> ### 必读文档（按顺序）
> 1. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/03-reviewer-review.md` — 你之前的审查报告和 Rework 要求
> 2. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/04-coder-rework-test-quality.md` — 第 1 次 rework 结果（对比参考）
> 3. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/05-coder-rework-test-quality.md` — **本次待审查的第 2 次 rework 结果**
>
> ### 审查重点（对应你提出的 P0/P1/P2）
>
> **P0 — 是否至少有一个真实方法调用测试？**
> - Coder 称使用 `SubViewport` 使 `entity.get_viewport()` 有效，T6/T7/T9/T10 现在**真正执行**了 `_update_display_aim()` 完整逻辑
> - 请验证：SubViewport 用法是否符合 Godot 项目标准做法？测试是否确实验证了 weapon-null 分支的实际行为？
>
> **P1 — T6/T7/T9/T10 断言是否验证实际状态值？**
> - 从文档看，现在断言的是 `display_aim_position` / `spread_angle_degrees` 等组件字段的**方法调用后实际值**
> - 请确认这不再是在测试中复制生产代码逻辑
>
> **P2 — T1-T3 注释和 TODO 标注是否充分？**
> - 文档显示已添加文件头部的详细限制说明 + 每个函数的 TODO
> - 请确认信息量足够让后续开发者理解为何无法做集成测试
>
> ### 审判标准
> - **pass**: P0/P1/P2 全部满足或合理降级（有明确理由）→ 可进入 CI
> - **rework**: 仍有实质性缺陷 → 列出具体问题
> - 注意：如果结论仍是 rework 但原因仅为微小改进（如注释措辞），可考虑 pass 并在 comment 中建议后续优化
>
> ### 输出要求
> - 审查结论写入 `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/06-reviewer-rework-review.md`
> - 使用中文撰写
> - 必须包含明确的 pass/rework/major-issue 判决
