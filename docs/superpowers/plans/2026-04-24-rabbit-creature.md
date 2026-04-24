# Rabbit Env-Creature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the first environment creature (rabbit) end-to-end — PCG spawner placement, GOAP-driven flee/forage behavior, food drop, camp stockpile pickup, hunger system for all creatures, runtime grass growth — with placeholder emoji visuals.

**Architecture:** Add `CCamp.NEUTRAL`, six new ECS components (`CHunger`, `CEatable`, `CLootDrop`, `CResourcePickup`, `CLabelDisplay`), seven new/modified systems, three new GOAP actions, a new PCG phase, three design sheets under a new `GOL.Tables` global, and three entity recipes. Everything is data-driven: loot rules, growth rules, and hunger tuning live in editable tables.

**Tech Stack:** GDScript / Godot 4.6, GECS addon, existing GOAP planner, gdUnit4 (unit + integration tests), PCG pipeline phases, console command framework.

**Spec:** `docs/superpowers/specs/2026-04-24-rabbit-creature-design.md`

**Branch:** All work happens on `feat/resource-system` in the `gol-project` submodule (user-specified — no worktree for this feature).

---

## Pre-flight: Read These First

Before starting Task 1, the implementing agent should read these for orientation:

1. **Spec:** `docs/superpowers/specs/2026-04-24-rabbit-creature-design.md` — non-negotiable. Every design decision lives there.
2. **Testing rules:** `gol-project/tests/AGENTS.md` — three-tier test architecture and delegation rules.
3. **Component catalog:** `gol-project/scripts/components/AGENTS.md` — existing component patterns.
4. **System patterns:** `gol-project/scripts/systems/AGENTS.md` — query shape, group assignment.
5. **GOAP architecture:** `gol-project/scripts/gameplay/AGENTS.md` — existing facts, goals, action patterns, blackboard conventions.
6. **PCG orientation:** `gol-project/scripts/pcg/AGENTS.md` — pipeline phase structure.
7. **Resource system predecessor plan:** `docs/superpowers/plans/2026-04-14-resource-system.md` — the `CStockpile` / `RWood` / worker GOAP pattern this plan extends.

**Testing delegation rule (from `gol/CLAUDE.md` / `AGENTS.md`):** Main agents **never** write or run tests directly. Delegate:

| Task | Skill | Model |
|---|---|---|
| Write unit test | `gol-test-writer` (unit) | sonnet |
| Write integration test | `gol-test-writer` (integration) | sonnet |
| Run existing tests | `gol-test-runner` (runner) | haiku |
| Manual playtest | `gol-test-runner` (playtest) | sonnet |

Steps in this plan that say "write test" / "run test" MUST be dispatched via that pattern, not by editing test files directly.

**Godot parse-check command (used to verify no script errors after GDScript changes):**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

---

## File Structure

### New files (44)

**Design sheets under `GOL.Tables` (4):**
- `scripts/gameplay/game_tables.gd` (aggregator)
- `scripts/gameplay/tables/loot_table.gd`
- `scripts/gameplay/tables/growth_table.gd`
- `scripts/gameplay/tables/hunger_table.gd`

**Resource type class (1):**
- `scripts/resources/r_food.gd`

**ECS components (5):**
- `scripts/components/c_loot_drop.gd`
- `scripts/components/c_resource_pickup.gd`
- `scripts/components/c_hunger.gd`
- `scripts/components/c_eatable.gd`
- `scripts/components/c_label_display.gd` (TEMPORARY placeholder)

**ECS systems (5):**
- `scripts/systems/s_resource_pickup.gd`
- `scripts/systems/s_hunger.gd`
- `scripts/systems/s_auto_feed.gd`
- `scripts/systems/s_world_growth.gd`
- `scripts/systems/s_label_display.gd` (TEMPORARY)

**GOAP actions (3):**
- `scripts/gameplay/goap/actions/flee_on_sight.gd` → `class_name GoapAction_FleeOnSight`
- `scripts/gameplay/goap/actions/move_to_grass.gd` → `class_name GoapAction_MoveToGrass`
- `scripts/gameplay/goap/actions/eat_grass.gd` → `class_name GoapAction_EatGrass`

**GOAP goals (2):**
- `resources/goals/survive_on_sight.tres`
- `resources/goals/feed_self.tres`

**Entity recipes (3):**
- `resources/recipes/rabbit.tres`
- `resources/recipes/food_pile.tres`
- `resources/recipes/grass.tres`

**PCG phase (1):**
- `scripts/pcg/phases/creature_spawner_placer.gd`

**Debug console command (1):**
- `scripts/debug/console/commands/hunger_command.gd`

**Unit tests (13):**
- `tests/unit/tables/test_loot_table.gd`
- `tests/unit/tables/test_growth_table.gd`
- `tests/unit/tables/test_hunger_table.gd`
- `tests/unit/test_c_loot_drop.gd`
- `tests/unit/test_c_hunger.gd`
- `tests/unit/test_c_eatable.gd`
- `tests/unit/test_s_hunger.gd`
- `tests/unit/test_s_auto_feed.gd`
- `tests/unit/test_s_resource_pickup.gd`
- `tests/unit/test_s_dead_loot_drop.gd`
- `tests/unit/test_s_world_growth.gd`
- `tests/unit/test_goap_action_flee_on_sight.gd`
- `tests/unit/test_goap_action_eat_grass.gd`

**Integration tests (4):**
- `tests/integration/creatures/test_rabbit_lifecycle.gd`
- `tests/integration/creatures/test_food_pickup_to_stockpile.gd`
- `tests/integration/creatures/test_auto_feed_loop.gd`
- `tests/integration/creatures/test_rabbit_forages_grass.gd`

### Modified files (11)

- `scripts/gol.gd` — add `Tables: GameTables` slot
- `scripts/components/c_camp.gd` — add `NEUTRAL = 2` enum value
- `scripts/systems/s_perception.gd` — multi-camp enemy set; blackboard mirrors (`has_threat`, `has_visible_grass`)
- `scripts/systems/s_dead.gd` — add `_drop_loot()` helper hooked in `_complete_death`
- `scripts/gameplay/ecs/gol_world.gd` — consume `pcg_result.creature_spawners` to create spawner entities
- `scripts/pcg/pipeline/pcg_context.gd` — add `creature_spawners: Array[Dictionary]` buffer + `add_creature_spawner(spec)`
- `scripts/pcg/data/pcg_result.gd` — expose `creature_spawners`
- `scripts/pcg/pipeline/pcg_pipeline.gd` (OR its registration call-site) — register `CreatureSpawnerPlacer` phase after `ZoneSmoother`
- `scripts/configs/config.gd` — add `RABBIT_SAFE_DISTANCE`, `RESOURCE_PICKUP_RADIUS`, `RESOURCE_PICKUP_LIFETIME`
- `scripts/ui/viewmodels/viewmodel_hud.gd` — add `RFood` binding mirroring the `RWood` pattern
- `scripts/debug/console/console_registry.gd` — add `HungerCommand` to `_MODULES` array

**Not modified** (verified during design): `scripts/systems/s_damage.gd` (already uses `!= camp`), `scripts/systems/s_enemy_spawn.gd` (already works without `CHP`).

---

## Notes on Verified Implementation Details

These findings from the exploration pass pre-resolve spec's "Open Implementation Questions":

1. **`ServiceContext.recipe().create_entity_by_id(id)` returns `Entity`** — no position parameter. Caller sets `CTransform.position` after. (`scripts/services/impl/service_recipe.gd:108`)
2. **`SDamage` friendly-fire check** uses `target.get_component(CCamp).camp != owner_camp` — works for NEUTRAL with zero modification. (`scripts/systems/s_damage.gd:177–186`)
3. **`SEnemySpawn.query()`** requires only `[CSpawner, CTransform]` — no CHP needed on creature spawners. (`scripts/systems/s_enemy_spawn.gd:14–15`)
4. **`ServiceContext.pcg().get_zone_map()`** is the runtime ZoneMap accessor (not `world()`). (`scripts/services/impl/service_pcg.gd:28–31`)
5. **No `ServiceContext.camp()` exists** — camp stockpile is accessed via ECS query. Pattern from `viewmodel_hud.gd:58`:
   ```gdscript
   var camp_entity := ECS.world.query.with_all([CStockpile]).with_none([CPlayer]).execute()[0]
   var stockpile := camp_entity.get_component(CStockpile)
   ```
6. **`PCGContext`** exposes `randf()`, `randi()`, `randi_range(from, to)`, `randf_range(from, to)` passthrough methods. (`scripts/pcg/pipeline/pcg_context.gd:54–67`)
7. **Console commands** are registered by preloading into `_MODULES` array at `scripts/debug/console/console_registry.gd:12–20`.
8. **No RFood icon exists.** `food.png` asset is out of scope (per user directive: no PNG creation). `RFood.ICON_PATH` will be an empty string; HUD handles null gracefully.

---

## Phase 1 — Foundation (Task 1–7)

These tasks land primitives with no gameplay-visible behavior yet. Each is independently testable and commits on completion.

### Task 1: Add `NEUTRAL` to `CCamp`

**Files:**
- Modify: `scripts/components/c_camp.gd`

- [ ] **Step 1: Read current file**

Read `scripts/components/c_camp.gd` to confirm current state (should be a 2-value enum).

- [ ] **Step 2: Add `NEUTRAL = 2`**

Replace file contents with:
```gdscript
class_name CCamp
extends Component


enum CampType {
	PLAYER = 0,
	ENEMY = 1,
	NEUTRAL = 2,  # wildlife, non-combatants; damageable by both other camps
}

@export var camp: CampType = CampType.PLAYER
```

- [ ] **Step 3: Godot parse check**

Run:
```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```
Expected: `No parse errors`.

- [ ] **Step 4: Delegate unit test update**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_c_camp.gd` (create if absent). Tests required:
> 1. Default `camp` equals `CCamp.CampType.PLAYER` (0)
> 2. Enum contains `CCamp.CampType.NEUTRAL` with value 2
> 3. Round-trip: setting `camp = CCamp.CampType.NEUTRAL` and reading back yields 2

- [ ] **Step 5: Delegate test run**

Dispatch to `gol-test-runner`:
> Run `tests/unit/test_c_camp.gd`. Expect PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
git add scripts/components/c_camp.gd tests/unit/test_c_camp.gd
git commit -m "feat(camp): add NEUTRAL=2 to CCamp.CampType

Enables wildlife/non-combatant entities. Damage rules already use
!=camp equality, so NEUTRAL is damageable by both PLAYER and ENEMY
with no change to SDamage."
```

---

### Task 2: Add `RFood` resource type

**Files:**
- Create: `scripts/resources/r_food.gd`

No tests — const-only class mirroring `RWood`.

- [ ] **Step 1: Create `r_food.gd`**

```gdscript
# scripts/resources/r_food.gd
class_name RFood
extends Resource

const DISPLAY_NAME: String = "食物"
## Empty string = no icon (HUD must handle null/empty).
## Production art is out of scope; placeholder visuals handle in-world food.
const ICON_PATH: String = ""
const MAX_STACK: int = 999
```

- [ ] **Step 2: Godot parse check**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```
Expected: `No parse errors`.

- [ ] **Step 3: Commit**

```bash
git add scripts/resources/r_food.gd
git commit -m "feat(resource): add RFood resource type

Parallels RWood const-only pattern. ICON_PATH empty for now — icon
production deferred; placeholder emoji visuals cover world rendering."
```

---

### Task 3: Add `Config` constants for rabbit/pickup

**Files:**
- Modify: `scripts/configs/config.gd`

- [ ] **Step 1: Read current `config.gd`**

Read the full file to find the appropriate section to add scalars.

- [ ] **Step 2: Add constants**

Append (or add in logical grouping) the following to `scripts/configs/config.gd`:

```gdscript
## Rabbit behavior
const RABBIT_SAFE_DISTANCE: float = 200.0   ## px; rabbit flees until threat is farther than this

## Resource pickup (numeric pickups, distinct from CContainer boxes)
const RESOURCE_PICKUP_RADIUS: float = 24.0        ## px; distance-based collision with receiver
const RESOURCE_PICKUP_LIFETIME: float = 120.0     ## s; pickup despawns if not collected
```

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/configs/config.gd
git commit -m "feat(config): add rabbit behavior + resource pickup constants

RABBIT_SAFE_DISTANCE: how far rabbits flee before stopping.
RESOURCE_PICKUP_RADIUS / LIFETIME: for distance-based numeric pickups
(food piles and future berries/water). Scalar tunables belong here;
per-species tables live under GOL.Tables."
```

---

### Task 4: Create `LootTable` design sheet

