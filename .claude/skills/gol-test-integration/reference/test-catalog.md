# Integration Test Catalog — Golden Examples

## Purpose
Complete catalog of all existing SceneConfig integration tests.
Use these as reference implementations when writing new tests.
Each entry shows: pattern class, systems rationale, entity design, assertion strategy, unique helpers.

## Summary Table

| # | File | Class Name | Pattern | Systems | Entities | Assertions | Lines |
|---|------|-----------|---------|---------|-----------|------------|-------|
| 1 | test_combat.gd | TestCombatConfig | combat-flow | 3 | 2 | 4 | 64 |
| 2 | test_teardown_cleanup.gd | TestTeardownCleanupConfig | custom/regression | 0 | 1 | 4 | 69 |
| 3 | test_pcg_map.gd | TestPCGMapConfig | pcg-pipeline | 1 | 0 | 3 | 38 |
| 4 | test_flow_composer_scene.gd | TestComposerFlowConfig | crafting-flow | 1 | 2 | ~8 | 133 |
| 5 | test_flow_composer_interaction_scene.gd | TestComposerInteractionFlowConfig | ui-interaction | 2 | 0 (default) | ~10 | 184 |
| 6 | test_flow_blueprint_drop_scene.gd | TestBlueprintDropConfig | death-drop | 2 | 2 | ~5 | 86 |
| 7 | test_flow_console_spawn_scene.gd | TestConsoleSpawnSceneConfig | console-command | 0 | 1 | ~8 | 161 |
| 8 | test_flow_composition_cost_scene.gd | TestCompositionCostConfig | penalty-conflict | 7 | 3 | ~15 | 222 |
| 9 | test_flow_elemental_status_scene.gd | TestFlowElementalStatusConfig | elemental-propagation | 3 | 3 | ~7 | 137 |
| 10 | test_flow_component_drop_scene.gd | TestComponentDropConfig | component-flow | 4 | 2 | 11 | 159 |

---

## Detailed Entries

### 1. test_combat.gd — Basic Combat Survival
**Pattern:** `combat-flow` (simplest example — START HERE for new combat tests)
**Location:** `tests/integration/test_combat.gd`
**Lines:** 64

**Systems (3):** `s_hp`, `s_damage`, `s_dead`
- Rationale: HP tracking + damage processing + death handling = minimal combat loop
- Missing s_move/s_ai: enemies don't move or think, just exist and take environmental/passive damage

**Entities (2):**
- `player` → "TestPlayer" @ Vector2(100, 100)
- `enemy_basic` → "TestEnemy" @ Vector2(300, 100) — 200px away (no collision range)

**Test Logic:**
1. Wait 60 frames (~1 sec at 60fps)
2. Find player by iterating world.entities
3. Assert: player exists, has CHP, HP > 0 (alive)

**Assertions (4):** existence(1) + component(1) + value(1) = 3 meaningful + pattern completeness
**Helpers:** None (inline lookup)
**Key Pattern:** Timed survival check — simplest possible integration test
**Unique Notes:** Best FIRST test to study when learning the framework

---

### 2. test_teardown_cleanup.gd — Purge Regression (#194)
**Pattern:** `custom` / regression test
**Location:** `tests/integration/test_teardown_cleanup.gd`
**Lines:** 69

**Systems (0):** `[]` (empty)
- Rationale: Testing World.purge() itself, no gameplay systems needed
- Shows: tests can have empty systems array

**Entities (1):**
- `player` → "PurgeTestEntity" @ Vector2(0, 0)

**Test Logic:**
1. Double frame await for initialization
2. Find entity, capture its ID
3. Manually free the entity (simulates bug scenario)
4. Call world.purge(false) — should not crash
5. Assert: purge completed, entities empty, registry clean

**Assertions (4):** existence(1) + behavior(1) + size(1) + registry(1)
**Helpers:** None (inline lookup)
**Key Pattern:** Bug reproduction via manual object lifecycle manipulation
**Unique Notes:** Only test that calls .free() directly. Edge case for cleanup APIs.

---

### 3. pcg/test_pcg_map.gd — PCG Pipeline
**Pattern:** `pcg-pipeline`
**Location:** `tests/integration/pcg/test_pcg_map.gd`
**Lines:** 38

**Systems (1):** `s_map_render`
- Rationale: Renders PCG-generated map data to the scene

**PCG:** `enable_pcg() = true` (ONLY test with PCG enabled)

**Entities (0):** `[]` (empty — PCG generates map entities)

