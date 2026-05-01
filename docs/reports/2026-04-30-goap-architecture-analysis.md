# GOAP Decision & Execution Architecture Analysis

**Date:** 2026-04-30  
**Scope:** Current monolithic AI system architecture (SAI + GoapPlanner)  
**Purpose:** Inform refactoring plan to potentially split decision-making and execution into separate systems

---

## Executive Summary

GOL's GOAP system is currently **monolithic**: `SAI` (the AI system) handles both expensive decision-making (plan building via A* search) and cheap action execution in a single system. The architecture uses a **two-pass processing model** within each frame:

- **Pass 1** (cheap, unconditional): Every AI agent executes its current action via `process_action_tick()`, accumulates decision-ready time, and emits threat-state signals.
- **Pass 2** (rate-limited): At most 3 agents per frame perform `_process_decision_tick()` (goal selection, plan building, plan validation).

This design achieves **deterministic frame-time budgeting** (bounded at ~3ms per frame for AI) and **fairness** (round-robin scheduling prevents starvation of distant agents). Plan caching with a 60-frame TTL and size limits further reduce planning load.

---

## 1. How SAI Currently Handles Both Decision-Making and Execution

### Architecture Overview

SAI operates as a **unified controller** that manages the full AI lifecycle in a single `process()` method:

```
process(entities, delta)
  │
  ├─ Pass 1: Unconditional loop over all entities
  │  ├─ process_action_tick(entity, delta)        [Cheap per-frame action execution]
  │  ├─ _consume_tick_delta(entity, delta)         [Accumulate decision readiness]
  │  └─ _emit_threat_state_if_changed(entity)      [Reactive system signaling]
  │
  └─ Pass 2: Rate-limited loop over ready agents
     ├─ Sort entities by instance_id (stable ordering)
     ├─ Round-robin offset by _frame_counter (fairness)
     └─ For up to 3 agents/frame:
        └─ _process_decision_tick(entity, delta)   [Expensive planning]
```

### Decision Tick (Expensive, Capped at 3 per Frame)

When an agent's decision timer expires, `_process_decision_tick()` executes this sequence:

1. **Goal Selection** (`_select_active_goal_data`): Scan agent's goal array (sorted by priority descending), find highest-priority unsatisfied goal.
2. **Plan Build/Cache Hit** (`_try_build_plan`): Query GoapPlanner, which checks the plan cache. If miss, run A* search (bounded to 256 iterations max).
3. **Plan Validation** (`_needs_replan`): Check if current plan is still valid (goal unsatisfied? preconditions met? world state changed?).
4. **Action Sequencing** (`_start_next_action`): Pop the first action from the plan, call `on_plan_enter()`, initialize running context.
5. **Instant Action Chain** (`_process_instant_action_chain`): Execute "instant" actions (cost=0) synchronously in a guard loop, preventing plan stalls on zero-cost actions.

### Action Tick (Cheap, Runs Every Frame)

Every frame, **before** Pass 2 even runs, `process_action_tick()` is called for every agent:

- Calls `perform(entity, agent, delta, context)` on the current `running_action` if one exists.
- Sets `action_completed` flag when the action signals completion.
- Ensures no action's `perform()` is called twice in one frame (guards with `_last_action_tick_frame`).

**Cost:** ~20 µs per agent per frame (microseconds, not milliseconds).

### Integration: Interleaved Execution Loop

The two passes are **not sequential**—they interleave within the same frame:

```gdscript
for entity in entities:
    process_action_tick(entity, delta)           # Execute current action (cheap)
    _consume_tick_delta(entity, delta)           # Check if decision-ready (cheap)
    _emit_threat_state_if_changed(entity)        # Signal to UI, speech, etc. (cheap)

# Later, in Pass 2:
for entity in ready_for_decision:
    if _decisions_this_frame < MAX_DECISIONS_PER_FRAME:
        _process_decision_tick(entity, delta)    # Plan new action (expensive, capped)
```

This allows **action execution to continue** on agents not getting a decision tick this frame, creating the illusion of always-active agents while keeping per-frame cost deterministic.

---

## 2. How Actions Are Currently Registered (Global Pool vs Per-Agent)

### Action Registration: Global Pooled Architecture

**Actions are registered globally**, not per-agent:

```gdscript
// In GoapPlanner.get_all_actions():
if _cached_action_instances.is_empty():
    var action_files := ResourceLoader.list_resources("res://scripts/gameplay/goap/actions/")
    for file: String in action_files:
        if file.ends_with(".gd"):
            var action_class = load(file)
            _cached_action_instances.append(action_class.new())
```