**Files:**
- Create: `scripts/gameplay/tables/loot_table.gd`
- Test: `tests/unit/tables/test_loot_table.gd`

- [ ] **Step 1: Create `scripts/gameplay/tables/` directory and `loot_table.gd`**

```gdscript
# scripts/gameplay/tables/loot_table.gd
class_name LootTable
extends Resource
## Central loot configuration for all drop-capable entities.
## Keyed by loot_id (CLootDrop.loot_id value, NOT recipe_id —
## loot_id can be transferred between entities at runtime).

## Each entry fields:
##   recipe_id:      String (which entity to spawn as drop)
##   count_min:      int
##   count_max:      int
##   chance:         float in [0.0, 1.0]
##   scatter_radius: float px (jitter around death pos)
const TABLES: Dictionary = {
	"rabbit": [
		{
			recipe_id = "food_pile",
			count_min = 1,
			count_max = 1,
			chance = 1.0,
			scatter_radius = 12.0,
		},
	],
}


## Resolve a loot_id to its drop entries, or empty array if unknown.
func get_drops(loot_id: String) -> Array:
	return TABLES.get(loot_id, [])
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/tables/test_loot_table.gd`. Tests required:
> 1. `LootTable.new().get_drops("rabbit")` returns a non-empty array.
> 2. The rabbit entry has fields: `recipe_id`, `count_min`, `count_max`, `chance`, `scatter_radius`.
> 3. `get_drops("nonexistent_id")` returns an empty array.
> 4. For every entry in every table: `0.0 <= chance <= 1.0`; `count_min <= count_max`; `recipe_id != ""`; `scatter_radius >= 0.0`.

- [ ] **Step 4: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/tables/test_loot_table.gd`. Expect PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay/tables/loot_table.gd tests/unit/tables/test_loot_table.gd
git commit -m "feat(tables): add LootTable design sheet

Central keyed-by-loot_id drop config. Table schema supports
multi-entry (composite drops) and probabilistic drops for future
creatures. Rabbit is the first tenant."
```

---

### Task 5: Create `GrowthTable` design sheet

**Files:**
- Create: `scripts/gameplay/tables/growth_table.gd`
- Test: `tests/unit/tables/test_growth_table.gd`

- [ ] **Step 1: Create `growth_table.gd`**

```gdscript
# scripts/gameplay/tables/growth_table.gd
class_name GrowthTable
extends Resource
## Things that grow (spawn naturally over time) in the world.
## Read by SWorldGrowth. Keyed by recipe_id of the spawned entity.

## Each rule fields:
##   zones:            Array[ZoneMap.ZoneType] — eligible zones
##   interval_sec:     float — seconds between per-cell rolls
##   per_cell_chance:  float in [0,1] — roll per eligible cell per interval
##   world_cap:        int > 0 — max live instances of this recipe worldwide
const TABLES: Dictionary = {
	"grass": {
		zones = [ZoneMap.ZoneType.WILDERNESS, ZoneMap.ZoneType.SUBURBS],
		interval_sec = 8.0,
		per_cell_chance = 0.02,
		world_cap = 60,
	},
}


## All growth rules (recipe_id -> rule dict).
func all() -> Dictionary:
	return TABLES


## Lookup one rule by recipe_id; returns empty dict if absent.
func get_rule(recipe_id: String) -> Dictionary:
	return TABLES.get(recipe_id, {})
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/tables/test_growth_table.gd`. Tests required:
> 1. `GrowthTable.new().get_rule("grass")` returns a non-empty dict with `zones`, `interval_sec`, `per_cell_chance`, `world_cap`.
> 2. `get_rule("nonexistent")` returns empty dict.
> 3. `all()` contains at least `"grass"`.
> 4. For every rule: `zones` is non-empty array; `0.0 <= per_cell_chance <= 1.0`; `interval_sec > 0`; `world_cap > 0`.
> 5. Grass rule's `zones` excludes `ZoneMap.ZoneType.URBAN`.

- [ ] **Step 4: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/tables/test_growth_table.gd`. Expect PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay/tables/growth_table.gd tests/unit/tables/test_growth_table.gd
git commit -m "feat(tables): add GrowthTable design sheet

Runtime growth rules for flora (grass now; trees/berries in future).
Zone-filtered, throttled, capped. Consumed by SWorldGrowth."
```

---

### Task 6: Create `HungerTable` design sheet

**Files:**
- Create: `scripts/gameplay/tables/hunger_table.gd`
- Test: `tests/unit/tables/test_hunger_table.gd`

- [ ] **Step 1: Create `hunger_table.gd`**

```gdscript
# scripts/gameplay/tables/hunger_table.gd
class_name HungerTable
extends Resource
## Hunger/food economy tuning. Global rates + per-species max values.

const DECAY_PER_SEC: float = 1.0               ## uniform hunger decay for all creatures
const STARVE_DAMAGE_PER_SEC: float = 2.0       ## HP damage when hunger <= 0
const HUNGER_PER_FOOD_UNIT: float = 30.0       ## 1 RFood unit restores this many points
const AUTO_FEED_TICK_INTERVAL: float = 0.5     ## SAutoFeed tick cadence (s)

## Per-species max_hunger. Fallback to DEFAULT_MAX for unknown species.
const DEFAULT_MAX: float = 100.0
const MAX_HUNGER: Dictionary = {
	"rabbit": 60.0,
	"player": 200.0,
	"zombie": 10000.0,
}


func max_for(recipe_id: String) -> float:
	return float(MAX_HUNGER.get(recipe_id, DEFAULT_MAX))
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/tables/test_hunger_table.gd`. Tests required:
> 1. Const `DECAY_PER_SEC > 0`, `STARVE_DAMAGE_PER_SEC > 0`, `HUNGER_PER_FOOD_UNIT > 0`, `AUTO_FEED_TICK_INTERVAL > 0`.
> 2. `HungerTable.new().max_for("rabbit") < max_for("player") < max_for("zombie")` — design invariant.
> 3. `max_for("unknown_recipe")` returns `DEFAULT_MAX` (100.0).
> 4. `max_for("rabbit") == 60.0`, `max_for("player") == 200.0`, `max_for("zombie") == 10000.0`.

- [ ] **Step 4: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/tables/test_hunger_table.gd`. Expect PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay/tables/hunger_table.gd tests/unit/tables/test_hunger_table.gd
git commit -m "feat(tables): add HungerTable design sheet

Global decay/starvation/food-unit constants and per-species max
hunger (rabbit 60, player 200, zombie 10000 — zombies effectively
never starve in-session). Consumed by SHunger and SAutoFeed."
```

---

### Task 7: Wire `GOL.Tables` global

**Files:**
- Create: `scripts/gameplay/game_tables.gd`
- Modify: `scripts/gol.gd`

- [ ] **Step 1: Create `game_tables.gd`**

```gdscript
# scripts/gameplay/game_tables.gd
class_name GameTables
extends Object
## Gameplay design sheets. Access via GOL.Tables.loot() / growth() / hunger().
## Per-session singletons; cheap to construct. Distinct from Config
## (which holds non-gameplay scalars like engine/UI/paths).

var _loot: LootTable = null
var _growth: GrowthTable = null
var _hunger: HungerTable = null


func _init() -> void:
	_loot = LootTable.new()
	_growth = GrowthTable.new()
	_hunger = HungerTable.new()


func loot() -> LootTable:
	return _loot


func growth() -> GrowthTable:
	return _growth


func hunger() -> HungerTable:
	return _hunger
```

- [ ] **Step 2: Modify `scripts/gol.gd` — add `Tables` slot**

Read current `gol.gd`. Modify to add `Tables`:

```gdscript
# GOL.gd - Global Game Manager & Entry Point
extends Node

const PlayerData = preload("res://scripts/gameplay/player_data.gd")
const GameTables = preload("res://scripts/gameplay/game_tables.gd")

## Game state instance - manages gameplay data like respawn & fail conditions
var Game: GOLGameState = null
var Player: PlayerData = null
## Gameplay design sheets — loot, growth, hunger. See scripts/gameplay/tables/.
var Tables: GameTables = null


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ServiceContext.static_setup(get_tree().get_root())
	Game = GOLGameState.new()
	Player = PlayerData.new()
	Tables = GameTables.new()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and Game:
		Game.toggle_pause()


func teardown() -> void:
	ServiceContext.static_teardown()
	Game.free()
	Player.free()
	Tables.free()
	Game = null
	Player = null
	Tables = null


func start_game() -> void:
	var config := ProceduralConfig.new()
	config.pcg_config().pcg_seed = randi()
	var result := ServiceContext.pcg().generate(config.pcg_config())
	if result == null or not result.is_valid():
		push_error("PCG generation failed - aborting game start")
		return

	# Cache campfire position from nearest VILLAGE POI to grid center
	Game.campfire_position = ServiceContext.pcg().find_nearest_village_poi()

	ServiceContext.scene().switch_scene(config)
```

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Delegate integration smoke test**

Dispatch to `gol-test-runner` (playtest):
> Launch the game headlessly past `setup()`. Verify `GOL.Tables != null`, `GOL.Tables.loot() != null`, `GOL.Tables.growth() != null`, `GOL.Tables.hunger() != null`. Capture any parse or setup errors.

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay/game_tables.gd scripts/gol.gd
git commit -m "feat(global): wire GOL.Tables aggregator for design sheets

Alongside GOL.Game and GOL.Player, GOL.Tables exposes LootTable,
GrowthTable, HungerTable via typed accessors. Lifecycle follows the
existing setup()/teardown() pattern."
```

---

## Phase 2 — ECS Components (Task 8–12)

Pure data components. Each has a unit test for default values and invariants. No behavior yet.

### Task 8: `CLootDrop` component

**Files:**
- Create: `scripts/components/c_loot_drop.gd`
- Test: `tests/unit/test_c_loot_drop.gd`

- [ ] **Step 1: Create component**

```gdscript
# scripts/components/c_loot_drop.gd
class_name CLootDrop
extends Component
## Runtime marker: "when this entity dies, drop the loot profile
## identified by loot_id". Looked up in LootTable (GOL.Tables.loot()).
##
## loot_id is a runtime value, NOT coupled to recipe_id — it can be
## moved between entities at runtime (e.g., predator absorbing prey's
## drop, pickpocket, trophy chain) to enable emergent mechanics.

@export var loot_id: String = ""
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_c_loot_drop.gd`. Tests required:
> 1. Default `loot_id == ""` (suppresses drop).
> 2. Assigning a value round-trips: `c.loot_id = "rabbit"; assert c.loot_id == "rabbit"`.

- [ ] **Step 4: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/test_c_loot_drop.gd`. Expect PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/components/c_loot_drop.gd tests/unit/test_c_loot_drop.gd
git commit -m "feat(component): add CLootDrop runtime marker

Single field loot_id keys into LootTable. Runtime component
(not recipe-coupled) to support future loot-transfer mechanics
(predator absorbs prey, theft, chain kills)."
```

---

### Task 9: `CResourcePickup` component

**Files:**
- Create: `scripts/components/c_resource_pickup.gd`

No unit test — tested via `test_s_resource_pickup.gd` in Task 15 (behavior-level).

- [ ] **Step 1: Create component**

```gdscript
# scripts/components/c_resource_pickup.gd
class_name CResourcePickup
extends Component
## Marks an entity as a numeric resource pickup. Player collision
## deposits `amount` of `resource_type` into the camp stockpile and
## removes the entity. Distinct from CContainer (weapon/component
## merge semantics) — numeric pickups are pure number-goes-up.

@export var resource_type: Script     ## e.g., RFood, RWood
@export var amount: int = 1
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/components/c_resource_pickup.gd
git commit -m "feat(component): add CResourcePickup

Marks numeric resource pickups (food_pile, future berries). Dedicated
lane distinct from CContainer boxes which carry weapon/component
merge semantics. Tested via SResourcePickup behavior."
```

---

### Task 10: `CHunger` component

**Files:**
- Create: `scripts/components/c_hunger.gd`
- Test: `tests/unit/test_c_hunger.gd`

- [ ] **Step 1: Create component**

```gdscript
# scripts/components/c_hunger.gd
class_name CHunger
extends Component
## Hunger points (decays over time via SHunger; refilled via food
## pickup/consumption). When hunger hits 0, starvation damage is
## applied to CHP.
##
## hungry_threshold / full_threshold are fractions of max_hunger used
## by SHunger to set the blackboard flags `is_hungry` and `is_fed`
## that GOAP goals key off of.

