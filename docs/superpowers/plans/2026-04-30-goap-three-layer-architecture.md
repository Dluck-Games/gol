# GOAP Three-Layer Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat 22-action GOAP system with a three-layer architecture (strategic planner → behavior templates → atomic execution), split s_ai.gd into SGoalDecision + SPlanExecution, migrate all actions, update the eval tool, and clean up dead code — with zero player-visible behavior change.

**Architecture:** Layer 1 (GOAP A*) plans over ~10 coarse StrategicActions with viability gates. Layer 2 (BehaviorTemplates) executes predefined step sequences using KCD2 enter-loop-exit lifecycle. Layer 3 (atomic steps) handles navigation, animation, and component updates every frame. Two ECS systems drive the pipeline: SGoalDecision (rate-limited) and SPlanExecution (every-frame).

**Tech Stack:** Godot 4.6, GDScript, GECS ECS addon, `gol` CLI test runner

**Spec:** `docs/superpowers/specs/2026-04-30-goap-planner-optimization-design.md`

---

## File Map

### New files to create

```
scripts/gameplay/goap/
├── strategic_action.gd            # StrategicAction Resource class
├── behavior_template.gd           # BehaviorTemplate Resource class
├── behavior_step.gd               # BehaviorStep base class (enter-loop-exit)
├── steps/                         # Reusable step implementations
│   ├── move_to_target_step.gd     # MoveToTargetStep — navigate to perception target
│   ├── timed_action_step.gd       # TimedActionStep — duration-based action
│   ├── instant_step.gd            # InstantStep — immediate fact change
│   ├── flee_step.gd               # FleeStep — move away from threat
│   ├── wander_step.gd             # WanderStep — random exploration movement
│   ├── attack_step.gd             # AttackStep — melee/ranged attack execution
│   ├── position_step.gd           # PositionStep — ranged position adjustment
│   ├── chase_step.gd              # ChaseStep — pursue threat target
│   ├── build_step.gd              # BuildStep — delegates to SBuildWorker
│   ├── find_work_target_step.gd   # FindWorkTargetStep — locate resource node
│   └── patrol_step.gd             # PatrolStep — waypoint patrol loop
├── templates/                     # Template definitions (could be .tres or .gd)
│   ├── feed_template.gd           # 3-variant Feed (grass/bush/pile)
│   ├── work_template.gd           # 5-step work cycle
│   ├── build_template.gd          # Build delegation
│   ├── fight_melee_template.gd    # Chase → Attack loop
│   ├── fight_ranged_template.gd   # Position → Attack loop
│   ├── flee_template.gd           # Single flee step
│   ├── patrol_template.gd         # Waypoint patrol loop
│   ├── explore_template.gd        # Wander loop
│   ├── guard_template.gd          # Return to post
│   └── rest_template.gd           # Timed rest
└── strategic_actions/              # .tres resources for each strategic action
    ├── sa_feed.tres
    ├── sa_work.tres
    ├── sa_build.tres
    ├── sa_fight_melee.tres
    ├── sa_fight_ranged.tres
    ├── sa_flee.tres
    ├── sa_patrol.tres
    ├── sa_explore.tres
    ├── sa_guard.tres
    └── sa_rest.tres

scripts/systems/
├── s_goal_decision.gd             # SGoalDecision — Layer 1 system (rate-limited)
└── s_plan_execution.gd            # SPlanExecution — Layer 2+3 system (every-frame)

resources/goals/                   # Updated goal .tres files
├── feed_self.tres                 # (update: add viability_facts if GoapGoal gets the field)
├── survive.tres                   # (no change to desired_state)
├── work.tres                      # (no change)
└── ...                            # Others updated as needed
```

### Files to modify

```
scripts/components/ai/c_goap_agent.gd    # Add NPC state fields, template state, strategic action config
scripts/gameplay/goap/goap_planner.gd     # Add viability gate filtering, accept StrategicAction arrays
scripts/gameplay/goap/goap_goal.gd        # (minor: clean up if needed)
scripts/tests/goap_eval_main.gd           # Rewrite for new architecture metrics
scripts/tests/goap_metrics_collector.gd   # New metric groups (decision/execution/planning)
scripts/tests/goap_eval_report.gd         # New report format
scripts/tests/goap_planner_bench.gd       # Rewrite benchmarks for strategic actions
scripts/tests/goap_feasibility_checker.gd # Update for strategic actions
gol-tools/cli/cmd/goap_eval.go            # Update output filter for new report format
resources/recipes/*.tres                  # Update 9 recipes: goal refs + allowed_strategic_actions
```

### Files to delete (dead code cleanup)

```
scripts/gameplay/goap/actions/             # Entire directory — all 23 action files
  adjust_shoot_position.gd
  attack_melee.gd
  attack_ranged.gd
  chase_target.gd
  deposit_resource.gd
  eat_grass.gd
  find_work_target.gd
  flee.gd
  flee_on_sight.gd
  gather_resource.gd
  goap_action_build.gd
  harvest_bush.gd
  march_to_campfire.gd
  move_to.gd                               # Abstract base — replaced by MoveToTargetStep
  move_to_food_pile.gd
  move_to_grass.gd
  move_to_harvestable.gd
  move_to_resource_node.gd
  move_to_stockpile.gd
  patrol.gd
  pickup_food.gd
  return_to_camp.gd
  wander.gd
scripts/gameplay/goap/goap_action.gd       # Old action base class
scripts/gameplay/goap/goap_plan.gd         # Old plan container (replaced by template execution)
scripts/gameplay/goap/goap_plan_step.gd    # Old plan step
scripts/gameplay/goap/goals/goap_goal_build.gd  # Empty stub, adds nothing over GoapGoal
scripts/systems/s_ai.gd                    # Replaced by s_goal_decision.gd + s_plan_execution.gd
resources/goals/wander.tres                # Desired state {has_threat:true} is a bug artifact
resources/goals/march_to_campfire.tres     # Unused — no agent references it after cleanup
resources/goals/clear_threat.tres          # Merged into EliminateThreat (same desired state)
```

---

## Task Breakdown

### Task 1: Core Framework — BehaviorStep base class

**Files:**
- Create: `scripts/gameplay/goap/behavior_step.gd`

This is the foundation. The enter-loop-exit lifecycle from KCD2. All template steps inherit from this.

- [ ] **Step 1: Create BehaviorStep base class**

