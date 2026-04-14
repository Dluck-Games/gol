# GOL 资源系统设计 (Resource System)

> **Date:** 2026-04-14
> **Status:** Approved
> **Issue:** TBD

## Overview

Design the general resource substrate for GOL. This prototype delivers one end-to-end slice (tree → worker → camp stockpile → HUD) on top of an architecture built to absorb four future consumers:

1. v0.3 build system (uses resources as build cost)
2. Survival loop (hunger, drink, fuel — consume resources over time)
3. Component craft economy (replaces current flat `component_points` with real resource costs)
4. Autonomous NPC job management (workers powered by GOAP)

The design replaces the ad-hoc `PlayerData.component_points` integer with a uniform **`CStockpile`** ECS component that all resource stores use — player pocket, camp storage cube, and future fuel tanks / food crates / ammo boxes. Resource types are identified by `Script` reference, mirroring the existing `CBlueprint.component_type: Script` pattern.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Resource storage primitive | `CStockpile` ECS component | Spatial stores need ECS identity (camp cube has position, HP, destructibility). Player pocket becomes just another entity with a stockpile — one API everywhere. |
| Resource type identification | `Script` reference to `R*` resource class | Matches existing `CBlueprint.component_type` pattern. Open-set extensibility without a central registry. Metadata co-located with the type via `const` fields. |
| `PlayerData.component_points` migration | Full deletion, replaced by `CStockpile` on player entity | User explicitly picked full migration. One source of truth; no dual-layer ambiguity. |
| Worker NPC implementation | GOAP (new goal + 4 new actions + 5 new facts) | Worker is the template for future NPC job autonomy (one of the four consumers). GOAP from day one. |
| Resource node representation | New `CResourceNode` component | Extensible to plants, carcasses, mines. Trees are one instance of a general concept. |
| Worker carry payload | Transient `CCarrying` component on worker | Simple, observable by other systems, GOAP-friendly. Added on chop, removed on deposit. |
| Stockpile granularity (prototype) | 1 camp cube holds all types | Minimum scope. API supports N stockpiles; multi-stockpile routing is a future spec. |
| Tree depletion | Infinite (never destroyed) in prototype | User explicitly scoped it out. `CResourceNode.infinite` flag present for future depletable nodes. |
| Kill-grants-points and composer-dissolve-grants-points | Deferred follow-up, not in the prototype itself | Prove wood flow end-to-end first. Both are 1–2 line additions against the new API. |
| Progress bar UI | Floating `Control` above worker, no sprite animation | User explicitly scoped "no animations". Owned by the GOAP action lifetime. |

## Architecture

```
┌─ Resource types (R*) ────────────────────────────────────┐
│   scripts/resources/r_*.gd                               │
│   RWood, RComponentPoint — const-only Resource classes,  │
│   carry display name / icon / max_stack                  │
└──────────────────────────────────────────────────────────┘
              ▲ referenced-by-Script
              │
┌─ ECS components ─────────────────────────────────────────┐
│   CStockpile     — storage: Dictionary[Script, int]      │
│                    lives on: player entity, camp cube,   │
│                    (future) fuel tanks, ammo boxes       │
│   CResourceNode  — yield source: trees today,            │
│                    (future) plants, carcasses, loot      │
│   CCarrying      — transient worker payload              │
│   CWorker        — tag marking a GOAP agent as a worker  │
└──────────────────────────────────────────────────────────┘
              ▲ read/written by
              │
┌─ Gameplay layer ─────────────────────────────────────────┐
│   Worker GOAP actions:                                   │
│     FindWorkTarget, MoveToResourceNode, GatherResource,  │
│     MoveToStockpile, DepositResource                     │
│   composer_utils — rewired to CStockpile on player       │
└──────────────────────────────────────────────────────────┘
              ▲ observed by
              │
┌─ UI layer ───────────────────────────────────────────────┐
│   ViewModelHud — rebinds component_points observable to  │
│                  player's CStockpile; adds wood counter  │
│                  bound to camp cube's CStockpile         │
│   ViewModelComposer — same rebinding                     │
└──────────────────────────────────────────────────────────┘
```

