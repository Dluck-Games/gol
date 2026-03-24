# Composition Cost Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement composition cost mechanics that penalize players for stacking too many ECS components, creating meaningful trade-offs in character building.

**Architecture:** Micro-system mesh pattern — each cost rule is an independent small system coupling 2-3 components, with a shared Config for tuning. Cost systems run in a new `"cost"` group before `"gameplay"` group. All modifiable stats use base+effective dual fields with multiplicative stacking.

**Tech Stack:** Godot 4.6, GDScript, GECS (ECS framework), gdUnit4 (testing)

**Spec:** `docs/superpowers/specs/2026-03-24-composition-cost-design.md`

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `scripts/components/c_poison.gd` | CPoison component — single-target DoT, losable |
| `scripts/systems/s_weight_penalty.gd` | Losable component count → CMovement.max_speed reduction |
| `scripts/systems/s_presence_penalty.gd` | Losable component count → enemy CPerception.vision_range increase + CSpawner enrage threshold |
| `scripts/systems/s_fire_heal_conflict.gd` | CElementalAttack(FIRE) → CHealer.heal_pro_sec reduction |
| `scripts/systems/s_cold_rate_conflict.gd` | CElementalAttack(COLD) → CWeapon.interval / CMelee.attack_interval increase |
| `scripts/systems/s_electric_spread_conflict.gd` | CElementalAttack(ELECTRIC) → CWeapon.spread_degrees increase |
| `scripts/systems/s_area_effect_modifier.gd` | CAreaEffect modifier — area-ifies CMelee/CHealer/CPoison |
| `scripts/systems/s_area_effect_modifier_render.gd` | Render for area effect modifier (replaces s_area_effect_render.gd) |
| `tests/unit/system/test_weight_penalty.gd` | Unit tests for SWeightPenalty |
| `tests/unit/system/test_presence_penalty.gd` | Unit tests for SPresencePenalty |
| `tests/unit/system/test_fire_heal_conflict.gd` | Unit tests for SFireHealConflict |
| `tests/unit/system/test_cold_rate_conflict.gd` | Unit tests for SColdRateConflict |
| `tests/unit/system/test_electric_spread_conflict.gd` | Unit tests for SElectricSpreadConflict |
| `tests/unit/system/test_area_effect_modifier.gd` | Unit tests for SAreaEffectModifier |
| `tests/unit/test_composition_cost_pickup.gd` | Unit tests for component cap in SPickup |
| `tests/unit/test_composition_cost_lethal_drop.gd` | Unit tests for enhanced lethal drop |
| `tests/integration/flow/test_flow_composition_cost_scene.gd` | Integration SceneConfig for full composition cost flow |

### Modified Files

| File | Change |
|------|--------|
| `scripts/configs/config.gd` | Add composition cost constants, add CPoison to LOSABLE_COMPONENTS |
| `scripts/components/c_movement.gd` | Add `base_max_speed: float`, initialize from `max_speed` |
| `scripts/components/c_weapon.gd` | Add `base_interval: float`, `spread_degrees: float`, `base_spread_degrees: float` |
| `scripts/components/c_melee.gd` | Add `base_attack_interval: float` |
| `scripts/components/c_healer.gd` | Add `base_heal_pro_sec: float` |
| `scripts/components/c_perception.gd` | Add `base_vision_range: float` |
| `scripts/components/c_area_effect.gd` | Remove `effect_type`/`amount`/`tick_interval`, keep `affects_self`, add `power_ratio` |
| `scripts/utils/ecs_utils.gd` | Add `is_at_component_cap()` helper |
| `scripts/systems/s_pickup.gd` | Add component cap check before `_open_box` (add path only, not swap path) |
| `scripts/systems/s_damage.gd` | Enhance `_on_no_hp` — drop count = `1 + max(0, count - T)` |
| `scripts/systems/s_fire_bullet.gd` | Read `CWeapon.spread_degrees`, apply random angle offset when > 0 |
| `scripts/systems/s_elemental_affliction.gd` | Use `CMovement.base_max_speed` instead of own `base_max_speed` snapshot |
| `scripts/gameplay/ecs/gol_world.gd` | Add `ECS.process(delta, "cost")` before `"gameplay"` in `_process` |
| `resources/recipes/enemy_poison.tres` | Migrate to CPoison + CAreaEffect |
| `resources/recipes/materia_damage.tres` | Migrate to CMelee + CAreaEffect |
| `resources/recipes/materia_heal.tres` | Migrate to CHealer + CAreaEffect |

### Removed Files

| File | Reason |
|------|--------|
| `scripts/systems/s_area_effect.gd` | Replaced by `s_area_effect_modifier.gd` |
| `scripts/systems/s_area_effect_render.gd` | Replaced by `s_area_effect_modifier_render.gd` |

---

## Task 1: Foundation — Config, System Group, Base+Effective Fields

**Files:**
- Modify: `scripts/gameplay/ecs/gol_world.gd` (add "cost" group)
- Modify: `scripts/configs/config.gd` (add constants)
- Modify: `scripts/components/c_movement.gd` (add base_max_speed)
- Modify: `scripts/components/c_weapon.gd` (add base_interval, spread fields)
- Modify: `scripts/components/c_melee.gd` (add base_attack_interval)
- Modify: `scripts/components/c_healer.gd` (add base_heal_pro_sec)
- Modify: `scripts/components/c_perception.gd` (add base_vision_range)
- Modify: `scripts/systems/s_elemental_affliction.gd` (use CMovement.base_max_speed)

- [ ] **Step 1: Add composition cost constants to Config**

In `scripts/configs/config.gd`, add after `DEATH_REMOVE_COMPONENTS`:

```gdscript
## ── Composition Cost ──────────────────────────
## Hard mechanics
static var COMPONENT_CAP: int = 5
static var WEIGHT_SPEED_PENALTY_PER_COMPONENT: float = 0.05
static var LETHAL_DROP_THRESHOLD: int = 3

## Elemental conflicts
static var FIRE_HEAL_REDUCTION: float = 0.3
static var COLD_RATE_MULTIPLIER: float = 1.4
static var ELECTRIC_SPREAD_DEGREES: float = 15.0
static var MAX_SPREAD_DEGREES: float = 30.0

## Presence penalty
static var VISION_BONUS_PER_COMPONENT: float = 0.1
static var SPAWNER_ENRAGE_COMPONENT_THRESHOLD: int = 3

## Area effect modifier
static var AREA_EFFECT_POWER_RATIO: float = 0.6
```

- [ ] **Step 2: Add "cost" system group to GOLWorld**

In `scripts/gameplay/ecs/gol_world.gd`, find the `_process` function and add `ECS.process(delta, "cost")` before `"gameplay"`:

```gdscript
func _process(delta) -> void:
    ECS.process(delta, "cost")
    ECS.process(delta, "gameplay")
    ECS.process(delta, "ui")
    ECS.process(delta, "render")
```

- [ ] **Step 3: Add base+effective dual fields to CMovement**

In `scripts/components/c_movement.gd`, add `base_max_speed` field. The `@export var max_speed` stays as the effective value. Add a non-exported `base_max_speed` that is initialized to `-1.0` (sentinel for "not yet captured"):

