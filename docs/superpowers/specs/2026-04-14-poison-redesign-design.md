# Poison Redesign — Two-Layer Design with Dedicated `SPoison` System

**Date:** 2026-04-14
**Status:** Design approved, ready for implementation planning
**Scope:** `gol-project` submodule — components, systems, utils, UI view

---

## 1. Problem Statement

The current poison system is architecturally broken:

- `CPoison` has no standalone behavior. It only activates when combined with `CAreaEffect + CTransform`, and even then it's handled inside `SAreaEffectModifier` as a per-frame piercing-damage writer — there is no persistent "poisoned" state on the target.
- This conflation causes two legacy bugs:
  1. **Poison sources don't spawn drop boxes on the map.** There's no acquisition path for the player.
  2. **Poison has no visible feedback.** Players can't tell when or why an enemy is taking damage.
- A prior PR attempted to patch both bugs in place, but instead exposed that the whole component architecture is wrong: `CPoison` is trying to be both an inventory-style source component and a damage emitter, with neither role fully coherent.

**Desired outcome:** a poison system with two distinct delivery modes, both producing the same persistent effect-layer identity on the target, so that drops, UI, VFX, and damage ticking all follow one consistent code path.

---

## 2. Design Goals and Non-Goals

### Goals
- **Two delivery modes, one effect layer.** On-hit poison (triggered by weapon attacks) and AoE poison (radius cloud) converge on a single target-side state.
- **Reuse the existing `CElementalAffliction` container.** Poison becomes a new entry type inside the same dict that already holds fire/wet/cold/electric. No third ad-hoc status system.
- **Concentrate poison-specific logic in a new `SPoison` system.** Remove poison branches from `SAreaEffectModifier` and `SElementalAffliction` so each system has one responsibility.
- **Preserve `CPoison` as a losable, droppable component.** The drop pipeline in `SDamage._on_no_hp` already handles this shape — bug #1 collapses for free.
- **Use the existing UI binding path.** `ViewModel_HPBar` already iterates `CElementalAffliction.entries` and renders an icon per entry type; adding a POISON entry lights up the existing wire automatically, fixing bug #2.
- **Per-source tuning.** `CPoison` carries its own instance data (not a global constant), so different poison sources (basic, legendary, boss-specific) can ship different stats without code changes.
- **Keep-best merging.** When multiple poison sources affect one target, the better value wins per field — player investment in stronger poison isn't erased by a weaker drop-by source.

### Non-Goals
- **Do not rename `CElementalAffliction` → `CStatusEffects` in this PR.** The rename is correct but deferred; the right time is when a third non-elemental, non-poison status appears and the right name becomes obvious. Noted as tech debt.
- **Do not extract a generic buff/debuff framework.** At N=2 status categories, abstraction is premature. Rule of three — wait for the third real case.
- **No new counter-element rules.** Poison does not interact with fire/wet/cold/electric. Each stays in its own lane.
- **No propagation, no movement modifiers, no freeze-style lockouts for poison.** Those are elemental-specific mechanics.
- **No balance tuning pass.** Starting values are reasonable placeholders; balance is a separate follow-up.

---

## 3. Two-Layer Architecture

```
┌─────────────────────────────────────────────────────────┐
│ EFFECT LAYER (shared — lives on the target)             │
│                                                         │
│   CElementalAffliction.entries[POISON] = {              │
│       stacks, max_stacks,                               │
│       decay_timer, decay_interval,                      │
│       tick_timer, tick_interval,                        │
│       damage_coeff_a, damage_coeff_b,                   │
│       accumulation_progress,                            │
│       source_entity                                     │
│   }                                                     │
│                                                         │
│   Owned by: SPoison (Pass B)                            │
│   Produces: CDamage.piercing_amount                     │
└────────────────▲────────────────────────────────────────┘
                 │  both deliveries route through
                 │  POISON_UTILS.apply_stack(target, count, source)
      ┌──────────┴──────────┐
      │                     │
┌─────┴──────────┐  ┌───────┴─────────────┐
│ AoE DELIVERY   │  │ ON-HIT DELIVERY     │
│                │  │                     │
│ source has:    │  │ source has:         │
│  CPoison +     │  │  CPoison            │
│  CAreaEffect   │  │  (no CAreaEffect    │
│  (apply_poison)│  │   with apply_poison)│
│                │  │                     │
│ Owner:         │  │ Hook points:        │
│  SPoison       │  │  SMeleeAttack       │
│  (Pass A)      │  │  ._apply_on_hit_    │
│                │  │     element()       │
│                │  │  SDamage            │
│                │  │  ._apply_bullet_    │
│                │  │     effects()       │
└────────────────┘  └─────────────────────┘
```

