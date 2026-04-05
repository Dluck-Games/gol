# Decision 7 — 2026-04-05 14:53
**Trigger:** @reviewer 完成 rework-review（第 2 轮），产出文档 `06-reviewer-rework-review.md`，结论为 **PASS**
**Assessment:** Reviewer 对第 2 次 test-quality rework 给出明确 PASS 判定：

- **P0 真实方法调用** ✅：T6/T7/T9/T10 通过 SubViewport 环境调用真实 `_update_display_aim()`，覆盖 weapon-null 核心路径，回归防护有效
- **P1 断言质量** ✅：不再复制生产代码逻辑，断言验证方法执行后组件实际状态值
- **P2 注释文档** ✅：文件头部和函数级注释充分说明纯单元测试限制及 TODO 指向

**完整状态回顾：**
| 阶段 | 结论 | 决策编号 |
|------|------|---------|
| Planner 分析 | 方案通过 | 001 |
| Coder 实现 | 生产代码完成 | 002 |
| Reviewer 全量审查 | 生产代码 PASS / 测试代码 REWORK | 003→004 |
| Coder Rework（第 1 次） | 测试改进未达要求 | 005 |
| Coder Rework（第 2 次） | P0/P1/P2 全部达成 | 006 |
| Reviewer Rework 审查 | **PASS** | 本轮 |

生产代码（`s_crosshair.gd`、`crosshair.gd`、`s_track_location.gd`）在 Decision 5 前已获 PASS。测试代码经两轮迭代现已满足审查要求。506 测试全部通过，无新增回归。调度轮次 2/3，未超限。

**Action:** verify
**Task:** —
**Model:** glm-5v-turbo-ioa
**Guidance:** 全部审查通过，任务可关闭。

**GitHub Comment:**
> ## Issue #239 修复完成
>
> ### Bug 概述
> 玩家无远程武器时准心仍显示的问题已修复。
>
> ### 修改文件（3 个）
> - `scripts/systems/s_crosshair.gd` — `_update_display_aim()` 增加 weapon-null guard，无武器时设置无效坐标并重置 spread
> - `scripts/ui/crosshair.gd` — `_try_bind_entity()` query 条件增加 `CWeapon`
> - `scripts/systems/s_track_location.gd` — 同步增加 `CWeapon` 条件以保持一致性
>
> ### 测试覆盖（10 个新测试）
> - `tests/unit/system/test_crosshair.gd`（T6-T10）— 使用 SubViewport 真实方法调用测试核心修复路径
> - `tests/unit/ui/test_crosshair_view.gd`（T1-T5）— 行为契约 + 详细限制说明
> - 全部 506 测试通过，无回归风险
>
> ### 后续建议（非阻塞）
> - 补充 SceneConfig 集成测试以覆盖完整 ECS query 和渲染管线路径（已在测试 TODO 中标注）
