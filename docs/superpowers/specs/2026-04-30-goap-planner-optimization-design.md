# GOAP Planner Performance Optimization Design

## Problem Statement

The GOAP planner has severe performance issues that block AI system scaling. Adding building-related actions (Build, etc.) caused measurable degradation. Previous mitigations (plan cache, per-frame decision cap) mask the problem without solving root causes.

### Eval Baseline (2026-04-30, 12 agents, 60s)

| Metric | Value | Budget | Status |
|--------|-------|--------|--------|
| avg_search_time_us | 12,862 | 100 | FAIL (128x over) |
| avg_iterations | 246.3 | 80 | FAIL (打满 256 上限) |
| cache_hit_rate | 3.2% | 75% | FAIL |
| plan_found_rate | 3.8% | 85% | FAIL |
| avg_decision_time_ms | 2.80 | 1.00 | FAIL |
| p99_decision_time_ms | 18.26 | 3.00 | FAIL |
| thrash_rate | 1.2% | 5% | PASS |

**Root cause**: `feed_self` goal accounts for 93.6% of planning calls (1257/1343), with 0.16% success rate and avg 255 iterations. All three feeding paths are gated behind system-provided perception facts (`sees_grass`, `sees_food_pile`, `sees_harvestable`) that no GOAP action can produce. The planner exhausts 256 iterations proving an unsolvable problem, then repeats every 0.2s because failures aren't cached.

### Compounding Factors

1. **Wander effect bug** — `wander.gd` sets `effects = { has_threat: true }` instead of `{ is_patrolling: true }`, injecting a full combat sub-tree into every search from non-threat states. Wastes 50-100 iterations per search on irrelevant branches.
2. **Global action pool** — All 22 actions are visible to all agent types. A rabbit sees Build, DepositResource, AttackMelee, etc. Branching factor is 7-10 when it should be 2-4.
3. **Heuristic degrades to Dijkstra** — `_calculate_heuristic()` counts unsatisfied goal facts. Most GOL goals have one desired key, so h is always 0 or 1. A* loses all directional signal.
4. **No negative cache** — Failed plans are never cached. Each tick repeats a full 256-iteration search.
5. **No SAI backoff** — SAI retries unsatisfied goals every 0.2s with no penalty for consecutive failures.

---

## Non-Goals

- Not replacing GOAP with a different AI architecture (behavior trees, utility AI, etc.)
- Not changing game design or goal/action semantics (beyond fixing the Wander bug)
- Not implementing hierarchical GOAP (Phase 4 is documented as future direction only)
- Not optimizing action execution performance (this spec targets planning/decision only)

---

## Design

Four phases, each validated independently via `gol test goap --json`. Phases 1-3 are implementation scope. Phase 4 is a documented future direction.

### Phase 1 — Eliminate Invalid Searches

Goal: reduce planning calls by 90%+ and eliminate wasted iterations on unsolvable problems.

#### 1a. Fix Wander Effect Bug

**File:** `scripts/gameplay/goap/actions/wander.gd`

Change effects from `{ "has_threat": true }` to `{ "is_patrolling": true }`.

Impact: eliminates artificial combat sub-tree injection during non-combat planning. Saves 50-100 iterations per search that currently explores ChaseTarget → AttackMelee/Ranged branches from Wander.

#### 1b. Per-Agent Action Lists

**Current:** `GoapPlanner.get_all_actions()` returns a single global pool of all 22 actions. Every agent's search branching factor includes actions irrelevant to that agent type.

**Change:** Add `@export var allowed_actions: Array[String]` to `CGoapAgent`. The planner filters the global action pool against this whitelist before search. If `allowed_actions` is empty, fall back to the global pool (backward compatible).

Action assignments per agent type:

| Agent Type | Actions | Count |
|-----------|---------|-------|
| rabbit | EatGrass, MoveToGrass, Flee, Wander | 4 |
| Worker | FindWorkTarget, MoveToResourceNode, GatherResource, MoveToStockpile, DepositResource, Build, EatGrass, MoveToGrass, MoveToHarvestable, HarvestBush | 10 |
| Guard | Patrol, ReturnToCamp, ChaseTarget, AttackMelee, AttackRanged, AdjustShootPosition, Defend, Flee | 8 |
| Guard_Healer | Patrol, ReturnToCamp, ChaseTarget, AttackMelee, Defend, Flee | 6 |
| enemy_* | ChaseTarget, AttackMelee, AttackRanged, AdjustShootPosition, Flee, Wander | 6 |
| ComposerNPC | MarchToCampfire, Wander, Idle | 3 |

The planner's `_plan_for_goal()` accepts an `actions: Array[GoapAction]` parameter (already exists). The change is in `build_plan_for_goal()` which resolves the agent's filtered action list before calling `_plan_for_goal()`.

