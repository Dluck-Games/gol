# Foreman 产出代码架构一致性保障

Date: 2026-03-28
Status: Approved
Scope: gol-tools/foreman/prompts/, gol-tools/foreman/lib/doc-manager.mjs

## 问题

Foreman agent 产出的代码不遵循 gol-project 的设计规范（ECS/GECS、MVVM、GOAP、分层约定、文件组织、测试模式）。PR #187/#188/#189 审核中发现：coder 不追踪调用方、测试空壳占位、reviewer 无法验证架构合规性。

当前 planner 的实现方案不强制引用项目约定，reviewer 的审查范围只覆盖"会不会坏"而不覆盖"对不对"。

## 方案

不引入新角色。在 @planner 和 @reviewer 的 prompt 模板中各加一个段落，形成闭环：planner 定义架构约束，reviewer 对照验证。

## 变更 1：planner-task.md — 新增「架构约束」必填段落

在「实现方案」和「测试契约」之间插入 `### 架构约束` 段落。

要求 planner 必须：

1. **列出本次修改涉及的 AGENTS.md 文件** — 如 `scripts/components/AGENTS.md`、`tests/AGENTS.md`
2. **引用具体的架构模式并说明为什么用它** — 如："新增伤害衰减数据 → 用 GECS Component（纯数据），不在 System 中存状态，因为 components/AGENTS.md 要求 Component = pure data"
3. **标注文件归属层级** — 新文件应放在哪个目录，依据是哪条 AGENTS.md 约定
4. **标注测试模式** — 单元测试用 gdUnit4 GdUnitTestSuite、集成测试用 SceneConfig、E2E 用 AI Debug Bridge，引用 tests/AGENTS.md 对应规则

如果 planner 判断需求不适用任何已有模式（全新领域），必须显式说明"无现有模式可引用"并建议合理的拓展方向。

## 变更 2：reviewer-task.md — 验证清单新增「架构一致性对照」

在现有「验证清单」段落的检查项后追加一组固定检查项，reviewer 必须逐项执行：

- [ ] 新增代码是否遵循 planner 指定的架构模式（Component/System/Service/UI 等）
- [ ] 新增文件是否放在 planner 指定的目录，命名是否符合该层的 AGENTS.md 约定
- [ ] 是否存在平行实现——功能和已有代码重叠但没有复用
- [ ] 测试是否使用 planner 指定的测试模式（gdUnit4 suite 结构、SceneConfig 用法等）
- [ ] 测试是否验证了真实行为（不是空壳 `assert_true(true)`、不是只测 happy path）

发现架构违规时：severity 标为 **Important**（不是 Minor），因为架构偏离的修复成本随时间增长。

## 变更 3：doc-manager.mjs — REQUIRED_SECTIONS 更新

`REQUIRED_SECTIONS.planner` 数组新增 `'## 架构约束'`，插入在 `'## 实现方案'` 之后、`'## 测试契约'` 之前。

## 不变的部分

| 组件 | 原因 |
|------|------|
| TL 调度逻辑 | TL 不需要理解架构，只做调度决策 |
| coder-task.md | Coder 读 planner 文档中的架构约束自行遵循，无需 prompt 重复 |
| tester-task.md | E2E 测试不涉及架构审查 |
| tl-decision.md | TL 转发 reviewer 的架构违规发现即可，不需要自行判断 |
| 文档命名/序号/校验流程 | 不涉及 |

## 信息流

```
planner 读 AGENTS.md
  → 输出「架构约束」段落（模式、目录、测试模式）
    → coder 读 plan（含架构约束）→ 按约束实现
      → reviewer 读 plan 的架构约束 + coder 的实际代码
        → 对照验证（5 项固定检查）
          → 违规 → rework（TL context 引用 reviewer 的具体违规发现）
          → 通过 → 继续流程
```

## 涉及文件

| 文件 | 变更 |
|------|------|
| `prompts/planner-task.md` | 新增「架构约束」必填段落 |
| `prompts/reviewer-task.md` | 验证清单追加架构一致性对照检查项 |
| `lib/doc-manager.mjs` | `REQUIRED_SECTIONS.planner` 新增 `'## 架构约束'` |