**Key facts:**

- **Loaded once** at first planner usage (lazy init).
- **Shared across all agents** of all types (rabbits, zombies, workers, player).
- **Stateless instances**: Each `GoapAction` subclass maintains only exported properties (`action_name`, `cost`, `preconditions`, `effects`), no instance-specific mutable state during planning.
- **Cloned into plans**: When a plan is built, actions are **not** referenced directly; instead, a `GoapPlanStep` records the action instance and a `context` dict (plan-specific state like target position, enemy reference).

### Action Pool Size & Performance

**Current pool:** ~15–20 action types loaded at startup (one of each `.gd` file found in `/actions/`).

**Planning cost:** During A* search, every state expansion considers all actions in the pool:
- Check preconditions (dictionary lookup, O(# preconditions) ≈ 2–5 comparisons)
- Simulate effects (create new world state copy, apply deltas)
- Estimate heuristic distance

With 256 iteration cap on A* per plan and 3 decision ticks per frame, the total A* work is **bounded** even with a large action pool.

### Per-Agent Configuration

Agents do **not** have per-agent action visibility. Instead:

- **Goal filtering** is per-agent (each agent has its own `goals: Array[GoapGoal]`).
- **World state filtering** is per-agent (each agent maintains its own `world_state: GoapWorldState` with facts like `has_target`, `is_hungry`, `build_done`).

This creates implicit per-agent action selection: an action whose preconditions depend on facts only a specific agent type sets will never be selected for other agent types. For example:

- Zombie actions check `has_target` (set by zombie perception systems).
- Worker actions check `has_build_site` (set by worker perception systems).
- Rabbit actions check `is_hungry` (set by hunger system).

**No explicit deny-list or capability bits exist.** The system relies on world state isolation and precondition matching.

---

## 3. How Goals Are Configured Per Agent Type

### Goal Configuration: Per-Agent, Resource-Based

Goals are **not** global. Each agent has its own goal array:

```gdscript
// In CGoapAgent component:
@export var goals: Array[GoapGoal] = []  // Per-agent instance
```

### Goal Definition Pattern

Goals are `.tres` (Resource) files, loaded explicitly by agent authoring or scene setup:

**Example goal resource (`goap_goal_build.tres`):**
```gdscript
class_name GoapGoal_Build
extends GoapGoal
## Build goal — worker seeks construction tasks when ghosts exist.
## Satisfied when build_done == true.
## Priority: 15 (below Work at 20, below FeedSelf at 50, below Survive at 100).
```

**Goal properties:**
```gdscript
class_name GoapGoal
extends Resource

@export var goal_name: String = ""
@export var priority: int = 0
@export var desired_state: Dictionary[String, bool] = {}  # { "build_done": true, ... }

func is_satisfied(world_state: Dictionary[String, bool]) -> bool:
    for key in desired_state:
        if world_state.get(key, false) != desired_state[key]:
            return false
    return true
```

### Agent Type Goal Assignment

**Currently:** Goals are assigned at entity creation time, likely via:

1. **Hardcoded in authoring tools** (e.g., `authoring_pawn.gd` for worker NPCs), or
2. **Loaded from scene files** (e.g., an enemy scene references a pre-built goal array), or
3. **Dynamically added by spawn scripts** (e.g., `SEnemySpawn` adds zombie goals at spawn time).

**Search result:** No explicit "agent type" or "agent capability def" file exists. Goals are bundled with individual agents or configured per-scene.

### Goal Priority System

Goals are **priority-ordered**; during each decision tick:

```gdscript
// In _select_active_goal_data():
var sorted_goals: Array[GoapGoal] = agent.get_sorted_goals()  // Sorted by priority DESC
for goal in sorted_goals:
    if not goal.is_satisfied(world_state):
        return goal  // First unsatisfied goal = active goal
```

**Priority hierarchy (example):**
- Survive: 100 (highest—flee from threats)
- FeedSelf: 50 (feed before work)
- Work: 20 (resource gathering, construction)
- Build: 15 (construction tasks)
- Idle: 0 (default fallback)

### Goal Tuning & Re-election

If a higher-priority goal becomes unsatisfied mid-plan:

```gdscript
// In _needs_replan():
if agent.plan.goal != active_goal:
    return "Higher priority goal activated"  // Trigger replan
```

The agent **abandons the current plan** and rebuilds for the new goal on the next decision tick.

---

## 4. The Decision Tick Frequency and Scheduling Mechanism

### Tick Interval: Per-Agent, Configurable

Each agent has an **independent timer** (`_update_timer` in CGoapAgent):

```gdscript
@export var update_interval: float = 0.15  // Default: 150 ms between decision ticks
```

### Accumulation & Consumption (Pass 1)

```gdscript
// In process():
for entity in entities:
    process_action_tick(entity, delta)                    // Action execution
    var elapsed_delta := _consume_tick_delta(entity, delta)  // Timer increment
    if elapsed_delta > 0.0:
        ready_for_decision.append(entity)                // Agent ready this frame
```

`_consume_tick_delta()` increments `_update_timer`, returns the overflow when `_update_timer >= update_interval`:

```gdscript
var elapsed_delta = agent._update_timer
if elapsed_delta >= agent.update_interval:
    agent._update_timer = agent._update_interval  // Clamp, don't reset to 0
    # This clamp prevents "fast" frames from accelerating future decision ticks
    return elapsed_delta
return 0.0
```

### Level of Detail (LOD): Distance-Based Throttling

Agents farther from the player get longer tick intervals to reduce CPU load:

```gdscript
const AI_LOD_NEAR_DISTANCE: float = 64.0     // Close: full update rate
const AI_LOD_FAR_DISTANCE: float = 192.0     // Far: reduced update rate
const AI_LOD_MID_INTERVAL_MULTIPLIER: float = 2.0      // Mid-distance: 2× slower
const AI_LOD_FAR_INTERVAL_MULTIPLIER: float = 4.0      // Far distance: 4× slower
```

**In `_get_effective_tick_interval()`:**
- If distance ≤ NEAR: use `update_interval` (e.g., 150 ms)
- If NEAR < distance ≤ FAR: use `update_interval * MID_MULTIPLIER` (e.g., 300 ms)
- If distance > FAR: use `update_interval * FAR_MULTIPLIER` (e.g., 600 ms)

This means a distant zombie might only get a decision tick every ~400 ms instead of every 150 ms, but its action tick (movement, combat) still runs **every frame** at full speed.

### Rate Limiting (Pass 2): Hard Cap & Fairness

Even if 10 agents are ready this frame, only **3 can run a decision tick**:

```gdscript
const MAX_DECISIONS_PER_FRAME: int = 3

// In Pass 2:
if _decisions_this_frame >= MAX_DECISIONS_PER_FRAME:
    # Clamp _update_timer to "just ready" so agent gets first pick next frame
    agent._update_timer = _get_effective_tick_interval(...)
    continue  # Skip this agent
```

### Fairness Mechanism: Round-Robin Scheduling

To prevent the same agents from monopolizing planning every frame:

```gdscript
ready_for_decision.sort_custom(_compare_by_instance_id)  // Stable sort
var start_offset: int = _frame_counter % ready_for_decision.size()

for i in range(ready_for_decision.size()):
    var entity = ready_for_decision[(start_offset + i) % ready_for_decision.size()]
    # Process in rotated order
```

**Effect:** If agents [A, B, C, D] are ready and we can process 3 per frame:
- Frame N: Process [A, B, C], defer [D]
- Frame N+1: Process [B, C, D], defer [A]  (rotated by 1)
- Frame N+2: Process [C, D, A], defer [B]  (rotated by 2)

### Decision Frequency in Practice

**At 60 FPS with 40 agents:**
- Each agent typically waits 40 / 3 ≈ 13–14 frames between decision ticks.
- At 150 ms default interval: ~13 frames × 16.7 ms = 217 ms actual latency (close to the 150 ms configured).
- Maximum threat-reaction latency is **bounded to ~14 frames** (233 ms), ensuring responsive combat behavior.

### Time Budget Safety Net

A secondary cap exists to handle pathological A* runs:

```gdscript
const DECISION_FRAME_HARD_BUDGET_MS: float = 3.0  // Hard wall, safety net

if _decision_ms_this_frame >= DECISION_FRAME_HARD_BUDGET_MS:
    continue  # Skip remaining decision ticks for the frame
```

This is **rarely hit** because `MAX_DECISIONS_PER_FRAME=3` typically keeps total planning cost under 1–2 ms per frame.

---

## 5. What Would Change to Split Decision/Execution Into Two Systems

### Proposed Architecture

**Current (Monolithic):**
```
SAI.process()
  ├─ Pass 1: Execute all actions + identify ready agents
  └─ Pass 2: Plan for up to 3 ready agents
```

**Proposed (Separated):**
```
SPlanner.process()                      [New system, "gameplay" group]
  └─ Plan for up to N agents/frame (rate-limited)

SExecutor.process()                     [New system, "gameplay" group]
  └─ Execute all actions every frame (no change to this cost)
```

### Changes Required

#### 1. **Extract Pass 2 Logic into SPlanner**

Create a new system `SPlanner` that **only** handles decision-making:

```gdscript
class_name SPlanner
extends System

func _ready() -> void:
    group = "gameplay"

func query() -> QueryBuilder:
    return q.with_all([CGoapAgent, CMovement, CTransform])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    # Only Pass 2 logic from SAI:
    # - Identify agents with stale plans or no plan
    # - For each ready agent (up to 3 per frame):
    #   - _process_decision_tick()
```

**Deleted from SAI:** All code in Pass 2 (goal selection, plan building, action sequencing).

#### 2. **Extract Pass 1 Execution into SExecutor (or Keep in SAI)**

Option A: **Create SExecutor** (new system for action execution only)
```gdscript
class_name SExecutor
extends System

func _ready() -> void:
    group = "gameplay"

func query() -> QueryBuilder:
    return q.with_all([CGoapAgent, CMovement, CTransform])

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    # Current Pass 1 logic:
    for entity in entities:
        process_action_tick(entity, delta)
        _emit_threat_state_if_changed(entity)
```

Option B: **Keep in SAI, trim to execution only**
```gdscript
class_name SAI
extends System

func process(entities: Array[Entity], _components: Array, delta: float) -> void:
    # Only Pass 1:
    for entity in entities:
        process_action_tick(entity, delta)
        _consume_tick_delta(entity, delta)  # Keep this for logging/introspection
        _emit_threat_state_if_changed(entity)
```

#### 3. **Decouple Timer & Decision Readiness State**

**Problem:** Pass 1 currently accumulates `_update_timer` and populates a `ready_for_decision` array for Pass 2. If we split systems, `SPlanner` won't have access to the readiness list from `SExecutor`.

**Solution:** Store decision readiness on the component itself.

```gdscript
// In CGoapAgent:
var _update_timer: float = 0.0
var _is_decision_ready: bool = false        # NEW: populated by executor, read by planner

// In SExecutor.process():
for entity in entities:
    process_action_tick(entity, delta)
    var elapsed := _consume_tick_delta(entity, delta)
    agent._is_decision_ready = (elapsed > 0.0)

// In SPlanner.process():
for entity in entities:
    agent := entity.get_component(CGoapAgent)
    if agent._is_decision_ready:
        # Consider for planning (up to 3/frame)
        _process_decision_tick(entity, ...)
        agent._is_decision_ready = false
```

#### 4. **Replicate GoapPlanner & LOD Logic**

Both systems need access to:
- **GoapPlanner** instance (can remain shared, or create separate instances)
- **LOD thresholds** and player position cache
- **Threat state tracking** (`_known_threat_states`)

**Minimal approach:** Move these into a shared **singleton** or **service** (e.g., `ServiceAI`).

```gdscript
// New service class:
class_name ServiceAI
extends RefCounted

static var _instance: ServiceAI
static var _planner: GoapPlanner
static var _player_position: Vector2
static var _known_threat_states: Dictionary

static func get_planner() -> GoapPlanner:
    if _planner == null:
        _planner = GoapPlanner.new()
    return _planner

static func set_player_position(pos: Vector2) -> void:
    _player_position = pos

static func get_effective_tick_interval(...) -> float:
    # LOD logic moved here
```

Then in `SExecutor` and `SPlanner`:
```gdscript
var _service_ai: ServiceAI

func _ready():
    _service_ai = ServiceAI.get_instance()

func process(...):
    var planner = _service_ai.get_planner()
    # ...
```

#### 5. **System Ordering & Dependencies**

**Current order** (no dependency, single system):
```
SAI → [acts on all agents]
```

**Proposed order** (sequential, executor first):
```
SExecutor → [updates _is_decision_ready, maintains running actions]
SPlanner → [checks _is_decision_ready, builds/updates plans]
```

**In the engine:** Both systems are in the `"gameplay"` group, but query the same entities. The ECS framework processes systems in registration order, so:

```gdscript
// In GOLWorld or system loader:
ECS.world.register_system(SExecutor)  # Runs first each frame
ECS.world.register_system(SPlanner)   # Runs second each frame
```

If the system loader discovers systems automatically (as noted in AGENTS.md), ensure `SExecutor` is registered before `SPlanner` (e.g., via alphabetical order: `s_executor.gd` before `s_planner.gd`).

#### 6. **Threat State Signaling**

Both systems currently emit `threat_state_changed` signals. After split:

- **SExecutor** emits immediately when threat state changes (stays as-is).
- **SPlanner** does not emit (remove `_emit_threat_state_if_changed` from planning).

Or, centralize threat emission into a third micro-system:
```gdscript
class_name SThreatDetector
extends System

func process(entities: Array[Entity], ...):
    for entity in entities:
        _emit_threat_state_if_changed(entity)
```

#### 7. **Agent Reset & State Cleanup**

Functions like `_reset_agent()` are called by both decision logic and action execution. After split, they should be **called from SPlanner** (after plan invalidation) and **referenced from SExecutor** (if action completion/failure requires cleanup).

**Option:** Move `_reset_agent()` into a shared service or keep both systems coupled on this function (define it in a utility class `GoapAgentUtils`).

#### 8. **Testing & Profiling**

The profiling hooks in SAI will need to be split:

- **SExecutor profiling:** Track action execution time, action counts.
- **SPlanner profiling:** Track decision tick count, replan reasons, A* iteration counts (already done in GoapPlanner).

```gdscript
// SExecutor:
var _profile_action_count: int = 0
var _profile_action_time_ms: float = 0.0

// SPlanner:
var _profile_decision_count: int = 0
var _profile_decision_time_ms: float = 0.0
```

---

## Estimated Effort & Risk

### Effort Breakdown

| Task | Complexity | Lines of Code |
|------|-----------|--------------|
| Extract Pass 2 into SPlanner | Low | ~250 lines (copy + trim SAI) |
| Extract Pass 1 into SExecutor | Low | ~100 lines |
| Add `_is_decision_ready` to CGoapAgent | Low | 1–2 lines |
| Create ServiceAI singleton | Low | ~50 lines |
| Update system registration order | Low | 0–5 lines (if auto-discovery) |
| Split/update profiling | Low | ~30 lines |
| **Testing & validation** | Medium | 4–8 hours (integration tests, perf benchmarking) |
| **Total** | **Low–Medium** | ~500 lines + testing |

### Risk Assessment

**Low Risk:**
- No algorithmic changes; only structural refactoring.
- Both systems query the same entities and call the same helper functions.
- Existing plan cache and LOD logic remain unchanged.

**Medium Risk:**
- **System ordering:** If SPlanner runs before SExecutor, agents won't have `_is_decision_ready` set yet. Must verify registration order carefully.
- **Threat signaling latency:** Splitting threat detection into a third system could introduce a one-frame delay. Test with reactive speech bubbles.
- **Shared state:** GoapPlanner, player position cache, and `_known_threat_states` must be thread-safe if systems run in parallel (unlikely in Godot single-threaded mode, but worth noting).

**Mitigation:**
- Add a unit test for system order verification.
- Profile threat-state emission latency before/after split.
- Document shared state ownership in code comments.

---

## Recommendations

### Before Refactoring

1. **Profile current system** to establish a baseline for frame time, decision count per frame, and replan frequency. Use SAI's profiling API (`enable_profiling()`, `get_profile_frame_data()`).

2. **Document goal/action mappings** for all agent types (zombie, rabbit, worker, player, etc.). Create an AGENTS.md section mapping agent type → goal priorities → action preconditions.

3. **Define success criteria:**
   - Frame time budget remains ≤ 3 ms for AI (no regression).
   - Threat-reaction latency ≤ 14 frames (no regression).
   - Code complexity decreases (easier to test, modify per-agent goals).

### After Refactoring

1. **Add integration tests** to verify:
   - Agent still selects highest-priority unsatisfied goal.
   - Plan executes in correct order.
   - Replanning triggers on goal/world-state changes.
   - System ordering produces correct output (decision before execution doesn't break sequencing).

2. **Add per-system profiling** to SExecutor and SPlanner to track time and decision counts independently.

3. **Consider event-driven replanning** (listed as TODO in SAI, line 42). With systems now split, it's easier to add a dirty-flag system:
   ```
   SPerceptionSystem → updates world state → sets CGoapAgent._world_dirty
   SPlanner → checks _world_dirty, only replans if set or plan is stale
   ```

---

## Conclusion

The current monolithic SAI system is well-designed for fairness and deterministic performance. Splitting decision-making and execution into separate systems is **technically straightforward** (low effort) and would improve **code clarity and testability** without algorithmic changes.

The refactoring is **low-risk** provided system ordering is verified and shared state (GoapPlanner, LOD, threat tracking) is centralized into a service layer. Estimated effort is **~500 lines of code + integration testing**, achievable in **2–3 days** of focused work.

A post-refactoring follow-up to implement event-driven replanning (triggered by world-state changes rather than fixed timers) would be a natural next optimization, further reducing unnecessary planning work for stable agents.