**Branching factor reduction:** rabbit 7-10 → 2-3, Worker 7-10 → 4-5, Guard 7-10 → 3-4.

#### 1c. Goal Viability Gate

**Problem:** The planner cannot detect unsolvable problems before entering A* search. Goals like `feed_self` are gated behind system-provided perception facts that no action can produce.

**Solution:** Add a `viability_facts` field to `GoapGoal`:

```gdscript
## At least one of these facts must be true in world state for this goal
## to be worth planning. If all are absent, skip planning entirely.
## Empty array = always viable (no gate).
@export var viability_facts: Array[String] = []
```

The SAI checks viability before calling `build_plan_for_goal()`. This is an O(K) dictionary lookup where K = number of viability facts (typically 1-3).

Viability fact assignments:

| Goal | viability_facts | Rationale |
|------|----------------|-----------|
| feed_self | `["sees_grass", "sees_food_pile", "sees_harvestable"]` | All three feeding paths require one of these perception facts |
| Work | `["sees_resource_node"]` | Work chain starts with FindWorkTarget which needs resource visibility |
| Build | `[]` (always viable) | Build action has no system-fact preconditions |
| Survive / survive_on_sight | `[]` (always viable) | Combat goals should always be plannable when activated |
| ClearThreat / EliminateThreat | `[]` (always viable) | Same as Survive |
| Wander | `[]` (always viable) | Fallback goal, always viable |
| PatrolCamp / GuardDuty | `[]` (always viable) | Guard duties always viable |

#### 1d. Negative Plan Cache

**Current:** Only successful plans are cached. Failed plans repeat full 256-iteration search.

**Change:** Add `_negative_cache: Dictionary[String, int]` to `GoapPlanner`. Key = same cache key format as positive cache. Value = frame number when the failure was recorded.

```
On plan failure:
  _negative_cache[cache_key] = Engine.get_process_frames()

On plan request:
  if cache_key in _negative_cache:
      frames_since = current_frame - _negative_cache[cache_key]
      if frames_since < NEGATIVE_CACHE_TTL:
          return null  # skip search
      else:
          _negative_cache.erase(cache_key)  # expired, retry
```

**TTL:** 30 frames (0.5s at 60fps). Short enough that world state changes (new perception facts) will be picked up quickly. Long enough to prevent the same unsolvable query from running multiple times per second.

**Size limit:** Same 64-entry cap as positive cache. LRU eviction when full.

**Profiling:** Negative cache hits tracked separately in eval metrics (`neg_cache_hits` counter).

#### 1e. SAI Goal Backoff

**Current:** SAI retries every unsatisfied goal every decision tick (0.15-0.5s depending on LOD), regardless of failure history.

**Change:** Track consecutive planning failures per goal in `CGoapAgent`:

```gdscript
var _goal_fail_counts: Dictionary[String, int] = {}
var _goal_backoff_until: Dictionary[String, int] = {}  # frame number
```

Backoff schedule:
- 1st failure: wait 30 frames (0.5s)
- 2nd failure: wait 60 frames (1.0s)
- 3rd+ failure: wait 120 frames (2.0s)
- Cap: 300 frames (5.0s)

**Reset condition:** When any viability fact for the backed-off goal changes from false to true in world state, reset that goal's backoff counter to 0. Detection mechanism: SGoalDecision (or s_ai.gd before the Phase 3 split) stores the previous-tick value of each agent's viability facts in a `_prev_viability: Dictionary[String, bool]`. On each decision tick, compare current vs previous. If any fact flipped false→true, clear all backoff state for goals that list that fact in their `viability_facts`. This adds O(V) work per decision tick where V = total viability facts across all goals (typically 5-8).

---

### Phase 2 — Heuristic Upgrade

Goal: reduce search iterations from ~246 to 5-15 for solvable problems, and immediately prune unsolvable branches.

#### 2a. Delete-Relaxation Heuristic

Replace the current "count unsatisfied conditions" heuristic with a delete-relaxation (FF-style) heuristic.

**Algorithm:**

```
func _calculate_heuristic(goal, state, actions) -> float:
    relaxed = state.duplicate()
    layers = 0
    
    while not goal.is_satisfied(relaxed):
        new_facts = false
        for action in actions:
            if action.preconditions_met(relaxed):
                for key in action.effects:
                    if not relaxed.has(key) or relaxed[key] != action.effects[key]:
                        relaxed[key] = action.effects[key]
                        new_facts = true
        layers += 1
        if not new_facts:
            return INF  # unreachable — prune
    
    return float(layers)
```

