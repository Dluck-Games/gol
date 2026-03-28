# Unified Logging Design

**Date:** 2026-03-28
**Status:** Approved

## Goal

Consolidate all log output across the GOL monorepo into a single `logs/` directory at the management repo root. Achieve a UE-style experience where all process logs are in one predictable location.

## Current State

Logs are scattered across multiple locations:

- `.foreman/logs/` — daemon logs, agent process logs, launchd stdout/stderr captures
- `gol-tools/foreman/logs/` — legacy stub files committed to source repo
- Godot `user://` (`~/Library/Application Support/Godot/app_userdata/God of Lego/`) — PCG debug log
- `.foreman/progress/` — per-issue progress markdown
- `.foreman/plans/`, `.foreman/reviews/`, `.foreman/tests/` — legacy working docs

Additionally, a standalone `PCGLogger` class (`scripts/debug/pcg_logger.gd`) exists solely for WFC solver debugging. It writes structured JSON to `user://pcg_debug.log` but has only one consumer.

## Design

### Directory Structure (Final State)

```
gol/
  logs/                              ← .gitignore, pure local state
    foreman/
      daemon-YYYYMMDD.log            ← daemon structured log (daily rotation)
      launchd-daemon.log             ← launchd stdout capture
      launchd-daemon-error.log       ← launchd stderr capture
      issues/
        issue-{N}/
          tl.log
          planner.log
          coder.log
          tester.log
          reviewer-pr-{PR}.log
          progress.md
    game/
      game-YYYYMMDD-HHMMSS.log      ← one file per game launch (full process log)
  .foreman/
    state.json                       ← task state SSOT (retained)
    cancel/                          ← task cancellation drop files (retained)
```

### Changes

#### gol-tools/foreman (submodule)

1. **`lib/logger.mjs`** — Change `logDir` to point to `logs/foreman/` relative to management repo root (resolve via `config.repoRoot` or equivalent).

2. **`lib/process-manager.mjs`** — `createProcessLog()` must support subdirectory paths (e.g., `issues/issue-188/tl.log`). Ensure `mkdirSync` creates intermediate directories.

3. **`foreman-daemon.mjs`** — Change log prefix at each spawn call site:
   - TL: `tl-issue-{N}` → `issues/issue-{N}/tl`
   - Planner: `planner-issue-{N}` → `issues/issue-{N}/planner`
   - Coder: `coder-issue-{N}` → `issues/issue-{N}/coder`
   - Tester: `tester-issue-{N}` → `issues/issue-{N}/tester`
   - Reviewer: `reviewer-issue-{N}-pr-{PR}` → `issues/issue-{N}/reviewer-pr-{PR}`

4. **Progress file writes** — Redirect from `.foreman/progress/issue-{N}.md` to `logs/foreman/issues/issue-{N}/progress.md`.

5. **launchd plist** (`com.dluckdu.foreman-daemon.plist`) — Update `StandardOutPath` and `StandardErrorPath` to absolute paths under `logs/foreman/` (e.g., `/Users/dluckdu/Documents/Github/gol/logs/foreman/launchd-daemon.log`). launchd requires absolute paths.

6. **Delete stub files** — Remove `gol-tools/foreman/logs/daemon.log`, `launchd-daemon.log`, `launchd-daemon-error.log` and the containing directory.

#### gol-project (submodule)

1. **Delete `scripts/debug/pcg_logger.gd`** — Remove the standalone PCG logger module entirely.

2. **`scripts/pcg/wfc/wfc_solver.gd`** — Replace all `PCGLogger` usage with `print()` calls. Remove the `logger` property, `set_logger()` method, and `PCGLogger` const/preload.

3. **Game launch script** — Create or modify the shortcut launch script to redirect Godot's stdout/stderr to `logs/game/game-YYYYMMDD-HHMMSS.log`. The script should:
   - Ensure `logs/game/` directory exists
   - Generate timestamped filename
   - Launch Godot with stdout/stderr redirected to that file
   - Optionally also tee to terminal for interactive use

#### gol (management repo)

1. **`.gitignore`** — Add `logs/` entry.

2. **`.foreman/` cleanup** — Remove `logs/`, `progress/`, `plans/`, `reviews/`, `tests/` directories. Only `state.json` and `cancel/` remain.

### Out of Scope

- Log cleanup/retention policies (no auto-deletion of old logs)
- Log format changes (daemon keeps its existing structured format)
- A new unified game logger framework (game just uses print/push_error for now)
- Log aggregation or search tooling
