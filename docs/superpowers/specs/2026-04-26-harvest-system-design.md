# GOL 玩家采集系统 + 新植物类型 — Harvest System Design

> **Date:** 2026-04-26
> **Status:** Draft
> **Scope:** v0.3 Resource System expansion (post-rabbit)
> **Depends on:** `2026-04-24-rabbit-creature-design.md` (all primitives landed)
> **Related notes:** `GOL 资源系统`, `GOL v0.3 版本规划`, `GOL 环境生物`

## Overview

Introduce a **player harvesting mechanic** and **two new plant types** to expand GOL's resource ecology beyond passive pickup. This spec delivers:

```
PCG places raspberry bushes + carrots during world generation
  → Player approaches plant, presses [interact]
    → Bush: timed gather (2s progress bar) → RFood(2), bush enters cooldown → regrows
    → Carrot: instant collect → RFood(1), entity removed
  → Rabbits eat carrots via existing CEatable/GOAP (no code change)
  → Camp NPCs forage bushes as hunger fallback when stockpile is empty
  → Progress bar is generic — reusable for woodcutting, mining, any future timed interaction
  → Floating "+N 资源" text on harvest completion (speech bubble event text)
```

This builds on the rabbit spec's primitives (`CEatable`, `CResourceNode`, `SWorldGrowth`, `GrowthTable`, `CStockpile`, `SAutoFeed`) without structural changes to any of them.

### Design philosophy: Don't Starve plant taxonomy

Plants follow a Don't Starve-inspired spawn model with three categories:

| Category | Spawn | Regrowth | Example |
|----------|-------|----------|---------|
| **PCG fixed, renewable** | World gen only | Cooldown → regrow in place | Raspberry bush |
| **PCG fixed, consumable** | World gen only | None (removed on harvest) | Carrot |
| **Runtime growth** | `SWorldGrowth` continuous | Infinite (new instances spawn) | Grass |

A new `spawn_source` field in `GrowthTable` formalizes this: `"pcg"` vs `"growth"`. `SWorldGrowth` only processes `spawn_source = "growth"` rules.

### Golden decisions from brainstorming

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Harvest interaction | Timed gather (interact key + progress bar) | Deliberate feel, like Stardew Valley. Reuses existing `ViewProgressBar`. |
| Resource type | Both plants yield `RFood` | Zero new plumbing. Food is scarce — immediate gameplay value. No premature crafting abstraction. |
| Carrot component model | `CEatable` only (no `CResourceNode`) | Rabbits eat carrots via existing GOAP. Player collects via `SHarvest`. One component, two consumers. |
| Bush component model | `CResourceNode` (with cooldown extension) | Timed gather + yield + cooldown. `CEatable` is wrong — bushes aren't "eaten." |
| Carrot player collection | Interact key, instant (no progress bar) | Slightly more deliberate than walk-over. Distinguishes from passive food pile pickup. |
| Bush post-harvest | Cooldown + emoji swap (🍓→🪵→🍓) | Bush is a permanent map fixture. Consistent with Don't Starve berry bush. |
| Grass harvestable? | No — grass is rabbit food only | `CEatable.player_harvestable = false`. Clean separation. |
| NPC bush foraging | All PLAYER-camp NPCs, fallback only | When hungry AND stockpile empty → GOAP plans forage. Lower priority than eating from stockpile. |
| Progress bar | Generic, reusable, pixel-art style | Terraria-inspired. Color per interaction type. Benefits woodcutting too. |
| Floating text | Extend speech bubble with one-shot event text | "+1 树莓" on harvest. Lightweight, reuses existing UI infrastructure. |

## Architecture

```
┌─ Modified design sheets ────────────────────────────────────────────┐
│   GrowthTable  — add spawn_source field, add raspberry_bush/carrot  │
│                  entries with spawn_source="pcg"                     │
└─────────────────────────────────────────────────────────────────────┘
                ▲
                │
┌─ Modified components ───────────────────────────────────────────────┐
│   CEatable       — add player_harvestable: bool = false             │
│   CResourceNode  — add cooldown_duration, cooldown_remaining,       │
│                    depleted_label fields                             │
│   ViewProgressBar — add fill_color param, border, flash-on-complete │
│   CSpeechBubble  — add show_event_text() for one-shot floating text │
└─────────────────────────────────────────────────────────────────────┘
                ▲
                │
┌─ New system ────────────────────────────────────────────────────────┐
│   SHarvest     — player interact → find nearest harvestable →       │
│                  progress bar (if timed) → yield to stockpile →     │
│                  remove or cooldown → floating text feedback         │
│                  Handles both CResourceNode and CEatable paths       │
└─────────────────────────────────────────────────────────────────────┘
                ▲
                │
┌─ New GOAP additions (NPC foraging) ─────────────────────────────────┐
│   GoapAction_MoveToHarvestable — perception → nearest CResourceNode │
│   GoapAction_HarvestBush       — timed gather → yield to stockpile  │
│   SPerception                  — add has_visible_harvestable fact    │
│   SHunger or new system        — add stockpile_has_food fact        │
└─────────────────────────────────────────────────────────────────────┘
                ▲
                │
┌─ New recipes ───────────────────────────────────────────────────────┐
│   raspberry_bush.tres — CResourceNode + CLabelDisplay(🍓)           │
│   carrot.tres         — CEatable(player_harvestable=true) +         │
│                         CLabelDisplay(🥕)                           │
└─────────────────────────────────────────────────────────────────────┘
                ▲
                │
┌─ PCG placement ─────────────────────────────────────────────────────┐
│   PlantPlacer (new PCG phase) — scatters bushes + carrots during    │
│                                 world gen based on zone rules        │
└─────────────────────────────────────────────────────────────────────┘
```

