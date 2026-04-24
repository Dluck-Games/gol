# GOL 环境生物（野兔）设计 — Rabbit Env-Creature System

> **Date:** 2026-04-24
> **Status:** Approved (design)
> **Scope:** v0.3 Resource System expansion
> **Related notes:** `GOL 环境生物`, `GOL 资源系统`, `GOL v0.3 版本规划`, `GOL GOAP 系统`, `GOL 区域`

## Overview

Introduce the first environment creature — the **rabbit** — to bring GOL's resource system to life as a live ecology rather than a static pickup map. This spec delivers one end-to-end vertical slice:

```
PCG places rabbit spawners in non-urban zones
  → Spawners emit rabbits during daytime
    → Rabbits wander peacefully
    → Rabbits flee from any non-neutral entity on sight
    → Rabbits forage grass (runtime-grown) when hungry
    → Rabbits killed → drop food (pickable entity)
      → Player walks over food → camp stockpile gains RFood
        → SAutoFeed consumes stockpile → all PLAYER-camp creatures refill hunger
```

Along the way it lands a handful of reusable primitives — `NEUTRAL` camp, `CLootDrop` + `LootTable`, `CResourcePickup`, `CHunger` + `SHunger` + `SAutoFeed`, `SWorldGrowth` + `GrowthTable`, and the `GOL.Tables` global — that future env creatures (deer, birds, fish) and future gameplay (hunger for all creatures, zombies-eat-rabbits) build on without structural changes.

The rabbit itself is the first tenant of these primitives, not the last.

### Golden decisions carried over from design notes