**Mode selection is encoded by component shape, not by a flag.** A source with `CPoison + CAreaEffect(apply_poison=true)` is an AoE emitter. A source with `CPoison` alone is an on-hit applier. Picking up a `CAreaEffect` materia automatically transforms a single-target poisoner into a cloud emitter — no migration logic, no state to clear.

The two modes are **mutually exclusive per source**. If an attacker has both `CPoison` and `CAreaEffect(apply_poison=true)`, the on-hit path is suppressed to prevent double application. This keeps the build decision discrete (emitter vs. applier) rather than creating hidden "best of both" builds.

---

## 4. Component Changes

### 4.1 `CPoison` — instance data with inline defaults

```gdscript
class_name CPoison extends Component

## Poison source. Presence on an attacker enables on-hit poison delivery.
## Combined with CAreaEffect(apply_poison=true), enables AoE delivery instead.
## Losable — drops as a component box on lethal damage via existing SDamage path.

@export var damage_coeff_a: float     = 1.5   # dps = a * stacks + b
@export var damage_coeff_b: float     = 0.5
@export var max_stacks: int           = 10
@export var aoe_stack_interval: float = 5.0   # seconds in-range per +1 stack
@export var decay_interval: float     = 3.0   # seconds per -1 stack while idle
@export var tick_interval: float      = 0.5   # damage emission cadence

func on_merge(other: CPoison) -> void:
    damage_coeff_a     = maxf(damage_coeff_a, other.damage_coeff_a)
    damage_coeff_b     = maxf(damage_coeff_b, other.damage_coeff_b)
    max_stacks         = maxi(max_stacks, other.max_stacks)
    aoe_stack_interval = minf(aoe_stack_interval, other.aoe_stack_interval)
    decay_interval     = maxf(decay_interval, other.decay_interval)
    tick_interval      = minf(tick_interval, other.tick_interval)
```

- Defaults live in the component source — no separate `Config` resource.
- `on_merge` uses keep-best semantics, matching `CMelee.on_merge`. Lower `aoe_stack_interval` and `tick_interval` are "better" (faster / smoother); higher for everything else.
- Component stays losable via `ECSUtils.is_losable_component` (no change to existing classification).

### 4.2 `CAreaEffect` — transient per-emitter state

```gdscript
# New field, non-exported, not serialized.
var poison_exposure_timers: Dictionary = {}
# Maps target Entity → seconds of continuous exposure.
# Reset to 0 on cross-frame eviction when a target leaves the radius.

func on_merge(other: CAreaEffect) -> void:
    # ... existing field copies ...
    poison_exposure_timers.clear()  # avoid dangling refs from the previous instance
```

- `apply_poison`, `radius`, `power_ratio`, and the faction flags retain their current meaning.
- `poison_exposure_timers` is pure runtime state read and written exclusively by `SPoison`.

### 4.3 `CElementalAffliction` — one new element type, no schema restructuring

- `ElementType.POISON = 4` added to the `CElementalAttack.ElementType` enum (the existing source-of-truth for element identifiers).
- Poison entries in `CElementalAffliction.entries` use a **different key-set** from elemental entries. This is allowed — the dict is untyped, and the tick handler branches by `element_type`.
- Poison entry schema:

```
{
    "element_type": POISON,
    "stacks": int,                  # 1..max_stacks
    "max_stacks": int,              # baked from source at apply time, keep-best merged thereafter
    "decay_timer": float,           # reset to 0 on every +stack event
    "decay_interval": float,        # baked, keep-best merged
    "tick_timer": float,            # counts up to tick_interval, emits damage, carries remainder
    "tick_interval": float,         # baked, keep-best merged
    "damage_coeff_a": float,        # baked, keep-best merged
    "damage_coeff_b": float,        # baked, keep-best merged
    "accumulation_progress": float, # UI mirror scalar, written by SPoison Pass A
    "source_entity": Entity         # informational — most recent source
}
```

- Poison entries **do not use** the elemental fields: `intensity`, `remaining_duration`, `decay_per_second`, `stack_mode`, `propagation_*`, `max_intensity`, `affects_same_camp`, `affects_other_camps`.

### 4.4 Naming debt — explicitly deferred

`CElementalAffliction` is now misnamed: it holds poison, which isn't elemental. The correct name is `CStatusEffects` or similar. **This rename is deliberately deferred** to a later PR — ideally when a third non-elemental, non-poison status is added, at which point the right name is self-evident and the refactor pays for its blast radius. Tracked as tech debt; not part of this work.

