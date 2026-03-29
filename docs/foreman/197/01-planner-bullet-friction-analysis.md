# Issue #197 — 冰冻后子弹减速停止 Bug 分析

## 需求分析

### Issue 要求
- **现象**：子弹射出后偶现速度递减，最终在空中停止不动
- **触发条件**：用户报告"冰冻后"出现，评论补充"拾取手枪时更容易出现"
- **期望行为**：子弹始终保持匀速飞行，直到达到最大射程（lifetime 3.0s）或发生碰撞被销毁

### 边界条件
- 子弹由玩家或 AI 射击者创建
- 子弹的 `CMovement.friction` 默认继承自 `DEFAULT_FRICTION = 800.0`
- 子弹不应被冰冻/元素效果系统影响（无 `CElementalAffliction` 组件）
- 射击者被冻结时不应阻止已射出子弹的运动（冻结只阻止新的射击）

---

## 根因分析

### 根因：`SMove._apply_friction()` 对所有 `CMovement` 实体施加默认摩擦力

**完整调用链追踪：**

```
EntityRecipe("bullet_normal")
  └─ CMovement { friction = 800.0 (DEFAULT_FRICTION, 未在 recipe 中覆盖) }
  └─ CBullet, CTransform, CSprite, CCollision, CLifeTime

SFireBullet._create_bullet()  (s_fire_bullet.gd:113-134)
  ├─ bullet_movement.velocity = direction * weapon.bullet_speed  (line 129)
  └─ bullet_movement.friction = 0.0  (line 130) ← 修复点

SMove.process()  (s_move.gd:12)
  └─ _process_entity(entity, delta)  (每帧对所有 CMovement + CTransform 实体)
       └─ _apply_friction(move, delta)  (s_move.gd:77-92)
            ├─ friction_force = move.friction * delta
            ├─ if speed > friction_force → move_toward(ZERO, friction_force)  // 逐帧减速
            └─ else → velocity = Vector2.ZERO  // 完全停止
```

**问题本质：**
1. `CMovement` 组件的 `friction` 默认值为 800.0（`c_movement.gd:10`）
2. 子弹 recipe `bullet_normal.tres` 创建的 `CMovement` 未显式设置 `friction`，因此继承默认值 800.0
3. `SMove._apply_friction()` 在每帧对**所有** `CMovement` 实体施加摩擦力（`s_move.gd:77-92`），不区分实体类型
4. 子弹速度约 1400 px/s，摩擦力 800.0 px/s²，意味着子弹在约 1.75 秒内速度降至零并停止
5. 子弹 lifetime 为 3.0 秒，因此在 lifetime 到期前子弹就已经停在了空中

### 为什么是"偶现"？

实际上这个问题应该是**必现**的（在没有修复的情况下），而非偶现。可能的原因：
- 子弹飞行时间短（近距离射击），减速效果不明显
- 观察者注意力集中在射击目标而非子弹轨迹
- "拾取手枪时更容易出现"可能是因为手枪射击频率高、连续射击使得停在空中的子弹更容易被注意到

### 冰冻与子弹的关系

**冰冻效果不影响子弹本身。** 分析链路：

- 冰冻效果通过 `CElementalAffliction` 组件施加，需要 `SElementalAffliction` 系统处理
- 子弹实体不携带 `CElementalAffliction`，也不会被元素系统查询
- `SDamage._apply_bullet_effects()` 在命中时调用 `ElementalUtils.apply_attack()`，但这是给**目标**施加效果，不是给子弹
- 射击者被冻结时 `SFireBullet` 会阻止新射击（`s_fire_bullet.gd:50-52`），但不会影响已射出子弹

**结论：冰冻与子弹减速是两个独立问题。子弹减速的根因是摩擦力默认值，与冰冻无关。**

---

## 影响面分析

### 受影响的文件