## Section 1 — Component Changes

### `CEatable` — add `player_harvestable` field

```gdscript
# scripts/components/c_eatable.gd  (MODIFIED — one field added)
class_name CEatable
extends Component

@export var hunger_restore: float = 20.0
@export var player_harvestable: bool = false   ## NEW — SHarvest checks this
@export var harvest_yield: int = 1             ## NEW — how many RFood player gets
```

- Grass recipe: `player_harvestable = false` (default, zero change to existing recipe)
- Carrot recipe: `player_harvestable = true`, `harvest_yield = 1`

`harvest_yield` is only read by `SHarvest` for the player path. `GoapAction_EatGrass` does not read `player_harvestable` or `harvest_yield` — it queries `CEatable` and eats regardless. This is correct: rabbits eat both grass and carrots.

### `CResourceNode` — add cooldown fields

```gdscript
# scripts/components/c_resource_node.gd  (MODIFIED — three fields added)
class_name CResourceNode
extends Component

@export var yield_type: Script
@export var yield_amount: int = 1
@export var gather_duration: float = 2.0
@export var infinite: bool = true
@export var remaining_yield: int = -1

@export var cooldown_duration: float = 0.0      ## NEW — 0 = no cooldown
@export var ready_label: String = ""             ## NEW — emoji when harvestable (e.g. "🍓")
@export var depleted_label: String = ""          ## NEW — emoji during cooldown (e.g. "🪵")
var cooldown_remaining: float = 0.0              ## NEW — runtime state

var is_on_cooldown: bool:                        ## NEW — computed property
    get: return cooldown_remaining > 0.0


func can_gather() -> bool:
    if is_on_cooldown:
        return false
    if infinite:
        return true
    return remaining_yield > 0


func consume_yield() -> int:
    if not can_gather():
        return 0
    if not infinite:
        remaining_yield -= 1
    return yield_amount


func start_cooldown() -> void:                   ## NEW
    if cooldown_duration > 0.0:
        cooldown_remaining = cooldown_duration
```

Existing `GoapAction_GatherResource` (woodcutting) calls `can_gather()` and `consume_yield()` — both still work. `cooldown_duration` defaults to `0.0`, so existing tree `CResourceNode` instances are unaffected.

### `ViewProgressBar` — upgrade to generic reusable bar

```gdscript
# scripts/ui/views/view_progress_bar.gd  (MODIFIED)
class_name ViewProgressBar
extends ViewBase

@onready var _fill: ColorRect = $Fill
@onready var _background: ColorRect = $Background
@onready var _border: ReferenceRect = $Border       ## NEW — 1px border

var _followed_entity: Entity = null
var _offset: Vector2 = Vector2(0, -32)

## Color presets per interaction type
const COLOR_HARVEST: Color = Color(0.3, 0.8, 0.3, 1.0)    ## green
const COLOR_CHOP: Color = Color(0.6, 0.4, 0.2, 1.0)       ## brown
const COLOR_MINE: Color = Color(0.3, 0.5, 0.9, 1.0)       ## blue

func setup(entity: Entity, color: Color = COLOR_HARVEST, offset: Vector2 = Vector2(0, -32)) -> void:
    _followed_entity = entity
    _offset = offset
    _fill.color = color
    set_progress(0.0)

func set_progress(ratio: float) -> void:
    ratio = clamp(ratio, 0.0, 1.0)
    if _fill == null:
        return
    _fill.size.x = _background.size.x * ratio

func flash_and_remove() -> void:
    ## Pixel-art style: hard white flash for 0.1s, then remove. No easing.
    _fill.color = Color.WHITE
    get_tree().create_timer(0.1).timeout.connect(func():
        if is_instance_valid(self):
            ServiceContext.ui().pop_view(self)
    )

func follow_entity(entity: Entity, offset: Vector2 = Vector2(0, -32)) -> void:
    _followed_entity = entity
    _offset = offset

func _process(_delta: float) -> void:
    if _followed_entity == null or not is_instance_valid(_followed_entity):
        return
    var t: CTransform = _followed_entity.get_component(CTransform)
    if t == null:
        return
    global_position = t.position + _offset
```

