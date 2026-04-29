# GOAP Evaluation Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `gol test goap` command that boots the real game headless, collects GOAP planner/scheduling/quality metrics for a configurable duration, prints a concise text report, and exits 0/1 based on hardcoded performance budgets.

**Architecture:** Two-layer entry: Go CLI (`goap_eval.go`) launches Godot headless with `goap_eval_main.tscn`. GDScript side boots the real game via `GOL.start_game()`, waits for systems, enables lightweight instrumentation hooks in `GoapPlanner` and `SAI`, collects data, then reports. Instrumentation is gated by a static `_profiling_enabled` flag — zero overhead when off.

**Tech Stack:** Go (Cobra CLI), GDScript (Godot 4), headless Godot

**Spec:** `docs/superpowers/specs/2026-04-29-goap-evaluation-suite-design.md`

---

### Task 1: GoapPlanner Instrumentation Hooks

Add profiling data collection to `GoapPlanner`. Gated by static flag, zero-overhead when off.

**Files:**
- Modify: `gol-project/scripts/gameplay/goap/goap_planner.gd`

- [ ] **Step 1: Add static profiling state after cache stats (line 72)**

After line 72 (`static var _cache_misses: int = 0`), add:

```gdscript
## ---------------------------------------------------------------------------
## PROFILING (eval suite)
## ---------------------------------------------------------------------------
## Gated by _profiling_enabled. When false, every hook early-returns — zero
## overhead on the production hot path. When true, each build_plan_for_goal()
## call appends a record to _profile_data with timing, iteration count, cache
## hit status, and search-space dimensions.
static var _profiling_enabled: bool = false
static var _profile_data: Array[Dictionary] = []
static var _profile_cache_misses: Array[Dictionary] = []
static var _profile_eviction_count: int = 0
static var _profile_cache_peak: int = 0


static func enable_profiling() -> void:
	_profiling_enabled = true
	clear_profile_data()


static func disable_profiling() -> void:
	_profiling_enabled = false


static func get_profile_data() -> Array[Dictionary]:
	return _profile_data


static func get_cache_miss_data() -> Array[Dictionary]:
	return _profile_cache_misses


static func get_profiling_extras() -> Dictionary:
	return {
		"eviction_count": _profile_eviction_count,
		"cache_peak": _profile_cache_peak,
	}


static func clear_profile_data() -> void:
	_profile_data.clear()
	_profile_cache_misses.clear()
	_profile_eviction_count = 0
	_profile_cache_peak = 0
```

- [ ] **Step 2: Instrument `build_plan_for_goal()` (lines 138–173)**

Replace the method body with timing + record collection. The planning logic is unchanged — we wrap it with `Time.get_ticks_usec()` and append a record at the end:

```gdscript
func build_plan_for_goal(world_state: Dictionary[String, bool], goal: GoapGoal, actions: Array[GoapAction] = []) -> GoapPlan:
	if goal == null or goal.is_satisfied(world_state):
		return null

	var use_cache: bool = actions.is_empty()
	var available_actions: Array[GoapAction] = actions if not actions.is_empty() else get_all_actions()
	var start_us: int = Time.get_ticks_usec() if _profiling_enabled else 0

	var cache_key: String = ""
	if use_cache:
		var ordered_keys: Array[String] = _get_planning_keys(world_state, goal, available_actions)
		cache_key = _build_cache_key(world_state, goal, ordered_keys)

		var cached_plan: GoapPlan = _try_cache_hit(cache_key, world_state)
		if cached_plan != null:
			_cache_hits += 1
			if _profiling_enabled:
				_profile_data.append({
					"goal_name": goal.goal_name,
					"goal_priority": goal.priority,
					"time_us": Time.get_ticks_usec() - start_us,
					"iterations": 0,
					"plan_length": cached_plan.steps.size(),
					"result": "found",
					"cache_hit": true,
					"state_var_count": world_state.size(),
					"action_count": available_actions.size(),
					"goal_count": 1,
				})
			return cached_plan
		_cache_misses += 1

	var plan_steps: Array[GoapPlanStep] = _plan_for_goal(world_state, goal, available_actions)

	if _profiling_enabled:
		var elapsed_us: int = Time.get_ticks_usec() - start_us
		var iterations_used: int = MAX_ITERATIONS - _last_iterations_remaining
		_profile_data.append({
			"goal_name": goal.goal_name,
			"goal_priority": goal.priority,
			"time_us": elapsed_us,
			"iterations": iterations_used,
			"plan_length": plan_steps.size(),
			"result": "found" if not plan_steps.is_empty() else ("max_iterations" if iterations_used >= MAX_ITERATIONS else "no_path"),
			"cache_hit": false,
			"state_var_count": world_state.size(),
			"action_count": available_actions.size(),
			"goal_count": 1,
		})

	if plan_steps.is_empty():
		return null

	var plan := GoapPlan.new()
	plan.goal = goal
	plan.steps = plan_steps
	plan.reset()

	if use_cache:
		_store_in_cache(cache_key, goal, plan_steps)

	return plan
```

