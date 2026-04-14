# Fire-Stuck-Enemy Bug — Phase 1 Investigation (Paused)

**Date:** 2026-04-14
**Branch:** `gol-project @ fix/poison-spawn-issues-196-203`
**Status:** Root cause NOT yet identified. Static analysis complete, evidence gathering pending.
**Next session:** reproduce live, run diagnostic script, form single hypothesis, test minimally.

---

## Symptoms (as reported by user)

- Enemy stops moving but the walk animation still plays.
- Player bullets (shooter weapon) cannot hit the enemy — no damage registered.
- Fire elemental DoT does not tick on the enemy either ("no any damage can be taken on it").
- Happens *sometimes*, to *some* enemies — not all.
- Re-applying or removing the fire buff (the exact mechanism is unclear) restores normal behavior.
- User associates the onset with "fire damage buff being added," though static analysis makes fire a suspect cause rather than a proven one (see Finding 2).

## Related recent work on the branch

- `098d47e refactor(damage): split CDamage into normal/piercing buckets` — shipped this session, unrelated to the bug (bug predates it).
- `fd306f6 refactor: remove redundant bypass_invincible and extract _calc_spawn_...`
- `908b93d fix(damage): bypass_invincible no longer sets invincible_time or trig...`
- `e02ebf7 fix(damage): poison effect bypasses invincible_time`

The branch name `fix/poison-spawn-issues-196-203` suggests this may be a new surface of an ongoing poison/spawn investigation. Worth checking if Issue #196 or related issues on `gol-project` describe overlapping symptoms before the next debugging session.

## Files read during investigation

| File | Reason |
|---|---|
| `scripts/components/c_damage.gd` | Damage component shape after this session's refactor |
| `scripts/components/c_movement.gd` | `base_max_speed`, `forbidden_move` fields |
| `scripts/components/c_elemental_affliction.gd` | Duplicate `base_max_speed` field, freeze state flags |
| `scripts/components/c_hp.gd` | `invincible_time`, HP observable |
| `scripts/systems/s_damage.gd` | `_take_damage` rejection paths, `_process_bullet_collision` |
| `scripts/systems/s_elemental_affliction.gd` | Freeze lifecycle, `_apply_movement_modifiers`, `_clear_afflictions` |
| `scripts/systems/s_move.gd` | `forbidden_move` gate, velocity clamp |
| `scripts/systems/s_animation.gd` | `forbidden_move` → `sprite.pause()` (line 74-76) |
| `scripts/systems/s_dead.gd` | Death component-strip path, `_initialize_generic_death` |
| `scripts/systems/s_collision.gd` | Area2D lifecycle |
| `scripts/utils/elemental_utils.gd` | `apply_attack` / `apply_payload`, `_ensure_affliction`, `_cleanup_empty_affliction` |
| `scripts/configs/config.gd` | `DEATH_REMOVE_COMPONENTS`, `LOSABLE_COMPONENTS` |
| `scripts/utils/ecs_utils.gd` | `is_losable_component` (CHP is not losable) |

## Findings

### Finding 1 — Split-brain `base_max_speed` state

Two different fields with identical names, written and read by different code paths:

| Field | Written by | Read by |
|---|---|---|
| `CMovement.base_max_speed` | `s_elemental_affliction.gd:177-178`, `s_weight_penalty.gd:24-25` | `s_elemental_affliction._clear_afflictions` (line 214), `s_weight_penalty` |
| `CElementalAffliction.base_max_speed` | `elemental_utils._ensure_affliction` (lines 146-155) | `elemental_utils._cleanup_empty_affliction` (line 189) |

Consequence: `s_elemental_affliction.gd:40` and `:84` enter cleanup via `_clear_afflictions` (reads `movement.base_max_speed`). `elemental_utils.apply_payload:80` enters cleanup via `_cleanup_empty_affliction` (reads `affliction.base_max_speed`). Different entry points read different "true" base values. If they diverge (e.g. weight system captured 140 but affliction captured the already-slowed 49), cleanup restores `max_speed` to the wrong value.

Additionally, neither cleanup resets `CMovement.base_max_speed` back to `-1`, so once captured it stays captured. If capture happened at a transiently bad moment (e.g. during a slow), the stale value persists across affliction re-applications.

**Status:** This is a structural bug regardless of the user's reported issue. Worth fixing after root cause confirmation of the reported bug (one-change-at-a-time discipline).

### Finding 2 — Fire alone cannot set `forbidden_move`

Searched `forbidden_move = true` across all scripts. The only production paths that set it are:

