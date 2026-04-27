# Building System Design (v1)

> Date: 2026-04-27
> Status: Draft
> Scope: Initial building system — ghost placement, NPC material delivery, construction, building activation

## Overview

RTS-style building flow: player places a **ghost** (white model) at a grid position, worker NPCs autonomously fetch materials from stockpile and deliver them to the site, then perform construction work. When complete, the ghost is replaced by the final building entity with collision and functional components activated.

### Design Principles

- **Buildings are entities** — a building is just an Entity with `CBuilding` marker + functional components (CCampfire, CCamp, etc.)
- **Separation of concerns** — EntityRecipe defines "what an entity is", BuildingTable defines "how to build it"
- **Reuse existing infrastructure** — CStockpile for resources, GOAP for NPC behavior, CCollision for physics, EntityRecipe for entity composition
- **No changes to addons/gecs** — all code in `scripts/`, scenes only hold node structure

## Architecture: Dual-Component Staged Approach

Ghost phase uses `CBuildSite` component on a temporary entity. On completion, the ghost entity is destroyed and a new building entity is created via EntityRecipe.

```
Ghost Entity = Entity + CTransform + CSprite(半透明) + CBuildSite
    ↓ materials delivered + construction complete
Destroy ghost → Create building = Entity + CTransform + CSprite + CCollision + CBuilding + functional components
```

Rationale:
- Ghost and building are fundamentally different entities — clean separation, no state residue
- CBuildSite and CBuilding each have single responsibility
- Systems query precisely: `query.with_all([CBuildSite])` vs `query.with_all([CBuilding])`
- Ghost doesn't carry functional components, avoiding premature activation

## Data Layer

### BuildingTable (`GOL.Tables.building()`)

Follows existing GOL.Tables pattern (LootTable, GrowthTable, HungerTable). A `BuildingTable` class with `const TABLES` dictionary + getter methods, registered in `GameTables`.

```gdscript
# scripts/gameplay/tables/building_table.gd
class_name BuildingTable
extends Resource

const TABLES: Dictionary = {
    "campfire": {
        display_name = "篝火",
        required_materials = {RWood: 5},
        build_duration = 3.0,
        entity_recipe_id = "campfire",
        ghost_texture = "res://assets/sprites/buildings/campfire.png",
    },
    "camp": {
        display_name = "营帐",
        required_materials = {RWood: 8, RStone: 3},
        build_duration = 5.0,
        entity_recipe_id = "camp",
        ghost_texture = "res://assets/sprites/buildings/camp.png",
    },
}

func get_building(building_id: String) -> Dictionary:
    return TABLES.get(building_id, {})

func all() -> Dictionary:
    return TABLES

func get_all_ids() -> Array:
    return TABLES.keys()
```

Access pattern: `GOL.Tables.building().get_building("campfire")`.

### CBuildSite Component (Ghost Runtime State)

```gdscript
# scripts/components/c_build_site.gd
class_name CBuildSite
extends Component

@export var building_id: String = ""             # key in BuildingTable
@export var required_materials: Dictionary = {}  # {Script → int} copied from table
@export var deposited_materials: Dictionary = {} # {Script → int} runtime tracking
@export var build_duration: float = 3.0          # copied from table
@export var build_progress: float = 0.0          # construction phase progress
@export var materials_complete: bool = false      # all materials delivered?

var progress_observable: ObservableProperty = ObservableProperty.new(0.0)
```

### CBuilding Component (Completed Building Marker)

```gdscript
# scripts/components/c_building.gd
class_name CBuilding
extends Component

@export var building_id: String = ""
```

Minimal marker. Future extensions (durability, upgrade level) add fields here.

### EntityRecipes

**Ghost (generic template):** `ghost_building.tres`
- Components: CTransform + CSprite + CBuildSite
- On spawn, SBuildOperation populates CBuildSite fields from BuildingTable and sets CSprite texture from building data

**Campfire:** `campfire.tres` (existing, modify to add CBuilding + CCollision)
- Components: CTransform + CSprite + CCampfire + CCollision + CBuilding

**Camp:** `camp.tres` (new)
- Components: CTransform + CSprite + CCamp + CCollision + CBuilding

## System Layer

### SBuildOperation — Player Building Interaction

Query: `[CPlayer, CTransform]`

State machine: `IDLE → MENU → PLACING`