- [ ] **Step 3: Add `_last_iterations_remaining` tracking to `_plan_for_goal()` (line 292)**

Add a static var before `_plan_for_goal` and set it inside the method:

```gdscript
## Stashed by _plan_for_goal for profiling — how many iterations remained when
## the search terminated. Avoids changing _plan_for_goal's return signature.
static var _last_iterations_remaining: int = 0
```

At the **top** of `_plan_for_goal()` (line 293), after `var open_list: Array = []`:

```gdscript
	_last_iterations_remaining = MAX_ITERATIONS
```

At the **end** of the while loop body, before the `return []` at line 361, add:

```gdscript
	_last_iterations_remaining = max_iterations
```

And at the early return `return current_path` (line 328), add before it:

```gdscript
		_last_iterations_remaining = max_iterations
```

- [ ] **Step 4: Instrument cache miss reasons in `_try_cache_hit()` (lines 199–233)**

Add miss-reason recording. After each `return null` in `_try_cache_hit`, record the reason if profiling:

After line 201 (`return null` — key not in cache), insert before the return:
```gdscript
		if _profiling_enabled:
			_profile_cache_misses.append({"reason": "cold", "goal_name": ""})
```

After line 211 (`return null` — TTL expired), insert before the return:
```gdscript
		if _profiling_enabled:
			_profile_cache_misses.append({"reason": "ttl_expired", "goal_name": cache_key.get_slice("|", 0).get_slice(":", 0)})
```

After line 224 (`return null` — precondition recheck failed), insert before the return:
```gdscript
		if _profiling_enabled:
			_profile_cache_misses.append({"reason": "precond_recheck_fail", "goal_name": cache_key.get_slice("|", 0).get_slice(":", 0)})
```

- [ ] **Step 5: Instrument cache evictions and peak in `_store_in_cache()` (lines 239–246)**

In `_store_in_cache`, after `_plan_cache.clear()` (line 241):
```gdscript
		if _profiling_enabled:
			_profile_eviction_count += 1
```

After storing the entry (after line 246), add:
```gdscript
	if _profiling_enabled:
		if _plan_cache.size() > _profile_cache_peak:
			_profile_cache_peak = _plan_cache.size()
```

- [ ] **Step 6: Clear profiling state in `reset_caches()` (line 123)**

After line 130 (`_cache_misses = 0`), add:
```gdscript
	clear_profile_data()
```

- [ ] **Step 7: Commit**

```bash
git add gol-project/scripts/gameplay/goap/goap_planner.gd
git commit -m "feat(goap): add profiling instrumentation to GoapPlanner

Static _profiling_enabled flag gates all hooks. When off, only cost
is a single bool check in build_plan_for_goal(). When on, records
per-plan timing, iterations, cache hit/miss reasons, eviction count,
and search space dimensions."
```

---

### Task 2: SAI Decision Scheduling Hooks

Add per-frame decision metrics to `SAI` for the eval collector.

**Files:**
- Modify: `gol-project/scripts/systems/s_ai.gd`

- [ ] **Step 1: Add profiling state and API after instance vars (line 81)**

After line 81 (`var _frame_counter: int = 0`), add:

```gdscript

## ---------------------------------------------------------------------------
## PROFILING (eval suite)
## ---------------------------------------------------------------------------
static var _profiling_enabled: bool = false
static var _profile_frame_data: Array[Dictionary] = []
## Accumulated within a single process() call, flushed at end of frame.
var _profile_replan_count: int = 0
var _profile_replan_reasons: Dictionary = {}
var _profile_deferred_count: int = 0


static func enable_profiling() -> void:
	_profiling_enabled = true
	_profile_frame_data.clear()


static func disable_profiling() -> void:
	_profiling_enabled = false


static func get_profile_frame_data() -> Array[Dictionary]:
	return _profile_frame_data


static func clear_profile_data() -> void:
	_profile_frame_data.clear()
```