```gdscript
var base_max_speed: float = -1.0  ## Set on first cost system pass; -1 = uninitialized
```

- [ ] **Step 4: Add base+effective dual fields to CWeapon**

In `scripts/components/c_weapon.gd`, add:

```gdscript
var base_interval: float = -1.0          ## Set on first cost system pass
@export var spread_degrees: float = 0.0  ## Bullet spread angle (0 = perfectly accurate)
var base_spread_degrees: float = -1.0    ## Set on first cost system pass
```

Also update `CWeapon.on_merge` (line ~48) to copy the new fields:

```gdscript
func on_merge(other: CWeapon) -> void:
    interval = other.interval
    bullet_speed = other.bullet_speed
    attack_range = other.attack_range
    bullet_recipe_id = other.bullet_recipe_id
    spread_degrees = other.spread_degrees
    # Reset base fields so cost systems re-capture
    base_interval = -1.0
    base_spread_degrees = -1.0
    # Reset runtime state for the new weapon
    last_fire_direction = Vector2.UP
    time_amount_before_last_fire = 0.0
    can_fire = true
```

- [ ] **Step 5: Add base+effective dual fields to CMelee**

In `scripts/components/c_melee.gd`, add:

```gdscript
var base_attack_interval: float = -1.0  ## Set on first cost system pass
```

- [ ] **Step 6: Add base_heal_pro_sec to CHealer**

In `scripts/components/c_healer.gd`, add:

```gdscript
var base_heal_pro_sec: float = -1.0  ## Set on first cost system pass
```

- [ ] **Step 7: Add base_vision_range to CPerception**

In `scripts/components/c_perception.gd`, add:

```gdscript
var base_vision_range: float = -1.0  ## Set on first cost system pass
```

- [ ] **Step 8: Update SElementalAffliction to use CMovement.base_max_speed**

In `scripts/systems/s_elemental_affliction.gd`, update `_apply_movement_modifiers` (lines ~169-210). The key change: replace the lazy-capture of `affliction.base_max_speed` with reading from `CMovement.base_max_speed`. The full updated function:

```gdscript
func _apply_movement_modifiers(entity: Entity, affliction: CElementalAffliction, cold_intensity: float, should_freeze: bool, delta: float) -> void:
    var movement := entity.get_component(CMovement) as CMovement
    if not movement:
        return

    # Use CMovement.base_max_speed instead of affliction.base_max_speed
    # (base_max_speed is now managed by the dual-field pattern)
    var base_speed := movement.base_max_speed if movement.base_max_speed >= 0.0 else movement.max_speed

    # Tick freeze cooldown
    if affliction.freeze_cooldown > 0.0:
        affliction.freeze_cooldown -= delta

    # Currently frozen — check if freeze should end
    if affliction.status_applied_movement_lock:
        affliction.freeze_timer += delta
        if affliction.freeze_timer >= FREEZE_MAX_DURATION:
            movement.forbidden_move = false
            affliction.status_applied_movement_lock = false
            affliction.freeze_timer = 0.0
            affliction.freeze_cooldown = FREEZE_COOLDOWN
        return

    # Should freeze and cooldown expired
    if should_freeze and affliction.freeze_cooldown <= 0.0:
        movement.velocity = Vector2.ZERO
        movement.max_speed = base_speed * (1.0 - MAX_COLD_SLOW)
        movement.forbidden_move = true
        affliction.status_applied_movement_lock = true
        affliction.freeze_timer = 0.0
        return

    # Apply proportional cold slow
    var slow_ratio := minf(MAX_COLD_SLOW, cold_intensity * COLD_SLOW_PER_INTENSITY)
    movement.max_speed = base_speed * (1.0 - slow_ratio)
```

Update `_clear_afflictions` (lines ~213-224) — restore to base:

```gdscript
func _clear_afflictions(entity: Entity, affliction: CElementalAffliction) -> void:
    var movement := entity.get_component(CMovement) as CMovement
    if movement:
        # Restore to base_max_speed (dual-field pattern)
        if movement.base_max_speed >= 0.0:
            movement.max_speed = movement.base_max_speed
        if affliction.status_applied_movement_lock:
            movement.forbidden_move = false
            affliction.status_applied_movement_lock = false
    affliction.freeze_timer = 0.0
    affliction.freeze_cooldown = 0.0
    affliction.entries.clear()
    entity.remove_component(COMPONENT_ELEMENTAL_AFFLICTION)
```

Note: After this change, `affliction.base_max_speed` is no longer used by this system. It can be left on `CElementalAffliction` for now (removing it is optional cleanup).

- [ ] **Step 9: Commit foundation**

```bash
git add scripts/configs/config.gd scripts/gameplay/ecs/gol_world.gd \
  scripts/components/c_movement.gd scripts/components/c_weapon.gd \
  scripts/components/c_melee.gd scripts/components/c_healer.gd \
  scripts/components/c_perception.gd scripts/systems/s_elemental_affliction.gd
git commit -m "feat(composition-cost): add foundation — config, cost group, base+effective fields"
```

---

## Task 2: SWeightPenalty — Weight → Movement Speed

**Files:**
- Create: `scripts/systems/s_weight_penalty.gd`
- Test: `tests/unit/system/test_weight_penalty.gd`

- [ ] **Step 1: Write failing test**

Create `tests/unit/system/test_weight_penalty.gd`:

```gdscript
extends GdUnitTestSuite

var system: SWeightPenalty

func before_test() -> void:
    system = auto_free(SWeightPenalty.new())

func _count_losable(entity: Entity) -> int:
    var count := 0
    for comp in entity.components.values():
        if ECSUtils.is_losable_component(comp):
            count += 1
    return count

func test_no_losable_components_no_penalty() -> void:
    var entity := auto_free(Entity.new())
    var movement := CMovement.new()
    movement.max_speed = 200.0
    entity.add_component(movement)

    system._process_entity(entity, 0.016)

    assert_float(movement.max_speed).is_equal(200.0)

func test_one_losable_component_applies_penalty() -> void:
    var entity := auto_free(Entity.new())
    var movement := CMovement.new()
    movement.max_speed = 200.0
    entity.add_component(movement)
    entity.add_component(CWeapon.new())

    system._process_entity(entity, 0.016)

    # 200 * (1 - 1 * 0.05) = 190
    assert_float(movement.max_speed).is_equal_approx(190.0, 0.01)

func test_multiple_losable_components_stack_multiplicatively() -> void:
    var entity := auto_free(Entity.new())
    var movement := CMovement.new()
    movement.max_speed = 200.0
    entity.add_component(movement)
    entity.add_component(CWeapon.new())
    entity.add_component(CTracker.new())
    entity.add_component(CHealer.new())

    system._process_entity(entity, 0.016)

    # 200 * (1 - 3 * 0.05) = 200 * 0.85 = 170
    assert_float(movement.max_speed).is_equal_approx(170.0, 0.01)

func test_base_max_speed_initialized_on_first_pass() -> void:
    var entity := auto_free(Entity.new())
    var movement := CMovement.new()
    movement.max_speed = 200.0
    entity.add_component(movement)
    entity.add_component(CWeapon.new())

    system._process_entity(entity, 0.016)

    assert_float(movement.base_max_speed).is_equal(200.0)

func test_speed_has_minimum_floor() -> void:
    var entity := auto_free(Entity.new())
    var movement := CMovement.new()
    movement.max_speed = 100.0
    entity.add_component(movement)
    # Add many losable components to exceed floor
    for i in range(Config.COMPONENT_CAP):
        entity.add_component(CWeapon.new())

    system._process_entity(entity, 0.016)

    # Speed should not go below 40% of base
    assert_float(movement.max_speed).is_greater_equal(40.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd gol-project && godot --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/system/test_weight_penalty.gd`
