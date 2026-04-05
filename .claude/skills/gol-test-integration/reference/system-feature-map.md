# System → Feature Mapping Reference

## Purpose

Guide for selecting which systems to register in `systems()` based on what feature you're testing. Every system in the GOL ECS architecture is cataloged here with its component dependencies, data flow, pairing requirements, and real test examples.

## Execution Groups

Systems execute in strict group order. This determines when side effects are visible:

| Group | When It Runs | What Belongs Here |
|-------|-------------|-------------------|
| **gameplay** | First (every frame) | Core logic: combat, AI, movement, spawning |
| **cost** | After gameplay | Stat modifiers that read gameplay-written values |
| **render** | After cost | Visual output: sprites, particles, shaders, maps |
| **ui** | Last | MVVM view binding and HUD initialization |

Cost systems use a **lazy-capture** pattern: first pass captures base value (`base_X < 0.0` = not yet captured), subsequent passes compute `base * modifier`. They must run AFTER the gameplay systems that set the values they modify.

---

## Complete System Catalog

### 1. SHP — HP Management (`s_hp.gd`)

**Group:** gameplay
**Query:** `CHP`

| Aspect | Detail |
|--------|--------|
| **Feature** | Invincibility frame countdown after damage |
| **Reads** | CHP.invincible_time |
| **Writes** | CHP.invincible_time (decrement) |
| **Dependencies** | None — standalone timer |
| **Pair with** | s_damage (sets invincibility), s_dead (death check) |

**What it does:** Each frame, decrements `CHP.invincible_time`. When it reaches 0, the entity can take damage again. Pure timer system with no external dependencies.

**Used in tests:** test_combat, test_player_respawn

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_hp.gd"]
entities(): [{ "recipe": "player", "name": "P" }]
```

---

### 2. SDamage — Damage Processing (`s_damage.gd`) ⭐ LARGEST SYSTEM (554 lines)

**Group:** gameplay
**Query:** `CBullet \| CDamage` (with_any)

| Aspect | Detail |
|--------|--------|
| **Feature** | Bullet collision detection, hit processing, knockback, death flow, component drops, blueprint drops |
| **Reads** | CBullet, CDamage, CTransform, CMovement, CCamp, CHP, CSpawner, CElementalAttack, CElementalAffliction, CBlueprint, CDead, CCampfire, CCollision |
| **Writes** | CHP.hp (decrease), CHP.invincible_time (set), CDamage (remove after process), CMovement.velocity (knockback), CSpawner.damage_enraged/enraged, CElementalAffliction.entries (fire dampening), CDead (add on HP≤0), CContainer (loot boxes), CBlueprint (drop boxes), CSprite (box visuals) |
| **Dependencies** | ServiceContext.console() (damage multiplier, invincibility toggle), ELEMENTAL_UTILS, Config, GOL.Game (campfire/player-down handlers) |
| **Pair with** | s_hp (invincibility timer), s_dead (death sequence), s_life (bullet expiry) |

**What it does:** The central combat hub. Processes pending CDamage markers and bullet-to-entity collisions via physics space queries. On hit: applies damage to CHP, knockback to CMovement, sets invincibility frames, triggers spawner enrage. On lethal damage (HP ≤ 0): runs component drop (lethal entities lose components into a CContainer box), blueprint chance drop, then adds CDead marker. Also handles fire affliction intensity reduction on hit.

**Death flow chain:** SDamage detects HP ≤ 0 → component loss (lethal drop) → blueprint chance drop → adds CDead → SDead consumes CDead

**Used in tests:** test_combat, test_flow_blueprint_drop, test_flow_component_drop, test_flow_elemental_status

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/s_damage.gd",
    "res://scripts/systems/s_hp.gd",
    "res://scripts/systems/s_dead.gd",
]
entities(): [
    { "recipe": "player", "name": "Player", "components": { "CTransform": { "position": Vector2(100, 100) } } },
    { "recipe": "enemy_basic", "name": "Enemy", "components": { "CTransform": { "position": Vector2(300, 100) } } },
]
```

---

### 3. SDead — Death Handling (`s_dead.gd`)

**Group:** gameplay
**Query:** `CDead + CTransform`

| Aspect | Detail |
|--------|--------|
| **Feature** | Death sequence: flash, collapse/dissolve animation, debris, entity removal/respawn |
| **Reads** | CDead, CPlayer, CSpawner, CCampfire, CMovement, CTransform |
| **Writes** | CMovement.velocity (zero/lock), CMovement.forbidden_move (true), CPlayer.is_enabled (false — player only), removes Config.DEATH_REMOVE_COMPONENTS, Entity removal from world |
| **Dependencies** | GOL.Game.handle_campfire_destroyed(), GOL.Game.handle_player_down(), Config.PLAYER_RESPAWN_DELAY, Config.DEATH_REMOVE_COMPONENTS |
| **Pair with** | s_damage (adds CDead), s_camera (respawn camera rebind), s_move (movement lock verification) |

**What it does:** Three distinct death paths:
1. **Player:** Lock movement, show death countdown UI, play death animation, respawn at campfire position after delay (creates new player entity)
2. **Spawner/Building:** Flash red + dissolve shader (no rotation collapse) + debris particles
3. **Generic (enemies):** Flash red + rotation collapse tween + debris particles

All paths remove interfering components and call `ECSUtils.remove_entity()` for cleanup.