**Properties:**
- **Admissible:** Relaxed world is strictly easier than real world (no deletions). Relaxed solution cost ≤ real solution cost. A* optimality preserved.
- **Informative:** Distinguishes "2 steps away" from "5 steps away", unlike current h=0/1 binary. Gives A* genuine directional signal.
- **Unreachability detection:** If the relaxed expansion reaches a fixpoint without satisfying the goal, returns INF. The planner can immediately prune that branch or abort the entire search.

**Performance:** With per-agent action lists (Phase 1b), each relaxation loop iterates over 3-10 actions and 15-26 bool keys. Worst case: 6 layers × 10 actions × 26 keys = 1560 operations. At ~10ns per bool check, that's ~15μs per heuristic call. Acceptable given current 13ms per search.

**Optimization — achievable-facts index:**

Precompute at planner init: for each bool fact, which actions can produce it.

```gdscript
var _fact_achievers: Dictionary[String, Array[GoapAction]]
# e.g., "is_fed" → [EatGrass, HarvestBush, PickupFood]
```

During relaxation, instead of scanning all actions each layer, only check actions whose effects include a fact not yet in the relaxed state. Reduces inner loop from O(A) to O(relevant actions).

**Integration with existing heuristic:**

The `_calculate_heuristic()` signature changes to include the actions array:

```gdscript
# Before:
func _calculate_heuristic(goal: GoapGoal, state: Dictionary[String, bool]) -> float

# After:
func _calculate_heuristic(goal: GoapGoal, state: Dictionary[String, bool], actions: Array[GoapAction]) -> float
```

All call sites in `_plan_for_goal()` updated to pass the (already available) filtered action list.

#### 2b. Reduce MAX_ITERATIONS to 32

**Precondition:** Phase 1 + 2a must be validated first. Only safe after confirming that solvable plans are found in <15 iterations with the new heuristic.

Change `MAX_ITERATIONS` from 256 to 32. This serves as a safety net — if any search exceeds 32 iterations, it's likely unsolvable or pathological, and should fail fast rather than burn CPU.

The eval suite budget `avg_iterations_max` drops from 80 to 20 to match.

---

### Phase 3 — Architecture Split: Decision / Execution

Goal: separate `s_ai.gd` into two independent systems for cleaner profiling, testing, and future optimization.

#### Current Architecture

`s_ai.gd` runs a two-pass loop in `process()`:
- **Pass 1 (every frame):** Execute `running_action.perform(delta)` for all agents with active plans
- **Pass 2 (rate-limited):** For agents needing decisions, run goal selection + planning (max 3/frame, 3ms budget)

Both passes share state through `CGoapAgent` component fields.

#### New Architecture

Two new systems replace `s_ai.gd`:

**SPlanExecution** (runs every frame, high priority)
- Query: entities with `CGoapAgent` where `running_action != null`
- Responsibilities:
  - Call `running_action.perform(delta)`
  - Handle action completion → advance plan or mark agent as needs_decision
  - Handle action failure → mark agent as needs_decision
  - Validate current plan's preconditions → invalidate if world changed
  - Consume `pending_plan` from decision system → call `on_plan_enter()`, begin execution
- Does NOT call the planner or do goal selection

**SGoalDecision** (runs rate-limited, after SPlanExecution)
- Query: entities with `CGoapAgent` where `needs_decision == true`
- Responsibilities:
  - Viability gate check (Phase 1c)
  - Backoff check (Phase 1e)
  - Goal selection (priority-sorted, skip satisfied goals)
  - Call `GoapPlanner.build_plan_for_goal()` with agent's filtered action list
  - Write result to `CGoapAgent.pending_plan` (consumed by SPlanExecution next frame)
- Rate limiting: MAX_DECISIONS_PER_FRAME = 3, DECISION_FRAME_HARD_BUDGET_MS = 3.0
- LOD-based update intervals preserved

**CGoapAgent changes:**

```gdscript
# New fields
var pending_plan: GoapPlan = null       # Written by SGoalDecision, consumed by SPlanExecution
var needs_decision: bool = true         # Set by SPlanExecution when plan completes/fails
```

**1-frame plan delivery latency:** A plan produced by SGoalDecision in frame N is consumed by SPlanExecution in frame N+1. At 60fps this is 16ms — negligible compared to the 0.15-0.5s decision interval.

**Eval tool adaptation:** Report two separate metric groups:

```
Execution:
  actions/frame, action_time_avg, action_time_p99

Decision:
  decisions/frame, decision_time_avg, decision_time_p99, planning_time_avg
```

The existing scheduling metrics (`avg_decision_time_ms`, `p99_decision_time_ms`) map directly to the new SGoalDecision metrics.

---

### Phase 4 — Future Direction: Hierarchical Decision Making (Not In Scope)

Documented here for future reference. Not implemented in this spec.