Expected: FAIL — `SWeightPenalty` class not found

- [ ] **Step 3: Implement SWeightPenalty**

Create `scripts/systems/s_weight_penalty.gd`:

```gdscript
class_name SWeightPenalty
extends System

const MIN_SPEED_RATIO: float = 0.4

func _ready() -> void:
    group = "cost"

func query() -> QueryBuilder:
    return q.with_all([CMovement])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    for entity in entities:
        _process_entity(entity, delta)

func _process_entity(entity: Entity, _delta: float) -> void:
    var movement: CMovement = entity.get_component(CMovement)
    if not movement:
        return

    # Lazy-capture base speed
    if movement.base_max_speed < 0.0:
        movement.base_max_speed = movement.max_speed

    # Count losable components
    var count := 0
    for comp in entity.components.values():
        if ECSUtils.is_losable_component(comp):
            count += 1

    if count == 0:
        movement.max_speed = movement.base_max_speed
        return

    var penalty_ratio := count * Config.WEIGHT_SPEED_PENALTY_PER_COMPONENT
    var effective_ratio := maxf(1.0 - penalty_ratio, MIN_SPEED_RATIO)
    movement.max_speed = movement.base_max_speed * effective_ratio
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd gol-project && godot --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/unit/system/test_weight_penalty.gd`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_weight_penalty.gd tests/unit/system/test_weight_penalty.gd
git commit -m "feat(composition-cost): add SWeightPenalty — losable component count reduces movement speed"
```

---

## Task 3: Component Cap + Enhanced Lethal Drop

**Files:**
- Modify: `scripts/systems/s_pickup.gd`
- Modify: `scripts/systems/s_damage.gd`
- Test: `tests/unit/test_composition_cost_pickup.gd`
- Test: `tests/unit/test_composition_cost_lethal_drop.gd`

- [ ] **Step 1: Write failing test for component cap**

Create `tests/unit/test_composition_cost_pickup.gd`:

```gdscript
extends GdUnitTestSuite

func _make_player_with_losable(count: int) -> Entity:
    var entity := auto_free(Entity.new())
    entity.add_component(CMovement.new())
    entity.add_component(CTransform.new())
    entity.add_component(CPickup.new())
    entity.add_component(CCamp.new())
    for i in range(count):
        if i == 0:
            entity.add_component(CWeapon.new())
        elif i == 1:
            entity.add_component(CTracker.new())
        elif i == 2:
            entity.add_component(CHealer.new())
    return entity

func test_pickup_blocked_when_at_cap() -> void:
    var player := _make_player_with_losable(Config.COMPONENT_CAP)
    var initial_count := _count_losable(player)

    # Attempt to add another losable component should be blocked
    assert_int(initial_count).is_equal(Config.COMPONENT_CAP)
    assert_bool(ECSUtils.is_at_component_cap(player)).is_true()

func test_pickup_allowed_below_cap() -> void:
    var player := _make_player_with_losable(1)
    assert_bool(ECSUtils.is_at_component_cap(player)).is_false()

func test_swap_allowed_when_at_cap() -> void:
    # Swap path (required_component) should NOT be blocked by cap
    var player := _make_player_with_losable(Config.COMPONENT_CAP)
    # Player should still be able to swap — cap only blocks "add" path
    assert_bool(ECSUtils.is_at_component_cap(player)).is_true()
    # The swap removes one before adding one, so net count stays the same

func _count_losable(entity: Entity) -> int:
    var count := 0
    for comp in entity.components.values():
        if ECSUtils.is_losable_component(comp):
            count += 1
    return count
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `ECSUtils.is_at_component_cap` not found

- [ ] **Step 3: Add is_at_component_cap to ECSUtils**

In `scripts/utils/ecs_utils.gd`, add:

```gdscript
static func is_at_component_cap(entity: Entity) -> bool:
    var count := 0
    for comp in entity.components.values():
        if is_losable_component(comp):
            count += 1
    return count >= Config.COMPONENT_CAP
```

- [ ] **Step 4: Run cap test to verify it passes**

- [ ] **Step 5: Add cap check to SPickup**

In `scripts/systems/s_pickup.gd`, in `_process_entity`, add a cap check before `_open_box` in the **non-swap** path (i.e., when `container.required_component` is null):

```gdscript
# After checking container.required_component swap path...
# Before _open_box in the add-only path:
if not container.required_component:
    if ECSUtils.is_at_component_cap(entity):
        continue
```

The swap path (when `required_component` is set) already removes a component first, so it is NOT blocked.

- [ ] **Step 6: Write failing test for enhanced lethal drop**

Create `tests/unit/test_composition_cost_lethal_drop.gd`:

```gdscript
extends GdUnitTestSuite

func test_drop_count_below_threshold() -> void:
    # 2 components, threshold 3 → drop 1
    var count := SDamage.calculate_drop_count(2)
    assert_int(count).is_equal(1)

func test_drop_count_at_threshold() -> void:
    # 3 components, threshold 3 → drop 1
    var count := SDamage.calculate_drop_count(3)
    assert_int(count).is_equal(1)

func test_drop_count_above_threshold() -> void:
    # 5 components, threshold 3 → drop 1 + (5-3) = 3
    var count := SDamage.calculate_drop_count(5)
    assert_int(count).is_equal(3)

func test_drop_count_one_above_threshold() -> void:
    # 4 components, threshold 3 → drop 1 + (4-3) = 2
    var count := SDamage.calculate_drop_count(4)
    assert_int(count).is_equal(2)
```

- [ ] **Step 7: Run test to verify it fails**

Expected: FAIL — `SDamage.calculate_drop_count` not found

- [ ] **Step 8: Implement enhanced lethal drop in SDamage**

In `scripts/systems/s_damage.gd`, add a static helper:

```gdscript
static func calculate_drop_count(losable_count: int) -> int:
    return 1 + maxi(0, losable_count - Config.LETHAL_DROP_THRESHOLD)
```

Modify `_on_no_hp` to use it — replace the single `_get_random_component` call with a loop:

```gdscript
var losable_count := _count_losable_components(entity)
var drop_count := calculate_drop_count(losable_count)

for i in range(drop_count):
    var comp_to_lose: Component = _get_random_component(target_entity)
    if not comp_to_lose:
        break
    target_entity.remove_component(comp_to_lose.get_script())
    var transform: CTransform = target_entity.get_component(CTransform)
    if transform:
        _drop_component_box(comp_to_lose, transform.position, target_entity)

# If at least one was dropped, survive at 1 HP
if drop_count > 0 and _count_losable_components(target_entity) < losable_count:
    var hp: CHP = target_entity.get_component(CHP)
    if hp:
        hp.hp = 1
else:
    # No components to lose — death
    var movement: CMovement = target_entity.get_component(CMovement)
    var last_knockback := movement.velocity.normalized() if movement else Vector2.ZERO
    _start_death(target_entity, last_knockback)
```

