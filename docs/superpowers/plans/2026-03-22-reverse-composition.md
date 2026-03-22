# Reverse Composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stripped components drop as pickable Box entities on lethal damage, completing the combat reward loop.

**Architecture:** Extend `CContainer` with `stored_components` for instance-mode storage. Modify `SDamage._on_no_hp()` to create Box entities from stripped components. Modify `SPickup._open_box()` to merge stored component instances back into the player.

**Tech Stack:** Godot 4.6, GDScript, GECS ECS, gdUnit4

**Spec:** `docs/superpowers/specs/2026-03-22-reverse-composition-design.md`

**Closes:** #106, #171

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `scripts/components/c_container.gd` | Modify | Add `stored_components` field |
| `scripts/systems/s_damage.gd` | Modify | Add `_drop_component_box()`, call it in `_on_no_hp()` |
| `scripts/systems/s_pickup.gd` | Modify | Add instance-mode branch in `_open_box()` |
| `tests/unit/test_container_component.gd` | Create | Unit tests for CContainer stored_components |
| `tests/unit/system/test_component_drop.gd` | Create | Unit tests for SDamage component drop (with World) |
| `tests/unit/system/test_pickup_instance.gd` | Create | Unit tests for SPickup._open_box instance-mode |
| `tests/integration/flow/test_flow_component_drop.gd` | Create | Integration: kill→drop→pickup E2E flow |

---

### Task 1: CContainer — add stored_components field

**Files:**
- Modify: `scripts/components/c_container.gd`
- Create: `tests/unit/test_container_component.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_container_component.gd`:

```gdscript
extends GdUnitTestSuite


func test_stored_components_default_empty() -> void:
	var container := auto_free(CContainer.new())
	assert_array(container.stored_components).is_empty()


func test_stored_components_holds_instance() -> void:
	var container := auto_free(CContainer.new())
	var weapon := CWeapon.new()
	weapon.attack_range = 999.0
	container.stored_components = [weapon]

	assert_array(container.stored_components).has_size(1)
	var retrieved: CWeapon = container.stored_components[0] as CWeapon
	assert_float(retrieved.attack_range).is_equal(999.0)


func test_stored_components_precedence_over_recipe_id() -> void:
	## When both modes are set, stored_components is the intended mode.
	## This test documents the invariant — enforcement is in SPickup.
	var container := auto_free(CContainer.new())
	container.stored_recipe_id = "weapon_rifle"
	container.stored_components = [CTracker.new()]

	assert_array(container.stored_components).is_not_empty()
	assert_str(container.stored_recipe_id).is_not_empty()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gol-unittest` skill targeting `res://tests/unit/test_container_component.gd`

Expected: FAIL — `stored_components` property does not exist on CContainer.

- [ ] **Step 3: Add stored_components to CContainer**

In `scripts/components/c_container.gd`, add after line 6 (`@export var stored_recipe_id`):

```gdscript
## Component instances for direct storage (runtime only, not exported).
## When non-empty, takes precedence over stored_recipe_id in SPickup.
var stored_components: Array[Component] = []
```

Full file after edit:

```gdscript
class_name CContainer
extends Component


## Recipe ID for stored item (use ServiceContext.recipe().get_recipe() to resolve)
@export var stored_recipe_id: String = ""

## Component instances for direct storage (runtime only, not exported).
## When non-empty, takes precedence over stored_recipe_id in SPickup.
var stored_components: Array[Component] = []

@export var required_component: Component = null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `gol-unittest` skill targeting `res://tests/unit/test_container_component.gd`

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd gol-project
git add scripts/components/c_container.gd tests/unit/test_container_component.gd
git commit -m "feat(container): add stored_components for instance-mode storage

CContainer can now hold actual component instances for reverse
composition drops. stored_components takes precedence over
stored_recipe_id when non-empty."
```

---

### Task 2: SDamage — drop component as Box on lethal damage

**Files:**
- Modify: `scripts/systems/s_damage.gd:222-231`
- Create: `tests/unit/system/test_component_drop.gd`

**Reference:** Existing `_spawner_drop_loot()` pattern at `s_damage.gd:265-301` for Box creation.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/system/test_component_drop.gd`:

