# Decision 2 — 2026-04-05 12:47
**Trigger:** @planner 完成 initial-analysis，产出计划文档和交接文档
**Assessment:** 计划质量优秀。根因定位精确（`s_crosshair.gd:45` 无条件赋值 + `crosshair.gd:89` query 缺 `CWeapon`），方案为路径 A+C 双重防御，含具体代码片段、行号引用、测试契约（T1-T8）、风险分析。STrackLocation 同步修复和 CWeapon 重命名已正确分离为可选/独立 task。可以派发 @coder 实施。
**Action:** spawn @coder
**Task:** implement
**Model:** kimi-k2.5-ioa
**Guidance:** 按照 planner 的 Step 1→2→3→4 顺序实施修复。先改 System 层再改 View 层，最后写测试。
**TL Context for @coder:**
> ## 任务：实施 #239 准心 Bug 修复
>
> ### 核心改动（3 个文件 + 2 个新测试文件）
>
> **Step 1 — System 层修复** (`scripts/systems/s_crosshair.gd`)
> - 找到 `_update_display_aim()` 方法（约 L44-88）
> - 将 `aim.display_aim_position = aim.aim_position` 从 weapon null check **之前**移到**之后**
> - 在 `weapon == null` 分支中增加 `aim.display_aim_position = Vector2(-99999, -99999)`
>
> **Step 2 — View 绑定层修复** (`scripts/ui/crosshair.gd`)
> - `_try_bind_entity()` 中将 `with_all([CPlayer, CAim])` 改为 `with_all([CPlayer, CAim, CWeapon])`
> - `_process()` 中增加武器丢失检测：若 `_bound_entity` 存在但无 `CWeapon`，则 unbind 并置空
> - `_on_draw()` 开头加 `if _bound_entity == null: return` 守卫
>
> **Step 3 — 同步修复 STrackLocation** (`scripts/systems/s_track_location.gd`)
> - 找到与 SCrosshair 相同的 `_update_display_aim` bug pattern，应用相同修复
>
> **Step 4 — 新建 Unit Tests**
> - `tests/unit/ui/test_crosshair_view.gd` — T1-T5（绑定成功/失败/武器丢失/解绑状态绘制/正常绘制）
> - `tests/unit/system/test_crosshair.gd` — T6-T8（weapon-null 时无效坐标/有 weapon 时有效坐标/query 条件验证）
> - 测试遵循 gdUnit4 规范（`extends GdUnitTestSuite`），参考项目既有测试风格
>
> ### 必读文档
> 1. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/plans/01-planner-crosshair-no-weapon-fix.md` — 完整计划和代码示例
> 2. `/Users/dluckdu/Documents/Github/gol/docs/foreman/239/iterations/01-planner-handoff-crosshair-fix.md` — 速查表和关键代码片段索引
>
> ### 约束
> - **不执行** git add / commit / push / gh pr create — 这些由框架处理
> - 不修改 `c_weapon.gd`、`c_aim.gd`、`crosshair_view_model.gd`（纯数据层不改）
> - 不做 CWeapon → CShooterWeapon 重命名（独立 optional task）
> - 遵循 AGENTS.md 命名规范和代码风格（tabs 缩进、静态类型、class_name）
> - 改完后确认 `s_dialogue.gd` 中对 CrosshairView.visible 的控制逻辑不受影响（只读验证即可）