Scene changes (`progress_bar.tscn`):
- Background: `Color(0, 0, 0, 0.5)`, size `36×5`
- Fill: size `0×5` (grows via `set_progress`)
- Border: `ReferenceRect` or `StyleBoxFlat` with 1px outline, `Color(0.2, 0.2, 0.2, 0.8)`
- No rounded corners, no easing — pixel-art hard edges

`GoapAction_GatherResource` (woodcutting) updated to use `setup(entity, COLOR_CHOP)` instead of raw `follow_entity` + manual color. Same behavior, now with the correct brown color.

### `CSpeechBubble` — add one-shot event text

```gdscript
# scripts/components/c_speech_bubble.gd  (MODIFIED — add event text support)

## NEW — one-shot floating text that bypasses the state/priority system.
## Used for harvest feedback ("+2 食物"), damage numbers, etc.
## Displayed for `event_duration` seconds, then auto-dismissed.
## Does NOT interrupt or conflict with state-driven speech bubbles —
## event text uses a separate display slot (offset above the speech bubble).
var event_text: String = ""
var event_text_observable: ObservableProperty = ObservableProperty.new("")
var event_duration: float = 0.0

func show_event_text(text: String, duration: float = 1.5) -> void:
    event_text = text
    event_duration = duration
    event_text_observable.notify(text)
```

`SSpeechBubble` ticks down `event_duration` and clears `event_text` when expired. The view renders event text in a separate label above the main speech bubble position, with the same pixel-art style (white text, black outline, font_size 8).

## Section 2 — SHarvest System (Player Harvesting)

### Overview

`SHarvest` is the single system handling all player-initiated gathering. It manages two paths:

| Path | Target component | Gather duration | Post-harvest | Example |
|------|-----------------|-----------------|--------------|---------|
| **Timed** | `CResourceNode` | `gather_duration` (e.g. 2s) | Cooldown or remove | Raspberry bush, trees |
| **Instant** | `CEatable` where `player_harvestable == true` | 0 (immediate) | Remove entity | Carrot |

### System definition

```gdscript
# scripts/systems/s_harvest.gd
class_name SHarvest
extends System

func _ready() -> void:
    group = "gameplay"
    active = true

func query() -> QueryBuilder:
    return q.with_all([CPlayer, CTransform])
```

### State machine

`SHarvest` tracks a per-player harvest state:

```
IDLE → (interact pressed + target in range) → GATHERING → (elapsed >= duration) → COMPLETE → IDLE
                                                  ↓
                                          (interact released / target lost / moved away)
                                                  ↓
                                               CANCEL → IDLE
```

State is stored in instance variables (single player game):

```gdscript
enum State { IDLE, GATHERING, COMPLETE }

var _state: State = State.IDLE
var _target: Entity = null
var _elapsed: float = 0.0
var _duration: float = 0.0
var _progress_view: ViewProgressBar = null
```

### Process flow

```gdscript
func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    var player: Entity = entities[0]
    var player_pos: Vector2 = player.get_component(CTransform).position

    match _state:
        State.IDLE:
            if Input.is_action_just_pressed("interact"):
                var target := _find_nearest_harvestable(player_pos)
                if target != null:
                    _begin_harvest(player, target)

        State.GATHERING:
            if not _is_valid_target(_target, player_pos):
                _cancel_harvest()
                return
            if not Input.is_action_pressed("interact"):
                _cancel_harvest()
                return
            _elapsed += delta
            if _progress_view:
                _progress_view.set_progress(_elapsed / _duration)
            if _elapsed >= _duration:
                _complete_harvest(player)

        State.COMPLETE:
            _state = State.IDLE
```

### Target finding

```gdscript
const HARVEST_RANGE: float = 32.0
const HARVEST_RANGE_SQ: float = HARVEST_RANGE * HARVEST_RANGE

func _find_nearest_harvestable(player_pos: Vector2) -> Entity:
    var best: Entity = null
    var best_dist_sq: float = HARVEST_RANGE_SQ

    ## Path 1: CResourceNode entities (bushes, future: rocks, etc.)
    var resource_nodes := ECS.world.query.with_all([CResourceNode, CTransform]).execute()
    for entity in resource_nodes:
        var node: CResourceNode = entity.get_component(CResourceNode)
        if not node.can_gather():
            continue
        var dist_sq := player_pos.distance_squared_to(entity.get_component(CTransform).position)
        if dist_sq < best_dist_sq:
            best = entity
            best_dist_sq = dist_sq

    ## Path 2: CEatable entities with player_harvestable=true (carrots)
    var eatables := ECS.world.query.with_all([CEatable, CTransform]).execute()
    for entity in eatables:
        var eatable: CEatable = entity.get_component(CEatable)
        if not eatable.player_harvestable:
            continue
        if entity.has_component(CDead):
            continue
        var dist_sq := player_pos.distance_squared_to(entity.get_component(CTransform).position)
        if dist_sq < best_dist_sq:
            best = entity
            best_dist_sq = dist_sq

    return best
```