- `s_elemental_affliction.gd:201` — the **cold-driven** freeze branch (requires `should_freeze = cold_intensity >= FROZEN_THRESHOLD (2.5)`)
- `s_dead.gd:96, 132` — death initialization
- `gol_game_state.gd:113` — game-over lock

Fire has no code path that directly stops movement. When the user says "fire damage buff caused it," the fire is at best an indirect trigger. Most plausible indirect scenarios:

- Enemy had **wet + fire**, fire consumed the wet via `_resolve_counter_elements`, wet was amplifying cold (`WET_COLD_BONUS = 0.75`), and the interaction exposes a freeze-lifecycle bug (see Finding 3).
- Enemy was already frozen by cold, fire was applied during the frozen window, and a component removal bypassed the `forbidden_move` cleanup (see Finding 3).
- User is associating the bug with the most visually prominent element, not the actually-causal one.

**Not yet verified** which. Need user confirmation on the affliction icons shown on the stuck enemy's HP bar.

### Finding 3 — Freeze lifecycle has an early-return that self-releases *only while the entity is still in the query*

`s_elemental_affliction._apply_movement_modifiers` at lines 186-195:

```gdscript
if affliction.status_applied_movement_lock:
    affliction.freeze_timer += delta
    movement.max_speed = base_speed * (1.0 - MAX_COLD_SLOW)
    if affliction.freeze_timer >= FREEZE_MAX_DURATION:
        movement.forbidden_move = false
        affliction.status_applied_movement_lock = false
        affliction.freeze_timer = 0.0
        affliction.freeze_cooldown = FREEZE_COOLDOWN
    return  # early return
```

Self-release fires after 2s **only while the entity is in the query** (`q.with_all([CElementalAffliction, CTransform])`). If `CElementalAffliction` is removed between freeze being set and timer expiring, `forbidden_move` never gets cleared.

I searched both cleanup paths (`_clear_afflictions` in s_elemental_affliction and `_cleanup_empty_affliction` in elemental_utils) and both *do* reset `forbidden_move`. I did not find a removal path that bypasses them in source. However, static analysis is insufficient — runtime component lifecycle events (e.g. entity teardown, world reset, component_removed signal order) could still sneak past.

**Note:** `s_animation.gd:74-76` does `sprite.pause()` when `forbidden_move` is true. If the sprite is paused mid-walk-frame, the visual is "frozen on a walk frame," which matches the user's "still play move animation" description. This is strong circumstantial evidence that `forbidden_move` IS stuck true, even if the triggering path is uncertain.

### Finding 4 — I cannot explain the "no damage taken" symptom from static source

For an alive enemy (has `CHP`, no `CDead`), every rejection path in `_take_damage`:

1. `_should_ignore_bullet_target` → checks `CTrigger`. Grep confirms no production code adds `CTrigger` dynamically (test fixtures only).
2. `if not hp: return false` → only if `CHP` is gone. `CHP` is not in `LOSABLE_COMPONENTS`, so the lethal-drop mechanic can't strip it.
3. `if hp.invincible_time > 0 and not bypass_invincible` → blocks bullets, but **explicitly bypassed** by fire DoT (piercing).
4. Console player-invincibility → only triggered for `CCamp.camp == PLAYER`. Enemies are always `ENEMY` camp (confirmed `camp` is set once at authoring, never mutated).

**Therefore fire DoT SHOULD tick on an alive enemy even if bullets are somehow blocked.** But the user reports fire DoT also fails to tick. This is the biggest unexplained symptom and the core question for the next session.

Candidate explanations (ordered by static-analysis plausibility):

- **(a)** The enemy has `CDead` but the user perceives it as alive (visually present because `_complete_death` never fires). **Counter-evidence:** `apply_payload` and `apply_attack` both early-reject on `has_component(CDead)`, so the user's "re-toggling fire fixes it" shouldn't be able to route through elemental_utils if CDead is present. Unless "toggle" means something else (e.g. a console command that bypasses elemental_utils).
- **(b)** The fire entry has `intensity == 0` and `_apply_tick_effect` computes `0 * FIRE_DAMAGE_PER_SECOND = 0` damage per tick. User perceives "no damage" even though the tick function is executing. `_should_remove_entry` should erase such entries, so this can only persist across one tick.
- **(c)** `CElementalAffliction` is silently missing from the entity, but the HP bar UI is still showing stale affliction icons via `viewmodel_hp_bar.gd` subscription that hasn't been torn down. The user thinks "fire is applied" because the icon is visible, but the entity no longer has the component.
- **(d)** `CCollision.area` got invalidated or `monitoring` was set false, so bullets' physics query misses the entity. Unrelated to fire on the face of it, but might correlate. Nothing in source dynamically touches `monitoring`/`monitorable`.
- **(e)** Some path I haven't found. Possibly in `gol-tools/foreman/` or a service layer I didn't search.

