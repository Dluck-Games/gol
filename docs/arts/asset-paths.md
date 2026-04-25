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

The pixel art pipeline stores source artifacts in `gol-arts/`:

```
gol-arts/
├── artworks/           # AI-generated images + prompts
│   ├── <name>.prompt       — Generation prompt text
│   └── <name>.png          — Raw AI image (concept art, key art)
└── assets/              # Aseprite source files (mirrors gol-project/assets/)
    └── <type>/<name>.aseprite  — Editable source sprite
```

Normalize writes source files to `gol-arts/`. Production PNGs are exported separately to `gol-project/assets/` via the explicit `export` command.

## Workspace

```bash
# 1. Generate concept
node gol-tools/pixel-art/pixel-art.mjs concept potion --type item --prompt 'A healing potion bottle'
# → saves to gol-arts/artworks/potion.png + potion.prompt

# 2. Normalize (produces .aseprite source file)
node gol-tools/pixel-art/pixel-art.mjs normalize potion --type item
# → saves gol-arts/assets/sprites/items/potion.aseprite + .preview.png

# 3. Export to game project (when ready)
node gol-tools/pixel-art/pixel-art.mjs export gol-arts/assets/sprites/items/potion.aseprite
# → exports to gol-project/assets/sprites/items/potion.png
```

## SpriteFrames Resources

Animation definitions live in `gol-project/resources/sprite_frames/`:

| Resource | Animations |
|----------|-----------|
| `player.tres` | death (22f@14fps), idle (2f@2fps), walk (4f@7fps) |
| `enemy.tres` | idle (2f@2fps), walk (4f@7fps) |
| `claw.tres` | (empty — needs animation setup) |
| `campfire.tres` | (empty — needs animation setup) |