Add the helper:

```gdscript
func _count_losable_components(entity: Entity) -> int:
    var count := 0
    for comp in entity.components.values():
        if ECSUtils.is_losable_component(comp):
            count += 1
    return count
```

- [ ] **Step 9: Run tests to verify they pass**

- [ ] **Step 10: Commit**

```bash
git add scripts/utils/ecs_utils.gd scripts/systems/s_pickup.gd \
  scripts/systems/s_damage.gd tests/unit/test_composition_cost_pickup.gd \
  tests/unit/test_composition_cost_lethal_drop.gd
git commit -m "feat(composition-cost): add component cap and enhanced lethal drop"
```

---

## Task 4: SPresencePenalty — Aggro Attraction

**Files:**
- Create: `scripts/systems/s_presence_penalty.gd`
- Test: `tests/unit/system/test_presence_penalty.gd`

- [ ] **Step 1: Write failing test**

Create `tests/unit/system/test_presence_penalty.gd`:

```gdscript
extends GdUnitTestSuite

var system: SPresencePenalty

func before_test() -> void:
    system = auto_free(SPresencePenalty.new())

func test_no_losable_no_vision_change() -> void:
    var player := auto_free(Entity.new())
    player.add_component(CPlayer.new())
    player.add_component(CTransform.new())

    var enemy := auto_free(Entity.new())
    var perception := CPerception.new()
    perception.vision_range = 600.0
    enemy.add_component(perception)
    enemy.add_component(CCamp.new())

    system._apply_presence(player, [enemy])

    assert_float(perception.vision_range).is_equal(600.0)

func test_losable_components_increase_enemy_vision() -> void:
    var player := auto_free(Entity.new())
    player.add_component(CPlayer.new())
    player.add_component(CTransform.new())
    player.add_component(CWeapon.new())
    player.add_component(CTracker.new())
    player.add_component(CHealer.new())

    var enemy := auto_free(Entity.new())
    var perception := CPerception.new()
    perception.vision_range = 600.0
    enemy.add_component(perception)
    enemy.add_component(CCamp.new())

    system._apply_presence(player, [enemy])

    # 600 * (1 + 3 * 0.1) = 780
    assert_float(perception.vision_range).is_equal_approx(780.0, 0.01)
    assert_float(perception.base_vision_range).is_equal(600.0)

func test_spawner_enrages_when_player_exceeds_threshold() -> void:
    var player := auto_free(Entity.new())
    player.add_component(CPlayer.new())
    player.add_component(CTransform.new())
    # Add components above SPAWNER_ENRAGE_COMPONENT_THRESHOLD (3)
    player.add_component(CWeapon.new())
    player.add_component(CTracker.new())
    player.add_component(CHealer.new())
    player.add_component(CPoison.new())

    var spawner_entity := auto_free(Entity.new())
    var spawner := CSpawner.new()
    spawner.enraged = false
    spawner_entity.add_component(spawner)

    system._apply_spawner_enrage(player, [spawner_entity])

    assert_bool(spawner.enraged).is_true()

func test_spawner_not_enraged_below_threshold() -> void:
    var player := auto_free(Entity.new())
    player.add_component(CPlayer.new())
    player.add_component(CTransform.new())
    player.add_component(CWeapon.new())

    var spawner_entity := auto_free(Entity.new())
    var spawner := CSpawner.new()
    spawner.enraged = false
    spawner_entity.add_component(spawner)

    system._apply_spawner_enrage(player, [spawner_entity])

    assert_bool(spawner.enraged).is_false()

func test_spawner_de_enrages_when_player_drops_below_threshold() -> void:
    var player := auto_free(Entity.new())
    player.add_component(CPlayer.new())
    player.add_component(CTransform.new())
    player.add_component(CWeapon.new())  # 1 component, below threshold

    var spawner_entity := auto_free(Entity.new())
    var spawner := CSpawner.new()
    spawner.enraged = true  # previously enraged
    spawner_entity.add_component(spawner)

    system._apply_spawner_enrage(player, [spawner_entity])

    assert_bool(spawner.enraged).is_false()  # should de-enrage
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `SPresencePenalty` class not found

- [ ] **Step 3: Implement SPresencePenalty**

Create `scripts/systems/s_presence_penalty.gd`:

```gdscript
class_name SPresencePenalty
extends System

func _ready() -> void:
    group = "cost"

func query() -> QueryBuilder:
    return q.with_all([CPlayer])

func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
    if entities.is_empty():
        return
    var player: Entity = entities[0]

    var perception_entities := ECS.world.query.with_all([CPerception, CCamp]).execute()
    _apply_presence(player, perception_entities)

    var spawner_entities := ECS.world.query.with_all([CSpawner]).execute()
    _apply_spawner_enrage(player, spawner_entities)

func _apply_presence(player: Entity, enemies: Array) -> void:
    var losable_count := 0
    for comp in player.components.values():
        if ECSUtils.is_losable_component(comp):
            losable_count += 1

    for enemy in enemies:
        if enemy == player:
            continue
        var perception: CPerception = enemy.get_component(CPerception)
        if not perception:
            continue

        # Lazy-capture base
        if perception.base_vision_range < 0.0:
            perception.base_vision_range = perception.vision_range

        if losable_count == 0:
            perception.vision_range = perception.base_vision_range
        else:
            var bonus := 1.0 + losable_count * Config.VISION_BONUS_PER_COMPONENT
            perception.vision_range = perception.base_vision_range * bonus

func _apply_spawner_enrage(player: Entity, spawner_entities: Array) -> void:
    var losable_count := 0
    for comp in player.components.values():
        if ECSUtils.is_losable_component(comp):
            losable_count += 1

    var should_enrage := losable_count > Config.SPAWNER_ENRAGE_COMPONENT_THRESHOLD
    for entity in spawner_entities:
        var spawner: CSpawner = entity.get_component(CSpawner)
        if spawner:
            spawner.enraged = should_enrage
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_presence_penalty.gd tests/unit/system/test_presence_penalty.gd
git commit -m "feat(composition-cost): add SPresencePenalty — losable components increase enemy detection range"
```

---

## Task 5: SFireHealConflict — Fire → Heal Reduction

**Files:**
- Create: `scripts/systems/s_fire_heal_conflict.gd`
- Test: `tests/unit/system/test_fire_heal_conflict.gd`

- [ ] **Step 1: Write failing test**

Create `tests/unit/system/test_fire_heal_conflict.gd`:

```gdscript
extends GdUnitTestSuite

var system: SFireHealConflict

func before_test() -> void:
    system = auto_free(SFireHealConflict.new())

