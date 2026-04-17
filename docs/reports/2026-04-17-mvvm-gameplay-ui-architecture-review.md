# MVVM Gameplay UI — Architecture Review & Refactor Plan

**Date**: 2026-04-17
**Scope**: `scripts/ui/**`, `scripts/services/impl/service_ui.gd`, downstream consumers in `scripts/systems/`, `scripts/gameplay/`
**Goal**: Catalog existing issues in the MVVM layer so a refactor pass can address them systematically.

---

## 1. Architecture Snapshot

```
ObservableProperty   — signal + value + 1:1 bind + N subscribers (RefCounted)
ViewModelBase        — setup/teardown, RefCounted
ViewBase             — Control, _ready → setup/bind; teardown manual
EntityBoundView      — auto-dies on entity/component removal, tracks bound observables
Service_UI           — ref-counted VM pool; push/pop view tree; HUD + GAME layers
```

**Documented contract** (`scripts/ui/AGENTS.md`): one-way flow `System → Component → ViewModel → View`.

**Reality**: Flow partially respected. See §2.3.

---

## 2. Findings

Severity: **P0** = blocks correct refactor, **P1** = frequent source of bugs, **P2** = tech debt / polish.

### 2.1 [P0] Shared ViewModel + per-entity dictionaries is the wrong abstraction

**Files**: `scripts/ui/viewmodels/viewmodel_hp_bar.gd`, `scripts/services/impl/service_ui.gd:106-128`, `scripts/ui/views/view_hp_bar.gd`

`Service_UI.acquire_view_model()` ref-count pools one VM instance per class. But `ViewModel_HPBar` holds **8** `Dictionary[Entity, ObservableProperty]` fields because a single VM serves N hp bars.

Consequences:
- `bind_to_entity()` overwrites prior entries silently — no guard against double bind (`viewmodel_hp_bar.gd:22-35`).
- Entity-keyed dicts leak if `unbind_to_entity` isn't called (e.g. entity freed before view teardown; `EntityBoundView.teardown` nulls `_entity` in super then view calls `vm.unbind_to_entity(_entity)` with null — see `view_hp_bar.gd:380-388`).
- Double-teardown: `EntityBoundView._unbind_all_observables` tears down the same observables that `vm.unbind_to_entity` will tear down. Works by luck (teardown is idempotent).
- Mixes two mental models (singleton VM for HUD vs multiplexed VM for HPBar) under one API.

**Fix direction**: Split `acquire_view_model` into `acquire_shared_vm(class)` (HUD, DialogueHint) and `create_scoped_vm(class, context)` (HPBar, BoxHint). Per-entity views own their VM instance; drop the dicts.

---

### 2.2 [P0] `ObservableProperty.set_value` short-circuits on mutated reference types

**File**: `scripts/ui/observable_property.gd:29-33`

```gdscript
func set_value(new_value: Variant) -> void:
    if typeof(_value) == typeof(new_value) and _value == new_value:
        return
    _value = new_value
    _changed.emit(new_value)
```

For Dictionary/Array/Resource, `==` compares by reference or shallow contents; mutating in-place then calling `set_value(same_ref)` is a no-op and never emits. Evidence of workaround tax:

- `viewmodel_hp_bar.gd:80,95` — `affliction.entries.duplicate(true)` to force a new reference.
- `crosshair.gd:47-49` — `_draw_node.queue_redraw()` every frame to bypass the equality gate when aim position stays the same Vector2 while weapon state changes.

**Fix direction**: Drop the equality check entirely (simpler, small perf cost) OR add a `set_value_force()` / `notify()` variant for callers that mutated contents. Keep the cheap check only for true primitives.

---

### 2.3 [P0] One-way flow is documented but not enforced

**Files**: `scripts/ui/views/view_composer.gd:90,112`, `scripts/ui/views/view_dialogue.gd:67,74`, `scripts/ui/views/view_composer.gd:84-87`

`AGENTS.md:98` states "DO NOT modify component data from Views". Code says:

