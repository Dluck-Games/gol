# Building Demolition & Unified Task System Design

> Date: 2026-05-17
> Status: Draft
> Scope: Building demolition mode, unified task queue architecture, and task cancellation

## Overview

The current building system allows players to place ghost buildings (CBuildSite) which worker NPCs then construct. However, once a building is completed (CBuilding), there is no way to remove it. Players can trap themselves behind walls with no escape.

This design adds a **demolition mode** and a **cancel mode**, unifying all player-to-NPC building interactions under a single **Task Queue** architecture. Build, demolish, and cancel are all tasks that players issue and NPCs execute.

## Design Principles

- **Three modes, one interaction pattern** — Build (B), Demolish (N), Cancel (C) all work the same way: enter mode → click target → task is queued → NPC executes
- **NPC executes, player commands** — Player never directly builds or destroys; they issue tasks that workers claim from a global queue
- **FIFO task ordering** — Tasks are processed in submission order, no priority distinctions
- **Cancellation is symmetric** — Canceling a task removes it from the queue; if a worker is already executing, the worker aborts and re-plans
- **Materials are not refunded on cancel** — Once materials are committed (deposited into a ghost), canceling the build task does not return them

## Architecture: Unified Task Queue

### Task Hierarchy

```
Task (abstract base)
├── BuildTask     — target: CBuildSite entity
├── DemolishTask  — target: CBuilding entity
└── (extensible)  — RepairTask, UpgradeTask, etc.
```

Each Task has:
- `target_entity: Entity` — the entity this task operates on
- `task_type: String` — "build", "demolish", etc.
- `is_claimed: bool` — whether a worker has picked this up
- `claimed_by: Entity` — the worker currently executing (null if unclaimed)

### Global Task Queue (CTaskQueue)

A single component attached to the world entity (or managed as a service). All pending and active tasks live here.

```gdscript
class_name CTaskQueue
extends Component

var pending: Array[Task] = []      # submitted but not yet claimed
var active: Array[Task] = []       # claimed by a worker

func submit(task: Task) -> void
    # Add to pending, notify systems

func cancel(task: Task) -> bool
    # Remove from pending or active. If active, notify the worker.

func claim_next_available(worker: Entity) -> Task
    # Find first pending task, mark claimed, move to active, return it
```

### Worker Task Assignment (CWorkerTask)

Replaces the current `CBuildTask` (which is build-specific). Each worker gets one when they claim a task.

```gdscript
class_name CWorkerTask
extends Component

var current_task: Task = null
```

### Task Lifecycle

```
Player enters mode → clicks target → Task created → CTaskQueue.submit(task)
                                                        ↓
                                NPC worker with CWorker sees queue has tasks
                                                        ↓
                                SWorkerTaskManager assigns task → worker.add_component(CWorkerTask)
                                                        ↓
                                Worker executes task (build/demolish FSM)
                                                        ↓
                                Task complete → CTaskQueue.remove(task) → worker.remove_component(CWorkerTask)
```

## Three Modes

### Mode 1: Build Mode (B)

**Existing behavior, refactored to use Task Queue.**

```
Press B → Enter BUILD mode
    ↓
Build hotbar appears (bottom of screen)
    ↓
Select building (number key or click) → cursor shows ghost preview
    ↓
Click valid position → spawn CBuildSite ghost
    → auto-submit BuildTask to CTaskQueue
    → ghost shows "🔨 等待工人" indicator
    ↓
Press B again or ESC → exit BUILD mode
```

**Key change from current system:** Ghost placement no longer relies on NPCs "noticing" ghosts via GOAP perception. Instead, placing a ghost automatically creates a BuildTask in the queue. Workers claim tasks from the queue.

### Mode 2: Demolish Mode (N)

**New mode. Symmetric to build mode.**

```
Press N → Enter DEMOLISH mode
    ↓
No hotbar shown. Cursor changes to red demolition cursor.
    ↓
Hover over completed building → building glows red
    ↓
Click building → submit DemolishTask to CTaskQueue
    → building shows "💣 等待拆除" indicator
    → if building is a wall/door, update pathfinding
    ↓
Press N again or ESC → exit DEMOLISH mode
```