```gdscript
extends GdUnitTestSuite
## Tests that SDamage._on_no_hp() creates a Box when stripping a component.
## Uses a real World so _drop_component_box can call ECS.world.add_entity.

var _world: World = null


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	ECS.world = _world


func after_test() -> void:
	if _world != null:
		_world.free()
		_world = null
	ECS.world = null


func _create_enemy_with_weapon(weapon_range: float = 42.0) -> Entity:
	var enemy := Entity.new()
	enemy.name = "enemy_basic@99999"
	var hp := CHP.new()
	hp.max_hp = 10.0
	hp.hp = 10.0
	enemy.add_component(hp)
	var transform := CTransform.new()
	transform.position = Vector2(50, 75)
	enemy.add_component(transform)
	var weapon := CWeapon.new()
	weapon.attack_range = weapon_range
	weapon.bullet_recipe_id = "bullet_normal"
	enemy.add_component(weapon)
	var camp := CCamp.new()
	camp.camp = CCamp.CampType.ENEMY
	enemy.add_component(camp)
	var movement := CMovement.new()
	enemy.add_component(movement)
	_world.add_entity(enemy)
	return enemy


func _find_box_in_world() -> Entity:
	for child in _world.get_children():
		if child is Entity and child.has_component(CContainer):
			var container: CContainer = child.get_component(CContainer)
			if container.stored_components.size() > 0:
				return child
	return null


func test_drop_component_box_creates_box_with_stored_component() -> void:
	## _drop_component_box creates a Box entity in the world with the component inside.
	var system := auto_free(SDamage.new())
	add_child(system)

	var weapon := CWeapon.new()
	weapon.attack_range = 42.0

	system._drop_component_box(weapon, Vector2(100, 200))

	var box := _find_box_in_world()
	assert_object(box).is_not_null()
	var container: CContainer = box.get_component(CContainer)
	assert_array(container.stored_components).has_size(1)
	var stored: CWeapon = container.stored_components[0] as CWeapon
	assert_float(stored.attack_range).is_equal(42.0)


func test_drop_component_box_has_lifetime() -> void:
	## Box should have CLifeTime set to 120s for auto-despawn.
	var system := auto_free(SDamage.new())
	add_child(system)

	system._drop_component_box(CWeapon.new(), Vector2.ZERO)

	var box := _find_box_in_world()
	assert_object(box).is_not_null()
	assert_bool(box.has_component(CLifeTime)).is_true()
	var lt: CLifeTime = box.get_component(CLifeTime)
	assert_float(lt.lifetime).is_equal(120.0)


func test_on_no_hp_strips_component_and_drops_box() -> void:
	## Enemy with CWeapon takes lethal damage → loses CWeapon → Box appears.
	var system := auto_free(SDamage.new())
	add_child(system)

	var enemy := _create_enemy_with_weapon(42.0)
	assert_bool(enemy.has_component(CWeapon)).is_true()

	# Deal lethal damage via CDamage
	var damage := CDamage.new()
	damage.amount = 999.0
	damage.knockback_direction = Vector2.RIGHT
	enemy.add_component(damage)
	system._process_entity(enemy, 0.016)

	# Enemy should have lost CWeapon
	assert_bool(enemy.has_component(CWeapon)).is_false()

	# Box should exist with the weapon
	var box := _find_box_in_world()
	assert_object(box).is_not_null()
	var stored: CWeapon = box.get_component(CContainer).stored_components[0] as CWeapon
	assert_float(stored.attack_range).is_equal(42.0)


func test_no_box_when_no_losable_components() -> void:
	## Entity with no LOSABLE_COMPONENTS gets CDead, no Box created.
	var system := auto_free(SDamage.new())
	add_child(system)

	var enemy := Entity.new()
	enemy.name = "bare@11111"
	enemy.add_component(CHP.new())
	enemy.add_component(CTransform.new())
	var camp := CCamp.new()
	camp.camp = CCamp.CampType.ENEMY
	enemy.add_component(camp)
	var movement := CMovement.new()
	enemy.add_component(movement)
	_world.add_entity(enemy)

	var damage := CDamage.new()
	damage.amount = 999.0
	enemy.add_component(damage)
	system._process_entity(enemy, 0.016)

	# No losable components → death triggered, no box
	var box := _find_box_in_world()
	assert_object(box).is_null()
	assert_bool(enemy.has_component(CDead)).is_true()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gol-unittest` skill targeting `res://tests/unit/system/test_component_drop.gd`