**Used in tests:** test_combat, test_teardown_cleanup (edge case), test_flow_blueprint_drop, test_flow_component_drop, test_player_respawn

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/s_damage.gd",
    "res://scripts/systems/s_dead.gd",
    "res://scripts/systems/s_hp.gd",
]
# Add CDamage(amount=999) to target entity in test_run() to trigger death
```

---

### 4. SPickup — Item Pickup (`s_pickup.gd`)

**Group:** gameplay
**Query:** `CPickup + CTransform`

| Aspect | Detail |
|--------|--------|
| **Feature** | Container opening, item transfer between entities, blueprint unlock, box hint UI |
| **Reads** | CPickup, CTransform, CCollision, CContainer, CBlueprint, CPlayer (via GOL.Player) |
| **Writes** | CPickup.focused_box, CPickup.box_hint_view, entity components (add/remove/merge), CContainer.stored_components, Entity removal (boxes consumed on pickup) |
| **Dependencies** | ServiceContext.ui() (hint view creation), ComposerUtils (blueprint unlock logic), ECSUtils (component cap enforcement) |
| **Pair with** | s_damage + s_dead + s_life for full kill→drop→pickup cycle; s_collision for physics-based container detection |

**What it does:** Look-ahead container detection via physics space query within `CPickup.look_distance`. Four pickup paths:
1. **Blueprint pickup:** Unlocks in GOL.Player.blueprints, destroys box
2. **Required-component swap:** Removes old component, installs new one from box
3. **Add-only with cap check:** Adds component if under limit
4. **Instance-mode merge:** Direct component merge with `on_merge()` callback

**Used in tests:** test_flow_composer (blueprint unlock flow), test_flow_component_drop (full loot cycle)

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/s_damage.gd",
    "res://scripts/systems/s_pickup.gd",
    "res://scripts/systems/s_life.gd",
    "res://scripts/systems/s_dead.gd",
]
entities(): [
    { "recipe": "player", "name": "Player" },
    { "recipe": "enemy_basic", "name": "Enemy" },
]
# In test_run(): attach CWeapon to enemy, add CDamage(999) to enemy,
#   wait for death+drop, then call pickup system's _open_box() directly
```

---

### 5. SLife — Lifetime Expiration (`s_life.gd`)

**Group:** gameplay
**Query:** `CLifeTime`

| Aspect | Detail |
|--------|--------|
| **Feature** | Lifetime countdown for temporary entities (bullets, dropped boxes), camp death trigger |
| **Reads** | CLifeTime, CBullet, CCamp, CMovement |
| **Writes** | CLifeTime.lifetime (decrement), CDead (add on expiry) |
| **Dependencies** | None |
| **Pair with** | s_dead (consumes CDead on expiry), s_damage (part of damage lifecycle) |

**What it does:** Each frame decrements `CLifeTime.lifetime`. When it reaches 0, adds CDead to trigger removal. Bullets auto-expire this way. Dropped component boxes have CLifeTime for auto-despawn. If a camp (player) entity expires, triggers camp death sequence.

**Used in tests:** test_flow_component_drop (verifies boxes get CLifeTime)

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_life.gd"]
# Entities with CLifeTime component (bullets, dropped boxes)
```

---

### 6. SMeleeAttack — Melee Combat (`s_melee_attack.gd`)

**Group:** gameplay
**Query:** `CMelee`

| Aspect | Detail |
|--------|--------|
| **Feature** | Melee cooldown management, physics overlap detection, damage application, swing animation |
| **Reads** | CMelee, CTransform, CCamp, CHP, CWeapon (optional — for attack_range fallback), CElementalAttack |
| **Writes** | CMelee.cooldown_remaining, CMelee.attack_pending, CDamage (add to hit targets), CDamage.knockback_direction |
| **Dependencies** | ELEMENTAL_UTILS.apply_attack(), ServiceContext.console() (player damage multiplier), ECSUtils (enemy/night checks) |
| **Pair with** | s_damage (processes CDamage), s_elemental_affliction (elemental melee chains), s_collision (Area2D shapes must exist for overlap query) |

**What it does:** When `CMelee.attack_pending == true` and cooldown is ready: performs physics shape query (CircleShape2D) at entity position with `CMelee.attack_range`. Filters targets by camp (no friendly fire). Applies player damage multiplier. Night attack speed boost for enemies. Triggers swing tween animation. Creates CDamage on each hit target. If attacker has CElementalAttack, applies elemental affliction via `ELEMENTAL_UTILS.apply_attack()`.

**Critical test setup note:** You MUST manually create CollisionShape2D + Area2D for each entity before melee can detect overlaps. See test_flow_elemental_status_scene.gd's `_setup_collision()` pattern.

**Used in tests:** test_flow_elemental_status

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/s_melee_attack.gd",
    "res://scripts/systems/s_elemental_affliction.gd",
    "res://scripts/systems/s_damage.gd",
]
entities(): [
    { "recipe": "enemy_fire", "name": "Attacker" },
    { "recipe": "player", "name": "Target" },
]
# Manual setup required: create Area2D + CollisionShape2D for overlap detection
# Manual trigger: set cooldown_remaining=0, attack_pending=true on attacker
```

---

### 7. SElementalAffliction — Elemental Status Engine (`s_elemental_affliction.gd`) ⭐ COMPLEX (234 lines)

**Group:** gameplay
**Query:** `CElementalAffliction + CTransform`

| Aspect | Detail |
|--------|--------|
| **Feature** | Per-element tick processing (DoT, propagation, movement modifiers), freeze mechanic, elemental synergies |
| **Reads** | CElementalAffliction, CTransform, CDead (exclude dead), CCamp, CMovement, CHP |
| **Writes** | CElementalAffliction.entries (tick decay, removal of expired), CDamage (queue fire/electric DoT), CMovement.max_speed (cold slow), CMovement.velocity (freeze = zero), CMovement.forbidden_move (freeze lock), removes CElementalAffliction entirely when empty |
| **Dependencies** | ELEMENTAL_UTILS.apply_payload() (propagation), Config constants (freeze thresholds, damage amounts) |
| **Pair with** | s_melee_attack or s_damage (sources of affliction), s_elemental_visual (particle rendering), all 3 conflict cost systems (read elemental state) |

**Four element types processed per tick:**

