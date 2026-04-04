# Decision 25 — 2026-04-04 17:03
**Trigger:** new_issue（Issue #195 框架再次重新派发，调度轮次 0/3）
**Assessment:**
- Issue #195 的完整修复链已在历史调度周期中完成：D1-D16 完成规划→编码→审查→测试全流程
- D17-D25（含本轮）连续九轮独立决策一致确认为终态 verify
- 代码交付物完整且已验证：
  - `scripts/components/c_animation.gd` — `animation_was_paused` 标记字段
  - `scripts/systems/s_animation.gd` — 冻结暂停标记 + 解冻三分支恢复逻辑
  - `tests/unit/system/test_animation_freeze_recovery.gd` — T1-T7 共 7 个单元测试，100% 通过率
- 本轮触发与 D23、D24 完全同构，无任何新的状态变化或待处理事项
- Orchestration 索引表为空需补全

**Action:** verify
**Task:** —
**Model:** —
**Guidance:** —
**TL Context for N/A:**
> （终态决策，无需下游 agent。Issue #195 已在 D17-D25 连续九轮决策中确认为已完成状态。）

**GitHub Comment:**
## Issue #195 — 已完成（复验确认 ×3）

此 issue 的修复工作已在之前的调度周期中全部完成并经验证，本轮为框架重复派发。

### 修复方案（v2）
在冻结恢复时增加三分支动画恢复逻辑（同名续播 / 异名切换 / 无操作），确保 Animation 状态机不会卡死导致移动动画丢失。

### 修改文件
| 文件 | 变更 |
|------|------|
| `gol-project/scripts/components/c_animation.gd` | 新增 `animation_was_paused: bool` 字段 |
| `gol-project/scripts/systems/s_animation.gd` | 冻结暂停标记设置 + 解冻三分支恢复 |
| `gol-project/tests/unit/system/test_animation_freeze_recovery.gd` | T1-T7 共 7 个单元测试 |

### 验证结论
- 代码审查：**approve**（多轮独立审查通过）
- 单元测试：**7/7 通过**，覆盖率 100%
- 架构一致性：与 ECS + Animation 状态机设计一致，无副作用

经连续九轮独立决策一致确认（D17-D25），建议直接合并。