**Execution:** Worker arrives at building → plays demolition animation → building's `demolish_progress` increases → at 100%, building entity is destroyed → 50% of build cost drops as resource pickups.

**Material return:** 50% of original `required_materials` (rounded down). Drops at building position.

### Mode 3: Cancel Mode (C)

**New mode. For canceling pending or active tasks.**

```
Press C → Enter CANCEL mode
    ↓
No hotbar shown. Cursor changes to yellow/orange cancel cursor.
    ↓
Hover over building with an active task → building glows yellow
    ↓
Click building → cancel the task associated with this building
    → if task was pending: removed from queue, indicator disappears
    → if task was active: worker aborts, removes CWorkerTask, re-plans
    → BuildTask cancel: ghost remains, materials lost
    → DemolishTask cancel: building remains untouched
    ↓
Press C again or ESC → exit CANCEL mode
```

## HUD Key Hints (Discovery)

Screen bottom-right shows contextual key hints:

```
[B] 建造   [N] 拆除   [C] 取消
```

- Hints are always visible when player is in the settlement/base area (within range of any building/ghost)
- When entering a mode, the corresponding hint is highlighted
- When no buildings are nearby, hints fade out

## System Design

### New Systems

#### SWorkerTaskManager

Queries: `[CWorker, CGoapAgent, CTransform]` (workers not currently on a task)

- Each frame, check if `CTaskQueue` has pending tasks
- For idle workers, call `CTaskQueue.claim_next_available(worker)`
- On successful claim: add `CWorkerTask` to worker with the claimed task
- The task type determines which FSM system processes this worker

#### SDemolishWorker

Queries: `[CWorker, CWorkerTask, CTransform]` where `CWorkerTask.current_task is DemolishTask`

FSM states:
- `MOVING_TO_TARGET` — navigate to building position
- `DEMOLISHING` — stand at building, increment `demolish_progress`
- `COMPLETING` — building destroyed, spawn material pickups, clean up

#### STaskIndicator

Queries: all entities with pending or active tasks

- Renders floating indicators above buildings/ghosts with tasks
- "🔨 等待工人" / "🔨 建造中 (45%)" / "💣 等待拆除" / "💣 拆除中 (30%)"

### Modified Systems

#### SBuildOperation

- Refactored to use Task Queue: ghost placement auto-submits `BuildTask`
- Remove direct ghost cancellation logic (moved to Cancel mode)
- Add mode switching: BUILD → DEMOLISH → CANCEL are mutually exclusive

#### SBuildWorker (existing)

- Change query from `[CWorker, CBuildTask, ...]` to `[CWorker, CWorkerTask, ...]` where task is BuildTask
- FSM logic remains the same

#### SBuildSiteComplete

- Unchanged. Still monitors CBuildSite progress and replaces ghost with building on completion.

## Data Flow

### Build Flow (refactored)

```
Player presses B → SBuildOperation enters BUILD mode
Player selects wall → ghost preview follows cursor
Player clicks position → SBuildOperation._place_ghost()
    → creates ghost entity with CBuildSite
    → calls CTaskQueue.submit(BuildTask.new(ghost_entity))
    → STaskIndicator shows "🔨 等待工人"

SWorkerTaskManager sees pending BuildTask
    → claims task for idle worker
    → worker.add_component(CWorkerTask with BuildTask)

SBuildWorker processes worker with BuildTask
    → FSM: stockpile → pickup → site → deliver → construct
    → on complete: CTaskQueue removes task, CWorkerTask removed

SBuildSiteComplete detects build_progress >= build_duration
    → destroys ghost, spawns building entity
```

### Demolish Flow (new)

```
Player presses N → SBuildOperation enters DEMOLISH mode
Player clicks completed wall → SBuildOperation._queue_demolish()
    → calls CTaskQueue.submit(DemolishTask.new(wall_entity))
    → STaskIndicator shows "💣 等待工人"

SWorkerTaskManager sees pending DemolishTask
    → claims task for idle worker
    → worker.add_component(CWorkerTask with DemolishTask)

SDemolishWorker processes worker with DemolishTask
    → FSM: moving → demolishing (progress += delta)
    → on complete: destroys building, spawns 50% material pickups
    → CTaskQueue removes task, CWorkerTask removed
```