- [ ] **Step 2: Record replan events in `_process_decision_tick()` (line 196)**

After line 196 (`if replan_reason != ""`), inside the if block, add at the top:
```gdscript
		if _profiling_enabled:
			_profile_replan_count += 1
			_profile_replan_reasons[replan_reason] = _profile_replan_reasons.get(replan_reason, 0) + 1
```

- [ ] **Step 3: Record deferred decisions in `process()` (line 160)**

Inside the budget-exceeded branch at line 160 (`if _decisions_this_frame >= MAX_DECISIONS_PER_FRAME or ...`), add at the top of that if block:
```gdscript
			if _profiling_enabled:
				_profile_deferred_count += 1
```

- [ ] **Step 4: Flush per-frame record at end of `process()` (after line 172)**

After the main for-loop ends (after line 172), add:

```gdscript
	if _profiling_enabled:
		_profile_frame_data.append({
			"frame": Engine.get_process_frames(),
			"decisions_count": _decisions_this_frame,
			"decision_time_ms": _decision_ms_this_frame,
			"deferred_count": _profile_deferred_count,
			"replan_count": _profile_replan_count,
			"replan_reasons": _profile_replan_reasons.duplicate(),
		})
		_profile_replan_count = 0
		_profile_replan_reasons.clear()
		_profile_deferred_count = 0
```

- [ ] **Step 5: Commit**

```bash
git add gol-project/scripts/systems/s_ai.gd
git commit -m "feat(ai): add profiling instrumentation to SAI

Per-frame records: decision count, wall time, deferred count,
replan count with reason distribution. Same static flag pattern
as GoapPlanner — zero overhead when off."
```

---

### Task 3: Metrics Collector

Aggregates raw profiling data from `GoapPlanner` and `SAI` into the 6 metric categories from the spec.

**Files:**
- Create: `gol-project/scripts/tests/goap_eval/goap_metrics_collector.gd`

- [ ] **Step 1: Create the metrics collector**

