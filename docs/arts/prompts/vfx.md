# Visual Effect Sprites

- **Dimensions**: 32×32
- **Target**: `gol-project/assets/sprites/effects/` (single) or `sprite_sheets/vfx/<effect>/` (animated)

## Prompt Template

```
A [effect type] visual effect sprite for a 2D survival game.
[Motion/energy description]. [Color emphasis].
Transparent background. Bright against dark backgrounds.
Single frame of a [duration] animation.
```

## Example (Existing: claw_1.png through claw_7.png)

```
A slashing claw attack visual effect for a 2D survival game.
Sharp diagonal slash marks with energy trails. Cool teal emphasis.
Transparent background. Frame [N] of 7-frame slash animation.
```

## Existing Effects

| Effect | Frames | Status |
|--------|--------|--------|
| claw | 7 | Sprites exist, SpriteFrames empty |
| campfire | 1 | Single sprite, SpriteFrames empty |

## Avoid

- Effects that are too subtle at 32×32
- Using non-palette colors (elemental colors are shader overlays)
- Inconsistent energy direction across frames
