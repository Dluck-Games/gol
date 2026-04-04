# 计划：冻结伤害后移动动画丢失修复

> **Issue:** #195 — 角色/怪物受到冰冻/冻结伤害效果后，移动时偶现动画不播放（实体"滑行"）
> **日期:** 2026-04-04
> **状态:** 规划完成，待实现

---

## 1. 需求分析

### 问题现象
角色或怪物受到冻结伤害后，解冻期间或解冻后偶现动画不播放——实体在视觉上"滑行"（位置移动但精灵帧不动）。

### 根因分析结论

经过完整代码审查，定位到 **3 个 Bug**（按严重程度排序）：

#### Bug-1 [CRITICAL] 无敌帧阻塞解冻恢复路径

**文件:** `scripts/systems/s_animation.gd:68-72`

`_update_animation()` 中，无敌帧检查（`invincible_time > 0`）位于冻结恢复逻辑 **之前**，且使用 `return` 直接退出。当以下时序发生时：

```
Frame N:   实体处于冻结状态 (forbidden_move=true) → sprite.pause(), animation_was_paused=true
Frame N+k: 元素 DoT 伤害触发 → SDamage._take_damage() 设置 invincible_time=0.3
           同帧 SElementalAffliction: freeze_timer >= 2.0s → forbidden_move=false（冻结结束）
Frame N+k: SAnimation._update_animation() 执行：
           Line 71: invincible_time > 0? YES → return ← *** 解冻恢复代码永远不会执行 ***
           → sprite 保持 paused 状态，animation_was_paused 保持 true
Frame N+k+m: invincibility 耗尽后，理论上可恢复
           但如果此期间再次受伤 → 又被阻塞
           或实体已开始移动但 sprite 仍 paused → "滑行"
```

**触发条件（同时满足）：**
1. 实体处于冻结状态（`forbidden_move == true`, `animation_was_paused == true`）
2. 冻结计时器耗尽与无敌帧激活在同一时间窗口内
3. 常见场景：火/电元素 DoT 在冻结期间造成持续伤害（每 0.5s tick），每次 tick 都设置 0.3s 无敌时间

#### Bug-2 [MODERATE] 解冻时 max_speed 未恢复到正常值

**文件:** `scripts/systems/s_elemental_affliction.gd:186-195`

冻结结束时（`freeze_timer >= FREEZE_MAX_DURATION`）：
```gdscript
movement.forbidden_move = false
affliction.status_applied_movement_lock = false
# ❌ 缺失: movement.max_speed = base_speed  （未恢复）
affliction.freeze_cooldown = FREEZE_COOLDOWN
return  # ← return 后不会执行 line 207 的比例减速计算
```

结果：解冻后 `max_speed` 保持在 35%（`1 - MAX_COLD_SLOW`）。后续帧虽然会通过 line 208 重新计算，但如果 `cold_intensity` 仍 > 0（COLD entry 尚未衰减完），速度仍然很低。这导致：
- `SMove` 加速度极慢 → `velocity` 长期接近零
- 零速度 → `SAnimation` 选择 `"idle"` 而非 `"walk"` → 玩家按住方向键但角色显示 idle 动画

#### Bug-3 [MINOR] velocity 未在解冻时重置/保留

**文件:** `scripts/systems/s_elemental_affliction.gd:199`

冻结启动时 `movement.velocity = Vector2.ZERO` 强制归零，但解冻时不做任何处理。依赖 SMove 从零重新加速。配合 Bug-2 的低速状态，前几帧 velocity 几乎为零。

---

## 2. 影响面分析

### 涉及文件清单

| 文件 | 变更类型 | 影响范围 |
|------|----------|----------|
| `scripts/systems/s_animation.gd` | **修改** | Bug-1 修复：无敌帧中允许解冻暂停恢复 |
| `scripts/systems/s_elemental_affliction.gd` | **修改** | Bug-2 修复：解冻时恢复 base max_speed |
| `tests/unit/system/test_animation_freeze_recovery.gd` | **修改** | 补充 Bug-1 场景测试用例 |

### 不需要修改的文件（仅引用）

| 文件 | 原因 |
|------|------|
| `scripts/components/c_animation.gd` | 数据组件，无需改结构 |
| `scripts/components/c_movement.gd` | 数据组件，flag 已有，仅被读写 |
| `scripts/components/c_elemental_affliction.gd` | 数据组件，字段足够 |
| `scripts/components/c_hp.gd` | 仅 `invincible_time` 数据持有者 |
| `scripts/systems/s_damage.gd` | 设置 `invincible_time` 的入口，不修改 |
| `scripts/systems/s_hp.gd` | 递减 `invincible_time` 的系统，不修改 |
| `scripts/systems/s_move.gd` | 读 `forbidden_move`，不修改 |
| `scripts/utils/elemental_utils.gd` | 元素效果工具函数，不修改 |