```gdscript
## scripts/gameplay/goap/behavior_step.gd
## Base class for all behavior template steps.
## Follows KCD2 enter-loop-exit lifecycle pattern.
class_name BehaviorStep
extends Resource

enum StepResult { RUNNING, COMPLETED, FAILED }
enum Phase { ENTERING, LOOPING, EXITING }

@export var step_name: String = ""

## World state conditions that must hold for this step to begin.
@export var entry_conditions: Dictionary = {}

var _phase: Phase = Phase.ENTERING

## ENTER: one-time setup (pick up tools, acquire nav target).
## Returns RUNNING (still entering) or COMPLETED (enter done, move to loop).
func enter(_agent: CGoapAgent, _entity: Entity, _delta: float) -> StepResult:
	return StepResult.COMPLETED

## LOOP: the core behavior, called every frame after enter completes.
## Returns RUNNING (continue), COMPLETED (step done, trigger exit), or FAILED.
func loop(_agent: CGoapAgent, _entity: Entity, _delta: float) -> StepResult:
	return StepResult.COMPLETED

## EXIT: cleanup (put down tools, release nav locks, update facts).
## Called when loop completes, fails, or when template is aborted.
## Returns RUNNING (still exiting) or COMPLETED (exit done).
func exit(_agent: CGoapAgent, _entity: Entity, _delta: float) -> StepResult:
	return StepResult.COMPLETED

## Called by BehaviorTemplate.tick() — manages phase state machine.
func tick(agent: CGoapAgent, entity: Entity, delta: float) -> StepResult:
	match _phase:
		Phase.ENTERING:
			var result := enter(agent, entity, delta)
			if result == StepResult.COMPLETED:
				_phase = Phase.LOOPING
				return StepResult.RUNNING
			return result  # RUNNING or FAILED
		Phase.LOOPING:
			var result := loop(agent, entity, delta)
			if result == StepResult.COMPLETED or result == StepResult.FAILED:
				_phase = Phase.EXITING
				return StepResult.RUNNING
			return StepResult.RUNNING
		Phase.EXITING:
			var result := exit(agent, entity, delta)
			if result == StepResult.COMPLETED:
				return StepResult.COMPLETED
			return StepResult.RUNNING
	return StepResult.FAILED

## Force transition to exit phase (for interruptions).
func begin_exit() -> void:
	_phase = Phase.EXITING

## Reset for reuse (looping templates).
func reset() -> void:
	_phase = Phase.ENTERING

## Check if entry conditions are met against world state.
func can_enter(world_state: GoapWorldState) -> bool:
	for key: String in entry_conditions:
		if world_state.get_fact(key) != entry_conditions[key]:
			return false
	return true
```

- [ ] **Step 2: Verify no parse errors**

Run: `gol test unit --suite goap -v 2>&1 | head -5` or `gol run game --headless -- --quit 2>&1 | grep -i error | head -10`

Expected: no errors related to behavior_step.gd (file exists but nothing references it yet)

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/goap/behavior_step.gd
git commit -m "feat(goap): add BehaviorStep base class with enter-loop-exit lifecycle"
```

---

### Task 2: Core Framework — BehaviorTemplate class

**Files:**
- Create: `scripts/gameplay/goap/behavior_template.gd`

Template manages a sequence of BehaviorSteps. Supports looping (combat, patrol) and interruption with guaranteed exit-phase cleanup.

- [ ] **Step 1: Create BehaviorTemplate class**

```gdscript
## scripts/gameplay/goap/behavior_template.gd
## Predefined sequence of BehaviorSteps. Not searched — executed in order.
## Follows KCD2 pattern: each step has enter-loop-exit lifecycle.
class_name BehaviorTemplate
extends Resource

@export var template_name: String = ""

## Whether this template loops. After last step completes, restart from step 0.
## Only ends when aborted (higher-priority goal) or a step fails.
@export var loops: bool = false

var _steps: Array[BehaviorStep] = []
var _current_step_index: int = 0
var _is_aborting: bool = false
var _started: bool = false
var _entity: Entity = null

## Override in subclasses to build the step list dynamically.
## Called once when the template is activated.
func _build_steps(_agent: CGoapAgent, _entity: Entity) -> Array[BehaviorStep]:
	return []

## Activate this template. Builds steps and starts first step.
func begin(agent: CGoapAgent, entity: Entity) -> BehaviorStep.StepResult:
	_entity = entity
	_steps = _build_steps(agent, entity)
	if _steps.is_empty():
		return BehaviorStep.StepResult.FAILED
	_current_step_index = 0
	_is_aborting = false
	_started = true
	# Check entry conditions of first step
	if not _steps[0].can_enter(agent.world_state):
		return BehaviorStep.StepResult.FAILED
	return BehaviorStep.StepResult.RUNNING

## Tick the current step. Advance on completion, loop or finish.
func tick(agent: CGoapAgent, entity: Entity, delta: float) -> BehaviorStep.StepResult:
	if not _started or _steps.is_empty():
		return BehaviorStep.StepResult.FAILED

	var step: BehaviorStep = _steps[_current_step_index]
	var result: BehaviorStep.StepResult = step.tick(agent, entity, delta)

	if result == BehaviorStep.StepResult.COMPLETED:
		if _is_aborting:
			return BehaviorStep.StepResult.COMPLETED  # abort exit done
		# Advance to next step
		_current_step_index += 1
		if _current_step_index >= _steps.size():
			if loops:
				_current_step_index = 0
				for s: BehaviorStep in _steps:
					s.reset()
				return BehaviorStep.StepResult.RUNNING
			else:
				_started = false
				return BehaviorStep.StepResult.COMPLETED
		# Check next step's entry conditions
		var next_step: BehaviorStep = _steps[_current_step_index]
		if not next_step.can_enter(agent.world_state):
			return BehaviorStep.StepResult.FAILED
		return BehaviorStep.StepResult.RUNNING

	if result == BehaviorStep.StepResult.FAILED:
		_started = false
		return BehaviorStep.StepResult.FAILED

	return BehaviorStep.StepResult.RUNNING

## Abort the template. Forces current step into exit phase.
## Call tick() after abort() to run the exit — returns COMPLETED when done.
func abort(_agent: CGoapAgent) -> void:
	if not _started or _steps.is_empty():
		return
	_is_aborting = true
	var step: BehaviorStep = _steps[_current_step_index]
	step.begin_exit()

## Force-abort: skip exit phase entirely (urgent interruptions like Flee).
func force_abort(_agent: CGoapAgent) -> void:
	_started = false
	_is_aborting = false

func get_current_step_name() -> String:
	if _started and _current_step_index < _steps.size():
		return _steps[_current_step_index].step_name
	return ""

func is_active() -> bool:
	return _started
```

- [ ] **Step 2: Verify no parse errors**

Run: `gol run game --headless -- --quit 2>&1 | grep -i error | head -10`

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/goap/behavior_template.gd
git commit -m "feat(goap): add BehaviorTemplate with step sequencing, looping, and abort"
```