Expected: FAIL — `_drop_component_box` method does not exist on SDamage.

- [ ] **Step 3: Add _drop_component_box and modify _on_no_hp**

In `scripts/systems/s_damage.gd`, add the `_drop_component_box` method after `_spawner_drop_loot` (after line 301), and modify `_on_no_hp` to call it.

Add new method after line 301:

```gdscript
func _drop_component_box(component: Component, position: Vector2) -> void:
	var box := Entity.new()
	box.name = "ComponentDrop"

	var box_transform := CTransform.new()
	box_transform.position = position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
	box.add_component(box_transform)

	var sprite := CSprite.new()
	var texture := load("res://assets/sprite_sheets/boxes/box_re_texture.png") as Texture2D
	if texture:
		sprite.texture = texture
	box.add_component(sprite)

	var collision := CCollision.new()
	var collision_shape := CircleShape2D.new()
	collision_shape.radius = 16.0
	collision.collision_shape = collision_shape
	box.add_component(collision)

	var container := CContainer.new()
	container.stored_components = [component]
	box.add_component(container)

	var lifetime := CLifeTime.new()
	lifetime.lifetime = 120.0
	box.add_component(lifetime)

	ECS.world.add_entity(box)
```

Modify `_on_no_hp` at lines 222-226. Replace:

```gdscript
	# Try to lose a component first
	var comps_to_lose: Component = _get_random_component(target_entity)
	if comps_to_lose:
		print("Lose Component: ", target_entity, ' -> ', comps_to_lose.get_script().resource_path)
		target_entity.remove_component(comps_to_lose.get_script())
```

With:

```gdscript
	# Try to lose a component first — drop it as a pickable Box
	var comps_to_lose: Component = _get_random_component(target_entity)
	if comps_to_lose:
		print("Lose Component: ", target_entity, ' -> ', comps_to_lose.get_script().resource_path)
		target_entity.remove_component(comps_to_lose.get_script())
		var transform: CTransform = target_entity.get_component(CTransform)
		if transform:
			_drop_component_box(comps_to_lose, transform.position)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `gol-unittest` skill targeting `res://tests/unit/system/test_component_drop.gd`

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd gol-project
git add scripts/systems/s_damage.gd tests/unit/system/test_component_drop.gd
git commit -m "feat(damage): drop stripped component as pickable Box

When _on_no_hp strips a LOSABLE_COMPONENT, it now spawns a Box
entity at the death position containing the component instance.
Uses same Box pattern as _spawner_drop_loot."
```

---

### Task 3: SPickup — handle instance-mode containers

**Files:**
- Modify: `scripts/systems/s_pickup.gd:91-111`
- Create: `tests/unit/system/test_pickup_instance.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/system/test_pickup_instance.gd`:

```gdscript
extends GdUnitTestSuite
## Tests for SPickup instance-mode merge via _open_box.

var _world: World = null


func before() -> void:
	GOL.setup()


func after() -> void:
	if _world != null:
		_world.free()
		_world = null
	ECS.world = null
	GOL.teardown()


func before_test() -> void:
	_world = World.new()
	add_child(_world)
	ECS.world = _world


func _create_player() -> Entity:
	var player := Entity.new()
	player.name = "player@00001"
	player.add_component(CTransform.new())
	player.add_component(CPickup.new())
	var collision := CCollision.new()
	collision.collision_shape = CircleShape2D.new()
	player.add_component(collision)
	_world.add_entity(player)
	return player


func _create_instance_box(components: Array[Component], pos: Vector2 = Vector2.ZERO) -> Entity:
	var box := Entity.new()
	box.name = "ComponentDrop"
	var transform := CTransform.new()
	transform.position = pos
	box.add_component(transform)
	var container := CContainer.new()
	container.stored_components = components
	box.add_component(container)
	var sprite := CSprite.new()
	box.add_component(sprite)
	var collision := CCollision.new()
	collision.collision_shape = CircleShape2D.new()
	box.add_component(collision)
	_world.add_entity(box)
	return box


