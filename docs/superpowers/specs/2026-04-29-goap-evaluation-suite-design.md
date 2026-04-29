# GOAP Evaluation Suite Design

## Purpose

Standalone benchmark framework for the GOAP AI system. Measures planner internals (search time, cache hit rate, iteration count), decision scheduling overhead, plan quality, and search space scope. Runs headless via `gol test goap`, produces concise text reports with optional JSON export. Configurable performance budgets with auto-calibration. Primary baseline for upcoming performance optimization and framework redesign.

## Non-Goals

- Not a correctness test (unit/integration tests cover that)
- Not a live profiler replacement (PerfPanel/GoapDebugger remain for runtime)
- Not a CI gate initially (but designed to support it later)

---

## Architecture

```
gol test goap [scenario] [--json] [--duration=<sec>]
      │
      ▼
┌─────────────────────────────────┐
│ gol CLI (Go)                    │
│ cmd/goap_eval.go                │
│ → build godot args              │
│ → launch headless godot         │
│ → relay exit code               │
└────────────┬────────────────────┘
             │ godot --headless --scene goap_eval_main.tscn
             │       -- --scenario=X [--json] [--duration=S]
             ▼
┌─────────────────────────────────┐
│ GoapEvalMain (GDScript)         │
│ 1. Parse CLI args               │
│ 2. Load scenario config         │
│ 3. Setup world + agents         │
│ 4. Wait for systems ready       │
│ 5. Collection phase             │
│ 6. Generate report              │
│ 7. Optional JSON export         │
│ 8. Budget check → exit code     │
└─────────────────────────────────┘
```

Exit codes: `0` = all budgets met, `1` = budget exceeded, `2` = runtime error.

---

## CLI Interface

```bash
# Run all scenarios
gol test goap

# Run specific scenario
gol test goap combat
gol test goap realworld --duration=300

# With JSON export
gol test goap mixed --json
```

### Arguments

| Arg | Default | Description |
|-----|---------|-------------|
| `[scenario]` | all | Scenario name or `all` |
| `--json` | off | Export JSON to `logs/tests/<timestamp>-goap-<scenario>.json` |
| `--duration=<sec>` | per-scenario | Override collection duration in seconds |

Available scenarios: `combat`, `worker`, `ecosystem`, `mixed`, `stress`, `realworld`.

---

## Instrumentation Layer

Added to `GoapPlanner` and `SAI` via static profiling flag. Zero-overhead when disabled — every hook starts with `if not _profiling_enabled: return`.

### GoapPlanner Hooks

```gdscript
# Static profiling state
static var _profiling_enabled: bool = false
static var _profile_data: Array[Dictionary] = []  # per-plan records
static var _profile_cache_misses: Array[Dictionary] = []  # miss reason log

# Per build_plan_for_goal() call, record:
{
  "goal_name": String,
  "goal_priority": int,
  "search_time_us": int,       # Time.get_ticks_usec() delta
  "iterations": int,            # loop counter from _plan_for_goal
  "plan_length": int,           # steps.size() or 0
  "result": String,             # "found" | "max_iterations" | "no_path"
  "cache_hit": bool,
  "state_var_count": int,       # world_state.size()
  "action_count": int,          # available actions count
  "goal_count": int,            # goals evaluated
}

# Per cache miss, record:
{
  "reason": String,  # "cold" | "ttl_expired" | "precond_recheck_fail"
  "goal_name": String,
}
```

### SAI Hooks

```gdscript
# Per-frame decision metrics (appended to collector each frame):
{
  "frame": int,
  "decisions_count": int,
  "decision_time_ms": float,
  "deferred_count": int,
  "replan_count": int,
  "replan_reasons": Dictionary,  # reason → count
}
```

### Enable/Disable API

```gdscript
static func enable_profiling() -> void
static func disable_profiling() -> void
static func get_profile_data() -> Array[Dictionary]
static func get_cache_miss_data() -> Array[Dictionary]
static func clear_profile_data() -> void
```

---

## Metrics (5 Categories)

### 1. Search Efficiency

