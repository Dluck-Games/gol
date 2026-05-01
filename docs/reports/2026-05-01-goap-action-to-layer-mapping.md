# GOAP Action-to-Layer Mapping Report

**Date:** 2026-05-01
**Context:** Three-layer architecture refactoring completion acceptance
**Purpose:** Document how the 23 legacy flat `GoapAction` classes map to the new Layer 1/2/3 hierarchy

---

## Architecture Overview

The old system had 23+ individual `GoapAction` subclasses, all competing in a single A* planner that produced multi-step plans. The new system splits responsibility across three layers:

| Layer | Abstraction | What It Does | Count |
|-------|-------------|--------------|-------|
| **Layer 1** | `StrategicAction` | Coarse-grained goal achievement, selected by A* | 10 |
| **Layer 2** | `BehaviorTemplate` | Predefined step sequence, variant resolution at runtime | 10 |
| **Layer 3** | `BehaviorStep` + ECS Systems | Atomic execution with `enter()` → `loop()` → `exit()` lifecycle | 14 steps + systems |

---

## Layer 1 — StrategicAction

These replace the *top-level intent* of old actions. Each has `preconditions`, `effects`, `cost`, and a `viability_gate`.

| StrategicAction | Purpose | Viability Gate | Replaces Old Actions |
|-----------------|---------|----------------|----------------------|
| `SA_Work` | Gather resource and deliver to stockpile | — | `find_work_target`, `gather_resource`, `move_to_resource_node`, `move_to_stockpile`, `deposit_resource` |
| `SA_Feed` | Restore hunger via nearest food source | `has_visible_grass` / `has_visible_food_pile` / `has_visible_harvestable` | `eat_grass`, `pickup_food`, `move_to_grass`, `move_to_food_pile`, `move_to_harvestable`, `harvest_bush` |
| `SA_FightMelee` | Close-quarters combat | `has_threat` | `attack_melee`, `chase_target` |
| `SA_FightRanged` | Ranged combat | `has_threat` + `has_shooter_weapon` | `attack_ranged`, `adjust_shoot_position`, `chase_target` |
| `SA_Flee` | Escape from threat | `has_threat` | `flee`, `flee_on_sight` |
| `SA_Patrol` | Guard waypoint loop | `is_guard` | `patrol`, `march_to_campfire`, `return_to_camp` |
| `SA_Guard` | Hold position near guard post | `is_guard` | (new — no direct old equivalent) |
| `SA_Explore` | Wander to discover map | — | `wander` |
| `SA_Rest` | Recover at campfire | — | (new — no direct old equivalent) |
| `SA_Build` | Construct a building | — | `goap_action_build` |

---

## Layer 2 — BehaviorTemplate

Each `StrategicAction.create_template()` returns one of these. Templates define the *step sequence* and whether it loops.

| Template | Steps | Loops | Replaces Old Actions |
|----------|-------|-------|----------------------|
| `WorkTemplate` | `FindWorkTarget` → `MoveToWorkTarget` → `GatherResource` → `MoveToStockpile` → `DeliverResource` | no | `find_work_target` + `move_to_*` + `gather_resource` + `deposit_resource` |
| `FeedTemplate` | Variant A: `MoveToGrass` → `EatGrass`<br>Variant B: `MoveToFoodPile` → `PickupFood`<br>Variant C: `MoveToHarvestable` → `HarvestBush` | no | `move_to_grass` / `eat_grass`, `move_to_food_pile` / `pickup_food`, `move_to_harvestable` / `harvest_bush` |
| `FightMeleeTemplate` | `Chase` → `AttackMelee` | **yes** | `chase_target` + `attack_melee` |
| `FightRangedTemplate` | `Position` → `AttackRanged` | **yes** | `adjust_shoot_position` + `attack_ranged` |
| `FleeTemplate` | `Flee` | no | `flee` |
| `PatrolTemplate` | `Patrol` | no | `patrol` |
| `GuardTemplate` | `MoveToGuardPost` | no | `march_to_campfire` / `return_to_camp` |
| `ExploreTemplate` | `Wander` | no | `wander` |
| `RestTemplate` | `MoveToCampfire` → `Rest` | no | (new) |
| `BuildTemplate` | `MoveToBuildSite` → `Build` | no | `goap_action_build` |

