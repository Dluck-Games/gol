# Handoff: Door / Wall Pixel Art Mismatch

Date: 2026-05-27
Session focus: Document the door-vs-wall visual mismatch so the user can tune the pixel art assets in Codex

## User Requests (Verbatim)

- "我想起来了，之前为什么有这个问题，是因为我说门的贴图和墙的贴图很奇怪。就是墙是斜着的，然后门是竖着的，两个东西看起来不匹配，然后我尝试让他去重新画了个美术素材。现在换回来了，的确是门显示正确了，但是效果就是不对，还是得让他去重新画一版。"
- "写一份交接文档，用户要基于这份文档在 Codex 中亲自调教门和墙的像素美术素材。"

## Goal

Prepare context for a follow-up Codex session where the user will personally tune the door and wall pixel art assets. The main goal is to make doors visually match the isometric / angled wooden wall style without reintroducing the bug where door textures are replaced by wall mask textures.

## Problem Background

The wall art is built for an isometric / angled view. Wall segments are diagonal in screen space and use neighbor-aware mask sprites so adjacent pieces visually connect.

The original door art, `door_closed.png` and `door_open.png`, is more front-facing / vertical. It reads as a door, but it does not visually fit the angled wall line, especially in the night raid perimeter where the wall is a slanted diamond shape.

To solve that art mismatch, a previous AI attempt changed the door recipe to use wall mask textures:

- closed door: `assets/sprites/items/walls/wall_mask_10.png`
- open door: `assets/sprites/items/walls/wall_mask_0.png`

That made the door visually blend into the wall, but it also created a gameplay/rendering bug: the entity at the door cell was logically a `CDoor`, while visually it looked like an ordinary wall. This confused visual diagnosis and made the door appear as a broken wall connection rather than a distinct door.

## Current State

The door recipe has been restored to the original door sprites:

- closed door: `assets/sprites/items/door_closed.png`
- open door: `assets/sprites/items/door_open.png`

This fixes the "door looks like a wall mask" bug. Runtime verification showed the night raid door entity at `Vector2i(10, 13)` now has:

- `CDoor = true`
- `CWall = false`
- `CSprite.texture = res://assets/sprites/items/door_closed.png`
- `CDoor.closed_texture = res://assets/sprites/items/door_closed.png`
- `CDoor.open_texture = res://assets/sprites/items/door_open.png`

However, the visual style mismatch remains: the door is readable as a door, but it still looks too vertical / front-facing compared with the angled wall segments.

## Key Files

- Door textures:
  - `gol-project/assets/sprites/items/door_closed.png`
  - `gol-project/assets/sprites/items/door_open.png`
- Wall textures:
  - `gol-project/assets/sprites/items/wall.png`
  - `gol-project/assets/sprites/items/walls/wall_mask_*.png`
- Door recipe:
  - `gol-project/resources/recipes/door.tres`
- Wall connection visual system:
  - `gol-project/scripts/systems/s_wall_connection_visual.gd`
- Door visual update system:
  - `gol-project/scripts/systems/s_door.gd`
- Pixel art production skill reference:
  - `.agents/skills/gol-pixel-art/SKILL.md`

## Night Raid Context

The night raid playtest defines a square perimeter from `WALL_MIN = Vector2i(7, 7)` to `WALL_MAX = Vector2i(13, 13)`.

The bottom-edge middle cell is explicitly configured as a door:

```gdscript
const DOOR_CELL := Vector2i(10, 13)
```

In `NightRaidVerifyConfig.entities()`, every perimeter cell is spawned as a wall except `DOOR_CELL`, which is spawned as:

```gdscript
{
    "recipe": "door",
    "name": "ScenarioDoor",
    "components": {
        "CTransform": {"position": _grid_to_world(cell)},
    },
}
```

This means the suspicious visual element in night raid is not a wall entity. It is a `door` recipe entity using whatever texture is configured in `door.tres`.

## Wall Connection System

`SWallConnectionVisual` is a 4-neighbor mask system, not a Godot TileMap autotile.

The bit values are:

- `NORTH = 1`
- `EAST = 2`
- `SOUTH = 4`
- `WEST = 8`

The system checks the four adjacent grid cells and builds a mask. It then loads:

```text
res://assets/sprites/items/walls/wall_mask_<mask>.png
```

Examples:

- `wall_mask_0.png`: no neighbors
- `wall_mask_2.png`: east neighbor only
- `wall_mask_8.png`: west neighbor only
- `wall_mask_10.png`: east + west neighbors

Closed doors are currently treated as connectable neighbors:

```gdscript
func _is_wall_connectable(entity: Entity) -> bool:
    return _is_wall_like(entity) or _is_closed_door(entity)
```

But doors are not updated by the wall mask system:

```gdscript
func _should_update_wall_texture(entity: Entity) -> bool:
    return not entity.has_component(CDoor)
```

