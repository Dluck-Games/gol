# Map Tiles

- **Dimensions**: 32×32
- **Target**: `gol-project/assets/tiles/<surface_type>/`

## Prompt Template

```
A [surface type] ground tile for a 2D top-down survival game.
Seamless edges for tiling. [Surface details].
Flat perspective, viewed from above at slight angle.
Subtle texture variation, not busy or noisy.
```

## Example (Existing: road/base.png, sidewalk/base.png)

```
A cracked asphalt road tile for a 2D top-down survival game.
Seamless edges for tiling. Faded lane markings, small debris.
Flat perspective, viewed from above at slight angle.
Subtle texture variation, not busy or noisy.
```

## Tile Types

| Type | Variants | Notes |
|------|----------|-------|
| road | base, dashed lines (h/v), crosswalk | Directional variants |
| sidewalk | base, grassground (1-4) | Multiple grass variants |
| transitions | corner, edge, outcorner | Cardinal/ordinal directions |

## Transition Pattern

Transitions follow: `<type>/<transition>/<logic>/<direction>/base.png`
- Transitions: corner, edge, outcorner
- Logic: road, grassground
- Directions: n/s/e/w (corners), ne/nw/se/sw (edges)

## Avoid

- Non-seamless edges (tiles must tile perfectly)
- Too much texture detail (becomes noisy when tiled)
- Perspective inconsistency with other tiles
