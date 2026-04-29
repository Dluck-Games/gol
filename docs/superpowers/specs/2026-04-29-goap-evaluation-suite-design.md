# GOAP Evaluation Suite Design

## Purpose

Standalone benchmark for the GOAP AI system. Runs the real game headless, collects planner/scheduling/quality metrics, reports to stdout with optional JSON. Hardcoded performance budgets with pass/fail exit code. Baseline for upcoming performance optimization.

## Non-Goals

- Not a correctness test (unit/integration tests cover that)
- Not a live profiler replacement (PerfPanel/GoapDebugger remain for runtime)

---

## Architecture

```
gol test goap [--json] [--duration=<sec>]
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
             │       -- [--json] [--duration=S]
             ▼
┌─────────────────────────────────┐
│ GoapEvalMain (GDScript)         │
│ 1. Parse CLI args               │
│ 2. GOL.setup() + PCG generate   │
│ 3. Wait for systems ready       │
│ 4. Enable profiling             │
│ 5. Collect for --duration sec   │
│ 6. Report to stdout             │
│ 7. Optional JSON to logs/tests/ │
│ 8. Budget check → exit code     │
└─────────────────────────────────┘
```

Exit codes: `0` = all budgets met, `1` = budget exceeded, `2` = runtime error.

---

## CLI

```bash
gol test goap                    # 60s collection
gol test goap --duration=300     # 5min
gol test goap --json             # + JSON export
```

| Arg | Default | Description |
|-----|---------|-------------|
| `--json` | off | Export to `logs/tests/<timestamp>-goap.json` |
| `--duration=<sec>` | 60 | Collection duration |

---

## Instrumentation

Added to `GoapPlanner` and `SAI` via static flag. Zero-overhead when off.

### GoapPlanner Hooks

```gdscript
static var _profiling_enabled: bool = false
static var _profile_data: Array[Dictionary] = []
static var _profile_cache_misses: Array[Dictionary] = []

# Per build_plan_for_goal() call:
{
  "goal_name": String,
  "goal_priority": int,
  "time_us": int,           # Time.get_ticks_usec() delta
  "iterations": int,         # from _plan_for_goal loop counter
  "plan_length": int,
  "result": String,          # "found" | "max_iterations" | "no_path"
  "cache_hit": bool,
  "state_var_count": int,
  "action_count": int,
  "goal_count": int,
}

# Per cache miss:
{
  "reason": String,  # "cold" | "ttl_expired" | "precond_recheck_fail"
  "goal_name": String,
}
```

### SAI Hooks

```gdscript
# Per-frame:
{
  "frame": int,
  "decisions_count": int,
  "decision_time_ms": float,
  "deferred_count": int,
  "replan_count": int,
  "replan_reasons": Dictionary,
}
```

### API

```gdscript
static func enable_profiling() -> void
static func disable_profiling() -> void
static func get_profile_data() -> Array[Dictionary]
static func get_cache_miss_data() -> Array[Dictionary]
static func clear_profile_data() -> void
```

---

## Metrics

### 1. Planning Time

| Metric | Description |
|--------|-------------|
| `avg_plan_time_us` | Mean per call (all) |
| `max_plan_time_us` | Worst case (all) |
| `avg_search_time_us` | Mean per cache-miss (A* only) |
| `max_search_time_us` | Worst case A* |
| `avg_cache_hit_time_us` | Mean per cache-hit |
| `max_cache_hit_time_us` | Worst case cache-hit |

### 2. Search Efficiency (cache-miss only)

| Metric | Description |
|--------|-------------|
| `avg_iterations` | Mean node expansions |
| `max_iterations` | Worst case (cap: 256) |
| `plan_found_rate` | % searches producing valid plan |

### 3. Cache

| Metric | Description |
|--------|-------------|
| `cache_hit_rate` | Hit rate % |
| `miss_cold` / `miss_ttl` / `miss_precond` | Miss reason counts |
| `eviction_count` | Full-clear events |
| `cache_entries_peak` | Max simultaneous entries |

### 4. Decision Scheduling

| Metric | Description |
|--------|-------------|
| `avg_decisions_per_frame` | Mean decisions/frame |
| `avg_decision_time_ms` | Mean per-frame decision time |
| `p99_decision_time_ms` | 99th percentile |
| `deferred_rate` | % deferred by frame budget |
| `total_replans` | Replan count |
| `replan_reason_dist` | Reason distribution |

### 5. Plan Quality

| Metric | Description |
|--------|-------------|
| `plan_completion_rate` | % plans executed to completion |
| `thrash_rate` | % agents thrashing (≥3 replans in 5s) |
| `goal_switch_rate` | Goal changes per second |
| `avg_plan_lifetime` | Mean plan survival (frames) |

### 6. Search Space

| Metric | Description |
|--------|-------------|
| `state_var_count` | World state variables |
| `available_action_count` | Concrete actions |
| `goal_count` | Goals per agent |
| `planning_key_count` | Planning keys |

---

## Budgets

Hardcoded in `goap_eval_main.gd`:

```gdscript
const BUDGETS := {
  "avg_search_time_us": 100,
  "cache_hit_rate_min": 0.75,
  "thrash_rate_max": 0.05,
  "avg_decision_time_ms": 1.0,
  "p99_decision_time_ms": 3.0,
  "plan_found_rate_min": 0.85,
  "plan_completion_rate_min": 0.70,
  "avg_iterations_max": 80,
}
```

---

## Report

```
GOAP Eval | 41 agents | 3600f (60.0s)

PLANNING TIME
  all: avg 12us  max 312us  |  miss: avg 42us  max 312us  |  hit: avg 3us  max 8us

SEARCH (cache-miss only)
  iter avg 23.4  max 156/256  found 94.1%

CACHE
  hit 83.2%  miss: cold 112 ttl 41 precond 16  evict 3  peak 48

SCHEDULING
  dec/f 2.1  avg 0.71ms  p99 1.82ms  deferred 2.7%  replans 156
  reasons: invalidated 42.9% priority 28.8% precond 28.2%

QUALITY
  complete 78.3%  thrash 3.2%  goal-switch 0.8/s  plan-life 42f

SCOPE
  state-vars 18  actions 23  goals 4  planning-keys 32

BUDGET 14/14 PASS
```

Budget fail:
```
BUDGET 13/14 FAIL
  FAIL p99_decision_time_ms: 3.21 > 3.0
```

JSON (`--json`) → `logs/tests/<timestamp>-goap.json` with same data structured as nested dict.

---

## Files

```
gol-tools/cli/cmd/
  goap_eval.go                  # CLI entry (Go)

gol-project/
  scenes/tests/
    goap_eval_main.tscn         # Entry scene
  scripts/tests/goap_eval/
    goap_eval_main.gd           # Controller + budgets
    goap_eval_report.gd         # Text + JSON output
    goap_metrics_collector.gd   # Aggregates planner/SAI hook data

  scripts/gameplay/goap/
    goap_planner.gd             # Add profiling hooks (~30 lines)
  scripts/systems/
    s_ai.gd                     # Add decision hooks (~15 lines)
```

---

## Notes

- Profiling gated by `_profiling_enabled` static flag, zero-overhead when off
- Godot `--headless` disables rendering; physics and `_process` still fire
- Full production boot path: `GOL.setup()` → PCG → natural spawns
- Per-minute time-series in report when duration > 60s