### Begin harvest

```gdscript
func _begin_harvest(player: Entity, target: Entity) -> void:
    _target = target
    _elapsed = 0.0
    _state = State.GATHERING

    if target.has_component(CResourceNode):
        var node: CResourceNode = target.get_component(CResourceNode)
        _duration = node.gather_duration
    else:
        _duration = 0.0   ## instant for CEatable

    ## Show progress bar only for timed gathers
    if _duration > 0.0:
        _progress_view = PROGRESS_BAR_SCENE.instantiate() as ViewProgressBar
        _progress_view.setup(target, ViewProgressBar.COLOR_HARVEST)
        ServiceContext.ui().push_view(Service_UI.LayerType.GAME, _progress_view)

    ## Stop player movement during gather
    var movement := player.get_component(CMovement) as CMovement
    if movement:
        movement.velocity = Vector2.ZERO
```

### Complete harvest

```gdscript
func _complete_harvest(player: Entity) -> void:
    var stockpile := _find_camp_stockpile()
    if stockpile == null:
        _cancel_harvest()
        return

    var yield_amount: int = 0
    var display_name: String = ""

    if _target.has_component(CResourceNode):
        ## Path 1: CResourceNode (bush)
        var node: CResourceNode = _target.get_component(CResourceNode)
        yield_amount = node.consume_yield()
        stockpile.add(node.yield_type, yield_amount)
        display_name = _get_resource_display_name(node.yield_type)

        ## Start cooldown + swap emoji
        node.start_cooldown()
        var label := _target.get_component(CLabelDisplay) as CLabelDisplay
        if label and node.depleted_label != "":
            label.text = node.depleted_label

    elif _target.has_component(CEatable):
        ## Path 2: CEatable (carrot)
        var eatable: CEatable = _target.get_component(CEatable)
        yield_amount = eatable.harvest_yield
        stockpile.add(RFood, yield_amount)
        display_name = "食物"
        cmd.remove_entity(_target)

    ## Flash progress bar (if present) then remove
    if _progress_view:
        _progress_view.flash_and_remove()
        _progress_view = null

    ## Floating text feedback
    _show_harvest_text(_target, yield_amount, display_name)

    _target = null
    _elapsed = 0.0
    _state = State.COMPLETE
```

### Cancel harvest

```gdscript
func _cancel_harvest() -> void:
    if _progress_view:
        ServiceContext.ui().pop_view(_progress_view)
        _progress_view = null
    _target = null
    _elapsed = 0.0
    _state = State.IDLE
```

### Floating text feedback

```gdscript
func _show_harvest_text(target: Entity, amount: int, display_name: String) -> void:
    var bubble := target.get_component(CSpeechBubble) as CSpeechBubble
    if bubble:
        bubble.show_event_text("+%d %s" % [amount, display_name])
    ## If target has no CSpeechBubble (e.g. carrot about to be removed),
    ## show on the player entity instead.
    elif amount > 0:
        var players := ECS.world.query.with_all([CPlayer, CSpeechBubble]).execute()
        if not players.is_empty():
            var player_bubble := players[0].get_component(CSpeechBubble) as CSpeechBubble
            player_bubble.show_event_text("+%d %s" % [amount, display_name])
```

### Cooldown tick (bush regrowth)

`SHarvest` also ticks cooldowns on `CResourceNode` entities:

```gdscript
## Called in process() regardless of harvest state
func _tick_cooldowns(delta: float) -> void:
    var nodes := ECS.world.query.with_all([CResourceNode, CTransform]).execute()
    for entity in nodes:
        var node: CResourceNode = entity.get_component(CResourceNode)
        if not node.is_on_cooldown:
            continue
        node.cooldown_remaining -= delta
        if node.cooldown_remaining <= 0.0:
            node.cooldown_remaining = 0.0
            ## Restore ready emoji
            var label := entity.get_component(CLabelDisplay) as CLabelDisplay
            if label and node.ready_label != "":
                label.text = node.ready_label
```

## Section 3 — Plant Recipes

### `raspberry_bush.tres`