- `view_composer.gd:90` — `COMPOSER_UTILS.craft_component(_player_entity, bp_type, GOL.Player)` in a button handler inside the View.
- `view_composer.gd:112` — `COMPOSER_UTILS.dismantle_component(...)` same pattern.
- `view_dialogue.gd:67,74` — `_on_option_callback.call(action)` routes Control events to System without passing through VM.
- `view_composer.gd:84,87,103` — View reads `GOL.Player.unlocked_blueprints`, `GOL.Player.component_points`, `_player_entity.components` directly.

Root cause: `ViewModelBase` has **no command / intent abstraction**. VMs only expose observables for reads.

**Fix direction**: Add command methods to each VM (`craft(bp_type)`, `dismantle(comp_type)`, `select_option(action)`). Views only call VM methods; VM calls game systems/utils. Remove all `GOL.Player.*` and `entity.components.*` reads from Views.

---

### 2.4 [P0] Coupling to global singletons inside VMs

**Files**: `scripts/ui/viewmodels/viewmodel_hud.gd:23,32`, `viewmodel_composer.gd:46,52-54`, `viewmodel_box_hint.gd:59-64`, `scripts/ui/crosshair.gd:114`

VMs reach directly into `GOL.Player`, `ECS.world.query`, `ServiceContext.recipe()`, etc. Effects:
- VMs are non-testable (can't inject fakes).
- View/VM boundary becomes meaningless because Views reach into the same singletons too.

**Fix direction**: Inject dependencies via VM constructor or `configure(context)`. Pass `player_data`, `world_query_fn`, `recipe_service` as parameters. No autoload access inside VM method bodies.

---

### 2.5 [P0] ECS components hold View references

**Files**: `scripts/components/c_hp.gd` (field `bound_hp_bar`), `scripts/components/c_pickup.gd` (field `box_hint_view`, `focused_box`), `scripts/systems/ui/s_ui_hpbar.gd:38,45`, `scripts/systems/s_pickup.gd:159-176`

Components are supposed to be pure data but currently hold pointers to Control nodes. Issues:
- Couples ECS to Godot UI tree.
- Creates cyclic refcount chains (VM → closure → View → Component → back).
- Blocks serialization / replay / headless testing.
- `CPickup.focused_box` is also an `ObservableProperty` embedded in a component — blurs the line between data and reactive state.

**Fix direction**: Move entity↔view maps out of components into the spawning System. `SUI_Hpbar` already has `_entity_to_hp_bar_map` — delete `CHP.bound_hp_bar` and use the system's map. Same for `CPickup.box_hint_view`. For `CPickup.focused_box`, decide whether it's domain state (keep in component as a plain value + signal) or UI state (move to VM).

---

### 2.6 [P1] `CrosshairView` bypasses the MVVM infrastructure

**File**: `scripts/ui/crosshair.gd`

- Extends `CanvasLayer`, not `ViewBase` (`:2`).
- Instantiates VM with `CrosshairViewModel.new()` — not via `acquire_view_model` (`:38`).
- Polls ECS every frame in `_process → _try_bind_entity` (`:45-121`) for entity discovery — domain logic in View.
- Duplicates the element color table already in `View_HPBar._get_element_color` (`:5-10` vs `view_hp_bar.gd:326-339`).

**Fix direction**: Create `SCrosshairBinding` system responsible for entity discovery. It calls `vm.bind_to_entity(player)` once. Make the View pure render + subscribe. Extract `ElementalVisualConfig` (constants or Resource) shared with HPBar. If it must remain a `CanvasLayer`, create a `CanvasLayerViewBase` that parallels `ViewBase` lifecycle.

---

### 2.7 [P1] Inconsistent lifecycle: `setup()` vs `bind()` is blurred

**Files**: `scripts/ui/view_base.gd:5-15`, `scripts/ui/views/view_hp_bar.gd:44-50`, `view_composer.gd:31-40`, `view_dialogue_hint.gd:20-23`

Stated contract: `setup()` = acquire VM, `bind()` = subscribe. In practice:

- `View_HPBar.setup()` calls `vm.bind_to_entity(_entity)` — that's VM state config, not just acquisition.
- `View_Composer.setup()` calls `vm.set_context(mode, player)`.
- `View_DialogueHint.setup()` calls `vm.set_target(name, transform)`.

Because `_ready` runs `setup()` → `bind()` synchronously and `ObservableProperty.subscribe` fires with current value immediately (`:82`), the ordering sort-of works, but the contract is unstated and fragile.

**Fix direction**: Replace the two-phase hook with three explicit phases:
1. `configure(context: Dictionary)` — called by spawner before adding to tree (sets required inputs).
2. `_ready → bind()` — subscribe.
3. `teardown()` — unsubscribe + release.

Remove `setup()` or narrow it to VM acquisition only.

---

### 2.8 [P1] Subscriber closures are never explicitly unsubscribed

**Files**: `scripts/ui/view_base.gd:20-28`, every View's `bind()` method

`ViewBase.bind_text`/`bind_visibility` and ad-hoc `observable.subscribe(lambda)` calls never unsubscribe. Current cleanup relies on VM teardown disconnecting everyone. This is safe only because VMs get torn down when the pool refcount hits 0.

Failure modes that will appear once VMs are shared across views with different lifetimes (likely after §2.1 fix):
- `ObservableProperty._subscriber_callbacks` holds strong references to lambdas that captured `self` (the View) → dead View kept pinned.
- Signals fire on a `queue_free`'d View → runtime error.

**Fix direction**: Return a `Disposable` (token object or Callable) from `subscribe()`. `ViewBase` tracks tokens, calls them in `teardown`. Never rely on VM teardown for View-scoped subscriptions.

---

### 2.9 [P1] No command / reactive-collection primitives

**File**: `scripts/ui/viewmodels/viewmodel_composer.gd:39-42`

```gdscript
func request_refresh() -> void:
    _refresh()
    refresh_requested.set_value(true)
    refresh_requested.set_value(false)
```

Toggling true→false is a workaround for missing "signal-without-value" semantics. Similarly, list observables (`available_blueprints`, `player_components`, `options`) are whole-array replacements — Views rebuild all children on each change (`view_composer.gd:67-68`).

**Fix direction**:
- Add `ObservableEvent` (pure signal, no stored value).
- Consider `ObservableList[T]` later only if a real list grows large enough to matter; don't speculatively introduce it.

---

### 2.10 [P2] Business / formatting logic in `ViewModel_BoxHint`

**File**: `scripts/ui/viewmodels/viewmodel_box_hint.gd:42-71`

VM builds display strings ("掉落物", "（需要：%s）") and navigates blueprint/recipe lookups. This couples VM to localization and presentation. Tests would have to assert Chinese strings.

**Fix direction**: VM exposes structured data (`{name_source: "blueprint"|"component"|"recipe", name_key: "...", required_component: Script|null}`). A formatter (view-side or a dedicated `BoxHintFormatter`) produces strings.

---

### 2.11 [P2] Typing inconsistency across Views

**Files**: `view_composer.gd:13`, `view_dialogue.gd:8`, `view_dialogue_hint.gd:5`, `view_hud.gd:4`

- `View_Composer.vm: ViewModelBase` with `vm as ViewModel_Composer` casts.
- `View_Dialogue.vm: ViewModelBase` same pattern.
- `View_DialogueHint.vm = null` fully dynamic.
- `View_HUD.vm: ViewModel_HUD` properly typed.

Likely root cause: preload circular-reference avoidance. Noted in `view_composer.gd:8` with explicit preload of VM script.

**Fix direction**: Always type `vm` as the concrete VM class. If cycles appear, rely on `class_name` references (no preload needed) or invert the dependency so VM doesn't import the View.

---

### 2.12 [P2] Double teardown of Observables on HPBar

**Files**: `scripts/ui/entity_bound_view.gd:109-113`, `scripts/ui/views/view_hp_bar.gd:380-388`, `viewmodel_hp_bar.gd:39-61`

`EntityBoundView._unbind_all_observables()` tears down everything in `_bound_observables`, then `vm.unbind_to_entity(_entity)` tears down the same observables via the dict entries. Idempotent today, but wasteful and fragile.

**Fix direction**: Pick one owner. Recommend VM owns observables (after §2.1 fix, VM is per-view anyway). `EntityBoundView` only tracks subscriptions, not observables themselves.

---

### 2.13 [P2] `bind_observable` conflates binding with transformation

**Files**: `scripts/ui/observable_property.gd:54-70`, `viewmodel_dialogue_hint.gd:33`, `view_dialogue_name_tag.gd:43`

The `custom_setter` parameter lets callers transform the bound value. Works but now `unbind()` must remember which Callable was used, and re-binding requires repeating the setter.

**Fix direction**: Introduce a pure `map(other, transform_fn) -> ObservableProperty` that returns a derived observable. `bind_observable` stays 1:1 identity binding. Keeps each primitive doing one thing.

---

### 2.14 [P2] Views reading ECS components directly

**File**: `scripts/ui/views/view_hp_bar.gd:107-113,162-165,352-373`

Even though HPBar has a VM, the View reaches back into `_entity.get_component(CHP)`, `_entity.get_component(CElementalAffliction)`, `_entity.get_component(CWeapon)`, etc. for both raw data and style logic. That bypasses the VM entirely — the VM becomes a half-useful cache.

**Fix direction**: Expose everything the View needs as VM observables (style, emoji kind, freeze_timer, etc.). View never calls `get_component`.

---

## 3. Recommended Refactor Order

Tackle dependencies in order — earlier fixes unblock later ones.

1. **§2.2** — Fix `ObservableProperty.set_value` mutation semantics. (Small, cross-cutting; removes workarounds throughout.)
2. **§2.8** — Disposable subscription tokens. (Prerequisite for §2.1 because per-view VMs need clean subscription scopes.)
3. **§2.1** — Split shared vs scoped VM pooling; kill entity-keyed dicts in `ViewModel_HPBar` / `ViewModel_BoxHint`.
4. **§2.5** — Remove View pointers from ECS components.
5. **§2.3** + **§2.4** — Introduce VM commands; stop reading `GOL.*` from Views and VMs; inject dependencies.
6. **§2.7** — Formalize three-phase lifecycle (`configure` / `bind` / `teardown`).
7. **§2.6** — Normalize `CrosshairView` into the MVVM shape (or explicit `CanvasLayerViewBase`).
8. **§2.14** — Remove direct `get_component` from Views now that VM commands exist.
9. **§2.12** — Clean up double-teardown once ownership is clear.
10. **§2.9**, **§2.10**, **§2.11**, **§2.13** — Polish (commands/events, formatters, typing, `map` primitive).

---

## 4. Out of Scope (explicitly)

- Menu views (`view_game_over`, `view_pause_menu`) — not MVVM, not in this review.
- Scene files under `scenes/ui/*.tscn` — structure is fine, only script changes needed.
- Testing infrastructure — after refactor, revisit how to unit-test VMs with injected fakes.

---

## 5. Quick Reference: Files to Touch

| Area | Files |
|------|-------|
| Core | `scripts/ui/observable_property.gd`, `view_base.gd`, `viewmodel_base.gd`, `entity_bound_view.gd` |
| VM pool | `scripts/services/impl/service_ui.gd` |
| VMs | `scripts/ui/viewmodels/viewmodel_hp_bar.gd`, `viewmodel_hud.gd`, `viewmodel_box_hint.gd`, `viewmodel_composer.gd`, `viewmodel_dialogue.gd`, `viewmodel_dialogue_hint.gd`, `crosshair_view_model.gd` |
| Views | `scripts/ui/views/view_hp_bar.gd`, `view_composer.gd`, `view_dialogue.gd`, `view_box_hint.gd`, `view_hud.gd`, `view_dialogue_hint.gd`, `view_dialogue_name_tag.gd`, `scripts/ui/crosshair.gd` |
| Systems (upstream) | `scripts/systems/ui/s_ui.gd`, `s_ui_hpbar.gd`, `s_ui_dialogue_name_tag.gd`, `scripts/systems/s_pickup.gd`, `s_dialogue.gd`, `s_dead.gd`, `scripts/gameplay/gol_game_state.gd` |
| Components (depoison) | `scripts/components/c_hp.gd`, `c_pickup.gd` |
| Docs | `scripts/ui/AGENTS.md` (update once refactor lands) |