| Element | Effect | Special Behavior |
|---------|--------|-----------------|
| **FIRE** | DoT damage per tick (CDamage) | Fire damage reduces fire affliction intensity (extinguishing) |
| **ELECTRIC** | DoT damage per tick (CDamage) | Wet + Electric synergy: 1.75x damage multiplier |
| **COLD** | Reduces CMovement.max_speed | Intensity threshold triggers **freeze**: velocity=0, forbidden_move=true, cooldown period. Wet + Cold synergy: bonus intensity toward freeze |
| **WET** | No direct damage | Modifier for other elements: boosts electric, accelerates cold freeze |

**Propagation:** Spreads to nearby entities within `CElementalAttack.propagation_radius`. Modes: stack (additive intensity) or refresh (reset timer). Respects `affects_same_camp` / `affects_other_camps` flags.

**Used in tests:** test_flow_elemental_status, test_flow_composition_cost

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/s_melee_attack.gd",
    "res://scripts/systems/s_elemental_affliction.gd",
    "res://scripts/systems/s_damage.gd",
]
entities(): [
    { "recipe": "enemy_fire", "name": "FireEnemy" },  # Has CElementalAttack(FIRE)
    { "recipe": "player", "name": "Target" },
    { "recipe": "survivor", "name": "NearbyAlly" },     # Propagation target
]
```

---

### 8. SCollision — Collision Detection (`s_collision.gd`)

**Group:** gameplay
**Query:** `CCollision`

| Aspect | Detail |
|--------|--------|
| **Feature** | Area2D + CollisionShape2D lifecycle management, position synchronization |
| **Reads** | CCollision, CTransform |
| **Writes** | CCollision.collision_shape (create if null), CCollision.area (create/manage Area2D node), CCollision.area.position (sync to CTransform), removes CCollision if no CTransform |
| **Dependencies** | None |
| **Pair with** | Required by: s_melee_attack (overlap queries), s_damage (bullet collision), s_pickup (container detection), s_trigger (zone activation) |

**What it does:** Lazy-creates Area2D + CollisionShape2D pair for entities with CCollision. Syncs area position to CTransform.position every frame. Must run in **gameplay** group (not Godot's physics group) to avoid 1-frame lag for fast-moving bullets. Cleans up Area2D if CTransform is removed.

**When you need this:** Any test involving spatial overlap detection (melee hits, bullet collisions, pickup range, trigger zones).

**Used in tests:** Implicitly used by any test with collision-dependent systems

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_collision.gd"]
entities(): [{ "recipe": "player", "name": "P" }]  # Player has CCollision by default
```

---

### 9. SFireBullet — Ranged Projectile Firing (`s_fire_bullet.gd`)

**Group:** gameplay
**Query:** `CWeapon`

| Aspect | Detail |
|--------|--------|
| **Feature** | Weapon firing with cooldown, spread application, bullet entity creation and initialization |
| **Reads** | CWeapon, CTransform, CPlayer, CMovement, CAim |
| **Writes** | CWeapon.time_amount_before_last_fire, CWeapon.last_fire_direction, CBullet.owner_entity (on new bullet), CMovement.velocity (bullet initial), CTransform.position (bullet spawn at weapon tip) |
| **Dependencies** | ServiceContext.recipe() (bullet entity creation), CAim (spread angle) |
| **Pair with** | s_damage (processes bullet collisions), s_crosshair or s_track_location (aim input), s_collision (bullet needs collision shape) |

**What it does:** Manages firing cooldown (`CWeapon.interval`). Player fires while holding input; AI fires when `CWeapon.can_flag == true`. Direction priority: CAim.aim_position > last_fire_direction > CMovement.velocity. Spread jitter applied from `CAim.spread_angle_degrees`. Creates bullet entity via recipe, initializes CBullet (damage, owner), CMovement (velocity from direction × bullet_speed), CTransform (spawn position).

**Used in tests:** No dedicated test yet (tested indirectly through s_damage bullet collision path)

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/s_fire_bullet.gd",
    "res://scripts/systems/s_damage.gd",
    "res://scripts/systems/s_collision.gd",
]
entities(): [
    { "recipe": "player", "name": "Player" },  # Player has no CWeapon by default — attach manually
]
# In test_run(): attach CWeapon to player, set can_fire=true
```

---

### 10. SEnemySpawn — Wave Spawning (`s_enemy_spawn.gd`)

**Group:** gameplay
**Query:** `CSpawner + CTransform`

| Aspect | Detail |
|--------|--------|
| **Feature** | Timer-based wave spawning with day/night conditions, enrage mode, position calculation |
| **Reads** | CSpawner, CTransform, CDayNightCycle (cached reference) |
| **Writes** | CSpawner.spawn_timer, CSpawner.condition_activated, CSpawner.spawned (array tracking), CTransform.position (on spawned entities) |
| **Dependencies** | ServiceContext.recipe() (entity creation), CDayNightCycle (condition checking) |
| **Pair with** | s_daynight_cycle (time progression), s_presence_penalty (enrage modification) |

**What it does:** Each frame, increments spawn timer. When timer exceeds interval: checks active_condition (ALWAYS / DAY_ONLY / NIGHT_ONLY against CDayNightCycle). Spawns up to count entities from spawn_recipe_id. Position calculated near spawner with minimum spacing variance. Enrage mode reduces interval. Max spawn count cap enforced. Tracks all spawned entities in `CSpawner.spawned` array.

**Spawner death behavior (in SDamage):** When a spawner dies, it burst-spawns 3 enemies + drops a loot box with random weapon.

**Used in tests:** No dedicated integration test yet

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/s_enemy_spawn.gd",
    "res://scripts/systems/s_daynight_cycle.gd",
]
entities(): [
    { "recipe": "daynight_cycle", "name": "Time" },
    # Spawner entity created dynamically or via custom recipe
]
```

---

