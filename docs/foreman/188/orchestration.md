# Orchestration — Issue #188

## Issue
**Title:** 修复：箱子会阻挡并消耗子弹
**Labels:** bug, foreman:assign
**Body:**
## 问题

子弹命中箱子（CContainer）后会被直接移除，即使箱子没有 `CHP` 组件（伤害无法生效）。导致玩家射击时，子弹被箱子"吃掉"，无法穿透到后方的敌人。

## 根因分析

### 碰撞管线

1. `SDamage._process_bullet_collision()` 查询所有 `CBullet + CCollision` 实体
2. 通过 `Area2D.get_overlapping_areas()` 找到所有重叠实体
3. `_is_valid_bullet_target()` 过滤目标：
   - 如果目标有 `CCamp`，必须与子弹所属阵营不同
   - **如果目标没有 `CCamp`，直接返回 `true`**（line 163-164）
   - **没有检查目标是否有 `CHP`**
4. 取最近的有效目标，调用 `_take_damage()`
5. **无论伤害是否生效，子弹都被移除**（line 99）

### 箱子实体构成

箱子（`authoring_box.gd`）拥有：`CTransform`, `CSprite`, `CCollision`(CircleShape2D r=16), `CContainer`
- **没有 `CCamp`** → 通过目标验证
- **没有 `CHP`** → `_take_damage()` 直接 return，伤害无效
- **但子弹仍然被移除**

### 项目不使用 collision_layer/mask

`project.godot` 没有配置任何碰撞层，所有 Area2D 都使用默认 layer 1 / mask 1。所有实体之间都会互相检测碰撞。

## 修复建议

在 `scripts/systems/s_damage.gd` 中修改，三选一：

**方案 A（推荐）**：在 `_is_valid_bullet_target()` 中增加 `CHP` 检查
```gdscript
if not target.has_component(CHP):
    return false
```

**方案 B**：让 `_take_damage()` 返回 bool，仅在伤害生效时移除子弹

**方案 C**：跳过拥有 `CContainer` 但没有 `CHP` 的实体

## 影响范围

- 修改文件：`scripts/systems/s_damage.gd`
- 不影响碰撞层/mask 配置（项目未使用）
- 不影响近战攻击（`SMeleeAttack` 有独立的碰撞逻辑）

---

## Decision Log
| # | Action | Summary |
|---|--------|--------|
| 1 | spawn @planner (initial-analysis) | 首次调度，Planner 进行初始分析选择修复方案 |
| 2 | verify | Planner 报告修复已在 commit 6329447 完成，8 个测试全部覆盖，Issue 可关闭 |
| 2 | verify | Planner 报告 Issue #188 描述的 bug 已被修复：`s_damage.gd` 中 `_is_valid_bullet_target()` 增 |