```gdscript
class_name GoapMetricsCollector
extends RefCounted

## Consumes raw profiling data from GoapPlanner and SAI, produces
## aggregated metrics for reporting.


static func collect() -> Dictionary:
	var plan_data: Array[Dictionary] = GoapPlanner.get_profile_data()
	var cache_miss_data: Array[Dictionary] = GoapPlanner.get_cache_miss_data()
	var planner_extras: Dictionary = GoapPlanner.get_profiling_extras()
	var frame_data: Array[Dictionary] = SAI.get_profile_frame_data()
	var cache_stats: Dictionary = GoapPlanner.get_cache_stats()

	return {
		"planning_time": _collect_planning_time(plan_data),
		"search": _collect_search(plan_data),
		"cache": _collect_cache(cache_stats, cache_miss_data, planner_extras),
		"scheduling": _collect_scheduling(frame_data),
		"quality": _collect_quality(frame_data),
		"scope": _collect_scope(plan_data),
	}


static func _collect_planning_time(plan_data: Array[Dictionary]) -> Dictionary:
	var all_times: Array[int] = []
	var miss_times: Array[int] = []
	var hit_times: Array[int] = []

	for record in plan_data:
		var t: int = record.get("time_us", 0)
		all_times.append(t)
		if record.get("cache_hit", false):
			hit_times.append(t)
		else:
			miss_times.append(t)

	return {
		"avg_plan_time_us": _avg_i(all_times),
		"max_plan_time_us": _max_i(all_times),
		"avg_search_time_us": _avg_i(miss_times),
		"max_search_time_us": _max_i(miss_times),
		"avg_cache_hit_time_us": _avg_i(hit_times),
		"max_cache_hit_time_us": _max_i(hit_times),
		"total_plans": all_times.size(),
		"total_misses": miss_times.size(),
		"total_hits": hit_times.size(),
	}


static func _collect_search(plan_data: Array[Dictionary]) -> Dictionary:
	var iterations: Array[int] = []
	var found_count: int = 0
	var miss_count: int = 0

	for record in plan_data:
		if record.get("cache_hit", false):
			continue
		miss_count += 1
		iterations.append(record.get("iterations", 0))
		if record.get("result", "") == "found":
			found_count += 1

	return {
		"avg_iterations": _avg_i(iterations),
		"max_iterations": _max_i(iterations),
		"plan_found_rate": float(found_count) / float(miss_count) if miss_count > 0 else 0.0,
		"miss_count": miss_count,
	}


static func _collect_cache(cache_stats: Dictionary, miss_data: Array[Dictionary], extras: Dictionary) -> Dictionary:
	var cold: int = 0
	var ttl: int = 0
	var precond: int = 0
	for record in miss_data:
		match record.get("reason", ""):
			"cold": cold += 1
			"ttl_expired": ttl += 1
			"precond_recheck_fail": precond += 1

	return {
		"hit_rate": cache_stats.get("hit_rate", 0.0),
		"hits": cache_stats.get("hits", 0),
		"misses": cache_stats.get("misses", 0),
		"miss_cold": cold,
		"miss_ttl": ttl,
		"miss_precond": precond,
		"eviction_count": extras.get("eviction_count", 0),
		"cache_entries_peak": extras.get("cache_peak", 0),
	}


static func _collect_scheduling(frame_data: Array[Dictionary]) -> Dictionary:
	var decision_counts: Array[int] = []
	var decision_times: Array[float] = []
	var total_deferred: int = 0
	var total_replans: int = 0
	var replan_reasons: Dictionary = {}
	var total_decisions: int = 0

	for record in frame_data:
		var dc: int = record.get("decisions_count", 0)
		decision_counts.append(dc)
		total_decisions += dc
		decision_times.append(record.get("decision_time_ms", 0.0))
		total_deferred += record.get("deferred_count", 0)
		total_replans += record.get("replan_count", 0)
		var reasons: Dictionary = record.get("replan_reasons", {})
		for reason: String in reasons:
			replan_reasons[reason] = replan_reasons.get(reason, 0) + int(reasons[reason])

	decision_times.sort()
	var p99_idx: int = int(ceil(decision_times.size() * 0.99)) - 1
	var p99_time: float = decision_times[clampi(p99_idx, 0, decision_times.size() - 1)] if not decision_times.is_empty() else 0.0

	return {
		"avg_decisions_per_frame": _avg_i(decision_counts),
		"avg_decision_time_ms": _avg_f(decision_times),
		"p99_decision_time_ms": p99_time,
		"deferred_rate": float(total_deferred) / float(total_deferred + total_decisions) if (total_deferred + total_decisions) > 0 else 0.0,
		"total_replans": total_replans,
		"replan_reason_dist": replan_reasons,
		"total_frames": frame_data.size(),
	}


static func _collect_quality(frame_data: Array[Dictionary]) -> Dictionary:
	## Plan quality requires tracking across frames — we derive what we can from
	## the per-frame replan data. Full plan-lifecycle tracking (completion rate,
	## thrash detection) would need agent-level instrumentation; for now we
	## approximate from replan frequency.
	var total_replans: int = 0
	var total_frames: int = frame_data.size()
	var duration_s: float = total_frames / 60.0 if total_frames > 0 else 1.0

	var replan_timestamps: Array[int] = []  ## frames where replans occurred
	for record in frame_data:
		var rc: int = record.get("replan_count", 0)
		total_replans += rc
		if rc > 0:
			replan_timestamps.append(record.get("frame", 0))

	## Thrash detection: count frames where ≥3 replans occurred in any 5s window.
	## Simplified: count replan-frames within sliding 300-frame window.
	var thrash_frames: int = 0
	for i in range(replan_timestamps.size()):
		var window_count: int = 0
		for j in range(i, replan_timestamps.size()):
			if replan_timestamps[j] - replan_timestamps[i] > 300:  ## 5s at 60fps
				break
			window_count += 1
		if window_count >= 3:
			thrash_frames += 1

	## Goal switch rate approximated from replan count with reason "Higher priority goal activated"
	var goal_switches: int = 0
	for record in frame_data:
		var reasons: Dictionary = record.get("replan_reasons", {})
		goal_switches += int(reasons.get("Higher priority goal activated", 0))

	return {
		"plan_completion_rate": 0.0,  ## Requires agent-level lifecycle tracking — deferred
		"thrash_rate": float(thrash_frames) / float(total_frames) if total_frames > 0 else 0.0,
		"goal_switch_rate": float(goal_switches) / duration_s,
		"avg_plan_lifetime": 0,  ## Requires agent-level lifecycle tracking — deferred
	}


static func _collect_scope(plan_data: Array[Dictionary]) -> Dictionary:
	var max_state_vars: int = 0
	var max_actions: int = 0
	var max_goals: int = 0
	for record in plan_data:
		max_state_vars = maxi(max_state_vars, record.get("state_var_count", 0))
		max_actions = maxi(max_actions, record.get("action_count", 0))
		max_goals = maxi(max_goals, record.get("goal_count", 0))

	return {
		"state_var_count": max_state_vars,
		"available_action_count": max_actions,
		"goal_count": max_goals,
		"planning_key_count": GoapPlanner._cached_planning_keys.size(),
	}


## --- Helpers ---

static func _avg_i(arr: Array[int]) -> float:
	if arr.is_empty():
		return 0.0
	var sum: int = 0
	for v in arr:
		sum += v
	return float(sum) / float(arr.size())


static func _max_i(arr: Array[int]) -> int:
	if arr.is_empty():
		return 0
	var m: int = arr[0]
	for v in arr:
		if v > m:
			m = v
	return m


static func _avg_f(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var sum: float = 0.0
	for v in arr:
		sum += v
	return sum / float(arr.size())
```

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/tests/goap_eval/goap_metrics_collector.gd
git commit -m "feat(goap-eval): add GoapMetricsCollector