---

### Task 3: Core Framework — StrategicAction class

**Files:**
- Create: `scripts/gameplay/goap/strategic_action.gd`

The Layer 1 planning unit. Replaces GoapAction for planner purposes. Carries viability gate and links to a BehaviorTemplate.

- [ ] **Step 1: Create StrategicAction class**

```gdscript
## scripts/gameplay/goap/strategic_action.gd
## A coarse-grained action for Layer 1 GOAP planning.
## Represents behavioral intent ("Feed", "Fight", "Work"), not physical steps.
## Each StrategicAction owns a BehaviorTemplate for Layer 2 execution.
class_name StrategicAction
extends Resource

@export var action_name: String = ""
@export var cost: float = 1.0
@export var preconditions: Dictionary = {}  ## Dictionary[String, bool] - untyped for .tres compat
@export var effects: Dictionary = {}        ## Dictionary[String, bool]

## Facts that must be true in world state for this action to be worth considering.
## If viability_gate is non-empty and ALL listed facts are false/absent, the planner
## skips this action. At least one gate fact must be true.
## Empty array = always viable (no gate).
@export var viability_gate: Array[String] = []

## The behavior template class to instantiate when this action executes.
## Set via _get_template() override or assigned at registration.
var behavior_template: BehaviorTemplate = null

## Check if preconditions are met against a world state.
func are_preconditions_met(world_state: Dictionary) -> bool:
	for key: String in preconditions:
		var expected: bool = preconditions[key]
		var actual: bool = world_state.get(key, false)
		if actual != expected:
			return false
	return true

## Apply effects to a world state (for A* simulation).
func simulate(world_state: Dictionary) -> Dictionary:
	var new_state: Dictionary = world_state.duplicate()
	for key: String in effects:
		new_state[key] = effects[key]
	return new_state

## Apply effects in place (for A* simulation without alloc).
func apply_effects_in_place(world_state: Dictionary) -> void:
	for key: String in effects:
		world_state[key] = effects[key]

## Check viability gate against world state.
## Returns true if the action is worth considering for planning.
func is_viable(world_state: Dictionary) -> bool:
	if viability_gate.is_empty():
		return true
	for fact: String in viability_gate:
		if world_state.get(fact, false) == true:
			return true
	return false  # All gate facts are false/absent

## Create a BehaviorTemplate instance for execution.
## Override in subclass or set behavior_template directly.
func create_template() -> BehaviorTemplate:
	return behavior_template
```

- [ ] **Step 2: Verify no parse errors**

Run: `gol run game --headless -- --quit 2>&1 | grep -i error | head -10`

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/goap/strategic_action.gd
git commit -m "feat(goap): add StrategicAction class with viability gate"
```

---

### Task 4: Reusable Step Implementations

**Files:**
- Create: `scripts/gameplay/goap/steps/move_to_target_step.gd`
- Create: `scripts/gameplay/goap/steps/timed_action_step.gd`
- Create: `scripts/gameplay/goap/steps/instant_step.gd`
- Create: `scripts/gameplay/goap/steps/flee_step.gd`
- Create: `scripts/gameplay/goap/steps/wander_step.gd`
- Create: `scripts/gameplay/goap/steps/attack_step.gd`
- Create: `scripts/gameplay/goap/steps/position_step.gd`
- Create: `scripts/gameplay/goap/steps/chase_step.gd`
- Create: `scripts/gameplay/goap/steps/build_step.gd`
- Create: `scripts/gameplay/goap/steps/find_work_target_step.gd`
- Create: `scripts/gameplay/goap/steps/patrol_step.gd`

Each step replaces one or more old GoapAction files. The implementation logic is migrated from the old action's `perform()` / `on_plan_enter()` / `on_plan_exit()` into the new enter/loop/exit lifecycle.

**Implementation approach:** For each step, read the corresponding old action file(s) and migrate the core logic:

| New Step | Old Action Source | Key Logic to Migrate |
|----------|------------------|---------------------|
| MoveToTargetStep | `move_to.gd`, `move_to_grass.gd`, `move_to_food_pile.gd`, `move_to_harvestable.gd`, `move_to_resource_node.gd`, `move_to_stockpile.gd` | Perception entity lookup (enter), navigation via CMovement (loop), arrival check (loop→exit) |
| TimedActionStep | `eat_grass.gd`, `gather_resource.gd`, `harvest_bush.gd` | Duration timer (loop), progress bar UI (enter/exit), fact update (exit) |
| InstantStep | `pickup_food.gd`, `deposit_resource.gd` | Immediate fact changes + component updates |
| FleeStep | `flee.gd`, `flee_on_sight.gd` | Move away from nearest enemy (loop), safety check (loop→exit) |
| WanderStep | `wander.gd` | Random target selection (enter), movement (loop) — NO has_threat effect |
| AttackStep | `attack_melee.gd`, `attack_ranged.gd` | Weapon component interaction, damage dealing, target death check |
| PositionStep | `adjust_shoot_position.gd` | Range maintenance, friendly-fire check, LOS validation |
| ChaseStep | `chase_target.gd` | Pursue threat entity, arrival at attack range |
| BuildStep | `goap_action_build.gd` | Add CBuildTask (enter), delegate to SBuildWorker (loop), remove CBuildTask (exit) |
| FindWorkTargetStep | `find_work_target.gd` | Query perception for resource nodes, select nearest |
| PatrolStep | `patrol.gd` | Waypoint navigation loop — MUST return COMPLETED at each waypoint |

**Each step file follows the same pattern. Example for MoveToTargetStep:**

- [ ] **Step 1: Create MoveToTargetStep**

```gdscript
## scripts/gameplay/goap/steps/move_to_target_step.gd
## Reusable step: navigate to a target identified by a perception fact.
## Replaces: move_to_grass, move_to_food_pile, move_to_harvestable, etc.
class_name MoveToTargetStep
extends BehaviorStep

## The perception entity type to search for. Maps to component classes.
## "grass" → CEatable, "food_pile" → CResourcePickup, "harvestable" → CResourceNode,
## "stockpile" → CStockpile, "threat" → nearest enemy, "work_target" → from blackboard
@export var target_type: String = ""

## World state fact to set to true when arrived.
@export var arrival_fact: String = ""

## How close the agent must be to consider "arrived".
@export var arrival_threshold: float = 16.0

var _target_entity: Entity = null
var _target_position: Vector2 = Vector2.ZERO

