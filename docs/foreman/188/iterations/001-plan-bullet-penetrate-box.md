# Issue #188 实施方案：修复箱子阻挡并消耗子弹

> **日期**: 2026-04-04
> **状态**: 待实施
> **规划者**: Planner Agent

---

## 需求分析

### 问题现象
玩家射击时，子弹击中箱子（Box / LootBox）后：
1. 子弹被**消耗销毁**（从世界移除）
2. 箱子**不受任何伤害**（无 CHP 组件）
3. 子弹**无法穿透**箱子继续飞行

### 根因验证（已确认）

**根因链路追踪：**

```
SDamage._process_bullet_collision() [s_damage.gd:60]
  ├── _find_bullet_targets() → 物理空间查询返回所有碰撞体（包括箱子）
  ├── _extract_valid_bullet_targets() → _is_valid_bullet_target() 过滤 [s_damage.gd:166]
  │   箱子无 CTrigger → 不被忽略 ✓
  │   箱子无 CCamp → 返回 true（视为有效目标）← 根因入口
  ├── _find_closest_entity() → 拾取最近实体（可能是箱子）
  └── _take_damage() → 无 CHP → 返回 true（仍消耗子弹！）[s_damage.gd:210-212]
      └── ECS.world.remove_entity(bullet_entity) ← 子弹销毁 [s_damage.gd:105]
```

**核心问题：`_is_valid_bullet_target()` 未将「无 CHP 的非战斗实体」排除在有效目标之外。**

### 箱子实体组件构成

| 组件 | 来源 | 说明 |
|------|------|------|
| CTransform | AuthoringNode2D 基类 | 位置/旋转/缩放 |
| CSprite | authoring_box.gd:42 | 箱子贴图 |
| CContainer | authoring_box.gd:47 | 存储物品 |
| CCollision | authoring_box.gd:53 | 碰撞体 (CircleShape2D r=16) |

**确认：箱子没有 CHP、CCamp、CTrigger。**

---

## 影响面分析

### 直接修改文件

| 文件 | 修改类型 | 影响 |
|------|----------|------|
| `scripts/systems/s_damage.gd` | **修改** `_is_valid_bullet_target()` | 唯一修改点 |

### 受影响的实体类型（有 CCollision 但无 CHP）

| 实体 | 文件 | 当前行为 | 修复后行为 | 风险评估 |
|------|------|----------|------------|----------|
| **Box（箱子）** | `authoring_box.gd` | 子弹命中→消耗→不穿透 | 子弹穿透通过 | **预期修复目标** ✅ |
| **LootBox（战利品箱）** | `gol_world.gd:229,537` | 同上 | 同上 | **预期修复目标** ✅ |
| **Trigger2D（触发区）** | `authoring_trigger_2d.gd` | 已被 `_should_ignore_bullet_target()` 排除 | 无变化 | **无影响** ⚪ |

### 不受影响的实体类型（有 CHP + CCollision）

| 实体 | 有 CHP？ | 有 CCollision？ | 说明 |
|------|----------|-----------------|------|
| Pawn（基础单位） | ✅ | ✅ | 正常受击 |
| Player（玩家） | ✅ | ✅ | 正常受击 |
| Survivor（幸存者） | ✅ | ✅ | 正常受击 |
| Campfire（营火） | ✅ | ✅ | 可破坏建筑 |
| Spawner（生成器） | ✅ | ✅ | 可破坏对象 |

### 子弹系统分析

- **仅一种子弹类型**: `bullet_normal.tres` — 无穿透/穿透属性
- **CBullet 组件极简**: 仅 `damage` + `owner_entity`，无特殊标记位
- **单次命中后销毁**: `s_damage.gd:105` 无条件移除，无穿透机制
- **结论**: 不存在需要特殊处理的子弹子类型

---

## 实现方案

### 方案选择：A — 在 `_is_valid_bullet_target()` 增加 CHP 前置检查