Aggregates raw GoapPlanner and SAI profiling data into 6 metric
categories: planning time, search efficiency, cache, scheduling,
quality, and scope."
```

---

### Task 4: Report Generator

Formats metrics as concise text for stdout + optional JSON.

**Files:**
- Create: `gol-project/scripts/tests/goap_eval/goap_eval_report.gd`

- [ ] **Step 1: Create the report generator**

```gdscript
class_name GoapEvalReport
extends RefCounted

## Formats GOAP eval metrics as concise text or JSON.


static func print_text(metrics: Dictionary, agent_count: int, frame_count: int, duration_s: float) -> void:
	var pt: Dictionary = metrics.get("planning_time", {})
	var se: Dictionary = metrics.get("search", {})
	var ca: Dictionary = metrics.get("cache", {})
	var sc: Dictionary = metrics.get("scheduling", {})
	var qu: Dictionary = metrics.get("quality", {})
	var sp: Dictionary = metrics.get("scope", {})

	print("GOAP Eval | %d agents | %df (%.1fs)" % [agent_count, frame_count, duration_s])
	print("")
	print("PLANNING TIME")
	print("  all: avg %dus  max %dus  |  miss: avg %dus  max %dus  |  hit: avg %dus  max %dus" % [
		pt.get("avg_plan_time_us", 0), pt.get("max_plan_time_us", 0),
		pt.get("avg_search_time_us", 0), pt.get("max_search_time_us", 0),
		pt.get("avg_cache_hit_time_us", 0), pt.get("max_cache_hit_time_us", 0),
	])
	print("")
	print("SEARCH (cache-miss only)")
	print("  iter avg %.1f  max %d/%d  found %.1f%%" % [
		se.get("avg_iterations", 0.0), se.get("max_iterations", 0), GoapPlanner.MAX_ITERATIONS,
		se.get("plan_found_rate", 0.0) * 100.0,
	])
	print("")
	print("CACHE")
	print("  hit %.1f%%  miss: cold %d ttl %d precond %d  evict %d  peak %d" % [
		ca.get("hit_rate", 0.0) * 100.0,
		ca.get("miss_cold", 0), ca.get("miss_ttl", 0), ca.get("miss_precond", 0),
		ca.get("eviction_count", 0), ca.get("cache_entries_peak", 0),
	])
	print("")
	print("SCHEDULING")
	print("  dec/f %.1f  avg %.2fms  p99 %.2fms  deferred %.1f%%  replans %d" % [
		sc.get("avg_decisions_per_frame", 0.0),
		sc.get("avg_decision_time_ms", 0.0),
		sc.get("p99_decision_time_ms", 0.0),
		sc.get("deferred_rate", 0.0) * 100.0,
		sc.get("total_replans", 0),
	])
	var reasons: Dictionary = sc.get("replan_reason_dist", {})
	if not reasons.is_empty():
		var total_replans: int = sc.get("total_replans", 1)
		var parts: Array[String] = []
		for reason: String in reasons:
			var short_reason: String = reason.substr(0, 20)
			parts.append("%s %.1f%%" % [short_reason, float(reasons[reason]) / float(total_replans) * 100.0])
		print("  reasons: %s" % " ".join(parts))
	print("")
	print("QUALITY")
	print("  thrash %.1f%%  goal-switch %.1f/s" % [
		qu.get("thrash_rate", 0.0) * 100.0,
		qu.get("goal_switch_rate", 0.0),
	])
	print("")
	print("SCOPE")
	print("  state-vars %d  actions %d  goals %d  planning-keys %d" % [
		sp.get("state_var_count", 0), sp.get("available_action_count", 0),
		sp.get("goal_count", 0), sp.get("planning_key_count", 0),
	])