### What this layer is NOT (non-goals)

- **Not a consumption model.** No hunger, no building costs, no crafting cost change. Consumption lives in each future consumer's own spec.
- **Not a loot system.** `CResourceNode` is for gatherable nodes (trees, future plants/carcasses). Existing `CContainer` + `SPickup` loot box flow stays exactly as it is — a different channel.
- **Not a transport network.** Workers carry one load at a time. No logistics graphs.
- **Not multi-stockpile routing.** The prototype has 1 camp cube. The API supports N stockpiles but the worker picks the nearest one with capacity — no priority queues, no allocation rules.
- **Not depletable.** Trees are infinite for this prototype. The `infinite` flag is present so future specs can flip it.

### Coexistence with existing systems

| Existing system | Treatment | Reason |
|---|---|---|
| `PlayerData` | Kept; shrinks to progression only (`unlocked_blueprints`) | Separation of concerns: progression ≠ resources |
| `PlayerData.component_points` | **Deleted.** Replaced by `CStockpile` on the player entity | Full migration |
| `composer_utils.craft_component` / `dismantle_component` | Signatures change: take the player entity, operate on its `CStockpile` | Same semantics, new storage |
| `ViewModelHud.component_points` | Rebinds to the player entity's `CStockpile.changed_observable` | Observable moves, semantics stay |
| `CContainer` / `SPickup` | Untouched | Loot pickups stay on their own channel |
| `CBlueprint` / blueprint pickup branch | Untouched | Blueprint unlock flow is orthogonal |
| GOAP system | Extended with worker goal + 5 new actions + 5 new facts | Additive; no existing behavior changes |
| PCG pipeline | Extended with one step that scatters tree entities | Additive; existing POI placement untouched |
| `GOLWorld` spawn logic | Adds: 1 camp cube + 1 worker NPC at game start | Same pattern as existing guard/composer spawn |

## Resource Types

Each resource type is a small `Resource` subclass in `scripts/resources/`:

```gdscript
# scripts/resources/r_wood.gd
class_name RWood extends Resource

const DISPLAY_NAME: String = "木材"
const ICON_PATH: String = "res://assets/icons/resources/wood.png"
const MAX_STACK: int = 999
```

```gdscript
# scripts/resources/r_component_point.gd
class_name RComponentPoint extends Resource

const DISPLAY_NAME: String = "组件点"
const ICON_PATH: String = "res://assets/icons/resources/component_point.png"
const MAX_STACK: int = 9999
```

Rules:
- Constants only — type metadata is static and shared across all holdings of that type.
- No instances are ever constructed — the **class itself** is the "value" passed around. `CStockpile.add(RWood, 5)` passes `RWood` as a `Script`.
- Saved/loaded (when save lands) via `resource_script.resource_path`. Same complexity as the blueprint save path.

## Components

### CStockpile

```gdscript
class_name CStockpile extends Component

## Resource holdings: Script -> int
@export var contents: Dictionary = {}

## Optional per-type caps; empty dict means uncapped per type.
## Global per-type cap is also enforced via each R*.MAX_STACK constant.
@export var per_type_caps: Dictionary = {}

## Observable for UI binding. Emits the contents dict on change. Not serialized.
var changed_observable: ObservableProperty = ObservableProperty.new({})

func get_amount(resource_type: Script) -> int
func add(resource_type: Script, amount: int) -> int        # returns accepted amount
func withdraw(resource_type: Script, amount: int) -> bool   # true iff full amount withdrew
func can_accept(resource_type: Script, amount: int) -> bool
```

Lives on:
- Player entity (holds `RComponentPoint`)
- Camp storage cube entity (holds `RWood`)
- (Future) fuel tank, ammo box, food crate, etc.

### CResourceNode

