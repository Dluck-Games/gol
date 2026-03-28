# Orchestration — Issue #194

## Issue
**Title:** 游戏正常退出后日志报错：gecs/ecs/world.gd remove_entity 报错
**Labels:** bug, topic:framework, foreman:assign
**Body:**
**Bug 描述：**
游戏正常退出时，控制台输出 GDScript 报错。

**实际行为：**
退出时日志报错：
```text
SCRIPT ERROR: Invalid type in function 'remove_entity' in base 'Node (GOLWorld)'. The Object-derived class of argument 1 (previously freed) is not a subclass of the expected argument class.
 at: GOLWorld.purge (res://addons/gecs/ecs/world.gd:652)
 GDScript backtrace (most recent call first):
 [0] purge (res://addons/gecs/ecs/world.gd:652)
 [1] teardown (res://scripts/services/impl/service_scene.gd:14)
 [2] teardown (res://scripts/services/service_context.gd:85)
 [3] static_teardown (res://scripts/services/service_context.gd:63)
 [4] teardown (res://scripts/gol.gd:25)
 [5] _exit_tree (res://scripts/main.gd:12)
```

**可能原因：**
在执行 `teardown` 并调用 `GOLWorld.purge` 清理 ECS 实体时，传入了已经被释放（previously freed）的实体对象引用。导致尝试调用 `remove_entity` 时类型不匹配/引用失效。

**期望行为：**
游戏正常退出时，ECS 和所有服务能够安全、干净地 `teardown`，控制台无报错。

---

## Decision Log

### Decision 1 — 2026-03-28 12:25
**Trigger:** New issue assigned
**Assessment:** 新 bug issue，需要分析 teardown 流程中实体被提前释放的根因。调用栈清晰（world.gd:652 purge），但 `remove_entity` 内部已有 `is_instance_valid` 守卫，说明问题可能出在 GDScript 类型系统层面——freed 对象传入 typed 函数参数时在函数体执行前就报错。需要 planner 深入分析 teardown 顺序和实体生命周期。
**Action:** spawn @planner
**Model:** glm-5.0-turbo-ioa
**Guidance:** 分析 teardown 流程中实体被提前释放的根因，制定修复方案和测试契约
**TL Context for Planner:**
> **Bug 概述：** 游戏正常退出时 `GOLWorld.purge()` 报错 "previously freed" entity。
>
> **关键调用栈：** `main._exit_tree` → `GOL.teardown` → `ServiceContext.static_teardown` → `Service_Scene.teardown` → `world.purge()` → `remove_entity(entity)` 报错
>
> **需要重点分析的内容：**
>
> 1. **Teardown 顺序问题：** `ServiceContext.teardown()` 按 setup 逆序 teardown 所有服务（pcg → input → console → recipe → savedata → ui → scene）。检查其他服务在 teardown 时是否会导致某些 entity 节点被 `queue_free()` 或 `free()`，使得 `Service_Scene.teardown()` 调用 `purge()` 时实体已失效。
>
> 2. **`purge()` 中的 `is_instance_valid` 失效：** `remove_entity` 在 `world.gd:394` 有 `is_instance_valid` 守卫，但错误发生在 `world.gd:652`（调用点），说明 GDScript 在将 freed 对象传入 typed 参数 `entity: Entity` 时，在函数体执行前就抛出了类型错误。这是一个 Godot 引擎层面的行为——typed 参数会在调用时做类型检查，freed 对象无法通过。
>
> 3. **Entity 引用来源：** 检查 `entities` 数组中的 entity 节点是否可能因为 Godot 场景树的 `notification(NOTIFICATION_UNPARENTED)` 或其他机制被自动释放。
>
> 4. **`queue_free` vs `free` 的时序：** 如果某处对 entity 调用了 `queue_free()`，在同一个 frame 内该对象仍然存在但标记为待删除，`is_instance_valid` 返回 true，但 GDScript 的类型检查可能已将其视为 invalid。
>
> **需要阅读的文件：**
> - `addons/gecs/ecs/world.gd` — `purge()` (L648) 和 `remove_entity()` (L393)
> - `scripts/services/impl/service_scene.gd` — teardown 和 _unload
> - `scripts/services/service_context.gd` — teardown 顺序
> - `scripts/gol.gd` — teardown 入口
> - `scripts/main.gd` — _exit_tree
> - `scripts/gameplay/ecs/gol_world.gd` — GOLWorld 是否覆写了 purge 或有额外清理
> - 检查其他所有 ServiceBase 子类的 teardown 是否会释放 entity 相关节点
>
> **修复方案方向（供参考，需验证）：**
> - 方案 A：在 `purge()` 调用 `remove_entity` 前加 `is_instance_valid` 过滤
> - 方案 B：调整 teardown 顺序，确保 scene service 先 teardown
> - 方案 C：`remove_entity` 改为 untyped 参数避免提前类型检查
>
> **测试契约要求：**
> - 验证正常退出流程无报错
> - 验证 purge 仍能正确清理所有有效实体
> - 验证部分实体已被释放时 purge 不会崩溃
> - 如涉及 teardown 顺序变更，需验证所有 service 的 setup/teardown 对称性

