# Character Sprites

- **Dimensions**: 32×32
- **Target**: `gol-project/assets/sprites/characters/` (single) or `sprite_sheets/characters/` (animated)

## Prompt Template

```
A [adjective] [character type] for a 2D survival game.
[Pose description]. [Clothing/equipment details].
Clear readable silhouette at small scale. Front-facing or 3/4 view.
```

## Example (Existing: character_32x.png)

```
A rugged survivor wearing a tattered jacket and carrying a makeshift backpack.
Standing idle pose, slightly hunched. Visible tool belt with small items.
Clear readable silhouette at small scale. 3/4 view facing right.
```

## Animation Frames

| Animation | Frames | Notes |
|-----------|--------|-------|
| idle | 2 | Subtle breathing motion |
| walk | 4 | Full walk cycle |
| death | 22 | Collapse sequence |

For animation sheets, generate each frame with consistent structural description, varying only the pose.

## Variations

- Different survivor outfits (military, civilian, medical)
- Different equipment loadouts
- Different body types
- Injured/healthy states

## Avoid

- Too much detail at 32×32 (keep it simple)
- Side-view poses (use 3/4 or front-facing)
- Bright saturated colors (use muted palette)
