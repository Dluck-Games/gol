# GOAP Three-Layer Architecture & Planner Optimization Design

## Problem Statement

The GOAP AI system has a fundamental architecture problem that causes severe performance degradation and blocks scaling to complex NPC behaviors. Adding a few building-related actions pushed the planner past its limits — but the root cause isn't "too many actions." It's that **strategic decisions, tactical sequences, and atomic actions are all flattened into a single A\* search space.**

### Eval Baseline (2026-04-30, 12 agents, 60s)

| Metric | Value | Budget | Status |
|--------|-------|--------|--------|
| avg_search_time_us | 12,862 | 100 | FAIL (128x over) |
| avg_iterations | 246.3 | 80 | FAIL (hitting 256 cap) |
| cache_hit_rate | 3.2% | 75% | FAIL |
| plan_found_rate | 3.8% | 85% | FAIL |
| avg_decision_time_ms | 2.80 | 1.00 | FAIL |
| p99_decision_time_ms | 18.26 | 3.00 | FAIL |
| thrash_rate | 1.2% | 5% | PASS |

### Root Causes

**1. Architecture: flat action space mixes decision levels.** GOAP searches across 22 actions that span three conceptual levels — "should I feed?" (strategic), "walk to grass then eat" (tactical sequence), "execute walk step" (atomic). The planner discovers obvious sequences (MoveToGrass → EatGrass) that a human would never question, wasting search budget on combinatorics that should be predefined.

**2. Unsolvable problems dominate search time.** `feed_self` accounts for 93.6% of planning calls at 0.16% success rate. All feeding paths are gated behind system-provided perception facts (`sees_grass`, etc.) that no action can produce. The planner exhausts 256 iterations proving impossibility, then repeats every 0.2s.

**3. Compounding bugs and missing safeguards.** `wander.gd` injects `has_threat: true` into every search tree. Failed plans aren't cached. SAI retries impossible goals with no backoff.

### Why This Blocks the Vision

GOL's goal is KCD-level NPC behavior — rich daily routines, dynamic work/social/combat, all driven by runtime planning. The current flat architecture cannot scale: each new action multiplies the search space exponentially. A three-layer architecture is needed to let GOAP focus on what it does best (strategic combination) while predefined templates handle tactical execution.

---

## Non-Goals

- Not replacing GOAP with behavior trees or utility AI — GOAP remains the strategic planner
- Not adding new NPC behaviors in this spec — this is infrastructure, not content
- Not optimizing action execution (animation, navigation) — this spec targets planning/decision only

---

## Design Overview

```
┌──────────────────────────────────────────────────────────┐
│ Layer 1: Life Planner (GOAP A*)                          │
│                                                          │
│ "What should I do?"                                      │
│ Actions: Feed, Work, Build, Fight, Flee, Patrol, Rest,   │
│          Socialize, Explore (~8-12 coarse actions)       │
│ Frequency: every 0.5-5s (LOD-adjusted)                   │
│ Output: selected StrategicAction                         │
├──────────────────────────────────────────────────────────┤
│ Layer 2: Behavior Templates (predefined sequences)       │
│                                                          │
│ "How do I do it?"                                        │
│ Each StrategicAction owns a BehaviorTemplate:            │
│   Feed → [MoveToFoodSource → Eat]                        │
│   Work → [FindTarget → MoveTo → Gather → Deliver]        │
│   Fight → [Chase → SelectAttack → Attack]                │
│ No search — step through predefined sequence             │
│ Frequency: on strategic action change + step transitions │
├──────────────────────────────────────────────────────────┤
│ Layer 3: Atomic Execution (engine interface)             │
│                                                          │
│ "Do the thing."                                          │
│ Navigation, animation, collision, component updates      │
│ Frequency: every frame                                   │
│ Output: step complete / step failed / interrupted        │
└──────────────────────────────────────────────────────────┘
```

Two ECS systems drive the pipeline:

- **SGoalDecision** — runs Layer 1 (rate-limited, max 3 agents/frame, 3ms budget)
- **SPlanExecution** — runs Layers 2+3 (every frame)