---

## Layer 3 — BehaviorStep + ECS Systems

Steps are the atomic execution units. They run inside `SPlanExecution` but delegate actual game effects to existing ECS systems.

| Step | Lifecycle | Delegates To | Replaces Old Actions |
|------|-----------|--------------|----------------------|
| `MoveToTargetStep` | `loop()` sets `CMovement.velocity` toward target | `SMove` (physics) | `move_to`, `move_to_grass`, `move_to_food_pile`, `move_to_harvestable`, `move_to_resource_node`, `move_to_stockpile`, `march_to_campfire`, `return_to_camp` |
| `ChaseStep` | `loop()` sets velocity toward threat | `SMove` | `chase_target` |
| `FleeStep` | `loop()` sets velocity away from threat | `SMove` | `flee`, `flee_on_sight` |
| `WanderStep` | `loop()` picks random waypoint and moves | `SMove` | `wander` |
| `PositionStep` | `loop()` positions for ranged attack | `SMove` | `adjust_shoot_position` |
| `PatrolStep` | `loop()` generates guard waypoints and moves | `SMove` | `patrol` |
| `AttackStep` | `loop()` sets `CMelee.attack_direction` / `CRanged.fire_request` | `SMeleeAttack` / `SRangedAttack` | `attack_melee`, `attack_ranged` |
| `TimedActionStep` | Base class: `loop()` counts down duration | — | (abstract base) |
| `EatStep` | `exit()` consumes target, restores hunger | `SStatus` (hunger) | `eat_grass`, `harvest_bush` |
| `GatherStep` | `exit()` calls `consume_yield()`, adds `CCarrying` | `SResourceNode` | `gather_resource` |
| `DepositStep` | `exit()` transfers `CCarrying` → stockpile | `SStockpile` | `deposit_resource` |
| `BuildStep` | `exit()` advances build progress | `SBuildWorker` | `goap_action_build` |
| `FindWorkTargetStep` | `enter()` queries world for work target | — | `find_work_target` |
| `InstantStep` | Base class: `loop()` sets facts immediately | — | (abstract base) |

---

## Consolidation Summary

| Category | Old Count | New Count | Reduction |
|----------|-----------|-----------|-----------|
| Top-level planner actions | 23 | 10 StrategicActions | 57% |
| Plan sequences | ad-hoc per action | 10 BehaviorTemplates | unified |
| Movement logic | 8 move actions | 1 `MoveToTargetStep` (configured by `target_type`) | 87% |
| Combat logic | 4 attack/chase actions | 2 templates + `AttackStep` / `ChaseStep` | 50% |
| Resource gathering | 4 actions | 1 `WorkTemplate` + 3 steps | 25% |
| Feeding | 5 actions | 1 `FeedTemplate` (3 variants) + 2 steps | 60% |

---

## Key Design Changes

1. **Movement unified:** All 8 old `move_to_*` actions collapsed into `MoveToTargetStep` with a `target_type` enum. Distance calculation and arrival logic live in one place.

2. **Combat looped:** `FightMeleeTemplate` and `FightRangedTemplate` set `loops = true`, so the `Chase → Attack` sequence repeats until the threat is dead or the goal changes. Old actions had to be replanned each attack cycle.

3. **Feed variant resolution:** `FeedTemplate` selects grass / food_pile / harvestable at runtime based on nearest distance, instead of having three separate action chains in the planner.

4. **Template interruption:** When `SGoalDecision` selects a new strategic action (e.g., threat detected → `SA_Flee`), the current template's `exit()` is called and the new template's `enter()` begins. This replaces the old `s_ai_action_tick` per-step abort logic.

5. **ECS delegation:** Steps no longer directly modify health, hunger, or stockpile. They set component flags (`CMelee.attack_pending`, `CCarrying.resource_type`) that existing systems consume on their own ticks.