| Metric | Unit | Description |
|--------|------|-------------|
| `avg_search_time_us` | µs | Mean A* search time per plan |
| `p99_search_time_us` | µs | 99th percentile search time |
| `max_search_time_us` | µs | Worst case search time |
| `avg_iterations` | count | Mean node expansions per search |
| `max_iterations` | count | Worst case expansions (cap: 256) |
| `plan_found_rate` | % | Searches that produced a valid plan |

### 2. Cache Performance

| Metric | Unit | Description |
|--------|------|-------------|
| `cache_hit_rate` | % | Plan cache hit rate |
| `miss_cold` | count | Misses — key never seen |
| `miss_ttl` | count | Misses — TTL expired |
| `miss_precond` | count | Misses — precondition recheck failed |
| `eviction_count` | count | Cache full-clear events |
| `cache_entries_peak` | count | Max simultaneous cache entries |

### 3. Decision Scheduling

| Metric | Unit | Description |
|--------|------|-------------|
| `avg_decisions_per_frame` | count | Mean decisions executed per frame |
| `avg_decision_time_ms` | ms | Mean per-frame decision time |
| `p99_decision_time_ms` | ms | 99th percentile decision time |
| `deferred_rate` | % | Decisions deferred by frame budget |
| `total_replans` | count | Total replan events |
| `replan_reason_dist` | dict | Distribution of replan reasons |

### 4. Plan Quality

| Metric | Unit | Description |
|--------|------|-------------|
| `plan_completion_rate` | % | Plans executed to completion |
| `thrash_rate` | % | Agents thrashing (≥3 replans in 5s) |
| `goal_switch_rate` | /s | Goal changes per second |
| `avg_plan_lifetime` | frames | Mean plan survival duration |

### 5. Search Space Scope

| Metric | Unit | Description |
|--------|------|-------------|
| `state_var_count` | count | World state variables used in planning |
| `available_action_count` | count | Concrete actions available to planner |
| `goal_count` | count | Goals evaluated per agent |
| `planning_key_count` | count | Total planning keys in cache |

---

## Evaluation Scenarios

### Synthetic Scenarios

| Scenario | Agents | Duration | Purpose |
|----------|--------|----------|---------|
| `combat` | 8 combat NPC + 4 enemies | 10s (600f) | High-frequency replan, goal switching, A* pressure |
| `worker` | 6 workers + resource nodes + stockpile | 10s (600f) | Long action chains (5-step gather loop), cache efficiency |
| `ecosystem` | 12 rabbits + grassland | 10s (600f) | Simple AI at scale, LOD effectiveness |
| `mixed` | All above combined (~30 agents) | 15s (900f) | Real-world mix, cache contention, scheduler fairness |
| `stress` | 100 agents (mixed types) | 10s (600f) | Extreme load, frame budget ceiling, deferred decision rate |

### Real-World Scenario

| Scenario | Description | Duration |
|----------|-------------|----------|
| `realworld` | Full game boot → PCG map generation → natural agent spawning → collect metrics over real gameplay. No artificial setup — uses identical boot path as `gol run game`. | Configurable: default 60s, supports `--duration=60/300/600` for 1min/5min/10min snapshots |

The `realworld` scenario:
1. Calls `GOL.setup()` with production config
2. Runs `ServiceContext.pcg().generate()` for real map
3. Waits for all systems to initialize (internal — caller does not configure this)
4. Collects metrics for the specified duration
5. Reports include a time-series breakdown (per-minute stats if duration > 60s)

---

## Budget System

Budgets are hardcoded in the scenario class hierarchy. Base class defines global defaults, subclasses override per-scenario.

### Location

```gdscript
# eval_scenario_base.gd
const DEFAULT_BUDGETS := {
  "avg_search_time_us": 100,
  "p99_search_time_us": 500,
  "cache_hit_rate_min": 0.75,
  "thrash_rate_max": 0.05,
  "avg_decision_time_ms": 1.0,
  "p99_decision_time_ms": 3.0,
  "plan_found_rate_min": 0.85,
  "plan_completion_rate_min": 0.70,
  "avg_iterations_max": 80,
}

func get_budgets() -> Dictionary:
  return DEFAULT_BUDGETS

# eval_scenario_stress.gd
func get_budgets() -> Dictionary:
  var b := DEFAULT_BUDGETS.duplicate()
  b["avg_decision_time_ms"] = 2.0
  b["p99_decision_time_ms"] = 5.0
  return b
```

