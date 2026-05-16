> **Superseded by `docs/arts/style-guide.md` and `docs/arts/asset-paths.md`.** This file is kept for backward compatibility. See `docs/arts/README.md` for the current SSOT.

# GOL Art Specifications

## Screen Resolution
- Viewport: 960×540
- Stretch mode: canvas_items
- Texture filter: Nearest-neighbor (pixel art mode)

## Asset Dimensions

| Type | Width | Height | Use Case |
|------|-------|--------|----------|
| character | 32 | 32 | Player and NPC sprites |
| enemy | 32 | 32 | Enemy sprites |
| box | 64 | 64 | Supply crates, containers |
| tile | 64 | 32 | Map tiles (isometric) |
| vfx | 100 | 100 | Visual effect sprites |
| bullet | 32 | 32 | Projectile sprites |
| icon | 16 | 16 | UI icons |
| item | 32 | 32 | Inventory item sprites |

All dimensions are multiples of 4.

## Color Palette (10 Colors)

| Hex | RGB | Name | Use |
|-----|-----|------|-----|
| #111a24 | (17, 26, 36) | Dark blue-black | Deep shadows |
| #102e58 | (16, 46, 88) | Dark blue | Mid shadows |
| #11767f | (17, 118, 127) | Teal | Accent, water |
| #a02342 | (160, 35, 66) | Crimson | Danger, blood |
| #83b5b5 | (131, 181, 181) | Muted cyan | Mid-tone cool |
| #b0c2c2 | (176, 194, 194) | Light gray-cyan | Highlights cool |
| #b68d7b | (182, 141, 123) | Dusty rose | Mid-tone warm |
| #a27b6b | (162, 123, 107) | Taupe | Shadows warm |
| #091018 | (9, 16, 24) | Near black | Outlines, darkest |
| #b8cccc | (184, 204, 204) | Pale cyan | Lightest highlight |

## Art Style Guidelines

- Muted, desaturated palette similar to Game Boy-style indie pixel art
- 3-5 tones per sprite maximum
- Simple geometric shapes with strong silhouettes
- No gradients or smooth transitions
- No dithering — flat, clean color fills
- Transparent background (RGBA PNG)
- Light wear details: small pixel chips, faded edges, nothing noisy
- Elegant, minimalist, restrained aesthetic
- Brutalist architecture influence for buildings/structures

## Animation Conventions

| Animation | Frames | FPS | Sheet Layout |
|-----------|--------|-----|-------------|
| idle | 2 | 2.0 | Horizontal strip |
| walk | 4 | 7.0 | Horizontal strip |
| death | 22 | 14.0 | Horizontal strip |

Sprite sheets are horizontal strips. Frame dimensions match the asset type dimensions.

## File Format

- Format: PNG (RGBA 8-bit)
- Compression: None (Godot handles import compression)
- Mipmaps: Disabled
- Import filter: Nearest-neighbor

## Directory Structure

```
gol-project/assets/
├── backgrounds/          # Large scene backgrounds
├── icons/resources/      # Resource UI icons (16×16)
├── sprite_sheets/        # Multi-frame animations
│   ├── boxes/           # Crate variants
│   ├── characters/      # Player animation sheets
│   ├── enemies/         # Enemy animation sheets
│   └── vfx/             # Effect animations
├── sprites/              # Single-frame sprites
│   ├── bullets/
│   ├── characters/
│   ├── effects/
│   ├── enemies/
│   └── items/
├── tiles/                # Tileable terrain
│   ├── road/
│   └── sidewalk/
└── ui/                   # UI elements
```

## Naming Convention

- Lowercase with underscores: `character_movement_01.png`
- Sprite sheets: `<entity>_<animation>_<variant>.png`
- Single sprites: `<entity>_<size>.png` (e.g., `character_32x.png`)
- Tiles: Follow `LogicType/TransitionType/NeighborType/DirectionType/base.png` hierarchy

## Elemental Colors (In-Game)

| Element | Color |
|---------|-------|
| Fire | (255, 77, 13) |
| Wet | (38, 166, 255) |
| Cold | (128, 230, 255) |
| Electric | (255, 230, 26) |

## Day/Night Lighting

| Time | Ambient Color |
|------|--------------|
| Night | (77, 89, 128) |
| Day | (255, 255, 255) |
| Sunrise | (255, 217, 179) |
| Sunset | (230, 153, 102) |