func enter(agent: CGoapAgent, entity: Entity, _delta: float) -> StepResult:
	_target_entity = _find_target(agent, entity)
	if _target_entity == null:
		return StepResult.FAILED
	var target_transform: CTransform = _target_entity.get_component(CTransform)
	if target_transform == null:
		return StepResult.FAILED
	_target_position = target_transform.position
	return StepResult.COMPLETED

func loop(agent: CGoapAgent, entity: Entity, delta: float) -> StepResult:
	# Check target still valid
	if not is_instance_valid(_target_entity):
		return StepResult.FAILED
	var transform: CTransform = entity.get_component(CTransform)
	var movement: CMovement = entity.get_component(CMovement)
	if transform == null or movement == null:
		return StepResult.FAILED
	# Update target position (entity may move)
	var target_transform: CTransform = _target_entity.get_component(CTransform)
	if target_transform != null:
		_target_position = target_transform.position
	# Check arrival
	var distance: float = transform.position.distance_to(_target_position)
	if distance <= arrival_threshold:
		return StepResult.COMPLETED
	# Move toward target
	var direction: Vector2 = (_target_position - transform.position).normalized()
	movement.velocity = direction * movement.get_patrol_speed()
	return StepResult.RUNNING

func exit(agent: CGoapAgent, entity: Entity, _delta: float) -> StepResult:
	# Stop movement
	var movement: CMovement = entity.get_component(CMovement)
	if movement != null:
		movement.velocity = Vector2.ZERO
	# Set arrival fact
	if not arrival_fact.is_empty():
		agent.world_state.update_fact(arrival_fact, true)
	# Store target entity in blackboard for next step
	agent.blackboard["current_target"] = _target_entity
	return StepResult.COMPLETED

func _find_target(agent: CGoapAgent, entity: Entity) -> Entity:
	# Target lookup based on target_type — migrated from old move_to_* actions
	var perception: CPerception = entity.get_component(CPerception)
	if perception == null:
		return null
	match target_type:
		"grass":
			return _find_nearest_with_component(perception, entity, CEatable)
		"food_pile":
			return _find_nearest_food_pile(perception, entity)
		"harvestable":
			return _find_nearest_harvestable(perception, entity)
		"resource_node":
			return _find_nearest_resource_node(perception, entity)
		"stockpile":
			return _find_accepting_stockpile(entity)
		"threat":
			return _find_nearest_threat(perception, entity)
		"work_target":
			return agent.blackboard.get("work_target_entity", null)
		"guard_post":
			return _find_guard_post(entity)
	return null

func _find_nearest_with_component(perception: CPerception, entity: Entity, component_class: GDScript) -> Entity:
	var transform: CTransform = entity.get_component(CTransform)
	if transform == null:
		return null
	var best: Entity = null
	var best_dist: float = INF
	for visible: Entity in perception._visible_entities:
		if not is_instance_valid(visible):
			continue
		if visible.has_component(component_class):
			var vt: CTransform = visible.get_component(CTransform)
			if vt == null:
				continue
			var dist: float = transform.position.distance_squared_to(vt.position)
			if dist < best_dist:
				best_dist = dist
				best = visible
	return best

func _find_nearest_food_pile(perception: CPerception, entity: Entity) -> Entity:
	# Migrated from move_to_food_pile.gd — looks for CResourcePickup with RFood
	var transform: CTransform = entity.get_component(CTransform)
	if transform == null:
		return null
	var best: Entity = null
	var best_dist: float = INF
	for visible: Entity in perception._visible_entities:
		if not is_instance_valid(visible):
			continue
		var pickup: CResourcePickup = visible.get_component(CResourcePickup)
		if pickup != null and pickup.resource_type is RFood:
			var vt: CTransform = visible.get_component(CTransform)
			if vt == null:
				continue
			var dist: float = transform.position.distance_squared_to(vt.position)
			if dist < best_dist:
				best_dist = dist
				best = visible
	return best

func _find_nearest_harvestable(perception: CPerception, entity: Entity) -> Entity:
	# Migrated from move_to_harvestable.gd — looks for CResourceNode.can_gather()
	var transform: CTransform = entity.get_component(CTransform)
	if transform == null:
		return null
	var best: Entity = null
	var best_dist: float = INF
	for visible: Entity in perception._visible_entities:
		if not is_instance_valid(visible):
			continue
		var node: CResourceNode = visible.get_component(CResourceNode)
		if node != null and node.can_gather():
			var vt: CTransform = visible.get_component(CTransform)
			if vt == null:
				continue
			var dist: float = transform.position.distance_squared_to(vt.position)
			if dist < best_dist:
				best_dist = dist
				best = visible
	return best

func _find_nearest_resource_node(perception: CPerception, entity: Entity) -> Entity:
	# Same as harvestable but for work targets
	return _find_nearest_harvestable(perception, entity)

func _find_accepting_stockpile(entity: Entity) -> Entity:
	# Migrated from move_to_stockpile.gd — query world for CStockpile that can accept
	var worker: CWorker = entity.get_component(CWorker)
	if worker == null:
		return null
	var carrying: CCarrying = entity.get_component(CCarrying)
	if carrying == null:
		return null
	var transform: CTransform = entity.get_component(CTransform)
	if transform == null:
		return null
	var best: Entity = null
	var best_dist: float = INF
	for sp_entity: Entity in ECS.world.query.with_all([CStockpile, CTransform]).execute():
		if sp_entity.has_component(CWorker):
			continue  # Skip worker entities
		var sp: CStockpile = sp_entity.get_component(CStockpile)
		if not sp.can_accept(carrying.resource_type, carrying.amount):
			continue
		var spt: CTransform = sp_entity.get_component(CTransform)
		var dist: float = transform.position.distance_squared_to(spt.position)
		if dist < best_dist:
			best_dist = dist
			best = sp_entity
	return best

func _find_nearest_threat(perception: CPerception, entity: Entity) -> Entity:
	# Use perception's nearest_enemy if available
	var nearest: Entity = perception.nearest_enemy
	if is_instance_valid(nearest):
		return nearest
	return null

func _find_guard_post(entity: Entity) -> Entity:
	# Guard post is stored in CGuard component
	var guard: CGuard = entity.get_component(CGuard)
	if guard != null and is_instance_valid(guard.camp_entity):
		return guard.camp_entity
	return null
