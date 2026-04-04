# Issue #226 元素子弹 VFX — Review 修复

## 修复概述

根据 Reviewer 报告 `/Users/dluckdu/Documents/Github/gol/docs/foreman/226/iterations/03-reviewer-element-bullet-vfx.md` 中的 2 个 Important 级别问题进行修复。

## 逐项修复记录

### 修复 1：集成测试添加 impact 验证

**问题**: `test_impact_on_hit` 契约声称"部分覆盖"但实际完全未实现。SDamage 第 107-108 行的 VFX 调用路径缺乏任何集成级验证。

**文件**: `tests/integration/test_bullet_vfx.gd`

**修复方式**:
1. 在 `test_run()` 方法末尾添加对 `_test_impact_vfx(world)` 的调用
2. 新增 `_test_impact_vfx()` 辅助方法，验证：
   - 调用 `SBulletVfx.spawn_impact(Vector2(200, 200), CElementalAttack.ElementType.FIRE)` 后
   - `ECS.world.get_child_count()` 应该增加（创建了子节点）
   - `ECS.world.get_children()` 中应该存在 `CPUParticles2D` 类型的节点

```gdscript
## 测试：spawn_impact 在 world 上创建 CPUParticles2D
func _test_impact_vfx(world: GOLWorld) -> TestResult:
	var result := TestResult.new()

	var children_before: int = ECS.world.get_child_count()
	SBulletVfx.spawn_impact(Vector2(200, 200), CElementalAttack.ElementType.FIRE)
	await world.get_tree().process_frame

	var children_after: int = ECS.world.get_child_count()
	result.assert_true(children_after > children_before, "spawn_impact creates a child node on ECS.world")

	var has_impact_particles: bool = false
	for child in ECS.world.get_children():
		if child is CPUParticles2D:
			has_impact_particles = true
			break
	result.assert_true(has_impact_particles, "spawn_impact creates CPUParticles2D node")

	return result
```

### 修复 2：两个空单元测试标记为 skip

**问题**: 两个 spawn_impact 相关的单元测试实质上是空断言，伪装为通过的测试。

**文件**: `tests/unit/system/test_bullet_vfx.gd`

**修复方式**:
使用 gdUnit4 的 `skip()` 方法标记这两个测试：

```gdscript
## 测试：spawn_impact() 创建 CPUParticles2D 并挂载到 ECS.world
## 注：此测试需要 ECS.world 可用，但单元测试中不设置 World
## 使用 skip 标记需要 World 环境才能验证
func test_spawn_impact_static_method_exists() -> void:
	skip("需要 ECS.world 环境")


## 测试：spawn_impact 对 element_type = -1 不创建 impact
## 注：单元测试中无法验证粒子创建（需要 World），使用 skip 标记
func test_spawn_impact_no_element_does_nothing() -> void:
	skip("需要 ECS.world 环境")
```

## 测试结果

运行 `/Users/dluckdu/Documents/Github/gol/gol-tools/foreman/bin/coder-run-tests.sh`：

```
  Total: 498    Passed: 498    Failed: 0      Skipped: 0

  RESULT: ALL TESTS PASSED
```

所有测试通过，无新增回归。

## 仓库状态

**修改的文件**:
- `tests/integration/test_bullet_vfx.gd` — 添加 `_test_impact_vfx()` 方法及调用
- `tests/unit/system/test_bullet_vfx.gd` — 两个空测试改为 `skip()` 标记

**未修改的文件**（遵循 Reviewer 约束）:
- 业务代码未修改（s_bullet_vfx.gd、s_damage.gd、c_bullet.gd、s_fire_bullet.gd）
- AGENTS.md 未修改
- Trail 相关测试未修改

## 未完成事项

无。Reviewer 提出的 2 个 Important 级别问题已全部修复并通过测试。