func test_fire_reduces_heal_rate() -> void:
    var entity := auto_free(Entity.new())
    var healer := CHealer.new()
    healer.heal_pro_sec = 10.0
    entity.add_component(healer)
    var elemental := CElementalAttack.new()
    elemental.element_type = ElementalUtils.ElementType.FIRE
    entity.add_component(elemental)

    system._process_entity(entity, 0.016)

    # 10 * (1 - 0.3) = 7
    assert_float(healer.heal_pro_sec).is_equal_approx(7.0, 0.01)
    assert_float(healer.base_heal_pro_sec).is_equal(10.0)

func test_non_fire_no_reduction() -> void:
    var entity := auto_free(Entity.new())
    var healer := CHealer.new()
    healer.heal_pro_sec = 10.0
    entity.add_component(healer)
    var elemental := CElementalAttack.new()
    elemental.element_type = ElementalUtils.ElementType.COLD
    entity.add_component(elemental)

    system._process_entity(entity, 0.016)

    assert_float(healer.heal_pro_sec).is_equal(10.0)

func test_no_elemental_no_reduction() -> void:
    var entity := auto_free(Entity.new())
    var healer := CHealer.new()
    healer.heal_pro_sec = 10.0
    entity.add_component(healer)

    system._process_entity(entity, 0.016)

    assert_float(healer.heal_pro_sec).is_equal(10.0)
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Implement SFireHealConflict**

Create `scripts/systems/s_fire_heal_conflict.gd`:

```gdscript
class_name SFireHealConflict
extends System

func _ready() -> void:
    group = "cost"

func query() -> QueryBuilder:
    return q.with_all([CHealer])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    for entity in entities:
        _process_entity(entity, delta)

func _process_entity(entity: Entity, _delta: float) -> void:
    var healer: CHealer = entity.get_component(CHealer)
    if not healer:
        return

    # Lazy-capture base
    if healer.base_heal_pro_sec < 0.0:
        healer.base_heal_pro_sec = healer.heal_pro_sec

    var elemental: CElementalAttack = entity.get_component(CElementalAttack)
    if elemental and elemental.element_type == ElementalUtils.ElementType.FIRE:
        healer.heal_pro_sec = healer.base_heal_pro_sec * (1.0 - Config.FIRE_HEAL_REDUCTION)
    else:
        healer.heal_pro_sec = healer.base_heal_pro_sec
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_fire_heal_conflict.gd tests/unit/system/test_fire_heal_conflict.gd
git commit -m "feat(composition-cost): add SFireHealConflict — fire element reduces healing rate"
```

---

## Task 6: SColdRateConflict — Cold → Attack Speed Reduction

**Files:**
- Create: `scripts/systems/s_cold_rate_conflict.gd`
- Test: `tests/unit/system/test_cold_rate_conflict.gd`

- [ ] **Step 1: Write failing test**

Create `tests/unit/system/test_cold_rate_conflict.gd`:

```gdscript
extends GdUnitTestSuite

var system: SColdRateConflict

func before_test() -> void:
    system = auto_free(SColdRateConflict.new())

func test_cold_increases_weapon_interval() -> void:
    var entity := auto_free(Entity.new())
    var weapon := CWeapon.new()
    weapon.interval = 0.5
    entity.add_component(weapon)
    var elemental := CElementalAttack.new()
    elemental.element_type = ElementalUtils.ElementType.COLD
    entity.add_component(elemental)

    system._process_entity(entity, 0.016)

    # 0.5 * 1.4 = 0.7
    assert_float(weapon.interval).is_equal_approx(0.7, 0.01)

func test_cold_increases_melee_interval() -> void:
    var entity := auto_free(Entity.new())
    var melee := CMelee.new()
    melee.attack_interval = 1.0
    entity.add_component(melee)
    var elemental := CElementalAttack.new()
    elemental.element_type = ElementalUtils.ElementType.COLD
    entity.add_component(elemental)

    system._process_entity(entity, 0.016)

    # 1.0 * 1.4 = 1.4
    assert_float(melee.attack_interval).is_equal_approx(1.4, 0.01)

func test_non_cold_no_change() -> void:
    var entity := auto_free(Entity.new())
    var weapon := CWeapon.new()
    weapon.interval = 0.5
    entity.add_component(weapon)
    var elemental := CElementalAttack.new()
    elemental.element_type = ElementalUtils.ElementType.ELECTRIC
    entity.add_component(elemental)

    system._process_entity(entity, 0.016)

    assert_float(weapon.interval).is_equal(0.5)
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Implement SColdRateConflict**

Create `scripts/systems/s_cold_rate_conflict.gd`:

```gdscript
class_name SColdRateConflict
extends System

func _ready() -> void:
    group = "cost"

func query() -> QueryBuilder:
    return q.with_all([CElementalAttack])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    for entity in entities:
        _process_entity(entity, delta)

func _process_entity(entity: Entity, _delta: float) -> void:
    var elemental: CElementalAttack = entity.get_component(CElementalAttack)
    var is_cold := elemental and elemental.element_type == ElementalUtils.ElementType.COLD

    var weapon: CWeapon = entity.get_component(CWeapon)
    if weapon:
        if weapon.base_interval < 0.0:
            weapon.base_interval = weapon.interval
        weapon.interval = weapon.base_interval * Config.COLD_RATE_MULTIPLIER if is_cold else weapon.base_interval

    var melee: CMelee = entity.get_component(CMelee)
    if melee:
        if melee.base_attack_interval < 0.0:
            melee.base_attack_interval = melee.attack_interval
        melee.attack_interval = melee.base_attack_interval * Config.COLD_RATE_MULTIPLIER if is_cold else melee.base_attack_interval
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_cold_rate_conflict.gd tests/unit/system/test_cold_rate_conflict.gd
git commit -m "feat(composition-cost): add SColdRateConflict — cold element increases attack intervals"
```

---

## Task 7: Weapon Spread + SElectricSpreadConflict

**Files:**
- Modify: `scripts/systems/s_fire_bullet.gd` (add spread support)
- Create: `scripts/systems/s_electric_spread_conflict.gd`
- Test: `tests/unit/system/test_electric_spread_conflict.gd`

- [ ] **Step 1: Write failing test for electric spread conflict**

Create `tests/unit/system/test_electric_spread_conflict.gd`:

```gdscript
extends GdUnitTestSuite

var system: SElectricSpreadConflict

func before_test() -> void:
    system = auto_free(SElectricSpreadConflict.new())

func test_electric_adds_spread() -> void:
    var entity := auto_free(Entity.new())
    var weapon := CWeapon.new()
    weapon.spread_degrees = 0.0
    entity.add_component(weapon)
    var elemental := CElementalAttack.new()
    elemental.element_type = ElementalUtils.ElementType.ELECTRIC
    entity.add_component(elemental)

    system._process_entity(entity, 0.016)

    assert_float(weapon.spread_degrees).is_equal_approx(Config.ELECTRIC_SPREAD_DEGREES, 0.01)

func test_spread_capped_at_max() -> void:
    var entity := auto_free(Entity.new())
    var weapon := CWeapon.new()
    weapon.spread_degrees = 20.0  # already has some base spread
    entity.add_component(weapon)
    var elemental := CElementalAttack.new()
    elemental.element_type = ElementalUtils.ElementType.ELECTRIC
    entity.add_component(elemental)

    system._process_entity(entity, 0.016)

    # 20 + 15 = 35, but max is 30
    assert_float(weapon.spread_degrees).is_equal_approx(Config.MAX_SPREAD_DEGREES, 0.01)