**选择理由：**
1. 最小改动量（单函数增加 2 行）
2. 在最早环节过滤无效目标，避免后续无意义的 `_take_damage()` 调用
3. 与现有架构一致：`_should_ignore_bullet_target()` 已是同类前置过滤模式
4. Trigger2D 已有 CTrigger 保护，新增 CHP 检查不影响它
5. 未来如需可破坏箱子，只需给箱子加 CHP 即可自然支持

### 具体修改点

**文件**: `gol-project/scripts/systems/s_damage.gd`
**函数**: `_is_valid_bullet_target()` (第 166-173 行)

#### 修改前：

```gdscript
func _is_valid_bullet_target(target: Entity, owner_camp: int) -> bool:
	if _should_ignore_bullet_target(target):
		return false
	if owner_camp < 0:
		return true
	if not target.has_component(CCamp):
		return true
	return target.get_component(CCamp).camp != owner_camp
```

#### 修改后：

```gdscript
func _is_valid_bullet_target(target: Entity, owner_camp: int) -> bool:
	if _should_ignore_bullet_target(target):
		return false
	if not target.has_component(CHP):        # <-- 新增：无血量实体不是有效子弹目标
		return false                           # <-- 新增
	if owner_camp < 0:
		return true
	if not target.has_component(CCamp):
		return true
	return target.get_component(CCamp).camp != owner_camp
```

### 修改逻辑说明

1. **位置**: 放在 `_should_ignore_bullet_target()` 之后、camp 判断之前
2. **条件**: `not target.has_component(CHP)` — 无 CHP 组件的实体直接排除
3. **效果**:
   - 箱子（Box/LootBox）→ 被排除 → 子弹穿透
   - Trigger2D → 已被 CTrigger 规则排除 → 无变化
   - 所有有 CHP 的战斗实体 → 通过此检查 → 行为不变
4. **为什么放在 camp 判断之前**：CHP 是更基础的门槛——一个不能承受伤害的对象不应该成为子弹目标，无论阵营如何

---

## 架构约束

### 涉及的 AGENTS.md 文件
- `/Users/dluckdu/Documents/Github/gol/AGENTS.md` — 工作流规则
- `/Users/dluckdu/Documents/Github/gol/.worktrees/foreman/ws_20260404050507._1b7ad736/AGENTS.md` — 游戏代码规范

### 引用的架构模式
- **ECS System 处理模式**: SDamage 是 gameplay 组系统，在 `_process` 中逐帧处理
- **组件纯数据原则**: CHP 作为数据组件表示「可受伤性」
- **前置过滤模式**: `_should_ignore_bullet_target()` 已建立同类先验过滤范式

### 文件归属层级
- `scripts/systems/s_damage.gd` — ECS System 层（唯一修改文件）
- 测试应位于 `tests/unit/systems/test_s_damage.gd` 或同级目录

### 测试模式
- **单元测试**: gdUnit4 `extends GdUnitTestSuite`，mock Entity 验证 `_is_valid_bullet_target()` 返回值
- **E2E 测试**: AI Debug Bridge 场景验证（射击箱子→子弹穿透）

---

## 测试契约

### 单元测试（必须）

**测试套件**: `test_s_damage_is_valid_bullet_target.gd`

| 用例 ID | 描述 | 输入 | 期望输出 |
|---------|------|------|----------|
| T01 | 有 CHP + 不同阵营 → 有效目标 | target={CHP, CCamp(camp=ENEMY)}, owner_camp=PLAYER | `true` |
| T02 | 有 CHP + 相同阵营 → 无效目标 | target={CHP, CCamp(camp=PLAYER)}, owner_camp=PLAYER | `false` |
| T03 | **无 CHP + 有 CCollision（箱子）→ 无效目标** | target={CCollision}, owner_camp=PLAYER | `false` ← **关键回归测试** |
| T04 | 无 CHP + 有 CTrigger（触发区）→ 无效目标 | target={CCollision, CTrigger}, owner_camp=PLAYER | `false` |
| T05 | 有 CHP + 无 CCamp（中立可破坏物）→ 有效目标 | target={CHP}, owner_camp=PLAYER | `true` |
| T06 | 无 CHP + owner_camp 未知 → 无效目标 | target={CCollision}, owner_camp=-1 | `false` ← **变更前为 true** |