---

## Phase 1 — Three-Layer Architecture (Priority: Immediate)

### 1.1 Strategic Actions (Layer 1)

Replace the current 22 fine-grained actions with ~8-12 coarse strategic actions. Each strategic action represents a **behavioral intent**, not a physical step.

#### Strategic Action Catalog

| Strategic Action | Desired Outcome | Viability Gate | Agent Types |
|-----------------|----------------|----------------|-------------|
| Feed | `is_fed = true` | `sees_grass OR sees_food_pile OR sees_harvestable` | rabbit, worker, guard |
| Work | `has_delivered = true` | `sees_resource_node` | worker |
| Build | `build_done = true` | (always viable) | worker |
| FightMelee | `has_threat = false` | `has_threat` | guard, enemy_* |
| FightRanged | `has_threat = false` | `has_threat AND has_shooter_weapon` | guard, enemy_* |
| Flee | `is_safe = true` | `has_threat OR is_low_health` | all |
| Patrol | `is_patrolling = true` | `is_guard` | guard |
| Rest | `is_rested = true` | `is_low_energy` | all |
| Explore | `is_exploring = true` | (always viable) | rabbit, composer |
| Guard | `at_guard_post = true` | `is_guard` | guard |

**Key design change:** Each strategic action carries a **viability gate** — a list of world-state facts that must hold for the action to be worth considering. The planner skips actions whose gate fails, equivalent to the old "viability check" but built into the action itself rather than the goal.

**Costs:** Strategic action costs reflect behavioral preference, not physical effort:

| Action | Cost | Rationale |
|--------|------|-----------|
| Flee | 1.0 | Survival always cheapest |
| FightMelee / FightRanged | 2.0 | React to threats quickly |
| Feed | 3.0 | Basic need |
| Work / Build | 5.0 | Productive but deferrable |
| Patrol / Guard | 5.0 | Duty-based |
| Rest | 8.0 | Only when needed |
| Explore | 10.0 | Lowest priority, fallback |

**Search complexity reduction:**

```
Before: 22 actions, branching factor 7-10, plan depth 2-5
  → search space: ~10^3 to 10^5 nodes

After: 8-12 actions per agent (filtered by viability), branching factor 2-4, plan depth 1-2
  → search space: ~4 to 16 nodes
```

Most plans will be depth 1 (a single strategic action). Depth 2 occurs when one action enables another (e.g., Feed enables Work by removing hunger debuff).

#### Strategic Action Interface

```gdscript
class_name StrategicAction extends Resource

@export var action_name: String
@export var cost: float = 1.0
@export var preconditions: Dictionary[String, bool] = {}
@export var effects: Dictionary[String, bool] = {}

## Facts that must be true in world state for this action to be worth planning.
## If all are absent, planner skips this action entirely. Empty = always viable.
@export var viability_gate: Array[String] = []

## The behavior template that executes this action's intent.
## Resolved at init time from the template registry.
var behavior_template: BehaviorTemplate
```

### 1.2 Behavior Templates (Layer 2)

Each strategic action owns a `BehaviorTemplate` — a predefined sequence of atomic steps. Templates are **not searched**; they execute in order.

**Design reference: KCD2 (GDC 2025, Warhorse Studios).** KCD2 uses GOAP to find state transitions, then executes each action as a "small behavior tree" with enter-loop-exit lifecycle. We adopt this pattern directly, adapted for GOL's 2D ECS context.

#### Template Design

```gdscript
class_name BehaviorTemplate extends Resource

## Ordered list of step definitions. Executed sequentially.
@export var steps: Array[BehaviorStep] = []

## Whether this template loops its step sequence. If true, after the last
## step completes, execution restarts from step 0. The template only ends
## when SPlanExecution aborts it (higher-priority goal) or a step fails.
## Example: MeleeCombat loops [ChaseTarget → AttackMelee] until target dies.
@export var loops: bool = false

## Called when the strategic action activates this template.
## Resolves variant (e.g., Feed picks grass/bush/pile based on perception).
## Returns FAILED if preconditions for any variant are not met.
func begin(agent: CGoapAgent) -> StepResult

## Called every frame by SPlanExecution.
## Returns: RUNNING, COMPLETED, FAILED
func tick(agent: CGoapAgent, delta: float) -> StepResult

## Called when template is abandoned (higher-priority goal, or failure).
## MUST run the current step's exit phase before returning.
func abort(agent: CGoapAgent) -> void
```