| 文件 | 角色 | 变更类型 |
|------|------|----------|
| `scripts/systems/s_fire_bullet.gd:130` | 修复点 | 新增 `friction = 0.0` |
| `scripts/components/c_movement.gd:10` | 默认值定义 | 不修改（修改会影响所有实体） |

### 上游调用者
- `SFireBullet` 由 ECS 框架在 "gameplay" 组内自动调度，每帧执行

### 下游依赖
- `SMove._apply_friction()` 消费 `CMovement.friction`，修复后 `friction=0.0` 使其为 no-op
- `SLife` 在 lifetime 到期后销毁子弹（不受影响）
- `SDamage` 在碰撞时销毁子弹（不受影响）

### 受影响的实体/组件类型
- **`CBullet` + `CMovement`**：所有子弹实体（当前仅 `bullet_normal` recipe）
- 潜在的未来子弹 recipe（如果有新 bullet 类型，也需在创建时设置 `friction=0.0`）

### 潜在副作用
- **无副作用**：设置 `friction=0.0` 只使 `_apply_friction` 变为 no-op（`move_toward(ZERO, 0.0)` 返回原值），不影响其他系统
- **未来风险**：如果新增 bullet recipe 但忘记设置 `friction=0.0`，问题会复现

---

## 实现方案

### 推荐方案：在 `SFireBullet._create_bullet()` 中显式设置 `bullet_movement.friction = 0.0`

**理由：**
1. 最小侵入性修改（仅 1 行代码）
2. 不影响 `CMovement` 默认值（其他实体仍正常使用摩擦力）
3. 不影响 `SMove` 系统逻辑（不需要修改系统行为）

### 具体修改位置

**文件**: `scripts/systems/s_fire_bullet.gd`
**函数**: `_create_bullet()` (line 113-134)
**修改行**: line 130（在 `velocity` 赋值之后新增）

```gdscript
# 现有代码 (line 128-129):
if bullet_movement:
    bullet_movement.velocity = direction * weapon.bullet_speed
    bullet_movement.friction = 0.0  # ← 新增：确保子弹匀速飞行，不受 SMove 摩擦力影响
```

**状态**：此修复已在当前代码库中实现（`s_fire_bullet.gd:130`）。

### 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/systems/s_fire_bullet.gd` | 修改 | `_create_bullet()` 中新增 `bullet_movement.friction = 0.0` |
| `tests/unit/system/test_s_move.gd` | 修改（已完成） | 新增 `test_move_no_friction_when_friction_is_zero` 验证 friction=0 行为 |
| `tests/integration/test_bullet_flight.gd` | 新增（已完成） | 端到端验证子弹匀速飞行 |

---

## 架构约束

### 涉及的 AGENTS.md 文件
- `scripts/systems/AGENTS.md` — SMove 和 SFireBullet 均在 systems 目录下
- `scripts/components/AGENTS.md` — CMovement 和 CBullet 组件定义
- `tests/AGENTS.md` — 测试层级和模式

### 引用的架构模式
- **GECS System = logic**：`SFireBullet` 在创建子弹时设置运行时属性，符合 system 包含逻辑的约定
- **Component = pure data**：`CMovement.friction` 是纯数据字段，在 system 层面设置运行时值
- **不修改默认值**：`CMovement.DEFAULT_FRICTION = 800.0` 对 AI/敌人正常运动是必要的，不应改为 0

### 文件归属层级
- 修改文件：`scripts/systems/s_fire_bullet.gd`（已在 systems 目录下，符合 AGENTS.md 约定）
- 测试文件：`tests/unit/system/test_s_move.gd`（unit 测试）、`tests/integration/test_bullet_flight.gd`（integration 测试）

### 测试模式
- **单元测试**：`test_s_move.gd` 使用 gdUnit4 `GdUnitTestSuite`，直接实例化 Component 和 System 验证摩擦力逻辑
- **集成测试**：`test_bullet_flight.gd` 使用 `SceneConfig`，加载真实 GOLWorld 验证端到端射击流程
- 引用 `tests/AGENTS.md`：Phase 1 (gdUnit4) + Phase 2 (SceneConfig)