func test_open_box_instance_mode_adds_new_component() -> void:
	## Player has no CWeapon, opens box with CWeapon → gains CWeapon.
	var system := auto_free(SPickup.new())
	add_child(system)

	var player := _create_player()
	assert_bool(player.has_component(CWeapon)).is_false()

	var weapon := CWeapon.new()
	weapon.attack_range = 77.0
	weapon.bullet_recipe_id = "bullet_normal"
	var box := _create_instance_box([weapon])

	var pickup: CPickup = player.get_component(CPickup)
	system._open_box(player, box, pickup)

	assert_bool(player.has_component(CWeapon)).is_true()
	var result: CWeapon = player.get_component(CWeapon)
	assert_float(result.attack_range).is_equal(77.0)


func test_open_box_instance_mode_merges_existing_weapon() -> void:
	## Player already has CWeapon, opens box with CWeapon → on_merge replaces.
	var system := auto_free(SPickup.new())
	add_child(system)

	var player := _create_player()
	var old_weapon := CWeapon.new()
	old_weapon.attack_range = 10.0
	old_weapon.bullet_recipe_id = "bullet_old"
	player.add_component(old_weapon)

	var new_weapon := CWeapon.new()
	new_weapon.attack_range = 99.0
	new_weapon.bullet_recipe_id = "bullet_new"
	var box := _create_instance_box([new_weapon])

	var pickup: CPickup = player.get_component(CPickup)
	system._open_box(player, box, pickup)

	var result: CWeapon = player.get_component(CWeapon)
	assert_float(result.attack_range).is_equal(99.0)
	assert_str(result.bullet_recipe_id).is_equal("bullet_new")


func test_open_box_instance_mode_tracker_no_merge() -> void:
	## Player has CTracker, opens box with CTracker → no-op (no on_merge).
	var system := auto_free(SPickup.new())
	add_child(system)

	var player := _create_player()
	var existing_tracker := CTracker.new()
	existing_tracker.track_range = 50.0
	player.add_component(existing_tracker)

	var new_tracker := CTracker.new()
	new_tracker.track_range = 200.0
	var box := _create_instance_box([new_tracker])

	var pickup: CPickup = player.get_component(CPickup)
	system._open_box(player, box, pickup)

	var result: CTracker = player.get_component(CTracker)
	assert_float(result.track_range).is_equal(50.0)


func test_open_box_instance_mode_tracker_added_when_missing() -> void:
	## Player has no CTracker, opens box with CTracker → gains it.
	var system := auto_free(SPickup.new())
	add_child(system)

	var player := _create_player()
	assert_bool(player.has_component(CTracker)).is_false()

	var tracker := CTracker.new()
	tracker.track_range = 150.0
	var box := _create_instance_box([tracker])

	var pickup: CPickup = player.get_component(CPickup)
	system._open_box(player, box, pickup)

	assert_bool(player.has_component(CTracker)).is_true()
	var result: CTracker = player.get_component(CTracker)
	assert_float(result.track_range).is_equal(150.0)


func test_open_box_instance_mode_takes_precedence() -> void:
	## Box has both stored_components and stored_recipe_id.
	## Instance mode should be used (stored_components wins).
	var system := auto_free(SPickup.new())
	add_child(system)

	var player := _create_player()
	var tracker := CTracker.new()
	tracker.track_range = 77.0

	var box := Entity.new()
	box.name = "DualModeBox"
	box.add_component(CTransform.new())
	box.add_component(CSprite.new())
	var collision := CCollision.new()
	collision.collision_shape = CircleShape2D.new()
	box.add_component(collision)
	var container := CContainer.new()
	container.stored_components = [tracker]
	container.stored_recipe_id = "weapon_rifle"
	box.add_component(container)
	_world.add_entity(box)

	var pickup: CPickup = player.get_component(CPickup)
	system._open_box(player, box, pickup)

	# Instance mode was used: player got CTracker, NOT CWeapon from recipe
	assert_bool(player.has_component(CTracker)).is_true()
	assert_float(player.get_component(CTracker).track_range).is_equal(77.0)
```

- [ ] **Step 2: Run test to verify it fails** (instance-mode branch doesn't exist yet)

Run: `gol-unittest` skill targeting `res://tests/unit/system/test_pickup_instance.gd`

Expected: FAIL — SPickup._open_box hits `push_error` for empty stored_recipe_id on instance-mode boxes.

- [ ] **Step 3: Modify SPickup._open_box for instance mode**

In `scripts/systems/s_pickup.gd`, replace `_open_box` (lines 91-111) with:

```gdscript
func _open_box(entity, overlapped_entity, pickup: CPickup) -> void:
	var container: CContainer = overlapped_entity.get_component(CContainer)
	if not container:
		return

	print("[SPickup] LogPickup: Opening box for entity: ", entity.name, " with overlapped entity: ", overlapped_entity.name)

	if container.stored_components.size() > 0:
		# Instance mode: merge stored component instances directly
		for comp in container.stored_components:
			if entity.has_component(comp.get_script()):
				var existing = entity.get_component(comp.get_script())
				if existing.has_method("on_merge"):
					existing.on_merge(comp)
			else:
				entity.add_component(comp)
		ECS.world.remove_entity(overlapped_entity)
	elif not container.stored_recipe_id.is_empty():
		# Recipe mode: create entity from recipe and merge (existing behavior)
		var stored_entity: Entity = ServiceContext.recipe().create_entity_by_id(container.stored_recipe_id)
		if not stored_entity:
			push_error("SPickup: Failed to create stored entity from recipe")
			return
		# Preserve original order: remove box first, then merge
		ECS.world.remove_entity(overlapped_entity)
		ECS.world.merge_entity(stored_entity, entity)
	else:
		push_error("SPickup: Container has no stored_components and no stored_recipe_id")
		return

	pickup.focused_box.set_value(null)
```

- [ ] **Step 4: Run all tests to verify nothing is broken**

Run: `gol-unittest` skill (all tests)

Expected: All existing tests + new tests PASS. Existing recipe-mode boxes still work via the `elif` branch.

- [ ] **Step 5: Commit**

```bash
cd gol-project
git add scripts/systems/s_pickup.gd tests/unit/system/test_pickup_instance.gd
git commit -m "feat(pickup): support instance-mode CContainer merge

SPickup._open_box now checks stored_components first (instance mode),
falling back to stored_recipe_id (recipe mode). Instance mode merges
component instances directly using on_merge when available."
```

---

### Task 4: Integration test — full drop-and-pickup flow

**Files:**
- Create: `tests/integration/flow/test_flow_component_drop.gd`

- [ ] **Step 1: Write integration test**

Create `tests/integration/flow/test_flow_component_drop.gd`:

```gdscript
extends GdUnitTestSuite
## Integration test: enemy takes lethal damage → component drops as Box → player picks up.

var _world: World = null


func before() -> void:
	GOL.setup()


func after() -> void:
	if _world != null:
		_world.free()
		_world = null
	ECS.world = null
	GOL.teardown()


func _create_world() -> World:
	var world := World.new()
	add_child(world)
	_world = world
	ECS.world = world
	return world


func _create_enemy(world: World, weapon_range: float = 42.0) -> Entity:
	var enemy := Entity.new()
	enemy.name = "enemy_basic@99999"
	var hp := CHP.new()
	hp.max_hp = 10.0
	hp.hp = 10.0
	enemy.add_component(hp)
	var transform := CTransform.new()
	transform.position = Vector2(100, 100)
	enemy.add_component(transform)
	var weapon := CWeapon.new()
	weapon.attack_range = weapon_range
	weapon.bullet_recipe_id = "bullet_normal"
	enemy.add_component(weapon)
	var camp := CCamp.new()
	camp.camp = CCamp.CampType.ENEMY
	enemy.add_component(camp)
	var movement := CMovement.new()
	enemy.add_component(movement)
	world.add_entity(enemy)
	return enemy


func _find_box_in_world(world: World) -> Entity:
	for child in world.get_children():
		if child is Entity and child.has_component(CContainer):
			var container: CContainer = child.get_component(CContainer)
			if container.stored_components.size() > 0:
				return child
	return null


func test_enemy_death_drops_weapon_box() -> void:
	## Full flow: enemy with CWeapon takes lethal damage, loses CWeapon,
	## a Box entity appears with the weapon inside + CLifeTime.
	var world := _create_world()
	var damage_system := SDamage.new()
	world.add_child(damage_system)

	var enemy := _create_enemy(world, 42.0)

	# Deal lethal damage
	var damage := CDamage.new()
	damage.amount = 999.0
	damage.knockback_direction = Vector2.RIGHT
	enemy.add_component(damage)
	damage_system._process_entity(enemy, 0.016)

	# Enemy should have lost CWeapon
	assert_bool(enemy.has_component(CWeapon)).is_false()

	# Box should exist with correct weapon data
	var box := _find_box_in_world(world)
	assert_object(box).is_not_null()
	var container: CContainer = box.get_component(CContainer)
	var stored_weapon: CWeapon = container.stored_components[0] as CWeapon
	assert_float(stored_weapon.attack_range).is_equal(42.0)
	assert_str(stored_weapon.bullet_recipe_id).is_equal("bullet_normal")

	# Box should have CLifeTime for auto-despawn
	assert_bool(box.has_component(CLifeTime)).is_true()
	var lt: CLifeTime = box.get_component(CLifeTime)
	assert_float(lt.lifetime).is_equal(120.0)


func test_e2e_kill_enemy_pickup_component() -> void:
	## E2E: kill enemy → Box spawns → player picks up → component acquired.
	var world := _create_world()
	var damage_system := SDamage.new()
	world.add_child(damage_system)
	var pickup_system := SPickup.new()
	world.add_child(pickup_system)

	# Create enemy and deal lethal damage
	var enemy := _create_enemy(world, 55.0)
	var damage := CDamage.new()
	damage.amount = 999.0
	damage.knockback_direction = Vector2.RIGHT
	enemy.add_component(damage)
	damage_system._process_entity(enemy, 0.016)

	# Find the dropped box
	var box := _find_box_in_world(world)
	assert_object(box).is_not_null()

	# Create player at box position
	var player := Entity.new()
	player.name = "player@00001"
	var player_transform := CTransform.new()
	var box_transform: CTransform = box.get_component(CTransform)
	player_transform.position = box_transform.position
	player.add_component(player_transform)
	player.add_component(CPickup.new())
	world.add_entity(player)

	assert_bool(player.has_component(CWeapon)).is_false()

	# Open the box via SPickup
	var pickup: CPickup = player.get_component(CPickup)
	pickup_system._open_box(player, box, pickup)

	# Player should now have CWeapon with the enemy's original stats
	assert_bool(player.has_component(CWeapon)).is_true()
	var result: CWeapon = player.get_component(CWeapon)
	assert_float(result.attack_range).is_equal(55.0)
```