**IDLE:**
- Press B → expand building quickbar (Don't Starve style — small bar expands into selection mode)
- Press interact near ghost → cancel ghost, deposited materials drop as pickup entities

**MENU:**
- Building quickbar expanded, shows available buildings with icons + names + material costs
- Select with 1/2 number keys or mouse → enter PLACING
- Press B again → collapse quickbar, return to IDLE
- ESC → collapse, return to IDLE

**PLACING:**
- Real-time ghost preview following cursor, snap-to-grid (TILE_SIZE = 32px)
- Valid position: green tint `Color(0.5, 1.0, 0.5, 0.4)`
- Invalid position (overlapping existing collision / out of bounds): red tint `Color(1.0, 0.5, 0.5, 0.4)`
- Confirm placement (left click / interact) → spawn ghost entity via ghost_building recipe, populate CBuildSite from BuildingTable
- ESC → cancel, return to IDLE

**Cancel ghost:**
- Player approaches ghost + presses interact → destroy ghost entity
- deposited_materials → spawn corresponding pickup entities at ghost position

### SBuildSiteComplete — Construction Completion Detection

Query: `[CBuildSite, CTransform]`

Per-frame check on all CBuildSite entities:
```
if site.materials_complete and site.build_progress >= site.build_duration:
    1. Get entity_recipe_id from BuildingTable via site.building_id
    2. ServiceContext.recipe().create_entity_by_id(recipe_id)
    3. Set new entity CTransform.position = ghost position
    4. Destroy ghost entity
```

Note: Material drop on ghost cancellation is handled by SBuildOperation (the system that processes the cancel input), not SBuildSiteComplete.

## GOAP Layer — NPC Construction Behavior

### Constraint: Worker NPCs Only

The build Goal is added **only** to worker NPC (`npc_worker`) `CGoapAgent.goals[]`. Other NPCs (rabbit, zombie, survivor) do not get this behavior.

### New World State Facts

| Fact | Meaning |
|------|---------|
| `has_build_target` | A nearby incomplete ghost has been identified |
| `reached_build_target` | NPC has arrived at the ghost position |
| `has_build_material` | NPC is carrying material needed by a ghost |
| `build_materials_delivered` | Materials have been delivered to the ghost |

### New GOAP Goal

**GoapGoal_Build** — Worker autonomously seeks construction tasks when ghosts exist nearby.

```
preconditions: { has_build_target: true }
desired_state: { build_materials_delivered: true }
priority: medium (below flee/eat, above wander)
```

### New GOAP Actions (4)

#### 1. GoapAction_FindBuildSite

Perceive nearby ghosts, select the nearest incomplete one.

```
preconditions: {}
effects: { has_build_target: true }
perform:
    Query CBuildSite entities → pick nearest
    → blackboard["build_target"] = entity
    → blackboard["needed_material"] = first missing material type
    → return true
```

#### 2. GoapAction_PickupBuildMaterial

Withdraw the required material from camp stockpile.

```
preconditions: { has_build_target: true, reached_stockpile: true }
effects: { has_build_material: true }
perform:
    Withdraw needed_material × 1 from camp_stockpile
    → CCarrying.resource_type = material
    → CCarrying.amount = 1
    → return true
```

Note: Reuses existing MoveTo-stockpile behavior. NPC walks to stockpile first, then picks up.

#### 3. GoapAction_DeliverBuildMaterial

Arrive at ghost position, deposit carried material into CBuildSite.

```
preconditions: { has_build_material: true, reached_build_target: true }
effects: { build_materials_delivered: true }
perform:
    site.deposited_materials[material] += carrying.amount
    Clear CCarrying
    Check if all materials met → site.materials_complete = true
    → return true
```

#### 4. GoapAction_ConstructBuilding

After all materials delivered, NPC stands near ghost and performs construction, advancing build_progress.

```
preconditions: { reached_build_target: true }
    + runtime check: site.materials_complete == true
effects: { build_materials_delivered: true }
perform:
    site.build_progress += delta
    if site.build_progress >= site.build_duration:
        return true  # SBuildSiteComplete handles replacement
    return false  # still constructing
```

### GOAP Plan Chain

GOAP plans are linear — each plan execution covers one trip. After completing a delivery, the plan resolves and NPC re-evaluates goals on the next tick. If the ghost still needs materials, `FindBuildSite` fires again and a new delivery plan is created.

```
Single delivery trip plan:
FindBuildSite → MoveTo(stockpile) → PickupBuildMaterial
    → MoveTo(build_target) → DeliverBuildMaterial

Construction plan (when materials_complete):
FindBuildSite → MoveTo(build_target) → ConstructBuilding
```

The NPC alternates between delivery plans and construction plans based on the ghost's current state. Multiple trips happen as multiple sequential plans, not a single looping plan.

**Multi-NPC parallel construction:**
- Multiple NPCs can target the same ghost simultaneously
- `DeliverBuildMaterial` deposits are atomic (GDScript single-threaded, no race conditions)
- `ConstructBuilding` progress is additive — multiple NPCs constructing simultaneously accelerates completion

## UI & Visuals

### Ghost Visual

- CSprite uses same texture as final building, with `modulate = Color(1, 1, 1, 0.5)` for translucency
- Material progress display above ghost (e.g., "Wood: 3/5  Stone: 0/3")
- Progress bar showing `sum(deposited) / sum(required)` percentage

### Construction Phase Visual

- Ghost modulate transitions from 0.5 to 1.0 as build_progress advances
- Optional: NPC construction animation (hammer action) — can be deferred

### Placement Preview (PLACING state)

- Translucent preview following cursor
- Valid: green tint `Color(0.5, 1.0, 0.5, 0.4)`
- Invalid: red tint `Color(1.0, 0.5, 0.5, 0.4)`
- Snap-to-grid: aligned to `TILE_SIZE (32px)` grid

### Building Quickbar (Don't Starve style)

- Default: small compact bar at bottom of HUD
- Press B → bar expands into selection mode showing building options
- Each option: icon + name + material cost
- Select with number keys or mouse → enter PLACING
- Press B again → collapse back to compact mode

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Placement overlaps existing collision | PLACING state detects collision, red preview, blocks placement |
| Stockpile lacks required materials | NPC PickupBuildMaterial fails → plan interrupts → idle → re-plans when materials available |
| Multiple ghosts simultaneously | FindBuildSite picks nearest; different NPCs may target different ghosts |
| Player cancels ghost while NPC en route | Ghost destroyed → NPC build plan invalidates (target gone) → re-plans on next tick → if NPC is carrying materials (`is_carrying=true`), existing Work goal's DepositResource action takes over → NPC returns materials to stockpile naturally. Zero new code needed. |
| Cancel ghost with deposited materials | Materials spawn as pickup entities at ghost position |
| NPC dies while carrying build materials | CCarrying resources drop via existing CLootDrop mechanism |
| NPC gets hungry during construction | Hunger goal has higher priority → interrupts construction → eats → resumes |

## Scope — Explicitly Excluded from v1

- Building upgrades
- Building repair / durability
- Demolishing completed buildings
- Functional component logic (CCampfire cooking, CCamp shelter effect — these components exist but their Systems are future work)
- Advanced placement constraints (e.g., campfire not on water) — v1 only checks collision overlap
- Build priority (NPC choice of which ghost to build first)

## New Files

```
scripts/
├── components/
│   ├── c_build_site.gd              # Ghost component
│   └── c_building.gd                # Completed building marker
├── gameplay/
│   ├── tables/
│   │   └── building_table.gd        # Building data table (GOL.Tables.building())
│   └── goap/
│       ├── goals/
│       │   └── goap_goal_build.gd   # (+.tres) Build goal for worker NPCs
│       └── actions/
│           ├── goap_action_find_build_site.gd
│           ├── goap_action_pickup_build_material.gd
│           ├── goap_action_deliver_build_material.gd
│           └── goap_action_construct_building.gd
├── systems/
│   ├── s_build_operation.gd         # Player building interaction
│   └── s_build_site_complete.gd     # Construction completion detection
└── ui/
    └── (building quickbar view/viewmodel — follows existing UI patterns)

resources/
├── recipes/
│   ├── ghost_building.tres          # Generic ghost template recipe
│   ├── campfire.tres                # Modified: add CBuilding + CCollision
│   └── camp.tres                    # New: camp building recipe
└── goals/
    └── goap_goal_build.tres         # Build goal resource

scripts/gameplay/game_tables.gd      # Modified: add _building + building() accessor
```

## Modified Files

| File | Change |
|------|--------|
| `scripts/gameplay/game_tables.gd` | Add `_building: BuildingTable` + `building()` accessor |
| `resources/recipes/campfire.tres` | Add CBuilding + CCollision components |
| `resources/recipes/npc_worker.tres` | Add GoapGoal_Build to CGoapAgent.goals[] (priority ~15, below Work at 20) |
| `project.godot` or input map | Add "build_menu" input action (B key) |