```

- [ ] **Step 2: Create remaining step files**

Create each step file following the same enter/loop/exit pattern. Key migration notes for each:

**TimedActionStep** — from eat_grass.gd, harvest_bush.gd, gather_resource.gd:
- enter: start timer, optionally show progress UI via `ServiceContext.ui().push_view()`
- loop: accumulate delta, return COMPLETED when timer expires
- exit: pop progress UI, set completion_fact

**InstantStep** — from pickup_food.gd, deposit_resource.gd:
- enter: return COMPLETED immediately
- loop: set all facts_to_set, return COMPLETED
- exit: no-op

**FleeStep** — from flee.gd + flee_on_sight.gd:
- enter: identify threat to flee from
- loop: move away from threat, check if safe (distance threshold)
- exit: stop movement, set is_safe

**WanderStep** — from wander.gd (BUG FIX: NO has_threat effect):
- enter: pick random target within radius
- loop: walk to target
- exit: stop, set is_exploring

**AttackStep** — from attack_melee.gd + attack_ranged.gd:
- enter: acquire target from blackboard/perception
- loop: execute attack (weapon component), check target death
- exit: update has_threat/is_safe facts

**PositionStep** — from adjust_shoot_position.gd:
- enter: check weapon range requirements
- loop: adjust position for LOS, check friendly fire
- exit: set ready_ranged_attack

**ChaseStep** — from chase_target.gd:
- enter: acquire threat target
- loop: move toward target, check attack range
- exit: set is_threat_in_attack_range, ready_melee_attack

**BuildStep** — from goap_action_build.gd:
- enter: find nearest incomplete ghost, add CBuildTask
- loop: delegate to SBuildWorker FSM
- exit: remove CBuildTask

**FindWorkTargetStep** — from find_work_target.gd:
- enter: query perception for resource nodes
- loop: select nearest valid target, store in blackboard
- exit: set has_work_target

**PatrolStep** — from patrol.gd (BUG FIX: MUST return COMPLETED):
- enter: get patrol waypoints from CGuard
- loop: walk between waypoints
- exit: set is_patrolling

- [ ] **Step 3: Verify no parse errors**

Run: `gol run game --headless -- --quit 2>&1 | grep -i error | head -10`

- [ ] **Step 4: Commit**

```bash
git add scripts/gameplay/goap/steps/
git commit -m "feat(goap): add 11 reusable behavior step implementations

Migrates logic from 23 old GoapAction files into enter-loop-exit steps:
MoveToTargetStep, TimedActionStep, InstantStep, FleeStep, WanderStep,
AttackStep, PositionStep, ChaseStep, BuildStep, FindWorkTargetStep, PatrolStep"
```

---

### Task 5: Behavior Templates

**Files:**
- Create: `scripts/gameplay/goap/templates/feed_template.gd` (and all 9 others)

Each template composes BehaviorSteps into the predefined sequences from the spec.

- [ ] **Step 1: Create all 10 template files**

**FeedTemplate** — 3 variants (grass/bush/pile) resolved in `_build_steps()`:

```gdscript
## scripts/gameplay/goap/templates/feed_template.gd
class_name FeedTemplate
extends BehaviorTemplate

func _init() -> void:
	template_name = "Feed"
	loops = false

func _build_steps(agent: CGoapAgent, entity: Entity) -> Array[BehaviorStep]:
	var facts := agent.world_state.facts
	# Select variant based on perception facts — prefer nearest food source
	var transform: CTransform = entity.get_component(CTransform)
	var perception: CPerception = entity.get_component(CPerception)
	if transform == null or perception == null:
		return []

	var best_type: String = ""
	var best_dist: float = INF

	if facts.get("sees_grass", false):
		var dist := _nearest_distance(perception, entity, transform, CEatable)
		if dist < best_dist:
			best_dist = dist
			best_type = "grass"

	if facts.get("sees_food_pile", false):
		var dist := _nearest_distance_food_pile(perception, entity, transform)
		if dist < best_dist:
			best_dist = dist
			best_type = "food_pile"

	if facts.get("sees_harvestable", false):
		var dist := _nearest_distance_harvestable(perception, entity, transform)
		if dist < best_dist:
			best_dist = dist
			best_type = "harvestable"

	match best_type:
		"grass":
			var move := MoveToTargetStep.new()
			move.step_name = "MoveToGrass"
			move.target_type = "grass"
			move.arrival_fact = "adjacent_to_grass"
			var eat := TimedActionStep.new()
			eat.step_name = "EatGrass"
			eat.duration_seconds = 1.5
			eat.completion_fact = "is_fed"
			return [move, eat]
		"food_pile":
			var move := MoveToTargetStep.new()
			move.step_name = "MoveToFoodPile"
			move.target_type = "food_pile"
			move.arrival_fact = "adjacent_to_food_pile"
			var pickup := InstantStep.new()
			pickup.step_name = "PickupFood"
			pickup.facts_to_set = {"is_fed": true}
			return [move, pickup]
		"harvestable":
			var move := MoveToTargetStep.new()
			move.step_name = "MoveToHarvestable"
			move.target_type = "harvestable"
			move.arrival_fact = "adjacent_to_harvestable"
			var harvest := TimedActionStep.new()
			harvest.step_name = "HarvestBush"
			harvest.duration_seconds = 2.0
			harvest.completion_fact = "is_fed"
			return [move, harvest]

	return []  # No food source found

# Distance helpers for variant selection
func _nearest_distance(perception: CPerception, _entity: Entity, transform: CTransform, component_class: GDScript) -> float:
	var best: float = INF
	for visible: Entity in perception._visible_entities:
		if not is_instance_valid(visible) or not visible.has_component(component_class):
			continue
		var vt: CTransform = visible.get_component(CTransform)
		if vt != null:
			best = minf(best, transform.position.distance_squared_to(vt.position))
	return best

func _nearest_distance_food_pile(perception: CPerception, _entity: Entity, transform: CTransform) -> float:
	var best: float = INF
	for visible: Entity in perception._visible_entities:
		if not is_instance_valid(visible):
			continue
		var pickup: CResourcePickup = visible.get_component(CResourcePickup)
		if pickup != null and pickup.resource_type is RFood:
			var vt: CTransform = visible.get_component(CTransform)
			if vt != null:
				best = minf(best, transform.position.distance_squared_to(vt.position))
	return best

func _nearest_distance_harvestable(perception: CPerception, _entity: Entity, transform: CTransform) -> float:
	var best: float = INF
	for visible: Entity in perception._visible_entities:
		if not is_instance_valid(visible):
			continue
		var node: CResourceNode = visible.get_component(CResourceNode)
		if node != null and node.can_gather():
			var vt: CTransform = visible.get_component(CTransform)
			if vt != null:
				best = minf(best, transform.position.distance_squared_to(vt.position))
	return best