static func check_budgets(metrics: Dictionary, budgets: Dictionary) -> Array[Dictionary]:
	## Returns array of {name, actual, budget, pass} for each budget check.
	var results: Array[Dictionary] = []
	var pt: Dictionary = metrics.get("planning_time", {})
	var se: Dictionary = metrics.get("search", {})
	var ca: Dictionary = metrics.get("cache", {})
	var sc: Dictionary = metrics.get("scheduling", {})

	## Max checks (actual <= budget)
	var max_checks: Dictionary = {
		"avg_search_time_us": pt.get("avg_search_time_us", 0.0),
		"avg_decision_time_ms": sc.get("avg_decision_time_ms", 0.0),
		"p99_decision_time_ms": sc.get("p99_decision_time_ms", 0.0),
		"avg_iterations_max": se.get("avg_iterations", 0.0),
		"thrash_rate_max": metrics.get("quality", {}).get("thrash_rate", 0.0),
	}
	for key: String in max_checks:
		if not budgets.has(key):
			continue
		var actual: float = float(max_checks[key])
		var budget: float = float(budgets[key])
		results.append({"name": key, "actual": actual, "budget": budget, "pass": actual <= budget})

	## Min checks (actual >= budget)
	var min_checks: Dictionary = {
		"cache_hit_rate_min": ca.get("hit_rate", 0.0),
		"plan_found_rate_min": se.get("plan_found_rate", 0.0),
		"plan_completion_rate_min": metrics.get("quality", {}).get("plan_completion_rate", 0.0),
	}
	for key: String in min_checks:
		if not budgets.has(key):
			continue
		var actual: float = float(min_checks[key])
		var budget: float = float(budgets[key])
		results.append({"name": key, "actual": actual, "budget": budget, "pass": actual >= budget})

	return results


static func print_budget_results(results: Array[Dictionary]) -> void:
	var passed: int = 0
	var total: int = results.size()
	var failures: Array[Dictionary] = []
	for r in results:
		if r["pass"]:
			passed += 1
		else:
			failures.append(r)

	print("")
	if failures.is_empty():
		print("BUDGET %d/%d PASS" % [passed, total])
	else:
		print("BUDGET %d/%d FAIL" % [passed, total])
		for f in failures:
			print("  FAIL %s: %.2f > %.2f" % [f["name"], f["actual"], f["budget"]])


static func write_json(path: String, metrics: Dictionary, agent_count: int, frame_count: int, duration_s: float, budget_results: Array[Dictionary]) -> void:
	var passed: int = 0
	var failures: Array[String] = []
	for r in budget_results:
		if r["pass"]:
			passed += 1
		else:
			failures.append(r["name"])

	var data := {
		"timestamp": Time.get_datetime_string_from_system(),
		"agent_count": agent_count,
		"frames": frame_count,
		"duration_s": duration_s,
		"metrics": metrics,
		"budget_result": {
			"pass": failures.is_empty(),
			"total": budget_results.size(),
			"passed": passed,
			"failures": failures,
		},
	}

	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GoapEvalReport: Failed to write JSON to %s" % path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("JSON exported to %s" % path)
```

- [ ] **Step 2: Commit**

```bash
git add gol-project/scripts/tests/goap_eval/goap_eval_report.gd
git commit -m "feat(goap-eval): add GoapEvalReport

