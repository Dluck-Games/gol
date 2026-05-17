# Handoff: CAreaEffect 目标过滤重构 + 范围化架构重设计

**Date:** 2026-05-16
**Topic:** Issue #331 — CAreaEffect 目标过滤重构
**Participants:** User (Dluck) + Claude
**Status:** 设计决策完成，待进入实施阶段

---

## 原始 Issue

- **Issue:** [#331](https://github.com/Dluck-Games/god-of-lego/issues/331) — 重构：CAreaEffect 目标过滤标志应从组件中移除，由各效果系统自行决定
- **根因:** `CAreaEffect` 同时承载范围参数（radius）和目标过滤标志（affects_self/allies/enemies），导致不同系统语义冲突
- **触发案例:** Issue #257 — 玩家同时拥有治疗魔晶（affects_allies=true）和毒魔晶时，SPoison 错误地对友方施加中毒
- **当前补丁:** Commit `c99d158` 在 SPoison 中构造临时视图 `_make_poison_targeting_view()` 强制覆盖标志，破坏 SSOT

---

## 对话演进与关键洞察

### 第一轮：用户要求

用户要求：
1. 仔细阅读和理解 issue #331
2. 用头脑风暴技能讨论修改方案

### 第二轮：Claude 的技术方案（被用户纠正）

Claude 最初直接给出了技术实现方案（回调函数式过滤），但用户指出：
> "你都不和我讨论一下这里的设计方案吗？先不说问题，说我们的数据结构的设计，数据流量的设计，玩法的设计"

**教训：** 用户希望先讨论设计层面的问题（数据结构、数据流、玩法），而不是直接跳到实现。

### 第三轮：设计层面讨论

用户明确了三个核心设计原则：

1. **CAreaEffect 只是一个范围化标签** —— 具体怎么生效由和它组合的其他玩法组件与系统决定
2. **数据流不存在问题** —— 关键在于范围化生效的那个玩法系统，它想对哪些实体进行操作，完全由对应的玩法行为决定
3. **不同系统有不同的实现** —— 不需要统一处理

### 第四轮：用户深入理解架构

用户主动分析了 `SAreaEffectModifier` 的架构问题：

> "范围化的效果本身是要有两个 system 来控制吗？一个是它的修改器的 system，还有一个是它原本玩法功能实现的那个 system... 相当于同一个玩法行为的逻辑有一份放在自己的 system 里，另一部分放在范围化修改器里"

用户的理解完全正确。当前架构中：
- `SMeleeAttack` 管单体近战攻击
- `SHealer` 管范围治疗（注意：它本身已经是范围效果）
- `SAreaEffectModifier` 管"范围化版本"的伤害/治疗
- 三个 system 并行运行，**没有互斥逻辑**

### 第五轮：最终决策

用户做出关键决策：

> **"这个 modifier 的 system 也可以被重构简化掉，也把它加入我们的计划清单里。相应的实现不如都挪到对应的 system 当中去就好了。"**

---

## 最终设计决策

### 决策 1：CAreaEffect 纯标签化

`CAreaEffect` 只保留范围化参数，移除所有行为逻辑：

**保留：**
- `radius: float` — 范围半径
- `power_ratio: float` — 功率衰减比例
- `apply_melee: bool` — 通道选择：是否范围化近战
- `apply_healer: bool` — 通道选择：是否范围化治疗
- `poison_exposure_timers: Dictionary` — SPoison 运行时状态（非导出）

**移除：**
- `affects_self: bool`
- `affects_allies: bool`
- `affects_enemies: bool`

### 决策 2：SAreaEffectModifier 逐步解散

`SAreaEffectModifier` 的职责分散到各个玩法 system：

| 当前职责 | 迁移目标 |
|---------|---------|
| CMelee + CAreaEffect → 圆形范围持续伤害 | `SMeleeAttack` 或新的 `SMeleeAreaEffect` |
| CHealer + CAreaEffect → 圆形范围持续治疗 | `SHealer`（扩展） |
| 目标过滤（affects_*） | 各 system 自行实现 |
| 半径扫描 | 共享工具函数 `AreaEffectUtils.find_targets_in_range()` |

### 决策 3：目标过滤由各 System 自行决定

不再有任何统一的目标过滤机制。每个 system 根据自己的玩法语义决定：

| System | 目标过滤逻辑 |
|--------|------------|
| SMeleeAttack（单体） | 敌方、扇形范围、视线检测 |
| SMeleeAttack（范围化） | 敌方、圆形范围、无视线检测 |
| SHealer | 友方、圆形范围 |
| SPoison | 敌方、圆形范围 |
| 未来系统 | 自定义 |

### 决策 4：AreaEffectUtils 保留为纯工具函数

`AreaEffectUtils.find_targets_in_range()` 只负责：
1. 查询世界中所有候选实体
2. 按距离过滤（<= radius）
3. **不做任何阵营/身份过滤**

各 system 拿到结果后自行过滤。

---

## 实施计划（待细化）

### Phase 1：CAreaEffect 简化（Issue #331 本身）

1. **移除 `affects_*` 字段**
   - `scripts/components/c_area_effect.gd`
   - `scripts/utils/area_effect_utils.gd` — 移除 `_should_affect_target()`

2. **更新调用方**
   - `scripts/systems/s_area_effect_modifier.gd` — 自行实现目标过滤
   - `scripts/systems/s_poison.gd` — 移除 `_make_poison_targeting_view()`，自行过滤

3. **更新 Recipe 文件**
   - `resources/recipes/materia_heal.tres`
   - `resources/recipes/materia_damage.tres`
   - `resources/recipes/survivor_healer.tres`
   - `resources/recipes/enemy_poison.tres`

4. **更新测试**
   - `tests/unit/test_area_effect_utils.gd`
   - `tests/unit/system/test_area_effect_modifier.gd`
   - `tests/integration/flow/test_flow_poison_heal_materia_targeting_scene.gd`

### Phase 2：SAreaEffectModifier 解散（新 Issue）

将 `SAreaEffectModifier` 的职责迁移到各玩法 system：

1. **SHealer 扩展**
   - 检查 `CAreaEffect` 存在时，使用 `CAreaEffect.radius` 替代 `CHealer.heal_range`
   - 应用 `power_ratio` 衰减
   - 自行实现阵营过滤（友方）

2. **SMeleeAttack 扩展（或新建 SMeleeAreaEffect）**
   - 检查 `CAreaEffect` 存在时，切换到圆形范围检测
   - 应用 `power_ratio` 衰减
   - 自行实现阵营过滤（敌方）

3. **移除 SAreaEffectModifier**
   - 删除 `scripts/systems/s_area_effect_modifier.gd`
   - 更新所有 system 注册表

4. **SAreaEffectModifierRender 更新**
   - 检查是否还依赖 `SAreaEffectModifier` 的存在
   - 可能需要改为监听 `CAreaEffect + CMelee/CHealer/CPoison` 组合

---

## 关键文件清单

### 需要修改的文件

| 文件 | 改动类型 | 说明 |
|-----|---------|------|
| `scripts/components/c_area_effect.gd` | 修改 | 移除 affects_* |
| `scripts/utils/area_effect_utils.gd` | 修改 | 移除 _should_affect_target() |
| `scripts/systems/s_area_effect_modifier.gd` | 修改 → 删除 | Phase 1 修改，Phase 2 删除 |
| `scripts/systems/s_poison.gd` | 修改 | 移除 _make_poison_targeting_view() |
| `scripts/systems/s_healer.gd` | 修改 | Phase 2 扩展范围化逻辑 |
| `scripts/systems/s_melee_attack.gd` | 修改 | Phase 2 扩展范围化逻辑 |
| `scripts/systems/s_area_effect_modifier_render.gd` | 修改 | 更新查询条件 |
| `resources/recipes/materia_heal.tres` | 修改 | 移除 affects_* |
| `resources/recipes/materia_damage.tres` | 修改 | 移除 affects_* |
| `resources/recipes/survivor_healer.tres` | 修改 | 移除 affects_* |
| `resources/recipes/enemy_poison.tres` | 修改 | 移除 affects_* |
| `tests/unit/test_area_effect_utils.gd` | 修改 | 更新测试 |
| `tests/unit/system/test_area_effect_modifier.gd` | 修改 → 删除 | Phase 1 修改，Phase 2 删除 |
| `tests/integration/flow/test_flow_poison_heal_materia_targeting_scene.gd` | 修改 | 移除 CAreaEffect 中的 affects_* |

### 需要检查的潜在影响

- 存档序列化：`CAreaEffect` 的旧字段在存档中可能仍存在（虽然 affects_* 是 @export 的）
- 动态代码设置：检查是否有运行时代码动态设置 `affects_*`
- 其他 Recipe：检查是否有其他 .tres 文件包含 `affects_*`

---

## 测试契约

### Phase 1 测试

- [ ] 治疗光环仍然只影响友方
- [ ] 伤害光环仍然只影响敌方
- [ ] 毒 AoE 仍然只影响敌方
- [ ] 同时拥有治疗+毒魔晶时，各自目标过滤独立工作
- [ ] `test_flow_poison_heal_materia_targeting_scene.gd` 通过
- [ ] `AreaEffectUtils.find_targets_in_range()` 在不传 affects_* 时只按距离过滤

### Phase 2 测试

- [ ] SHealer 单体模式不变（无 CAreaEffect 时）
- [ ] SHealer 范围化模式正确（有 CAreaEffect 时）
- [ ] SMeleeAttack 单体模式不变
- [ ] SMeleeAttack 范围化模式正确
- [ ] SAreaEffectModifier 完全移除后无报错
- [ ] 粒子渲染正常

---

## 风险点

1. **SHealer 已经是范围效果** — 它和 `SAreaEffectModifier + CHealer` 的区别是什么？需要明确设计语义
2. **SMeleeAttack 范围化** — 单体攻击有扇形+视线检测，范围化后是圆形+无视线检测，这个语义差异需要确认
3. **双重效果** — 当前 `SMeleeAttack` 和 `SAreaEffectModifier` 并行运行，解散后是否还需要并行？还是互斥？
4. **存档兼容** — 旧存档中 `CAreaEffect` 可能序列化了 `affects_*` 字段

---

## 相关 Issue

- #331 — 本 Issue（CAreaEffect 目标过滤重构）
- #257 — 触发案例（毒+治疗魔晶目标过滤冲突）
- #332 — 魔晶掉落表简化（有关联，CAreaEffect 配置需同步调整）

---

## 下一步行动

1. **创建 Phase 2 Issue** — SAreaEffectModifier 解散
2. **实施 Phase 1** — 按 gol-fix-issue 技能流程执行
3. **实施 Phase 2** — 待 Phase 1 完成后进行

---

*This handoff document is immutable. For updates, create a new handoff file.*