```gdscript
class_name CResourceNode extends Component

@export var yield_type: Script          # e.g., RWood
@export var yield_amount: int = 1        # per gather
@export var gather_duration: float = 2.0 # seconds per gather
@export var infinite: bool = true        # prototype default
@export var remaining_yield: int = -1    # -1 = infinite; >0 = depletable
```

Attached to: trees (prototype), and future plants/carcasses/mines.

### CCarrying

```gdscript
class_name CCarrying extends Component

@export var resource_type: Script
@export var amount: int
```

Transient marker added to a worker while hauling. Removed on deposit. Prevents picking up another load mid-haul. Not in `LOSABLE_COMPONENTS` — not extracted by reverse composition.

### CWorker

```gdscript
class_name CWorker extends Component
# Tag marker; no fields
```

Identifies a GOAP agent as a worker. Parallels `CGuard`. Distinguishes worker NPCs from guard NPCs (different goal set, different action preconditions).

## GOAP Integration

### New facts

| Fact | Set by | Cleared by | Meaning |
|---|---|---|---|
| `has_work_target` | `FindWorkTarget` | `GatherResource` | Worker has a chosen resource node in blackboard |
| `reached_work_target` | `MoveToResourceNode` | `GatherResource` | Worker is adjacent to target node |
| `is_carrying` | `GatherResource` | `DepositResource` | Worker has `CCarrying` component |
| `reached_stockpile` | `MoveToStockpile` | `DepositResource` | Worker is adjacent to target stockpile |
| `has_delivered` | `DepositResource` | `SAI` post-plan tick | Most recent delivery cycle succeeded |

### New goal

| Goal | Priority | Desired state | Used by |
|---|---|---|---|
| `Work` | 20 | `has_delivered: true` | Worker NPCs |

Priority placement: above `PatrolCamp` (1), below `GuardDuty` (60) and `Survive` (100). Worker still flees from threats first, survives first.

### New actions

| Class | Pre | Effects | Cost |
|---|---|---|---|
| `GoapAction_FindWorkTarget` | `is_carrying: false`, `has_work_target: false` | `has_work_target: true` | 1.0 |
| `GoapAction_MoveToResourceNode` (extends `MoveTo`) | `has_work_target: true`, `reached_work_target: false` | `reached_work_target: true` | 1.0 |
| `GoapAction_GatherResource` | `reached_work_target: true`, `is_carrying: false` | `is_carrying: true`, `has_work_target: false`, `reached_work_target: false` | `gather_duration` |
| `GoapAction_MoveToStockpile` (extends `MoveTo`) | `is_carrying: true`, `reached_stockpile: false` | `reached_stockpile: true` | 1.0 |
| `GoapAction_DepositResource` | `reached_stockpile: true`, `is_carrying: true` | `has_delivered: true`, `is_carrying: false`, `reached_stockpile: false` | 1.0 |

**Blackboard keys:** `work_target_entity: Entity`, `stockpile_target_entity: Entity`.

**`FindWorkTarget.perform()`** — queries all `CResourceNode` entities via ECS, picks nearest within a configurable radius (`Config.WORKER_SEARCH_RADIUS`, default 2000px which covers the playable area), writes to blackboard, sets `has_work_target`.

**`MoveToResourceNode` / `MoveToStockpile`** — both extend abstract `GoapAction_MoveTo`. They read their target from the blackboard, drive `CMovement.desired_velocity` toward it, and flip their effect fact when within arrival threshold (`Config.MOVE_ARRIVAL_THRESHOLD`).

**`GatherResource.perform()`** — on entry, creates a `ProgressBarView` above the worker. Runs a timer for `target.CResourceNode.gather_duration`. On complete:
- Destroys the progress bar
- Adds `CCarrying(yield_type, yield_amount)` to the worker
- Decrements `remaining_yield` if the node is not infinite (a depletable node with `remaining_yield <= 0` is not valid as a work target — `FindWorkTarget` filters it out)
- Sets `is_carrying`, clears `has_work_target` and `reached_work_target`
- Clears `work_target_entity` from blackboard