| From | Decision |
|---|---|
| `GOL 环境生物` | Env creatures exist to feed the resource system AND add interaction richness |
| `GOL 环境生物` | Rabbits flee from player and monsters; advanced: forage plants |
| `GOL v0.3 版本规划` | Wild rabbits drop food resource |
| `GOL 区域` | WILDERNESS/SUBURBS/URBAN; rabbits outside city only |
| `GOL 资源系统` | Creature drops are **renewable** resources |
| `GOL GOAP 系统` | Behavior = GOAP goals + actions; `Flee`/`Wander` exist as templates |

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Faction model | Add `CCamp.CampType.NEUTRAL = 2` | PLAYER/ENEMY binary cannot express "damageable by both, hostile to neither." Ripples into perception (multi-camp enemy set) but damage rules (same-camp-no-friendly-fire) require no change. |
| Perception threat resolution for NEUTRAL | Multi-camp "enemy" as `Array[CampType]` | Natural extension for any future faction (raider gang, friendly NPC). Replaces the binary flip in `SPerception._get_enemy_camp`. |
| Flee behavior for rabbits | New `GoapAction_FleeOnSight` (precondition `has_threat: true`) | Existing `GoapAction_Flee` uses `is_low_health: true` — wrong trigger for prey. Separate action keeps semantics clean. |
| Goal priority structure | 3 goals: `survive_on_sight (100)` > `feed_self (50)` > `wander (1)` | GOAP priority selection replaces manual state machine. Priority order matches behavior: safety first, eat when hungry, otherwise wander. |
| Loot drop mechanism | Runtime `CLootDrop { loot_id: String }` component + `LootTable` data sheet | Runtime component enables transfer (prey → predator, theft, etc.) as future emergent mechanic. Data sheet centralizes tuning. Not coupled to `recipe_id`. |
| Food pickup mechanism | **Dedicated** `CResourcePickup` + `SResourcePickup`, separate from `CContainer` boxes | Box pickup carries weapon/component-merge semantics. Resource pickups are numeric-only — different concern, different lane. |
| Food storage | Camp stockpile (same as wood), new `RFood` resource script | Consistent with existing `RWood` idiom. HUD and multi-consumer plumbing already exist. |
| Pickup collision | Distance-based (radius from player), not Area2D signal | Simpler, fits existing ECS query-per-tick idiom, sufficient for MVP density. |
| Hunger system | New `CHunger` on all creatures + global `SHunger` + per-species `max_hunger` table | Uniform mechanic — every creature carries `CHunger`, per-species tuning via `HungerTable.MAX_HUNGER`. Zombies get `max=10000` (effectively never starve in-session). Future predator/prey loop drops in without structural change. |
| Auto-feed for PLAYER camp | `SAutoFeed` drains stockpile; **prioritized lowest-hunger first**; **atomic consume — skip if deficit < 30** | User-specified rules. "Lowest first" = fairness. "Atomic" = no wasted food (one RFood unit always yields full 30 restored points or doesn't get spent). |
| Grass generation | `SWorldGrowth` ECS system (continuous, runtime) — NOT a PCG phase | PCG runs once at world gen; grass must regrow during play. Zone-filtered (non-URBAN only) via `GrowthTable`. |
| Rabbit spawning | PCG phase `CreatureSpawnerPlacer` scatters `CSpawner` markers, existing `SEnemySpawn` processes them | One-time spawner placement fits the PCG-as-data model. Reuses the proven spawner system (DAY_ONLY already supported). |
| Design data organization | `GOL.Tables.loot() / growth() / hunger()` — autoload slot alongside `Game`/`Player` | Gameplay design sheets are first-class global state. Separates gameplay tuning (GOL.Tables) from non-gameplay config (Config). |
| Placeholder visuals | `CLabelDisplay` + `SLabelDisplay` rendering emoji via Godot `Label` — **MARKED TEMPORARY** | Art deferred; zero PNG files (user directive). Built-in Label supports emoji natively. Component/system carry removal banners; auto-delete when all recipes migrate to real sprites. |
| Pickup flow (player hunger) | Pickup deposits to stockpile; `SAutoFeed` fills hunger from stockpile — **no direct pickup→hunger path** | Clean separation: resource economy ≠ hunger need. Future NPCs eat from same stockpile via same system. |
| Testing scope | ~20 tests: tables (3) + components (4) + systems (6) + GOAP (3) + integration (4) | Table tests as balance guardrails; integration tests covering the end-to-end loop; deliberate exclusion of PCG density and visual rendering. |

## Architecture

```
┌─ Design sheets (GOL.Tables) ────────────────────────────────────────┐
│   scripts/gameplay/tables/                                          │
│   LootTable    — who drops what (keyed by loot_id)                  │
│   GrowthTable  — what grows where, how often (keyed by recipe_id)   │
│   HungerTable  — per-species max_hunger + global rate constants     │
└─────────────────────────────────────────────────────────────────────┘
                ▲ accessed via GOL.Tables.loot() / growth() / hunger()
                │
┌─ New ECS components ────────────────────────────────────────────────┐
│   CCamp            — MODIFIED, adds NEUTRAL=2                       │
│   CLootDrop        — loot_id key; runtime-movable between entities  │
│   CResourcePickup  — resource_type + amount; numeric pickup         │
│   CHunger          — max_hunger + current hunger                    │
│   CEatable         — hunger_restore on consumption                  │
│   CLabelDisplay    — TEMPORARY placeholder emoji renderer           │
└─────────────────────────────────────────────────────────────────────┘
                ▲ read/written by
                │
┌─ New / modified gameplay systems ───────────────────────────────────┐
│   SPerception   — MODIFIED, multi-camp enemy set + blackboard       │
│                   mirrors (has_threat, has_visible_grass)           │
│   SDead         — MODIFIED, _drop_loot() hook reads CLootDrop       │
│   SResourcePickup — distance-based collision → CStockpile           │
│   SHunger       — decay over time, starvation damage                │
│   SAutoFeed     — prioritized, atomic stockpile → hunger refill     │
│   SWorldGrowth  — continuous runtime grass growth (zone-filtered)   │
│   SLabelDisplay — TEMPORARY placeholder renderer                    │
└─────────────────────────────────────────────────────────────────────┘
                ▲ observed by
                │
┌─ GOAP additions ────────────────────────────────────────────────────┐
│   GoapAction_FleeOnSight  — precondition has_threat, runs away      │
│   GoapAction_MoveToGrass  — perception → nearest CEatable           │
│   GoapAction_EatGrass     — adjacency → consume CEatable, restore   │
│   Goals:                                                            │
│     survive_on_sight.tres (pri 100, desired is_safe=true)           │
│     feed_self.tres        (pri 50,  desired is_fed=true)            │
│     wander.tres           (pri 1,   EXISTING — reused)              │
└─────────────────────────────────────────────────────────────────────┘
                ▲ authored by
                │
┌─ Recipes ───────────────────────────────────────────────────────────┐
│   rabbit.tres     — NEUTRAL, CHunger(60), CLootDrop("rabbit"),      │
│                     CPerception, CGoapAgent(3 goals), CLabelDisplay │
│   food_pile.tres  — CResourcePickup(RFood, 1), CLifeTime, emoji 🍖  │
│   grass.tres      — CEatable(30), emoji 🌱                          │
└─────────────────────────────────────────────────────────────────────┘
                ▲ placed by
                │
┌─ Spawn layer ───────────────────────────────────────────────────────┐
│   PCG: new phase CreatureSpawnerPlacer writes spawner specs into    │
│        PCGContext.creature_spawners (per eligible cell roll)        │
│   gol_world.gd: consumes result.creature_spawners, creates          │
│        [CTransform + CSpawner(DAY_ONLY)] entities                   │
│   SEnemySpawn: existing — processes both enemy and creature         │
│        spawners uniformly, emits rabbit entities during daytime     │
│   SWorldGrowth: tick-driven, grows grass in non-URBAN cells         │
└─────────────────────────────────────────────────────────────────────┘
```

## Section 1 — Faction Model

### `CCamp` change

```gdscript
# scripts/components/c_camp.gd
enum CampType {
    PLAYER = 0,
    ENEMY = 1,
    NEUTRAL = 2,   # NEW — wildlife, non-combatants
}
```

### Damage rules (unchanged semantics — "same camp, no friendly fire")

| Attacker → Target | PLAYER | ENEMY | NEUTRAL |
|---|---|---|---|
| **PLAYER** | ❌ | ✅ | ✅ |
| **ENEMY**  | ✅ | ❌ | ✅ |
| **NEUTRAL**| ❌* | ❌* | ❌* |

\* Rabbits have no `CWeapon`, cannot inflict damage.

Implementation note: verify `SDamage` uses `attacker.camp != target.camp` (not `==ENEMY/PLAYER` special cases). Expected change: zero; confirmation done during implementation.

### Perception multi-camp resolution

`SPerception._get_enemy_camp` (returning a single `CampType`) becomes `_get_enemy_camps` (returning `Array[int]`):

```gdscript
func _get_enemy_camps(my_camp: CCamp) -> Array[int]:
    if my_camp == null: return [CCamp.CampType.ENEMY]
    match my_camp.camp:
        CCamp.CampType.PLAYER:  return [CCamp.CampType.ENEMY]
        CCamp.CampType.ENEMY:   return [CCamp.CampType.PLAYER]
        CCamp.CampType.NEUTRAL: return [CCamp.CampType.PLAYER, CCamp.CampType.ENEMY]
    return []

func _is_enemy(candidate: Entity, enemy_camps: Array[int]) -> bool:
    var camp := candidate.get_component(CCamp) as CCamp
    if camp == null or not enemy_camps.has(camp.camp): return false
    return not candidate.has_component(CDead)
```

### Blackboard mirror writes (end of `_process_entity`)

At the end of each perception tick, mirror two flags into the GOAP agent's `world_state`:

```gdscript
var agent := entity.get_component(CGoapAgent) as CGoapAgent
if agent:
    agent.world_state["has_threat"] = perception.nearest_enemy != null
    agent.world_state["has_visible_grass"] = _has_visible_eatable(perception)
```

`_has_visible_eatable` scans `perception._visible_entities` for any entity with `CEatable`.

## Section 2 — GOAP Behavior

### Rabbit's three goals

| Goal (.tres) | Priority | Desired state | Fulfilled by |
|---|---|---|---|
| `survive_on_sight` | 100 | `{is_safe: true}` | `GoapAction_FleeOnSight` |
| `feed_self` | 50 | `{is_fed: true}` | `GoapAction_MoveToGrass` → `GoapAction_EatGrass` |
| `wander` (existing) | 1 | `{has_threat: true}` (impossible — always pursued) | `GoapAction_Wander` (existing) |

GOAP planner picks the highest-priority goal whose desired state isn't already satisfied. The "impossible" desired state on wander is an intentional idiom for fallback/idle behavior (already used by existing wander goal).

### `GoapAction_FleeOnSight`

Parallels existing `GoapAction_Flee` but:
- Precondition: `{has_threat: true}` (not `is_low_health: true`)
- No `CWeapon` lookup — uses `Config.RABBIT_SAFE_DISTANCE` constant (200 px)
- Effect: `{is_safe: true}` when distance to `perception.nearest_enemy` ≥ safe distance

Path: `scripts/gameplay/goap/actions/flee_on_sight.gd`. When there is a threat inside safe distance, sets `CMovement.velocity = -offset.normalized() * max_speed` and returns `false` (keep fleeing). When beyond safe distance or no threat, zeros velocity and returns `true`.

### `GoapAction_MoveToGrass`

- Precondition: `{has_visible_grass: true}`
- Effect: `{adjacent_to_grass: true}` when within a proximity threshold (e.g., 16 px) of nearest `CEatable` in perception
- Implementation: scan `perception._visible_entities` for `CEatable`, pick nearest, set `CMovement.velocity` toward it

### `GoapAction_EatGrass`

- Precondition: `{adjacent_to_grass: true}`
- Effect: `{is_fed: true}`
- On successful adjacency: increment eater's `CHunger.hunger` by grass's `CEatable.hunger_restore`, `cmd.remove_entity(grass_entity)`. No `CDead` pass — grass is consumed, not killed.

### Rabbit recipe composition

```
resources/recipes/rabbit.tres (EntityRecipe)
  recipe_id = "rabbit"
  display_name = "野兔"
  components = [
    CTransform,
    CMovement    { max_speed = 140.0 },
    CHP          { max_hp = 5.0, hp = 5.0 },          # glass cannon
    CCamp        { camp = NEUTRAL },
    CCollision,
    CPerception  { vision_range = 180.0 },
    CGoapAgent   { goals = [survive_on_sight, feed_self, wander] },
    CHunger      { max_hunger = 60.0, hunger = 60.0 },
    CLootDrop    { loot_id = "rabbit" },
    CLabelDisplay{ text = "🐰", font_size = 24 },      # TEMPORARY
  ]
```

Deliberately excluded (not MVP): `CAnimation`, `CSemanticTranslation`, `CMelee`, `CWeapon`, `CElementalAffliction`.

## Section 3 — Hunger System

### `CHunger` component

```gdscript
# scripts/components/c_hunger.gd
class_name CHunger
extends Component

@export var max_hunger: float = 100.0
@export var hunger: float = 100.0
@export var hungry_threshold: float = 0.5      # below → is_hungry
@export var full_threshold: float = 0.9        # above → is_fed
```

### `SHunger` system (universal — all creatures with `CHunger`)

Per-tick:
1. Decay: `hunger -= HungerTable.DECAY_PER_SEC * delta` (clamped ≥ 0)
2. Mirror to GOAP blackboard: `agent.world_state["is_hungry"]` and `["is_fed"]`
3. If `hunger <= 0`: apply `HungerTable.STARVE_DAMAGE_PER_SEC * delta` to `CHP.hp`

### `SAutoFeed` system (PLAYER camp only — stockpile → hunger)

Ticks at `HungerTable.AUTO_FEED_TICK_INTERVAL` (0.5s). Per tick:

1. Collect candidates: entities with `[CHunger, CCamp(PLAYER)]` whose `hunger < max_hunger`
2. Sort ascending by current hunger (lowest first = highest priority)
3. For each candidate:
   - While `deficit >= HUNGER_PER_FOOD_UNIT` AND `stockpile.RFood > 0`:
     - `stockpile.withdraw(RFood, 1)`; `hunger += HUNGER_PER_FOOD_UNIT`
   - If deficit < `HUNGER_PER_FOOD_UNIT`: **skip** this entity (atomic-consume rule). No partial feeds; no wasted units.

**Zombies (ENEMY) don't pass the filter** — they rely on direct eating (future: prey consumption).

### `HungerTable` (global tuning)

```gdscript
# scripts/gameplay/tables/hunger_table.gd
class_name HungerTable
extends Resource

const DECAY_PER_SEC: float = 1.0
const STARVE_DAMAGE_PER_SEC: float = 2.0
const HUNGER_PER_FOOD_UNIT: float = 30.0
const AUTO_FEED_TICK_INTERVAL: float = 0.5

const MAX_HUNGER: Dictionary = {
    "rabbit": 60.0,
    "player": 200.0,
    "zombie": 10000.0,
}

func max_for(recipe_id: String) -> float:
    return float(MAX_HUNGER.get(recipe_id, 100.0))
```

### Hunger ownership summary

| Camp | Creature | Max | Feeds from | System |
|---|---|---|---|---|
| PLAYER | Player | 200 | Camp stockpile (RFood) | `SAutoFeed` |
| PLAYER | Future NPC allies | 150 | Camp stockpile (RFood) | `SAutoFeed` |
| NEUTRAL | Rabbit | 60 | Grass (`CEatable`) | `GoapAction_EatGrass` |
| ENEMY | Zombie | 10000 | *(future: rabbits)* | *(out of scope)* |

## Section 4 — Death, Loot Drop, Pickup

### `CLootDrop` component (runtime identity)

```gdscript
# scripts/components/c_loot_drop.gd
class_name CLootDrop
extends Component

## Key into LootTable.TABLES — identifies which loot profile this entity drops.
## NOT coupled to recipe_id: can be transferred at runtime (predator absorbs
## prey's drop; theft; chain kills) to enable emergent mechanics.
@export var loot_id: String = ""
```

### `LootTable` central sheet

```gdscript
# scripts/gameplay/tables/loot_table.gd
class_name LootTable
extends Resource

## Keyed by loot_id (runtime CLootDrop.loot_id value).
## Entry fields: recipe_id (drop), count_min, count_max, chance, scatter_radius
const TABLES: Dictionary = {
    "rabbit": [
        { recipe_id = "food_pile", count_min = 1, count_max = 1,
          chance = 1.0, scatter_radius = 12.0 },
    ],
}

func get_drops(loot_id: String) -> Array:
    return TABLES.get(loot_id, [])
```

### `SDead._drop_loot` (new helper, called in `_complete_death` before `cmd.remove_entity`)

```gdscript
func _drop_loot(entity: Entity) -> void:
    var loot := entity.get_component(CLootDrop) as CLootDrop
    if loot == null or loot.loot_id == "": return

    var transform := entity.get_component(CTransform) as CTransform
    if transform == null: return

    var drops := GOL.Tables.loot().get_drops(loot.loot_id)
    for entry in drops:
        if randf() > entry.chance: continue
        var n := randi_range(entry.count_min, entry.count_max)
        for i in n:
            var offset := Vector2(
                randf_range(-entry.scatter_radius, entry.scatter_radius),
                randf_range(-entry.scatter_radius, entry.scatter_radius))
            var spawned := ServiceContext.recipe().create_entity_by_id(entry.recipe_id)
            if spawned:
                var t := spawned.get_component(CTransform) as CTransform
                if t: t.position = transform.position + offset
```

### `food_pile` recipe

```
resources/recipes/food_pile.tres
  recipe_id = "food_pile"
  display_name = "食物"
  components = [
    CTransform,
    CCollision       { shape = CircleShape2D(radius = 10) },
    CResourcePickup  { resource_type = RFood, amount = 1 },
    CLifeTime        { lifetime = Config.RESOURCE_PICKUP_LIFETIME },  # 120s
    CLabelDisplay    { text = "🍖", font_size = 20 },   # TEMPORARY
  ]
```

### `CResourcePickup` component

```gdscript
# scripts/components/c_resource_pickup.gd
class_name CResourcePickup
extends Component

@export var resource_type: Script     # RWood / RFood / etc.
@export var amount: int = 1
```

### `SResourcePickup` system (distance-based collision, PLAYER as receiver)

Per tick:
1. Find player entity: `ECS.world.query.with_all([CPlayer, CTransform]).execute()`; bail if not found
2. Query `[CResourcePickup, CTransform, CCollision]`
3. For each pickup entity:
   - Skip if `CDead` present
   - Compute squared distance to player; skip if greater than `Config.RESOURCE_PICKUP_RADIUS * Config.RESOURCE_PICKUP_RADIUS` (radius = 24 px). Use squared values on both sides to avoid the sqrt.
   - Check `stockpile.can_accept(resource_type, amount)`; skip if full
   - `stockpile.add(resource_type, amount)`; `cmd.remove_entity(pickup_entity)`

### `RFood` resource script (mirror of `RWood`)

```gdscript
# scripts/resources/r_food.gd
class_name RFood
extends Resource

const DISPLAY_NAME: String = "食物"
const ICON_PATH: String = "res://assets/icons/resources/food.png"   # placeholder path
const MAX_STACK: int = 999
```

## Section 5 — Spawning & World Growth

### `CreatureSpawnerPlacer` — new PCG phase

```gdscript
# scripts/pcg/phases/creature_spawner_placer.gd
class_name CreatureSpawnerPlacer
extends PCGPhase

const RABBIT_PER_CELL_CHANCE: float = 0.015

func execute(config: PCGConfig, context: PCGContext) -> void:
    var rng := context.get_rng()
    for cell in context.zone_map.zones:
        var zone := context.zone_map.get_zone(cell)
        if zone == ZoneMap.ZoneType.URBAN: continue
        if rng.randf() > RABBIT_PER_CELL_CHANCE: continue
        context.add_creature_spawner({
            recipe_id = "rabbit",
            cell = cell,
            active_condition = CSpawner.ActiveCondition.DAY_ONLY,
            spawn_interval = 30.0,
            spawn_radius = 128.0,
            max_spawn_count = 3,
        })
```

**Registered** in the PCG pipeline **after** `ZoneSmoother` (zones must exist). Writes to `PCGContext.creature_spawners: Array[Dictionary]`. `PCGResult` exposes the same field.

### `gol_world.gd` — instantiate spawners from PCG result

Small loop added to the world-build sequence (where trees are currently placed):

```gdscript
for spec in pcg_result.creature_spawners:
    var entity := Entity.new()
    entity.name = StringName("creature_spawner_%s" % spec.recipe_id)
    var t := CTransform.new()
    t.position = _cell_to_world(spec.cell)
    entity.add_component(t)
    var sp := CSpawner.new()
    sp.spawn_recipe_id = spec.recipe_id
    sp.spawn_interval = spec.spawn_interval
    sp.spawn_interval_variance = spec.spawn_interval * 0.2
    sp.spawn_count = 1
    sp.spawn_radius = spec.spawn_radius
    sp.max_spawn_count = spec.max_spawn_count
    sp.active_condition = spec.active_condition
    entity.add_component(sp)
    ECS.world.add_entity(entity)
```

Creature spawners have **no `CHP`** — they're passive infrastructure, not destructible buildings. Implementation note: verify `SEnemySpawn` does not require `CHP` on the spawner entity; add a null-guard if it does.

### `SWorldGrowth` — continuous grass regrowth

**Not a PCG phase** — grass grows during gameplay, not at world gen.

```gdscript
# scripts/systems/s_world_growth.gd
class_name SWorldGrowth
extends System

var _timers: Dictionary = {}

func query() -> QueryBuilder:
    return q.with_none([])  # system-level tick, logic inside

func process(_entities, _c, delta):
    var zone_map: ZoneMap = ServiceContext.world().get_zone_map()
    if zone_map == null: return

    for recipe_id in GOL.Tables.growth().all().keys():
        var rule := GOL.Tables.growth().get_rule(recipe_id)
        _timers[recipe_id] = _timers.get(recipe_id, 0.0) + delta
        if _timers[recipe_id] < rule.interval_sec: continue
        _timers[recipe_id] = 0.0
        _attempt_spawn(zone_map, recipe_id, rule)
```

`_attempt_spawn` counts live instances of `recipe_id`, enforces `world_cap`, rolls `per_cell_chance` per eligible cell, creates the entity via `ServiceContext.recipe().create_entity_by_id()`.

### `GrowthTable`

```gdscript
# scripts/gameplay/tables/growth_table.gd
class_name GrowthTable
extends Resource

const TABLES: Dictionary = {
    "grass": {
        zones = [ZoneMap.ZoneType.WILDERNESS, ZoneMap.ZoneType.SUBURBS],
        interval_sec = 8.0,
        per_cell_chance = 0.02,
        world_cap = 60,
    },
    # Future: "tree", "berry_bush", ...
}

func all() -> Dictionary: return TABLES
func get_rule(recipe_id: String) -> Dictionary: return TABLES.get(recipe_id, {})
```

### `grass` recipe

```
resources/recipes/grass.tres
  recipe_id = "grass"
  display_name = "草"
  components = [
    CTransform,
    CCollision     { shape = CircleShape2D(radius = 12) },
    CEatable       { hunger_restore = 30.0 },
    CLifeTime      { lifetime = 300.0 },                # stale-grass despawn
    CLabelDisplay  { text = "🌱", font_size = 20 },     # TEMPORARY
  ]
```

### `CEatable` component

```gdscript
# scripts/components/c_eatable.gd
class_name CEatable
extends Component

@export var hunger_restore: float = 20.0
```

## Section 6 — Placeholder Visuals (Temporary)

### `CLabelDisplay` — temporary component

```gdscript
# scripts/components/c_label_display.gd
class_name CLabelDisplay
extends Component

## --------------------------------------------------------------
## !!! TEMPORARY PLACEHOLDER — REMOVE WHEN ART LANDS !!!
##
## Renders emoji/text visuals for entities without production
## sprites. Enables the rabbit/grass/food_pile mechanics to ship
## fully playable without any PNG production.
##
## Migration:
##   1. Add a real CSprite (or CAnimation) to the recipe.
##   2. Remove CLabelDisplay from the recipe.
##   3. When all three recipes migrate, delete this file and
##      s_label_display.gd.
##
## Do NOT build production gameplay around this component.
## --------------------------------------------------------------

@export var text: String = ""
@export var font_size: int = 24
@export var color: Color = Color.WHITE
@export var outline_size: int = 2
@export var outline_color: Color = Color.BLACK
```

### `SLabelDisplay` — temporary renderer

- Query: `[CLabelDisplay, CTransform]`
- On first tick per entity: create `Label` child, set `text`/`theme_override_font_sizes/font_size`/`theme_override_colors`/outline; center via `label.pivot_offset = label.size/2`; `entity.add_child(label)`
- Subsequent ticks: `label.position = CTransform.position - label.size/2`

Same **TEMPORARY** banner at the top. When `CLabelDisplay` is removed from all recipes, delete both files.

### Death visual interaction

`SDead._find_sprite` only searches for `Sprite2D`/`AnimatedSprite2D` children. Entities with only a `Label` return `null` → `SDead._complete_death` fires immediately (no tween animation). Rabbit dies → vanishes → loot drops. This is **correct behavior** for placeholder visuals.

## Section 7 — GOL.Tables Global

### Autoload addition

```gdscript
# scripts/gol.gd (modified)
extends Node

const PlayerData = preload("res://scripts/gameplay/player_data.gd")
const GameTables = preload("res://scripts/gameplay/game_tables.gd")    # NEW

var Game: GOLGameState = null
var Player: PlayerData = null
var Tables: GameTables = null                                           # NEW

func setup() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    ServiceContext.static_setup(get_tree().get_root())
    Game = GOLGameState.new()
    Player = PlayerData.new()
    Tables = GameTables.new()

func teardown() -> void:
    ServiceContext.static_teardown()
    Game.free(); Player.free(); Tables.free()
    Game = null; Player = null; Tables = null
```

### `GameTables` aggregator

```gdscript
# scripts/gameplay/game_tables.gd
class_name GameTables
extends Object

var _loot: LootTable = null
var _growth: GrowthTable = null
var _hunger: HungerTable = null

func _init() -> void:
    _loot = LootTable.new()
    _growth = GrowthTable.new()
    _hunger = HungerTable.new()

func loot() -> LootTable: return _loot
func growth() -> GrowthTable: return _growth
func hunger() -> HungerTable: return _hunger
```

### Where tuning lives

| Goes in `Config` | Goes in `GOL.Tables` |
|---|---|
| `PLAYER_RESPAWN_DELAY` | Loot drop entries (LootTable) |
| `DEATH_REMOVE_COMPONENTS` | Grass growth intervals (GrowthTable) |
| `RESOURCE_PICKUP_RADIUS` (24) | Hunger decay rates (HungerTable) |
| `RESOURCE_PICKUP_LIFETIME` (120) | Per-species max_hunger |
| `RABBIT_SAFE_DISTANCE` (200) | |
| Engine/UI paths, scalar constants | Structured per-species design data |

**Rule:** scalar + non-tabular → `Config`. Per-species or per-entry tables → `GOL.Tables`.

## Section 8 — Debug Console Additions

### Existing: zero code changes needed for entity spawn

`spawn_command.gd` already handles arbitrary recipe IDs via `create_entity_by_id`:

```
> spawn entity rabbit
> spawn entity grass
> spawn entity food_pile
```

All three work the moment the recipes exist.

### New: `hunger` debug command

```gdscript
# scripts/debug/console/commands/hunger_command.gd
class_name HungerCommand
extends ConsoleCommandModule

func build() -> Array:
    return [
        Spec.CommandSpec.category("hunger", "Hunger debug", [
            Spec.SubcommandSpec.new("set",
                "Set an entity's hunger value",
                [
                    Spec.ParamSpec.required("target", Types.ENTITY),
                    Spec.ParamSpec.required("value", Types.FLOAT),
                ],
                Callable(self, "_set_hunger")),
            Spec.SubcommandSpec.new("stockpile",
                "Add food to camp stockpile",
                [Spec.ParamSpec.optional("amount", Types.INT, 10)],
                Callable(self, "_add_stockpile_food")),
        ])
    ]
```

Registered at the same registration site where `SpawnCommand`, `DamageCommand` register (detail found during implementation).

## Section 9 — Testing Strategy

**~20 tests, organized by layer.** All follow the existing Blocky framework.

### Unit — Tables (`tests/unit/tables/`)

- `test_loot_table.gd` — schema contract; `chance ∈ [0,1]`; `count_min ≤ count_max`
- `test_growth_table.gd` — zone arrays non-empty; `world_cap > 0`
- `test_hunger_table.gd` — `max_for(rabbit) < max_for(player) < max_for(zombie)`; rate constants positive

### Unit — Components (`tests/unit/components/`)

- `test_c_camp.gd` — NEUTRAL=2; default PLAYER
- `test_c_loot_drop.gd` — default empty `loot_id`; field exported
- `test_c_hunger.gd` — default `hunger = max_hunger`; thresholds bounded
- `test_c_eatable.gd` — default `hunger_restore = 20`

### Unit — Systems (`tests/unit/systems/`)

- `test_s_hunger.gd` — decay rate; starvation damage; blackboard mirrors
- `test_s_auto_feed.gd` — prioritization (lowest first); atomic consume (skip when deficit < 30); multi-unit consumption up to deficit
- `test_s_resource_pickup.gd` — distance threshold (inside: pickup, outside: no); stockpile cap respected
- `test_s_dead_loot_drop.gd` — with CLootDrop → food_pile spawned; without → no drop; unknown loot_id → no drop (silent)
- `test_s_world_growth.gd` — zone filter (URBAN skipped); `world_cap` enforced
- `test_s_perception_neutral.gd` — rabbit perceives both PLAYER and ENEMY; nearest wins; `has_threat` blackboard set

### Unit — GOAP actions (`tests/unit/goap/`)

- `test_flee_on_sight.gd` — within safe_distance: flee away; beyond: is_safe=true; no threat: is_safe=true
- `test_move_to_grass.gd` — visible grass: velocity toward nearest; no grass: no-op
- `test_eat_grass.gd` — adjacent: grass removed, hunger increased; not adjacent: preconditions unmet

### Integration — Scenarios (`tests/integration/creatures/`)

- `test_rabbit_lifecycle.gd` — spawn, wander, flee from zombie, killed, food_pile dropped
- `test_food_pickup_to_stockpile.gd` — food_pile + player → stockpile.RFood += 1; HUD reflects
- `test_auto_feed_loop.gd` — hungry player + stockpile → hunger refills by `HUNGER_PER_FOOD_UNIT × n`; no food → decay continues
- `test_rabbit_forages_grass.gd` — hungry rabbit + visible grass → rabbit moves to grass, eats it, hunger refilled

### Deliberately NOT tested (YAGNI)

- PCG rabbit-spawner density (playtest-verified, seeded-deterministic)
- Label visual rendering (temporary)
- Hunger tuning balance (playtest territory)
- `SDead` interactions with non-rabbit creatures (covered by existing tests; our hook is additive)

### Manual smoke plan (pre-merge)

1. Fresh PCG world: 🐰 labels in WILDERNESS/SUBURBS during day; none in URBAN
2. Approach rabbit → flees at ~140 px/s
3. Shoot rabbit → dies, 🍖 appears at death position
4. Walk over 🍖 → HUD RFood counter increments
5. Idle: hunger ticks down; with enough RFood, SAutoFeed refills player hunger
6. Night: no new rabbit spawns (DAY_ONLY); existing rabbits remain until killed
7. Wait in WILDERNESS/SUBURBS → 🌱 grass sprouts
8. Hungry rabbit → walks to grass → eats → grass vanishes
9. Console: `/spawn entity rabbit`, `/spawn entity food_pile`, `/hunger set <player> 10`, `/hunger stockpile 10`

## Section 10 — File Summary

### New files

```
scripts/gameplay/game_tables.gd                        (GOL.Tables aggregator)
scripts/gameplay/tables/loot_table.gd
scripts/gameplay/tables/growth_table.gd
scripts/gameplay/tables/hunger_table.gd

scripts/components/c_loot_drop.gd
scripts/components/c_resource_pickup.gd
scripts/components/c_hunger.gd
scripts/components/c_eatable.gd
scripts/components/c_label_display.gd                  (TEMPORARY)

scripts/systems/s_resource_pickup.gd
scripts/systems/s_hunger.gd
scripts/systems/s_auto_feed.gd
scripts/systems/s_world_growth.gd
scripts/systems/s_label_display.gd                     (TEMPORARY)

scripts/gameplay/goap/actions/flee_on_sight.gd
scripts/gameplay/goap/actions/move_to_grass.gd
scripts/gameplay/goap/actions/eat_grass.gd

scripts/resources/r_food.gd

scripts/pcg/phases/creature_spawner_placer.gd

scripts/debug/console/commands/hunger_command.gd

resources/recipes/rabbit.tres
resources/recipes/food_pile.tres
resources/recipes/grass.tres
resources/goals/survive_on_sight.tres
resources/goals/feed_self.tres

tests/unit/tables/test_loot_table.gd
tests/unit/tables/test_growth_table.gd
tests/unit/tables/test_hunger_table.gd
tests/unit/components/test_c_camp.gd              (extend if exists)
tests/unit/components/test_c_loot_drop.gd
tests/unit/components/test_c_hunger.gd
tests/unit/components/test_c_eatable.gd
tests/unit/systems/test_s_hunger.gd
tests/unit/systems/test_s_auto_feed.gd
tests/unit/systems/test_s_resource_pickup.gd
tests/unit/systems/test_s_dead_loot_drop.gd
tests/unit/systems/test_s_world_growth.gd
tests/unit/systems/test_s_perception_neutral.gd
tests/unit/goap/test_flee_on_sight.gd
tests/unit/goap/test_move_to_grass.gd
tests/unit/goap/test_eat_grass.gd
tests/integration/creatures/test_rabbit_lifecycle.gd
tests/integration/creatures/test_food_pickup_to_stockpile.gd
tests/integration/creatures/test_auto_feed_loop.gd
tests/integration/creatures/test_rabbit_forages_grass.gd
```

### Modified files

```
scripts/gol.gd                                         (Tables slot)
scripts/components/c_camp.gd                           (NEUTRAL enum)
scripts/systems/s_perception.gd                        (multi-camp + blackboard mirrors)
scripts/systems/s_dead.gd                              (_drop_loot helper)
scripts/gameplay/ecs/gol_world.gd                      (consume creature_spawners)
scripts/pcg/pipeline/pcg_context.gd                    (creature_spawners buffer)
scripts/pcg/data/pcg_result.gd                         (expose creature_spawners)
scripts/pcg/pipeline/pcg_pipeline.gd                   (register phase)
scripts/configs/config.gd                              (+ RABBIT_SAFE_DISTANCE,
                                                         RESOURCE_PICKUP_RADIUS,
                                                         RESOURCE_PICKUP_LIFETIME)
scripts/ui/viewmodels/viewmodel_hud.gd                 (RFood binding)
```

## Open Implementation Questions

These are not design holes — they are verification points for the plan phase:

1. **`create_entity_by_id` signature** — does it accept a position override, or do we set `CTransform.position` after creation? (Used in `_drop_loot`, pickup creation, spawner instantiation.)
2. **`SDamage` camp equality check** — confirm it uses `!=` not `==ENEMY/PLAYER`. Expected: zero change.
3. **`SEnemySpawn` `CHP` assumption** — confirm creature spawners without CHP don't break the spawner tick.
4. **`ServiceContext.world().get_zone_map()` availability** — verify the accessor exists or add it; SWorldGrowth depends on it.
5. **`ServiceContext.camp().get_stockpile()`** — verify the camp service exposes the stockpile entity's component; SAutoFeed and SResourcePickup both depend on it.
6. **`PCGContext.get_rng()`** — verify the deterministic RNG accessor; if not present, add alongside the creature_spawners buffer.
7. **Console command registration site** — find where existing commands register (`SpawnCommand`, `DamageCommand`) and register `HungerCommand` alongside.
8. **RFood icon** — placeholder path `res://assets/icons/resources/food.png` may not exist; either create a minimal placeholder PNG (contradicts user directive), or leave `ICON_PATH` empty and handle null in HUD, or reuse an existing icon. Decision deferred to implementation.

## Out of Scope (Explicitly Deferred)

- **Zombies eat rabbits + heal** — requires zombie GOAP extensions, prey detection via NEUTRAL camp, heal-on-kill. Data model in this spec supports it; behavior is a follow-up.
- **`CLootDrop` transfer mechanic** — component is designed for transfer (predator absorbs prey's drop) but the transfer system is not implemented.
- **Hunger effects beyond starvation damage** — no movement/combat penalties for low hunger.
- **Production art** — `CLabelDisplay` covers visibility; sprite production is a later art pass.
- **Grass-as-`CResourceNode`** — grass is consumed directly by `GoapAction_EatGrass`, not harvested via the resource-node pipeline. If NPCs ever farm grass for camp food, that's a refactor.
- **PCG rabbit density tuning** — `RABBIT_PER_CELL_CHANCE = 0.015` is a first guess; real tuning happens after playtest.
- **Multi-biome growth rules** — `GrowthTable` currently distinguishes by `ZoneType` only; future biomes (forest, desert) would add a biome axis.

## Acceptance Criteria

The spec is complete when all of the following can be demonstrated on a fresh PCG world:

- [ ] Rabbits spawn during day, only in non-URBAN zones
- [ ] Rabbits flee from player (approach → rabbit runs)
- [ ] Rabbits flee from zombies (the zombie doesn't need to target them for rabbit to flee)
- [ ] Rabbits wander when no threats are visible
- [ ] Shooting a rabbit kills it; a food_pile appears at death position
- [ ] Walking over a food_pile increments the camp RFood stockpile
- [ ] Player hunger decays over time
- [ ] When player hunger deficit ≥ 30 and RFood > 0, stockpile is drained and hunger restored
- [ ] Grass grows in non-URBAN zones over time (up to `world_cap`)
- [ ] Hungry rabbits walk to grass and eat it, consuming the grass and restoring their own hunger
- [ ] All ~20 automated tests pass
- [ ] Debug commands `spawn entity rabbit`, `spawn entity grass`, `spawn entity food_pile`, `hunger set <e> <v>`, `hunger stockpile <n>` all work
