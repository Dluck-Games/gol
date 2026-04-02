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

### Decision 2 — 2026-03-29 17:18
**Trigger:** @coder completed (07-coder-fix-redundant-add-entity.md), CI passed
**Assessment:** 第 3 次内部迭代。Coder 识别到根因：commit `41c83c2` 添加的 `ECS.world.add_entity(new_entity)` 是冗余调用——`create_entity_by_id()` 内部的 `_instantiate_entity()` 已经调用了 `add_entity()`，重复调用触发 ID collision handling 导致实体被 `remove_entity()` 释放后重新添加，实体状态损坏。Coder 从 `s_enemy_spawn.gd:85` 和 `s_damage.gd:335` 移除了冗余的 `add_entity()` 调用（commit `c334b0c`）。CI 全部通过（Unit Tests + Integration Tests，run 23705877373）。修改范围收敛为 2 files changed, 3 deletions(-)，符合最小改动原则。需要 reviewer 审查确认移除的正确性以及测试覆盖是否充分。
**Action:** spawn @reviewer
**Model:** glm-5.0-turbo-ioa
**Guidance:** 审查冗余 add_entity 移除的正确性，验证测试覆盖
**TL Context for Reviewer:**
> ## 变更概述
> 
> Coder 在第 3 次迭代中识别到根因：之前修复添加的 `ECS.world.add_entity(new_entity)` 是冗余的。
> 
> **修改文件：**
> - `scripts/systems/s_enemy_spawn.gd` — 移除 `_spawn_wave()` 中冗余的 `ECS.world.add_entity(new_entity)`
> - `scripts/systems/s_damage.gd` — 移除 `_spawner_death_burst()` 中冗余的 `ECS.world.add_entity(new_entity)`
> 
> **根因分析：**
> `ServiceContext.recipe().create_entity_by_id()` → `_instantiate_entity()` (`service_recipe.gd:130`) 内部已调用 `ECS.world.add_entity(entity)`。重复调用触发 GECS 的 ID collision handling（`world.gd:296-304`），导致实体被 `remove_entity()` 释放后重新添加，实体状态损坏。
> 
> **CI 状态：** Unit Tests ✓, Integration Tests ✓ (run 23705877373)
> 
> ## 审查重点
> 
> 1. **确认 `create_entity_by_id()` 确实内部调用了 `add_entity()`** — 阅读 `service_recipe.gd` 的 `_instantiate_entity()` 方法
> 2. **确认移除后不会遗漏其他调用路径** — 检查是否有其他地方调用 `create_entity_by_id()` 后又手动 `add_entity()`
> 3. **确认 `s_damage.gd` 的 `_spawner_death_burst()` 有相同的模式** — 验证移除是合理的
> 4. **评估测试覆盖** — 当前 Test 1 验证 spawner spawn + entity 在 world 中，Test 3 验证 poison enemy + area effect。E2E（AI Debug Bridge 运行时验证）未覆盖。
> 
> **PR:** https://github.com/Dluck-Games/god-of-lego/pull/219
> **Branch:** `foreman/issue-196`
> **Commit:** `c334b0c`

### Decision 3 — 2026-03-29 17:35
**Trigger:** @reviewer completed (08-reviewer-zerodiff-no-code-change.md)
**Assessment:** Reviewer 结论为 `verified`，但审查发现了重要事实：PR 最终生产代码 diff 为零——`main` 和 `HEAD` 的 `s_enemy_spawn.gd`、`s_damage.gd` 完全相同。Planner 的根因分析（"缺少 `add_entity` 调用"）是错误的，`create_entity_by_id()` 内部的 `_instantiate_entity()` 在 `service_recipe.gd:130` 已调用 `ECS.world.add_entity()`。经过 3 轮内部迭代（05→06→07），最终净效果为添加了 2 个测试文件（8 unit + 9 integration assertions），验证了 spawner 系统行为和 `enemy_poison` recipe 组件结构。测试有价值，CI 全部通过。Review 同时发现了 `gol_game_state.gd:74` 存在同类双重 `add_entity` bug（Critical，在 main 分支上），应在后续 Issue 中处理。Issue #196 描述的"毒药和范围化组件在地图上不刷新"现象的真实根因未在本 PR 中解决，需要重新调查（可能涉及 PCG POI 配置、recipe 加载或 spawn condition）。已达到 3 次内部迭代上限，PR 测试代码质量确认合格，终止本流程。
**Action:** verify
**Model:** glm-5.0-turbo-ioa
**Guidance:** PR 测试代码通过审查，但 Issue 根因未解决

**GitHub Comment:**
#196 调查结论：原始 bug 根因不在 `s_enemy_spawn.gd`，planner 的分析有误。

**本 PR 交付内容：**
- 新增集成测试 `test_flow_enemy_spawn_scene.gd`（验证 spawner 系统行为 + enemy_poison recipe 组件结构）
- 修改单元测试 `test_spawner_system.gd`（覆盖 max_spawn_count 计算和 cleanup 逻辑）
- CI 全部通过（Unit ✓ + Integration ✓）

**关键发现：**
- `create_entity_by_id()` 内部的 `_instantiate_entity()` 已调用 `ECS.world.add_entity()`，不存在"缺少 add_entity"的问题
- PR 最终生产代码 diff 为零（3 次迭代的净效果 = 添加测试）
- `enemy_poison` recipe 包含完整的 CPoison + CAreaEffect 组件（13 个组件），recipe 层面无问题

**Issue #196 真实根因需要重新调查**，可能方向：
1. PCG POI 配置未正确放置 enemy_poison spawner
2. Spawn condition（camp、距离等）未满足导致不触发
3. Recipe 加载或组件初始化时序问题

**额外发现（需后续处理）：**
- `gol_game_state.gd:74` 存在双重 `add_entity` bug（Critical），会导致玩家重生时 use-after-free
- 建议为 GECS `add_entity` 添加防重入 guard
