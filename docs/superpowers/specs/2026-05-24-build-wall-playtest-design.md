# Build Wall Playtest Design

## Overview

Automated playtest that verifies the end-to-end building construction flow: a worker picks up materials from a stockpile, delivers them to a Wall build site, and completes construction.

**Suite name:** `build_wall`
**CLI command:** `gol test playtest --suite build_wall`
**Base class:** `AutomationPlayTestSuite`

## Test Configuration

| Element | Setup |
|---------|-------|
| Map | 20x20 grid |
| Player | Center of map, normal HP |
| Stockpile | Within 2 tiles of player, contains 3 wood |
| Worker | 1 worker NPC near stockpile |
| BuildSite | Wall ghost placed at worker-reachable position through `SBuildOperation._place_ghost()` |
| Timeout | 90 seconds |

No time compression — Wall builds in 4 seconds and worker paths are short.

## Checkpoint Chain

8 sequential checkpoints validating the worker BuildTask FSM:

| # | Checkpoint | Verification |
|---|-----------|-------------|
| 1 | `build_site_created` | BuildSite entity exists, requires 3 wood, deposited = 0 |
| 2 | `worker_assigned` | Worker holds BuildTask targeting our BuildSite |
| 3 | `worker_moving_to_stockpile` | Worker BuildTask state = MOVING_TO_STOCKPILE |
| 4 | `material_picked_up` | Worker state past PICKING_UP, stockpile wood reduced |
| 5 | `worker_moving_to_site` | Worker BuildTask state = MOVING_TO_SITE |
| 6 | `material_delivered` | Worker in DELIVERING or CONSTRUCTING, BuildSite deposited = 3 |
| 7 | `construction_started` | Worker BuildTask state = CONSTRUCTING |
| 8 | `building_completed` | BuildSite entity removed, CBuilding entity at same position |

## Execution Flow

1. `_setup()` — spawn map, player, stockpile (3 wood), worker
2. **Wait 3 seconds** — let scene stabilize, recording captures empty ground
3. Place Wall ghost through the production `SBuildOperation._place_ghost()` path
4. `check_next_checkpoint()` validates 8 checkpoints sequentially
5. All passed — **wait 3 seconds** — recording captures completed building
6. State PASSED, test ends

## Implementation Lessons

- Reuse the production placement path. The playtest should get the world `SBuildOperation`, set `_selected_building_id = "wall"`, and call `_place_ghost(position)`, then track the resulting ghost/build site. Hand-creating `ghost_building`, filling `CBuildSite`, and submitting `BuildTask` duplicates production logic and skips visual setup.
- `ghost_building.tres` is only a generic recipe template. The production path looks up `building_id` in `BuildingTable`, copies the target building recipe texture and sprite offset into `CSprite`, creates a placeholder texture when needed, applies `PLACED_GHOST_MODULATE`, and queues the build task.
- Recipe spawn does not guarantee visibility. `camp_stockpile.tres` also depends on production setup (`StockpileSpriteFactory.get_texture()` in `GOLWorld._spawn_camp_stockpile_and_worker()`) for its texture.
- If a playtest entity is invisible, inspect the production spawn/initialization path before changing the recipe or adding test-only rendering code.

## Failure Handling

| Condition | Result |
|-----------|--------|
| Single checkpoint timeout | FAILED, report which checkpoint stalled |
| Overall timeout (90s) | ERROR, test stops |
| Worker entity disappears | Detected in checkpoint check → FAILED |

## Out of Scope

- Player placement UI / ghost placement flow
- Multiple workers
- Other building types (Door, Healing Station, Watchtower)
- Demolition or repair mechanics
- Resource gathering (logging, etc.)
