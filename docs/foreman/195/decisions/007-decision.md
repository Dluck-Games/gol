# Decision 7 — 2026-04-04 12:35
**Trigger:** @reviewer 完成 — 审查文档 `03-reviewer-freeze-animation-recovery.md` 结论为 `verified`
**Assessment:** Reviewer 完成了全面审查，结论为通过（verified）。代码实现与计划高度一致：Fix-1/Fix-2 代码位置、逻辑、边界条件均正确，架构约束全部通过，T8/T9/T10 测试覆盖充分。发现两个非阻塞性改进项：
- **Issue-1 (Important)**: Coder 交接文档遗漏 `c_animation.gd` 变更声明（新增 `animation_was_paused` 字段）
- **Issue-2 (Minor)**: T8 用例缺少 sprite.frame 保持断言

两项均不影响正确性，Reviewer 明确表示"不阻碍合入"。但修复成本极低（文档补一行 + 测试加一个断言），在合入前清理可提升交付质量。调度轮次 0/3，充裕。
**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** Reviewer 已 verified 代码正确性，仅需修复两个非阻塞性改进项。工作量很小，专注完成即可。
**TL Context for @coder:**
> ## Issue #195 — 冻结伤害后移动动画丢失 — Rework（非阻塞性改进）
>
> ### 背景
> Reviewer 已给出 `verified` 结论，代码实现正确性无问题。需完成两个轻量改进后即可合入。
>
> ### 必读文档
> 1. **`docs/foreman/195/iterations/03-reviewer-freeze-animation-recovery.md`** — 审查全文，重点关注"发现的问题"章节（Issue-1 和 Issue-2）
> 2. **`docs/foreman/195/iterations/02-coder-fix-freeze-animation-recovery.md`** — 你的上一版交接文档，需要更新
>
> ### 待完成的改进项
>
> **Rework-1 [Important] 补充 c_animation.gd 变更声明**
> - 在交接文档 `02-coder-fix-freeze-animation-recovery.md` 的"完成的工件 / 代码修改"表格中，补充第 4 行：
>   | `scripts/components/c_animation.gd` | 新增 `animation_was_paused: bool = false` 字段（line 12-13） | Bug-1 基础设施：将暂停状态提升为 Component 持久化字段 |
> - 同时在"详细修改"章节增加对应的说明段落
>
> **Rework-2 [Minor] T8 补充 frame 保持断言**
> - 文件：`tests/unit/system/test_animation_freeze_recovery.gd` 的 T8 用例 (`test_unfreeze_during_invincibility_recovers_sprite`)
> - 在冻结前设置一个初始帧号（如 `sprite.frame = 5`），解冻恢复后断言帧号保持不变：`assert_int(sprite.frame).is_equal(5)`
> - 参考 T1/T2 中已有的 frame 断言风格保持一致
>
> ### 约束
> - 仅修改上述两个文件（交接文档 + 测试文件），不要动 `s_animation.gd` / `s_elemental_affliction.gd` / `c_animation.gd` 的代码
> - 工作目录：`/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260404120254._43e08cab`
> - 分支：`foreman/issue-195`
> - 不执行 git add / commit / push / gh pr create（由框架处理）
