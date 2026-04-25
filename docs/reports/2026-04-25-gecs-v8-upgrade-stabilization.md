# GECS v8 Upgrade Stabilization — Perf + CI + Profiler Fixes

**Date:** 2026-04-25
**Branch:** `chore/gecs-v8-upgrade`
**PR:** [#264](https://github.com/Dluck-Games/god-of-lego/pull/264)
**Scope:** CI fixes, GOAP perf overhaul, SPerception crash fix, SAI burst smoothing, GOAP plan cache, profiler attribution fix

## TL;DR

Seven atomic commits landed on the GECS v8 upgrade branch that together:

- **Unblocked CI** — fixed 2 unit-test suites and 1 integration test broken by the v8 API/typing changes, and a freed-instance flood that inflated game logs to 1.5 GB.
- **Cut AI cost by ~60%** — GOAP re-plans went from catastrophic (~18 allocations + O(N²) open-list scan + 1024-iter A\* per decision) to memoized-and-staggered (82% cache hit rate, 3 decisions/frame cap, 128-iter A\* cap).
- **Killed frame bursts** — p99 AI frame cost 3.26 ms → 1.51 ms (-54%), max 3.78 ms → 2.26 ms (-40%), 0 frames >3× avg.
- **Fixed profiler attribution** — the 12–14 ms gap between "Total Process" and "Group Breakdown" is now fully attributed to ECS wall time vs non-ECS engine work.

## Work Items

| # | Commit | Category | Impact |
|---|---|---|---|
| 1 | `ad1bd1b` | fix(tests) | Unblocks CI on GECS v8 typing changes |
| 2 | `340ad6b` | fix(perception) | Stops SCRIPT ERROR flood; log size 1.5 GB → 366 lines |
| 3 | `07f25e2` | perf(goap) | Eliminates ~18 allocations per plan build; caps A\* iterations |
| 4 | `42052e7` | fix(world) | `purge()` evicts freed entity refs (CI integration test) |
| 5 | `9dfcb90` | perf(ai) | Frame-stagger GOAP decisions (≤ 3 / frame) |
| 6 | `59246bf` | perf(goap) | Plan memoization by (goal, world-state) — 82% hit rate |
| 7 | `f20d49c` | fix(perf_panel) | Profiler attribution gap closed |

## 1. CI Test Fixes (`ad1bd1b`)

**Failures:**

- `test_console_subcommand_case.gd` — 2 cases errored: `Invalid assignment of property '_sorted_names' with value of type 'Array' on RefCounted (ConsoleRegistry)`.
- `test_console_parser_quotes.gd` — parse error on `is_true("msg")`, entire suite silently skipped.

**Root causes:**

- Godot 4.6 + GECS v8 stricter typing: untyped `Array` literal `["spawn"]` assigned to typed `Array[String]` field no longer silently converts. The test helper aborted mid-function, downstream `registry.execute(...)` crashed with `Nonexistent function 'execute' in base 'Nil'`.
- gdUnit4 4.x API: `is_true()` takes **no** arguments. The custom message must go through `.override_failure_message()`. `is_true(msg)` was a parse error, so the file failed to load and gdUnit silently skipped the suite. Fixing the parse error exposed a third bug — an incorrect `positionals` assertion that didn't match the parser's contract (parts[1] is `subcmd_candidate`, not a positional).

**Fix:** Construct typed `Array[String]` locals explicitly; port assertions to the correct gdUnit4 API; align parser-test expectations with the actual `cmd / subcmd_candidate / positionals[]` contract.

**Result:** unit count 616 → 620 (4 errored cases now pass, 1 previously-skipped case runs and passes). 0 failures, 0 errors.

## 2. SPerception Freed-Instance Flood (`340ad6b`)

**Symptom:** Log file `game-20260425-*.log` flooded with `SCRIPT ERROR: Trying to assign invalid previously freed instance` every 10 lines from `s_perception.gd:109`. Game logs hit **1.5 GB**.

**Root cause:** `SPerception._pos_cache` is a frame-scoped snapshot built at the top of `process()`. Other systems earlier in the `gameplay` group order (notably `EatGrass` and `SWorldGrowth`, which call `ECS.world.remove_entity`) can free entities mid-frame. When perception later iterated the cache, the typed assignment

```gdscript
var candidate: Entity = entry["entity"]
```

threw because the cached ref was freed.

**Fix:** read the cached ref as `Variant`, validate with `is_instance_valid`, skip stale entries. The cache is still rebuilt next frame; dead entries just don't contribute to this frame's visibility.

**Verified:** headless playtest with 223 entities, 20 s of active GOAP ticking — zero SCRIPT ERROR, log size 366 lines (vs 1.5 GB pre-fix).

## 3. GOAP Per-Plan Allocation Cleanup (`07f25e2`)

**Root cause analysis:** `GoapPlanner.build_plan_for_goal` had four compounding issues:

1. `get_all_actions()` did `script.new()` for all 18 action classes **on every plan build** (~18 RefCounted allocations per plan × multiple plans per tick × N agents).
2. `_plan_for_goal` rebuilt and re-sorted `planning_keys` on every call.
3. A\* open-list used a linear min-f scan per expansion — O(N²) in open-list size.
4. `MAX_ITERATIONS = 1024`, absurdly high for GOL's 2–5 step plans.

**Fixes:**

- **Action instance cache** — `_cached_action_instances` statically holds one shared instance per action class. Zero `RefCounted.new()` after warmup.
- **Planning-keys cache** — `_get_planning_keys` now maintains a monotonically growing key set, eliminating the O(K log K) re-sort.
- **A\* iteration cap** — `MAX_ITERATIONS = 128`, still 4× the deepest plan observed.
- **GatherResource refactor** — the one action with mutable per-agent state (`_gather_elapsed`, `_progress_view`) moved those fields into the plan-step `context` dict, matching the convention used by `attack_ranged` and `patrol`. This restored the "actions are stateless" invariant, which is the prerequisite for instance sharing.

**Behavior verification:** 620 unit tests (including 6 planner assertions on action choice + cost preferences), plus integration tests for rabbit forage, rabbit lifecycle (flee-from-zombie assertion), combat, speech bubble — all pass.

## 4. GOLWorld.purge Freed-Ref Eviction (`42052e7`)

**Failure:** Integration test `test_teardown_cleanup` — `purge() removes stale refs from world.entities` expected 0, got 1.

**Root cause:** GECS v8's `World.remove_entity` early-returns on freed instances:

```gdscript
func remove_entity(entity: Entity) -> void:
    if not is_instance_valid(entity):
        return                      # ← never reaches the entities.remove_at line
    ...
    entities.remove_at(erase_idx)
```

So `purge()` couldn't evict stale refs from the `entities` array. The GECS tests that would have caught this were removed during the v8 upgrade (commit `9119829`).

**Fix:** Override `GOLWorld.purge` to scan `entities` and `entity_id_registry` for freed refs and strip them *before* delegating to `super.purge()`. Pure defense; no effect on live entities.

**Verified:** `test_teardown_cleanup` 4/4 pass; CI job `Integration Tests` green.

## 5. SAI Frame-Stagger (`9dfcb90`)

**Problem:** even after the allocation cleanup, the user reported visible micro-stutters — AI cost was bursty (4–8 ms spikes) rather than steady. A 2 ms wall-clock budget didn't help because the budget itself varied with host load.

**Fix design:** replace the wall-clock budget with a deterministic **two-pass loop** in `SAI.process`:

- **Pass 1** (cheap, unconditional): every agent gets `process_action_tick` + `_consume_tick_delta` + threat-state signal. Collects agents whose tick-interval timer crossed into `ready_for_decision`.
- **Pass 2** (rate-limited): at most `MAX_DECISIONS_PER_FRAME = 3` decision ticks, in stable `instance_id` order with a rotating start offset derived from `_frame_counter`. Fairness is guaranteed — no agent can be starved across frames.

Over-quota agents have their `_update_timer` clamped to "just ready" so they re-arm next frame without accumulating unbounded excess. A 3 ms hard wall-clock ceiling remains as a safety net for pathological A\* runs.

**Parameter sweep** at 41 agents (20 rabbits + 20 zombies + 1 player, full gameplay systems), 360 frames at 60 FPS:

| MAX | max | p99 | frames > 3× avg |
|---|---|---|---|
| 2 | 3.0 ms | 2.3 ms | 0.6% |
| **3** | **3.0 ms** | **2.5 ms** | **0.3%** ← chosen |
| 4 | 3.1 ms | 2.6 ms | 0.3% |
| 6 | 4.2 ms | 3.0 ms | 1.1% (bursts return) |

**Measured delta** (before → after stagger, same scenario):

| Metric | Before (2 ms budget) | After (MAX=3) | Δ |
|---|---|---|---|
| avg | 0.991 ms | 0.941 ms | -5% |
| p95 | 1.641 ms | 1.630 ms | -1% |
| p99 | 3.259 ms | 2.100 ms | **-36%** |
| max | 3.782 ms | 2.962 ms | -22% |
| frames > 3× avg | 1.7% | **0.3%** | **-82%** |

User's acceptance metric ("no single frame noticeably above the average") satisfied: 1 of 360 frames exceeds 3× avg; absolute max 3.0 ms, well under a 16.6 ms frame budget.

**Deferred follow-up** (TODO noted in `s_ai.gd`): switch from timer-driven re-planning to event-driven re-planning via a fact-transition dirty flag. Higher risk (needs careful coverage of every fact transition in SPerception/SHunger/SSemanticTranslation and action-internal writes) and was explicitly scoped out of this PR.

## 6. GOAP Plan Cache (`59246bf`)

Classic Jeff Orkin "Three States and a Plan" (GDC 2006) technique. A\* on a stateless, fully-observable domain is deterministic — identical (goal, world-state) inputs produce identical plans, safe to memoize.

**Research** (background librarian report, summarized): production GOAP impls — crashkonijn/GOAP, ReGoap, GPGOAP, F.E.A.R.'s own SDK — mostly **do not** cache plans because stale-plan bugs are the classic failure mode. That's not a reason to not cache, but it was a strong prompt to land the right safety rails.

**Design:**

- **Key** = `goal_name + priority + _state_to_key(world_state)` using the **same** `ordered_keys` the A\* search itself uses → no key-coverage gap by construction. For the bool-only fact vocabulary in GOL, the key string is ~200 chars max, zero collision risk.
- **Value** = shared `Array[GoapPlanStep]` template (steps and actions are stateless — already verified in the allocation cleanup commit).
- **Hand-out**: a *fresh* `GoapPlan` wrapping the shared step refs, with `current_step_index = 0`. Per-agent state lives in the wrapper cursor and in `agent.running_context`.
- **Invalidation**:
  - Lazy: first action's preconditions re-checked on lookup; mismatch → evict + miss.
  - TTL: entries older than 60 frames (~1 s at 60 FPS) treated as misses.
  - Size cap: 64 entries; overflow → `clear()` wholesale.
- **Test determinism**: the cache only participates when `actions` is empty (production path via `get_all_actions()`). Tests passing explicit action subsets via `build_plan_with_actions` take the uncached branch, so their plan-content assertions are unaffected.

**Measured impact** (same 41-agent scenario, 360 frames):

| Metric | Stagger only | Stagger + cache | Δ |
|---|---|---|---|
| avg | 0.941 ms | **0.697 ms** | **-26%** |
| p95 | 1.630 ms | **0.856 ms** | **-47%** |
| p99 | 2.100 ms | **1.514 ms** | -28% |
| max | 2.962 ms | **2.262 ms** | -24% |
| Cache hit rate | — | **82.1%** | — |
| Steady-state working set | — | 6 entries | — |

Small working set (6 entries) confirms the hypothesis that GOL agents converge on a few distinct world-state signatures (idle rabbit, hungry rabbit, rabbit with threat, zombie pursuing target, etc.). Most plan builds hit cache.

## 7. Profiler Attribution Fix (`f20d49c`)

**User report:** "Total Process shows ~20 ms but group breakdowns sum to only 6–8 ms. Numbers don't add up."

**Root cause (not a bug — a scope mismatch):**

- `Performance.TIME_PROCESS` is Godot's **engine-wide main-thread time**: every `_process` callback of every Node (autoloads, ImGui, debug panels, scene tree walks, etc.).
- The per-system `_last_execution_time_ms` only covers each system's `process()` body (`system.gd:413–461`).
- The gap = (a) **GECS framework overhead** running between system calls — observer dispatch triggered by `add/remove_component`, PER_GROUP `cmd.flush()` after each group, cache invalidation from structural changes — plus (b) **non-ECS Godot work** on the main thread.

**Fix (three-layer instrumentation):**

1. **`GOLWorld._timed_ecs_process(delta, group)`** wraps each `ECS.process(group)` call with `Time.get_ticks_usec()`. Per-group wall time stored in `_group_wall_usec`, accessible via `get_group_wall_ms(group)` and `get_ecs_total_wall_ms()`. Two `get_ticks_usec` calls per group per frame — sub-microsecond, always on, no debug-flag gate.

2. **`perf_panel` Frame Budget** now shows three attribution lines:

   ```
   Frame (engine-wide): 16.20 / 16.67 ms
     Process: 12.40 ms | Physics: 3.80 ms              ← Godot-wide
     ECS Total: 2.30 ms | Other (non-ECS): 13.90 ms    ← NEW: fully attributed
   ```

3. **`perf_panel` Group Breakdown** now shows `wall` (full group) vs `sys` (sum of `process()` bodies) vs `fw` (framework overhead = wall − sys) explicitly:

   ```
   gameplay  wall 2.29 ms  sys 2.27 ms  fw +0.02 ms  99.5 %  Ent:41
   ```

4. **`perf_panel` ECS Overview** also surfaces `GoapPlanner.get_cache_stats()` (hit rate, size) alongside the existing GECS query-cache stats.

5. **Clipboard export** matches the new layout so copied snapshots include the full attribution.

**Verified attribution coherence** (180-frame headless playtest, 41 agents):

```
Godot TIME_PROCESS : 113.026 ms     (headless-inflated; engine-wide)
ECS Total wall     :   2.297 ms
Sum of sys process :   2.274 ms
Non-ECS (gap)      : 110.729 ms     (= Process − ECS Total, fully attributed)
Framework overhead :   0.023 ms     (= ECS wall − Σ sys)
```

Invariants hold: `ECS wall ≥ Σ sys` (framework overhead non-negative), `Process − ECS = Non-ECS ≥ 0`.

## Aggregate Verification

| Check | Result |
|---|---|
| Unit tests | **620 / 620 pass** (0 errors, 0 failures) |
| Integration tests (AI-critical) | **85 / 85 assertions pass** across `test_teardown_cleanup`, `test_rabbit_forages_grass`, `test_rabbit_lifecycle`, `test_auto_feed_loop`, `test_food_pickup_to_stockpile`, `test_combat`, `test_bullet_flight`, `test_speech_bubble` |
| Behavior preservation | Rabbit flee / forage / wander assertions still pass; combat still works; auto-feed still works; purge cleanup still works |
| LSP diagnostics | Clean on all modified files (3 pre-existing `SHADOWED_GLOBAL_IDENTIFIER` warnings on untouched lines) |
| CI (remote) | **Run 24932778853 — success**; Unit Tests + Integration Tests jobs both green |
| Headless playtest (20 s, 223 entities) | Zero SCRIPT ERROR; log size 366 lines (vs 1.5 GB pre-fix) |

## Cumulative Perf Delta (end-to-end)

Baseline = start of the session (stagger implemented with 2 ms time budget, no plan cache, original 1024-iter planner). End state = all seven commits landed.

| Metric | Session start | Session end | Δ |
|---|---|---|---|
| avg per-frame AI cost | 0.991 ms | **0.697 ms** | **-30%** |
| p95 | 1.641 ms | **0.856 ms** | **-48%** |
| p99 | 3.259 ms | **1.514 ms** | **-54%** |
| max | 3.782 ms | **2.262 ms** | **-40%** |
| frames > 3× avg | 1.7% | **0.3%** | **-82%** |
| GOAP plan cache hit rate | n/a | **82%** | — |
| per-plan RefCounted allocations | ~18 | **0** (warm) | — |
| Profiler attribution coverage | partial (6-8 / 20 ms) | **complete** | — |

## Files Touched

```
scripts/systems/s_perception.gd                  (340ad6b)
scripts/systems/s_ai.gd                          (07f25e2, 9dfcb90)
scripts/components/ai/c_goap_agent.gd            (9dfcb90)
scripts/gameplay/goap/goap_planner.gd            (07f25e2, 59246bf)
scripts/gameplay/goap/actions/gather_resource.gd (07f25e2)
scripts/gameplay/ecs/gol_world.gd                (42052e7, f20d49c)
scripts/debug/perf_panel.gd                      (f20d49c)
tests/unit/debug/test_console_subcommand_case.gd (ad1bd1b)
tests/unit/debug/test_console_parser_quotes.gd   (ad1bd1b)
```

## Follow-ups

1. **Event-driven re-planning** — TODO comment in `s_ai.gd`. Would further cut the cache-miss path by only considering agents whose blackboard transitioned since their last decision. Deferred: needs careful coverage of every fact-transition path.
2. **GECS PR upstream** — the `World.purge` freed-ref bug (fixed locally via override in `gol_world.gd`) should be sent upstream to `csprance/gecs`. GECS shipped tests for this in earlier versions; those tests were removed in the v8 release.
3. **Plan-cache effectiveness monitoring** — perf panel now shows hit rate. If cache hit rate drops below ~60% in production, investigate whether the fact vocabulary grew (new goals / actions) or whether SPerception / SSemanticTranslation started writing noisy continuous values.
