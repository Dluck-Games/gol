# Performance Profiler

Runtime performance profiling tool for God of Lego. Collects FPS, per-system ECS timing, entity distribution, and memory stats from a running game instance — designed for AI agents to diagnose performance issues, but readable by humans too.

## Quick Start

```bash
# Game must be running
node gol-tools/ai-debug/ai-debug.mjs perf
```

This returns a JSON snapshot with everything: FPS, frame timing, all system execution times, entity counts, memory usage, and query cache stats.

## Commands

### `perf` / `perf snapshot`

Full performance snapshot. The go-to command for a quick health check.

```bash
node gol-tools/ai-debug/ai-debug.mjs perf
```

**Output fields:**

| Field | Type | Description |
|-------|------|-------------|
| `fps` | int | Current frames per second |
| `frame_time_ms` | float | Time per frame in milliseconds |
| `process_time_ms` | float | Godot `_process` time (ms) |
| `physics_time_ms` | float | Godot `_physics_process` time (ms) |
| `object_count` | int | Total Godot objects alive |
| `memory_mib` | float | Static memory usage in MiB |
| `entity_count` | int | Total ECS entities |
| `archetype_count` | int | Distinct archetype signatures |
| `system_count` | int | Registered ECS systems |
| `debug_mode` | bool | Whether `ECS.debug` is enabled |
| `systems` | array | Per-system timing (see below) |
| `query_cache` | object | Cache hit/miss stats |

**Example output (truncated):**

```json
{
  "fps": 60,
  "frame_time_ms": 16.67,
  "process_time_ms": 8.2,
  "physics_time_ms": 0.8,
  "entity_count": 1041,
  "system_count": 46,
  "memory_mib": 602.8,
  "systems": [
    {"name": "s_ai", "group": "gameplay", "execution_time_ms": 2.31, "entity_count": 471},
    {"name": "s_move", "group": "gameplay", "execution_time_ms": 0.45, "entity_count": 472}
  ],
  "query_cache": {"hit_rate": 0.99, "cached_queries": 45}
}
```

### `perf systems`

Per-system execution timing, sorted slowest-first. Use this to find which system is eating your frame budget.

```bash
node gol-tools/ai-debug/ai-debug.mjs perf systems
```

Each entry contains:

| Field | Description |
|-------|-------------|
| `name` | System script name (e.g. `s_ai`, `s_move`) |
| `group` | Processing group (`gameplay`, `render`, `physics`, etc.) |
| `execution_time_ms` | Time spent in this system last frame |
| `entity_count` | Number of entities processed |
| `archetype_count` | Archetypes matched by the system's query |
| `active` | Whether the system is currently active |
| `parallel` | Whether parallel processing was used |

### `perf entities`

Entity distribution across archetypes and component frequency. Use this to understand what's in the world and spot unexpected entity bloat.

```bash
node gol-tools/ai-debug/ai-debug.mjs perf entities
```

**Output:**

```json
{
  "total": 1057,
  "archetypes": [
    {"signature": 3778125141, "entity_count": 434, "component_count": 11},
    {"signature": 2625573794, "entity_count": 80, "component_count": 4}
  ],
  "by_component": {
    "c_transform": 1056,
    "c_collision": 621,
    "c_camp": 489,
    "c_hp": 489,
    "c_goap_agent": 471,
    "c_movement": 472
  }
}
```

`by_component` shows the top 20 most common components across all entities.

### `perf memory`

Memory and Godot object counts.

```bash
node gol-tools/ai-debug/ai-debug.mjs perf memory
```

| Field | Description |
|-------|-------------|
| `static_memory_mib` | Static memory usage in MiB |
| `object_count` | Total Godot objects |
| `resource_count` | Loaded resources |
| `node_count` | Scene tree nodes |
| `orphan_node_count` | Nodes not in the tree (leak indicator) |

## ECS Debug Mode

Per-system timing data (`execution_time_ms`, `entity_count` per system) requires the GECS debug mode to be enabled. This is a Godot project setting:

**Project Settings → gecs/debug_mode → true**

When disabled, the `systems` array returns a placeholder noting that timing is unavailable. All other data (FPS, memory, entity counts, archetypes, query cache) works regardless.

Debug mode adds a small overhead per system call (~microseconds for timing instrumentation), so it's fine to leave on during development.

## How It Works

```
CLI (Node.js)                        Godot Game
  |                                       |
  | perf snapshot                         |
  |-- write command file ---------------->|
  |                                       |-- AIDebugBridge polls (100ms)
  |                                       |-- Forwards to console: "perf snapshot"
  |                                       |-- PerfCommand collects metrics
  |                                       |-- Returns JSON string
  |                                       |-- Write result file
  |<-- read result file ------------------|
  |                                       |
  | Parse JSON, display                   |
```

The tool is built on the existing AI Debug Bridge IPC layer — same file-based signal mechanism used by all other debug commands. No new dependencies or protocols.

### Components

| Layer | File | Role |
|-------|------|------|
| CLI | `gol-tools/ai-debug/ai-debug.mjs` | Validates subcommand, sends bridge request |
| Bridge | `gol-project/scripts/debug/ai_debug_bridge.gd` | IPC transport (unchanged) |
| Command | `gol-project/scripts/debug/console/commands/perf_command.gd` | Collects metrics, returns JSON |
| Registry | `gol-project/scripts/debug/console/console_registry.gd` | Discovers and registers the command |

### Data Sources

| Metric | Source |
|--------|--------|
| FPS, frame time | `Engine.get_frames_per_second()` |
| Process/physics time | Godot `Performance` monitors |
| System timing | GECS `System.lastRunData` (requires debug mode) |
| Entity/archetype counts | `ECS.world.entities`, `ECS.world.archetypes` |
| Query cache stats | `ECS.world.get_cache_stats()` |
| Memory | `OS.get_static_memory_usage()` |
| Object/node counts | Godot `Performance` monitors |

## Use Cases

**"The game feels slow"** — Run `perf snapshot`. Check `fps` and `process_time_ms`. If process time is high, run `perf systems` to find the bottleneck system.

**"Are there too many entities?"** — Run `perf entities`. Check `total` count and the archetype breakdown. Large archetype with many entities might indicate a spawner gone wild.

**"Is something leaking?"** — Run `perf memory` periodically. Watch `orphan_node_count` (should be 0) and `object_count` trending upward over time.

**"Which system is slowest?"** — Run `perf systems` (requires debug mode). Systems are sorted by `execution_time_ms` descending — the first entry is your hottest system.

**"Is the query cache working?"** — Check `query_cache.hit_rate` in the snapshot. Should be >0.95. Low hit rate means frequent cache invalidation from structural entity changes.