Text report to stdout + optional JSON export. Budget checking
with PASS/FAIL per metric."
```

---

### Task 5: GoapEvalMain Controller + Scene

The main controller: boots the game, waits for systems, collects, reports.

**Files:**
- Create: `gol-project/scripts/tests/goap_eval/goap_eval_main.gd`
- Create: `gol-project/scenes/tests/goap_eval_main.tscn`

- [ ] **Step 1: Create the controller script**

```gdscript
extends Node

## GOAP Evaluation Suite — main controller.
## Usage: godot --headless --path . res://scenes/tests/goap_eval_main.tscn -- [--json] [--duration=60] [--skip-menu]

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

var _json_export: bool = false
var _duration_sec: float = 60.0

var _collecting: bool = false
var _collection_start_frame: int = 0
var _collection_target_frames: int = 0
var _agent_count: int = 0


func _ready() -> void:
	_parse_args()
	_boot_game()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--json":
			_json_export = true
		elif arg.begins_with("--duration="):
			_duration_sec = float(arg.substr("--duration=".length()))


func _boot_game() -> void:
	GOL.setup()

	## Use production boot path — PCG + scene switch, identical to GOL.start_game().
	var config := ProceduralConfig.new()
	config.pcg_config().pcg_seed = randi()
	var result := ServiceContext.pcg().generate(config.pcg_config())
	if result == null or not result.is_valid():
		push_error("[goap_eval] PCG generation failed")
		print("[goap_eval] FAIL: PCG generation failed")
		get_tree().quit(2)
		return

	GOL.Game.campfire_position = ServiceContext.pcg().find_nearest_village_poi()
	ServiceContext.scene().switch_scene(config)

	## Wait for world + systems to initialize.
	await get_tree().process_frame
	await get_tree().process_frame

	_start_collection()


func _start_collection() -> void:
	## Count GOAP agents.
	if ECS.world == null:
		push_error("[goap_eval] ECS.world is null after boot")
		print("[goap_eval] FAIL: ECS.world is null")
		get_tree().quit(2)
		return

	var goap_entities: Array = ECS.world.query.with_all([CGoapAgent]).execute()
	_agent_count = goap_entities.size()
	if _agent_count == 0:
		push_error("[goap_eval] No GOAP agents found")
		print("[goap_eval] FAIL: No GOAP agents found")
		get_tree().quit(2)
		return

	## Enable profiling on both systems.
	GoapPlanner.enable_profiling()
	SAI.enable_profiling()

	_collection_start_frame = Engine.get_process_frames()
	_collection_target_frames = int(_duration_sec * 60.0)  ## Assume 60fps in headless
	_collecting = true

	print("[goap_eval] Collecting: %d agents, %d frames (%.0fs)..." % [_agent_count, _collection_target_frames, _duration_sec])


func _process(_delta: float) -> void:
	if not _collecting:
		return

	var elapsed_frames: int = Engine.get_process_frames() - _collection_start_frame
	if elapsed_frames < _collection_target_frames:
		return

	## Collection complete.
	_collecting = false
	GoapPlanner.disable_profiling()
	SAI.disable_profiling()

	var actual_frames: int = elapsed_frames
	var actual_duration: float = actual_frames / 60.0

	## Collect + report.
	var metrics: Dictionary = GoapMetricsCollector.collect()

	GoapEvalReport.print_text(metrics, _agent_count, actual_frames, actual_duration)
	var budget_results: Array[Dictionary] = GoapEvalReport.check_budgets(metrics, BUDGETS)
	GoapEvalReport.print_budget_results(budget_results)

	## Optional JSON export.
	if _json_export:
		var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		var json_path: String = "res://logs/tests/%s-goap.json" % timestamp
		GoapEvalReport.write_json(json_path, metrics, _agent_count, actual_frames, actual_duration, budget_results)

	## Exit with budget result.
	var all_passed: bool = true
	for r in budget_results:
		if not r["pass"]:
			all_passed = false
			break

	get_tree().quit(0 if all_passed else 1)


func _exit_tree() -> void:
	GoapPlanner.disable_profiling()
	SAI.disable_profiling()
	GOL.teardown()