---

## 5. System Changes

### 5.1 New: `SPoison` — owns all poison-specific logic

`SPoison` concentrates every poison-related code path into one place, running in `group = "gameplay"`. It has two internal passes per frame, executed in strict order.

**Pass A — AoE Emission**

```
query: q.with_all([CPoison, CAreaEffect, CTransform])

for each emitter:
    area_effect = emitter.get_component(CAreaEffect)
    if not area_effect.apply_poison:
        continue   # this emitter's AoE channel is configured for melee/heal only

    emitter_camp = emitter's CCamp.camp (or PLAYER if missing)
    in_range_targets = AreaEffectUtils.find_targets_in_range(
        emitter, area_effect, emitter_camp
    )
    in_range_set = set of in_range_targets

    # Eviction: "target left range → timer resets"
    for target in area_effect.poison_exposure_timers.keys().duplicate():
        if target not in in_range_set or not is_instance_valid(target):
            area_effect.poison_exposure_timers.erase(target)
            _clear_accumulation_progress(target)  # zero the UI mirror

    src_poison = emitter.get_component(CPoison)

    for target in in_range_targets:
        stacks = _get_poison_stacks(target)

        if stacks == 0:
            # Edge trigger: first contact gives 1 stack immediately
            POISON_UTILS.apply_stack(target, 1, emitter)
            area_effect.poison_exposure_timers[target] = 0.0
            _write_accumulation_progress(target, 0.0)
        else:
            elapsed = float(area_effect.poison_exposure_timers.get(target, 0.0)) + delta
            if elapsed >= src_poison.aoe_stack_interval:
                POISON_UTILS.apply_stack(target, 1, emitter)
                elapsed -= src_poison.aoe_stack_interval
            area_effect.poison_exposure_timers[target] = elapsed
            _write_accumulation_progress(
                target, elapsed / src_poison.aoe_stack_interval
            )
```

**Pass B — Affliction Tick**

```
query: q.with_all([CElementalAffliction])

for each afflicted entity:
    if entity.has_component(CDead):
        continue
    affliction = entity.get_component(CElementalAffliction)
    entry = affliction.entries.get(POISON, null)
    if entry == null:
        continue

    # Decay — advances only when no source reset decay_timer this frame
    entry["decay_timer"] = float(entry["decay_timer"]) + delta
    while entry["decay_timer"] >= float(entry["decay_interval"]):
        entry["decay_timer"] -= float(entry["decay_interval"])
        entry["stacks"] = int(entry["stacks"]) - 1
        if int(entry["stacks"]) <= 0:
            affliction.entries.erase(POISON)
            affliction.notify_entries_changed()
            break

    # Damage tick
    if POISON still in affliction.entries:
        entry["tick_timer"] = float(entry["tick_timer"]) + delta
        while float(entry["tick_timer"]) >= float(entry["tick_interval"]):
            entry["tick_timer"] -= float(entry["tick_interval"])
            var dps = float(entry["damage_coeff_a"]) * int(entry["stacks"]) \
                    + float(entry["damage_coeff_b"])
            _queue_damage(entity, dps * float(entry["tick_interval"]))
        affliction.entries[POISON] = entry
```

**Ordering invariant:** Pass A runs before Pass B in the same frame. Any `POISON_UTILS.apply_stack` call during emission resets `decay_timer = 0` *before* Pass B advances it, so a target continuously in range never decays. This is enforced by calling the passes sequentially inside the same `SPoison._process_entity` body (or, if GECS forces a split into two systems, by system priority within the `gameplay` group).

**`_queue_damage` helper** is the same shape as `SElementalAffliction._queue_damage`: `entry.piercing_amount += amount`, creating `CDamage` if absent.

### 5.2 `POISON_UTILS.apply_stack` — the single chokepoint

All `+stack` events — AoE emission, on-hit attacks, future sources — route through this one function. It enforces every invariant in one place: ensure `CElementalAffliction` exists, create or merge the POISON entry, enforce `max_stacks` cap, reset `decay_timer`, emit the `entries_changed` signal.