So a closed door helps nearby walls connect visually, but the door texture itself is controlled by `SDoor`, not by `SWallConnectionVisual`.

## Door Visual System

`SDoor._update_visual()` sets the sprite texture every frame based on door state:

```gdscript
var texture := door.open_texture if door.is_open else door.closed_texture
if texture != null:
    sprite.texture = texture
```

This matters for future art work:

- If `door.closed_texture` is a wall mask, the door will look like a wall.
- If `SWallConnectionVisual` ever calculates a mask texture for doors, `SDoor._update_visual()` can overwrite it afterward.
- Closed doors must participate in wall connectivity as neighbors, but their own rendered texture should remain a door, not a plain wall segment.

For future implementation, decide one of these approaches before changing art/code:

1. Keep a single closed-door sprite and make it visually match the most common wall orientation.
2. Add neighbor-aware door variants such as `door_closed_mask_<mask>.png` and update systems so doors can use direction-aware door art.
3. Let `SWallConnectionVisual` handle closed-door visual selection and make `SDoor` avoid overwriting connection-derived textures unless the door opens/closes.

Do not solve the art mismatch by pointing `door.tres` back to `wall_mask_*.png`; that recreates the previous bug.

## Art Requirements

The new door art should:

- Match the wall's isometric / angled perspective.
- Read as a door or gate, not as a generic wall post.
- Have both closed and open states.
- Fit the 32x32 sprite footprint used by the existing item sprites.
- Respect the current `CSpatialAnchor` offset in `door.tres` (`Vector2(0, -16)`).
- Work beside the wall masks in `assets/sprites/items/walls/`.
- Avoid making the door visually indistinguishable from `wall_mask_10.png`.

Recommended visual direction:

- Closed door: a short angled wooden gate panel aligned with the diagonal fence rail, with a recognizable latch / darker doorway detail.
- Open door: same perspective, visibly swung open or partly displaced, while still matching the wall palette.
- Keep silhouettes simple and readable at gameplay zoom.

## Suggested Codex Workflow

1. Open `.agents/skills/gol-pixel-art/SKILL.md` and follow the project pixel art pipeline.
2. Inspect the existing wall mask sprites as visual references:
   - `assets/sprites/items/wall.png`
   - `assets/sprites/items/walls/wall_mask_10.png`
   - neighboring endpoint masks such as `wall_mask_2.png` and `wall_mask_8.png`
3. Generate or hand-edit candidate replacements for:
   - `assets/sprites/items/door_closed.png`
   - `assets/sprites/items/door_open.png`
4. Keep `resources/recipes/door.tres` pointing at the door assets, not wall mask assets.
5. Run the night raid playtest or live game and inspect `Vector2i(10, 13)` visually.
6. Verify runtime texture paths with the debug bridge if needed:
   - closed door should use `res://assets/sprites/items/door_closed.png`
   - open door should use `res://assets/sprites/items/door_open.png`

## Current Uncommitted State

At the time this handoff was written, `gol-project/resources/recipes/door.tres` has an uncommitted fix restoring the original door texture paths.

Expected diff:

```diff
- res://assets/sprites/items/walls/wall_mask_10.png
- res://assets/sprites/items/walls/wall_mask_0.png
+ res://assets/sprites/items/door_closed.png
+ res://assets/sprites/items/door_open.png
```

This handoff file itself is also intentionally uncommitted because the user requested "不要提交".

## Constraints

- Do not replace door textures with wall mask textures again.
- Keep the door logically distinct from walls (`CDoor`, not `CWall`).
- A closed door should be connectable for neighboring wall visuals.
- Avoid broad refactors unless adding direction-aware door variants requires a small system change.
- If changing runtime visual logic, inspect both:
  - `scripts/systems/s_wall_connection_visual.gd`
  - `scripts/systems/s_door.gd`
- Use `gol` CLI for running the game and debug bridge commands.
- Save temporary screenshots outside the project tree, for example under `/tmp/`.

## Useful Verification Command Pattern

Run the night raid playtest live:

```bash
cd /Users/dluck/Documents/GitHub/gol/gol-project
gol run game --detach --windowed -- --skip-menu --playtest=night_raid
```

Then use the debug bridge to inspect or capture:

```bash
gol debug get entity_count
gol debug screenshot
gol stop
```

For deeper runtime inspection, create a temporary script under the management repo's `.debug/scripts/` directory and run it with:

```bash
gol debug script /Users/dluck/Documents/GitHub/gol/.debug/scripts/<script>.gd
```

## Continuation Notes

The immediate code bug is fixed by restoring `door.tres` to door assets. The remaining work is art direction: create a better isometric door/gate sprite that matches the angled wall system while remaining visibly different from a wall segment.

When continuing, start by reviewing this file, the current `door.tres` diff, and `.agents/skills/gol-pixel-art/SKILL.md`.