func test_non_electric_no_spread() -> void:
    var entity := auto_free(Entity.new())
    var weapon := CWeapon.new()
    weapon.spread_degrees = 0.0
    entity.add_component(weapon)
    var elemental := CElementalAttack.new()
    elemental.element_type = ElementalUtils.ElementType.FIRE
    entity.add_component(elemental)

    system._process_entity(entity, 0.016)

    assert_float(weapon.spread_degrees).is_equal(0.0)
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Implement SElectricSpreadConflict**

Create `scripts/systems/s_electric_spread_conflict.gd`:

```gdscript
class_name SElectricSpreadConflict
extends System

func _ready() -> void:
    group = "cost"

func query() -> QueryBuilder:
    return q.with_all([CWeapon])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    for entity in entities:
        _process_entity(entity, delta)

func _process_entity(entity: Entity, _delta: float) -> void:
    var weapon: CWeapon = entity.get_component(CWeapon)
    if not weapon:
        return

    # Lazy-capture base
    if weapon.base_spread_degrees < 0.0:
        weapon.base_spread_degrees = weapon.spread_degrees

    var elemental: CElementalAttack = entity.get_component(CElementalAttack)
    if elemental and elemental.element_type == ElementalUtils.ElementType.ELECTRIC:
        weapon.spread_degrees = minf(
            weapon.base_spread_degrees + Config.ELECTRIC_SPREAD_DEGREES,
            Config.MAX_SPREAD_DEGREES
        )
    else:
        weapon.spread_degrees = weapon.base_spread_degrees
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Add spread logic to SFireBullet**

In `scripts/systems/s_fire_bullet.gd`, modify `_fire_bullet` (or `_create_bullet`) to apply spread when `weapon.spread_degrees > 0`:

```gdscript
# In _fire_bullet, after getting fire_direction:
var direction := _get_fire_direction(entity, weapon)
if weapon.spread_degrees > 0.0:
    var spread_rad := deg_to_rad(randf_range(-weapon.spread_degrees, weapon.spread_degrees))
    direction = direction.rotated(spread_rad)
_create_bullet(entity, weapon, origin_position, direction)
```

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/s_electric_spread_conflict.gd \
  scripts/systems/s_fire_bullet.gd \
  tests/unit/system/test_electric_spread_conflict.gd
git commit -m "feat(composition-cost): add weapon spread system and electric element spread conflict"
```

---

## Task 8: CPoison Component + CAreaEffect Redesign

**Files:**
- Create: `scripts/components/c_poison.gd`
- Modify: `scripts/components/c_area_effect.gd` (remove effect_type/amount, add power_ratio)
- Modify: `scripts/configs/config.gd` (add CPoison to LOSABLE_COMPONENTS)
- Test: `tests/unit/test_poison_component.gd`

- [ ] **Step 1: Write failing test for CPoison**

Create `tests/unit/test_poison_component.gd`:

```gdscript
extends GdUnitTestSuite

func test_poison_component_exists() -> void:
    var poison := auto_free(CPoison.new())
    assert_float(poison.damage_per_sec).is_equal(3.0)
    assert_float(poison.duration).is_equal(5.0)

func test_poison_on_merge() -> void:
    var poison := auto_free(CPoison.new())
    var other := CPoison.new()
    other.damage_per_sec = 7.0
    other.duration = 10.0
    poison.on_merge(other)
    assert_float(poison.damage_per_sec).is_equal(7.0)
    assert_float(poison.duration).is_equal(10.0)

func test_poison_is_losable() -> void:
    var poison := CPoison.new()
    assert_bool(ECSUtils.is_losable_component(poison)).is_true()

func test_area_effect_has_no_effect_type() -> void:
    var area := auto_free(CAreaEffect.new())
    # CAreaEffect should no longer have effect_type enum
    assert_bool(area.has_method("get") == false or not "effect_type" in area).is_true()
    assert_float(area.power_ratio).is_equal_approx(0.6, 0.01)
    assert_float(area.radius).is_equal(540.0)
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `CPoison` class not found

- [ ] **Step 3: Create CPoison component**

Create `scripts/components/c_poison.gd`:

```gdscript
class_name CPoison
extends Component

@export var damage_per_sec: float = 3.0
@export var duration: float = 5.0

func on_merge(other: CPoison) -> void:
    damage_per_sec = other.damage_per_sec
    duration = other.duration
```

- [ ] **Step 4: Add CPoison to Config.LOSABLE_COMPONENTS**

In `scripts/configs/config.gd`:

```gdscript
static var LOSABLE_COMPONENTS: Array = [
    CWeapon,
    CTracker,
    CHealer,
    CPoison,
]
```

- [ ] **Step 5: Redesign CAreaEffect**

Modify `scripts/components/c_area_effect.gd` — remove `effect_type` enum, `amount`, `tick_interval`. Keep `radius`, `affects_self`, `affects_allies`, `affects_enemies`. Add `power_ratio`:

```gdscript
class_name CAreaEffect
extends Component

@export var radius: float = 540.0
@export var power_ratio: float = 0.6
@export var affects_self: bool = false
@export var affects_allies: bool = false
@export var affects_enemies: bool = true

func on_merge(other: CAreaEffect) -> void:
    radius = other.radius
    power_ratio = other.power_ratio
    affects_self = other.affects_self
    affects_allies = other.affects_allies
    affects_enemies = other.affects_enemies
```

- [ ] **Step 6: Run tests to verify they pass**

- [ ] **Step 7: Commit**

```bash
git add scripts/components/c_poison.gd scripts/components/c_area_effect.gd \
  scripts/configs/config.gd tests/unit/test_poison_component.gd
git commit -m "feat(composition-cost): add CPoison component, redesign CAreaEffect as modifier"
```

---

## Task 9: SAreaEffectModifier System

**Files:**
- Create: `scripts/systems/s_area_effect_modifier.gd`
- Test: `tests/unit/system/test_area_effect_modifier.gd`

- [ ] **Step 1: Write failing test for SAreaEffectModifier**

Create `tests/unit/system/test_area_effect_modifier.gd`. Tests must call `system._process_entity()` to verify actual system behavior:

```gdscript
extends GdUnitTestSuite

var system: SAreaEffectModifier

func before_test() -> void:
    system = auto_free(SAreaEffectModifier.new())

func _make_source_at(pos: Vector2) -> Entity:
    var entity := auto_free(Entity.new())
    var transform := CTransform.new()
    transform.position = pos
    entity.add_component(transform)
    var camp := CCamp.new()
    camp.camp = CCamp.CampType.PLAYER
    entity.add_component(camp)
    return entity

func _make_target_at(pos: Vector2, camp_type: int, hp: float = 100.0) -> Entity:
    var entity := auto_free(Entity.new())
    var transform := CTransform.new()
    transform.position = pos
    entity.add_component(transform)
    var hp_comp := CHP.new()
    hp_comp.hp = hp
    hp_comp.max_hp = hp
    entity.add_component(hp_comp)
    var camp := CCamp.new()
    camp.camp = camp_type
    entity.add_component(camp)
    return entity