### Rationale

- Budget lives next to the scenario config — change one, see the other
- Budget changes show up in git diff for easy before/after comparison
- Zero configuration — no external files, no auto-calibration magic
- Same pattern as `SceneConfig` subclass overrides elsewhere in the codebase

---

## Report Format

Concise plain text, minimal characters. Output to stdout by default.

```
GOAP Eval: mixed | 30 agents | 900f (15.0s) | warmup 60f

SEARCH
  avg 42us  p99 189us  max 312us  iter avg 23.4 max 156/256  found 94.1%

CACHE
  hit 83.2%  miss: cold 112 ttl 41 precond 16  evict 3  peak 48 entries

SCHEDULING
  dec/f 2.1  avg 0.71ms  p99 1.82ms  deferred 2.7%  replans 156
  reasons: invalidated 42.9% priority 28.8% precond 28.2%

QUALITY
  complete 78.3%  thrash 3.2%  goal-switch 0.8/s  plan-life 42f

SCOPE
  state-vars 18  actions 23  goals 4  planning-keys 32

BUDGET 12/12 PASS
```

When a budget fails:
```
BUDGET 11/12 FAIL
  FAIL p99_decision_time_ms: 3.21 > 3.0
```

### JSON Export

With `--json`, write to `logs/tests/<timestamp>-goap-<scenario>.json`:

```json
{
  "timestamp": "2026-04-29T14:30:00",
  "scenario": "mixed",
  "agent_count": 30,
  "frames": 900,
  "duration_s": 15.0,
  "metrics": {
    "search": { "avg_time_us": 42, "p99_time_us": 189, ... },
    "cache": { "hit_rate": 0.832, ... },
    "scheduling": { "avg_decision_time_ms": 0.71, ... },
    "quality": { "completion_rate": 0.783, ... },
    "scope": { "state_var_count": 18, ... }
  },
  "budget_result": { "pass": true, "total": 12, "passed": 12, "failures": [] }
}
```

---

## File Structure

```
gol-tools/cli/cmd/
  goap_eval.go                    # CLI entry (Go, ~60 lines)

gol-project/
  scenes/tests/
    goap_eval_main.tscn           # Eval entry scene
  scripts/tests/goap_eval/
    goap_eval_main.gd             # Main controller
    goap_eval_report.gd           # Text + JSON report generation
    goap_metrics_collector.gd     # Metrics aggregator (consumes planner/SAI hooks)
    scenarios/
      eval_scenario_base.gd       # Scenario base class
      eval_scenario_combat.gd
      eval_scenario_worker.gd
      eval_scenario_ecosystem.gd
      eval_scenario_mixed.gd
      eval_scenario_stress.gd
      eval_scenario_realworld.gd

  scripts/gameplay/goap/
    goap_planner.gd               # Add instrumentation hooks (~30 lines)
  scripts/systems/
    s_ai.gd                       # Add decision metrics hooks (~15 lines)
```

---

## Implementation Notes

### Instrumentation Safety

- All hooks gated by `static var _profiling_enabled: bool = false`
- First statement in every hook: `if not _profiling_enabled: return`
- Profile data stored as `Array[Dictionary]` — simple, no custom classes
- `clear_profile_data()` called between scenarios to avoid cross-contamination

### Headless Mode

- Godot `--headless` disables rendering, audio, and input
- Physics still runs (needed for movement actions)
- `_process()` and `_physics_process()` fire normally
- No ImGui/UI code paths execute

### Scenario Isolation

- Each scenario calls `GoapPlanner.reset_caches()` + `reset_cache_stats()` + `clear_profile_data()` before starting
- Each scenario internally waits for systems to be ready before enabling profiling and collecting data
- ECS World is rebuilt per scenario (via `GOL.setup()` or direct `World.new()`)
- No state leaks between scenarios

### Real-World Scenario Specifics

- Uses `GOL.setup()` → full production boot path
- PCG generation creates real map with natural spawn points
- Agent count depends on map/spawn config (not fixed)
- Internally waits for system initialization before collecting
- Supports time-series output: metrics reported per-minute when duration > 60s
- `--duration` parameter controls collection window (default 60s)