## Proposed diagnostic script (not yet saved to disk)

To be run via AI Debug Bridge (`node gol-tools/ai-debug/ai-debug.mjs script scripts/debug/debug_stuck_enemy.gd`) **at the moment the bug is observed live**. Dumps everything relevant to disambiguate (a)-(e) above.

```gdscript
# scripts/debug/debug_stuck_enemy.gd
# Usage: node gol-tools/ai-debug/ai-debug.mjs script scripts/debug/debug_stuck_enemy.gd
# Picks the enemy nearest the player and dumps everything relevant to the stuck-enemy bug.

extends Node

func run():
    if not ECS or not ECS.world:
        print("ERROR: no ECS world"); return

    var target: Entity = _find_target()
    if target == null:
        print("ERROR: no enemy target found"); return

    print("=== Stuck Enemy Diagnostic: %s (id=%d) ===" % [target.name, target.get_instance_id()])

    # 1. Raw component list
    print("\n[Components]")
    for key in target.components.keys():
        print("  - ", key)

    # 2. HP state
    var hp: CHP = target.get_component(CHP)
    if hp:
        print("\n[CHP] hp=%.1f/%.1f  invincible_time=%.3f" % [hp.hp, hp.max_hp, hp.invincible_time])
    else:
        print("\n[CHP] MISSING — bullets & fire DoT both return false from _take_damage")

    # 3. Movement state
    var mv: CMovement = target.get_component(CMovement)
    if mv:
        print("\n[CMovement] max_speed=%.1f  base_max_speed=%.1f  forbidden_move=%s  velocity=%s" % [
            mv.max_speed, mv.base_max_speed, str(mv.forbidden_move), str(mv.velocity)
        ])

    # 4. Affliction state
    var aff = target.get_component(CElementalAffliction)
    if aff:
        print("\n[CElementalAffliction]")
        print("  base_max_speed=%.1f" % aff.base_max_speed)
        print("  status_applied_movement_lock=%s" % str(aff.status_applied_movement_lock))
        print("  freeze_timer=%.3f / FREEZE_MAX_DURATION=%.1f" % [aff.freeze_timer, 2.0])
        print("  freeze_cooldown=%.3f" % aff.freeze_cooldown)
        print("  entries.size=%d" % aff.entries.size())
        for elem_type in aff.entries.keys():
            var e: Dictionary = aff.entries[elem_type]
            print("    element=%d  intensity=%.3f  remaining=%.3f  decay=%.3f  tick_timer=%.3f  tick_interval=%.3f" % [
                elem_type,
                float(e.get("intensity", 0.0)),
                float(e.get("remaining_duration", 0.0)),
                float(e.get("decay_per_second", 0.0)),
                float(e.get("tick_timer", 0.0)),
                float(e.get("tick_interval", 0.5)),
            ])
    else:
        print("\n[CElementalAffliction] MISSING — but user claims fire buff is present")

    # 5. Pending CDamage inbox (post-refactor: two buckets)
    var dmg: CDamage = target.get_component(CDamage)
    if dmg:
        print("\n[CDamage PENDING] normal=%.2f  piercing=%.2f  knockback=%s" % [
            dmg.normal_amount, dmg.piercing_amount, str(dmg.knockback_direction)
        ])
    else:
        print("\n[CDamage PENDING] none (inbox empty)")

    # 6. Collision / physics visibility
    var col: CCollision = target.get_component(CCollision)
    if col:
        if col.area and is_instance_valid(col.area):
            print("\n[CCollision] area_valid=true  monitoring=%s  monitorable=%s  layer=%d  mask=%d" % [
                str(col.area.monitoring), str(col.area.monitorable),
                col.area.collision_layer, col.area.collision_mask
            ])
        else:
            print("\n[CCollision] area missing / invalidated — bullets cannot hit this entity")
    else:
        print("\n[CCollision] MISSING — bullets cannot find this entity via physics query")

    # 7. Camp + CDead sanity
    var camp: CCamp = target.get_component(CCamp)
    if camp:
        print("\n[CCamp] camp=%d (0=player,1=enemy)" % camp.camp)
    print("[CDead] present=%s" % str(target.has_component(CDead)))
    print("[CTrigger] present=%s" % str(target.has_component(CTrigger)))

    print("\n=== end diagnostic ===")


func _find_target() -> Entity:
    if not ECS.world:
        return null
    var players: Array = ECS.world.query.with_all([CPlayer, CTransform]).execute()
    if players.is_empty():
        return null
    var player: Entity = players[0]
    var ptr: CTransform = player.get_component(CTransform)
    if ptr == null:
        return null

    var enemies: Array = ECS.world.query.with_all([CCamp, CTransform, CHP]).execute()
    var best: Entity = null
    var best_dist := INF
    for e in enemies:
        if e == player:
            continue
        var c: CCamp = e.get_component(CCamp)
        if c == null or c.camp != CCamp.CampType.ENEMY:
            continue
        var t: CTransform = e.get_component(CTransform)
        if t == null:
            continue
        var d := ptr.position.distance_squared_to(t.position)
        if d < best_dist:
            best_dist = d
            best = e
    return best
```