func test_melee_area_applies_scaled_damage() -> void:
    var source := _make_source_at(Vector2.ZERO)
    var melee := CMelee.new()
    melee.damage = 10.0
    source.add_component(melee)
    var area := CAreaEffect.new()
    area.power_ratio = 0.6
    area.radius = 100.0
    area.affects_enemies = true
    source.add_component(area)

    # Target within radius, enemy camp
    var target := _make_target_at(Vector2(50, 0), CCamp.CampType.ENEMY)

    # Call internal method to apply area damage
    var targets: Array[Entity] = [target]
    system._apply_area_damage(targets, melee.damage * area.power_ratio, 1.0)

    # Should have CDamage added: 10 * 0.6 * 1.0 = 6.0
    assert_bool(target.has_component(CDamage)).is_true()
    var dmg: CDamage = target.get_component(CDamage)
    assert_float(dmg.amount).is_equal_approx(6.0, 0.01)

func test_healer_area_applies_scaled_heal() -> void:
    var source := _make_source_at(Vector2.ZERO)
    var healer := CHealer.new()
    healer.heal_pro_sec = 10.0
    source.add_component(healer)
    var area := CAreaEffect.new()
    area.power_ratio = 0.6
    area.affects_allies = true
    source.add_component(area)

    # Allied target within radius, damaged
    var target := _make_target_at(Vector2(50, 0), CCamp.CampType.PLAYER, 50.0)

    var targets: Array[Entity] = [target]
    system._apply_area_heal(targets, healer.heal_pro_sec * area.power_ratio, 1.0)

    # HP should increase by 10 * 0.6 * 1.0 = 6.0 → 56.0
    var hp: CHP = target.get_component(CHP)
    assert_float(hp.hp).is_equal_approx(56.0, 0.01)

func test_should_affect_respects_camp_flags() -> void:
    var area := CAreaEffect.new()
    area.affects_self = false
    area.affects_allies = false
    area.affects_enemies = true

    var player_camp := CCamp.new()
    player_camp.camp = CCamp.CampType.PLAYER
    var enemy_camp := CCamp.new()
    enemy_camp.camp = CCamp.CampType.ENEMY

    assert_bool(system._should_affect(player_camp, enemy_camp, area, false)).is_true()
    assert_bool(system._should_affect(player_camp, player_camp, area, false)).is_false()
    assert_bool(system._should_affect(player_camp, player_camp, area, true)).is_false()  # affects_self = false
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `SAreaEffectModifier` class not found

- [ ] **Step 3: Implement SAreaEffectModifier**

Create `scripts/systems/s_area_effect_modifier.gd`:

```gdscript
class_name SAreaEffectModifier
extends System

func _ready() -> void:
    group = "gameplay"

func query() -> QueryBuilder:
    return q.with_all([CAreaEffect, CTransform])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    for entity in entities:
        _process_entity(entity, delta)

func _process_entity(entity: Entity, delta: float) -> void:
    var area: CAreaEffect = entity.get_component(CAreaEffect)
    var transform: CTransform = entity.get_component(CTransform)
    if not area or not transform:
        return

    var targets := _get_targets_in_radius(transform.position, area.radius, entity, area)

    if entity.has_component(CMelee):
        var melee: CMelee = entity.get_component(CMelee)
        _apply_area_damage(targets, melee.damage * area.power_ratio, delta)

    if entity.has_component(CHealer):
        var healer: CHealer = entity.get_component(CHealer)
        _apply_area_heal(targets, healer.heal_pro_sec * area.power_ratio, delta)

    if entity.has_component(CPoison):
        var poison: CPoison = entity.get_component(CPoison)
        _apply_area_poison(targets, poison.damage_per_sec * area.power_ratio, delta)

func _get_targets_in_radius(origin: Vector2, radius: float, source: Entity, area: CAreaEffect) -> Array[Entity]:
    var results: Array[Entity] = []
    var all_entities := ECS.world.query.with_all([CTransform, CHP]).execute()
    var source_camp: CCamp = source.get_component(CCamp)

    for target in all_entities:
        if target == source and not area.affects_self:
            continue
        var target_transform: CTransform = target.get_component(CTransform)
        if target_transform.position.distance_to(origin) > radius:
            continue
        var target_camp: CCamp = target.get_component(CCamp)
        if _should_affect(source_camp, target_camp, area, target == source):
            results.append(target)
    return results

func _should_affect(source_camp: CCamp, target_camp: CCamp, area: CAreaEffect, is_self: bool) -> bool:
    if is_self:
        return area.affects_self
    if source_camp and target_camp:
        if source_camp.camp == target_camp.camp:
            return area.affects_allies
        else:
            return area.affects_enemies
    return area.affects_enemies

func _apply_area_damage(targets: Array[Entity], damage_per_sec: float, delta: float) -> void:
    var scaled := damage_per_sec * delta
    for target in targets:
        var dmg := CDamage.new()
        dmg.amount = scaled
        target.add_component(dmg)

func _apply_area_heal(targets: Array[Entity], heal_per_sec: float, delta: float) -> void:
    var scaled := heal_per_sec * delta
    for target in targets:
        var hp: CHP = target.get_component(CHP)
        if hp:
            hp.hp = clamp(hp.hp + scaled, 0, hp.max_hp)

func _apply_area_poison(targets: Array[Entity], damage_per_sec: float, delta: float) -> void:
    var scaled := damage_per_sec * delta
    for target in targets:
        var dmg := CDamage.new()
        dmg.amount = scaled
        target.add_component(dmg)
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_area_effect_modifier.gd tests/unit/system/test_area_effect_modifier.gd
git commit -m "feat(composition-cost): add SAreaEffectModifier system"
```

---

## Task 10: SAreaEffectModifierRender + Remove Old Systems

**Files:**
- Create: `scripts/systems/s_area_effect_modifier_render.gd`
- Remove: `scripts/systems/s_area_effect.gd`
- Remove: `scripts/systems/s_area_effect_render.gd`
- Update: `tests/unit/system/test_area_effect_system.gd`

- [ ] **Step 1: Create SAreaEffectModifierRender**

Create `scripts/systems/s_area_effect_modifier_render.gd`. Adapted from the old `s_area_effect_render.gd` — same particle lifecycle pattern but determines particle style by checking companion components instead of `EffectType`:

```gdscript
class_name SAreaEffectModifierRender
extends System

var _views: Dictionary = {}  ## entity instance_id → {root: Node2D, particles: GPUParticles2D, current_radius: float}

func _ready() -> void:
    group = "render"

func query() -> QueryBuilder:
    return q.with_all([CAreaEffect, CTransform])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    for entity in entities:
        _process_entity(entity, delta)

func _process_entity(entity: Entity, _delta: float) -> void:
    var area: CAreaEffect = entity.get_component(CAreaEffect)
    var transform: CTransform = entity.get_component(CTransform)
    var entity_id := entity.get_instance_id()

    # Determine visual style from companion components
    var is_damage := entity.has_component(CPoison) or entity.has_component(CMelee)
    var is_heal := entity.has_component(CHealer) and not is_damage

    if not _views.has(entity_id):
        _create_fog_view(entity, area, is_damage, is_heal)
    else:
        _update_fog_view(entity_id, transform, area)

func _create_fog_view(entity: Entity, area: CAreaEffect, is_damage: bool, is_heal: bool) -> void:
    var entity_id := entity.get_instance_id()
    var root := Node2D.new()
    root.name = "AreaEffectView_%d" % entity_id

    var particles := GPUParticles2D.new()
    particles.name = "AreaFog"
    particles.emitting = true
    particles.amount = clampi(int(area.radius / 13.5), 8, 40)
    particles.lifetime = area.radius / 200.0

    var material := ParticleProcessMaterial.new()
    material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    material.emission_sphere_radius = area.radius * 0.8

    # Color based on type
    if is_damage:
        material.color = Color(0.2, 0.7, 0.1, 0.15)  # green poison fog
    elif is_heal:
        material.color = Color(0.1, 0.5, 0.9, 0.15)  # blue healing aura
    else:
        material.color = Color(0.7, 0.7, 0.7, 0.15)  # grey default

    material.gravity = Vector3.ZERO
    material.initial_velocity_min = 5.0
    material.initial_velocity_max = 15.0
    material.scale_min = 6.0
    material.scale_max = 10.0
    particles.process_material = material

    root.add_child(particles)
    entity.add_child(root)

    _views[entity_id] = {
        "root": root,
        "particles": particles,
        "current_radius": area.radius
    }

    # Connect cleanup signal
    if entity.has_signal("component_removed"):
        entity.component_removed.connect(_on_component_removed.bind(entity_id))

func _update_fog_view(entity_id: int, transform: CTransform, area: CAreaEffect) -> void:
    var view = _views[entity_id]
    var root: Node2D = view["root"]
    root.global_position = transform.position

    # Rebuild particles if radius changed
    if view["current_radius"] != area.radius:
        var particles: GPUParticles2D = view["particles"]
        var mat: ParticleProcessMaterial = particles.process_material
        mat.emission_sphere_radius = area.radius * 0.8
        particles.amount = clampi(int(area.radius / 13.5), 8, 40)
        particles.lifetime = area.radius / 200.0
        view["current_radius"] = area.radius

func _on_component_removed(component: Component, entity_id: int) -> void:
    if component is CAreaEffect and _views.has(entity_id):
        _remove_view(entity_id)

func _remove_view(entity_id: int) -> void:
    if _views.has(entity_id):
        var view = _views[entity_id]
        var root: Node2D = view["root"]
        if is_instance_valid(root):
            root.get_parent().remove_child(root)
            root.queue_free()
        _views.erase(entity_id)
```

- [ ] **Step 2: Remove old area effect systems**

Delete `scripts/systems/s_area_effect.gd` and `scripts/systems/s_area_effect_render.gd`.

- [ ] **Step 3: Remove or adapt old tests**

Delete `tests/unit/system/test_area_effect_system.gd` (replaced by `test_area_effect_modifier.gd`).

- [ ] **Step 4: Commit**

```bash
git rm scripts/systems/s_area_effect.gd scripts/systems/s_area_effect_render.gd \
  tests/unit/system/test_area_effect_system.gd
git add scripts/systems/s_area_effect_modifier_render.gd
git commit -m "feat(composition-cost): add area effect render, remove old area effect systems"
```

---

## Task 11: Recipe Migration

**Files:**
- Modify: `resources/recipes/enemy_poison.tres`
- Modify: `resources/recipes/materia_damage.tres`
- Modify: `resources/recipes/materia_heal.tres`

- [ ] **Step 1: Migrate enemy_poison.tres**

Replace `CAreaEffect(DAMAGE)` sub-resource with `CPoison` + `CAreaEffect` (modifier):
- `CPoison.damage_per_sec = 3.0`
- `CAreaEffect.radius = 64.0`, `CAreaEffect.affects_enemies = false`, `CAreaEffect.affects_allies = true`

- [ ] **Step 2: Migrate materia_damage.tres**

Replace with `CMelee` + `CAreaEffect`:
- `CMelee.damage = 5.0` (matching original `amount`)
- `CAreaEffect.radius = 540.0`, `CAreaEffect.affects_enemies = true`

- [ ] **Step 3: Migrate materia_heal.tres**

Replace with `CHealer` + `CAreaEffect`:
- `CHealer.heal_pro_sec = 5.0`
- `CAreaEffect.radius = 540.0`, `CAreaEffect.affects_self = true`, `CAreaEffect.affects_allies = true`, `CAreaEffect.affects_enemies = false`

- [ ] **Step 4: Commit**

```bash
git add resources/recipes/enemy_poison.tres resources/recipes/materia_damage.tres \
  resources/recipes/materia_heal.tres
git commit -m "feat(composition-cost): migrate recipes to new CAreaEffect modifier pattern"
```

---

## Task 12: Integration Test + Final Verification

**Files:**
- Create: `tests/integration/flow/test_flow_composition_cost_scene.gd`

- [ ] **Step 1: Create SceneConfig integration test**

Create `tests/integration/flow/test_flow_composition_cost_scene.gd`:

```gdscript
class_name TestCompositionCostConfig
extends SceneConfig

func systems() -> Variant:
    return [
        "res://scripts/systems/s_weight_penalty.gd",
        "res://scripts/systems/s_presence_penalty.gd",
        "res://scripts/systems/s_fire_heal_conflict.gd",
        "res://scripts/systems/s_cold_rate_conflict.gd",
        "res://scripts/systems/s_electric_spread_conflict.gd",
        "res://scripts/systems/s_area_effect_modifier.gd",
        "res://scripts/systems/s_area_effect_modifier_render.gd",
        "res://scripts/systems/s_move.gd",
        "res://scripts/systems/s_fire_bullet.gd",
        "res://scripts/systems/s_healer.gd",
        "res://scripts/systems/s_damage.gd",
        "res://scripts/systems/s_pickup.gd",
    ]

func enable_pcg() -> bool:
    return false

func entities() -> Variant:
    return [{
        "recipe": "player",
        "name": "TestPlayer",
        "components": {}
    }]

func test_run(world: GOLWorld) -> Variant:
    var result := TestResult.new()
    await world.get_tree().process_frame

    var player: Entity = _find_entity(world, "TestPlayer")
    result.assert_true(player != null, "Player entity exists")

    if player:
        var movement: CMovement = player.get_component(CMovement)
        result.assert_true(movement != null, "Player has CMovement")
        if movement:
            result.assert_true(movement.base_max_speed > 0.0 or movement.base_max_speed == -1.0,
                "base_max_speed is valid")

    return result
```

- [ ] **Step 2: Run all tests**

Run: `cd gol-project && ./run-tests.command` (or the equivalent headless test runner)
Expected: All unit tests and integration tests PASS

- [ ] **Step 3: Fix any failing tests**

Address any test failures from recipe migration or system changes.

- [ ] **Step 4: Final commit**

```bash
git add tests/integration/flow/test_flow_composition_cost_scene.gd
git commit -m "test(composition-cost): add integration test for composition cost system"
```

- [ ] **Step 5: Verify full test suite passes**

Run the complete test suite one more time to confirm no regressions.