#### Behavior Step: Enter-Loop-Exit Lifecycle (KCD2 Pattern)

Each step follows the KCD2 "enter-loop-exit" pattern. This is critical for clean state management — when a step is interrupted, it MUST run its exit phase to restore NPC state (put down held items, cancel animations, release navigation locks).

```gdscript
class_name BehaviorStep extends Resource

@export var step_name: String

## World state conditions that must hold for this step to begin.
## If not met, the template can skip this step or fail.
@export var entry_conditions: Dictionary[String, bool] = {}

## Phase enum tracks where in the lifecycle this step is.
enum Phase { ENTERING, LOOPING, EXITING }

## ENTER: one-time setup. Pick up tools, start transition animation,
## acquire navigation target. Called once when step becomes active.
## Returns RUNNING (still entering) or COMPLETED (enter done, move to loop).
func enter(agent: CGoapAgent, delta: float) -> StepResult

## LOOP: the core behavior. Called every frame after enter completes.
## Returns RUNNING (continue), COMPLETED (step done, trigger exit),
## or FAILED (abort step, trigger exit).
## For instant steps (e.g., PickupFood), loop returns COMPLETED immediately.
func loop(agent: CGoapAgent, delta: float) -> StepResult

## EXIT: cleanup. Put down tools, play transition-out animation,
## release navigation locks, update world state facts.
## Called once when loop completes, fails, or when template is aborted.
## Returns RUNNING (still exiting) or COMPLETED (exit done).
func exit(agent: CGoapAgent, delta: float) -> StepResult
```

**Step lifecycle state machine:**

```
begin → [ENTERING] → enter() returns COMPLETED
           ↓
       [LOOPING]  → loop() returns COMPLETED or FAILED
           ↓
       [EXITING]  → exit() returns COMPLETED → next step (or template done)
           
Interrupt at any phase → immediately transition to EXITING
```

**Why enter-loop-exit matters for GOL:**

| Step | Enter | Loop | Exit |
|------|-------|------|------|
| GatherResource | Walk to node, equip pickaxe | Mining animation loop | Put down pickaxe, update `has_gathered_resource` |
| EatGrass | Walk to grass tile | Eating animation | Update `is_fed`, clear navigation |
| AttackMelee | Charge animation | Attack swing loop | Sheathe weapon if switching behavior |
| Patrol | Start walking to waypoint | Walk between waypoints | Stop at current position |

Without the exit phase, interrupting GatherResource mid-loop would leave the pickaxe equipped and the mining animation stuck. KCD2 solves this by guaranteeing the exit phase always runs.

**Data-driven step configuration (KCD2 principle):**

Steps should be configurable via Resource exports as much as possible, minimizing per-step GDScript subclasses. Common patterns become reusable base classes:

```gdscript
## Reusable step: move to a target identified by a world state fact.
class_name MoveToTargetStep extends BehaviorStep
@export var target_fact: String = ""  ## e.g., "sees_grass"
@export var arrival_fact: String = "" ## e.g., "adjacent_to_grass"

## Reusable step: play an animation loop for a duration.
class_name TimedActionStep extends BehaviorStep
@export var duration_seconds: float = 1.0
@export var completion_fact: String = "" ## set to true on loop complete

## Reusable step: instant state change (e.g., pick up item).
class_name InstantStep extends BehaviorStep
@export var facts_to_set: Dictionary[String, bool] = {}
```

With these 3 base classes, most of the current 22 actions can be configured purely through Resource exports without writing new GDScript.

#### Template Catalog

**Feed Template** (3 variants resolved at runtime based on food source):