**`MoveToStockpile.perform()`** — if `stockpile_target_entity` is unset or invalid, runs an inline search: finds the nearest `CStockpile` entity where `can_accept(carried_type, carried_amount)` is true. If none, calls `fail_plan()` (worker idles holding the load; `Work` goal stays unsatisfied). For the prototype with one always-available cube, this search runs once and caches.

**`DepositResource.perform()`** — reads the worker's `CCarrying`, calls `target_stockpile.add(type, amount)`, removes `CCarrying` from the worker, sets `has_delivered`, clears `is_carrying`, `reached_stockpile`, and `stockpile_target_entity` from the blackboard.

### Goal replanning loop

After a successful plan, `has_delivered: true` is set in the worker's world state. `SAI` has a post-plan tick that, upon seeing a completed plan for a `Work` goal, clears `has_delivered` in the agent's `CGoapAgent.world_state`. Next SAI tick, the goal is unsatisfied again and the planner builds the same plan. This mirrors the existing continuous-loop pattern used by `Patrol` and `Wander`.

The fact-clearing hook is the one new mechanic in `SAI`:

```gdscript
# In SAI, after action.on_plan_exit() if the plan completed successfully
if completed_goal and completed_goal.resource_path.ends_with("work.tres"):
    agent.world_state.set_fact("has_delivered", false)
```

A cleaner alternative is a general "goal restart" flag on the `GoapGoal` resource. Decision deferred to the implementation plan.

## Data Flow (End-to-End)

```
World init (GOLWorld)
  │
  ├─ PCG generates map + POIs (unchanged)
  ├─ PCG scatters N trees (new step: _scatter_resource_nodes)
  │    Each tree = Entity with
  │      CTransform(random walkable pos),
  │      CSprite(tree texture),
  │      CCollision(solid),
  │      CResourceNode(RWood, yield_amount=1, gather_duration=2.0, infinite=true)
  │
  ├─ spawn_camp() [existing, extended]
  │    Existing: campfire, guards, composer NPC
  │    NEW: camp_stockpile entity at campfire_pos + STOCKPILE_SPAWN_OFFSET
  │      CTransform, CSprite(cube), CCollision, CStockpile(empty)
  │    NEW: 1 worker NPC at campfire_pos + WORKER_SPAWN_OFFSET
  │      recipe: npc_worker.tres (survivor base + CWorker - CGuard)
  │      goals: [Survive, Flee, Work]
  │
  └─ spawn_player() [existing, extended]
       NEW: player_entity.add_component(CStockpile.new())

First tick
  │
  ├─ SAI picks worker's Work goal (Survive/Flee inactive: no threats)
  ├─ Planner builds plan:
  │    FindWorkTarget → MoveToResourceNode → GatherResource
  │                   → MoveToStockpile → DepositResource
  │
  ├─ FindWorkTarget
  │    Queries CResourceNode entities, picks nearest
  │    Writes work_target_entity to blackboard
  │    Sets has_work_target
  │
  ├─ MoveToResourceNode
  │    Drives CMovement toward target
  │    On arrival, sets reached_work_target
  │
  ├─ GatherResource
  │    Creates ProgressBarView above worker
  │    2.0s timer
  │    On complete:
  │      - Destroys ProgressBarView
  │      - Adds CCarrying(RWood, 1) to worker
  │      - Sets is_carrying, clears has_work_target
  │      - Tree entity unchanged (infinite)
  │
  ├─ MoveToStockpile
  │    On first entry: queries CStockpile entities, picks nearest accepting
  │    Drives CMovement toward it
  │    On arrival, sets reached_stockpile
  │
  └─ DepositResource
       stockpile.add(RWood, 1) → contents[RWood] += 1
                              → changed_observable emits updated dict
       worker.remove_component(CCarrying)
       Sets has_delivered, clears is_carrying, reached_stockpile

Next tick
  SAI clears has_delivered → Work goal unsatisfied → replan → loop

UI side (passive)
  ViewModelHud subscribes to camp_stockpile's CStockpile.changed_observable
  On change: updates "木材: N" label in the HUD
```

## Component Points Migration

### Deletions