### 11. SMove — Movement & Position Updates (`s_move.gd`)

**Group:** gameplay
**Query:** `CMovement + CTransform`

| Aspect | Detail |
|--------|--------|
| **Feature** | Player input-driven acceleration, AI desired_velocity smoothing, friction, velocity clamping, night speed bonus |
| **Reads** | CMovement, CTransform, CPlayer, ServiceContext.input() |
| **Writes** | CMovement.velocity, CTransform.position |
| **Dependencies** | ServiceContext.input(), ECSUtils (enemy/night speed multiplier) |
| **Pair with** | s_weight_penalty (modifies max_speed after this runs), s_ai (sets desired_velocity), s_collision (position sync) |

**What it does:** Two paths:
- **Player:** Reads input via `ServiceContext.input()`, applies acceleration toward input direction, clamps to max_speed
- **AI:** Smooths `CMovement.desired_velocity` toward target (set by GOAP actions), applies friction

Both paths: apply friction, clamp velocity to max_speed, integrate position. Enemies get night speed multiplier from `CMovement.night_speed_multiplier`.

**Used in tests:** test_player_respawn (movement lock on death verification)

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_move.gd"]
entities(): [{ "recipe": "player", "name": "P" }]
```

---

### 12. SAI — GOAP AI Decision Making (`s_ai.gd`)

**Group:** gameplay
**Query:** `CGoapAgent + CMovement + CTransform`

| Aspect | Detail |
|--------|--------|
| **Feature** | Full GOAP loop: goal prioritization, replan detection, action precondition validation, plan step execution, completion handling |
| **Reads** | CGoapAgent, CMovement, CTransform |
| **Writes** | CGoapAgent.plan, CGoapAgent.running_action, CGoapAgent.running_context, CGoapAgent.blackboard, CGoapAgent.plan_invalidated, CGoapAgent.plan_invalidated_reason |
| **Dependencies** | GoapPlanner (shared instance), GoapGoal, GoapPlan, GoapWorldState, GoapAction classes |
| **Pair with** | s_perception (feeds visible_entities), s_semantic_translation (produces world_state facts), s_move (executes movement actions), s_melee_attack (executes attack actions) |

**What it does:** The AI brain. Each frame: checks if current plan is invalidated (world state changed). If so, re-prioritizes goals and re-plans. Validates running action's preconditions. If valid, calls `action.perform()` or `action.tick()`. On completion, advances to next plan step. Writes execution state to blackboard for action implementations.

**AI Chain:** SPerception (scan) → SSemanticTranslation (facts) → SAI (plan + execute) → SMove/SMeleeAttack (act)

**Used in tests:** No dedicated integration test yet (enemy_basic has CGoapAgent but no test exercises planning)

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/s_ai.gd",
    "res://scripts/systems/s_perception.gd",
    "res://scripts/systems/s_semantic_translation.gd",
    "res://scripts/systems/s_move.gd",
]
entities(): [
    { "recipe": "enemy_basic", "name": "Enemy" },  # Has CGoapAgent + CPerception
    { "recipe": "player", "name": "Player" },       # AI target
]
```

---

### 13. SPerception — Entity Detection (`s_perception.gd`)

**Group:** gameplay
**Query:** `CPerception + CTransform`

| Aspect | Detail |
|--------|--------|
| **Feature** | Vision radius scan, enemy/friendly tracking, nearest enemy caching, night vision multiplier |
| **Reads** | CPerception, CTransform, CCamp, CDead (exclude dead entities) |
| **Writes** | CPerception._visible_entities, CPerception._visible_friendlies, CPerception.nearest_enemy, CPerception._update_timer, CPerception.owner_entity |
| **Dependencies** | ECSUtils (enemy/night vision boost) |
| **Pair with** | s_ai (consumes nearest_enemy), s_semantic_translation (consumes visible_entities), s_presence_penalty (modifies vision_range) |

**What it does:** O(N²) spatial scan throttled by `CPerception.update_interval`. For each entity with CPerception: iterates all world entities, checks distance ≤ vision_range, filters by camp (enemy vs friendly), excludes dead entities. Caches nearest enemy and visible entity lists. Enemies get night vision multiplier.

**Used in tests:** test_flow_composition_cost (verifies presence_penalty increases vision_range)

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_perception.gd"]
entities(): [
    { "recipe": "enemy_basic", "name": "Watcher",
      "components": { "CPerception": { "vision_range": 600.0 } } },
    { "recipe": "player", "name": "Target" },
]
```

---

### 14. SMapRender — PCG Map Rendering (`s_map_render.gd`)

**Group:** render
**Query:** `CMapData`

| Aspect | Detail |
|--------|--------|
| **Feature** | PCG map data to TileMapLayer rendering (two-pass: zone colors + texture tiles) |
| **Reads** | CMapData.pcg_result |
| **Writes** | TileMapLayer cells (two-pass rendering) |
| **Dependencies** | TileSetBuilder, PCGCell, PCGResult classes |
| **Pair with** | None — standalone render system |
| **Special** | Requires `enable_pcg() = true` in SceneConfig |

**What it does:** Listens to `CMapData.map_changed` signal. Two-pass rendering: first pass draws fallback zone colors, second pass overlays texture tiles. z_index=-10 renders behind all entities. Only functions when PCG pipeline has produced a result.

**Used in tests:** test_pcg_map (ONLY PCG test)

**Minimum setup:**
```gdscript
func enable_pcg() -> bool:
    return true  # REQUIRED — only test that enables PCG

func systems() -> Variant:
    return ["res://scripts/systems/s_map_render.gd"]

func entities() -> Variant:
    return []  # PCG generates the map entity automatically
