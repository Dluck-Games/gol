# Decision 8 — 2026-04-04 12:54
**Trigger:** `doc_validation_failed` — 框架校验 Reviewer 交接文档 `03-reviewer-freeze-animation-recovery.md` 未通过格式验证，缺少必需章节（完成的工作 / 测试契约覆盖 / 决策记录 / 仓库状态 / 未完成事项）
**Assessment:**
Review 文档的**实质内容质量很高**（已全文审阅）：
- 审查结论为 `verified`，代码与计划高度一致
- 8 步验证清单全部通过（文件一致性、代码正确性、边界条件、调用链、测试质量、架构一致性）
- 发现 2 个非阻塞性改进项：Issue-1（Important, c_animation.gd 变更声明遗漏）、Issue-2（Minor, T8 缺 frame 断言）

框架校验失败原因：Review 文档使用自定义章节标题（"审查范围"/"发现的问题"/"结论"等），未匹配框架期望的标准交接文档模板标题。属于**格式问题非内容问题**。

Decision 7 已基于 Review 内容派发 @coder (rework) 处理上述 2 个改进项，但 iterations/ 目录中无 `04-coder-*` 文档，说明该次 coder 调度**未能成功执行或产出被框架拦截**（可能因 reviewer 文档校验阻塞了流水线推进）。

**调度轮次 1/3**，充裕。无需回退 planner，直接推动 coder 完成剩余改进工作。
**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** Reviewer 已 verified 代码正确性，仅剩 2 个轻量改进项未完成。专注完成即可。
**TL Context for @coder:**
> ## Issue #195 — 冻结伤害后移动动画丢失 — Rework（非阻塞性改进）
>
> ### 背景
> Reviewer 已给出 `verified` 结论，代码实现正确性无问题（Fix-1/Fix-2 均正确）。需完成 2 个改进项后即可合入。这是 Decision 7 派发的 rework 任务的实际执行轮次。
>
> ### 必读文档
> 1. **`docs/foreman/195/iterations/03-reviewer-freeze-animation-recovery.md`** — Reviewer 审查全文，重点关注"发现的问题"章节（Issue-1 和 Issue-2）
> 2. **`docs/foreman/195/iterations/02-coder-fix-freeze-animation-recovery.md`** — 你的上一版交接文档，需要更新补充遗漏内容
> 3. **`docs/foreman/195/decisions/007-decision.md`** — 上轮决策，了解完整指令上下文
>
> ### 待完成的改进项
>
> **Rework-1 [Important] 补充 c_animation.gd 变更声明**
> - 在交接文档 `02-coder-fix-freeze-animation-recovery.md` 的"完成的工件 / 代码修改"表格中，补充第 4 行：
>   | `scripts/components/c_animation.gd` | 新增 `animation_was_paused: bool = false` 字段（line 12-13） | Bug-1 基础设施：将暂停状态提升为 Component 持久化字段 |
> - 同时在"详细修改"章节增加对应的说明段落（描述此字段的用途和读写位置）
>
> **Rework-2 [Minor] T8 补充 frame 保持断言**
> - 文件：`tests/unit/system/test_animation_freeze_recovery.gd` 的 T8 用例 (`test_unfreeze_during_invincibility_recovers_sprite`)
> - 在冻结前设置一个初始帧号（如 `sprite.frame = 5`），解冻恢复后断言帧号保持不变：`assert_int(sprite.frame).is_equal(5)`
> - 参考 T1/T2 中已有的 frame 断言风格保持一致
>
> ### 输出要求
> 必须产出交接文档到 `docs/foreman/195/iterations/04-coder-rework-freeze-animation.md`，包含以下必需章节：
> - ## 完成的工作（列出本次修改的文件和变更说明）
> - ## 测试契约覆盖（确认 T1-T10 状态）
> - ## 决策记录（说明做了什么决定及理由）
> - ## 仓库状态（分支名、工作目录、修改文件列表）
> - ## 未完成事项（如有）
>
> ### 约束
> - 仅修改两个文件：交接文档（更新）+ 测试文件（补断言）。不要动 `s_animation.gd` / `s_elemental_affliction.gd` / `c_animation.gd` 的代码逻辑
> - 工作目录：`/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260404120254._43e08cab`
> - 分支：`foreman/issue-195`
> - 不执行 git add / commit / push / gh pr create（由框架处理）