- [ ] **Step 2: Run integration test**

Run: `gol-unittest` skill targeting `res://tests/integration/flow/test_flow_component_drop.gd`

Expected: PASS — Both tests pass: Box creation with CLifeTime, and full E2E kill→pickup flow.

- [ ] **Step 3: Commit**

```bash
cd gol-project
git add tests/integration/flow/test_flow_component_drop.gd
git commit -m "test: add integration tests for component drop + pickup flow

Verifies full path: enemy takes lethal damage → CWeapon stripped →
Box entity spawned with weapon data + CLifeTime → player picks up →
CWeapon merged into player."
```

---

### Task 5: Run full test suite and verify

- [ ] **Step 1: Run full test suite**

Run: `gol-unittest` skill (all tests)

Expected: All tests PASS, including existing tests (recipe-mode boxes, spawner loot, etc.).

- [ ] **Step 2: Verify no regressions in existing loot boxes**

Check that `_spawner_drop_loot` still works — it uses `stored_recipe_id` which hits the `elif` branch in the updated `_open_box`. No changes needed.

- [ ] **Step 3: Final commit if any fixes needed**

Only if test failures require fixes.

---

### Task 6: Push submodule and create PR

- [ ] **Step 1: Push gol-project submodule**

```bash
cd gol-project
git push origin HEAD
```

- [ ] **Step 2: Update main repo submodule reference**

```bash
cd ..
git add gol-project
git commit -m "chore: update gol-project submodule (reverse composition)"
git push
```

- [ ] **Step 3: Create PR**

```bash
cd gol-project
gh pr create --title "feat: reverse composition — component drop on death" --body "$(cat <<'EOF'
## Summary
- Stripped components now drop as pickable Box entities when enemies take lethal damage
- CContainer extended with `stored_components` for instance-mode storage
- SPickup supports both instance-mode and recipe-mode containers
- Full test coverage: unit + integration

## Changes
- `c_container.gd`: Add `stored_components: Array[Component]` field
- `s_damage.gd`: Add `_drop_component_box()`, call in `_on_no_hp()` after component strip
- `s_pickup.gd`: Instance-mode branch in `_open_box()` with on_merge support

Closes #106, Closes #171

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