### Cancel Flow (new)

```
Player presses C → SBuildOperation enters CANCEL mode
Player clicks building with pending BuildTask
    → SBuildOperation._cancel_task()
    → CTaskQueue.cancel(build_task)
    → task removed from pending
    → indicator disappears

Player clicks building with active DemolishTask
    → CTaskQueue.cancel(demolish_task)
    → task removed from active
    → worker's CWorkerTask cleared
    → worker re-plans via GOAP
    → indicator disappears
```

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Player cancels build task after materials deposited | Materials remain in ghost; ghost stays. Player can place a new build task on the same ghost to resume. |
| Worker dies while executing task | Task is orphaned in `active`. A periodic cleanup in CTaskQueue detects dead workers and returns tasks to `pending`. |
| Building destroyed by other means (e.g., enemy attack) while task pending | Task becomes invalid. CTaskQueue validates targets before assignment; invalid tasks are auto-removed. |
| Player queues demolish on building already being built | Not possible — demolish targets CBuilding, build targets CBuildSite. They are different entities. |
| Multiple workers claim same task | Prevented by `is_claimed` flag. Only one worker can claim a task. |
| No workers available | Tasks sit in pending queue with indicator showing "等待工人". No timeout. |
| Player spams many tasks | Queue grows unbounded. Future enhancement: queue size limit per player. |

## Visual Design

### Mode Cursors

| Mode | Cursor | Hover Effect |
|------|--------|-------------|
| BUILD | Normal + ghost preview | Green preview (valid) / Red preview (invalid) |
| DEMOLISH | Red crosshair or hammer icon | Target building pulses red |
| CANCEL | Yellow/orange X icon | Target building pulses yellow |

### Task Indicators (above entity)

| State | Indicator |
|-------|-----------|
| Pending build | 🔨 等待工人 |
| Active build (45%) | 🔨 建造中 45% |
| Pending demolish | 💣 等待拆除 |
| Active demolish (30%) | 💣 拆除中 30% |

## Files to Create/Modify

### New Files

```
scripts/
├── gameplay/
│   └── tasks/
│       ├── task.gd              # Abstract Task base class
│       ├── build_task.gd        # BuildTask extends Task
│       └── demolish_task.gd     # DemolishTask extends Task
├── components/
│   ├── c_task_queue.gd          # Global task queue component
│   └── c_worker_task.gd         # Per-worker current task (replaces CBuildTask)
└── systems/
    ├── s_worker_task_manager.gd # Assigns pending tasks to idle workers
    ├── s_demolish_worker.gd     # FSM for demolition execution
    └── s_task_indicator.gd      # Renders floating task status labels
```

### Modified Files

| File | Change |
|------|--------|
| `scripts/systems/s_build_operation.gd` | Add DEMOLISH and CANCEL modes; refactor ghost placement to auto-submit BuildTask; add task cancellation logic |
| `scripts/systems/s_build_worker.gd` | Change query from CBuildTask to CWorkerTask + BuildTask check |
| `scripts/components/c_build_task.gd` | Rename/refactor to CWorkerTask (or keep and add CWorkerTask as new) |
| `scripts/gameplay/goap/actions/goap_action_build.gd` | Simplify: check CTaskQueue for pending BuildTask instead of perceiving ghosts |
| `scripts/gameplay/tables/building_table.gd` | Add `demolish_duration` and `demolish_return_ratio` fields |

## Scope — Explicitly Excluded

- Task priorities (all FIFO)
- Max workers per task (any number can target same building independently)
- Partial material return on build cancel (materials committed to ghost are lost)
- Repair tasks
- Upgrade tasks
- Building durability / damage from enemies
- Advanced demolition effects (particles, sound)

## Future Extensions

| Feature | How it fits |
|---------|------------|
| Repair | Add RepairTask + SRepairWorker |
| Upgrade | Add UpgradeTask + SUpgradeWorker |
| Task priority | Add `priority: int` to Task base class; sort pending queue |
| Max workers per task | Add `max_workers: int` to Task; claim logic checks current count |
| Building damage | DemolishTask could be auto-submitted when HP reaches 0 |