@export var max_hunger: float = 100.0
@export var hunger: float = 100.0
@export var hungry_threshold: float = 0.5     ## below this fraction: is_hungry
@export var full_threshold: float = 0.9       ## above this fraction: is_fed
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_c_hunger.gd`. Tests required:
> 1. Defaults: `max_hunger == 100.0`, `hunger == 100.0`, `hungry_threshold == 0.5`, `full_threshold == 0.9`.
> 2. Invariant: `hungry_threshold < full_threshold`.
> 3. Invariant: `0.0 <= hungry_threshold <= 1.0` and `0.0 <= full_threshold <= 1.0`.
> 4. Fields are exported (check via `get_property_list()` or equivalent reflection).

- [ ] **Step 4: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/test_c_hunger.gd`. Expect PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/components/c_hunger.gd tests/unit/test_c_hunger.gd
git commit -m "feat(component): add CHunger for all creatures

max_hunger + current hunger + threshold fractions. SHunger drives
decay and starvation damage; SAutoFeed / GoapAction_EatGrass refill."
```

---

### Task 11: `CEatable` component

**Files:**
- Create: `scripts/components/c_eatable.gd`
- Test: `tests/unit/test_c_eatable.gd`

- [ ] **Step 1: Create component**

```gdscript
# scripts/components/c_eatable.gd
class_name CEatable
extends Component
## Marks an entity as consumable food for direct-eating creatures
## (rabbits eating grass, future: zombies eating rabbits).
## The eater's GoapAction_EatGrass removes the entity and increments
## the eater's CHunger.hunger by hunger_restore.

@export var hunger_restore: float = 20.0
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_c_eatable.gd`. Tests required:
> 1. Default `hunger_restore == 20.0`.
> 2. Field is exported.

- [ ] **Step 4: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/test_c_eatable.gd`. Expect PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/components/c_eatable.gd tests/unit/test_c_eatable.gd
git commit -m "feat(component): add CEatable

Direct-consumption food marker. hunger_restore is the number of
hunger points the eater gains on consumption. Consumed by
GoapAction_EatGrass."
```

---

### Task 12: `CLabelDisplay` component (TEMPORARY)

**Files:**
- Create: `scripts/components/c_label_display.gd`

No unit test — trivial data component. Behavior tested via playtest.

- [ ] **Step 1: Create component with TEMPORARY banner**

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

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/components/c_label_display.gd
git commit -m "feat(component): add CLabelDisplay placeholder (TEMPORARY)

Emoji/text renderer for entities without production sprites. Banner
marks removal steps. Used by rabbit/grass/food_pile MVP recipes."
```

---

## Phase 3 — Systems (Task 13–19)

### Task 13: `SPerception` — multi-camp enemy resolution + blackboard mirrors

**Files:**
- Modify: `scripts/systems/s_perception.gd`
- Test: Already covered by `test_s_perception_neutral.gd` (Task 18 — but we write it here since the system change is here)

- [ ] **Step 1: Read the current file**

Read `scripts/systems/s_perception.gd` in full to identify `_get_enemy_camp` and the call sites.

- [ ] **Step 2: Replace `_get_enemy_camp` with `_get_enemy_camps` (array) and update `_is_enemy`**

```gdscript
# Replace the existing _get_enemy_camp function with:

func _get_enemy_camps(my_camp: CCamp) -> Array[int]:
	if my_camp == null:
		return [CCamp.CampType.ENEMY]
	match my_camp.camp:
		CCamp.CampType.PLAYER:
			return [CCamp.CampType.ENEMY]
		CCamp.CampType.ENEMY:
			return [CCamp.CampType.PLAYER]
		CCamp.CampType.NEUTRAL:
			return [CCamp.CampType.PLAYER, CCamp.CampType.ENEMY]
	return []


# Replace the existing _is_enemy function with:

func _is_enemy(candidate: Entity, enemy_camps: Array[int]) -> bool:
	var camp := candidate.get_component(CCamp) as CCamp
	if camp == null:
		return false
	if not enemy_camps.has(camp.camp):
		return false
	return not candidate.has_component(CDead)
```

- [ ] **Step 3: Update the call site in `_process_entity`**

Find where `_get_enemy_camp(my_camp)` is called (currently line ~43). Replace:

```gdscript
# OLD:
# var enemy_camp: CCamp.CampType = _get_enemy_camp(my_camp)

# NEW:
var enemy_camps: Array[int] = _get_enemy_camps(my_camp)
```

And the call to `_is_enemy`:
```gdscript
# OLD:
# if _is_enemy(candidate, enemy_camp) and dist_sq < closest_enemy_dist_sq:

# NEW:
if _is_enemy(candidate, enemy_camps) and dist_sq < closest_enemy_dist_sq:
```

- [ ] **Step 4: Add blackboard mirror writes at the end of `_process_entity`**

Immediately before the function's end (after `nearest_enemy` has been determined), add:

```gdscript
	# Mirror perception signals into GOAP blackboard so goals can key off them.
	var agent := entity.get_component(CGoapAgent) as CGoapAgent
	if agent != null:
		agent.world_state["has_threat"] = perception.nearest_enemy != null
		agent.world_state["has_visible_grass"] = _has_visible_eatable(perception)


func _has_visible_eatable(perception: CPerception) -> bool:
	for candidate in perception._visible_entities:
		if candidate != null and is_instance_valid(candidate) and candidate.has_component(CEatable):
			return true
	return false
```

- [ ] **Step 5: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 6: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_s_perception_neutral.gd`. Setup: construct a minimal ECS world, create entities with `CCamp` set to NEUTRAL/PLAYER/ENEMY, add `CPerception`, `CTransform`, and `CGoapAgent`. Tick the system via `gameplay` group.
>
> Tests required:
> 1. NEUTRAL rabbit within vision range of both a PLAYER and an ENEMY entity → `perception.nearest_enemy` is set to the closer of the two regardless of camp.
> 2. NEUTRAL rabbit with no PLAYER or ENEMY in range → `perception.nearest_enemy == null`.
> 3. After tick with visible threat: `agent.world_state["has_threat"] == true`.
> 4. After tick with no threats: `agent.world_state["has_threat"] == false`.
> 5. Add a `CEatable` entity in vision range → `agent.world_state["has_visible_grass"] == true`.
> 6. Remove/hide the eatable → `has_visible_grass == false` on next tick.

- [ ] **Step 7: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/test_s_perception_neutral.gd`. Expect PASS. Also re-run any pre-existing perception tests to verify no regressions.

- [ ] **Step 8: Commit**

```bash
git add scripts/systems/s_perception.gd tests/unit/test_s_perception_neutral.gd
git commit -m "feat(perception): multi-camp enemy set + blackboard mirrors

_get_enemy_camps returns an array so NEUTRAL entities see both
PLAYER and ENEMY as threats. Also mirrors has_threat and
has_visible_grass into the GOAP agent's world_state for goal
preconditions."
```

---

### Task 14: `SDead` — loot drop hook

**Files:**
- Modify: `scripts/systems/s_dead.gd`
- Test: `tests/unit/test_s_dead_loot_drop.gd`

- [ ] **Step 1: Read current `s_dead.gd`**

Identify `_complete_death` and the line `cmd.remove_entity(entity)`.

- [ ] **Step 2: Add `_drop_loot` helper + call in `_complete_death`**

Add a call to `_drop_loot(entity)` immediately before `cmd.remove_entity(entity)`:

```gdscript
# In _complete_death, immediately before `cmd.remove_entity(entity)`, insert:

	# Drop loot (if configured) while transform is still readable.
	_drop_loot(entity)

	# ...then the existing cmd.remove_entity(entity) line follows.
```

Add the helper function at the bottom of the file:

```gdscript
func _drop_loot(entity: Entity) -> void:
	var loot := entity.get_component(CLootDrop) as CLootDrop
	if loot == null or loot.loot_id == "":
		return

	var transform := entity.get_component(CTransform) as CTransform
	if transform == null:
		return

	var drops := GOL.Tables.loot().get_drops(loot.loot_id)
	if drops.is_empty():
		return

	for entry in drops:
		if randf() > float(entry.get("chance", 1.0)):
			continue
		var count_min: int = int(entry.get("count_min", 1))
		var count_max: int = int(entry.get("count_max", count_min))
		var n: int = randi_range(count_min, count_max)
		var scatter: float = float(entry.get("scatter_radius", 0.0))
		var drop_recipe: String = String(entry.get("recipe_id", ""))
		if drop_recipe == "":
			continue
		for i in n:
			var offset := Vector2(
				randf_range(-scatter, scatter),
				randf_range(-scatter, scatter))
			var spawned: Entity = ServiceContext.recipe().create_entity_by_id(drop_recipe)
			if spawned == null:
				continue
			var spawned_t := spawned.get_component(CTransform) as CTransform
			if spawned_t != null:
				spawned_t.position = transform.position + offset
```

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_s_dead_loot_drop.gd`. Setup: minimal ECS world; create a test recipe for the drop target (may need to mock `ServiceContext.recipe()` or pre-register a simple recipe — consult existing `test_s_*.gd` files for patterns).
>
> Tests required:
> 1. Entity with `CLootDrop(loot_id="rabbit")` + `CTransform` + `CDead` + a sprite child (to drive SDead through `_complete_death`): after ticking long enough for the death tween to complete, assert an entity with `recipe_id` `food_pile` exists in the world at (approximately) the death position.
> 2. Entity without `CLootDrop` but otherwise identical: no food_pile spawned after death.
> 3. Entity with `CLootDrop(loot_id="unknown_id")`: no food_pile spawned (silent no-op via empty `get_drops`).
> 4. `_drop_loot` does not crash when `CTransform` is missing (early return).
>
> If mocking GOL.Tables proves difficult, use the real `GOL.Tables` (Task 7 instantiated it in `setup()`).

- [ ] **Step 5: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/test_s_dead_loot_drop.gd`. Expect PASS. Also re-run existing death-related tests.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/s_dead.gd tests/unit/test_s_dead_loot_drop.gd
git commit -m "feat(death): SDead drops CLootDrop-tagged loot before entity removal

_drop_loot helper reads CLootDrop and LootTable, rolls per-entry
chance, spawns drop recipes with jitter at the death position.
Runs in _complete_death before cmd.remove_entity while transform
is still live. Silent no-op when component missing or loot_id
unknown."
```

---

### Task 15: `SResourcePickup` system

**Files:**
- Create: `scripts/systems/s_resource_pickup.gd`
- Test: `tests/unit/test_s_resource_pickup.gd`

- [ ] **Step 1: Create system**

```gdscript
# scripts/systems/s_resource_pickup.gd
class_name SResourcePickup
extends System
## Distance-based pickup of CResourcePickup entities by the player.
## On overlap, deposits resource into the camp stockpile (ECS query —
## entity with CStockpile but without CPlayer) and removes the pickup.
## Pickup radius = Config.RESOURCE_PICKUP_RADIUS.

func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CResourcePickup, CTransform, CCollision])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		return

	var player_entity := _find_player()
	if player_entity == null:
		return
	var player_t := player_entity.get_component(CTransform) as CTransform
	if player_t == null:
		return

	var camp_stockpile := _find_camp_stockpile()
	if camp_stockpile == null:
		return

	var radius_sq: float = Config.RESOURCE_PICKUP_RADIUS * Config.RESOURCE_PICKUP_RADIUS

	for pickup_entity in entities:
		if pickup_entity == null or not is_instance_valid(pickup_entity):
			continue
		if pickup_entity.has_component(CDead):
			continue
		var pickup := pickup_entity.get_component(CResourcePickup) as CResourcePickup
		var pt := pickup_entity.get_component(CTransform) as CTransform
		if pickup == null or pt == null:
			continue
		if pickup.resource_type == null:
			continue

		var dist_sq: float = player_t.position.distance_squared_to(pt.position)
		if dist_sq > radius_sq:
			continue

		if not camp_stockpile.can_accept(pickup.resource_type, pickup.amount):
			continue

		camp_stockpile.add(pickup.resource_type, pickup.amount)
		cmd.remove_entity(pickup_entity)


func _find_player() -> Entity:
	var found := ECS.world.query.with_all([CPlayer, CTransform]).execute()
	if found.is_empty():
		return null
	return found[0]


func _find_camp_stockpile() -> CStockpile:
	# Camp stockpile convention: entity with CStockpile but without CPlayer
	# (player has a separate personal stockpile for component_points).
	var found := ECS.world.query.with_all([CStockpile]).with_none([CPlayer]).execute()
	if found.is_empty():
		return null
	return found[0].get_component(CStockpile) as CStockpile