### Decision 2 — 2026-03-28 12:32
**Trigger:** @planner completed (01-planner-entity-purge-freed-ref.md)
**Assessment:** Plan 质量充分。根因分析准确——GDScript typed 参数在函数体执行前做类型检查，`is_instance_valid` 守卫无法生效。双层防御方案最小改动且治本：purge filter 加 `is_instance_valid` + remove_entity 去掉类型标注。测试契约完整，正确选择了 SceneConfig 集成测试而非违反 AGENTS.md 的 unit test 方案。
**Action:** spawn @coder
**Model:** glm-5.0-turbo-ioa
**Guidance:** 实现双层防御修复，编写集成测试和 E2E 测试
**TL Context for Coder:**
> **修改范围：仅 `addons/gecs/ecs/world.gd`，2 处改动**
>
> **改动 1 — `world.gd:651` purge() filter 加防御：**
> ```
> # 修改前
> for entity in entities.duplicate().filter(func(x): return not keep.has(x)):
> # 修改后
> for entity in entities.duplicate().filter(func(x): return not keep.has(x) and is_instance_valid(x)):
> ```
>
> **改动 2 — `world.gd:393` remove_entity 去掉参数类型标注：**
> ```
> # 修改前
> func remove_entity(entity: Entity) -> void:
> # 修改后
> func remove_entity(entity) -> void:
> ```
> 注意：函数体内已有 `entity = entity as Entity`（world.gd:396），去掉类型标注后安全性不变。
>
> **不要改动的文件：**
> - 不要修改 `remove_entities()`（它内部调用 `remove_entity`，自动受益）
> - 不要修改 `add_entity()` 的 ID 碰撞处理（同理自动受益）
> - 不要修改 teardown 顺序或 `service_scene.gd`
>
> **测试要求：**
> 1. **集成测试**：在 `tests/integration/` 创建 `test_teardown_cleanup.gd`（extends SceneConfig），创建 GOLWorld → 注册实体 → 手动 free 一个实体 → 调用 purge() → 验证无报错且有效实体被清理
> 2. **E2E 测试**：启动游戏 → 正常退出 → 确认控制台无 SCRIPT ERROR
>
> **注意事项：**
> - `tests/AGENTS.md` 禁止在 unit tests 中创建 World，所以 purge/remove_entity 的测试必须走集成测试（SceneConfig）路径
> - E2E 测试使用 kimi-k2.5-ioa 模型运行

