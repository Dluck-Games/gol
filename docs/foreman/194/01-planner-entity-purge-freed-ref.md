# Issue #194 — Entity purge freed reference analysis

## 需求分析

### Issue 要求
游戏正常退出时，`GOLWorld.purge()` 调用 `remove_entity()` 时报错，因为 `entities` 数组中存在已被释放（previously freed）的实体引用。

### 用户期望行为
游戏正常退出时，ECS 和所有服务能够安全、干净地 teardown，控制台无报错。

### 边界条件
- 正常游戏退出（`_exit_tree` → `GOL.teardown()`）
- 场景切换（`_unload()` 也调用 `purge()`）
- 部分实体已被外部逻辑释放时调用 `purge()`

## 影响面分析

### 受影响的文件/函数

| 文件 | 函数/位置 | 角色 |
|------|-----------|------|
| `addons/gecs/ecs/world.gd:651` | `purge()` 实体迭代循环 | **报错触发点** |
| `addons/gecs/ecs/world.gd:393` | `remove_entity(entity: Entity)` | **typed 参数导致 freed 对象无法传入** |
| `scripts/services/impl/service_scene.gd:14` | `teardown()` 调用 `world.purge()` | 调用方 |
| `scripts/services/impl/service_scene.gd:76` | `_unload()` 调用 `old_world.purge()` | 另一调用方 |
| `scripts/services/service_context.gd:78-90` | `teardown()` 服务逆序清理 | teardown 编排 |
| `scripts/gol.gd:24-27` | `teardown()` | teardown 入口 |
| `scripts/main.gd:11-12` | `_exit_tree()` | 最外层触发 |

### 调用链追踪

```
main.gd:12  _exit_tree()
  → gol.gd:25  teardown()
    → service_context.gd:63  static_teardown()
      → service_context.gd:85  service.teardown()  (逆序: pcg→input→console→recipe→savedata→scene→ui)
        → service_scene.gd:10  _pop_ui_layers()
        → service_scene.gd:14  world.purge()
          → world.gd:651  for entity in entities.duplicate().filter(...)
            → world.gd:652  remove_entity(entity)  ← 💥 ERROR: entity is previously freed
```

### 根因分析

**GDScript typed 参数在函数体执行前进行类型检查。**

`remove_entity` 的签名是 `func remove_entity(entity: Entity)`（`world.gd:393`）。当传入一个已被释放的对象引用时，GDScript 引擎在将参数绑定到 `entity: Entity` 类型时就会抛出运行时错误：

```
Invalid type in function 'remove_entity'. The Object-derived class of argument 1 (previously freed)
is not a subclass of the expected argument class.
```

函数体内的 `is_instance_valid(entity)` 守卫（`world.gd:394`）**永远不会被执行到**，因为类型检查在函数体之前就失败了。

**实体为何被提前释放：**

`purge()` 内部遍历 `entities.duplicate()` 的快照（`world.gd:651`），对每个实体调用 `remove_entity()`。`remove_entity()` 内部根据实体是否在场景树中决定释放方式（`world.gd:441-444`）：
- 在树中 → `entity.queue_free()`（延迟释放）
- 不在树中 → `entity.free()`（立即释放）

当实体不在场景树中时，`entity.free()` 会**立即**释放对象。如果同一个快照中存在对该已释放实体的引用（例如，快照创建后有另一个路径释放了实体），后续迭代就会触发类型检查错误。

此外，`purge()` 的系统清理阶段（`world.gd:670-672`）调用 `remove_system()` → `system.queue_free()`，以及最后的 `self.queue_free()`（`world.gd:683`），在帧末清理时可能导致子节点（实体）被 Godot 场景树级联释放。

### 受影响的实体/组件类型
所有注册在 `world.entities` 数组中的实体，包括：玩家、NPC、敌人、建筑、战利品箱等。

### 潜在的副作用
- 当前 `purge()` 中止执行，后续的系统清理、observer 清理可能不完整
- 如果 `purge()` 被调用时 `should_free = true`（默认），`self.queue_free()` 不会被调用（因为函数提前报错），World 节点可能泄漏
- `service_scene.gd:17` 的 `world.queue_free()` 仍会执行，提供兜底清理

## 实现方案

### 推荐方案：双层防御

**第一层（治本）：修改 `purge()` 中的过滤条件**

在 `world.gd:651` 的 filter 中增加 `is_instance_valid(x)` 检查：

```gdscript
# world.gd:651 (修改前)
for entity in entities.duplicate().filter(func(x): return not keep.has(x)):

# world.gd:651 (修改后)
for entity in entities.duplicate().filter(func(x): return not keep.has(x) and is_instance_valid(x)):
```

**第二层（防御）：修改 `remove_entity()` 参数类型**

将 `remove_entity` 的参数改为 untyped，让 `is_instance_valid` 守卫生效：

```gdscript
# world.gd:393 (修改前)
func remove_entity(entity: Entity) -> void:
    if not is_instance_valid(entity):
        return
    entity = entity as Entity

# world.gd:393 (修改后)
func remove_entity(entity) -> void:
    if not is_instance_valid(entity):
        return
    entity = entity as Entity
```