```

**Other templates follow similar pattern — create each file with `_build_steps()` composing the right steps:**

- `work_template.gd` — WorkTemplate: [FindWorkTargetStep → MoveToTargetStep(work_target) → TimedActionStep(gather, 3s) → MoveToTargetStep(stockpile) → InstantStep(has_delivered)]
- `build_template.gd` — BuildTemplate: [BuildStep]
- `fight_melee_template.gd` — FightMeleeTemplate: loops=true, [ChaseStep → AttackStep(melee)]
- `fight_ranged_template.gd` — FightRangedTemplate: loops=true, [PositionStep → AttackStep(ranged)]
- `flee_template.gd` — FleeTemplate: [FleeStep]
- `patrol_template.gd` — PatrolTemplate: loops=true, [PatrolStep]
- `explore_template.gd` — ExploreTemplate: loops=true, [WanderStep]
- `guard_template.gd` — GuardTemplate: [MoveToTargetStep(guard_post)]
- `rest_template.gd` — RestTemplate: [TimedActionStep(5s, is_rested)]

- [ ] **Step 2: Verify no parse errors**

Run: `gol run game --headless -- --quit 2>&1 | grep -i error | head -10`

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/goap/templates/
git commit -m "feat(goap): add 10 behavior templates composing step sequences

FeedTemplate (3 variants), WorkTemplate, BuildTemplate, FightMeleeTemplate,
FightRangedTemplate, FleeTemplate, PatrolTemplate, ExploreTemplate,
GuardTemplate, RestTemplate"
```

---

### Task 6: Strategic Action .tres Resources

**Files:**
- Create: `scripts/gameplay/goap/strategic_actions/sa_feed.tres` (and 9 others)

Create .tres Resource files for each strategic action with preconditions, effects, costs, viability gates.

- [ ] **Step 1: Create all 10 .tres files**

Each .tres references StrategicAction script and sets exported fields per the spec's Post-Migration Strategic Actions table.