```

- [ ] **Step 2: Register the system**

System registration in this codebase happens via `SceneConfig` (see `scripts/gameplay/ecs/scene_config.gd`). Check the existing registration pattern and add `SResourcePickup` to whichever registration list the main scene uses. If the convention is instead that all systems in `scripts/systems/` are auto-loaded, no action needed — verify during the parse check.

Implementation note: look at how `s_damage.gd` or `s_ai.gd` is registered — there's a specific pattern. If a scene config file lists systems explicitly, add:
```gdscript
"SResourcePickup",  # or whatever the string form is
```

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_s_resource_pickup.gd`. Setup: minimal ECS world with a player entity ([CPlayer, CTransform]), a camp stockpile entity ([CStockpile]), and a pickup entity ([CResourcePickup(RFood, 1), CTransform, CCollision]).
>
> Tests required:
> 1. Pickup at distance < `Config.RESOURCE_PICKUP_RADIUS` from player: after `process()`, pickup entity is removed from world (or marked for removal) and `camp_stockpile.get_amount(RFood) == 1`.
> 2. Pickup at distance > RADIUS: unchanged after process; pickup still exists, stockpile still 0.
> 3. Player missing from world: system is a no-op (no crash, no change).
> 4. Camp stockpile missing: system is a no-op.
> 5. `pickup.resource_type == null`: skipped (no crash).
> 6. Stockpile at cap (`can_accept` returns false): pickup NOT removed.

- [ ] **Step 5: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/test_s_resource_pickup.gd`. Expect PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/s_resource_pickup.gd tests/unit/test_s_resource_pickup.gd
git commit -m "feat(system): add SResourcePickup for distance-based numeric pickups

Queries [CResourcePickup, CTransform, CCollision]. On overlap with
player (within Config.RESOURCE_PICKUP_RADIUS), adds to camp
stockpile (ECS query: [CStockpile] without [CPlayer]) and removes
pickup. Distinct from SPickup which handles CContainer boxes."
```

---

### Task 16: `SHunger` system

**Files:**
- Create: `scripts/systems/s_hunger.gd`
- Test: `tests/unit/test_s_hunger.gd`

- [ ] **Step 1: Create system**

```gdscript
# scripts/systems/s_hunger.gd
class_name SHunger
extends System
## Universal hunger tick: decays CHunger.hunger for every creature
## that has a CHunger component, mirrors is_hungry/is_fed flags into
## the GOAP blackboard, and applies starvation damage when hunger
## reaches 0.

func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CHunger])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	var table: HungerTable = GOL.Tables.hunger()
	var decay: float = HungerTable.DECAY_PER_SEC
	var starve: float = HungerTable.STARVE_DAMAGE_PER_SEC

	for entity in entities:
		if entity == null or not is_instance_valid(entity):
			continue
		if entity.has_component(CDead):
			continue
		var h := entity.get_component(CHunger) as CHunger
		if h == null:
			continue

		# Decay
		h.hunger = max(0.0, h.hunger - decay * delta)

		# Blackboard mirror
		var agent := entity.get_component(CGoapAgent) as CGoapAgent
		if agent != null:
			agent.world_state["is_hungry"] = h.hunger < h.max_hunger * h.hungry_threshold
			agent.world_state["is_fed"]    = h.hunger >= h.max_hunger * h.full_threshold

		# Starvation damage
		if h.hunger <= 0.0:
			var hp := entity.get_component(CHP) as CHP
			if hp != null:
				hp.hp = max(0.0, hp.hp - starve * delta)
```

- [ ] **Step 2: Register the system** (same pattern as Task 15 Step 2 — follow existing registration convention).

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_s_hunger.gd`. Setup: construct entities with `CHunger` (and optionally `CGoapAgent`, `CHP`).
>
> Tests required:
> 1. Entity with hunger=100, max=100. After `process()` with delta=1.0, hunger ≈ 99.0 (within 0.01).
> 2. Hunger cannot go below 0: with hunger=0.5 and delta=1.0, hunger == 0.0 (clamped).
> 3. Below `hungry_threshold`: `agent.world_state["is_hungry"] == true`; above: false.
> 4. At/above `full_threshold`: `agent.world_state["is_fed"] == true`; below: false.
> 5. With hunger=0 and hp=10: after delta=1.0, hp decreased by `STARVE_DAMAGE_PER_SEC` (≈2.0).
> 6. Entity with `CDead`: skipped (hunger unchanged, no HP loss).
> 7. Entity missing `CGoapAgent`: no crash; system processes hunger normally.

- [ ] **Step 5: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/test_s_hunger.gd`. Expect PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/s_hunger.gd tests/unit/test_s_hunger.gd
git commit -m "feat(system): add SHunger for universal decay + starvation

Ticks CHunger for every live creature. Clamps to 0, mirrors
is_hungry/is_fed to GOAP blackboard, applies starve damage when
at 0. Skips CDead entities."
```

---

### Task 17: `SAutoFeed` system (prioritized + atomic consumption)

**Files:**
- Create: `scripts/systems/s_auto_feed.gd`
- Test: `tests/unit/test_s_auto_feed.gd`

- [ ] **Step 1: Create system**

```gdscript
# scripts/systems/s_auto_feed.gd
class_name SAutoFeed
extends System
## Auto-feed for PLAYER-camp creatures from the camp stockpile.
## Ticks at HungerTable.AUTO_FEED_TICK_INTERVAL. Rules:
##   1. Candidates: entities with [CHunger, CCamp(PLAYER)] whose
##      hunger < max_hunger.
##   2. Prioritize lowest-hunger first (fairness).
##   3. Atomic consume: only spend 1 RFood unit when the eater can
##      absorb >= HUNGER_PER_FOOD_UNIT points. No partial feeds, no
##      wasted units.

const RFood = preload("res://scripts/resources/r_food.gd")

var _tick_timer: float = 0.0


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CHunger, CCamp])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	_tick_timer += delta
	if _tick_timer < HungerTable.AUTO_FEED_TICK_INTERVAL:
		return
	_tick_timer = 0.0

	if entities.is_empty():
		return

	var stockpile := _find_camp_stockpile()
	if stockpile == null:
		return
	if stockpile.get_amount(RFood) <= 0:
		return

	var per_unit: float = HungerTable.HUNGER_PER_FOOD_UNIT

	# 1. Collect PLAYER-camp candidates with any deficit.
	var candidates: Array[Entity] = []
	for e in entities:
		if e == null or not is_instance_valid(e):
			continue
		if e.has_component(CDead):
			continue
		var camp := e.get_component(CCamp) as CCamp
		if camp == null or camp.camp != CCamp.CampType.PLAYER:
			continue
		var h := e.get_component(CHunger) as CHunger
		if h == null:
			continue
		if h.hunger >= h.max_hunger:
			continue
		candidates.append(e)

	if candidates.is_empty():
		return

	# 2. Sort ascending by current hunger (hungriest first).
	candidates.sort_custom(func(a: Entity, b: Entity) -> bool:
		var ha := a.get_component(CHunger) as CHunger
		var hb := b.get_component(CHunger) as CHunger
		return ha.hunger < hb.hunger)

	# 3. Serve, atomically — skip eaters whose deficit < per_unit.
	for e in candidates:
		var h := e.get_component(CHunger) as CHunger
		while h.hunger <= h.max_hunger - per_unit:
			if stockpile.get_amount(RFood) <= 0:
				return
			if not stockpile.withdraw(RFood, 1):
				return
			h.hunger = min(h.max_hunger, h.hunger + per_unit)


func _find_camp_stockpile() -> CStockpile:
	var found := ECS.world.query.with_all([CStockpile]).with_none([CPlayer]).execute()
	if found.is_empty():
		return null
	return found[0].get_component(CStockpile) as CStockpile
```

- [ ] **Step 2: Register the system** (follow Task 15 Step 2 pattern).

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_s_auto_feed.gd`. Setup: ECS world with a camp stockpile ([CStockpile] no CPlayer) and PLAYER-camp entities with CHunger.
>
> Helper: advance system by calling `process(entities, [], HungerTable.AUTO_FEED_TICK_INTERVAL)` (forces timer to fire).
>
> Tests required:
> 1. **Prioritization**: rabbit(hunger=25, max=60) with [CHunger, CCamp(PLAYER)] and player(hunger=185, max=200) with [CHunger, CCamp(PLAYER)]. Stockpile has 1 RFood. After `process()`: rabbit.hunger == 55 (25 + 30), player.hunger == 185 (unchanged — deficit 15 < 30 skipped), stockpile has 0 RFood.
> 2. **Atomic consume — skip partial**: player hunger=185, max=200 (deficit 15). Stockpile has 5 RFood. After process: hunger still 185, stockpile still 5 (nobody has enough deficit).
> 3. **Multiple units**: player hunger=80, max=200 (deficit 120). Stockpile has 5 RFood. After process: player.hunger == 200 (consumed 4 units × 30 = 120); stockpile has 1 remaining.
> 4. **ENEMY-camp entities not fed**: zombie with [CHunger, CCamp(ENEMY)] alongside; unchanged after process.
> 5. **No stockpile in world**: no-op, no crash.
> 6. **Tick throttling**: calling process with delta=0.1 three times does NOT trigger feeding until cumulative time ≥ `AUTO_FEED_TICK_INTERVAL`.

- [ ] **Step 5: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/test_s_auto_feed.gd`. Expect PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/s_auto_feed.gd tests/unit/test_s_auto_feed.gd
git commit -m "feat(system): add SAutoFeed — prioritized atomic feeding

PLAYER-camp creatures with CHunger are fed from the camp stockpile,
lowest hunger first, atomic consumption (skip when deficit < 30 to
avoid wasted food). Throttled at 0.5s tick. Zombies (ENEMY) never
eat from this stockpile."
```

---

### Task 18: `SWorldGrowth` system

**Files:**
- Create: `scripts/systems/s_world_growth.gd`
- Test: `tests/unit/test_s_world_growth.gd`

- [ ] **Step 1: Create system**

```gdscript
# scripts/systems/s_world_growth.gd
class_name SWorldGrowth
extends System
## Continuous runtime growth of flora (grass now; trees/berries
## in future). Reads rules from GOL.Tables.growth(); per-recipe
## timer, per-cell roll, world-cap enforcement.
##
## This is NOT a PCG phase — PCG runs once at world gen; growth
## happens across the play session.

var _timers: Dictionary = {}      ## recipe_id -> elapsed (float)


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	# System-level tick; entity set unused. Query something cheap
	# that matches at least one entity per tick.
	return q.with_all([CTransform])


func process(_entities: Array[Entity], _components: Array, delta: float) -> void:
	var zone_map: ZoneMap = ServiceContext.pcg().get_zone_map()
	if zone_map == null:
		return

	var rules: Dictionary = GOL.Tables.growth().all()
	for recipe_id in rules.keys():
		var rule: Dictionary = rules[recipe_id]
		_timers[recipe_id] = float(_timers.get(recipe_id, 0.0)) + delta
		var interval: float = float(rule.get("interval_sec", 10.0))
		if _timers[recipe_id] < interval:
			continue
		_timers[recipe_id] = 0.0
		_attempt_spawn(zone_map, String(recipe_id), rule)


func _attempt_spawn(zone_map: ZoneMap, recipe_id: String, rule: Dictionary) -> void:
	var world_cap: int = int(rule.get("world_cap", 0))
	if world_cap <= 0:
		return
	if _count_live(recipe_id) >= world_cap:
		return

	var zones: Array = rule.get("zones", [])
	var chance: float = float(rule.get("per_cell_chance", 0.0))
	if zones.is_empty() or chance <= 0.0:
		return

	var tile_size: int = _get_tile_size()

	for cell in zone_map.zones.keys():
		if _count_live(recipe_id) >= world_cap:
			return
		var zone_type: int = zone_map.get_zone(cell)
		if not zones.has(zone_type):
			continue
		if randf() > chance:
			continue
		_spawn_at_cell(recipe_id, cell, tile_size)


func _spawn_at_cell(recipe_id: String, cell: Vector2i, tile_size: int) -> void:
	var entity: Entity = ServiceContext.recipe().create_entity_by_id(recipe_id)
	if entity == null:
		return
	var t := entity.get_component(CTransform) as CTransform
	if t != null:
		t.position = Vector2(cell.x * tile_size + tile_size * 0.5,
			cell.y * tile_size + tile_size * 0.5)


func _count_live(recipe_id: String) -> int:
	# Entities keep the recipe_id as their name prefix ("recipe_id@instance_id").
	# Cheap scan over ECS entities with CTransform.
	var count := 0
	var prefix: String = recipe_id + "@"
	for e in ECS.world.query.with_all([CTransform]).execute():
		if e == null or not is_instance_valid(e):
			continue
		var name_str: String = String(e.name)
		if name_str.begins_with(prefix):
			count += 1
	return count


func _get_tile_size() -> int:
	# Match PCGContext._get_tile_size() and POIGenerator's config-default path.
	# At runtime, PCGConfig is stored on PCGResult. If unavailable, fall back
	# to the canonical default of 32.
	var pcg_service := ServiceContext.pcg()
	if pcg_service != null and pcg_service.last_result != null:
		var cfg = pcg_service.last_result.config
		if cfg != null:
			var ts = cfg.get("tile_size")
			if ts != null:
				return int(ts)
	return 32
```

