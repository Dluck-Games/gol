# Component Blueprint System Design (组件设计图机制)

**Date:** 2026-03-27
**Issue:** [#109](https://github.com/Dluck-Games/god-of-lego/issues/109)
**Status:** Approved

## Overview

组件设计图是类似科技树的解锁机制。玩家通过探索获取设计图（怪物掉落、地图刷新），在营地的组合专家 NPC 处消耗设计图解锁组件制作权限，并通过组件点数进行制作和移除。

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| 蓝图物品表达 | CBlueprint 组件 + 复用 Pickup 系统 | 和现有 Box 拾取流程一致 |
| 玩家数据存储 | PlayerData 全局数据类（和 GameState 同级） | 持久化归数据类，Service 是会话逻辑 |
| 类型引用方式 | Script 对象引用 | 类型安全，和 GECS 查询模式一致 |
| NPC 交互方式 | 最小对话系统（B-lite） | ~200-250 行，为未来对话系统打基础 |
| 组件点数汇率 | 有损兑换（移除得 1 点，制作花 2 点） | 形成资源压力，后续可调 |
| 组合专家逻辑 | Utils 静态函数，无事件驱动系统 | 遵循 ECS 轮询理念 |
| 蓝图对应范围 | 4 种 losable components | CWeapon, CTracker, CHealer, CPoison |
| NPC 生成方式 | recipe + GOLWorld VILLAGE POI 生成 | 和现有 guards 生成逻辑一致 |

## Data Layer

### PlayerData (Global Data Class)

和 GameState 同级的全局数据类，管理玩家进度数据。

```gdscript
class_name PlayerData

var unlocked_blueprints: Array[Script] = []   # [CWeapon, CHealer, ...]
var component_points: int = 0

signal blueprint_unlocked(component_type: Script)
signal points_changed(new_value: int)
```

- Initial state: no unlocked blueprints, 0 points
- Lifecycle matches GameState — instantiated in `GOL.setup()` as `GOL.Player = PlayerData.new()`
- Accessed globally via `GOL.Player`, passed as parameter to utils functions
- Future save/load serializes alongside GameState
- Signals (`blueprint_unlocked`, `points_changed`) are for MVVM ViewModel binding only — no system logic subscribes to them

### CBlueprint (ECS Component)

```gdscript
class_name CBlueprint extends Component

var component_type: Script    # e.g., CWeapon, CHealer
```

Attached to blueprint entities. Blueprint entities also carry CContainer (empty — no `stored_recipe_id` or `stored_components`), CSprite, CTransform, CCollision. The CContainer is present solely to enter the SPickup detection flow; the early-exit branch in SPickup (see below) prevents the normal `_open_box()` path from running.

### CDialogue (ECS Component)

```gdscript
class_name CDialogue extends Component

var npc_name: String
var entries: Array[DialogueEntry]
```

```gdscript
class_name DialogueEntry

var text: String
var options: Array[DialogueOption]
```

```gdscript
class_name DialogueOption

enum DialogueAction { CRAFT, DISMANTLE, CLOSE }

var label: String
var action: DialogueAction
```

Single-layer structure, no branching dialogue trees. `DialogueAction` enum ensures type safety (no string matching).

## System Layer

### SDialogue (Dialogue System)

```
Group: gameplay
Query: [CDialogue, CTransform]
Interaction range: Config.DIALOGUE_RANGE (default 64.0 pixels)
```

- Polls distance between player and CDialogue entities each frame
- Shows interaction hint when within `Config.DIALOGUE_RANGE`
- Opens DialogueUI on interact key press
- Dialogue option callbacks invoke composer_utils functions for CRAFT/DISMANTLE
- Note: NPC entity has CDialogue but no CPickup/CContainer, so SPickup will not interfere with it

### SPickup Modification

Add an early-exit branch in SPickup's `_process_entity()`, after the entity/container check but **before** `_open_box()`:
1. Check `entity.has(CBlueprint)`
2. If true → call `composer_utils.unlock_blueprint(entity.get(CBlueprint).component_type, GOL.Player)`
3. Destroy the blueprint entity
4. `return` to skip the normal `_open_box()` path (which would error on empty CContainer)

### composer_utils.gd (Static Utility Functions, at `scripts/utils/composer_utils.gd`)

```gdscript
static func unlock_blueprint(component_type: Script, player_data: PlayerData) -> bool
    # Check if already unlocked, write to unlocked_blueprints

static func craft_component(entity: Entity, component_type: Script, player_data: PlayerData) -> bool
    # Check: unlocked? points >= 2? not at CAP?
    # Pass → deduct 2 points, instantiate via component_type.new() (default constructor values), add to entity

static func dismantle_component(entity: Entity, component_type: Script, player_data: PlayerData) -> bool
    # Lookup: entity.get(component_type) to get live component instance
    # Remove losable component from entity, +1 point
```

Call chain:
```
SPickup detects pickup → finds CBlueprint → composer_utils.unlock_blueprint()
SDialogue option callback → "craft" → composer_utils.craft_component()
SDialogue option callback → "dismantle" → composer_utils.dismantle_component()
```

## UI Layer (MVVM)

### DialogueUI

```
ViewModelDialogue
  is_open: ObservableProperty
  npc_name: ObservableProperty
  current_text: ObservableProperty
  options: ObservableProperty
  func select_option(action: DialogueOption.DialogueAction)

ViewDialogue (Panel)
  NPC name label
  Text area
  Dynamic option buttons
```

### ComposerUI

```
ViewModelComposer
  mode: ObservableProperty           # "craft" or "dismantle"
  available_blueprints: ObservableProperty
  player_components: ObservableProperty
  component_points: ObservableProperty
  func execute(component_type: Script)

ViewComposer (Panel)
  Mode title ("制作组件" / "移除组件")
  Points display
  Component list (name + action button per item)
  Back button → return to DialogueUI
```

### Interaction Flow

```
Player approaches NPC → interaction hint appears
Press interact → DialogueUI opens ("需要什么帮助？" + 3 options)
Select "制作组件" → ComposerUI (craft mode)
Select "移除组件" → ComposerUI (dismantle mode)
Select "离开" → close dialogue
ComposerUI back → return to DialogueUI
```

## Entity & Recipe Layer

### Blueprint Recipes (4 types)

```
blueprint_weapon.tres    → CBlueprint(component_type=CWeapon), CContainer, CSprite, CTransform, CCollision, CLifeTime(120s)
blueprint_tracker.tres   → CBlueprint(component_type=CTracker), CContainer, CSprite, CTransform, CCollision, CLifeTime(120s)
blueprint_healer.tres    → CBlueprint(component_type=CHealer), CContainer, CSprite, CTransform, CCollision, CLifeTime(120s)
blueprint_poison.tres    → CBlueprint(component_type=CPoison), CContainer, CSprite, CTransform, CCollision, CLifeTime(120s)
```

### Composer NPC Recipe

```
npc_composer.tres
  CTransform, CSprite, CCollision
  CCamp(PLAYER)
  CDialogue(
    npc_name: "组合专家",
    entries: [DialogueEntry(
      text: "需要什么帮助？",
      options: [
        { label: "制作组件", action: CRAFT },
        { label: "移除组件", action: DISMANTLE },
        { label: "离开", action: CLOSE }
      ]
    )]
  )
```

### Spawn Logic

- **Map blueprints:** GOLWorld places 1-2 random blueprint Boxes at BUILDING POI positions (alongside existing loot boxes)
- **Monster drops:** SDamage._on_no_hp(), after the existing component-loss block and before `_start_death()`, adds a 10% chance to drop a random blueprint Box. Applies to all enemies with `CCamp.ENEMY`. Drop probability and eligible enemy types are configurable in Config constants (`BLUEPRINT_DROP_CHANCE = 0.1`)
- **Composer NPC:** GOLWorld spawns one `npc_composer` at VILLAGE POI (alongside guards)

## Testing

### Unit Tests

```
tests/unit/test_composer_utils.gd
  test_unlock_blueprint_success
  test_unlock_blueprint_already_unlocked
  test_craft_component_success
  test_craft_component_not_unlocked
  test_craft_component_insufficient_points
  test_craft_component_at_cap
  test_dismantle_component_success
  test_dismantle_component_not_losable

tests/unit/test_blueprint_pickup.gd
  test_pickup_blueprint_unlocks
  test_pickup_blueprint_already_unlocked
  test_pickup_blueprint_destroys_entity
```

### Integration Test (SceneConfig)

```
tests/integration/flow/test_flow_composer_scene.gd
  Scene: player + composer NPC + blueprint Boxes
  test_full_blueprint_to_craft_flow
    Player entity spawned with at least one losable component pre-equipped (e.g., CWeapon)
    pickup blueprint → walk to NPC → dismantle existing component for points → craft new component
  test_dialogue_interaction
    approach NPC → open dialogue → select option → verify UI state
```

### Main Game Integration

Full gameplay loop in GOLWorld: explore to find blueprints → return to camp → talk to composer NPC → unlock and craft → manage components.

## Dependencies

| Dependency | Status | Resolution |
|------------|--------|------------|
| Dialogue system | Missing | Minimal B-lite implementation (~200-250 lines) |
| Composer NPC | Missing | New recipe + spawn logic |
| PlayerData | Missing | New global data class |
| Existing SPickup | Exists | Small modification to detect CBlueprint |
| Existing SDamage | Exists | Small extension for blueprint drops |
| Existing GOLWorld | Exists | Add NPC + blueprint spawn logic |

## Workflow Notes

- Use git worktree for implementation (isolate from current workspace)
- Update Issue #109 description to match this design
- Close stale PR #117
- New PR on completion, closing #109