When action count grows to 40+ or goal interdependencies become complex, introduce two decision layers:

```
Strategic Layer (rule-based, O(1)):
  "What should I be doing?" → selects goal category (feed/fight/work/idle)
  Runs every 1-5 seconds
  No planner involvement

Tactical Layer (GOAP A*):
  "How do I accomplish this goal?" → plans action chain
  Runs on demand when strategic layer selects a goal
  Uses Phase 2 heuristic with per-agent action lists
```

**Trigger condition:** Phase 1-3 complete, eval data shows goal selection itself (not planning) is a bottleneck.

---

## Action Catalog Reference

Full action table as of 2026-04-30. The eval reports 22 registered actions (`available_action_count: 22`); the table below includes 26 known action definitions — 4 may be defined but not yet registered in the global pool (AdjustAttackPosition, Defend, React, Idle). Per-agent action lists (Phase 1b) should reference only registered actions.

| Action | Cost | Preconditions | Effects |
|--------|------|---------------|---------|
| EatGrass | 1.0 | `adjacent_to_grass` | `is_fed` |
| MoveToGrass | 1.0 | `sees_grass` ★ | `adjacent_to_grass` |
| HarvestBush | 1.0 | `adjacent_to_harvestable` | `is_fed` |
| MoveToHarvestable | 1.0 | `sees_harvestable` ★ | `adjacent_to_harvestable` |
| PickupFood | 1.0 | `adjacent_to_food_pile` | `is_fed` |
| MoveToFoodPile | 1.0 | `sees_food_pile` ★ | `adjacent_to_food_pile` |
| FindWorkTarget | 1.0 | `sees_resource_node` ★ | `has_work_target` |
| MoveToResourceNode | 1.0 | `has_work_target` | `adjacent_to_resource_node` |
| GatherResource | 1.0 | `adjacent_to_resource_node` | `has_gathered_resource` |
| MoveToStockpile | 1.0 | `sees_stockpile` ★ | `adjacent_to_stockpile` |
| DepositResource | 1.0 | `adjacent_to_stockpile`, `has_gathered_resource` | `has_delivered` |
| Build | 1.0 | (none) | `build_done` |
| ChaseTarget | 1.0 | `has_threat` | `is_threat_in_attack_range`, `ready_melee_attack` |
| AttackMelee | 1.0 | `has_threat`, `ready_melee_attack` | `has_threat: false`, `is_safe` |
| AttackRanged | 1.0 | `has_threat`, `ready_ranged_attack` | `has_threat: false`, `is_safe` |
| AdjustShootPosition | 1.0 | `has_threat`, `has_weapon`, `attack_range` | `ready_ranged_attack` |
| AdjustAttackPosition | 1.0 | `has_threat`, `ready_melee_attack` | `ready_melee_attack` |
| Defend | 1.0 | `has_threat`, `ready_melee_attack` | `is_threat_contained` |
| React | 1.0 | `has_threat` | `reacted_to_threat` |
| Search | 5.0 | `heard_threat` ★ | `found_threat` |
| Flee | 1.0 | `is_low_health` ★ | `is_safe` |
| Rest | 10.0 | `is_low_energy` ★ | `is_rested` |
| Wander | 10.0 | (none) | `is_patrolling` (post-fix) |
| MarchToCampfire | 10.0 | (none) | `at_campfire` |
| Patrol | 1.0 | (none) | `is_patrolling` |
| Idle | 10.0 | (none) | `is_idle` |

★ = system-provided fact (written by perception/health/energy systems, not producible by any GOAP action)

---

## Verification Strategy

Run `gol test goap --json --duration=60` after each phase. Compare against baseline:

| Metric | Baseline | Phase 1 Target | Phase 2 Target | Phase 3 Target |
|--------|----------|---------------|---------------|---------------|
| avg_search_time_us | 12,862 | < 2,000 | < 100 | < 100 |
| avg_iterations | 246.3 | < 100 | < 15 | < 15 |
| cache_hit_rate | 3.2% | > 50% | > 75% | > 75% |
| plan_found_rate | 3.8% | > 60% | > 85% | > 85% |
| p99_decision_time_ms | 18.26 | < 5.0 | < 3.0 | < 3.0 |
| avg_decision_time_ms | 2.80 | < 1.5 | < 1.0 | < 1.0 |
| thrash_rate | 1.2% | < 5% | < 5% | < 5% |

Phase 3 targets are same as Phase 2 — the architecture split should not regress performance. The split enables better profiling granularity (separate decision vs execution metrics) for future optimization.

### Known Issue: Patrol Action

`patrol.gd` always returns `false` from `perform()`, never completing. Effects declare `is_patrolling: true` but are never applied. This violates the GOAP completion contract. Fix is out of scope for this spec but should be tracked separately.