### 数据流影响

```
SElementalAffliction (gameplay group)
  ↓ CMovement.forbidden_move / max_speed / velocity
SAnimation (render group)
  ↓ AnimatedSprite2D.paused / play()
SDamage (gameplay group)
  ↓ CHP.invincible_time
SAnimation (render group)
  ↓ early return blocks unfreeze recovery  ← BUG-1 所在
```

---

## 3. 实现方案

### Fix-1: 无敌帧期间仍执行解冻暂停恢复

**文件:** `scripts/systems/s_animation.gd`
**位置:** `_update_animation()` 方法，line 68-77
**当前代码:**
```gdscript
var hp: CHP = entity.get_component(CHP)
if hp and hp.invincible_time > 0:
    return  # <-- 阻塞所有动画更新

if movement.forbidden_move:
    sprite.pause()
    anim_comp.animation_was_paused = true
    return
```
**修改为:**
```gdscript
var hp: CHP = entity.get_component(CHP)

# 解冻恢复优先级最高：即使处于无敌帧，也要取消暂停
if anim_comp.animation_was_paused and not movement.forbidden_move and sprite:
    sprite.paused = false
    anim_comp.animation_was_paused = false

if hp and hp.invincible_time > 0:
    return  # 无敌帧期间阻止 walk/idle 切换和翻转更新

if movement.forbidden_move:
    sprite.pause()
    anim_comp.animation_was_paused = true
    return
```

**设计理由:**
- 将 `animation_was_paused` 的恢复提升到无敌帧检查 **之前**
- 条件: `was_paused==true` AND `forbidden_move==false`（已解冻）AND sprite 有效
- 仅执行 `paused = false`，不切换动画名称、不设置 flip_h —— 最小侵入
- 无敌帧的 `return` 仍在之后，继续阻断正常的 walk/idle 判断和翻转向量更新

### Fix-2: 解冻时恢复 max_speed 到 base_speed

**文件:** `scripts/systems/s_elemental_affliction.gd`
**位置:** `_apply_movement_modifiers()` 方法，line 190-194
**当前代码:**
```gdscript
if affliction.freeze_timer >= FREEZE_MAX_DURATION:
    movement.forbidden_move = false
    affliction.status_applied_movement_lock = false
    affliction.freeze_timer = 0.0
    affliction.freeze_cooldown = FREEZE_COOLDOWN
```
**修改为:**
```gdscript
if affliction.freeze_timer >= FREEZE_MAX_DURATION:
    movement.forbidden_move = false
    affliction.status_applied_movement_lock = false
    movement.max_speed = base_speed  # 恢复基础速度（剩余 cold 效果由下方比例计算处理）
    affliction.freeze_timer = 0.0
    affliction.freeze_cooldown = FREEZE_COOLDOWN
```

**注意:** 此处加一行 `movement.max_speed = base_speed` 后，由于后面紧跟 `return`，不会执行 line 208 的比例减速计算。这意味着解冻瞬间速度完全恢复正常，下一帧如果 COLD entry 仍未过期，会走 line 206-208 的正常比例减速路径。这是正确行为——解冻不应该残留冻结时的极端降速。

---

## 4. 架构约束

### 涉及的 AGENTS.md 文件
- `gol-project/AGENTS.md` — 总览：ECS + MVVM + System Group 执行顺序（gameplay → render）
- `gol-project/scripts/systems/AGENTS.md` — 系统命名和分组规则
- `gol-project/tests/AGENTS.md` — 测试模式（unit test 使用 GdUnit4）

### 引用的架构模式
- **数据流单向:** `System → Component → ViewModel → View`
- **系统组执行顺序:** gameplay (含 SElementalAffliction, SDamage, SHP, SMove) → render (SAnimation)
- **组件纯数据原则:** 不在 Component 中添加逻辑
- **System 自动发现:** 不手动实例化 System

### 文件归属层级
- `s_animation.gd` → `scripts/systems/` — render 组动画系统
- `s_elemental_affliction.gd` → `scripts/systems/` — gameplay 组元素状态系统
- `test_animation_freeze_recovery.gd` → `tests/unit/system/` — 单元测试

### 测试模式
- 单元测试框架: gdUnit4 (`extends GdUnitTestSuite`)
- 测试风格: 手动构建 Entity + Component + System，调用 `system.process()` 断言组件状态
- Mock 工具: `auto_free()` 自动清理, `PlaceholderTexture2D` 占位纹理
- 约束: 不加载场景，不依赖 ServiceContext

---

## 5. 测试契约

### 现有测试覆盖情况（`test_animation_freeze_recovery.gd`）