```

- [ ] **Step 2: Create the scene file**

```
[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/tests/goap_eval/goap_eval_main.gd" id="1_goap_eval"]

[node name="GoapEvalMain" type="Node"]
script = ExtResource("1_goap_eval")
```

- [ ] **Step 3: Commit**

```bash
git add gol-project/scripts/tests/goap_eval/goap_eval_main.gd gol-project/scenes/tests/goap_eval_main.tscn
git commit -m "feat(goap-eval): add GoapEvalMain controller and scene

Boots real game headless via ProceduralConfig, waits for systems,
enables profiling, collects for --duration seconds, reports metrics
and budget pass/fail, exits 0 or 1."
```

---

### Task 6: Go CLI Entry Point

Add `gol test goap` subcommand.

**Files:**
- Create: `gol-tools/cli/cmd/goap_eval.go`

- [ ] **Step 1: Create the CLI command**

```go
package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"

	"github.com/spf13/cobra"

	"github.com/Dluck-Games/gol-cli/internal/godot"
)

var (
	flagGoapJSON     bool
	flagGoapDuration int
)

var goapEvalCmd = &cobra.Command{
	Use:   "goap",
	Short: "Run GOAP evaluation benchmark",
	Long:  "Boot the real game headless, collect GOAP planner/scheduling metrics, report results with budget pass/fail.",
	RunE:  goapEvalRun,
}

func init() {
	testCmd.AddCommand(goapEvalCmd)
	goapEvalCmd.Flags().BoolVar(&flagGoapJSON, "json", false, "export JSON report to logs/tests/")
	goapEvalCmd.Flags().IntVar(&flagGoapDuration, "duration", 60, "collection duration in seconds")
}

func goapEvalRun(cmd *cobra.Command, args []string) error {
	projectDir, err := resolveProject()
	if err != nil {
		return err
	}

	godotBin, err := godot.FindBinary()
	if err != nil {
		return err
	}

	var extraArgs []string
	if flagGoapJSON {
		extraArgs = append(extraArgs, "--json")
	}
	extraArgs = append(extraArgs, "--duration="+strconv.Itoa(flagGoapDuration))
	extraArgs = append(extraArgs, "--skip-menu")

	godotArgs := []string{
		"--headless",
		"--path", projectDir,
		"res://scenes/tests/goap_eval_main.tscn",
		"--",
	}
	godotArgs = append(godotArgs, extraArgs...)

	if flagVerbose {
		fmt.Fprintf(os.Stderr, "Running: %s %v\n", godotBin, godotArgs)
	}

	c := exec.Command(godotBin, godotArgs...)
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr

	if err := c.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			os.Exit(exitErr.ExitCode())
		}
		return fmt.Errorf("failed to run GOAP eval: %w", err)
	}

	return nil
}
```

- [ ] **Step 2: Build and verify help output**

Run:
```bash
cd gol-tools/cli && go build -o gol . && ./gol test goap --help
```

Expected output should show the `goap` subcommand with `--json` and `--duration` flags.

- [ ] **Step 3: Commit**

```bash
git add gol-tools/cli/cmd/goap_eval.go
git commit -m "feat(cli): add 'gol test goap' subcommand

Launches Godot headless with goap_eval_main.tscn, passes --json
and --duration flags through, relays exit code."
```

---

### Task 7: End-to-End Smoke Test

Verify the full pipeline works.

**Files:** None (manual verification)

- [ ] **Step 1: Run with short duration to smoke test**

```bash
gol test goap --duration=10
```

Expected: Text report printed to stdout, exit code 0 or 1 depending on budgets.

- [ ] **Step 2: Run with JSON export**

```bash
gol test goap --duration=10 --json
```

Expected: Same text report + JSON file at `gol-project/logs/tests/<timestamp>-goap.json`.

- [ ] **Step 3: Verify JSON is valid**

```bash
cat gol-project/logs/tests/*-goap.json | python -m json.tool > /dev/null && echo "Valid JSON"
```

- [ ] **Step 4: Review output for sanity**

Check that:
- Agent count > 0
- Planning time values are in microseconds (not zero)
- Cache hit rate is between 0 and 1
- Scheduling metrics show decisions happening
- Scope shows real action/state counts (should see ~23 actions, ~18 state vars)
- Budget results show pass/fail for each check

- [ ] **Step 5: Final commit with any fixes**

If any fixes were needed during smoke testing, commit them.