- `PlayerData.component_points` field
- `PlayerData.points_changed` signal

### Modifications

| File | Change |
|---|---|
| `scripts/gameplay/player_data.gd` | Remove `component_points` and `points_changed`. Keep `unlocked_blueprints` and `blueprint_unlocked`. |
| `scripts/utils/composer_utils.gd` | `craft_component(player_entity: Entity, component_type: Script) -> bool` — read/write via `player_entity.get_component(CStockpile)`, using `RComponentPoint` as the type. Same for `dismantle_component`. |
| `scripts/ui/viewmodels/viewmodel_hud.gd` | `component_points` observable binds to the player entity's `CStockpile.changed_observable`, reading `get_amount(RComponentPoint)`. |
| `scripts/ui/viewmodels/viewmodel_composer.gd` | Same rebinding. |
| `scripts/ui/views/view_composer.gd` | Disabled-button check reads from the viewmodel's rebound observable instead of `GOL.Player.component_points`. |
| `scripts/gameplay/ecs/gol_world.gd` | Add `CStockpile` to player entity on spawn. |
| `scripts/ui/viewmodels/viewmodel_composer.gd` call sites | Pass `player_entity` instead of `player_data`. |
| `tests/unit/test_composer_utils.gd` (if present) | Rewrite against a player entity with `CStockpile`. |
| `tests/integration/flow/test_flow_composer_scene.gd` | Adapt to new signatures. |

### Untouched by migration

- `composer_utils.unlock_blueprint` — only touches `unlocked_blueprints`
- `CBlueprint` and the `SPickup` blueprint early-exit branch
- `SDamage` (kill-grants-points is deferred)

## World & Entity Setup

### New recipe: `npc_worker.tres`