**Test Logic:**
1. Wait 0.5s via timer (not frame count — PCG needs real time)
2. ECS query for CMapData components
3. Assert: map entity exists, result non-null, result valid

**Assertions (3):** query-result(1) + null-check(1) + validity(1)
**Helpers:** None
**Key Patterns:**
- Uses `ECS.world.query.with_all([CMapData]).execute()` instead of name lookup
- Uses timer wait instead of frame count
- enable_pcg()=true is the differentiator
**Unique Notes:** Shortest test. Good reference for PCG-enabled tests.

---

### 4. flow/test_flow_composer_scene.gd — Composer NPC Crafting
**Pattern:** `crafting-flow`
**Location:** `tests/integration/flow/test_flow_composer_scene.gd`
**Lines:** 133

**Systems (1):** `s_pickup`
- Rationale: Crafting involves picking up blueprints and components

**Entities (2):**
- `player` → "TestPlayer" @ Vector2(100, 100)
- `npc_composer` → "TestComposer" @ Vector2(200, 100)

**Test Logic:**
1. Initialize GOL.Player (game state)
2. Clear unlocked blueprints, reset points
3. Spawn blueprint box dynamically via ServiceContext.recipe()
4. Multi-step workflow: unlock blueprint → craft fail(0pts) → dismantle → craft success → pickup auto-unlock
5. Dialogue structure validation

**Assertions (~8):** Multi-step workflow with assertion after each phase
**Helpers:** `_find()`, `_configure_composer_dialogue()`
**Key Patterns:**
- Game state initialization (GOL.Player setup)
- Dynamic entity creation outside of entities() list
- Recipe-based instantiation: `ServiceContext.recipe().create_entity_by_id("blueprint_healer")`
- Preloaded utils: COMPOSER_UTILS, CONFIG, PLAYER_DATA
**Unique Notes:** Heavily uses gameplay utility classes. Most "game-like" test.

---

### 5. flow/test_flow_composer_interaction_scene.gd — UI Interaction
**Pattern:** `ui-interaction`
**Location:** `tests/integration/flow/test_flow_composer_interaction_scene.gd`
**Lines:** 184 (MOST complex test)

**Systems (2):** `s_ui`, `s_dialogue`

**Entities (0):** `null` (uses DEFAULT scene spawning — Player + ComposerNPC from scene)

**Test Logic:**
1. Find UI nodes by script type traversal
2. Simulate keyboard input (E key) via InputEventKey + push_input
3. Verify dialogue opens, mouse mode changes
4. Emit button pressed signal programmatically
5. Check HUD reactive updates via signal emission
6. Verify distance-based interaction range

**Assertions (~10):** UI state(4) + input handling(2) + signal reactivity(2) + HUD(2)
**Helpers (8!):** `_find()`, `_find_dialogue_hint()`, `_find_dialogue_view()`, `_push_interact_input()`, `_find_name_tag_label()`, `_find_dialogue_button()`, `_find_hud_points_label()`, `_find_entity_hp_bar()`
**Key Patterns:**
- `entities() = null` for default spawning (only test doing this!)
- Node finding by `child.get_script() == SCRIPT_CLASS` (type matching, not names)
- Input simulation: InputEventKey + viewport.push_input()
- Signal-driven testing: button.pressed.emit()
- Game state mutation: GOL.Player.component_points = X; points_changed.emit()
**Unique Notes:** Most helpers (8). Only UI-focused test. Shows advanced Godot node tree manipulation.

---

### 6. flow/test_flow_blueprint_drop_scene.gd — Blueprint Drop on Death
**Pattern:** `death-drop`
**Location:** `tests/integration/flow/test_flow_blueprint_drop_scene.gd`
**Lines:** 86

**Systems (2):** `s_damage`, `s_dead`

**Entities (2):**
- `player` → "TestPlayer" @ Vector2(100, 100)
- `enemy_basic` → "TestEnemy" @ Vector2(100, 120) — VERY CLOSE (20px apart)

**Test Logic:**
1. Save/restore config.BLUEPRINT_DROP_CHANCE (set to 1.0 for determinism)
2. Attach CDamage to enemy manually
3. Trigger SDamage + SDead via damage component
4. Find dropped blueprint box by C_BLUEPRINT component
5. Assert blueprint drop succeeded
6. Restore config value (ALWAYS, even on early returns!)