```

---

### 15. SUI — HUD Initialization (`ui/s_ui.gd`)

**Group:** ui
**Query:** None (processes all entities once, flagged by _initialized)

| Aspect | Detail |
|--------|--------|
| **Feature** | One-shot HUD bootstrap: pushes HUD scene, DayNightCycle UI, registers sub-UI systems (SUI_Hpbar, SUI_DialogueNameTag) |
| **Reads** | ECS.world (entity iteration) |
| **Writes** | Registers SUI_Hpbar and SUI_DialogueNameTag as child systems; instantiates HUD scene tree |
| **Dependencies** | SUI_Hpbar, SUI_DialogueNameTag, ServiceContext.ui() |
| **Pair with** | s_ui_hpbar (per-entity HP bars), s_ui_dialogue_name_tag (NPC name tags), s_dialogue (dialogue views) |

**What it does:** Runs once on first frame (flags `_initialized = true`). Bootstraps the entire HUD layer. Sub-systems handle per-entity view binding.

**Used in tests:** test_player_respawn, test_flow_composer_interaction

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/ui/s_ui.gd",
    "res://scripts/systems/ui/s_ui_hpbar.gd",
]
entities(): [
    { "recipe": "player", "name": "Player" },
    { "recipe": "campfire", "name": "Camp" },
]
```

---

### 16. SDialogue — Dialogue System (`s_dialogue.gd`)

**Group:** gameplay
**Query:** None (reads CDialogue directly)

| Aspect | Detail |
|--------|--------|
| **Feature** | NPC dialogue proximity detection, hint UI, dialogue view open/close, composer sub-flow, mouse mode management |
| **Reads** | CDialogue, CTransform, CPlayer, ServiceContext.input(), DIALOGUE_DATA |
| **Writes** | UI views (dialogue panel, composer panel, hint), Input.mouse_mode, CPlayer.is_enabled (disable during dialogue) |
| **Dependencies** | ServiceContext.ui(), ServiceContext.input(), DIALOGUE_DATA, crosshair script |
| **Pair with** | s_ui (HUD layer), s_pickup (composer crafting from dialogue) |

**What it does:** Each frame: checks distance between player and entities with CDialogue. Within range: shows hint UI ("按 E 交互"). On interact (E key): opens dialogue view with options (craft/dismantle/close from DIALOGUE_DATA). Captures mouse (VISIBLE mode), disables player controls. Close button restores captured mouse mode and re-enables player.

**Used in tests:** test_flow_composer_interaction

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/ui/s_ui.gd",
    "res://scripts/systems/s_dialogue.gd",
]
func entities() -> Variant:
    return null  # Use default production entities (includes ComposerNPC)
```

---

### 17. SWeightPenalty — Weight-Based Speed Penalty (`s_weight_penalty.gd`)

**Group:** cost
**Query:** `CMovement`

| Aspect | Detail |
|--------|--------|
| **Feature** | Each losable component on an entity reduces movement speed |
| **Reads** | CMovement, entity.components (count of losable components) |
| **Writes** | CMovement.max_speed (reduced), CMovement.base_max_speed (lazy-captured on first pass) |
| **Dependencies** | Config.WEIGHT_SPEED_PENALTY_PER_COMPONENT, ECSUtils.is_losable_component() |
| **Pair with** | s_move (must run first to set base max_speed), always include with other cost systems |

**What it does:** First pass captures current `CMovement.max_speed` as `base_max_speed`. Each subsequent pass: counts losable components on entity, applies `max_speed = base_max_speed × (1.0 - count × penalty_per_component)`. Minimum 40% speed floor (can't reduce below 0.4 × base).

**Lazy-capture pattern:** `base_max_speed < 0.0` means "not captured yet". First pass captures; subsequent passes modify.

**Used in tests:** test_flow_composition_cost

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_weight_penalty.gd"]
entities(): [
    { "recipe": "player", "name": "P" },
    # Attach extra losable components (CWeapon, CTracker, etc.) to observe penalty
]
```

---

### 18. SPresencePenalty — Presence-Based Power Detection (`s_presence_penalty.gd`)

**Group:** cost
**Query:** `CPlayer`

| Aspect | Detail |
|--------|--------|
| **Feature** | More losable components on player → enemies see farther + spawners enrage faster |
| **Reads** | CPlayer, CPerception (all enemy perceptions), CSpawner (all spawners) |
| **Writes** | CPerception.vision_range (increased), CPerception.base_vision_range (captured), CSpawner.enraged, CSpawner.presence_enraged, CSpawner.damage_enraged |
| **Dependencies** | Config.VISION_BONUS_PER_COMPONENT, Config.SPAWNER_ENRAGE_COMPONENT_THRESHOLD |
| **Pair with** | s_perception (must run first to set base vision_range), s_enemy_spawn (reads enrage state) |

**What it does:** Counts losable components on player entity. For each enemy with CPerception: increases vision_range proportionally. For each spawner: if component count exceeds threshold, sets enraged/presence_enraged flags. Uses lazy-capture pattern for base_vision_range.

**Used in tests:** test_flow_composition_cost

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_presence_penalty.gd"]
entities(): [
    { "recipe": "player", "name": "Player" },          # Source of component count
    { "recipe": "enemy_basic", "name": "Watcher",       # Target: vision boosted
      "components": { "CPerception": { "vision_range": 600.0 } } },
]
```

---

### 19. SColdRateConflict — Cold Attack Speed Penalty (`s_cold_rate_conflict.gd`)

**Group:** cost
**Query:** `CElementalAttack`

| Aspect | Detail |
|--------|--------|
| **Feature** | Cold element slows both ranged (CWeapon.interval) and melee (CMelee.attack_interval) attack rate |
| **Reads** | CElementalAttack, CWeapon, CMelee |
| **Writes** | CWeapon.interval (increased), CWeapon.base_interval (captured), CMelee.attack_interval (increased), CMelee.base_attack_interval (captured) |
| **Dependencies** | Config.COLD_RATE_MULTIPLIER |
| **Pair with** | s_fire_heal_conflict, s_electric_spread_conflict (other elemental conflicts); s_melee_attack, s_fire_bullet (set base intervals) |

**What it does:** If entity has CElementalAttack with COLD type: multiplies CWeapon.interval and CMelee.attack_interval by `Config.COLD_RATE_MULTIPLIER`. Lazy-capture preserves original base values.

**Used in tests:** test_flow_composition_cost

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_cold_rate_conflict.gd"]
entities(): [
    { "recipe": "player", "name": "P" },
]
# In test_run(): attach CWeapon + CElementalAttack(COLD) to player
```