---

## 测试契约

### 已完成的测试

- [x] **单元测试：friction=0 时速度不衰减** (`tests/unit/system/test_s_move.gd:7-27`)
  - 验证方式：创建 CMovement(friction=0.0)，模拟 60 帧 SMove 处理，断言速度不变
  - 覆盖根因：确认 `_apply_friction` 在 friction=0 时为 no-op

- [x] **单元测试：friction>0 时正常减速** (`tests/unit/system/test_s_move.gd:31-50`)
  - 验证方式：创建 CMovement(friction=800.0)，模拟 60 帧，断言速度显著下降
  - 回归保护：确认正常摩擦力逻辑不受影响

- [x] **集成测试：SFireBullet 创建的子弹 friction=0 且匀速飞行** (`tests/integration/test_bullet_flight.gd:42-105`)
  - 验证方式：SceneConfig 加载 GOLWorld，AI 射击者发射子弹，验证 friction=0、60 帧后速度不变、位移>1000px
  - 覆盖端到端流程：recipe 创建 → velocity 设置 → friction 覆盖 → SMove 保持匀速

### 建议补充的测试

- [ ] **集成测试：子弹 lifetime 到期正常销毁**
  - 验证方式：等待 3.0 秒后检查子弹是否被移除
  - 标注：需要 E2E 验证（需等待 3.0s 真实时间）
  - 原因：验证匀速飞行子弹能在 lifetime 内正常飞出屏幕/被销毁，而非停在空中

- [ ] **E2E 验证：冰冻后射击表现**
  - 验证方式：AI Debug Bridge 触发冰冻效果，射击者被冻结后验证不射击、冻结解除后射击正常
  - 标注：E2E 验证（运行时行为）
  - 原因：Issue 提到冰冻场景，虽然根因与冰冻无关，但需验证冰冻不影响射击

---

## 风险点

### 低风险
- **修复已就位**：`s_fire_bullet.gd:130` 的 `bullet_movement.friction = 0.0` 已经实现且测试覆盖
- **无性能影响**：friction=0 使 `_apply_friction` 仍执行但为 no-op，开销可忽略

### 需注意
- **未来 bullet recipe**：如果新增子弹类型（如霰弹、火箭），`_create_bullet()` 中的 `friction=0.0` 会覆盖所有通过 `SFireBullet` 创建的子弹。但如果绕过 `SFireBullet` 直接创建子弹（当前无此路径），需注意手动设置 friction
- **recipe 中的 friction**：`bullet_normal.tres` 的 CMovement 子资源未设置 friction，依赖运行时覆盖。可以考虑在 recipe 中显式设置 `friction = 0.0` 作为防御性措施，但不是必需的

---

## 建议的实现步骤

### 当前状态：修复已完成

根据代码库当前状态，修复已实现，测试已覆盖。以下是原始修复步骤（供参考）：

1. **确认根因**：阅读 `SMove._apply_friction()` 确认它对所有 CMovement 实体施加摩擦力
2. **定位修复点**：`SFireBullet._create_bullet()` 是子弹创建的唯一入口
3. **添加 friction=0.0**：在 `s_fire_bullet.gd:130` 新增 `bullet_movement.friction = 0.0`
4. **添加单元测试**：`test_s_move.gd` 新增 friction=0 验证
5. **添加集成测试**：`test_bullet_flight.gd` 验证端到端子弹匀速飞行
6. **运行全量测试**：确认无回归
7. **E2E 验收**：实际游戏中射击、冰冻后射击、连续射击表现正常

### 如需进一步加固

8. 在 `bullet_normal.tres` 的 CMovement 子资源中显式设置 `friction = 0.0`（防御性措施，非必需）
9. 补充 lifetime 销毁集成测试
10. 补充冰冻场景 E2E 测试