**Assertions (~5):** entity(2) + damage(1) + drop(1) + config_restore(implicit)
**Helpers:** `_find_entity()`, `_find_blueprint_box()` (component-based search)
**Key Patterns:**
- Config mutation with guaranteed cleanup (save/restore pattern)
- Component-based entity finding: iterate world.entities looking for has_component(C_BLUEPRINT)
- Manual CDamage attachment to trigger damage system
**Unique Notes:** Only test that mutates global config. Shows save/restore discipline.

---

### 7. flow/test_flow_console_spawn_scene.gd — Console Commands
**Pattern:** `console-command`
**Location:** `tests/integration/flow/test_flow_console_spawn_scene.gd`
**Lines:** 161

**Systems (0):** `[]` (console is service, not system)

**Entities (1):**
- `player` → "TestPlayer" @ Vector2(100, 100)

**Test Logic:**
1. Execute console commands via ServiceContext.console().execute()
2. Validate string output (exact match and contains checks)
3. Count entities at specific positions
4. Destructive test: remove player, verify error, restore player
5. Test invalid inputs: bad count, bad recipe, missing player

**Assertions (~8):** Command output(4) + entity counting(2) + error cases(2)
**Helpers:** `_find()`, `_count_entities_at(position, excluded_names)`
**Key Patterns:**
- String-based output validation: `==` for exact, `.contains()` for partial
- Destructive testing with restoration
- Position-based entity counting with exclusion list
**Unique Notes:** Only test using console service. String-assertion heavy.

---

### 8. flow/test_flow_composition_cost_scene.gd — Penalty/Conflict Systems
**Pattern:** `penalty-conflict` (MOST SYSTEMS — 7)
**Location:** `tests/integration/flow/test_flow_composition_cost_scene.gd`
**Lines:** 222 (LONGEST test)

**Systems (7):** `s_weight_penalty`, `s_presence_penalty`, `s_fire_heal_conflict`, `s_cold_rate_conflict`, `s_electric_spread_conflict`, `s_area_effect_modifier`, `s_area_effect_modifier_render`

**Entities (3):**
- `player` → "TestPlayer" (with many runtime-added components)
- `enemy_basic` → "TestEnemyWatcher" @ Vector2(180, 100) (with custom CPerception: vision_range=600)
- `enemy_basic` → "TestPoisonAlly" @ Vector2(360, 100)

**Test Logic:**
1. Stack multiple components on player (CWeapon, CTracker, CHealer, CPoison, CElementalAttack)
2. Capture base values BEFORE penalties apply
3. Assert penalties reduce stats below base values
4. Switch elemental type (FIRE → COLD → ELECTRIC), re-assert each time
5. Create dynamic materia entities (damage/heal source, poison source, heal source)
6. Explicit cleanup between phases (remove components + entities)
7. Factory helpers for transform and camp creation

**Assertions (~15):** Base captures(3) + penalty effects(6) + elemental switching(3) + cleanup verification(3)
**Helpers (5):** `_find()`, `_make_transform(pos)`, `_make_camp(type)`, `_find_child_named(entity, name)`, `_wait_frames(world, n)`
**Key Patterns:**
- Runtime component stacking (add_component for CWeapon, CTracker, CHealer, CPoison, CElementalAttack)
- Base-vs-modified value comparison pattern
- Elemental type switching mid-test for multi-scenario coverage
- Explicit cleanup between test phases (remove components/entities before next phase)
- Factory helpers for transform and camp objects
**Unique Notes:** Most systems (7), most assertions (~15), longest (222 lines). Reference for complex multi-system tests.

---

### 9. flow/test_flow_elemental_status_scene.gd — Elemental Propagation Chain
**Pattern:** `elemental-propagation`
**Location:** `tests/integration/flow/test_flow_elemental_status_scene.gd`
**Lines:** 137

**Systems (3):** `s_melee_attack`, `s_elemental_affliction`, `s_damage`

**Entities (3):**
- `enemy_fire` → "TestEnemyFire" @ Vector2(100, 100) (WITH custom CElementalAttack overrides)
- `player` → "TestPlayer" @ Vector2(118, 100) — 18px from enemy (within melee range)
- `survivor` → "TestNearbyPlayerCamp" @ Vector2(150, 100) — propagation target

**Custom Component Overrides (in entity definition):**
```gdscript
"CElementalAttack": {
    "propagation_radius": 64.0,
    "propagation_interval": 0.01,
    "max_targets_per_tick": 1,
    "affects_same_camp": true,
    "affects_other_camp": false,
}
```

**Test Logic:**
1. Set up collision shapes programmatically (CircleShape2D + Area2D)
2. Await physics_frame + process_frame for collision
3. Trigger melee attack via direct component manipulation (cooldown=0, pending=true)
4. Assert player received CElementalAffliction with FIRE entry
5. Wait 120 frames for propagation
6. Assert nearby survivor also received FIRE affliction