---

### 20. SElectricSpreadConflict — Electric Spread Increase (`s_electric_spread_conflict.gd`)

**Group:** cost
**Query:** `CWeapon`

| Aspect | Detail |
|--------|--------|
| **Feature** | Electric element adds weapon spread (inaccuracy) |
| **Reads** | CWeapon, CElementalAttack |
| **Writes** | CWeapon.spread_degrees (increased), CWeapon.base_spread_degrees (captured) |
| **Dependencies** | Config.ELECTRIC_SPREAD_DEGREES, Config.MAX_SPREAD_DEGREES |
| **Pair with** | s_cold_rate_conflict, s_fire_heal_conflict (other conflicts); s_crosshair/s_track_location (display spread) |

**What it does:** If entity has CElementalAttack with ELECTRIC type: adds `Config.ELECTRIC_SPREAD_DEGREES` to CWeapon.spread_degrees. Clamped to MAX_SPREAD_DEGREES. Lazy-capture pattern.

**Used in tests:** test_flow_composition_cost

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_electric_spread_conflict.gd"]
entities(): [
    { "recipe": "player", "name": "P" },
]
# In test_run(): attach CWeapon + CElementalAttack(ELECTRIC) to player
```

---

### 21. SFireHealConflict — Fire Healing Reduction (`s_fire_heal_conflict.gd`)

**Group:** cost
**Query:** `CHealer`

| Aspect | Detail |
|--------|--------|
| **Feature** | Fire element reduces healing effectiveness |
| **Reads** | CHealer, CElementalAttack |
| **Writes** | CHealer.heal_pro_sec (reduced), CHealer.base_heal_pro_sec (captured) |
| **Dependencies** | Config.FIRE_HEAL_REDUCTION |
| **Pair with** | s_cold_rate_conflict, s_electric_spread_conflict (other conflicts); s_healer (sets base heal rate) |

**What it does:** If entity has CElementalAttack with FIRE type: multiplies CHealer.heal_pro_sec by `(1.0 - Config.FIRE_HEAL_REDUCTION)`. Lazy-capture pattern.

**Used in tests:** test_flow_composition_cost

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_fire_heal_conflict.gd"]
entities(): [
    { "recipe": "survivor_healer", "name": "Healer" },
]
# In test_run(): attach CElementalAttack(FIRE) to healer
```

---

### 22. SAreaEffectModifier — Area Effect Auras (`s_area_effect_modifier.gd`)

**Group:** cost
**Query:** `CAreaEffect + CTransform`

| Aspect | Detail |
|--------|--------|
| **Feature** | FF7-style Materia area effects: radius-based damage/heal/poison scaling with power_ratio |
| **Reads** | CAreaEffect, CTransform, CCamp (target filtering), CMelee (scale melee damage), CHealer (scale healing), CPoison (scale poison DoT), CHP (targets), CCollision (targets) |
| **Writes** | CHP.hp (damage or heal), CDamage.amount (add/increment for delayed processing) |
| **Dependencies** | ECS.world.query (target discovery within radius) |
| **Pair with** | s_area_effect_modifier_render (visual fog), s_damage (processes queued CDamage), s_healer (base healing) |

**What it does:** For each entity with CAreaEffect: queries all entities within radius. Filters by camp (self/allies/enemies per CAreaEffect flags). Scales companion component effects:
- CMelee.damage × power_ratio → CDamage on enemies
- CHealer.heal_pro_sec × power_ratio → direct CHP increase on allies
- CPoison.damage_per_sec × power_ratio → CDamage on enemies

Channel override system allows selective activation/deactivation of specific effect types.

**Used in tests:** test_flow_composition_cost (materia_damage, materia_heal recipes)

**Minimum setup:**
```gdscript
systems(): ["res://scripts/systems/s_area_effect_modifier.gd"]
entities(): [
    { "recipe": "player", "name": "P" },
    # Create materia_damage or materia_healer entity via ServiceContext.recipe().create_entity_by_id()
]
```

---

### 23. SAreaEffectModifierRender — Area Effect Fog Particles (`s_area_effect_modifier_render.gd`)

**Group:** render
**Query:** `CAreaEffect + CTransform`

| Aspect | Detail |
|--------|--------|
| **Feature** | GPU particle fog visualization for area effect auras |
| **Reads** | CAreaEffect, CTransform, CDead, CMelee, CHealer, CPoison |
| **Writes** | GPUParticles2D fog view nodes (create/update/remove), view cache dictionary |
| **Dependencies** | None (purely visual) |
| **Pair with** | s_area_effect_modifier (must be registered together — this renders what that computes) |

**What it does:** Creates GPUParticles2D fog at aura radius. Two visual styles: HEAL (blue fog) vs DAMAGE (green fog). Reacts to radius changes and companion component add/remove. Stale view cleanup when components change.

**Used in tests:** test_flow_composition_cost

**Minimum setup:**
```gdscript
systems(): [
    "res://scripts/systems/s_area_effect_modifier.gd",
    "res://scripts/systems/s_area_effect_modifier_render.gd",
]
```

---

## Additional Systems (Short Reference)

These systems exist in the codebase but are less commonly needed for integration testing:

### 24. SCrosshair — Mouse Aim Input (`s_crosshair.gd`)
- **Group:** gameplay | **Query:** `CAim`
- Converts mouse position to world aim target with smooth spread jitter
- **Pair with:** s_fire_bullet (consumes CAim), yields to s_track_location when CTracker present

### 25. STrackLocation — Auto-Target Tracking (`s_track_location.gd`)
- **Group:** gameplay | **Query:** `CTracker + CCollision`
- Auto-targets nearest enemy within track_range, writes to CAim
- **Pair with:** s_fire_bullet, s_crosshair (alternative aim source)

### 26. SHealer — Area Healing (`s_healer.gd`)
- **Group:** gameplay | **Query:** `CHealer`
- Heals same-camp entities within heal_range at heal_pro_sec rate
- **Pair with:** s_fire_heal_conflict (reduces output), s_area_effect_modifier (scales output)

### 27. STrigger — Trigger Zones (`s_trigger.gd`)
- **Group:** gameplay | **Query:** `CTrigger + CCollision`
- Executes trigger action on first overlapped entity
- **Pair with:** s_collision (requires Area2D shapes)

### 28. SCamera — Camera Management (`s_camera.gd`)
- **Group:** gameplay | **Query:** `CCamera + CCamp`
- Lazy Camera2D creation with smoothing, follows player
- **Pair with:** s_dead (rebinds camera on player respawn)

### 29. SDaynightCycle — Time Progression (`s_daynight_cycle.gd`)
- **Group:** gameplay | **Query:** `CDayNightCycle`
- Simple time accumulator wrapping at duration
- **Pair with:** s_daynight_lighting (consumes time), s_enemy_spawn (checks day/night)

### 30. SSemanticTranslation — Perception-to-GOAP Bridge (`s_semantic_translation.gd`)
- **Group:** gameplay | **Query:** `CSemanticTranslation + CPerception + CTransform + CGoapAgent`
- Translates raw perception data into symbolic GOAP world_state facts
- **Pair with:** s_ai (consumes world_state), s_perception (source data)

### 31. SRenderView — Static Sprite Rendering (`s_render_view.gd`)
- **Group:** render | **Query:** `CTransform + CSprite` (without CAnimation)
- Creates Sprite2D child nodes, syncs position/texture each frame

### 32. SAnimation — Animated Sprite Rendering (`s_animation.gd`)
- **Group:** render | **Query:** `CAnimation + CTransform`
- Walk/idle animations based on velocity, flip direction, elemental glow overlay

### 33. SCampfireRender — Campfire Visuals (`s_campfire_render.gd`)
- **Group:** render | **Query:** `CTransform + CCampfire`
- Minecraft-style pixel art campfire with flame layers and spark particles

### 34. SDaynightLighting — Day/Night Shader Lighting (`s_daynight_lighting.gd`)
- **Group:** render | **Query:** `CDayNightCycle`
- Full-screen shader with 6-phase color interpolation + campfire point lights (up to 16)

### 35. SElementalVisual — Elemental Particle Effects (`s_elemental_visual.gd`)
- **Group:** render | **Query:** `CElementalAffliction + CTransform`
- 4 particle setups: FIRE (embers), WET (droplets), COLD (crystals), ELECTRIC (sparks)

### 36. SUI_Hpbar — HP Bar View Binding (`ui/s_ui_hpbar.gd`)
- **Group:** ui | **Query:** `CTransform + CHP`
- Binds View_HPBar per entity, cleans up on removal

### 37. SUI_DialogueNameTag — Dialogue Name Tag (`ui/s_ui_dialogue_name_tag.gd`)
- **Group:** ui | **Query:** `CTransform + CDialogue`
- Shows NPC name overhead for dialogue entities

---

## Feature → System Decision Table

Use this quick reference to pick the right systems for your test scenario:

| If testing... | Register these systems | Minimum entities | Key manual setup in test_run() |
|---|---|---|---|
| **Combat / HP survival** | s_hp, s_damage, s_dead | player + enemy_basic | Await frames, assert HP > 0 |
| **Kill → drop → pickup** (full loot cycle) | s_damage, s_pickup, s_life, s_dead | player + enemy_basic | Attach CWeapon to enemy, add CDamage(999), await, call _open_box() |
| **Melee + elemental chain** | s_melee_attack, s_elemental_affliction, s_damage | enemy_fire + player (+ survivor for propagation) | Setup Area2D+CollisionShape2D per entity, set attack_pending=true |
| **PCG map generation** | s_map_render | (none) | Set enable_pcg()=true, query CMapData entity |
| **Crafting / composer** | s_pickup | player + npc_composer | Initialize GOL.Player, configure dialogue entries |
| **Console commands** | (none — service layer) | player | Call ServiceContext.console().execute() directly |
| **UI interaction** (dialogue, hints, HUD) | ui/s_ui, s_dialogue | null (= default production spawn) | Simulate input events, traverse UI tree |
| **Penalty / conflict systems** (ALL 7 cost systems) | s_weight_penalty, s_presence_penalty, s_fire_heal_conflict, s_cold_rate_conflict, s_electric_spread_conflict, s_area_effect_modifier, s_area_effect_modifier_render | player + enemy_basic(+custom CPerception) + poison_ally | Attach CWeapon/CHealer/CPoison/CElementalAttack to player, create materia entities |
| **Player respawn lifecycle** | s_hp, s_damage, s_dead, s_camera, s_move, s_animation, ui/s_ui, ui/s_ui_hpbar | player + campfire | Add CDamage(9999) to player, await respawn delay, verify new entity |
| **Blueprint drop on death** | s_damage, s_dead | player + enemy_basic | Set BLUEPRINT_DROP_CHANCE=1.0, add CDamage(999) to enemy |
| **AI perception + vision** | s_perception | enemy_basic(+vision_range override) + player | Assert vision_range / nearest_enemy after frames |
| **GOAP AI planning** | s_ai, s_perception, s_semantic_translation, s_move | enemy_basic + player | Inspect CGoapAgent.plan / running_action |
| **Weight slowdown** | s_weight_penalty | player (+extra components) | Attach CWeapon, CTracker, etc.; assert max_speed < base |
| **Presence enrage** | s_presence_penalty | player (+components) + enemy_basic(+CPerception) | Assert enemy vision_range increased |
| **Ranged combat** | s_fire_bullet, s_damage, s_collision, s_crosshair | player (+CWeapon attached) | Set can_fire=true, assert bullet spawned |
| **Area effect auras** | s_area_effect_modifier, s_area_effect_modifier_render | player + materia_damage entity | Assert CDamage queued or CHP modified on nearby entities |