```
FeedFromGrass:
  step 0: MoveToTargetStep { target_fact: "sees_grass", arrival_fact: "adjacent_to_grass" }
  step 1: TimedActionStep   { duration: 1.5, completion_fact: "is_fed" }

FeedFromBush:
  step 0: MoveToTargetStep { target_fact: "sees_harvestable", arrival_fact: "adjacent_to_harvestable" }
  step 1: TimedActionStep   { duration: 2.0, completion_fact: "is_fed" }

FeedFromPile:
  step 0: MoveToTargetStep { target_fact: "sees_food_pile", arrival_fact: "adjacent_to_food_pile" }
  step 1: InstantStep       { facts_to_set: { "is_fed": true } }
```

Template selection: when `Feed.behavior_template.begin(agent)` is called, it checks the agent's world state for which perception fact is true (`sees_grass`, `sees_harvestable`, `sees_food_pile`) and selects the matching variant. Priority when multiple are true: nearest food source by Euclidean distance (cheapest navigation). If none are true, `begin()` immediately returns FAILED — this should not happen because the viability gate prevents Feed from being planned without at least one perception fact. The variant is locked at `begin()` time and does not change mid-template.

**Work Template:**

```
WorkCycle:
  step 0: FindWorkTargetStep  { completion_fact: "has_work_target" }
  step 1: MoveToTargetStep    { target_fact: "has_work_target", arrival_fact: "adjacent_to_resource_node" }
  step 2: TimedActionStep     { duration: 3.0, completion_fact: "has_gathered_resource" }
  step 3: MoveToTargetStep    { target_fact: "sees_stockpile", arrival_fact: "adjacent_to_stockpile" }
  step 4: InstantStep         { facts_to_set: { "has_delivered": true } }
```

**Build Template:**

```
BuildCycle:
  step 0: BuildStep  { delegates to SBuildWorker FSM, completion_fact: "build_done" }
```

**FightMelee Template (loops: true):**

```
MeleeCombat:
  step 0: MoveToTargetStep  { target_fact: "has_threat", arrival_fact: "is_threat_in_attack_range" }
  step 1: AttackStep         { attack_type: "melee", completion_facts: { "has_threat": false, "is_safe": true } }
  (loops until target eliminated or template aborted)
```

**FightRanged Template (loops: true):**

```
RangedCombat:
  step 0: PositionStep       { maintain optimal range, sets "ready_ranged_attack" }
  step 1: AttackStep         { attack_type: "ranged", completion_facts: { "has_threat": false, "is_safe": true } }
  (loops until target eliminated or template aborted)
```

**Flee Template:**

```
FleeFromThreat:
  step 0: FleeStep  { moves away from nearest threat, completion_fact: "is_safe" }
```

**Patrol Template (loops: true):**

```
PatrolRoute:
  step 0: MoveToTargetStep  { target_fact: waypoint, arrival_fact: "at_waypoint" }
  (loops through patrol waypoints until aborted)
```

**Explore Template (loops: true):**

```
Wander:
  step 0: WanderStep  { random movement, sets "is_exploring" }
  (loops until a higher-priority goal interrupts)
```

**Guard Template:**

```
GuardPost:
  step 0: MoveToTargetStep  { target: guard post position, arrival_fact: "at_guard_post" }
```

**Rest Template:**

```
RestAction:
  step 0: TimedActionStep  { duration: 5.0, completion_fact: "is_rested" }
```

#### Template Interruption

When SGoalDecision selects a new strategic action (higher-priority goal changed), SPlanExecution:
1. Calls `current_step.exit(agent, delta)` — guarantees cleanup (KCD2 pattern: always run exit phase)
2. Waits for exit to return COMPLETED (may take 1-2 frames for exit animation)
3. Calls `current_template.abort(agent)` — template-level cleanup
4. Loads the new template via `new_action.behavior_template.begin(agent)`
5. Starts ticking the new template