```gdscript
static func apply_stack(target: Entity, count: int, source: Entity) -> void:
    if target == null or not is_instance_valid(target):
        return
    if target.has_component(CDead) or not target.has_component(CHP):
        return
    var src: CPoison = source.get_component(CPoison)
    if src == null:
        return

    var affliction: CElementalAffliction = _ensure_affliction(target)
    var entry: Dictionary = affliction.entries.get(
        CElementalAttack.ElementType.POISON, {}
    )

    if entry.is_empty():
        entry = {
            "element_type": CElementalAttack.ElementType.POISON,
            "stacks": 0,
            "max_stacks": src.max_stacks,
            "decay_timer": 0.0,
            "decay_interval": src.decay_interval,
            "tick_timer": 0.0,
            "tick_interval": src.tick_interval,
            "damage_coeff_a": src.damage_coeff_a,
            "damage_coeff_b": src.damage_coeff_b,
            "accumulation_progress": 0.0,
            "source_entity": source,
        }
    else:
        # Keep-best merge — each field picks the better value.
        entry["max_stacks"]     = maxi(int(entry["max_stacks"]), src.max_stacks)
        entry["decay_interval"] = maxf(float(entry["decay_interval"]), src.decay_interval)
        entry["tick_interval"]  = minf(float(entry["tick_interval"]), src.tick_interval)
        entry["damage_coeff_a"] = maxf(float(entry["damage_coeff_a"]), src.damage_coeff_a)
        entry["damage_coeff_b"] = maxf(float(entry["damage_coeff_b"]), src.damage_coeff_b)
        entry["source_entity"]  = source

    entry["stacks"] = mini(
        int(entry["stacks"]) + count,
        int(entry["max_stacks"])
    )
    entry["decay_timer"] = 0.0   # any add resets decay

    affliction.entries[CElementalAttack.ElementType.POISON] = entry
    affliction.notify_entries_changed()
```

**Current `stacks` is never decremented by a weaker source.** If a target is at 12 stacks from a legendary source (`max_stacks = 15`) and a basic source (`max_stacks = 10`) applies, the merged ceiling stays at 15 and current stacks stay at 12. Only the ceiling can grow via merge.

### 5.3 `POISON_UTILS.apply_on_hit` — on-hit delivery helper

Called from both on-hit hooks:

```gdscript
static func apply_on_hit(attacker: Entity, target: Entity) -> void:
    if attacker == null or not is_instance_valid(attacker):
        return
    if not attacker.has_component(CPoison):
        return
    # Mode mutex: if the attacker is an AoE poison emitter, AoE path owns delivery
    var area_effect: CAreaEffect = attacker.get_component(CAreaEffect)
    if area_effect != null and area_effect.apply_poison:
        return
    apply_stack(target, 1, attacker)
```

### 5.4 `SElementalAffliction` — defensive guard only

One line added at the top of the per-entry loop in `_process_entity`:

```gdscript
for element_type_variant in affliction.entries.keys().duplicate():
    var element_type := int(element_type_variant)
    if element_type == CElementalAttack.ElementType.POISON:
        continue  # SPoison owns poison entries
    var entry: Dictionary = affliction.entries.get(element_type, {})
    # ... existing elemental handling unchanged ...
```

**This guard is load-bearing.** Without it, the existing `entry["remaining_duration"] = ... - delta` line would zero out poison entries' `remaining_duration` field (defaulted from nothing) and `_should_remove_entry` would erase them on frame 1.

**Natural cleanup still works.** After `SPoison` erases a POISON entry, if the entries dict is now empty, the existing `if affliction.entries.is_empty(): _clear_afflictions(...)` block at the end of `SElementalAffliction._process_entity` removes the component on the next frame. No special handling in `SPoison`.

### 5.5 `SAreaEffectModifier` — poison channel removed

The following code is deleted:
- `const _CPoison := preload(...)` at the top of the file
- `_apply_poison_damage(source, target, area_effect, delta)` function
- `_should_apply_poison(area_effect)` function
- The `if _should_apply_poison(...) and source.has_component(_CPoison)` branch inside `_apply_effects`
- The `apply_poison` term in `_has_channel_overrides`