Note: The `behavior_template` var is not exported (it's runtime-assigned). Each StrategicAction subclass or factory will set it. Alternatively, create thin GDScript subclasses for each strategic action that override `create_template()` to return the right template. This is the simpler approach:

Create `scripts/gameplay/goap/strategic_actions/` directory with 10 .gd files (one per action), each a minimal subclass:

```gdscript
## scripts/gameplay/goap/strategic_actions/sa_feed.gd
class_name SA_Feed
extends StrategicAction

func _init() -> void:
	action_name = "Feed"
	cost = 3.0
	preconditions = {"is_fed": false}
	effects = {"is_fed": true}
	viability_gate = ["sees_grass", "sees_food_pile", "sees_harvestable"]

func create_template() -> BehaviorTemplate:
	return FeedTemplate.new()
```

Repeat for all 10: SA_Feed, SA_Work, SA_Build, SA_FightMelee, SA_FightRanged, SA_Flee, SA_Patrol, SA_Explore, SA_Guard, SA_Rest. Each with values from spec table.

- [ ] **Step 2: Verify no parse errors**

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/goap/strategic_actions/
git commit -m "feat(goap): add 10 strategic action definitions with viability gates"
```

---

### Task 7: Update CGoapAgent Component

**Files:**
- Modify: `scripts/components/ai/c_goap_agent.gd`

Add NPC state fields (KCD2 pattern), template execution state, and strategic action configuration.

- [ ] **Step 1: Rewrite c_goap_agent.gd**

Keep existing fields that are still needed (`world_state`, `goals`, `update_interval`, `blackboard`, `_update_timer`). Remove old plan fields. Add new fields.

```gdscript
class_name CGoapAgent
extends Component

## --- World State ---
var world_state: GoapWorldState = GoapWorldState.new()
@export var goals: Array[GoapGoal] = []
@export var update_interval: float = 0.15

## --- NPC State (KCD2 pattern) ---
var posture: StringName = &"standing"    ## standing, crouching, sitting
var held_item: StringName = &"none"      ## none, pickaxe, sword, bow
var activity: StringName = &"idle"       ## idle, working, eating, fighting, fleeing, patrolling

## --- Layer 1 State (written by SGoalDecision) ---
var pending_strategic_action: StrategicAction = null
var current_goal: GoapGoal = null
var current_strategic_action: StrategicAction = null
var needs_decision: bool = true

## --- Layer 2 State (managed by SPlanExecution) ---
var active_template: BehaviorTemplate = null

## --- Agent Configuration ---
## Strategic actions this agent can use. Registered at spawn by recipe/authoring.
var allowed_strategic_actions: Array[StrategicAction] = []

## --- Shared State ---
var blackboard: Dictionary = {}
var _update_timer: float = 0.0
var _pending_decision_delta: float = 0.0

func _init() -> void:
	_update_timer = randf_range(0.0, update_interval)

func get_sorted_goals() -> Array[GoapGoal]:
	var sorted: Array[GoapGoal] = goals.duplicate()
	sorted.sort_custom(func(a: GoapGoal, b: GoapGoal) -> bool:
		return a.priority > b.priority)
	return sorted

## Get viable strategic actions (filtered by viability gate against current world state).
func get_viable_actions() -> Array[StrategicAction]:
	var viable: Array[StrategicAction] = []
	var facts := world_state.facts
	for action: StrategicAction in allowed_strategic_actions:
		if action.is_viable(facts):
			viable.append(action)
	return viable
```

- [ ] **Step 2: Verify no parse errors**

- [ ] **Step 3: Commit**

```bash
git add scripts/components/ai/c_goap_agent.gd
git commit -m "refactor(goap): update CGoapAgent for three-layer architecture

Add NPC state (posture, held_item, activity), template execution state,
strategic action config. Remove old plan/running_action fields."
```

---

### Task 8: Update GoapPlanner for Strategic Actions

**Files:**
- Modify: `scripts/gameplay/goap/goap_planner.gd`

The planner's A* search stays but operates on StrategicAction arrays instead of GoapAction. Add viability gate filtering. Remove old action auto-discovery from `actions/` directory.

- [ ] **Step 1: Update planner to accept StrategicAction**

Key changes:
- `build_plan_for_goal()` accepts `Array[StrategicAction]` instead of `Array[GoapAction]`
- Remove `get_all_actions()`, `_load_all_action_scripts()`, `_cached_action_scripts`, `_cached_action_instances` — no more auto-discovery
- `_plan_for_goal()` uses `StrategicAction.are_preconditions_met()` and `.simulate()`
- The heuristic and cache key logic stays the same (operates on Dictionary world state)
- Add viability gate pre-filter: before A* loop, filter actions by `action.is_viable(world_state)`

- [ ] **Step 2: Verify no parse errors**

- [ ] **Step 3: Commit**

```bash
git add scripts/gameplay/goap/goap_planner.gd
git commit -m "refactor(goap): update planner for StrategicAction arrays

Remove old action auto-discovery. Accept StrategicAction with viability
gate pre-filtering. A* search logic unchanged."
```

---

### Task 9: New Systems — SGoalDecision + SPlanExecution

**Files:**
- Create: `scripts/systems/s_goal_decision.gd`
- Create: `scripts/systems/s_plan_execution.gd`

These two systems replace `s_ai.gd`. SGoalDecision handles Layer 1 (rate-limited planning). SPlanExecution handles Layer 2+3 (every-frame template execution).

- [ ] **Step 1: Create SGoalDecision**

Migrates from s_ai.gd's Pass 2 (decision tick). Key logic:
- `query()` → `q.with_all([CGoapAgent, CMovement, CTransform])`
- `process()` → accumulate delta per agent, check update_interval, rate-limit to MAX_DECISIONS_PER_FRAME=3 with 3ms budget
- `_process_decision_tick()` → get sorted goals, for each unsatisfied goal call `_planner.build_plan_for_goal()` with `agent.get_viable_actions()`, write result to `agent.pending_strategic_action`
- LOD distance-based interval adjustment from old s_ai.gd
- Profiling hooks: record decision time, gate skips, action selected

```gdscript
class_name SGoalDecision
extends System

const MAX_DECISIONS_PER_FRAME: int = 3
const DECISION_FRAME_HARD_BUDGET_MS: float = 3.0

var _planner: GoapPlanner = GoapPlanner.new()
var _decisions_this_frame: int = 0
var _decision_ms_this_frame: float = 0.0
# ... (full implementation migrated from s_ai.gd Pass 2)
```

- [ ] **Step 2: Create SPlanExecution**

Migrates from s_ai.gd's Pass 1 (action tick). Key logic:
- `query()` → same as SGoalDecision
- `process()` → for each entity:
  1. If `pending_strategic_action != null` → abort current template (with exit phase), create new template, begin it
  2. If `active_template != null` → tick template
  3. On COMPLETED/FAILED → set `needs_decision = true`, clear template
- Emit `threat_state_changed` signal (migrated from s_ai)

```gdscript
class_name SPlanExecution
extends System

signal threat_state_changed(entity: Entity, has_threat: bool)
# ... (full implementation migrated from s_ai.gd Pass 1)
```

- [ ] **Step 3: Register new systems, remove old s_ai registration**

Find where `SAI` is registered with `ECS.world.add_system()` and replace with `SGoalDecision` + `SPlanExecution`. SPlanExecution runs first (higher priority), SGoalDecision second.

- [ ] **Step 4: Verify compilation**

Run: `gol run game --headless -- --quit 2>&1 | grep -i error | head -20`

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/s_goal_decision.gd scripts/systems/s_plan_execution.gd
git commit -m "feat(goap): add SGoalDecision + SPlanExecution systems

SGoalDecision: rate-limited Layer 1 planning (max 3/frame, 3ms budget).
SPlanExecution: every-frame Layer 2+3 template execution with KCD2
enter-loop-exit lifecycle and guaranteed exit-phase on interruption."
```

---

### Task 10: Update Goal Resources and Entity Recipes

**Files:**
- Modify: `resources/goals/*.tres` — clean up goals
- Modify: `resources/recipes/{rabbit,survivor,survivor_healer,npc_worker,npc_composer,enemy_basic,enemy_raider}.tres` — update goal assignments and add strategic action config
- Delete: `resources/goals/wander.tres`, `resources/goals/march_to_campfire.tres`, `resources/goals/clear_threat.tres`
- Create: `resources/goals/explore.tres` — new goal for Explore strategic action

- [ ] **Step 1: Update goal .tres files**

- Remove `wander.tres` (desired_state `{has_threat:true}` is buggy) → replaced by `explore.tres`
- Create `explore.tres`: goal_name="Explore", priority=1, desired_state={is_exploring: true}
- Remove `march_to_campfire.tres` (unused)
- Remove `clear_threat.tres` (same desired_state as eliminate_threat, consolidate)
- Keep all others as-is

- [ ] **Step 2: Update entity recipes**

For each recipe, update the CGoapAgent goals array and add `allowed_strategic_actions` configuration. The recipe system uses `base_recipe` inheritance, so changes to `enemy_basic.tres` propagate to all elemental variants.

| Recipe | Goals (updated) | Strategic Actions |
|--------|----------------|-------------------|
| rabbit.tres | survive_on_sight, feed_self, explore | SA_Flee, SA_Feed, SA_Explore |
| survivor.tres | survive, guard_duty, eliminate_threat, patrol_camp, feed_self | SA_Flee, SA_FightMelee, SA_FightRanged, SA_Guard, SA_Patrol, SA_Feed |
| survivor_healer.tres | survive, guard_duty, eliminate_threat, patrol_camp | SA_Flee, SA_FightMelee, SA_Guard, SA_Patrol |
| npc_worker.tres | survive, feed_self, work, build | SA_Flee, SA_Feed, SA_Work, SA_Build |
| npc_composer.tres | survive, explore | SA_Flee, SA_Explore |
| enemy_basic.tres | eliminate_threat, explore | SA_FightMelee, SA_FightRanged, SA_Flee, SA_Explore |
| enemy_raider.tres | eliminate_threat, explore | SA_FightMelee, SA_FightRanged, SA_Flee, SA_Explore |

- [ ] **Step 3: Commit**

```bash
git add resources/goals/ resources/recipes/
git commit -m "refactor(goap): update goals and recipes for three-layer architecture

Remove wander/march_to_campfire/clear_threat goals. Add explore goal.
Update all 9 agent recipes with strategic action assignments."
```

---

### Task 11: Delete Old Code

**Files:**
- Delete: `scripts/gameplay/goap/actions/` (entire directory, 23 files)
- Delete: `scripts/gameplay/goap/goap_action.gd`
- Delete: `scripts/gameplay/goap/goap_plan.gd`
- Delete: `scripts/gameplay/goap/goap_plan_step.gd`
- Delete: `scripts/gameplay/goap/goals/goap_goal_build.gd`
- Delete: `scripts/systems/s_ai.gd`

- [ ] **Step 1: Delete all old files**

```bash
rm -rf scripts/gameplay/goap/actions/
rm scripts/gameplay/goap/goap_action.gd
rm scripts/gameplay/goap/goap_plan.gd
rm scripts/gameplay/goap/goap_plan_step.gd
rm scripts/gameplay/goap/goals/goap_goal_build.gd
rm scripts/systems/s_ai.gd
```

- [ ] **Step 2: Find and fix any remaining references**

```bash
grep -rn "GoapAction\b\|GoapPlan\b\|GoapPlanStep\b\|SAI\b\|s_ai\b" scripts/ resources/ --include="*.gd" --include="*.tres" --include="*.tscn"
```

Fix any remaining references to point to new classes.

- [ ] **Step 3: Verify game loads without errors**

Run: `gol run game --headless -- --quit 2>&1 | grep -i error`

Expected: zero errors. All references to old code replaced.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(goap): remove old flat action system and s_ai

Delete 23 old GoapAction files, GoapAction base class, GoapPlan,
GoapPlanStep, GoapGoal_Build stub, and monolithic s_ai.gd.
All functionality migrated to three-layer architecture."
```

---

### Task 12: Update Eval Tool

**Files:**
- Modify: `scripts/tests/goap_eval_main.gd`
- Modify: `scripts/tests/goap_metrics_collector.gd`
- Modify: `scripts/tests/goap_eval_report.gd`
- Modify: `scripts/tests/goap_planner_bench.gd`
- Modify: `scripts/tests/goap_feasibility_checker.gd`
- Modify: `gol-tools/cli/cmd/goap_eval.go`

- [ ] **Step 1: Update goap_eval_main.gd**

Key changes:
- `_discover_goals()` → load actual .tres files instead of hardcoding (fixes priority discrepancy)
- Remove old GoapAction references
- Update profiling hooks for new SGoalDecision + SPlanExecution
- Update BUDGETS to new targets from spec:
  ```gdscript
  const BUDGETS := {
      "avg_search_time_us": 50,
      "avg_iterations_max": 10,
      "plan_found_rate_min": 0.90,
      "decision_time_avg_us": 200,
      "decision_time_p99_us": 1000,
      "step_failures_per_s": 1.0,
      "template_interruptions_per_s": 2.0,
  }
  ```

- [ ] **Step 2: Update goap_metrics_collector.gd**

Add new metric groups per spec:
- Decision metrics: from SGoalDecision profiling data
- Execution metrics: from SPlanExecution profiling data (templates_active, step_completions, step_failures, template_interruptions, avg_template_lifetime)
- Planning metrics: same as before but with strategic action counts
- Remove old cache metrics (smart cache is Phase 3, deferred)

- [ ] **Step 3: Update goap_eval_report.gd**

New report format:
```
GOAP Eval | N agents | Xf (Ys)
Status: PASS/FAIL (N/M budgets met)

Decision (SGoalDecision):
  dec/f X.X  avg Xus  p99 Xus  gate_skips X  backoff_skips X

Execution (SPlanExecution):
  templates X  steps/s X.X  failures/s X.X  interrupts/s X.X

Planning (GoapPlanner):
  avg Xus  max Xus  iter avg X.X  found X.X%

Per-Goal: ...
Per-Agent: ...

Budget: ...
```

- [ ] **Step 4: Update goap_planner_bench.gd**

Rewrite benchmarks to use StrategicAction arrays:
- `rabbit/feed`: SA_Feed + SA_Flee + SA_Explore, sees_grass=true → should find Feed in 1-2 iterations
- `rabbit/feed_blocked`: sees_grass=false → SA_Feed gated, planner sees only SA_Flee + SA_Explore
- `worker/work`: SA_Work + SA_Feed + SA_Build + SA_Flee → should find Work in 1-2 iterations
- `guard/combat`: SA_FightMelee + SA_FightRanged + ... → should find FightMelee/Ranged quickly

- [ ] **Step 5: Update goap_feasibility_checker.gd**

Update to work with StrategicAction instead of GoapAction. Simplify — with viability gates built into actions, feasibility is mostly "does at least one action have a viable gate for this goal?"

- [ ] **Step 6: Update goap_eval.go CLI filter**

Add new output line prefixes: `"Decision"`, `"Execution"`, `"Planning"`, `"templates"`, `"steps/s"`.

- [ ] **Step 7: Commit**

```bash
git add scripts/tests/ gol-tools/cli/cmd/goap_eval.go
git commit -m "refactor(goap-eval): update eval suite for three-layer architecture

New metric groups: Decision (SGoalDecision), Execution (SPlanExecution),
Planning (strategic actions). Updated budgets, benchmarks, report format.
Goals loaded from .tres files instead of hardcoded."
```

---

### Task 13: Integration Test — Run Eval and Verify

**Files:** (no file changes — verification only)

- [ ] **Step 1: Run the full eval suite**

```bash
gol test goap --json --duration=60
```

Expected: All budgets PASS. Specifically:
- avg_search_time_us < 50 (was 12,862)
- avg_iterations < 10 (was 246)
- plan_found_rate > 90% (was 3.8%)

- [ ] **Step 2: Run the game windowed and observe NPC behavior**

```bash
gol run game --windowed -- --skip-menu
```

Manually verify:
- Rabbits still eat grass, flee from threats, wander when idle
- Workers still gather resources, deliver to stockpile, build
- Guards still patrol, fight enemies, return to post
- Enemies still chase and attack the player
- No stuck NPCs, no animation glitches, no error spam in console

- [ ] **Step 3: Run unit tests**

```bash
gol test unit --suite goap -v
```

Expected: all existing GOAP unit tests pass (or are updated to use new classes)

- [ ] **Step 4: If any issues, fix and re-run**

- [ ] **Step 5: Commit eval results**

```bash
git add logs/tests/
git commit -m "test(goap): baseline eval results after three-layer migration"
```

---

### Task 14: Update AGENTS.md Documentation

**Files:**
- Modify: `scripts/gameplay/goap/AGENTS.md` (if exists) or `scripts/gameplay/AGENTS.md`
- Modify: `scripts/systems/AGENTS.md`

- [ ] **Step 1: Update AGENTS.md files with new architecture**

Document:
- Three-layer architecture overview
- Strategic action catalog
- Template catalog  
- BehaviorStep enter-loop-exit pattern
- SGoalDecision + SPlanExecution system descriptions
- How to add a new behavior (create step → create template → create strategic action → add to recipe)

- [ ] **Step 2: Commit**

```bash
git add scripts/gameplay/AGENTS.md scripts/systems/AGENTS.md
git commit -m "docs: update AGENTS.md for three-layer GOAP architecture"
```

---

## Verification

After all tasks complete:

1. **`gol test goap --json --duration=60`** — all 7 budgets PASS
2. **`gol test`** — all unit + integration tests pass
3. **`gol run game --windowed -- --skip-menu`** — NPCs behave identically to before
4. **No references to old code** — `grep -rn "GoapAction\b\|GoapPlan\b\|SAI\b" scripts/ resources/` returns nothing
5. **No dead files** — `scripts/gameplay/goap/actions/` directory does not exist, `s_ai.gd` does not exist
