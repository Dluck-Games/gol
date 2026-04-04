# Issue #188 实现交接文档

> **日期**: 2026-04-04  
> **Agent**: Coder Agent  
> **关联 Issue**: #188

---

## 完成的工作

### 修改的文件

1. **`scripts/systems/s_damage.gd`** (第 166-176 行)
   - 在 `_is_valid_bullet_target()` 函数中增加 CHP 组件前置检查
   - 位于 `_should_ignore_bullet_target()` 之后、camp 判断之前
   - 无 CHP 组件的实体（箱子、战利品箱等）不再被视为有效子弹目标

2. **`tests/unit/systems/test_s_damage_is_valid_bullet_target.gd`** (新建)
   - 6 个单元测试用例，覆盖 T01-T06 全部场景
   - 严格遵循 AGENTS.md 测试命名规范

3. **`tests/unit/system/test_damage_system.gd`** (更新)
   - `test_is_valid_bullet_target_allows_container_without_chp` → 重命名为 `test_is_valid_bullet_target_rejects_container_without_chp`
   - `test_process_bullet_collision_removes_bullet_for_container_without_chp` → 重命名为 `test_process_bullet_collision_keeps_bullet_for_container_without_chp`
   - 断言逻辑更新以匹配修复后的行为

---

## 测试契约覆盖

| 用例 ID | 描述 | 实现位置 | 覆盖状态 |
|---------|------|----------|----------|
| T01 | 有 CHP + 不同阵营 → 有效目标 | `test_valid_target_with_hp_different_camp` | ✅ 已覆盖 |
| T02 | 有 CHP + 相同阵营 → 无效目标 | `test_invalid_target_with_hp_same_camp` | ✅ 已覆盖 |
| T03 | 无 CHP + 有 CCollision（箱子）→ 无效目标 | `test_invalid_target_without_hp_box` | ✅ 已覆盖 |
| T04 | 无 CHP + 有 CTrigger（触发区）→ 无效目标 | `test_invalid_target_trigger` | ✅ 已覆盖 |
| T05 | 有 CHP + 无 CCamp（中立可破坏物）→ 有效目标 | `test_valid_target_with_hp_no_camp` | ✅ 已覆盖 |
| T06 | 无 CHP + owner_camp=-1 → 无效目标 | `test_invalid_target_without_hp_unknown_owner` | ✅ 已覆盖 |

**回归测试**: 旧的 `test_damage_system.gd` 中的两个用例已更新以反映新行为。

---

## 决策记录

### 1. CHP 检查的位置选择
- **决策**: 将 `if not target.has_component(CHP): return false` 放在 `_should_ignore_bullet_target()` 之后、camp 判断之前
- **理由**: CHP 是更基础的门槛——一个不能承受伤害的对象不应该成为子弹目标，无论阵营如何。这与 `_should_ignore_bullet_target()` 的前置过滤模式保持一致。

### 2. 旧测试更新策略
- **决策**: 直接修改旧的 `test_damage_system.gd` 中的两个用例，而非删除
- **理由**: 这两个用例测试的是容器实体的子弹碰撞行为，与本次修复直接相关。更新断言比删除更能体现行为变更的意图。

### 3. 测试文件命名
- **决策**: 新建文件使用 `test_s_damage_is_valid_bullet_target.gd`
- **理由**: 明确指向被测函数，便于快速定位。符合 AGENTS.md 中 "测试应位于 `tests/unit/systems/test_s_damage.gd` 或同级目录" 的指引。

---

## 仓库状态

| 项目 | 值 |
|------|-----|
| branch | `foreman/issue-188` |
| 修改文件 | `scripts/systems/s_damage.gd` |
| 新建文件 | `tests/unit/systems/test_s_damage_is_valid_bullet_target.gd` |
| 更新文件 | `tests/unit/system/test_damage_system.gd` |

### 测试结果摘要

**测试运行命令**:
```bash
/Users/dluckdu/Documents/Github/gol/gol-tools/foreman/bin/coder-run-tests.sh
```

**预期结果**:
- T01-T06 全部 6 个新测试用例通过
- `test_damage_system.gd` 中的更新用例通过
- 无其他 SDamage 相关测试回归

> **注意**: 由于环境限制，本次实现阶段未执行完整测试运行。请在合并前执行上述命令验证。

---

## 未完成事项

- [ ] 执行 `coder-run-tests.sh` 验证全部测试通过
- [ ] 提交代码（commit message 建议：`修复: 箱子不再阻挡子弹 (#188)`）

---

## 代码变更详情

### `scripts/systems/s_damage.gd` (第 166-176 行)

```gdscript
# 修改前
func _is_valid_bullet_target(target: Entity, owner_camp: int) -> bool:
	if _should_ignore_bullet_target(target):
		return false
	if owner_camp < 0:
		return true
	if not target.has_component(CCamp):
		return true
	return target.get_component(CCamp).camp != owner_camp

# 修改后
func _is_valid_bullet_target(target: Entity, owner_camp: int) -> bool:
	if _should_ignore_bullet_target(target):
		return false
	# Issue #188: 无血量实体不是有效子弹目标（如箱子、战利品箱）
	if not target.has_component(CHP):
		return false
	if owner_camp < 0:
		return true
	if not target.has_component(CCamp):
		return true
	return target.get_component(CCamp).camp != owner_camp
```

### 影响面

| 实体类型 | 修复前行为 | 修复后行为 |
|----------|-----------|-----------|
| Box（箱子） | 子弹命中→消耗→不穿透 | 子弹穿透通过 |
| LootBox（战利品箱） | 同上 | 同上 |
| Trigger2D（触发区） | 已被排除 | 无变化 |
| Pawn/Player/Survivor（战斗单位） | 正常受击 | 无变化 |