| 用例 | 场景 | 覆盖的 Bug |
|------|------|-----------|
| T1 | walk→freeze→unfreeze（保持 walk） | 基本流程 |
| T2 | idle→freeze→unfreeze（保持 idle） | 基本流程 |
| T3 | walk→freeze→unfreeze（变为 idle） | 动画切换路径 |
| T4 | 无冻结的正常行为 | 回归保护 |
| T5 | was_paused 标记清理 | 标记生命周期 |
| T6 | 多次冻结循环 x3 | 重复性 |
| T7 | 缺失动画名边界 case | 异常安全性 |

**缺失覆盖（关键空白）：**

| 缺失用例 | 对应 Bug | 描述 |
|----------|---------|------|
| **T8** | Bug-1 | freeze + invincible_time > 0 同时存在时，解冻后 sprite 应恢复播放 |
| **T9** | Bug-1 | freeze 结束于 invincibility 期间，invincibility 结束后动画正常 |
| **T10** | Bug-2 | 解冻后 `CMovement.max_speed` 应等于 `base_max_speed` |
| **T11** | Bug-1+Bug-2 联合 | 完整场景：冻结中受 DoT 伤害 → 冻结结束于无敌帧内 → 无敌帧结束后全部恢复正常 |

### 新增测试用例规范

**T8 — 无敌帧中的解冻恢复:**
```
前置: entity 有 CAnimation(walk), CMovement(forbidden_move=true), CHP(invincible_time=0.3)
操作: forbidden_move = false; process()
断言: sprite.paused == false, animation_was_paused == false
```

**T9 — 无敌帧结束后动画正常:**
```
前置: 同 T8，且 sprite 已恢复
操作: process()（此时 invincible_time 已自然递减至 0）
断言: 根据 velocity 正确选择 walk 或 idle
```

**T10 — 解冻后 max_speed 恢复:**
```
前置: entity 有 CElementalAffliction(status_applied_movement_lock=true), CMovement(max_speed=35%*base)
操作: 模拟 freeze_timer >= 2.0; process()
断言: CMovement.max_speed == base_max_speed
```

---

## 6. 风险点

| 风险 | 等级 | 缓解措施 |
|------|------|----------|
| Fix-1 改变无敌帧期间的动画行为 | 低 | 仅添加 unpause 操作，不改变动画选择逻辑；无敌帧的 return 仍在之后，walk/idle 切换依然被阻断 |
| Fix-1 与死亡动画冲突 | 极低 | 死亡检查（Line 65-66）在无敌帧检查之前，CDead 存在时会先 return；且死亡时移除 CElementalAffliction 组件 |
| Fix-2 导致解冻瞬间速度突变 | 可接受 | 解冻本身就是状态转换点；base_speed 是正常速度，不是 buffed 速度 |
| 系统组内执行顺序不确定 | 已知限制 | gameplay 组内的系统执行顺序取决于 discovery order；Fix-1 不依赖同帧内的顺序（render group 在 gameplay 之后执行） |
| 多次连续 DoT 伤害导致 invincible_time 反复重置 | 已被 Fix-1 覆盖 | 只要 `forbidden_move == false`，每次进入 _update_animation 都会先执行 unpause recovery |

---

## 7. 建议的实现步骤

### Step 1: 修复 Bug-1 — s_animation.gd
1. 打开 `scripts/systems/s_animation.gd`
2. 定位 `_update_animation()` 方法（line 55）
3. 在 line 68（`var hp: CHP = ...`）之前插入解冻恢复代码块
4. 调整缩进确保代码块位置正确（必须在无敌帧 return 之前、forbidden_move 检查之前）
5. 验证：不影响现有 T1-T7 测试

### Step 2: 修复 Bug-2 — s_elemental_affliction.gd
1. 打开 `scripts/systems/s_elemental_affliction.gd`
2. 定位 `_apply_movement_modifiers()` 方法（line 171）
3. 在 line 191-194 的 if 块内添加 `movement.max_speed = base_speed`
4. 验证：不影响现有行为

### Step 3: 补充单元测试 — test_animation_freeze_recovery.gd
1. 打开 `tests/unit/system/test_animation_freeze_recovery.gd`
2. 新增 T8: `test_unfreeze_during_invincibility_recovers_sprite()` — 模拟冻结中受伤害、冻结于无敌帧内结束的场景
3. 新增 T9: `test_post_invincibility_anim_resumes()` — 无敌帧结束后动画恢复正常
4. 新增 T10: `test_unfreeze_restores_max_speed()` — 验证解冻时 max_speed 恢复
5. 运行全量测试确认无回归

### Step 4: 运行验证
1. 运行 `tests/unit/system/` 下所有动画相关测试
2. 运行完整的 Phase 1 测试套件确认无回归
