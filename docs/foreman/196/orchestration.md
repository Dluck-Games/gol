# Orchestration — Issue #196

## Issue
**Title:** 毒药和范围化组件在地图上不刷新
**Labels:** bug, topic:gameplay, foreman:assign
**Body:**
**Bug 描述：**
毒药和范围化组件（可能指掉落物/道具组件）在地图上不刷新出现。

**具体场景（基于观察）：**
预期在地图中随时间或特定条件刷新的“毒药”与“范围化组件”，实际并未在地图中生成/刷新。

**期望行为：**
毒药和范围化组件应能按照游戏逻辑或刷新池配置正常在地图上生成并显示。

**实际行为：**
这两种组件未出现在地图上，刷新机制失效。

---

## Decision Log

### Decision 1 — 2026-03-29 17:05
**Trigger:** @coder completed (06-coder-fix-spawner-test-detection.md), CI re-checked
**Assessment:** CI 仍然失败（run 23705608737）。Unit Tests 通过，Integration Tests 失败。失败点与修复前完全相同：`Spawned enemy entity found in world.entities — expected: true, got: false`。关键线索：entity count 从 2 增长到 5，证明 `add_entity()` 确实执行了，但 `_find()` / `world.entities` 遍历仍找不到新 spawn 的 enemy。Coder 在 06 中的修复（额外帧等待 + `_find()` 查找）没有解决问题，说明可能不是时序问题而是 entity 查找逻辑本身有问题（例如 entity name 不匹配、或者 deep-copy 导致的 entity 引用不一致）。这是第 2 次内部迭代（05 + 06），还剩最后一次机会。
**Action:** spawn @coder
**Model:** kimi-k2.5-ioa
**Guidance:** 修复 Test 1 的 entity 查找失败。entity count 证明 spawn 工作正常，问题在查找逻辑。
**TL Context for Coder:**
> ## CI 失败详情
> 
> **Run:** https://github.com/Dluck-Games/god-of-lego/actions/runs/23705608737/job/69056872990
> 
> **失败输出：**
> ```
> [PASS] Spawner spawned a new entity into the world (2 -> 5)
> [FAIL] Spawned enemy entity found in world.entities — expected: true, got: false
> ```
> 
> **关键观察：** entity count 从 2 增长到 5，证明 `ECS.world.add_entity(new_entity)` 在 `s_enemy_spawn.gd:85` 确实执行了。问题不在 spawn 逻辑，而在测试中查找 spawned enemy 的方式。
> 
> ## 你的任务
> 
> 1. **阅读 `tests/integration/flow/test_flow_enemy_spawn_scene.gd`**，理解 Test 1 (`test_spawner_spawns_enemy_into_world`) 中如何查找 spawned enemy
> 2. **检查 `_find_enemy_without_name()` 和 `_find()` 的实现**，确认查找条件是否与实际 spawn 出来的 entity 属性匹配
> 3. **检查 `s_enemy_spawn.gd` 的 `_spawn_wave()` 方法**，确认 spawn 出来的 entity 的 name 是什么、有哪些组件
> 4. **在 worktree 中运行测试**（如有 .godot 缓存）或通过代码分析定位根因
> 5. **推送修复后确认 CI 通过**
> 
> ## 已知线索
> 
> - `ECS.world.add_entity()` deep-copies components（GECS v6），spawn 出来的 entity 的引用可能与原始 entity 不同
> - entity count 增加了 3 个（2→5），说明 spawner recipe 中的所有 entity 都被正确 spawn 了
> - 上次修复添加了额外帧等待和 `_find()` 查找，但问题仍然存在，说明**不是时序问题**
> - 重点排查：entity name 不匹配、`_find()` / `_find_enemy_without_name()` 的过滤条件过于严格、或 deep-copy 导致 entity 属性丢失
> 
> ## 注意事项
> 
> - **不要修改 `s_enemy_spawn.gd` 的核心 spawn 逻辑**（已验证正确）
> - 只修改测试文件 `test_flow_enemy_spawn_scene.gd` 中的查找/断言逻辑
> - 这是最后一次迭代机会，请确保修复的确定性
