# Decision 5 — 2026-04-03 19:00
**Trigger:** `doc_validation_failed` — 文档 `04-coder-element-bullet-vfx-review-fix.md` 缺少 3 个必填章节：`## 完成的工作`、`## 测试契约覆盖`、`## 决策记录`
**Assessment:** Coder 的 rework 实际代码工作已完成（498 测试全通过，仅修改 2 个测试文件），但交接文档不符合模板规范。对比首次实现文档 `02-coder-element-bullet-vfx.md`，该文档完整包含所有必填章节。rework 文档使用了非标准章节名（`## 修复概述`、`## 测试结果`）替代必填章节，且完全缺少 `## 决策记录`。代码层面无问题，纯文档格式修复，不涉及架构或逻辑变更。调度 coder 修正文档格式。
**Action:** spawn @coder
**Task:** rework
**Model:** kimi-k2.5-ioa
**Guidance:** 仅修改文档 `04-coder-element-bullet-vfx-review-fix.md`，补充缺失的 3 个必填章节。不修改任何代码文件，不修改其他文档。

**TL Context for @coder:**
> ## Issue #226: 元素子弹 VFX — Rework（文档格式修正）
>
> **你的代码修复工作已确认完成**（498 测试全通过），本次 rework 仅修复交接文档格式。
>
> ### 问题
> 文档 `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/04-coder-element-bullet-vfx-review-fix.md` 文档验证失败，缺少 3 个必填章节：
> 1. `## 完成的工作` — 当前文档有 `## 修复概述` 和 `## 逐项修复记录`，但缺少标准章节名
> 2. `## 测试契约覆盖` — 当前文档有 `## 测试结果`，但缺少以表格形式对照 reviewer 提出的修复项的契约覆盖状态
> 3. `## 决策记录` — 完全缺失
>
> ### 参考文档（必读）
> - `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/02-coder-element-bullet-vfx.md` — 首次实现文档，包含正确的章节格式，对照参考
>
> ### 修复要求
> 1. **添加 `## 完成的工作`** 章节：表格列出本次 rework 修改的文件（2 个测试文件），说明修改内容
> 2. **添加 `## 测试契约覆盖`** 章节：表格对照 reviewer 报告中 2 个 Important 问题，标明修复后的覆盖状态（✅ 已覆盖）
> 3. **添加 `## 决策记录`** 章节：记录本次修复中做出的决策（如 skip() 标记空测试、集成测试中直接调用静态方法验证 impact）
> 4. 保留现有的 `## 测试结果` 和 `## 仓库状态` 章节
>
> ### 不做的事情
> - **不要修改任何代码文件**（.gd 文件）
> - **不要修改 AGENTS.md**
> - **不要修改 reviewer 报告**
> - **不要修改首次实现的文档**
> - **不要 git commit**（仅修改文档，不涉及代码变更）