```
resources/recipes/raspberry_bush.tres (EntityRecipe)
  recipe_id = "raspberry_bush"
  display_name = "树莓灌木丛"
  components = [
    CTransform,
    CCollision       { shape = CircleShape2D(radius = 16) },
    CResourceNode    {
        yield_type = RFood,
        yield_amount = 2,
        gather_duration = 2.0,
        infinite = true,
        cooldown_duration = 60.0,
        ready_label = "🍓",
        depleted_label = "🪵",
    },
    CLabelDisplay    { text = "🍓", font_size = 20 },    # TEMPORARY
    CSpeechBubble    { offset = Vector2(0, -40) },       # for harvest floating text
  ]
```

No `CEatable` — bushes are not edible by rabbits. No `CLifeTime` — bushes are permanent map fixtures. `CSpeechBubble` is included so `SHarvest` can show "+2 食物" on the bush itself after harvest.

### `carrot.tres`

```
resources/recipes/carrot.tres (EntityRecipe)
  recipe_id = "carrot"
  display_name = "胡萝卜"
  components = [
    CTransform,
    CCollision       { shape = CircleShape2D(radius = 12) },
    CEatable         { hunger_restore = 15.0, player_harvestable = true, harvest_yield = 1 },
    CLabelDisplay    { text = "🥕", font_size = 18 },    # TEMPORARY
  ]
```

No `CLifeTime` — carrots persist until harvested by player or eaten by rabbit. No `CResourceNode` — carrot collection is instant, no timed gather needed.

Rabbits eat carrots via existing `GoapAction_EatGrass` which queries `CEatable` — no code change. The action name is misleading ("EatGrass" eats any `CEatable`) but renaming is out of scope.

### `grass.tres` — unchanged

Grass keeps `CEatable.player_harvestable = false` (the default). `SHarvest` ignores it. Rabbits eat it as before.

## Section 4 — Spawn Source & PCG Placement

### `GrowthTable` — add `spawn_source` field

```gdscript
# scripts/gameplay/tables/growth_table.gd  (MODIFIED)
const TABLES: Dictionary = {
    "grass": {
        spawn_source = "growth",                    ## NEW
        zones = [ZoneMap.ZoneType.WILDERNESS, ZoneMap.ZoneType.SUBURBS],
        interval_sec = 8.0,
        per_cell_chance = 0.02,
        world_cap = 60,
    },
    "raspberry_bush": {                             ## NEW — PCG only, no runtime growth
        spawn_source = "pcg",
    },
    "carrot": {                                     ## NEW — PCG only, no runtime growth
        spawn_source = "pcg",
    },
}
```

Entries with `spawn_source = "pcg"` have no growth fields (`zones`, `interval_sec`, etc.) — they exist in the table purely as a registry for the spawn taxonomy. `SWorldGrowth` skips them.

### `SWorldGrowth` — filter by `spawn_source`

One-line change in `_on_growth_tick()`:

```gdscript
for recipe_id in GOL.Tables.growth().all().keys():
    var rule := GOL.Tables.growth().get_rule(recipe_id)
    if rule.get("spawn_source", "growth") != "growth":    ## NEW — skip PCG-only plants
        continue
    # ... existing growth logic unchanged
```

### `PlantPlacer` — new PCG phase

```gdscript
# scripts/pcg/phases/plant_placer.gd
class_name PlantPlacer
extends PCGPhase

const BUSH_ZONES: Array = [ZoneMap.ZoneType.WILDERNESS, ZoneMap.ZoneType.SUBURBS]
const CARROT_ZONES: Array = [ZoneMap.ZoneType.WILDERNESS]

const MAX_BUSHES: int = 20
const MAX_CARROTS: int = 35

const BUSH_PER_CELL_CHANCE: float = 0.01
const CARROT_PER_CELL_CHANCE: float = 0.015

func execute(config: PCGConfig, context: PCGContext) -> void:
    var rng := context.get_rng()
    _place_plants(context, rng, "raspberry_bush", BUSH_ZONES, BUSH_PER_CELL_CHANCE, MAX_BUSHES)
    _place_plants(context, rng, "carrot", CARROT_ZONES, CARROT_PER_CELL_CHANCE, MAX_CARROTS)

func _place_plants(context: PCGContext, rng: RandomNumberGenerator,
        recipe_id: String, zones: Array, chance: float, max_count: int) -> void:
    var placed: int = 0
    var candidates: Array = []

    for cell in context.zone_map.zones:
        var zone := context.zone_map.get_zone(cell)
        if zone not in zones:
            continue
        if context.has_poi_at(cell):
            continue
        candidates.append(cell)

    candidates.shuffle()

    for cell in candidates:
        if placed >= max_count:
            break
        if rng.randf() > chance:
            continue
        context.add_plant({
            recipe_id = recipe_id,
            cell = cell,
        })
        placed += 1
```