**理由：**
- 第一层修复了 `purge()` 的直接报错点，最小改动
- 第二层让 `remove_entity()` 对所有调用者（不仅仅是 `purge()`）都安全，防止未来类似问题
- `remove_entities()`（`world.gd:454`）内部循环调用 `remove_entity()`，同样受益于第二层修复
- `add_entity()` 中 ID 碰撞时也会调用 `remove_entity()`（`world.gd:304`），也需要防御

### 具体的代码修改位置

| 文件 | 行号 | 修改内容 |
|------|------|----------|
| `addons/gecs/ecs/world.gd` | 651 | filter 增加 `is_instance_valid(x)` 条件 |
| `addons/gecs/ecs/world.gd` | 393 | 移除 `entity: Entity` 的类型标注 |

### 新增/修改的文件列表
- **修改**: `addons/gecs/ecs/world.gd`（2 处改动）

### 实现步骤

1. 修改 `world.gd:651` — 在 `purge()` 的 filter 中添加 `is_instance_valid(x)` 条件
2. 修改 `world.gd:393` — 移除 `remove_entity` 参数的 `Entity` 类型标注
3. 编写单元测试验证 `purge()` 在存在 freed 实体时不会报错
4. 编写 E2E 测试验证正常退出无报错

## 架构约束

### 涉及的 AGENTS.md 文件
- `tests/AGENTS.md` — 测试层级和框架选择

### 引用的架构模式
- **ECS Component = pure data**: 本次修改不涉及新增 Component
- **Unit tests use GdUnitTestSuite**: 测试方案遵循此规则
- **Integration tests use SceneConfig**: 如果需要测试完整 teardown 流程

### 文件归属层级
- 修改的 `world.gd` 位于 `addons/gecs/ecs/` — 这是 GECS 插件代码，非 GOL 游戏代码

### 测试模式
- 单元测试使用 gdUnit4 `GdUnitTestSuite`（引用 `tests/AGENTS.md`）
- 集成测试使用 `SceneConfig`（引用 `tests/AGENTS.md`）
- E2E 测试使用 AI Debug Bridge（引用 `tests/AGENTS.md`）
- 注意：`tests/AGENTS.md` 明确规定 `tests/unit/` **禁止创建 World 或设置 ECS.world**

## 测试契约

- [ ] **Unit: purge 跳过 freed 实体** — 在 `tests/unit/` 中创建一个 mock World（不使用真实 World），手动向 `entities` 数组添加一个实体和一个已 free 的引用，调用 `purge()`，验证无报错且 `entities` 数组为空
- [ ] **Unit: remove_entity 安全处理 freed 参数** — 直接调用 `remove_entity()` 传入一个已 free 的对象，验证函数正常返回（不报错）
- [ ] **E2E: 正常退出无报错** — 使用 AI Debug Bridge 启动游戏后正常退出，检查控制台无 SCRIPT ERROR（运行时行为验证）

### 测试可行性说明

Unit 测试需要在没有真实 World 的情况下测试 `purge()` 和 `remove_entity()`。由于 `tests/AGENTS.md` 禁止在 unit tests 中创建 `World`，而 `purge()` 和 `remove_entity()` 是 `World` 的方法，有两种选择：

1. **集成测试（SceneConfig）**：创建包含实体的完整 GOLWorld，手动释放一个实体后调用 `purge()`，验证无报错
2. **单元测试**：直接实例化 `World`（通过 GDScript `World.new()`），绕过 SceneConfig 限制 — 但这违反 `tests/AGENTS.md` 硬规则

**推荐**：使用集成测试（SceneConfig）验证此修复，因为：
- 涉及 World 级别操作，属于集成测试范畴
- 需要 ECS.world 和真实场景树来测试 freed 实体场景
- E2E 测试验证完整的退出流程

## 风险点

### 低风险
- **移除类型标注**：`remove_entity(entity)` 去掉类型后，调用者传入非 Entity 类型时不会在参数绑定时报错，但函数内有 `entity = entity as Entity`（`world.gd:396`），会安全转换为 null 或正确类型。后续代码（如 `entity.components`）如果 entity 为 null 会触发不同的运行时错误，但这是合理的防御行为。

### 需要注意的代码
- `remove_entities()`（`world.gd:454-467`）内部循环调用 `remove_entity()`，修改类型标注后同样受益
- `add_entity()` 中的 ID 碰撞处理（`world.gd:304`）调用 `remove_entity()`，同样受益
- `purge()` 的 `should_free` 参数（默认 true）：`service_scene.gd` 两处调用 `purge()` 均使用默认值，之后又调用 `world.queue_free()`，形成双重 queue_free（无害但冗余）

### 性能/兼容性考量
- `is_instance_valid()` 在 GDScript 中是轻量级调用
- 移除类型标注对性能无影响（GDScript 本身是动态类型）

## 建议的实现步骤

1. **修改 `world.gd:651`** — 在 `purge()` 的 filter lambda 中添加 `and is_instance_valid(x)` 条件
2. **修改 `world.gd:393`** — 将 `func remove_entity(entity: Entity)` 改为 `func remove_entity(entity)`
3. **编写集成测试** — 在 `tests/integration/` 中创建 `test_teardown_cleanup.gd`（extends SceneConfig），验证 purge 在存在 freed 实体时正常执行
4. **E2E 验证** — 使用 AI Debug Bridge 启动游戏 → 正常退出 → 确认控制台无 SCRIPT ERROR