**Implementation note:** Step 1 uses `entity.name.begins_with(recipe_id + "@")` to count live instances (the naming convention from `service_recipe.gd:136`). If this becomes a perf issue later, add a cheap tag component. For MVP it's fine — grass count is < 60.

- [ ] **Step 2: Register the system** (Task 15 Step 2 pattern).

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_s_world_growth.gd`. Setup: mock or construct a `ZoneMap` with known cells (e.g., 10 WILDERNESS cells, 10 URBAN cells). Override `GrowthTable` rules in the test (or use real rules with `per_cell_chance = 1.0` for deterministic behavior by pre-calling `process()` enough).
>
> If mocking `ServiceContext.pcg().get_zone_map()` is difficult, make the test fixture stub `ServiceContext.pcg()` to return a mock with `get_zone_map()`. Consult existing PCG tests for patterns.
>
> Tests required:
> 1. **Zone filter**: with all cells set to URBAN and `per_cell_chance=1.0`, after one tick (elapsed ≥ `interval_sec`): zero grass spawned.
> 2. **Eligible zones spawn**: with all cells WILDERNESS and `per_cell_chance=1.0`, after one interval: grass entities exist in the world.
> 3. **world_cap enforced**: with 20 eligible cells but `world_cap=5` and `per_cell_chance=1.0`, after one interval: exactly 5 grass entities exist (not 20).
> 4. **Interval throttling**: calling `process(entities, [], 0.1)` three times (total 0.3s, less than `interval_sec=8.0`) spawns nothing.
> 5. **Missing zone_map**: no-op, no crash.

- [ ] **Step 5: Delegate test run**

Dispatch to `gol-test-runner`: run `tests/unit/test_s_world_growth.gd`. Expect PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/s_world_growth.gd tests/unit/test_s_world_growth.gd
git commit -m "feat(system): add SWorldGrowth for runtime grass spawning

Reads GOL.Tables.growth() rules. Per-recipe timer, per-cell roll,
world-cap via name-prefix count. Zone-filtered (grass: WILDERNESS,
SUBURBS; never URBAN). Tile position centers via ZoneMap coords."
```

---

### Task 19: `SLabelDisplay` system (TEMPORARY)

**Files:**
- Create: `scripts/systems/s_label_display.gd`

No unit test — visual-only; tested via playtest smoke plan.

- [ ] **Step 1: Create system with TEMPORARY banner**

```gdscript
# scripts/systems/s_label_display.gd
class_name SLabelDisplay
extends System

## --------------------------------------------------------------
## !!! TEMPORARY PLACEHOLDER — REMOVE WHEN ART LANDS !!!
## Renders CLabelDisplay.text as a centered Label child per entity.
## Use for emoji-as-placeholder-sprite. Delete this file along with
## CLabelDisplay when all three placeholder recipes migrate to
## production sprites. See c_label_display.gd migration steps.
## --------------------------------------------------------------

func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CLabelDisplay, CTransform])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		if entity == null or not is_instance_valid(entity):
			continue
		var cfg := entity.get_component(CLabelDisplay) as CLabelDisplay
		var t := entity.get_component(CTransform) as CTransform
		if cfg == null or t == null:
			continue

		var label := _get_or_create_label(entity, cfg)
		# Center the label over the entity position
		label.position = t.position - label.size * 0.5


func _get_or_create_label(entity: Entity, cfg: CLabelDisplay) -> Label:
	# Look for existing child we created
	for child in entity.get_children():
		if child is Label and child.name == "_PlaceholderLabel":
			return child as Label

	var label := Label.new()
	label.name = "_PlaceholderLabel"
	label.text = cfg.text
	label.add_theme_font_size_override("font_size", cfg.font_size)
	label.add_theme_color_override("font_color", cfg.color)
	label.add_theme_color_override("font_outline_color", cfg.outline_color)
	label.add_theme_constant_override("outline_size", cfg.outline_size)
	# Center horizontally inside its own rect — Godot-autosize to text.
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	entity.add_child(label)

	# Let Godot size the label after add_child so .size is correct next tick.
	return label
```

- [ ] **Step 2: Register the system** (Task 15 Step 2 pattern).

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Commit**

```bash
git add scripts/systems/s_label_display.gd
git commit -m "feat(system): add SLabelDisplay placeholder renderer (TEMPORARY)

Creates a child Label per entity with CLabelDisplay and centers it
on the entity's CTransform.position. Enables visibility for rabbit,
grass, food_pile recipes without PNG production. Banner marks
removal steps."
```

---

## Phase 4 — GOAP Actions + Goals (Task 20–24)

### Task 20: `GoapAction_FleeOnSight`

**Files:**
- Create: `scripts/gameplay/goap/actions/flee_on_sight.gd`
- Test: `tests/unit/test_goap_action_flee_on_sight.gd`

- [ ] **Step 1: Create action**

```gdscript
# scripts/gameplay/goap/actions/flee_on_sight.gd
class_name GoapAction_FleeOnSight
extends GoapAction
## Flee from any perceived threat until safe_distance reached.
## Differs from GoapAction_Flee: no CWeapon dependency (rabbits are
## unarmed); triggers on has_threat (not is_low_health).

func _init() -> void:
	action_name = "FleeOnSight"
	cost = 1.0
	preconditions = {
		"has_threat": true,
	}
	effects = {
		"is_safe": true,
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform) as CTransform
	var movement := agent_entity.get_component(CMovement) as CMovement
	var perception := agent_entity.get_component(CPerception) as CPerception
	if transform == null or movement == null or perception == null:
		return true

	var threat: Entity = perception.nearest_enemy
	if threat == null or not is_instance_valid(threat):
		movement.velocity = Vector2.ZERO
		update_world_state(agent_component, "is_safe", true)
		return true

	var threat_t := threat.get_component(CTransform) as CTransform
	if threat_t == null:
		movement.velocity = Vector2.ZERO
		update_world_state(agent_component, "is_safe", true)
		return true

	var offset: Vector2 = threat_t.position - transform.position
	var dist: float = offset.length()
	var safe_dist: float = Config.RABBIT_SAFE_DISTANCE

	if dist >= safe_dist:
		movement.velocity = Vector2.ZERO
		update_world_state(agent_component, "is_safe", true)
		return true

	# Flee at max speed directly away from threat
	var flee_dir: Vector2 = Vector2.ZERO if dist == 0.0 else -offset.normalized()
	movement.velocity = flee_dir * movement.max_speed
	update_world_state(agent_component, "is_safe", false)
	return false  # keep fleeing next tick
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_goap_action_flee_on_sight.gd`. Setup: construct entities with `CTransform`, `CMovement(max_speed=140)`, `CPerception` (with `nearest_enemy` manually set or cleared), and `CGoapAgent`.
>
> Tests required:
> 1. **Within safe_distance**: rabbit at (0,0), threat at (50,0) (dist 50 < 200), rabbit.max_speed=140. After `perform()`: `movement.velocity.x == -140` (flees +x direction negated → -x; magnitude == 140); return value == false.
> 2. **Beyond safe_distance**: threat at (300,0). After perform: `velocity == Vector2.ZERO`, `agent.world_state["is_safe"] == true`, return true.
> 3. **No threat** (`nearest_enemy == null`): `velocity == Vector2.ZERO`, `is_safe == true`, return true.
> 4. **Zero distance** (threat overlapping): no NaN/inf velocity; velocity is `Vector2.ZERO` (not NaN) and return is `false` still.
> 5. **Missing CTransform/CMovement/CPerception**: returns true (no crash).

- [ ] **Step 4: Delegate test run**

Dispatch to `gol-test-runner`: run the test. Expect PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay/goap/actions/flee_on_sight.gd tests/unit/test_goap_action_flee_on_sight.gd
git commit -m "feat(goap): add GoapAction_FleeOnSight for prey behavior

Precondition has_threat, effect is_safe. No CWeapon dependency —
uses Config.RABBIT_SAFE_DISTANCE. Returns false while fleeing, true
when safe or threat absent."
```

---

### Task 21: `GoapAction_MoveToGrass`

**Files:**
- Create: `scripts/gameplay/goap/actions/move_to_grass.gd`

No unit test — behavior covered by integration test in Task 30 (`test_rabbit_forages_grass.gd`). Keeps test scope focused on interesting behavior.

- [ ] **Step 1: Create action**

```gdscript
# scripts/gameplay/goap/actions/move_to_grass.gd
class_name GoapAction_MoveToGrass
extends GoapAction
## Move toward the nearest visible CEatable entity. Sets
## adjacent_to_grass when close enough for EatGrass to take over.

const ADJACENCY_THRESHOLD: float = 16.0  ## px — close enough to eat

func _init() -> void:
	action_name = "MoveToGrass"
	cost = 1.0
	preconditions = {
		"has_visible_grass": true,
	}
	effects = {
		"adjacent_to_grass": true,
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform) as CTransform
	var movement := agent_entity.get_component(CMovement) as CMovement
	var perception := agent_entity.get_component(CPerception) as CPerception
	if transform == null or movement == null or perception == null:
		return true

	var nearest: Entity = _find_nearest_eatable(perception, transform.position)
	if nearest == null:
		movement.velocity = Vector2.ZERO
		update_world_state(agent_component, "has_visible_grass", false)
		return true

	var nt := nearest.get_component(CTransform) as CTransform
	if nt == null:
		return true

	var offset: Vector2 = nt.position - transform.position
	var dist: float = offset.length()

	if dist <= ADJACENCY_THRESHOLD:
		movement.velocity = Vector2.ZERO
		agent_component.blackboard["target_grass"] = nearest
		update_world_state(agent_component, "adjacent_to_grass", true)
		return true

	# Move toward the grass at normal movement speed
	var dir: Vector2 = offset.normalized() if dist > 0.0 else Vector2.ZERO
	movement.velocity = dir * movement.max_speed
	update_world_state(agent_component, "adjacent_to_grass", false)
	return false  # keep moving next tick


func _find_nearest_eatable(perception: CPerception, from: Vector2) -> Entity:
	var best: Entity = null
	var best_dist_sq := INF
	for candidate in perception._visible_entities:
		if candidate == null or not is_instance_valid(candidate):
			continue
		if not candidate.has_component(CEatable):
			continue
		var ct := candidate.get_component(CTransform) as CTransform
		if ct == null:
			continue
		var d := from.distance_squared_to(ct.position)
		if d < best_dist_sq:
			best_dist_sq = d
			best = candidate
	return best
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/goap/actions/move_to_grass.gd
git commit -m "feat(goap): add GoapAction_MoveToGrass

Scans CPerception._visible_entities for nearest CEatable, moves
toward it. Stores target in blackboard.target_grass for EatGrass
handoff. Sets adjacent_to_grass when within 16 px."
```

---

### Task 22: `GoapAction_EatGrass`

**Files:**
- Create: `scripts/gameplay/goap/actions/eat_grass.gd`
- Test: `tests/unit/test_goap_action_eat_grass.gd`

- [ ] **Step 1: Create action**

```gdscript
# scripts/gameplay/goap/actions/eat_grass.gd
class_name GoapAction_EatGrass
extends GoapAction
## Consume the grass entity the rabbit has moved adjacent to.
## Increments eater's CHunger and removes the grass. Sets is_fed=true.

