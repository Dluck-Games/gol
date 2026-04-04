# Coder 迭代文档 - Issue #195 新周期 Rework

## 完成的工作

### 1. `scripts/components/c_animation.gd` - 新增字段

**位置**: 第 12-13 行

**修改内容**:
```gdscript
## 追踪精灵是否被外部原因暂停（冻结/死亡等），用于解冻后恢复播放
var animation_was_paused: bool = false
```

在 `animated_sprite_node` 字段之后新增 `animation_was_paused` 布尔标记，用于追踪精灵是否被外部原因（冻结、死亡等）暂停，以便在解冻后正确恢复播放。

### 2. `scripts/systems/s_animation.gd` - 暂停标记设置

**位置**: 第 74-76 行

**修改内容**:
```gdscript
if movement.forbidden_move:
    sprite.pause()
    anim_comp.animation_was_paused = true   # 标记已暂停
    return
```

在冻结暂停时设置 `animation_was_paused = true`，记录暂停状态供后续恢复逻辑使用。

### 3. `scripts/systems/s_animation.gd` - 三分支恢复逻辑

**位置**: 第 97-106 行

**修改内容**:
```gdscript
if anim_comp.frames and anim_comp.frames.has_animation(next_animation):
    var needs_play: bool = sprite.animation != next_animation
    # 解冻恢复：动画名相同但之前被暂停过 → 仅取消暂停，不重置帧
    if anim_comp.animation_was_paused and not needs_play:
        sprite.paused = false
        anim_comp.animation_was_paused = false
    elif needs_play:
        sprite.play(next_animation)
        anim_comp.animation_was_paused = false
```

实现 v2 方案的核心改进：
- **分支 1**: 动画名相同且之前被暂停过 → 使用 `sprite.paused = false` 无缝续播，不重置帧位置
- **分支 2**: 动画名不同 → 使用 `sprite.play()` 切换动画（原有行为）
- **分支 3**: 其他情况 → 不执行操作

### 4. `tests/unit/systems/test_animation_freeze_recovery.gd` - 单元测试

**位置**: 新建文件

包含 T1-T7 共 7 个测试用例，覆盖冻结解冻的各种场景。

---

## 测试契约覆盖

| 用例编号 | 名称 | 覆盖状态 |
|---------|------|---------|
| T1 | `test_freeze_unfreeze_walk_keeps_frame` | ✅ 已覆盖 |
| T2 | `test_freeze_unfreeze_idle_keeps_frame` | ✅ 已覆盖 |
| T3 | `test_freeze_then_state_change_switches_anim` | ✅ 已覆盖 |
| T4 | `test_no_freeze_normal_behavior_unchanged` | ✅ 已覆盖 |
| T5 | `test_was_paused_cleared_after_restore` | ✅ 已覆盖 |
| T6 | `test_multiple_freeze_cycles` | ✅ 已覆盖 |
| T7 | `test_unfreeze_with_missing_animation` | ✅ 已覆盖 |

---

## 决策记录

本实现遵循方案文档 `docs/superpowers/plans/2026-04-04-issue195-freeze-animation-loss-v2-redesign.md` 的 v2 设计：

1. **采用 v2 恢复策略**: 区分动画名是否变化，同名时使用 `paused = false` 续播（无视觉跳跃），异名时使用 `play()` 切换（原有行为）

2. **三分支逻辑结构**: 显式分离三种处理路径，逻辑意图更清晰：
   - `was_paused && !needs_play`: 解冻续播
   - `needs_play`: 正常切换
   - 其他: 无操作

3. **标记清理**: 在两种恢复路径中均清除 `animation_was_paused` 标记，避免状态残留

4. **has_animation 守卫**: 外层检查 `has_animation()`，确保不会对不存在的动画名调用操作（T7 场景）

---

## 仓库状态

- **分支**: `foreman/issue-195`
- **修改文件列表**:
  - `scripts/components/c_animation.gd` - 新增 `animation_was_paused` 字段
  - `scripts/systems/s_animation.gd` - 暂停标记 + 三分支恢复逻辑
  - `tests/unit/systems/test_animation_freeze_recovery.gd` - T1-T7 测试用例
- **测试结果**: 测试脚本已执行完成（通过 coder-run-tests.sh）
- **Git 状态**: 待框架处理提交

---

## 未完成事项

无。所有代码文件已按方案实现，测试用例已覆盖 T1-T7。
