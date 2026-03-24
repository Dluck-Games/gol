# 组合代价系统设计 (Composition Cost)

> **Issue:** #108 — 实现"组合代价"数值系统
> **Date:** 2026-03-24

## 概述

当玩家在 ECS 实体上叠加过多组件时，游戏机制给予负面惩罚，创造有意义的组合决策。代价分为两类：

- **硬机制**：系统级惩罚，独立于组件设计，专门为组合代价而设
- **软代价**：组件间功能冲突，源于组件自身属性的互斥性

## 架构方案：微系统网状 + 共享配置

每条代价规则是一个独立的小系统，只查询 2-3 个组件，符合 ECS 网状耦合模式。所有数值常量集中在共享配置中统一调参。

### 核心原则

- **网状耦合**：每个代价系统只耦合 2-3 个组件，无"全知"中心系统
- **base + effective 双字段**：可修改属性存 `base_xxx`（永不被修改）+ `xxx`（每帧从 base 重算）。每个代价系统负责从 base 读取、计算、写入 effective 值；若同一属性有多个代价源，后续系统从前一系统写入的 effective 值继续叠加（乘法链式）
- **乘法叠加**：多重惩罚独立相乘，自然不会叠到极端值
- **代价系统先于游戏系统执行**：确保 effective 值在消费前已更新。每帧第一阶段开始前，各组件的 effective 值从 base 值重置（由各代价系统的首次写入隐式完成：第一个写入者从 base 读取）

## 硬机制（4 项）

### 1. 组件上限

玩家实体最多携带 N 个 losable 组件。达到上限时 `SPickup` 拒绝拾取新的 losable 组件。

注意：组件上限仅阻止"新增"路径。`SPickup` 的 `required_component` 交换路径（献祭一个组件换取另一个）不受上限限制——交换后组件总数不变。

- 影响系统：`SPickup`
- 配置：`COMPONENT_CAP`

### 2. 负重 → 移速惩罚

`SWeightPenalty` 每帧查询 `[CMovement]` 的实体，计数 losable 组件数量，按公式降低移速。

```
effective_speed = base_max_speed × (1 - component_count × WEIGHT_SPEED_PENALTY_PER_COMPONENT)
```

设下限避免完全走不动（不低于 base 的某个百分比）。

- 查询：losable 组件计数 + `CMovement`
- 写入：`CMovement.max_speed`
- 配置：`WEIGHT_SPEED_PENALTY_PER_COMPONENT`

### 3. 存在感 → 仇恨吸引

`SPresencePenalty` 扫描玩家 losable 组件数量，影响：

- 敌人 `CPerception.vision_range` 增大（使用 base + effective 双字段：`base_vision_range` + `vision_range`）
- `CSpawner` 的 enrage 触发条件降低

实现方式：`SPresencePenalty` 查询所有带 `CPerception` 的敌方实体，根据玩家组件数量对每个敌人的 `vision_range` 施加乘法加成。每帧从 `base_vision_range` 重算。

- 查询：玩家 losable 组件计数 + 所有敌人 `CPerception` / `CSpawner`
- 写入：敌人 `CPerception.vision_range` / `CSpawner` 参数

### 4. 致命掉落加剧

修改 `SDamage._on_no_hp`：losable 组件超过阈值 T 时，每超 1 个额外掉 1 个。

```
drop_count = 1 + max(0, component_count - LETHAL_DROP_THRESHOLD)
```

- 影响系统：`SDamage._on_no_hp`
- 配置：`LETHAL_DROP_THRESHOLD`

## 软代价：元素冲突（3 项）

玩家只持有一把武器，元素冲突是二元检查。

### 火元素 → 阻碍治疗速度

`SFireHealConflict` 查询同时拥有 `[CElementalAttack(FIRE), CHealer]` 的实体。

```
effective_heal = base_heal_pro_sec × (1 - FIRE_HEAL_REDUCTION)
```

- 查询：`CElementalAttack` + `CHealer`
- 写入：`CHealer.heal_pro_sec`
- 配置：`FIRE_HEAL_REDUCTION`

### 冰元素 → 阻碍攻击速度

`SColdRateConflict` 查询 `[CElementalAttack(COLD), CWeapon]`（及 `CMelee`）。

```
effective_interval = base_interval × COLD_RATE_MULTIPLIER
```

- 查询：`CElementalAttack` + `CWeapon` / `CMelee`
- 写入：`CWeapon.interval` / `CMelee.attack_interval`
- 配置：`COLD_RATE_MULTIPLIER`

### 电元素 → 弹道散布

`SElectricSpreadConflict` 查询 `[CElementalAttack(ELECTRIC), CWeapon]`。

```
effective_spread = min(base_spread_degrees + ELECTRIC_SPREAD_DEGREES, MAX_SPREAD_DEGREES)
```

`SFireBullet` 发射时始终读取 `CWeapon.spread_degrees` 应用随机角度偏移：

```
spread_angle = randf_range(-spread_degrees, spread_degrees)
bullet_direction = aim_direction.rotated(deg_to_rad(spread_angle))
```

- 查询：`CElementalAttack` + `CWeapon`
- 写入：`CWeapon.spread_degrees`
- 前置改动：`CWeapon` 新增 `spread_degrees` / `base_spread_degrees` 原生属性
- 配置：`ELECTRIC_SPREAD_DEGREES`, `MAX_SPREAD_DEGREES`

## CAreaEffect 范围化重设计

### 核心变化

CAreaEffect 从"独立效果组件"变为"修饰器组件"——不再自带 `effect_type` / `amount`，而是改变同实体上其他组件的作用方式。