func _init() -> void:
	action_name = "EatGrass"
	cost = 1.0
	preconditions = {
		"adjacent_to_grass": true,
	}
	effects = {
		"is_fed": true,
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var hunger := agent_entity.get_component(CHunger) as CHunger
	if hunger == null:
		return true

	var target: Entity = agent_component.blackboard.get("target_grass", null)
	if target == null or not is_instance_valid(target):
		update_world_state(agent_component, "adjacent_to_grass", false)
		return true

	var eatable := target.get_component(CEatable) as CEatable
	if eatable == null:
		update_world_state(agent_component, "adjacent_to_grass", false)
		return true

	hunger.hunger = min(hunger.max_hunger, hunger.hunger + eatable.hunger_restore)
	cmd.remove_entity(target)

	agent_component.blackboard.erase("target_grass")
	update_world_state(agent_component, "adjacent_to_grass", false)
	update_world_state(agent_component, "is_fed", true)
	return true
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Delegate unit test**

Dispatch to `gol-test-writer` (unit):
> Target: `tests/unit/test_goap_action_eat_grass.gd`. Setup: eater entity with `CHunger(max=60, hunger=20)` and `CGoapAgent`; target grass entity with `CEatable(hunger_restore=30)`. Set `agent.blackboard["target_grass"] = grass_entity`.
>
> Tests required:
> 1. After `perform()`: eater.hunger == 50 (20+30); grass entity is removed from world.
> 2. Blackboard `target_grass` is erased.
> 3. `agent.world_state["is_fed"] == true`, `agent.world_state["adjacent_to_grass"] == false`.
> 4. Perform returns true (action completes in one tick).
> 5. **No target in blackboard**: perform does not crash; returns true; `adjacent_to_grass=false`.
> 6. **Hunger cap**: eater.hunger=50, max=60. After eating grass(restore=30): hunger == 60 (clamped, not 80).

- [ ] **Step 4: Delegate test run**

Dispatch to `gol-test-runner`: run the test. Expect PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay/goap/actions/eat_grass.gd tests/unit/test_goap_action_eat_grass.gd
git commit -m "feat(goap): add GoapAction_EatGrass

Consumes blackboard.target_grass, increments CHunger.hunger by
CEatable.hunger_restore (clamped to max_hunger), removes the grass
entity. One-tick action."
```

---

### Task 23: Goal resources (`survive_on_sight.tres`, `feed_self.tres`)

**Files:**
- Create: `resources/goals/survive_on_sight.tres`
- Create: `resources/goals/feed_self.tres`

- [ ] **Step 1: Examine existing goal .tres format**

Read `resources/goals/survive.tres` (or any existing goal) to match the exact resource format. The script reference is `scripts/gameplay/goap/goap_goal.gd`.

- [ ] **Step 2: Create `survive_on_sight.tres` in the Godot editor**

Open Godot, create new Resource inheriting `GoapGoal`:
- `goal_name = "survive_on_sight"`
- `priority = 100`
- `desired_state = { "is_safe": true }`

Save as `res://resources/goals/survive_on_sight.tres`.

Alternative (by direct file write): mirror the format of `survive.tres`:

```
[gd_resource type="Resource" script_class="GoapGoal" format=3]

[ext_resource type="Script" uid="<match_survive.tres>" path="res://scripts/gameplay/goap/goap_goal.gd" id="1"]

[resource]
script = ExtResource("1")
goal_name = "survive_on_sight"
priority = 100
desired_state = { "is_safe": true }
```

**Implementation note:** `ext_resource` uid values must match the actual goap_goal.gd uid. Best to create via Godot editor rather than hand-editing to avoid mismatches.

- [ ] **Step 3: Create `feed_self.tres`**

Same process:
- `goal_name = "feed_self"`
- `priority = 50`
- `desired_state = { "is_fed": true }`

Save as `res://resources/goals/feed_self.tres`.

- [ ] **Step 4: Godot parse check**

Open both .tres files in Godot editor; verify no inspector errors.

Then:
```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 5: Commit**

```bash
git add resources/goals/survive_on_sight.tres resources/goals/feed_self.tres
git commit -m "feat(goap): add survive_on_sight and feed_self goals

survive_on_sight (pri 100, desired is_safe=true) fulfilled by
FleeOnSight. feed_self (pri 50, desired is_fed=true) chain:
MoveToGrass then EatGrass."
```

---

## Phase 5 — Recipes (Task 24–26)

### Task 24: `food_pile.tres` recipe

**Files:**
- Create: `resources/recipes/food_pile.tres`

- [ ] **Step 1: Examine existing simple recipe (`tree.tres` is simplest)**

Read `resources/recipes/tree.tres` to match resource format and component instantiation style.

- [ ] **Step 2: Create `food_pile.tres` via Godot editor**

Open Godot. Create new `EntityRecipe` resource at `res://resources/recipes/food_pile.tres` with:
- `recipe_id = "food_pile"`
- `display_name = "食物"`
- `components = [`:
  - `CTransform`
  - `CCollision` with `collision_shape = CircleShape2D(radius=10)`
  - `CResourcePickup` with `resource_type = RFood (Script reference)`, `amount = 1`
  - `CLifeTime` with `lifetime = 120.0` (matches `Config.RESOURCE_PICKUP_LIFETIME`)
  - `CLabelDisplay` with `text = "🍖"`, `font_size = 20`
- `]`

**Implementation note:** `CResourcePickup.resource_type` is typed `Script`. Set it to the `r_food.gd` script file in the editor inspector. Do not set it to a RFood instance — it's the Script class itself.

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Commit**

```bash
git add resources/recipes/food_pile.tres
git commit -m "feat(recipe): add food_pile — pickable food resource

Components: CTransform, CCollision(r=10), CResourcePickup(RFood, 1),
CLifeTime(120s), CLabelDisplay(🍖, 20). Dropped by rabbit death;
picked up on player overlap within RESOURCE_PICKUP_RADIUS."
```

---

### Task 25: `grass.tres` recipe

**Files:**
- Create: `resources/recipes/grass.tres`

- [ ] **Step 1: Create `grass.tres` via Godot editor**

Create `EntityRecipe` at `res://resources/recipes/grass.tres`:
- `recipe_id = "grass"`
- `display_name = "草"`
- `components = [`:
  - `CTransform`
  - `CCollision` with `collision_shape = CircleShape2D(radius=12)`
  - `CEatable` with `hunger_restore = 30.0` (matches `HUNGER_PER_FOOD_UNIT`)
  - `CLifeTime` with `lifetime = 300.0` (stale grass despawn)
  - `CLabelDisplay` with `text = "🌱"`, `font_size = 20`
- `]`

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Commit**

```bash
git add resources/recipes/grass.tres
git commit -m "feat(recipe): add grass — runtime-grown eatable flora

Components: CTransform, CCollision(r=12), CEatable(30),
CLifeTime(300s), CLabelDisplay(🌱, 20). Spawned by SWorldGrowth
in WILDERNESS/SUBURBS. Consumed by rabbit's EatGrass action."
```

---

### Task 26: `rabbit.tres` recipe

**Files:**
- Create: `resources/recipes/rabbit.tres`

- [ ] **Step 1: Create `rabbit.tres` via Godot editor**

Create `EntityRecipe` at `res://resources/recipes/rabbit.tres`:
- `recipe_id = "rabbit"`
- `display_name = "野兔"`
- `components = [`:
  - `CTransform`
  - `CMovement` with `max_speed = 140.0`
  - `CHP` with `max_hp = 5.0`, `hp = 5.0`
  - `CCamp` with `camp = CCamp.CampType.NEUTRAL` (integer value 2)
  - `CCollision` (default shape; a small collision body)
  - `CPerception` with `vision_range = 180.0`
  - `CGoapAgent` with `goals = [survive_on_sight.tres, feed_self.tres, wander.tres]`
  - `CHunger` with `max_hunger = 60.0`, `hunger = 60.0`
  - `CLootDrop` with `loot_id = "rabbit"`
  - `CLabelDisplay` with `text = "🐰"`, `font_size = 24`
- `]`

Deliberately NOT included: `CAnimation`, `CSemanticTranslation`, `CMelee`, `CWeapon`, `CElementalAffliction`.

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Quick manual spawn smoke test**

Dispatch to `gol-test-runner` (playtest):
> Launch the game, open the debug console, run `spawn entity rabbit`. Verify: (1) a 🐰 emoji appears in the world, (2) no runtime errors in the log, (3) if the player approaches, the rabbit sets `movement.velocity` in the opposite direction (check logs, or screenshot the rabbit position over time).

- [ ] **Step 4: Commit**

```bash
git add resources/recipes/rabbit.tres
git commit -m "feat(recipe): add rabbit — first env creature

NEUTRAL camp, HP 5, max_speed 140, vision 180, hunger 60. Goals:
survive_on_sight(100) > feed_self(50) > wander(1). Drops food_pile
on death via CLootDrop(loot_id=rabbit). Placeholder 🐰 visual."
```

---

## Phase 6 — PCG Integration (Task 27–29)

### Task 27: Extend `PCGContext` with `creature_spawners` buffer

**Files:**
- Modify: `scripts/pcg/pipeline/pcg_context.gd`
- Modify: `scripts/pcg/data/pcg_result.gd`

- [ ] **Step 1: Read current `pcg_context.gd` and `pcg_result.gd`**

- [ ] **Step 2: Add buffer and helper to `PCGContext`**

Append to `scripts/pcg/pipeline/pcg_context.gd` (preserving existing code):

```gdscript
## Creature spawner specs accumulated by CreatureSpawnerPlacer phase.
## Each spec is a Dictionary with keys matching the phase's add_creature_spawner.
var creature_spawners: Array[Dictionary] = []


## Phase helper: record a creature spawner placement for post-PCG instantiation.
func add_creature_spawner(spec: Dictionary) -> void:
	creature_spawners.append(spec)
```

- [ ] **Step 3: Expose `creature_spawners` on `PCGResult`**

Modify `scripts/pcg/data/pcg_result.gd`:
- Add `var creature_spawners: Array[Dictionary] = []` field.
- Add constructor parameter or setter — match the existing init pattern (the result is built in `pcg_pipeline.gd:24`).

Update `PCGPipeline.generate` in `scripts/pcg/pipeline/pcg_pipeline.gd` to pass `context.creature_spawners` into `PCGResult.new(...)`. Since the existing constructor is:
```gdscript
PCGResult.new(effective_config, context.road_graph, null, null, context.grid)
```
add the new field to `PCGResult`'s init signature at the end:
```gdscript
PCGResult.new(effective_config, context.road_graph, null, null, context.grid, context.creature_spawners)
```
And update `PCGResult._init` (or its constructor equivalent) to accept and store the array.

- [ ] **Step 4: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 5: Commit**

```bash
git add scripts/pcg/pipeline/pcg_context.gd scripts/pcg/data/pcg_result.gd scripts/pcg/pipeline/pcg_pipeline.gd
git commit -m "feat(pcg): add creature_spawners buffer to Context + Result

Creature spawner specs accumulate in PCGContext during phases and
surface on PCGResult for post-PCG consumers (gol_world.gd). Spec
dict keys: recipe_id, cell, active_condition, spawn_interval,
spawn_radius, max_spawn_count."
```

---

### Task 28: `CreatureSpawnerPlacer` PCG phase

**Files:**
- Create: `scripts/pcg/phases/creature_spawner_placer.gd`
- Modify: `scripts/pcg/pipeline/pcg_phase_config.gd` (phase registration + name)

- [ ] **Step 1: Create the phase**

```gdscript
# scripts/pcg/phases/creature_spawner_placer.gd
class_name CreatureSpawnerPlacer
extends PCGPhase
## PCG phase: scatters creature-spawner specs into PCGContext based
## on zone eligibility. Does not create world entities — the
## post-PCG consumer (gol_world.gd) materializes spawners.
##
## Reads zone info from PCGContext.grid (unified grid, each PCGCell
## carries zone_type as int matching ZoneMap.ZoneType). Uses
## context.randf() for deterministic rolls.

const RABBIT_PER_CELL_CHANCE: float = 0.015


func execute(_config: PCGConfig, context: PCGContext) -> void:
	if context == null or context.grid == null:
		return

	for pos: Variant in context.grid.keys():
		if not (pos is Vector2i):
			continue
		var cell = context.grid[pos]
		if cell == null:
			continue
		# Skip URBAN; allow WILDERNESS + SUBURBS (anything non-urban).
		var zone_type: int = cell.zone_type
		if zone_type == ZoneMap.ZoneType.URBAN:
			continue
		if context.randf() > RABBIT_PER_CELL_CHANCE:
			continue
		context.add_creature_spawner({
			"recipe_id": "rabbit",
			"cell": pos,
			"active_condition": CSpawner.ActiveCondition.DAY_ONLY,
			"spawn_interval": 30.0,
			"spawn_radius": 128.0,
			"max_spawn_count": 3,
		})
```

- [ ] **Step 2: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 3: Register in `pcg_phase_config.gd`**

Modify `scripts/pcg/pipeline/pcg_phase_config.gd`. Add preload:

```gdscript
const CreatureSpawnerPlacer := preload("res://scripts/pcg/phases/creature_spawner_placer.gd")
```

Add to `PHASE_NAMES` array (keep it in sequence — insert after "Zone Smoother"):

```gdscript
const PHASE_NAMES: Array[String] = [
	"Empty",
	"Irregular Grid",
	"Road Rasterizer",
	"Zone Calculator",
	"Zone Smoother",
	"Creature Spawner Placer",   # NEW — after zones are finalized, before POIs
	"Organic Subdivider",
	"POI Generator",
	"Tile Resolve",
	"Tile Decide"
]
```

Add to `create_phases()` in the same sequence position:

```gdscript
static func create_phases() -> Array[PCGPhase]:
	var phases: Array[PCGPhase] = []
	phases.append(IrregularGridGenerator.new())
	phases.append(RoadRasterizer.new())
	phases.append(ZoneCalculator.new())
	phases.append(ZoneSmoother.new())
	phases.append(CreatureSpawnerPlacer.new())   # NEW — reads zones, writes spawner specs
	phases.append(OrganicBlockSubdivider.new())
	phases.append(POIGenerator.new())
	phases.append(TileResolvePhase.new())
	phases.append(TileDecidePhase.new())
	return phases
```

- [ ] **Step 4: Godot parse check (post-registration)**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 5: Delegate integration playtest**

Dispatch to `gol-test-runner` (playtest):
> Launch the game, generate a fresh PCG world. From the debug console or via a test harness, read `ServiceContext.pcg().last_result.creature_spawners`. Expect: a non-empty array (> 0 entries for a normally sized world), each entry has keys `recipe_id=="rabbit"`, `cell` (Vector2i), `active_condition`, `spawn_interval`, `spawn_radius`, `max_spawn_count`. Report count.

- [ ] **Step 6: Commit**

```bash
git add scripts/pcg/phases/creature_spawner_placer.gd scripts/pcg/pipeline/pcg_phase_config.gd
git commit -m "feat(pcg): add CreatureSpawnerPlacer phase for rabbits

Scatters rabbit spawner specs (DAY_ONLY, max=3 per spawner) into
WILDERNESS + SUBURBS cells at 1.5% per-cell chance. Registered
in PCGPhaseConfig after ZoneSmoother, before OrganicBlockSubdivider.
Specs accumulate in PCGContext for gol_world to materialize."
```

---

### Task 29: `gol_world.gd` — instantiate creature spawners

**Files:**
- Modify: `scripts/gameplay/ecs/gol_world.gd`

- [ ] **Step 1: Read `gol_world.gd`**

Find where `pcg_result` is consumed and where trees are placed (`create_entity_by_id("tree")` call site around line 595). The creature-spawner loop runs in the same region.

- [ ] **Step 2: Add creature-spawner placement logic**

After the tree-placement block (or wherever feels structurally adjacent), add:

```gdscript
func _place_creature_spawners(pcg_result: PCGResult) -> void:
	if pcg_result == null:
		return
	if pcg_result.creature_spawners == null or pcg_result.creature_spawners.is_empty():
		return

	# Tile size comes from PCGConfig; mirror the poi_generator pattern.
	# poi_generator.gd:9 uses: config.get("tile_size", 32) with default 32.
	var tile_size: int = 32
	if pcg_result.config != null:
		var ts: Variant = pcg_result.config.get("tile_size")
		if ts != null:
			tile_size = int(ts)

	for spec in pcg_result.creature_spawners:
		var recipe_id: String = String(spec.get("recipe_id", ""))
		if recipe_id == "":
			continue
		var cell: Vector2i = spec.get("cell", Vector2i.ZERO)
		var pos := Vector2(
			cell.x * tile_size + tile_size * 0.5,
			cell.y * tile_size + tile_size * 0.5)

		var entity := Entity.new()
		entity.name = StringName("creature_spawner_%s" % recipe_id)

		var t := CTransform.new()
		t.position = pos
		entity.add_component(t)

		var sp := CSpawner.new()
		sp.spawn_recipe_id = recipe_id
		sp.spawn_interval = float(spec.get("spawn_interval", 30.0))
		sp.spawn_interval_variance = sp.spawn_interval * 0.2
		sp.spawn_count = 1
		sp.spawn_radius = float(spec.get("spawn_radius", 128.0))
		sp.max_spawn_count = int(spec.get("max_spawn_count", 3))
		sp.active_condition = spec.get("active_condition", CSpawner.ActiveCondition.ALWAYS)
		entity.add_component(sp)

		ECS.world.add_entity(entity)
		print("[GOLWorld] Placed creature spawner '%s' at cell %s → %s" %
			[recipe_id, cell, pos])
```

Then call `_place_creature_spawners(pcg_result)` from the world-build sequence, next to the existing tree placement logic. Concretely: find the function that is invoked during world setup where `ServiceContext.pcg().last_result` is already populated and `ECS.world` is live — the tree-scattering code is in the same neighborhood (grep `create_entity_by_id("tree")` → surrounding function).

- [ ] **Step 3: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 4: Delegate playtest verification**

Dispatch to `gol-test-runner` (playtest):
> Launch game, generate world. Wait for day-time. Verify:
> 1. Console logs contain `[GOLWorld] Placed creature spawner 'rabbit' at cell ...` entries.
> 2. After 30s–60s of daytime, 🐰 emoji entities appear in the world.
> 3. No spawners appear in tiles known to be URBAN.
> 4. At night, no new rabbits appear.

- [ ] **Step 5: Commit**

```bash
git add scripts/gameplay/ecs/gol_world.gd
git commit -m "feat(world): materialize creature spawners from PCG result

Consumes pcg_result.creature_spawners and creates a
[CTransform + CSpawner] entity per spec. Spawners have no CHP —
they're passive infrastructure, not destructible buildings."
```

---

## Phase 7 — UI + Debug Wiring (Task 30–31)

### Task 30: HUD — RFood binding

**Files:**
- Modify: `scripts/ui/viewmodels/viewmodel_hud.gd`
- Modify (optional): `scripts/ui/views/view_hud.gd` — add a food label if it doesn't exist
- Modify (optional): `scenes/ui/view_hud.tscn` — add food panel node

- [ ] **Step 1: Read current `viewmodel_hud.gd`**

Note the existing `wood_count` ObservableProperty pattern (lines 12, 23, 56–66).

- [ ] **Step 2: Add `food_count` observable mirroring wood**

Modify `scripts/ui/viewmodels/viewmodel_hud.gd`:

Add at top:
```gdscript
const RFood = preload("res://scripts/resources/r_food.gd")
```

Add observable:
```gdscript
var food_count : ObservableProperty = ObservableProperty.new(0)
```

In `setup()`, append:
```gdscript
_bind_food_count()
```

In `teardown()`, append:
```gdscript
food_count.teardown()
```

Add bind function (mirrors `_bind_wood_count` exactly — rebinds to same camp stockpile):

```gdscript
func _bind_food_count() -> void:
	# Reuses camp stockpile; wood_count binding already established it.
	# If _camp_stockpile hasn't been resolved yet, resolve now.
	if _camp_stockpile == null:
		var camp_entity: Entity = _find_entity_with([CStockpile], [CPlayer])
		if camp_entity == null:
			food_count.set_value(0)
			return
		_camp_stockpile = camp_entity.get_component(CStockpile)

	food_count.set_value(_camp_stockpile.get_amount(RFood))
	# Subscribe for both wood and food to the same stockpile signal;
	# the wood subscription already exists. Add a food callback.
	var food_sub = func(_contents):
		food_count.set_value(_camp_stockpile.get_amount(RFood))
	_camp_stockpile.changed_observable.subscribe(food_sub)
	# Track this subscription so teardown can unsubscribe cleanly.
	# (If the file doesn't already have a _camp_stockpile_subs list,
	# add one; otherwise reuse the existing subscription-tracking pattern.)
```

**Implementation note for this step:** the existing file tracks one `_camp_stockpile_sub` callable. For two subscribers (wood + food), convert to an array `_camp_stockpile_subs: Array[Callable]` or keep two named fields (`_camp_stockpile_wood_sub`, `_camp_stockpile_food_sub`) and update teardown to iterate. Choose whichever matches the codebase's style.

- [ ] **Step 3: Update the HUD view (if applicable)**

If the HUD view has a visible wood counter widget, duplicate its binding for food. Otherwise, skip this step and verify via debug console (`GOL.Tables` is not involved, but the observable will tick; visual display can come later).

- [ ] **Step 4: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 5: Delegate playtest smoke**

Dispatch to `gol-test-runner` (playtest):
> Spawn food_pile via `spawn entity food_pile`. Walk the player over it. Verify that in-game: (a) the food_pile disappears, (b) if a wood counter is shown in the HUD, verify the food counter (if added) increments. If no visual food display, verify via an inspect command or logging that `viewmodel_hud.food_count.value == 1`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/viewmodels/viewmodel_hud.gd scripts/ui/views/view_hud.gd scenes/ui/view_hud.tscn
git commit -m "feat(hud): bind RFood to viewmodel_hud.food_count

Mirrors the RWood binding pattern to the same camp stockpile.
Food pickup → stockpile.add → observable fires → HUD updates."
```

---

### Task 31: `HungerCommand` debug console

**Files:**
- Create: `scripts/debug/console/commands/hunger_command.gd`
- Modify: `scripts/debug/console/console_registry.gd`

- [ ] **Step 1: Read an existing command for template (e.g., `damage_command.gd`)**

Match the class style, `build()` pattern, Callable binding, `ConsoleContext` usage.

- [ ] **Step 2: Create `hunger_command.gd`**

```gdscript
# scripts/debug/console/commands/hunger_command.gd
class_name HungerCommand
extends ConsoleCommandModule
## Debug console for hunger state:
##   /hunger set <entity> <value>
##   /hunger stockpile [amount]   # default 10

const RFood = preload("res://scripts/resources/r_food.gd")


func build() -> Array:
	return [
		Spec.CommandSpec.category("hunger", "Hunger debug", [
			Spec.SubcommandSpec.new(
				"set",
				"Set an entity's CHunger.hunger",
				[
					Spec.ParamSpec.required("target", Types.ENTITY),
					Spec.ParamSpec.required("value", Types.FLOAT),
				],
				Callable(self, "_set_hunger")
			),
			Spec.SubcommandSpec.new(
				"stockpile",
				"Add RFood to camp stockpile",
				[
					Spec.ParamSpec.optional("amount", Types.INT, 10),
				],
				Callable(self, "_add_stockpile_food")
			),
		])
	]


func _set_hunger(_ctx: ConsoleContext, args: Dictionary) -> String:
	var target: Entity = args.target
	if target == null or not is_instance_valid(target):
		return "Error: invalid target"
	var h := target.get_component(CHunger) as CHunger
	if h == null:
		return "Error: target has no CHunger"
	var value: float = float(args.value)
	h.hunger = clamp(value, 0.0, h.max_hunger)
	return "Set hunger of %s to %.1f / %.1f" % [target.name, h.hunger, h.max_hunger]


func _add_stockpile_food(_ctx: ConsoleContext, args: Dictionary) -> String:
	var amount: int = int(args.amount)
	if amount <= 0:
		return "Error: amount must be positive"

	var camp_entities := ECS.world.query.with_all([CStockpile]).with_none([CPlayer]).execute()
	if camp_entities.is_empty():
		return "Error: camp stockpile not found"
	var stockpile := camp_entities[0].get_component(CStockpile) as CStockpile
	if stockpile == null:
		return "Error: camp stockpile entity has no CStockpile component"

	stockpile.add(RFood, amount)
	return "Added %d RFood to camp stockpile (total: %d)" % [amount, stockpile.get_amount(RFood)]
```

- [ ] **Step 3: Register in `console_registry.gd`**

Add to the `_MODULES` array:

```gdscript
const _MODULES: Array = [
	preload("res://scripts/debug/console/commands/spawn_command.gd"),
	preload("res://scripts/debug/console/commands/add_command.gd"),
	preload("res://scripts/debug/console/commands/damage_command.gd"),
	preload("res://scripts/debug/console/commands/remove_command.gd"),
	preload("res://scripts/debug/console/commands/basic_commands.gd"),
	preload("res://scripts/debug/console/commands/refresh_command.gd"),
	preload("res://scripts/debug/console/commands/time_command.gd"),
	preload("res://scripts/debug/console/commands/hunger_command.gd"),  # NEW
]
```

- [ ] **Step 4: Godot parse check**

```bash
godot --headless --quit --path . 2>&1 | grep -E "(ERROR|SCRIPT ERROR)" || echo "No parse errors"
```

- [ ] **Step 5: Delegate console playtest**

Dispatch to `gol-test-runner` (playtest):
> In-game: open debug console. Run:
> 1. `/hunger stockpile 5` → expect "Added 5 RFood to camp stockpile (total: 5)"
> 2. Spawn a rabbit: `/spawn entity rabbit`
> 3. `/hunger set <rabbit_name> 10` → expect confirmation
> 4. After ~30s observe rabbit hunger decay via repeated `/hunger set <rabbit> <current>` queries or log inspection; verify rabbit eventually triggers `feed_self` goal if grass is nearby.

- [ ] **Step 6: Commit**

```bash
git add scripts/debug/console/commands/hunger_command.gd scripts/debug/console/console_registry.gd
git commit -m "feat(debug): add /hunger set and /hunger stockpile commands

/hunger set <entity> <value> — override hunger on any CHunger entity.
/hunger stockpile <amount> — add RFood to camp stockpile."
```

---

## Phase 8 — Integration Tests (Task 32–35)

Integration tests exercise multiple systems via `SceneConfig`. Dispatch all test writes to `gol-test-writer` (integration).

### Task 32: Integration test — rabbit lifecycle

**Files:**
- Test: `tests/integration/creatures/test_rabbit_lifecycle.gd`

- [ ] **Step 1: Delegate integration test write**

Dispatch to `gol-test-writer` (integration):
> Target: `tests/integration/creatures/test_rabbit_lifecycle.gd`. Use `SceneConfig` to build a minimal level: camp stockpile, player (at origin), one rabbit at (100, 0), one zombie prepared but initially far away.
>
> Scenario:
> 1. Tick 5 seconds of simulated time. Verify rabbit wandered (position ≠ initial spawn to within small tolerance, OR at least velocity was non-zero at some point).
> 2. Move zombie to (150, 0) (within rabbit's 180 vision). Tick 3 seconds. Verify rabbit's distance from zombie INCREASED (it fled).
> 3. Apply lethal damage to rabbit via `CHP.hp = 0` then tick enough for SDead to run `_complete_death`. Verify: rabbit entity removed from world AND a food_pile entity exists within 24 px of rabbit's death position.
>
> Use existing integration test patterns from `tests/integration/flow/`.

- [ ] **Step 2: Delegate test run**

Dispatch to `gol-test-runner`: run the test. Expect PASS. If FAIL, capture the specific assertion that failed and the diagnostic output; return for fix.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/creatures/test_rabbit_lifecycle.gd
git commit -m "test(integration): rabbit lifecycle — wander, flee, drop food

End-to-end: rabbit wanders, flees zombie, killed, food_pile drops
at death position."
```

---

### Task 33: Integration test — food pickup to stockpile

**Files:**
- Test: `tests/integration/creatures/test_food_pickup_to_stockpile.gd`

- [ ] **Step 1: Delegate integration test write**

Dispatch to `gol-test-writer` (integration):
> Target: `tests/integration/creatures/test_food_pickup_to_stockpile.gd`. Setup: SceneConfig with camp stockpile + player at (0, 0) + a `food_pile` entity at (10, 0) (within RESOURCE_PICKUP_RADIUS=24).
>
> Scenario:
> 1. Tick one frame of `gameplay` group. Verify: food_pile entity is gone (queued_free or removed), camp stockpile `get_amount(RFood) == 1`.
> 2. viewmodel_hud.food_count observable value == 1.
> 3. Second scenario (separate test method): food_pile at (100, 0) — outside pickup radius. Tick. Verify food_pile still exists, stockpile still 0.

- [ ] **Step 2: Delegate test run**

Dispatch to `gol-test-runner`: run the test. Expect PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/creatures/test_food_pickup_to_stockpile.gd
git commit -m "test(integration): food pickup deposits to camp stockpile

Inside radius → pickup removed, RFood += 1, HUD observable ticks.
Outside radius → no change."
```

---

### Task 34: Integration test — auto-feed loop

**Files:**
- Test: `tests/integration/creatures/test_auto_feed_loop.gd`

- [ ] **Step 1: Delegate integration test write**

Dispatch to `gol-test-writer` (integration):
> Target: `tests/integration/creatures/test_auto_feed_loop.gd`. Setup: camp stockpile with 5 RFood; player with `CHunger(max=200, hunger=50)`.
>
> Scenario:
> 1. Tick gameplay group for at least `AUTO_FEED_TICK_INTERVAL` (0.5s). Verify: player.hunger == 200 (consumed 5 units × 30 = 150, capped at 200), stockpile has 0 RFood.
> 2. Second test: player hunger=190 (deficit 10). Tick. Verify no consumption (atomic rule), hunger unchanged, stockpile unchanged.
> 3. Third test: continue decay — no food in stockpile, player hunger=200. Tick 3 seconds. Verify hunger has decayed by ≈ 3.0 (DECAY_PER_SEC=1.0).

- [ ] **Step 2: Delegate test run**

Dispatch to `gol-test-runner`: run the test. Expect PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/creatures/test_auto_feed_loop.gd
git commit -m "test(integration): auto-feed — prioritized atomic stockpile drain

Player with deficit ≥ 30 eats from stockpile until full or stockpile
empty. Partial-deficit case: no consumption. No-food case: decay
continues."
```

---

### Task 35: Integration test — rabbit forages grass

**Files:**
- Test: `tests/integration/creatures/test_rabbit_forages_grass.gd`

- [ ] **Step 1: Delegate integration test write**

Dispatch to `gol-test-writer` (integration):
> Target: `tests/integration/creatures/test_rabbit_forages_grass.gd`. Setup: rabbit at (0, 0) with `CHunger(max=60, hunger=20)` (below hungry_threshold 0.5*60=30); one grass at (50, 0); no threats.
>
> Scenario:
> 1. Tick gameplay group for up to 10 seconds of simulated time. Verify at some point during that window: grass entity is removed from world AND rabbit.hunger increased by ≈ CEatable.hunger_restore (30.0, so hunger goes from 20 → 50, clamped if max is lower).
> 2. After consumption, rabbit resumes wander (verify `feed_self` goal is no longer active via inspecting `CGoapAgent.world_state["is_fed"]` becoming true, or movement pattern reverts).

- [ ] **Step 2: Delegate test run**

Dispatch to `gol-test-runner`: run the test. Expect PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/integration/creatures/test_rabbit_forages_grass.gd
git commit -m "test(integration): rabbit forages — chain MoveToGrass → EatGrass

Hungry rabbit with visible grass walks to it, eats it, hunger
restored, grass removed."
```

---

## Phase 9 — Final Verification (Task 36)

### Task 36: Full smoke playtest + documentation refresh

**Files:**
- (No code changes — verification only)
- Optional: update `scripts/components/AGENTS.md`, `scripts/systems/AGENTS.md`, `scripts/gameplay/AGENTS.md`, `scripts/pcg/AGENTS.md`, `scripts/debug/console/AGENTS.md` if they catalog components/systems.

- [ ] **Step 1: Run the full unit test suite**

Dispatch to `gol-test-runner`:
> Run all tests under `tests/unit/`. Expect all pass. Report any failures.

- [ ] **Step 2: Run all integration tests**

Dispatch to `gol-test-runner`:
> Run all tests under `tests/integration/`. Expect all pass. Report any failures.

- [ ] **Step 3: Delegate the full manual smoke plan**

Dispatch to `gol-test-runner` (playtest):
> Run the 9-step manual smoke plan from the spec (Section 9 Manual smoke plan), capturing screenshots at key moments:
>
> 1. Fresh PCG world: 🐰 labels in WILDERNESS/SUBURBS during day; none in URBAN cells.
> 2. Approach a rabbit → rabbit flees at ~140 px/s.
> 3. Shoot a rabbit → 🍖 appears at death position.
> 4. Walk over 🍖 → HUD RFood counter increments (if visible) or `viewmodel_hud.food_count.value` == 1.
> 5. Idle: hunger decays. With enough RFood in stockpile, SAutoFeed refills player hunger at crossing of deficit threshold.
> 6. Night: no new rabbit spawns; existing ones remain until killed.
> 7. Wait in WILDERNESS/SUBURBS → 🌱 grass sprouts over time.
> 8. Hungry rabbit (consoe: `/hunger set <rabbit> 10`) + visible 🌱 → rabbit walks to grass, eats it, grass vanishes.
> 9. Debug commands work: `/spawn entity rabbit`, `/spawn entity grass`, `/spawn entity food_pile`, `/hunger set <e> <v>`, `/hunger stockpile <n>`.
>
> For each step report PASS/FAIL and any error log lines.

- [ ] **Step 4: Update AGENTS.md catalogs if they list components/systems**

Check `scripts/components/AGENTS.md`, `scripts/systems/AGENTS.md` for component/system listing tables. If they exist and catalog additions, add rows for:
- Components: `CHunger`, `CEatable`, `CLootDrop`, `CResourcePickup`, `CLabelDisplay` (TEMPORARY)
- Systems: `SHunger`, `SAutoFeed`, `SResourcePickup`, `SWorldGrowth`, `SLabelDisplay` (TEMPORARY)
- PCG phases: `CreatureSpawnerPlacer`
- GOAP actions: `GoapAction_FleeOnSight`, `GoapAction_MoveToGrass`, `GoapAction_EatGrass`
- Goals: `survive_on_sight`, `feed_self`
- Recipes: `rabbit`, `food_pile`, `grass`

- [ ] **Step 5: Commit catalog updates**

```bash
git add scripts/components/AGENTS.md scripts/systems/AGENTS.md scripts/gameplay/AGENTS.md scripts/pcg/AGENTS.md
git commit -m "docs(agents): catalog rabbit env-creature additions

New components, systems, actions, goals, recipes, and PCG phase."
```

- [ ] **Step 6: Acceptance checklist (from spec)**

Tick each acceptance criterion from the spec Section 11:
- [ ] Rabbits spawn during day, only in non-URBAN zones
- [ ] Rabbits flee from player
- [ ] Rabbits flee from zombies
- [ ] Rabbits wander when no threats visible
- [ ] Shooting a rabbit kills it; food_pile appears
- [ ] Walking over food_pile increments camp RFood stockpile
- [ ] Player hunger decays over time
- [ ] When player deficit ≥ 30 and RFood > 0, stockpile drains, hunger restores
- [ ] Grass grows in non-URBAN zones over time (up to world_cap)
- [ ] Hungry rabbits walk to grass, eat it, restoring their own hunger
- [ ] All automated tests pass
- [ ] Debug commands `spawn entity rabbit`, `spawn entity grass`, `spawn entity food_pile`, `hunger set`, `hunger stockpile` all work

- [ ] **Step 7: Final commit (if any cleanup remains)**

```bash
git status
# Review; if anything uncommitted from test fixes or doc tweaks, commit.
```

---

## Appendix A — Why Tests Live Where They Do

| Layer | Where | Why |
|---|---|---|
| Tables | `tests/unit/tables/` | Static data schema — pure data validation; isolated from ECS |
| Components | `tests/unit/` | Matches existing `test_c_*.gd` placement |
| Systems | `tests/unit/` | Matches existing `test_s_*.gd` placement — mock-based |
| GOAP actions | `tests/unit/` | Matches existing `test_goap_action_*.gd` placement |
| Integration | `tests/integration/creatures/` | New subdirectory for creature-system integration tests |

## Appendix B — Dependency Graph (execution order)

```
Phase 1 (Foundation)        Phase 2 (Components)
  1. CCamp NEUTRAL              8. CLootDrop
  2. RFood                      9. CResourcePickup
  3. Config                    10. CHunger
  4. LootTable                 11. CEatable
  5. GrowthTable               12. CLabelDisplay
  6. HungerTable
  7. GOL.Tables ─────────┐
                          │
                          ▼
Phase 3 (Systems — depend on Tasks 1,2,8–12)
  13. SPerception
  14. SDead loot hook (needs LootTable, CLootDrop)
  15. SResourcePickup (needs CResourcePickup, RFood)
  16. SHunger (needs CHunger, HungerTable)
  17. SAutoFeed (needs CHunger, CCamp, HungerTable)
  18. SWorldGrowth (needs GrowthTable)
  19. SLabelDisplay (needs CLabelDisplay)

Phase 4 (GOAP — depend on Phase 2 + 3)
  20. FleeOnSight (needs CPerception with multi-camp = Task 13)
  21. MoveToGrass (needs CEatable, SPerception blackboard)
  22. EatGrass (needs CHunger, CEatable)
  23. Goal .tres files

Phase 5 (Recipes — depend on all of above)
  24. food_pile.tres
  25. grass.tres
  26. rabbit.tres (needs goal .tres from Task 23)

Phase 6 (PCG — depends on ZoneSmoother + Phase 5 recipes)
  27. PCGContext buffer
  28. CreatureSpawnerPlacer phase
  29. gol_world consumer

Phase 7 (UI + Debug — depends on Phase 2 components + Phase 5 recipes)
  30. HUD RFood binding
  31. HungerCommand

Phase 8 (Integration tests — depend on everything)
  32. rabbit lifecycle
  33. food pickup to stockpile
  34. auto-feed loop
  35. rabbit forages grass

Phase 9 (Verification)
  36. Full smoke + acceptance
```

Phases 1–2 can run in arbitrary order within themselves. Phase 3+ must follow. Within Phase 3, tasks are independent of each other (but all depend on Phase 1 + 2 completion).