Based on `survivor` recipe with these deltas:
- Remove: `CGuard`
- Add: `CWorker`
- Goals: `[Survive, Flee, Work]` (replaces guard's `[Survive, GuardDuty, EliminateThreat, PatrolCamp]`)

### New recipe: `camp_stockpile.tres`

```
CTransform, CSprite (stockpile cube), CCollision (solid 32x32),
CStockpile (empty contents, per_type_caps={})
```

### New resource type files

- `scripts/resources/r_wood.gd`
- `scripts/resources/r_component_point.gd`

### PCG tree scattering

Add `_scatter_resource_nodes(pcg_result)` step to the PCG pipeline, running after POI placement. Configurable via `Config.TREE_SCATTER_COUNT` (default 50). Picks random walkable tiles outside POI exclusion radius (`Config.TREE_POI_EXCLUSION_RADIUS`). Spawns tree entities with `CResourceNode(RWood, 1)`.

### GOLWorld changes

In `spawn_camp()`:
- Spawn 1 `camp_stockpile.tres` at `campfire_pos + STOCKPILE_SPAWN_OFFSET`
- Spawn 1 `npc_worker.tres` at `campfire_pos + WORKER_SPAWN_OFFSET`

In `spawn_player()`:
- `player_entity.add_component(CStockpile.new())`

## UI Integration

### HUD layout

`ViewHud` gains a resources panel on the left edge:

```
┌───────────┐
│ 组件点: 0 │   ← player.CStockpile.get_amount(RComponentPoint)
│ 木材: 0   │   ← camp_stockpile.CStockpile.get_amount(RWood)
└───────────┘
```

The existing `ComponentPointsPanel` rebinds to the new source (same visual, new data path). A new `WoodPanel` sits below it.

`ViewModelHud` gains:
- `wood_count: ObservableProperty` — bound to the camp stockpile's `changed_observable`
- `component_points: ObservableProperty` — rebound to the player entity's `changed_observable`

Wiring: `ViewModelHud._ready()` locates the camp stockpile entity via ECS query (`with_all([CStockpile]).with_none([CPlayer])` — prototype assumes exactly one non-player stockpile) and subscribes. Later, multi-stockpile support can replace this with an explicit HUD → stockpile registry.

### Worker progress bar

A `ProgressBarView` scene (tiny `Control` with a horizontal `ColorRect` fill, no animations). Lifetime owned by `GoapAction_GatherResource`:
- `on_plan_enter()`: instantiate, push to render layer, cache reference in blackboard
- `perform()`: update fill ratio each frame
- `on_plan_exit()`: free the instance

Position-synced to the worker's screen position each frame. No MVVM ceremony — it's a short-lived gameplay feedback element.

## Error Handling & Edge Cases

| Case | Behavior |
|---|---|
| Worker's target node destroyed mid-plan | `MoveToResourceNode` / `GatherResource` detects invalid blackboard entity, calls `fail_plan()`, SAI replans |
| Worker's target stockpile destroyed mid-plan | Same — `fail_plan()`, replan picks another stockpile or idles |
| Stockpile full (`can_accept` returns false) | `MoveToStockpile` search skips that stockpile. If no stockpile can accept, worker idles with `CCarrying` held; `Work` goal stays unsatisfied. Prototype has one generous cube — should not trigger. |
| Worker dies mid-haul | `CCarrying` is not in `LOSABLE_COMPONENTS`, so it's discarded with the worker's death. Wood is lost. Acceptable for the prototype. |
| Worker can't reach target (pathing timeout) | Existing `GoapAction_MoveTo` timeout → `fail_plan()` → replan. Inherited behavior. |
| Threat appears mid-haul | `Survive` goal (100) preempts `Work` (20). Worker flees. `CCarrying` persists. When `Survive` is satisfied, worker replans `Work`: since `is_carrying: true`, the plan starts from `MoveToStockpile` (skips `FindWorkTarget` + `GatherResource`). |
| `CStockpile.add()` with negative amount | Rejected (assertion in debug; no-op in release) |
| `CStockpile.withdraw()` insufficient | Returns `false`, no state change |
| Player entity spawn races `CStockpile` init | `spawn_player()` adds `CStockpile` synchronously before emitting any "player ready" signal. UI bindings wait for that signal. |
| HUD loads before camp stockpile exists | `ViewModelHud._bind_wood_count()` retries or waits for `world.entity_added` signal on the first stockpile match. |

## Testing Strategy

### Unit tests

| Test file | Coverage |
|---|---|
| `tests/unit/test_cstockpile.gd` | `add` / `withdraw` / `get_amount` / `can_accept`; per-type caps; `MAX_STACK` enforcement via `R*` constants; `changed_observable` emits exactly once per mutation |
| `tests/unit/test_cresource_node.gd` | Field defaults; infinite vs depletable behavior; `remaining_yield` decrement |
| `tests/unit/test_composer_utils_migration.gd` | `craft_component` / `dismantle_component` against a player entity with `CStockpile(RComponentPoint)`; insufficient points; at-cap; unlocked check |

Tier: `gol-test-writer-unit` skill, `quick` category.

### Integration tests (SceneConfig, `tests/integration/flow/`)

| Test file | Coverage |
|---|---|
| `test_flow_worker_gather.gd` | Scene: player + camp cube + worker + 1 tree. Assert `camp_stockpile.get_amount(RWood) == N` after the worker has run for `N * (gather_duration + travel_estimate)` seconds. |
| `test_flow_worker_flee.gd` | Scene: player + camp cube + worker + 1 tree + 1 enemy spawned after worker picks up first load. Assert: worker flees, `CCarrying` persists during flee, worker resumes `Work` after threat removed, final wood count reaches expected. |
| `test_flow_composer_migration.gd` | Rewrite of existing composer integration test. Scene: player + composer NPC + blueprint boxes. Pre-seed player `CStockpile(RComponentPoint, 2)`. Dismantle → `get_amount(RComponentPoint) == 3`. Craft → 1. |

Tier: `gol-test-writer-integration` skill, `deep` category.

### Manual / E2E

Boot the main game. Expected observable behavior:
- A worker NPC appears at camp next to the stockpile cube
- Worker walks toward a tree, stops, shows progress bar, walks back to cube, and the HUD wood counter ticks up by 1
- This loops indefinitely
- Spawning an enemy near the worker causes it to flee; after the enemy is dead, worker resumes
- Composer dialogue still works end-to-end for craft / dismantle against the migrated `CStockpile`

## Scope Boundaries (Explicit Non-Goals)

Not in this prototype — each is a future spec:

- Building system that consumes resources (v0.3)
- Hunger / drink / survival tick consumption
- Fuel / generator mechanic
- Component crafting UI change to use resources other than component points
- Multi-stockpile routing & allocation policies
- Depletable / regrowing resource nodes
- Environment creatures as resource sources
- Non-renewable loot (houses, vehicles) flowing through `CStockpile` (today and in the prototype they stay on `CContainer` / `SPickup`)
- Kill-grants-component-points and composer-dissolve-grants-points source paths
- Save/load of `CStockpile` contents
- Worker click-to-command UI
- Worker job scheduling / priorities / work order queues

## Future Extensibility

| Future need | How this design accommodates it |
|---|---|
| New resource type (fuel, food, stone) | Add one `r_*.gd` file. No other code changes — all APIs are `Script`-generic. |
| Build system consumes resources | `stockpile.withdraw(RWood, N)` at blueprint placement. Build spec chooses which stockpile(s) to deduct from. |
| Multi-stockpile logistics | `FindStockpile`/`MoveToStockpile` grow a routing strategy (nearest, priority, type-specific). `CStockpile` API unchanged. |
| Hunger / survival ticks | A new `SSurvival` periodically withdraws `RFood` from the player's stockpile. Same API. |
| Environment creatures as sources | Carcass entity spawns with `CResourceNode(RMeat, 3)`. Worker reuses the same actions. |
| Kill-grants-points | `SDamage._on_no_hp()` adds `killer.get_component(CStockpile).add(RComponentPoint, 1)` after the existing component-strip block. ~2 lines. |
| Composer-dissolve-grants-points | `composer_utils.dismantle_component` already becomes a stockpile call in this migration — the dissolve path is just the same call from a different button. |
| Save / load | `CStockpile.contents` is `@export`, serializes via `ResourceSaver` alongside the owning entity. `Script` refs serialize via `resource_path`. Blueprint save path will hit the same pattern. |
| Multiple workers | No design change. Each worker runs its own GOAP plan. `FindWorkTarget` picking needs a "reserved by another worker" check eventually; for the prototype with one worker, not needed. |

## Configuration Constants (new `Config` entries)

```gdscript
# Tree scatter
const TREE_SCATTER_COUNT: int = 50
const TREE_POI_EXCLUSION_RADIUS: float = 64.0

# Gather timing (default for CResourceNode; overridable per-node)
const DEFAULT_GATHER_DURATION: float = 2.0

# Worker behavior
const WORKER_SEARCH_RADIUS: float = 2000.0
const MOVE_ARRIVAL_THRESHOLD: float = 24.0

# Spawn offsets from campfire
const WORKER_SPAWN_OFFSET: Vector2 = Vector2(-48, 0)
const STOCKPILE_SPAWN_OFFSET: Vector2 = Vector2(48, 0)

# Initial camp stockpile cap (generous for prototype)
const CAMP_STOCKPILE_DEFAULT_CAP: int = 9999
```

All values are initial. Tune via playtest.

## Open Questions (deferred to implementation plan)

1. Progress bar view scene path (`scenes/ui/` vs `scenes/gameplay/`) and visual style.
2. Tree sprite asset: placeholder or existing asset — needs art check.
3. PCG tree scattering algorithm: uniform random vs Poisson disk. Default to uniform random; revisit if trees overlap visually.
4. `has_delivered` fact-clearing mechanism: SAI inline vs general "continuous goal restart" flag on `GoapGoal`. Defaults to SAI inline for the prototype.
5. Exact numeric values for `TREE_SCATTER_COUNT`, `DEFAULT_GATHER_DURATION`, `WORKER_SEARCH_RADIUS`. Defaults above are starting guesses.
