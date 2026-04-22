# Box / Container Sprites

- **Dimensions**: 32×32
- **Target**: `gol-project/assets/sprite_sheets/boxes/`

## Prompt Template

```
A [condition] [container type] for a 2D survival game.
[Material details]. [Wear/damage description].
Light wear: small pixel chips, faded edges, nothing noisy.
```

## Example (Existing: box.prompt)

```
A clean, readable pixel-art supply crate for a 2D survival game.
Simple geometric shape, strong silhouette, no background.
Subtle shading using 3-5 tones only.
Light wear: small pixel chips, faded edges, nothing noisy.
Variants optional: wooden crate, metal crate, medical supply box, food box.
```

## States

Each box has three states:
- `box.png` — intact/closed
- `box_opened.png` — opened/looted
- `box_destroyed.png` — destroyed/broken

Generate all three states with consistent base design.

## Variations

- Wooden crate (standard)
- Metal container (military)
- Medical supply box (red cross marking)
- Food box (organic markings)

## Avoid

- Making boxes too detailed (they're 32×32)
- Inconsistent style between states
- Forgetting the destroyed state
