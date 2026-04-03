# Foreman Label Timeline Optimization

**Date:** 2026-04-03
**Status:** Draft
**Scope:** gol-tools/foreman

## Problem

GitHub label operations in foreman produce redundant timeline entries. When labels are removed then immediately re-added (e.g., `reset` removes `foreman:assign` then adds it back), GitHub records both events, creating noise in the issue timeline.

## Goal

Eliminate unnecessary label add/remove operations so that GitHub issue timelines only show meaningful state transitions. Keep the `transitionLabels()` API unchanged — optimize at the call sites.

## Changes

### 1. `reset` Command — `foreman-ctl.mjs`

**Current behavior:** Remove all `foreman:*` labels in one call, then add `foreman:assign` in a second call. Always 2 API calls, always 2+ timeline entries.

**New behavior:** Compute the minimal diff between current state and desired state (`foreman:assign` only), then execute 0 or 1 API call.

**Logic:**

```
currentForeman = current labels filtered by startsWith('foreman:')
toRemove = currentForeman - {'foreman:assign'}
toAdd = 'foreman:assign' not in currentForeman ? ['foreman:assign'] : []

if toRemove is empty AND toAdd is empty:
    skip (no API call)
else:
    single gh issue edit with --remove-label and/or --add-label as needed
```

**Timeline effect:**

| Scenario | Before | After |
|---|---|---|
| Issue has only `foreman:assign` | 2 entries (remove + re-add) | 0 entries |
| Issue has `foreman:progress` + `foreman:assign` | 2 entries | 1 entry (remove progress) |
| Issue has `foreman:progress`, no `foreman:assign` | 2 entries | 1 entry (remove progress + add assign, merged) |

### 2. Phase C Stale Demotion Guard — `foreman-daemon.mjs`

**Current behavior:** Phase C in `#runGithubSync()` checks `task.pid` and `#decisionPending` to decide if an issue with `foreman:progress` is actively worked. If neither is set, it demotes `progress → assign`.

**Problem:** When TL abandons an issue in the same sync cycle it was picked up, `#decisionPending` is already cleared and `task.pid` is unset, but a `label_swap` pendingOp targeting the issue is already queued. Phase C doesn't see this and demotes prematurely, causing 4 timeline entries instead of 1.

**New behavior:** Add a third guard condition — check if there is an uncompleted `label_swap` pendingOp for this issue number.

```
hasPendingLabelOp = state.getPendingOps() has any op where:
    op.issueNumber === issue.number AND
    op.steps has any step where step.action === 'label_swap' AND step.status !== 'completed'

isActive = task && (task.pid || decisionPending || hasPendingLabelOp)
```

**Timeline effect:** Phase C skips demotion when a `label_swap` is pending, letting the pending operation handle the label transition in one step. Reduces 4 timeline entries to 1 in the edge case.

## Non-Changes

The following are confirmed safe and require no modification:

- **`transitionLabels()` in `github-sync.mjs`** — single remove/add per call, API unchanged
- **`label_swap` normal path** — single `transitionLabels` call, no redundancy
- **`label_swap` stale-done cleanup** — removes a different label (`foreman:done`), not a re-add
- **Phase A issue pickup (`assign → progress`)** — single call, no redundancy
- **Phase C normal path** — correctly skipped when PID or decisionPending is set

## Files Modified

1. **`gol-tools/foreman/bin/foreman-ctl.mjs`** — reset command label logic (~15 lines rewrite)
2. **`gol-tools/foreman/foreman-daemon.mjs`** — Phase C isActive guard (~3 lines added)

Changes are independent of each other.

## Testing

- **Reset command:** Test with issues in each label state (assign-only, progress+assign, progress-only, blocked, no foreman labels). Verify correct labels after reset and that only necessary API calls are made.
- **Phase C guard:** Simulate same-cycle pickup + abandon scenario. Verify Phase C skips demotion when `label_swap` pendingOp exists.