The `apply_poison` flag on `CAreaEffect` stays (it's still data). It is now read exclusively by `SPoison.Pass A`. `SAreaEffectModifier` becomes shorter and only handles CMelee and CHealer channels — one less responsibility per system.

### 5.6 New: `AreaEffectUtils.find_targets_in_range`

Extracted from `SAreaEffectModifier._process_entity` / `_is_in_radius` / `_should_affect_target` / `_get_potential_targets` into a pure static helper:

```gdscript
class_name AreaEffectUtils

static func find_targets_in_range(
    emitter: Entity,
    area_effect: CAreaEffect,
    emitter_camp: int
) -> Array[Entity]:
    # ... factored-out target scan, radius check, camp filtering ...
```

Called by both `SAreaEffectModifier` (for CMelee / CHealer channels) and `SPoison.Pass A` (for poison emission). No behavioral change — just factoring. Prevents the two systems from drifting apart on camp-filtering semantics.

### 5.7 On-hit hook integration

**`SMeleeAttack._apply_on_hit_element`** (currently calls `ELEMENTAL_UTILS.apply_attack`) gains one line:

```gdscript
func _apply_on_hit_element(attacker: Entity, target: Entity) -> void:
    ELEMENTAL_UTILS.apply_attack(attacker, target)
    POISON_UTILS.apply_on_hit(attacker, target)
```

**`SDamage._apply_bullet_effects`** (currently calls `ELEMENTAL_UTILS.apply_attack(bullet.owner_entity, target_entity)`) gains one line:

```gdscript
func _apply_bullet_effects(bullet_entity: Entity, target_entity: Entity) -> void:
    var bullet: CBullet = bullet_entity.get_component(CBullet)
    if not bullet or not bullet.owner_entity or not is_instance_valid(bullet.owner_entity):
        return
    if bullet.owner_entity.has_component(COMPONENT_ELEMENTAL_ATTACK):
        ELEMENTAL_UTILS.apply_attack(bullet.owner_entity, target_entity)
    POISON_UTILS.apply_on_hit(bullet.owner_entity, target_entity)
```

The bullet's **owner** is the poison source (same pattern as `CElementalAttack`). The bullet entity itself does not carry poison — if the shooter has `CPoison`, every bullet they fire applies poison on hit.

---

## 6. UI Integration

### 6.1 Wiring — already in place

`ViewModel_HPBar._bind_elemental_entries` already binds to `CElementalAffliction.entries` via the `entries_changed` signal. `view_hp_bar.gd` already iterates `elemental_entries` and creates an icon per element type. Adding `ElementType.POISON` to the icon factory's match statement surfaces poison automatically — no new ViewModel wiring, no new signals.

### 6.2 Poison icon — shader-based, minimal

New asset: `resources/poison_icon.gdshader`

```glsl
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 base_color : source_color    = vec4(0.35, 0.80, 0.30, 1.0);  // poison green
uniform vec4 overlay_color : source_color = vec4(0.00, 0.00, 0.00, 0.55); // semi-transparent dim
uniform vec4 edge_color : source_color    = vec4(1.00, 1.00, 1.00, 1.0);  // progress line
uniform float edge_thickness : hint_range(0.0, 0.1) = 0.025;

void fragment() {
    vec4 col = base_color;
    // Overlay covers UV.y ∈ (progress, 1] — icon revealed from the top as progress grows.
    if (UV.y > progress) {
        col = mix(col, overlay_color, overlay_color.a);
    }
    // Thin horizontal edge line at UV.y == progress.
    float edge_dist = abs(UV.y - progress);
    if (edge_dist < edge_thickness && progress > 0.0 && progress < 1.0) {
        col = mix(col, edge_color, edge_color.a);
    }
    COLOR = col;
}
```

Scene: `scenes/ui/poison_status_icon.tscn`

```
PoisonStatusIcon (Control, 32×32)
├── icon (ColorRect)         anchors=full, material=poison_icon_material
└── stack_label (Label)      anchor_right=1, anchor_bottom=1,
                             offset_left=-12, offset_top=-12,
                             text=str(entry.stacks)
```

The view updates `progress` and `stack_label.text` each frame (or each `entries_changed` event) from the bound `elemental_entries[target][POISON]`:

```gdscript
var entry: Dictionary = elemental_entries.get(POISON, {})
if entry.is_empty():
    # poison gone — remove the icon
    return
var accumulation: float = float(entry.get("accumulation_progress", 0.0))
var decay_frac: float = float(entry.get("decay_timer", 0.0)) \
                      / float(entry.get("decay_interval", 1.0))
var progress: float = maxf(accumulation, 1.0 - decay_frac)
material.set_shader_parameter("progress", progress)
stack_label.text = str(int(entry.get("stacks", 0)))
```

**Semantics of the animation:**
- **While AoE is actively adding** (`accumulation_progress` grows each frame): progress rises smoothly from 0 → 1, snapping back to 0 when a stack is granted. Represents "5s accumulation timer."
- **While no source is active** (`decay_timer` grows, `accumulation_progress` frozen or zeroed on eviction): `1 - decay_timer/decay_interval` dominates and shrinks smoothly from 1 → 0 over 3s, representing "time until next stack decays."
- The `max()` lets the two phases hand off cleanly — accumulation always wins while a source is contributing (because `decay_timer` is reset each frame), and decay takes over the moment contribution stops.

### 6.3 `view_hp_bar.gd` icon factory extension

The existing factory (currently matches on `ElementType.FIRE / WET / COLD / ELECTRIC` and returns a generic tinted sprite) gains a `POISON` case that instantiates `PoisonStatusIcon.tscn` instead. This is the only view-side code change.

---

## 7. Data Flow Summary

```
ON-HIT PATH                              AOE PATH
─────────                                ────────
attacker attacks                         SPoison.Pass A tick
    │                                        │
SMeleeAttack / SDamage bullet                for each emitter with CPoison+CAreaEffect:
    │                                        │
_apply_on_hit_element() /                    find in-range targets via
_apply_bullet_effects()                      AreaEffectUtils.find_targets_in_range()
    │                                        │
POISON_UTILS.apply_on_hit()                  evict absent targets from
    │ (guard: not an AoE emitter)            poison_exposure_timers
    │                                        │
    │                                        for each in-range target:
    │                                            if stacks == 0: apply 1 immediately
    │                                            else: accumulate delta; if ≥ 5s, apply 1
    │                                            write accumulation_progress mirror
    │                                        │
POISON_UTILS.apply_stack(target, 1, src)  ◄──┘
    │ (ensure CElementalAffliction,
    │  get-or-create POISON entry,
    │  keep-best merge, stack cap,
    │  decay_timer = 0,
    │  entries_changed signal)
    ▼
CElementalAffliction.entries[POISON] on target
    │
SPoison.Pass B per-frame tick
    │
    ├─ decay_timer += delta
    │  while ≥ decay_interval: stacks -= 1, timer -= decay_interval
    │  if stacks == 0: erase entry, signal
    │
    └─ tick_timer += delta
       while ≥ tick_interval:
           dps = a * stacks + b
           CDamage.piercing_amount += dps * tick_interval
    │
SDamage applies → target HP, ViewModel_HPBar icon updates via entries_changed
```

---

## 8. Edge Cases

| Case | Handling |
|---|---|
| Target dies mid-tick | `SPoison.Pass B` checks `target.has_component(CDead)` at the top and skips. `SDamage` re-entry guard already prevents double-death handling. |
| Emitter dies with live exposure timers | `CAreaEffect` is freed with the emitter → `poison_exposure_timers` dict is GC'd → no orphan state. Target's poison entry is unaffected and decays normally. |
| Target leaves range, re-enters before decay finishes | Exposure timer was evicted on leave. Re-entry takes the `stacks > 0` branch → 5s wait before next `+1`. Matches spec's "leave resets timer." |
| Accumulation_progress stale after target leaves | On eviction, `SPoison` zeros `entry.accumulation_progress`. UI's `max(0.0, 1.0 - decay_timer/decay_interval)` takes over cleanly. |
| Multiple overlapping clouds writing `accumulation_progress` | `SPoison.Pass A` writes `maxf(existing, new_value)` rather than overwriting — the closest-to-next-tick cloud wins the visual. Acceptable minor visual inconsistency between emitters. |
| Attacker has `CPoison + CAreaEffect(apply_poison=true)` and also swings melee | On-hit guard in `POISON_UTILS.apply_on_hit` sees `apply_poison == true` and returns. AoE path alone applies stacks. No double-dip. |
| Enemy drops `CPoison` via lethal damage, continues to "emit" via old AoE | `SDamage._drop_component_box` removes `CPoison`. Next frame, `SPoison.Pass A`'s query excludes the emitter entirely. Existing poison entries on targets continue to tick and decay normally. |
| `CAreaEffect.on_merge` called while `poison_exposure_timers` has stale refs | `on_merge` clears the dict. Prevents dangling Entity references surviving the merge. |
| Player invincibility (`hp.invincible_time > 0` or console flag) | Poison damage is `piercing_amount`, bypasses `invincible_time` just like elemental DoT. Console `is_player_invincible()` still blocks all damage in `SDamage._take_damage`. No change from today. |
| Self-poison (`affects_self = true` on CAreaEffect) | `AreaEffectUtils.find_targets_in_range` respects `affects_self` (extracted from existing logic). `SPoison.Pass A` applies to the emitter itself if the flag is set. Symmetric with `SAreaEffectModifier`'s existing semantics. |
| Entity has `CElementalAffliction` with *only* a POISON entry | `SElementalAffliction` still runs but hits the POISON guard, falls through to the "is entries empty" check. Entries is NOT empty (POISON still there), so no cleanup. When poison decays out, `SPoison` erases the entry → next frame `SElementalAffliction` sees empty and cleans up. |
| `SPoison` Pass A / Pass B ordering drifts | Both passes are in the same system instance registered under `group = "gameplay"` and called sequentially inside `_process_entity`. If GECS later forces a split, enforce ordering via system priority. |
| Two different sources poison same target with different `max_stacks` | Keep-best merge: `max_stacks` rises to the higher of the two. Current `stacks` is never decremented — only the ceiling grows. |
| Enemy with `CPoison` meleeing player | Fully symmetric with player case. Existing camp filtering in `SMeleeAttack` and bullet hit-detection already excludes allies. |

---

## 9. Testing Strategy

Tests delegate via the v3 test harness: `gol-test-writer-unit` for unit tests, `gol-test-writer-integration` for integration tests, `gol-test-runner` for execution.

### Unit tests (`tests/unit/`)

- **`test_c_poison.gd`** — defaults match initializers; `on_merge` keep-best across all six fields; idempotent (`merge(a, a) == a`).
- **`test_poison_utils_apply_stack.gd`** — first-time application creates entry with baked source fields; repeated application merges keep-best per field; `stacks` cap respected; existing `stacks` never decremented by weaker source's `max_stacks`; `decay_timer` reset to 0 on every add; `entries_changed` signal fires.
- **`test_poison_utils_apply_on_hit.gd`** — AoE emitter guard (returns early when attacker has `CAreaEffect(apply_poison=true)`); dead / HP-less targets skipped; attacker without `CPoison` is a no-op.
- **`test_s_elemental_affliction_poison_guard.gd`** — running `SElementalAffliction` against an entity whose only affliction entry is POISON leaves the entry's `decay_timer`, `tick_timer`, and `stacks` untouched. **Regression guard**: without the skip, today's code would erase the entry on frame 1.
- **`test_poison_damage_formula.gd`** — pure math: `(a*x + b) * tick_interval` at various stack counts and tuning values.

### Integration tests (`tests/integration/`)

- **`test_poison_on_hit_melee.gd`** — player with `CPoison + CMelee` hits enemy → poison entry appears, `stacks == 1`, damage ticks after `tick_interval` seconds, decays after `decay_interval` of idle.
- **`test_poison_on_hit_bullet.gd`** — same, via a bullet with a `CPoison`-carrying owner.
- **`test_poison_aoe_edge_trigger.gd`** — enemy walks into a `CPoison + CAreaEffect(apply_poison=true)` emitter's radius → gets 1 stack immediately (stacks=0 branch).
- **`test_poison_aoe_interval_accumulation.gd`** — enemy stays in range → stacks increment on a 5s cadence (using test-harness time advancement).
- **`test_poison_aoe_leave_reset.gd`** — enemy in range at t=4s, leaves at t=4.5s, re-enters at t=6s → no `+1` at t=6s; next `+1` at t=11s.
- **`test_poison_aoe_decay_pause.gd`** — enemy continuously in range → decay_timer never elapses; enemy leaves and stays out → decays 1 stack per 3s.
- **`test_poison_aoe_overlap.gd`** — two overlapping clouds → 2 stacks per 5s (each contributes independently).
- **`test_poison_drop_on_lethal.gd`** — enemy dies from poison tick → drops `CPoison` as a component box. **Bug #1 regression test** — fails on current `main`, passes after this refactor.
- **`test_poison_aoe_mutex_onhit.gd`** — attacker with both `CPoison + CAreaEffect(apply_poison=true)` swings melee → target's poison stack count reflects AoE path only, not double.
- **`test_poison_keep_best_merge.gd`** — two emitters with different tuning apply to same target → entry reflects keep-best per field; stacks grow toward the merged (higher) ceiling.
- **`test_poison_icon_visible.gd`** — target gains a stack → `CElementalAffliction.entries_changed` fires → `ViewModel_HPBar.elemental_entries[target]` contains a POISON key. **Bug #2 regression test** — verifies UI wire-up without needing a headless renderer.

**Out of scope for automated coverage:** visual verification of the shader overlay animation. Flagged as manual QA during the UI implementation step.

---

## 10. Migration Order

Designed so each step is individually testable and the game is never in a long-lived broken state. Steps 1–4 can land as a prep PR without changing player-visible behavior. Steps 5–11 form the "activation" PR where the new behavior ships.

1. Add `ElementType.POISON = 4` to `CElementalAttack`. No behavioral change.
2. Extract `AreaEffectUtils.find_targets_in_range` from `SAreaEffectModifier`. Pure refactor — update `SAreaEffectModifier` to call the helper. Existing AoE tests pass.
3. Rewrite `CPoison` with instance fields + keep-best `on_merge`. Add the POISON guard to `SElementalAffliction` (one-line skip). No new behavior yet — the guard is dead code until step 6.
4. Create `POISON_UTILS.apply_stack` and `POISON_UTILS.apply_on_hit` chokepoints. Unit-tested in isolation.
5. Create `SPoison` system with Pass A (AoE emission) and Pass B (affliction tick). Integration-tested against a minimal world. At this point poison still flows through `SAreaEffectModifier` in parallel — **not shipped yet**.
6. Remove poison channel from `SAreaEffectModifier` (delete `_apply_poison_damage`, `_should_apply_poison`, the preload, the `apply_poison` branch in `_apply_effects`). Now `SPoison` is the sole poison path. Integration tests verify AoE behavior.
7. Add on-hit hook calls in `SMeleeAttack._apply_on_hit_element` and `SDamage._apply_bullet_effects`. On-hit integration tests pass.
8. Add `poison_exposure_timers` field to `CAreaEffect` and clearing in `on_merge`.
9. UI: author `poison_icon.gdshader`, create `poison_status_icon.tscn`, extend `view_hp_bar.gd`'s icon factory with a `POISON` case. Manual QA pass.
10. Cleanup: delete any remaining `_CPoison := preload(...)` references left over from step 6.
11. Full test pass — unit + integration + manual UI QA.

---

## 11. Open Questions / Flagged Decisions

- **Single `SPoison` system vs. split into `SPoisonEmitter` + `SPoisonTicker`.** Design currently assumes single-system-with-two-passes. If GECS query dispatch forces one query per system, implementation will split into two systems in the same `gameplay` group with explicit priority ordering. Behavior is identical either way; the doc documents the single-system form for clarity.
- **Placeholder poison-green color** (`vec4(0.35, 0.80, 0.30, 1.0)`). Art team may swap the shader base color or replace the ColorRect with a proper texture later. The shader's `base_color` uniform makes this a one-line change.
- **`CElementalAffliction` rename is tech debt**, tracked here but explicitly deferred.

---

## 12. Files Touched (summary)

**New:**
- `scripts/systems/s_poison.gd` — the new system
- `scripts/utils/poison_utils.gd` — `apply_stack` + `apply_on_hit` chokepoints
- `scripts/utils/area_effect_utils.gd` — factored target-scanning helper
- `resources/poison_icon.gdshader`
- `scenes/ui/poison_status_icon.tscn`
- `tests/unit/test_c_poison.gd`
- `tests/unit/test_poison_utils_apply_stack.gd`
- `tests/unit/test_poison_utils_apply_on_hit.gd`
- `tests/unit/test_s_elemental_affliction_poison_guard.gd`
- `tests/unit/test_poison_damage_formula.gd`
- `tests/integration/test_poison_on_hit_melee.gd`
- `tests/integration/test_poison_on_hit_bullet.gd`
- `tests/integration/test_poison_aoe_edge_trigger.gd`
- `tests/integration/test_poison_aoe_interval_accumulation.gd`
- `tests/integration/test_poison_aoe_leave_reset.gd`
- `tests/integration/test_poison_aoe_decay_pause.gd`
- `tests/integration/test_poison_aoe_overlap.gd`
- `tests/integration/test_poison_drop_on_lethal.gd`
- `tests/integration/test_poison_aoe_mutex_onhit.gd`
- `tests/integration/test_poison_keep_best_merge.gd`
- `tests/integration/test_poison_icon_visible.gd`

**Modified:**
- `scripts/components/c_poison.gd` — replace marker with per-instance tuning, keep-best `on_merge`
- `scripts/components/c_area_effect.gd` — add `poison_exposure_timers` runtime dict, clear in `on_merge`
- `scripts/components/c_elemental_attack.gd` — add `ElementType.POISON = 4`
- `scripts/systems/s_elemental_affliction.gd` — add POISON guard (one line) at top of entry loop
- `scripts/systems/s_area_effect_modifier.gd` — delete poison channel, adopt `AreaEffectUtils.find_targets_in_range`
- `scripts/systems/s_melee_attack.gd` — add `POISON_UTILS.apply_on_hit` call in `_apply_on_hit_element`
- `scripts/systems/s_damage.gd` — add `POISON_UTILS.apply_on_hit` call in `_apply_bullet_effects`
- `scripts/ui/viewmodels/viewmodel_hp_bar.gd` — no changes required (entries_changed path already works)
- `scripts/ui/views/view_hp_bar.gd` — add `POISON` case to the icon factory

**Deleted:** none.