For **urgent interruptions** (e.g., Flee from sudden threat), the exit phase can be shortened or skipped via a `force_abort: bool` flag. This trades clean state restoration for responsiveness — acceptable for survival situations.

This replaces the current "replan" mechanism. Replanning happens at Layer 1 (strategic), not within templates.

### 1.3 NPC State as First-Class Citizen (KCD2 Pattern)

KCD2's key insight: GOAP plans transitions between **NPC states**, not just world state booleans. NPC state includes posture (standing/sitting/crouching), presentation state (working/idle/fighting), and held items.

GOL adaptation: introduce a lightweight NPC state struct tracked in `CGoapAgent`:

```gdscript
## NPC's own behavioral state — distinct from world state facts.
## World state facts describe the environment; NPC state describes the agent itself.
## BehaviorSteps update NPC state during enter/exit phases.

@export var posture: StringName = &"standing"  ## standing, crouching, sitting
@export var held_item: StringName = &"none"    ## none, pickaxe, sword, bow
@export var activity: StringName = &"idle"     ## idle, working, eating, fighting, fleeing, patrolling
```

**How NPC state interacts with templates:**

- **Enter phase** sets NPC state: GatherResource.enter() → `held_item = "pickaxe"`, `activity = "working"`
- **Exit phase** restores NPC state: GatherResource.exit() → `held_item = "none"`, `activity = "idle"`
- **Interruption safety**: exit phase guarantees NPC state is cleaned up before new template starts

**How NPC state interacts with the planner (future extensibility):**

NPC state is NOT part of GOAP world state in this version — it would expand the search space unnecessarily. Instead, NPC state serves as:
1. A correctness guard — templates check NPC state in entry_conditions (e.g., "can't mine if already holding sword")
2. A rendering driver — sprite/animation systems read `activity` and `held_item` to select visuals
3. A foundation for Phase 4 (hierarchical planner) where posture/activity could become strategic planning dimensions

### 1.3 System Split: SGoalDecision + SPlanExecution

Replace `s_ai.gd` with two independent systems.

**SGoalDecision** (runs rate-limited):
- Query: `CGoapAgent` where `needs_decision == true`
- For each agent:
  1. Get sorted goals (priority descending)
  2. For each unsatisfied goal, call `GoapPlanner.build_plan_for_goal()` with strategic actions (filtered by viability gates)
  3. If plan found → write to `agent.pending_strategic_action`
  4. If no plan → apply backoff, try next goal
- Rate limiting: MAX_DECISIONS_PER_FRAME = 3, DECISION_FRAME_HARD_BUDGET_MS = 3.0
- LOD-based update intervals preserved

**SPlanExecution** (runs every frame):
- Query: `CGoapAgent` where `active_template != null OR pending_strategic_action != null`
- For each agent:
  1. If `pending_strategic_action` exists → abort current template, load new one
  2. Call `active_template.tick(agent, delta)`
  3. On COMPLETED → mark `needs_decision = true`
  4. On FAILED → mark `needs_decision = true`
  5. On RUNNING → continue next frame

**CGoapAgent component changes:**

```gdscript
## Layer 1 state (written by SGoalDecision)
var pending_strategic_action: StrategicAction = null
var current_goal: GoapGoal = null
var needs_decision: bool = true

## Layer 2 state (managed by SPlanExecution)  
var active_template: BehaviorTemplate = null
var current_step_index: int = 0

## Per-agent action configuration
@export var allowed_strategic_actions: Array[String] = []
@export var goals: Array[GoapGoal] = []
```

### 1.4 Action Migration Map

Full migration from current 22 fine-grained actions to strategic actions + template steps:

| Current Action | → Strategic Action | → Template Step | Notes |
|---------------|-------------------|-----------------|-------|
| EatGrass | Feed | FeedFromGrass.step[1] | |
| MoveToGrass | Feed | FeedFromGrass.step[0] | |
| HarvestBush | Feed | FeedFromBush.step[1] | |
| MoveToHarvestable | Feed | FeedFromBush.step[0] | |
| PickupFood | Feed | FeedFromPile.step[1] | |
| MoveToFoodPile | Feed | FeedFromPile.step[0] | |
| FindWorkTarget | Work | WorkCycle.step[0] | |
| MoveToResourceNode | Work | WorkCycle.step[1] | |
| GatherResource | Work | WorkCycle.step[2] | |
| MoveToStockpile | Work | WorkCycle.step[3] | |
| DepositResource | Work | WorkCycle.step[4] | |
| Build | Build | BuildCycle.step[0] | Delegates to SBuildWorker |
| ChaseTarget | FightMelee | MeleeCombat.step[0] | |
| AttackMelee | FightMelee | MeleeCombat.step[1] | |
| AdjustShootPosition | FightRanged | RangedCombat.step[0] | |
| AttackRanged | FightRanged | RangedCombat.step[1] | |
| Flee | Flee | FleeFromThreat.step[0] | |
| Wander | Explore | Wander.step[0] | Fix: remove has_threat effect |
| Patrol | Patrol | PatrolRoute.step[0] | Fix: perform() must complete |
| ReturnToCamp | Guard | GuardPost.step[0] | |
| MarchToCampfire | (remove) | — | Unused, no agent assignment |
| Rest | Rest | RestAction.step[0] | |

**Actions to remove:** MarchToCampfire (no agent uses it), AdjustAttackPosition (redundant with ChaseTarget), React (unused), Idle (replaced by Explore fallback), Search (unused), Defend (merged into FightMelee template logic).

### 1.5 Per-Agent Strategic Action Assignments

| Agent Type | Strategic Actions | Count |
|-----------|------------------|-------|
| rabbit | Feed, Flee, Explore | 3 |
| Worker | Feed, Work, Build, Flee | 4 |
| Guard | FightMelee, FightRanged, Flee, Patrol, Guard, Feed | 6 |
| Guard_Healer | FightMelee, Flee, Patrol, Guard | 4 |
| enemy_* | FightMelee, FightRanged, Flee, Explore | 4 |
| ComposerNPC | Explore, Flee | 2 |

Maximum branching factor: 6 (Guard). With viability gates, effective branching is typically 2-3.

---

## Phase 2 — Eval Tool Adaptation (Priority: Immediate, alongside Phase 1)

The eval tool must be updated to measure the new two-system architecture.

### New Metric Groups

```
Decision (SGoalDecision):
  decisions/frame           — how many agents decided per frame
  decision_time_avg_us      — avg time per decision tick
  decision_time_p99_us      — tail latency
  strategic_action_selected — distribution of which actions are chosen
  viability_gate_skips      — how many actions skipped by gate
  backoff_skips             — how many goals skipped by backoff

Execution (SPlanExecution):
  templates_active          — how many agents have running templates
  step_completions/s        — template throughput
  step_failures/s           — template failure rate
  template_interruptions/s  — how often higher-priority goals interrupt
  avg_template_lifetime_s   — how long a template runs before completion/interruption

Planning (GoapPlanner, Layer 1 only):
  avg_search_time_us        — per A* search (strategic actions only)
  avg_iterations            — iterations per search
  plan_found_rate           — success rate
  max_iterations            — worst case

Cache (if smart cache is implemented in Phase 3):
  hit_rate, miss_reasons, negative_hits
```

### Updated Performance Budgets

| Metric | Budget | Rationale |
|--------|--------|-----------|
| avg_search_time_us | < 50 | 8-12 strategic actions, depth 1-2, should be trivial |
| avg_iterations | < 10 | Most plans are depth 1 |
| plan_found_rate | > 90% | Viability gates prevent unsolvable searches |
| decision_time_avg_us | < 200 | Gate checks + shallow search |
| decision_time_p99_us | < 1000 | Worst case with full search |
| step_failures/s | < 1.0 | Templates should rarely fail |
| template_interruptions/s | < 2.0 | Frequent interruptions indicate goal instability |

### Benchmark Scenarios

Update `goap_planner_bench.gd` to use strategic actions:

| Scenario | Agent | Goal | Expected |
|----------|-------|------|----------|
| rabbit/feed | rabbit | feed_self (sees_grass=true) | Feed, 1 step, <5 iter |
| rabbit/feed_blocked | rabbit | feed_self (sees_grass=false) | gate skip, 0 iter |
| worker/work | worker | Work (sees_resource=true) | Work, 1 step, <5 iter |
| guard/combat | guard | EliminateThreat (has_threat=true) | FightMelee or FightRanged, <5 iter |
| guard/no_threat | guard | EliminateThreat (has_threat=false) | gate skip, 0 iter |

---

## Phase 3 — Smart Cache & Planner Refinements (Priority: Deferred)

Implement **after** Phase 1+2 are validated. Only if eval data shows remaining performance issues.

### 3a. Smart Cache (Unified Positive + Negative, Template Key)

Each goal declares `cache_key_facts: Array[String]` — only these facts appear in the cache key. Positive and negative results share the same cache with a `success: bool` flag.

```
Cache key format:  goal_name | fact1=val, fact2=val, ...
                   (only cache_key_facts, not all 26 planning keys)

Cache entry:       { success: bool, plan: GoapPlan or null, stored_frame: int }
```

feed_self example:
```
feed_self | sees_grass=false, sees_food=false, sees_harv=false  → { success: false }
feed_self | sees_grass=true, sees_food=false, sees_harv=false   → { success: true, plan: Feed }
```

With 3 binary facts, there are only 8 possible keys. After 8 searches, **every future query is a cache hit**.

### 3b. Delete-Relaxation Heuristic

If A* search over strategic actions still shows high iteration counts (unlikely with 8-12 actions), replace the "count unsatisfied conditions" heuristic with delete-relaxation (FF-style).

Given the expected search space (branching 2-4, depth 1-2), the current heuristic may be sufficient. Validate with eval data before implementing.

### 3c. SAI Goal Backoff

Track consecutive planning failures per goal with exponential backoff: 0.5s → 1s → 2s → cap 5s. Reset when viability-gate-relevant facts change. May not be needed if viability gates + smart cache catch all unsolvable cases.

### 3d. MAX_ITERATIONS Reduction

Reduce from 256 to 32 after validating that all legitimate plans complete in <10 iterations with the new architecture.

---

## Phase 4 — Future Directions (Not In Scope)

Documented for reference. Not implemented in this spec.

### 4a. Hierarchical Life Planner

When agent behavioral complexity grows (40+ strategic actions, schedule-based daily routines), introduce a strategic layer above GOAP:

```
Schedule Layer (rule-based):
  "It's morning → Work mode" / "Threat nearby → Combat mode"
  Runs every 5-10 seconds, selects a behavioral mode
  
Tactical Layer (GOAP):
  Within the selected mode, plan which strategic action to take
  Runs every 0.5-5 seconds, searches over mode-relevant actions only
```

### 4b. Contextual Template Selection

Templates can be parameterized based on agent traits or world state:

```
Fight template for a cautious NPC:  [Assess → Flee if outnumbered → Fight if advantage]
Fight template for an aggressive NPC: [Charge → Attack → Pursue]
```

Same strategic action (Fight), different behavioral expression.

### 4c. Effect Pollution Detection Tool

Extend the feasibility checker to detect suspicious effect declarations:

```
⚠ Wander declares effects = {has_threat: true}
  → This makes Wander a precondition provider for ChaseTarget, AttackMelee, AttackRanged
  → In a feed_self search, this injects the entire combat sub-tree
  Confirm this is intentional? [Y/n]
```

---

## Action Catalog Reference

### Current Actions (pre-migration, 22 registered)

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
| Flee | 1.0 | `is_low_health` ★ | `is_safe` |
| Rest | 10.0 | `is_low_energy` ★ | `is_rested` |
| Wander | 10.0 | (none) | `has_threat` ⚠ BUG |
| MarchToCampfire | 10.0 | (none) | `at_campfire` |
| Patrol | 1.0 | (none) | `is_patrolling` |
| ReturnToCamp | 1.0 | (none) | `at_guard_post` |