**`PCGContext`** — add `plants: Array[Dictionary]` field and `add_plant()` method (mirrors `creature_spawners` pattern).

**`PCGResult`** — expose `plants` array.

**`gol_world.gd`** — add `_place_plants(pcg_result)` in the world-build sequence:

```gdscript
func _place_plants(pcg_result: PCGResult) -> void:
    for spec in pcg_result.plants:
        var entity: Entity = ServiceContext.recipe().create_entity_by_id(spec.recipe_id)
        if entity == null:
            continue
        var t := entity.get_component(CTransform) as CTransform
        if t:
            t.position = pcg_result.grid_to_world(spec.cell)
```

Registered in the PCG pipeline **after** zone generation, **before** creature spawner placement (plants should exist before rabbits spawn to eat them).

## Section 5 — NPC Foraging (GOAP)

### Trigger condition

Camp NPCs forage bushes as a **fallback** when:
1. `is_hungry = true` (hunger below threshold)
2. `stockpile_has_food = false` (camp stockpile has zero RFood)
3. `has_visible_harvestable = true` (CResourceNode in perception range)

### New world_state facts

**`stockpile_has_food`** — set by `SAutoFeed` (or a lightweight helper) each tick:

```gdscript
## In SAutoFeed, after finding camp stockpile:
var has_food: bool = stockpile != null and stockpile.get_amount(RFood) > 0
## Mirror to all PLAYER-camp GOAP agents:
for entity in player_camp_entities:
    var agent := entity.get_component(CGoapAgent) as CGoapAgent
    if agent:
        agent.world_state.update_fact("stockpile_has_food", has_food)
```

**`has_visible_harvestable`** — set by `SPerception`:

```gdscript
## In SPerception._process_entity, alongside existing has_visible_grass:
var has_harvestable: bool = false
for visible in perception._visible_entities:
    if visible.has_component(CResourceNode):
        var node: CResourceNode = visible.get_component(CResourceNode)
        if node.can_gather():
            has_harvestable = true
            break
agent.world_state.update_fact("has_visible_harvestable", has_harvestable)
```

### New GOAP actions

**`GoapAction_MoveToHarvestable`**

```gdscript
# scripts/gameplay/goap/actions/move_to_harvestable.gd
class_name GoapAction_MoveToHarvestable
extends GoapAction

func _init() -> void:
    action_name = "MoveToHarvestable"
    cost = 5.0    ## higher than eating from stockpile (cost ~2)
    preconditions = {
        "is_hungry": true,
        "stockpile_has_food": false,
        "has_visible_harvestable": true,
        "adjacent_to_harvestable": false,
    }
    effects = {"adjacent_to_harvestable": true}
```

Scans `perception._visible_entities` for nearest `CResourceNode` where `can_gather()`, moves toward it. Returns `true` when within adjacency threshold (24 px).

**`GoapAction_HarvestBush`**

```gdscript
# scripts/gameplay/goap/actions/harvest_bush.gd
class_name GoapAction_HarvestBush
extends GoapAction

func _init() -> void:
    action_name = "HarvestBush"
    cost = 1.0
    preconditions = {"adjacent_to_harvestable": true}
    effects = {"is_fed": true}    ## satisfies feed_self goal
```

On perform:
1. Stop movement
2. Get target `CResourceNode` from blackboard
3. Show progress bar (reuse `ViewProgressBar` with `COLOR_HARVEST`)
4. Tick elapsed time against `gather_duration`
5. On complete: `consume_yield()`, add to camp stockpile, `start_cooldown()`, swap emoji
6. Restore hunger: `hunger += HungerTable.HUNGER_PER_FOOD_UNIT * yield_amount`

This mirrors `GoapAction_GatherResource` (woodcutting) but deposits to stockpile AND directly restores hunger, since the NPC is foraging because it's hungry.

### Goal integration

