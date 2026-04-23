# Asset Placement Guide

Where to place each asset type in `gol-project/assets/`.

## Directory Map

| Asset Type | Dimensions | Single Sprite Path | Sprite Sheet Path |
|------------|-----------|-------------------|-------------------|
| character | 32×32 | `sprites/characters/` | `sprite_sheets/characters/` |
| enemy | 32×32 | `sprites/enemies/` | `sprite_sheets/enemies/` |
| box | 32×32 | — | `sprite_sheets/boxes/` |
| tile | 32×32 | — | `tiles/<surface_type>/` |
| vfx | 32×32 | `sprites/effects/` | `sprite_sheets/vfx/<effect_name>/` |
| bullet | 12×12 | `sprites/bullets/` | — |
| icon | 16×16 | `icons/resources/` | — |
| item | 32×32 | `sprites/items/` | — |
| background | 1024+ | `backgrounds/` | — |
| artwork | 3840×2160 | `artworks/` | — |
| ui | varies | `ui/` | — |

All paths are relative to `gol-project/assets/`.

## Tile Hierarchy

Tiles follow a nested directory structure for transitions:

```
tiles/
├── road/
│   ├── base.png                    # Base road tile
│   ├── h/                          # Horizontal variants
│   │   ├── dashed_line_thin.png
│   │   ├── dashed_line_thick.png
│   │   └── crosswalk.png
│   └── v/                          # Vertical variants
└── sidewalk/
    ├── base.png                    # Base sidewalk
    ├── grassground_1.png           # Grass variants (1-4)
    ├── corner/<logic>/<direction>/base.png
    ├── edge/<logic>/<direction>/base.png
    └── outcorner/<logic>/<direction>/base.png
```

Directions: n, s, e, w (corners), ne, nw, se, sw (edges/outcorners)
Logic types: road, grassground

## Artifact Pattern

The pixel art pipeline produces files across three workspace directories:

```
.art-workspace/
├── concepts/           # AI-generated concept images (Gemini/ComfyUI)
│   ├── <name>.prompt       — Generation prompt text
│   └── <name>.original.png — Raw AI concept (1024×1024)
├── aseprite/           # Aseprite source files (agent-edited)
│   ├── <name>.aseprite     — Editable source sprite
│   └── <name>.preview.png  # Latest preview export
└── export/             # Final production PNGs (ready to commit)
    └── <name>.png          — Production pixel art
```

Only files from `.art-workspace/export/` get committed to `gol-project/assets/`.

## Workspace

All art work-in-progress lives in `.art-workspace/` (gitignored):

```bash
# 1. Generate concept
node gol-tools/pixel-art/pixel-art.mjs pipeline \
  --prompt "A healing potion bottle" \
  --type item --backend gemini \
  --output .art-workspace/concepts/potion

# 2. Create sprite and draw in Aseprite
node gol-tools/pixel-art/pixel-art.mjs draw create \
  --type item --output .art-workspace/aseprite/potion

# 3. Agent draws pixel art (referencing concept)
# ... draw apply with JSON instructions ...

# 4. Export final
node gol-tools/pixel-art/pixel-art.mjs draw export \
  --sprite .art-workspace/aseprite/potion.aseprite \
  --output .art-workspace/export/potion.png

# 5. Copy to game assets
cp .art-workspace/export/potion.png gol-project/assets/sprites/items/potion.png
```

## SpriteFrames Resources

Animation definitions live in `gol-project/resources/sprite_frames/`:

| Resource | Animations |
|----------|-----------|
| `player.tres` | death (22f@14fps), idle (2f@2fps), walk (4f@7fps) |
| `enemy.tres` | idle (2f@2fps), walk (4f@7fps) |
| `claw.tres` | (empty — needs animation setup) |
| `campfire.tres` | (empty — needs animation setup) |