★ = system-provided fact (perception/health/energy, not producible by any action)

### Post-Migration Strategic Actions (Layer 1)

| Action | Cost | Preconditions | Effects | Viability Gate |
|--------|------|---------------|---------|----------------|
| Feed | 3.0 | `is_fed: false` | `is_fed: true` | sees_grass OR sees_food_pile OR sees_harvestable |
| Work | 5.0 | `has_delivered: false` | `has_delivered: true` | sees_resource_node |
| Build | 5.0 | `build_done: false` | `build_done: true` | (always) |
| FightMelee | 2.0 | `has_threat: true` | `has_threat: false, is_safe: true` | has_threat |
| FightRanged | 2.0 | `has_threat: true, has_shooter_weapon: true` | `has_threat: false, is_safe: true` | has_threat AND has_shooter_weapon |
| Flee | 1.0 | (none) | `is_safe: true` | has_threat OR is_low_health |
| Patrol | 5.0 | `is_guard: true` | `is_patrolling: true` | is_guard |
| Guard | 5.0 | `is_guard: true` | `at_guard_post: true` | is_guard |
| Rest | 8.0 | `is_low_energy: true` | `is_rested: true` | is_low_energy |
| Explore | 10.0 | (none) | `is_exploring: true` | (always) |

---

## World State Fact Inventory

### System-Provided Facts (written by perception/health/energy systems)

| Fact | Source System | Purpose |
|------|-------------|---------|
| `sees_grass` | SPerception | Grass in vision range |
| `sees_food_pile` | SPerception | Food pile in vision range |
| `sees_harvestable` | SPerception | Harvestable bush in vision range |
| `sees_resource_node` | SPerception | Resource node in vision range |
| `sees_stockpile` | SPerception | Stockpile in vision range |
| `has_threat` | SSemanticTranslation | Hostile entity visible |
| `is_safe` | SSemanticTranslation | No threat in safety radius |
| `is_low_health` | SSemanticTranslation | HP below threshold |
| `has_shooter_weapon` | SSemanticTranslation | Has ranged weapon component |
| `is_guard` | SSemanticTranslation | Has guard component |
| `is_low_energy` | SSemanticTranslation | Energy below threshold |

### Action-Managed Facts (written by template steps during execution)

| Fact | Updated By | Purpose |
|------|-----------|---------|
| `is_fed` | EatGrass, HarvestBush, PickupFood steps | Hunger satisfied |
| `has_delivered` | DepositResource step | Work cycle complete |
| `build_done` | SBuildWorker system | Construction complete |
| `is_patrolling` | Patrol step | On patrol route |
| `at_guard_post` | ReturnToCamp step | At assigned post |
| `is_rested` | Rest step | Energy restored |
| `is_exploring` | Wander step | Exploring/idle |

---

## Verification Strategy

### Phase 1+2 Validation (run after architecture migration)

`gol test goap --json --duration=60`

| Metric | Baseline | Phase 1+2 Target |
|--------|----------|-----------------|
| avg_search_time_us | 12,862 | < 50 |
| avg_iterations | 246.3 | < 10 |
| plan_found_rate | 3.8% | > 90% |
| decision_time_avg_us | 2,800 | < 200 |
| decision_time_p99_us | 18,260 | < 1,000 |
| step_failures/s | N/A | < 1.0 |

### Phase 3 Validation (run after cache/heuristic changes, if implemented)

Only proceed with Phase 3 items if Phase 1+2 targets are not fully met, or if profiling reveals specific remaining bottlenecks.

### Known Issues to Fix During Migration

| Issue | Fix | Phase |
|-------|-----|-------|
| Wander effects `has_threat: true` bug | Remove — Explore strategic action uses `is_exploring` | 1 |
| Patrol `perform()` never returns true | Fix in PatrolRoute template step | 1 |
| MarchToCampfire unused | Remove entirely | 1 |
| Failed plans not cached | Addressed by smart cache if needed | 3 |
| SAI no backoff on failure | Addressed by backoff if needed | 3 |