No new goals needed. The existing `feed_self` goal (`priority = 50`, desired `{is_fed: true}`) is satisfied by the `MoveToHarvestable → HarvestBush` action chain. The GOAP planner picks this chain only when:
- `is_fed` is false (hungry)
- `stockpile_has_food` is false (can't eat from stockpile)
- `has_visible_harvestable` is true (bush in range)

The higher cost (5 for move + 1 for harvest = 6 total) vs eating from stockpile (cost ~2) ensures foraging is a fallback, not the primary feeding strategy.

### Which NPCs get foraging?

All entities with `CGoapAgent` + `CHunger` + `CCamp(PLAYER)` can plan foraging actions. Currently this includes:
- **Survivors (guards)** — have `feed_self` goal
- **Workers** — have `feed_self` goal

No recipe changes needed — the GOAP planner automatically considers the new actions for any agent whose goal set includes `feed_self`.

## Section 6 — Progress Bar Visual Spec

Terraria-inspired pixel-art progress bar. Generic — used by harvesting, woodcutting, mining, any timed interaction.

### Dimensions & style

| Property | Value |
|----------|-------|
| Width | 36 px |
| Height | 5 px |
| Background | `Color(0, 0, 0, 0.5)` |
| Border | 1 px, `Color(0.2, 0.2, 0.2, 0.8)` |
| Position | Entity head top, offset `Vector2(0, -32)` |
| Fill direction | Left → right |
| Animation | None — hard pixel cuts, no easing |

### Color per interaction type

| Type | Color | Constant |
|------|-------|----------|
| Harvest (plants) | Green `Color(0.3, 0.8, 0.3, 1.0)` | `COLOR_HARVEST` |
| Chop (trees) | Brown `Color(0.6, 0.4, 0.2, 1.0)` | `COLOR_CHOP` |
| Mine (future) | Blue `Color(0.3, 0.5, 0.9, 1.0)` | `COLOR_MINE` |

### Completion behavior

1. Fill reaches 100%
2. Fill color hard-swaps to `Color.WHITE` (flash)
3. After 0.1s, bar is removed (`pop_view`)
4. No fade, no scale animation — pixel-art hard cut

### Cancellation behavior

Bar is immediately removed (`pop_view`). No animation.

## Section 7 — Floating Harvest Text

On harvest completion, display floating text above the entity:

```
+2 食物
```

### Implementation

Extend `CSpeechBubble` with a one-shot `show_event_text(text, duration)` method. Event text:
- Renders in a **separate label** above the main speech bubble position
- Uses same pixel-art style: white text, black 2px outline, font_size 8
- Duration: 1.5s, then auto-dismiss
- Does NOT interrupt state-driven speech bubbles (idle, combat, hunger)
- If the target entity is about to be removed (carrot), show on the player entity instead

### Text format

| Plant | Text |
|-------|------|
| Raspberry bush | `+2 食物` |
| Carrot | `+1 食物` |

Uses `RFood.DISPLAY_NAME` ("食物") for the resource name.

## Section 8 — Interaction Summary

### Player harvests raspberry bush

```
Player approaches bush (within 32px)
  → Presses [interact]
  → SHarvest finds CResourceNode, begins GATHERING state
  → Progress bar appears above bush (green, 36×5px)
  → Player holds [interact] for 2.0s
  → Progress bar fills left→right
  → At 100%: flash white (0.1s), remove bar
  → CResourceNode.consume_yield() → 2
  → Camp stockpile gains RFood(2)
  → Bush enters cooldown: emoji swaps 🍓→🪵
  → Floating text: "+2 食物" (1.5s)
  → After 60s cooldown: emoji swaps 🪵→🍓, bush harvestable again
```

### Player harvests carrot

```
Player approaches carrot (within 32px)
  → Presses [interact]
  → SHarvest finds CEatable (player_harvestable=true), duration=0
  → No progress bar (instant)
  → Camp stockpile gains RFood(1)
  → Carrot entity removed from world
  → Floating text on player: "+1 食物" (1.5s)
```

### Rabbit eats carrot

```
Rabbit is hungry (CHunger below threshold)
  → SPerception detects CEatable (carrot) → has_visible_grass=true
  → GOAP plans: MoveToGrass → EatGrass (existing actions)
  → Rabbit moves to carrot
  → GoapAction_EatGrass: hunger += 15.0, carrot entity removed
  → No floating text, no stockpile interaction
```

### NPC forages bush (fallback)

```
Guard is hungry + camp stockpile has 0 RFood
  → SPerception detects CResourceNode (bush) → has_visible_harvestable=true
  → SAutoFeed mirrors stockpile_has_food=false
  → GOAP plans: MoveToHarvestable → HarvestBush
  → Guard moves to bush
  → GoapAction_HarvestBush: progress bar, 2s gather
  → consume_yield() → 2, add to stockpile, restore hunger
  → Bush enters cooldown (emoji swap)
  → SAutoFeed resumes normal feeding from stockpile
```

## Section 9 — Testing Strategy

### Unit tests

| Test | Validates |
|------|-----------|
| `CEatable.player_harvestable` default | New field defaults to `false` |
| `CResourceNode.cooldown` cycle | `start_cooldown()` → `is_on_cooldown` → tick down → `can_gather()` restored |
| `CResourceNode.can_gather` rejects cooldown | Returns `false` while `cooldown_remaining > 0` |
| `GrowthTable.spawn_source` | `grass` = `"growth"`, `raspberry_bush` = `"pcg"`, `carrot` = `"pcg"` |

### Integration tests

| Test | Validates |
|------|-----------|
| Player harvest bush → stockpile | Interact + wait → `RFood` amount increases by 2 |
| Player harvest carrot → stockpile + entity removed | Interact → `RFood` +1, carrot entity freed |
| Bush cooldown → regrow | After harvest, `can_gather()` = false; after cooldown, `can_gather()` = true |
| SWorldGrowth skips PCG plants | Only `spawn_source="growth"` recipes get runtime spawning |
| Rabbit eats carrot | Rabbit with low hunger + visible carrot → hunger restored, carrot removed |
| NPC forages bush when stockpile empty | Guard hungry + stockpile 0 → plans forage → stockpile gains food |

### Playtest scenarios

| Scenario | Expected |
|----------|----------|
| Walk around map, find bushes and carrots | PCG places ~20 bushes, ~35 carrots in correct zones |
| Harvest bush, wait, harvest again | Full cycle: gather → cooldown → regrow → gather |
| Harvest carrot near rabbit | Player and rabbit compete for same carrot |
| Empty stockpile, watch NPCs forage | Guards leave posts to forage bushes, return after eating |
| Progress bar visual check | Green bar, correct size, flash on complete, no easing |

## Section 10 — File Manifest

### New files

| File | Type | Description |
|------|------|-------------|
| `scripts/systems/s_harvest.gd` | System | Player harvesting — interact, progress, yield, cooldown |
| `scripts/gameplay/goap/actions/move_to_harvestable.gd` | GOAP Action | NPC moves to nearest harvestable bush |
| `scripts/gameplay/goap/actions/harvest_bush.gd` | GOAP Action | NPC timed gather from bush |
| `scripts/pcg/phases/plant_placer.gd` | PCG Phase | Scatters bushes + carrots during world gen |
| `resources/recipes/raspberry_bush.tres` | Recipe | Bush entity definition |
| `resources/recipes/carrot.tres` | Recipe | Carrot entity definition |

### Modified files

| File | Change |
|------|--------|
| `scripts/components/c_eatable.gd` | Add `player_harvestable: bool = false`, `harvest_yield: int = 1` |
| `scripts/components/c_resource_node.gd` | Add `cooldown_duration`, `cooldown_remaining`, `ready_label`, `depleted_label`, `is_on_cooldown`, `start_cooldown()` |
| `scripts/ui/views/view_progress_bar.gd` | Add `setup()`, `flash_and_remove()`, color constants, border |
| `scenes/ui/progress_bar.tscn` | Update dimensions (36×5), add border node |
| `scripts/components/c_speech_bubble.gd` | Add `event_text`, `event_text_observable`, `show_event_text()` |
| `scripts/systems/s_speech_bubble.gd` | Tick `event_duration`, clear expired event text |
| `scripts/ui/views/view_speech_bubble.gd` | Render event text in separate label |
| `scripts/gameplay/tables/growth_table.gd` | Add `spawn_source` field, add `raspberry_bush` + `carrot` entries |
| `scripts/systems/s_world_growth.gd` | Filter by `spawn_source == "growth"` |
| `scripts/systems/s_perception.gd` | Add `has_visible_harvestable` fact |
| `scripts/systems/s_auto_feed.gd` | Mirror `stockpile_has_food` fact to GOAP agents |
| `scripts/pcg/data/pcg_context.gd` | Add `plants` array + `add_plant()` |
| `scripts/pcg/data/pcg_result.gd` | Expose `plants` array |
| `scripts/gameplay/ecs/gol_world.gd` | Add `_place_plants()` in world-build sequence |
| `scripts/pcg/pipeline/pcg_pipeline.gd` | Register `PlantPlacer` phase |
| `scripts/gameplay/goap/actions/gather_resource.gd` | Use `ViewProgressBar.setup()` with `COLOR_CHOP` |

## Appendix — Tuning Constants

| Constant | Value | Location |
|----------|-------|----------|
| `HARVEST_RANGE` | 32 px | `SHarvest` |
| Bush `gather_duration` | 2.0s | `raspberry_bush.tres` |
| Bush `cooldown_duration` | 60.0s | `raspberry_bush.tres` |
| Bush `yield_amount` | 2 (RFood) | `raspberry_bush.tres` |
| Carrot `hunger_restore` | 15.0 | `carrot.tres` |
| Carrot player yield | 1 (RFood) | `carrot.tres` via `CEatable.harvest_yield` |
| Progress bar size | 36×5 px | `progress_bar.tscn` |
| Progress bar flash | 0.1s white | `ViewProgressBar.flash_and_remove()` |
| Floating text duration | 1.5s | `CSpeechBubble.show_event_text()` |
| PCG max bushes | 20 | `PlantPlacer` |
| PCG max carrots | 35 | `PlantPlacer` |
| NPC forage move cost | 5.0 | `GoapAction_MoveToHarvestable` |
| NPC forage harvest cost | 1.0 | `GoapAction_HarvestBush` |