### Decision 3 — 2026-03-28 12:41
**Trigger:** @coder completed (03-coder-fix-purge-freed-entity.md), doc_validation_failed — 缺少中文标准段落标题
**Assessment:** 代码实现和测试内容完整正确（2 处 world.gd 改动、集成测试已通过 3/3、PR #211 已创建），但 handoff 文档使用了英文标题（"Completed Work"、"Test Contract Coverage"、"Decision Records"、"Repository State"、"Incomplete Items"），不符合框架要求的中文标准段落格式（## 完成的工作、## 测试契约覆盖、## 决策记录、## 仓库状态、## 未完成事项）。这是文档格式问题，代码本身无需修改，内部迭代 1 次远低于上限。
**Action:** spawn @coder
**Model:** glm-5.0-turbo-ioa
**Guidance:** 仅修复 handoff 文档格式，不改动任何代码
**TL Context for Coder:**
> **你的任务：仅重写 `03-coder-fix-purge-freed-entity.md` 的段落标题和格式，不修改任何代码文件。**
>
> **当前问题：** 文档使用了英文标题，框架验证要求以下中文标准段落：
> - `## 完成的工作` — 替换 "## Completed Work"
> - `## 测试契约覆盖` — 替换 "## Test Contract Coverage"
> - `## 决策记录` — 替换 "## Decision Records"
> - `## 仓库状态` — 替换 "## Repository State"
> - `## 未完成事项` — 替换 "## Incomplete Items"
>
> **规则：**
> - 只改文档标题，内容保持不变（可以翻译小标题但保留所有数据和表格）
> - 不要修改 `world.gd`、`test_teardown_cleanup.gd` 或任何代码文件
> - 不要重新运行测试
> - 不要创建新 PR
> - 不要 push
> - 仓库状态信息不变：branch `foreman/issue-194-gecsecsworldgd-removeentity`，commit `b2ef1ab`，PR #211 OPEN

### Decision 4 — 2026-03-28 12:50
**Trigger:** @coder completed (05-coder-accept-freed-entity-fix.md), doc_validation_failed — 仍然使用英文标准段落标题
**Assessment:** Coder 在 Decision 3 中已被明确指示使用中文标题并提供了逐行映射表，但产出的 `05-coder-accept-freed-entity-fix.md` 仍然使用英文标题（"Completed Work"、"Test Contract Coverage" 等）。这是连续第 2 次在同一文档格式要求上失败。代码本身已完成且正确（PR #211 OPEN，集成测试 3/3 通过），问题纯粹是 handoff 文档格式。Coder 内部迭代将达第 3 次（Decision 2=第1次，Decision 3=第2次，本次=第3次），仍在上限内（>3 才 abandon）。给予最后一次机会，使用极明确的指令。
**Action:** spawn @coder
**Model:** glm-5.0-turbo-ioa
**Guidance:** 最后一次修复文档格式，提供完整的文件模板
**TL Context for Coder:**
> **这是你第 3 次被要求修复文档格式，必须严格使用中文标题。如果再失败，任务将被放弃。**
>
> **你的任务：重写 `05-coder-accept-freed-entity-fix.md`，使用以下精确格式。不要改动任何代码文件。**
>
> **文档必须以以下结构开头（直接复制使用）：**
>
> ```markdown
> # Handoff: Issue #194 — Accept freed entity fix
>
> ## 完成的工作
>
> [此处放原有内容，小标题可保留英文但必须翻译为中文：如 "Verified files (no changes needed)" → "已验证文件（无需更改）"]
>
> ## 测试契约覆盖
>
> [此处放原有表格内容]
>
> ## 决策记录
>
> [此处放原有内容]
>
> ## 仓库状态
>
> [此处放原有内容]
>
> ## 未完成事项
>
> [此处放原有内容]
> ```
>
> **关键规则（不可违反）：**
> 1. 二级标题 `##` 必须且只能使用这 5 个中文标题：`## 完成的工作`、`## 测试契约覆盖`、`## 决策记录`、`## 仓库状态`、`## 未完成事项`
> 2. 文档中不得出现 `## Completed Work`、`## Test Contract Coverage`、`## Decision Records`、`## Repository State`、`## Incomplete Items` 这 5 个英文标题中的任何一个
> 3. 不修改任何代码文件
> 4. 不运行测试、不 push、不创建 PR
> 5. 仓库状态不变：branch `foreman/issue-194-gecsecsworldgd-removeentity`，commit `b2ef1ab`，PR #211 OPEN