**Assertions (~7):** existence(3) + collision(1) + melee_trigger(1) + affliction(1) + propagation(1)
**Helpers:** `_find()`, `_setup_collision(entity, radius)`
**Key Patterns:**
- Custom component property overrides in entity definition (ONLY test doing this extensively)
- Programmatic collision shape creation (_setup_collision helper)
- Direct component manipulation to trigger system: melee.cooldown_remaining=0; melee.attack_pending=true
- physics_frame await for collision detection (vs normal process_frame)
- Long frame wait (120) for propagation timing
- Enum-keyed dictionary: affliction.entries.has(ElementType.FIRE)
**Unique Notes:** Only test with physics_frame. Shows collision + elemental chain. Custom entity overrides are powerful pattern.

---

### 10. flow/test_flow_component_drop_scene.gd — Kill→Drop→Pickup Cycle
**Pattern:** `component-flow` (MOST COMPLETE game loop)
**Location:** `tests/integration/flow/test_flow_component_drop_scene.gd`
**Lines:** 159

**Systems (4):** `s_damage`, `s_pickup`, `s_life`, `s_dead`

**Entities (2):**
- `player` → "TestPlayer" @ Vector2(100, 100)
- `enemy_basic` → "TestEnemy" @ Vector2(100, 120) — very close (20px)

**Test Logic:**
1. Find both entities
2. Manually attach CWeapon to enemy (enemy_basic has none by default!) — attack_range=42, bullet_recipe="bullet_normal"
3. Deal lethal damage (CDamage amount=999)
4. Assert enemy loses CWeapon after death
5. Find dropped Box entity (by CContainer with stored_components)
6. Assert Box has CContainer, has stored_items, item is CWeapon
7. Assert weapon preserved original attack_range through round-trip
8. Assert Box has CLifeTime (auto-despawn)
9. Remove player's existing weapon (if any)
10. Find SPickup system instance (searches world children AND Systems node)
11. Direct system call: pickup_system._open_box(player, box, pickup)
12. Assert player gained CWeapon with correct attack_range

**Assertions (11):** Highest count — exercises complete kill→drop→pickup lifecycle
**Helpers:** `_find_entity()`, `_find_component_box()` (finds by CContainer with non-empty stored_components)
**Key Patterns:**
- Manual weapon attachment: enemy.add_component(CWeapon.new()) then set properties
- Lethal damage: CDamage.new() with amount=999, knockback_direction
- Component-based entity search: find entity where has_component(CContainer) AND container.stored_components.size() > 0
- Data integrity: capture original_range, verify after round-trip through death+drop+pickup
- System instance discovery: dual-location search (world children + world/Systems children)
- Direct system method call: bypasses input, directly invokes _open_box()
**Unique Notes:** MOST COMPLETE game mechanics test. Best reference for multi-system interaction. Shows system discovery pattern and data preservation verification.

---

## Pattern Classification Guide

### By Complexity (recommended learning order):

1. **Start here:** test_combat.gd (64 lines) — simplest, purest example
2. **Then:** test_pcg_map.gd (38 lines) — PCG variant, ECS queries
3. **Then:** test_teardown_cleanup.gd (69 lines) — edge case / regression
4. **Then:** test_blueprint_drop_scene.gd (86 lines) — death drop + config mutation
5. **Then:** test_elemental_status_scene.gd (137 lines) — collision + propagation chain
6. **Then:** test_component_drop_scene.gd (159 lines) — complete game loop
7. **Then:** test_composer_scene.gd (133 lines) — crafting + game state
8. **Then:** test_console_spawn_scene.gd (161 lines) — service layer + destructive testing
9. **Then:** test_composition_cost_scene.gd (222 lines) — multi-system penalty stress test
10. **Advanced:** test_composer_interaction_scene.gd (184 lines) — UI + input simulation

### By Pattern Type (for template selection):

| New test is about... | Study these examples |
|---|---|
| Basic combat/HP | #1 combat |
| PCG map generation | #3 pcg_map |
| Bug regression | #2 teardown_cleanup |
| Kill→drop→pickup | #10 component_drop |
| Death loot drop | #6 blueprint_drop |
| Melee→elemental→spread | #9 elemental_status |
| Crafting/blueprint | #4 composer |
| UI/dialogue/input | #5 composer_interaction |
| Console/service commands | #7 console_spawn |
| Multi-penalty systems | #8 composition_cost |