现有的 `SAreaEffect` 和 `SAreaEffectRender` 将被移除，由新的 `SAreaEffectModifier` 和对应的渲染逻辑替代。

### CAreaEffect 新定义

```
CAreaEffect:
  radius: float = 540.0
  power_ratio: float = 0.6
  affects_self: bool = false
  affects_allies: bool
  affects_enemies: bool
```

保留 `affects_self` 字段以支持自身效果（如自我治疗场景）。

### 新增组件：CPoison

```
CPoison:
  damage_per_sec: float = 3.0
  duration: float = 5.0
```

单体模式：攻击命中时对目标施加持续毒伤害（非元素系统，不参与元素相克）。

CPoison 属于 losable 组件（加入 `Config.LOSABLE_COMPONENTS`），可在致命伤害时掉落。

### 组合规则

| 被修饰组件 | 单体行为 | + CAreaEffect 后 | 处理系统 |
|-----------|---------|------------------|---------|
| CMelee | 对碰撞目标造成伤害 | 范围内所有敌人受伤，伤害 ×power_ratio | `SAreaEffectModifier` |
| CHealer | 治疗自身/单体 | 范围内所有同阵营实体受疗，治疗量 ×power_ratio | `SAreaEffectModifier` |
| CPoison | 受击时施加中毒 DoT | 范围内自动对敌人施加中毒 DoT，伤害 ×power_ratio | `SAreaEffectModifier` |

### 现有数据迁移

- `enemy_poison.tres` → `CPoison + CAreaEffect`（毒雾僵尸，范围毒伤害）
- `materia_damage.tres` → `CMelee + CAreaEffect`（伤害魔晶，范围物理伤害）
- `materia_heal.tres` → `CHealer + CAreaEffect`（治疗魔晶，范围治疗）

## 系统执行顺序

```
第一阶段：代价计算（新系统，先执行）
  SWeightPenalty            → 写 CMovement.max_speed
  SPresencePenalty          → 写敌人感知参数
  SFireHealConflict         → 写 CHealer.heal_pro_sec
  SColdRateConflict         → 写 CWeapon.interval / CMelee.attack_interval
  SElectricSpreadConflict   → 写 CWeapon.spread_degrees

第二阶段：现有游戏系统（读取 effective 值）
  SPerception               → 读 CPerception.vision_range（需在 SPresencePenalty 之后）
  SMove                     → 读 CMovement.max_speed
  SFireBullet               → 读 CWeapon.interval, spread_degrees
  SMeleeAttack              → 读 CMelee.attack_interval
  SHealer                   → 读 CHealer.heal_pro_sec
  SAreaEffectModifier       → 读 CAreaEffect + 被修饰组件（替代旧 SAreaEffect）
  SDamage                   → 掉落加剧逻辑
  SPickup                   → 组件上限检查
```

## 组件改动总览

| 组件 | 改动 |
|------|------|
| `CMovement` | 新增 `base_max_speed`，`max_speed` 变为 effective 值 |
| `CWeapon` | 新增 `base_interval`、`spread_degrees` / `base_spread_degrees` |
| `CMelee` | 新增 `base_attack_interval` |
| `CHealer` | 新增 `base_heal_pro_sec` |
| `CPerception` | 新增 `base_vision_range`，`vision_range` 变为 effective 值 |
| `CAreaEffect` | 移除 `effect_type` / `amount`，保留 `affects_self`，变为修饰器 |
| `CPoison`（新） | `damage_per_sec`, `duration`（losable 组件） |

## 现有系统改动

| 系统 | 改动 |
|------|------|
| `SPickup` | 新增组件上限检查：在 `_open_box` 的新增组件路径中，若实体 losable 组件数 ≥ `COMPONENT_CAP` 则拒绝拾取。`required_component` 交换路径不受影响 |
| `SDamage` | 修改 `_on_no_hp`：掉落数量从固定 1 改为 `1 + max(0, count - LETHAL_DROP_THRESHOLD)` |
| `SFireBullet` | 发射时始终读取 `CWeapon.spread_degrees`，当值 > 0 时在瞄准方向上施加随机角度偏移 |
| `SAreaEffect` | **移除**，由新的 `SAreaEffectModifier` 替代 |
| `SAreaEffectRender` | **移除**，由 `SAreaEffectModifier` 对应的渲染逻辑替代 |

## 新增系统总览

| 系统 | 查询组件 | 写入 |
|------|---------|------|
| `SWeightPenalty` | losable 计数 + `CMovement` | `CMovement.max_speed` |
| `SPresencePenalty` | 玩家 losable 计数 | 敌人 `CPerception` / `CSpawner` |
| `SFireHealConflict` | `CElementalAttack` + `CHealer` | `CHealer.heal_pro_sec` |
| `SColdRateConflict` | `CElementalAttack` + `CWeapon`/`CMelee` | `interval` |
| `SElectricSpreadConflict` | `CElementalAttack` + `CWeapon` | `spread_degrees` |
| `SAreaEffectModifier` | `CAreaEffect` + `CMelee`/`CHealer`/`CPoison` | 范围化效果 |

## 配置常量

```
COMPONENT_CAP = 5
WEIGHT_SPEED_PENALTY_PER_COMPONENT = 0.05
LETHAL_DROP_THRESHOLD = 3
FIRE_HEAL_REDUCTION = 0.3
COLD_RATE_MULTIPLIER = 1.4
ELECTRIC_SPREAD_DEGREES = 15.0
MAX_SPREAD_DEGREES = 30.0
AREA_EFFECT_POWER_RATIO = 0.6
```

所有数值为初始值，需通过 playtest 调整。