### E2E 测试（建议）

**场景**: 射击箱子穿透验证
- 前置：生成箱子实体 + 敌方目标（位于箱子后方）
- 动作：朝箱子方向射击
- 断言：
  1. 子弹未在箱子位置销毁
  2. 敌方目标受到伤害
  3. 箱子 HP 无变化（本来就无 CHP）

---

## 风险点

| # | 风险 | 等级 | 缓解措施 |
|---|------|------|----------|
| R1 | 未来添加无 CHP 的可破坏装饰物（如玻璃瓶） | 低 | 设计阶段给此类实体加 CHP；或扩展 CBullet 增加 `can_hit_non_hp` 标记位 |
| R2 | LootBox 本身设计意图是否应被射开？ | 低 | 当前 LootBox 无 CHP，即使射中也不会造成任何效果（不扣血、不开箱），所以排除它是合理的行为修正 |
| R3 | T06 用例：owner_camp=-1 时行为变更（true→false） | 中 | 需确认是否有代码路径传入 owner_camp=-1 且期望命中无 CHP 对象。经分析：`owner_camp=-1` 来自 owner 无 CCamp，此时子弹应该只命中战斗单位，排除非战斗对象是合理的 |
| R4 | 性能：每帧对每个候选目标多一次 has_component 查查 | 极低 | has_component 是 Dictionary O(1) 查找，可忽略不计 |

---

## 建议的实现步骤

### Step 1: 单元测试先行
1. 创建 `tests/unit/systems/test_s_damage_is_valid_bullet_target.gd`
2. 实现 T01-T06 共 6 个测试用例
3. **运行确认 T03/T06 失败**（当前行为的回归基线）

### Step 2: 实施 bugfix
1. 编辑 `scripts/systems/s_damage.gd` 第 168-169 行
2. 在 `_is_valid_bullet_target()` 中插入 CHP 检查
3. 代码变更量：+2 行

### Step 3: 验证单元测试
1. 运行 gdUnit4 测试套件
2. 确认全部 6 个用例通过
3. 确认无其他测试回归（SDamage 相关的全部单元测试）

### Step 4: E2E 验证（可选但推荐）
1. 使用 AI Debug Bridge 创建测试场景
2. 验证射击箱子时子弹穿透行为
3. 截图留存证据

### Step 5: 提交
1. commit message 格式遵循项目规范
2. 引用 Issue #188

---

## 附录：调用链完整追踪

```
每帧循环:
SDamage.process(delta)
  └── query(): CBullet OR CDamage
      └── _process_entity(entity, delta)
          ├── [entity has CDamage] → _process_pending_damage(entity)
          │       └── _take_damage(target_entity, amount, dir)
          │           ├── 无 CHP → return true (仍消耗！)
          │           ├── 无敌帧 → return true (仍消耗！)
          │           └── 有 CHP → 扣血/死亡处理
          │
          └── [entity has CBullet + CCollision] → _process_bullet_collision(bullet_entity)  [L60]
                  ├── L111: _find_bullet_targets(pos, collision, owner)
                  │     ├── Area2D overlap → each via _is_valid_bullet_target()  [L122]
                  │     └── space_state.query → _extract_valid_bullet_targets()
                  │             └── each via _is_valid_bullet_target()  [L160]
                  ├── L74: _find_closest_entity(pos, valid_targets)
                  ├── L98: _take_damage(closest, damage, knockback_dir)
                  │   └── return bool: false=不消耗, true=消耗
                  ├── L102: if has CH P → _apply_bullet_effects()
                  └── L105: ECS.world.remove_entity(bullet_entity)  ← 子弹销毁
```

**本次修改位置**: `_is_valid_bullet_target()` [L166] — 在调用链最前端拦截无 CHP 实体
