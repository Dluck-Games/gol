# Reverse Composition (Component Drop on Death)

> Closes #106, #171

## Problem

When entities take lethal damage, stripped components are discarded. Players have no way to recover components from defeated enemies. The combat loop lacks reward feedback.

## Solution

Stripped components drop as pickable Box entities instead of being discarded. This reuses the existing `CContainer` + `SPickup` pipeline with a new "instance mode" that stores actual component data rather than recipe IDs.

## Data Flow

```
Lethal damage → SDamage._on_no_hp()
  │
  ├── Has LOSABLE_COMPONENT?
  │     1. _get_random_component() → select component instance (e.g. CWeapon)
  │     2. entity.remove_component(comp_script)         [existing]
  │     3. _drop_component_box(comp, position)           [new]
  │           ├── Create Box Entity
  │           ├── CContainer.stored_components = [comp]
  │           ├── CTransform (death position + random offset)
  │           ├── CSprite (box texture)
  │           ├── CCollision (pickup collision)
  │           └── CLifeTime (120s auto-despawn)
  │
  └── No LOSABLE_COMPONENT → normal death flow (unchanged)

Player walks over Box → SPickup._open_box()
  │
  ├── stored_components not empty? (instance mode)
  │     └── For each component: on_merge() if exists, else add_component()
  │
  └── stored_recipe_id set? (recipe mode, unchanged)
        └── create_entity_by_id() → merge_entity()
```

## Changes

### 1. CContainer — add instance storage

File: `scripts/components/c_container.gd`

Add one field:

```gdscript
var stored_components: Array[Component] = []
```

Not `@export` — populated at runtime only. Two modes are mutually exclusive: `stored_components` takes precedence over `stored_recipe_id`.

### 2. SDamage — drop component as Box

File: `scripts/systems/s_damage.gd`

Add `_drop_component_box(component, position)` method that creates a Box entity following the existing `_spawner_drop_loot()` pattern:

- Same box texture (`res://assets/sprite_sheets/boxes/box_re_texture.png`)
- Same collision shape (CircleShape2D, radius 16)
- Same lifetime (120s via CLifeTime)
- `CContainer.stored_components = [component]` instead of `stored_recipe_id`
- Random position offset (±16px) to prevent stacking

Modify `_on_no_hp()`: after `remove_component()`, call `_drop_component_box()` with the stripped component and entity position.

**Component instance lifetime:** `_get_random_component()` returns a component instance reference. After `remove_component()`, GECS erases it from the entity's dictionary but does not free the Resource — GDScript reference counting keeps it alive as long as `stored_components` holds a reference. The call order (remove → drop) is safe.

**HP after stripping:** The existing behavior is intentional — HP stays at 0 after component stripping, with `invincible_time` (0.3s) preventing immediate re-triggering. Each subsequent lethal hit strips another component. This progressive decomposition IS the reverse composition mechanic.

### 3. SPickup — handle instance mode

File: `scripts/systems/s_pickup.gd`

Modify `_open_box()`: add instance-mode branch **before** the existing `stored_recipe_id.is_empty()` error guard. The existing `push_error` for empty `stored_recipe_id` must move into an else-branch that only fires when **both** `stored_components` is empty **and** `stored_recipe_id` is empty.

Instance-mode logic:

- For each stored component, check if the player entity already has that component type
- If yes and `on_merge()` exists: call `on_merge()` (e.g. CWeapon replaces weapon params)
- If no: `add_component()` directly
- Skip the recipe-based `create_entity_by_id()` path

Direct component-level merging is used instead of creating a temporary Entity and calling `merge_entity()`, to avoid unnecessary entity allocation and world registration for a simple component transfer.

**Note:** CHealer and CTracker currently lack `on_merge()`. Picking up a duplicate when the player already has one is a no-op (existing component kept). This is intentional for the initial implementation.

## What Does NOT Change

- SDead death flow — untouched
- `_get_random_component()` selection logic — untouched
- Existing recipe-based CContainer boxes — untouched
- No new Resource types, Services, or Systems

## Tests

| Level | Test | File |
|-------|------|------|
| Unit | CContainer.stored_components data integrity | `tests/unit/test_container_component.gd` |
| System | _on_no_hp() creates Box with stripped component | `tests/system/test_component_drop.gd` |
| System | _open_box() instance mode merges component to player | `tests/system/test_pickup_instance.gd` |

Core assertions:

1. Enemy with CWeapon takes lethal damage → Box appears in world with CWeapon inside
2. CWeapon in Box retains original properties (bullet_recipe_id, attack_range, etc.)
3. Player picks up Box → CWeapon merges via on_merge()
4. Enemy with no LOSABLE_COMPONENT dies → no Box generated
5. Box auto-despawns after 120s (CLifeTime)
6. CTracker drop + pickup works (add_component path, no on_merge)
7. Player already has CWeapon, picks up CWeapon Box → on_merge replaces params
8. stored_components takes precedence over stored_recipe_id when both set
9. E2E: kill enemy → Box spawns → player picks up → component acquired

## PR #118 Disposition

Close without merging. The DecompositionRecipe / Service_Decomposition / SDecomposition architecture implements a static loot table, not reverse composition. If a base drop pool is needed later, implement via CLootDrop component separately.

## Future Extension (Out of Scope)

Adding a base drop pool (ammo, materials) via CLootDrop component alongside reverse-extracted components. Migration path: stored_components can coexist with a future CLootDrop-driven drop system since they operate at different trigger points (component stripping vs death).