---

## Data Flow Chains (Critical Paths)

Understanding these chains helps debug cross-system issues:

```
COMBAT CHAIN:
SFireBullet (create CBullet+CMovement bullet)
  → SCollision (sync Area2D positions)
  → SDamage (physics space query: bullet↔entity)
    → SHP (invincibility countdown)
    → [if HP ≤ 0] → CDead added
      → SDeath (tween sequence → entity removal/respawn)

MELEE CHAIN:
SMeleeAttack (shape query overlap)
  → CDamage added to targets (+ elemental apply_attack)
  → SDamage (processes CDamage)
  → SHP → SDeath (same as above)

DEATH → LOOT CHAIN:
SDamage (HP ≤ 0 detected)
  → Component loss: entity's losable components → CContainer box (+ CLifeTime)
  → Blueprint chance roll → CBlueprint box (+ CLifeTime)
  → CDead added → SDeath (removes entity)
  → SLife (boxes expire after lifetime)
  → SPickup (player approaches box → components transfer)

ELEMENTAL CHAIN:
SMeleeAttack/SDamage → ELEMENTAL_UTILS.apply_attack()
  → CElementalAffliction.entries populated
  → SElementalAffliction (tick: DoT, propagation, freeze)
    → CDamage (fire/electric damage queued back to SDamage)
    → CMovement.max_speed (cold slow)
    → CMovement.velocity (freeze lock)
  → Cost conflicts read CElementalAttack for penalties
  → SElementalVisual (particles)

COST MODIFIER CHAIN (post-gameplay, same frame):
SWeightPenalty (CMovement.max_speed ↓)
SPresencePenalty (CPerception.vision_range ↑, CSpawner.enrage)
SColdRateConflict (CWeapon.interval ↑, CMelee.attack_interval ↑)
SElectricSpreadConflict (CWeapon.spread_degrees ↑)
SFireHealConflict (CHealer.heal_pro_sec ↓)

AI CHAIN:
SPerception (O(N²) scan → visible_entities, nearest_enemy)
  → SSemanticTranslation (world_state facts from perception)
    → SAI (GOAP plan selection + action execution)
      → Actions write CMovement.desired_velocity / CMelee.attack_pending
        → SMove / SMeleeAttack (physical execution)
```

---

## Verified Recipe IDs

Only these recipe IDs are confirmed to exist in `resources/recipes/`. Use ONLY these in `entities()`:

| Recipe ID | Type | Key Components |
|-----------|------|---------------|
| `player` | Player | Transform, Movement, HP, Collision, Sprite, Animation, Player, Camera, Camp(PLAYER), Aim |
| `enemy_basic` | Enemy | Transform, Movement, HP, Collision, Sprite, Animation, Camp(ENEMY), Perception, GoapAgent, Melee |
| `enemy_fire` | Elemental Enemy | enemy_base + CElementalAttack(FIRE) |
| `enemy_wet` | Elemental Enemy | enemy_base + CElementalAttack(WET) |
| `enemy_cold` | Elemental Enemy | enemy_base + CElementalAttack(COLD) |
| `enemy_electric` | Elemental Enemy | enemy_base + CElementalAttack(ELECTRIC) |
| `survivor` | Ally NPC | Transform, Movement, HP, Collision, Sprite, Animation, Camp(PLAYER), Guard, Perception, GoapAgent |
| `campfire` | Structure | Transform, Sprite, Animation, HP, Campfire, Collision, Camp(PLAYER) |
| `weapon_rifle` | Item | CWeapon (slow, long range) |
| `weapon_pistol` | Item | CWeapon (fast, short range) |
| `npc_composer` | Crafting NPC | Transform, Dialogue |
| `daynight_cycle` | System | CDayNightCycle |
| `survivor_healer` | Healer Ally | survivor + CHealer |
| `enemy_poison` | Poison Enemy | enemy_base + CPoison aura |
| `tracker` | Item | CTracker |
| `bullet_normal` | Projectile | CBullet + CMovement + CLifeTime |
| `materia_damage` | Aura | CAreaEffect(DAMAGE) |
| `materia_heal` | Aura | CAreaEffect(HEAL) |
| `blueprint_weapon` | Blueprint | CBlueprint(CWeapon) |
| `blueprint_healer` | Blueprint | CBlueprint(CHealer) |
| `blueprint_tracker` | Blueprint | CBlueprint(CTracker) |
| `blueprint_poison` | Blueprint | CBlueprint(CPoison) |
| `weapon_fire` | Elemental Weapon | CWeapon + CElementalAttack(FIRE) |
| `weapon_cold` | Elemental Weapon | CWeapon + CElementalAttack(COLD) |
| `weapon_wet` | Elemental Weapon | CWeapon + CElementalAttack(WET) |
| `weapon_electric` | Elemental Weapon | CWeapon + CElementalAttack(ELECTRIC) |
| `enemy_raider` | Armed Enemy | enemy_basic + CWeapon |
| `enemy_fast` | Fast Enemy | enemy_base variant (speed-tuned) |

> **Note:** `enemy_raider` inherits `enemy_basic` but does NOT include CWeapon in the current recipe definition. Always verify component presence or attach manually in test_run().