Expected output-to-diagnosis mapping:

| Observed in dump | Root cause candidate |
|---|---|
| `CHP MISSING` | Component got stripped somehow — investigate who removed it |
| `CDead present=true` + fire entries still in affliction | Death tween stalled, investigate `_complete_death` not firing |
| `CCollision MISSING` or `area invalid` | Entity lost physics — investigate removal path |
| `forbidden_move=true` + `status_applied_movement_lock=true` + `freeze_timer < 2.0` frozen forever | Freeze timer isn't advancing — entity not in affliction query (verify `affliction.entries.size`) |
| `forbidden_move=true` + `status_applied_movement_lock=false` | `forbidden_move` leaked from a removed lock — find the missing cleanup path |
| `base_max_speed=0.0` or tiny | Split-brain capture happened during slow state (Finding 1) |
| Fire entry with `intensity=0.0` | `_should_remove_entry` race — entry should have been erased |
| All fields look normal | Problem is in the damage application path, not the component state — instrument `_take_damage` next |

## Open questions for user (before next session)

1. **Element certainty** — when the bug happens, is the stuck enemy's HP bar showing *only* fire, or also cold/wet? If you can see the icons, which ones are lit?
2. **Hit feedback** — when you shoot the stuck enemy, does the hit-blink shader fire (sprite flashes white)? If it flashes but HP doesn't drop, the damage *is* being applied but something else is wrong (possibly UI bind). If no flash, the bullet is being rejected before `_play_hit_blink` fires.
3. **Cursor/hover** — does the cursor/target indicator still acknowledge the enemy, or does it behave like the enemy isn't there?
4. **"Toggle fire" mechanism** — what exact action unsticks it? Shooting it again with a fire weapon? A console command? Both?
5. **Repro pattern** — any reliable steps, or purely random? Specific enemy types (e.g. only `enemy_poison`)?
6. **Pre-existence** — does this happen on `main` branch too, or only on `fix/poison-spawn-issues-196-203`? (If only on the branch, check recent commits for the introducing change.)

## Next session plan

1. **Check Issue tracker** — `gh issue list -R Dluck-Games/god-of-lego --search "stuck OR frozen OR elemental"` to see if this is already filed; if so, read existing context.
2. **Answer open questions** — get user responses.
3. **Save diagnostic script** — `scripts/debug/debug_stuck_enemy.gd` (content above).
4. **Reproduce live** — user provokes the bug, then runs the diagnostic via `gol-debug` skill.
5. **Parse dump** — use the output-to-diagnosis mapping table to narrow candidates from 5 to 1.
6. **Form single hypothesis** — write it down ("I think X is the root cause because Y").
7. **Test minimally** — smallest possible change to verify the hypothesis. One variable at a time.
8. **If confirmed** — write failing test first, then fix at root, then verify.
9. **If disconfirmed** — back to Phase 1 with new evidence, DO NOT stack fixes.
10. **After root cause is fixed** — separately tackle Finding 1 (split-brain `base_max_speed`) as structural cleanup. One change per session.

## Iron Law status

**Phase 1 (Root Cause Investigation):** in progress. Static analysis done, runtime evidence not yet gathered.
**Phase 2 (Pattern Analysis):** not started.
**Phase 3 (Hypothesis and Testing):** not started.
**Phase 4 (Implementation):** blocked on Phase 1. No fixes proposed. Finding 1 is a known structural issue but explicitly NOT being bundled into this bug's fix.
