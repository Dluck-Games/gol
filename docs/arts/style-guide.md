# GOL Art Style Guide

## Color Direction

The GOL palette is a style reference, not a hard production limit for every sprite. Use these colors to guide mood, contrast, and saturation, but preserve or sample concept-art colors when the strict 10-color palette damages readability or material identity.

For small production sprites:

- Prefer a compact local palette of 6-16 colors per sprite.
- Keep colors muted and desaturated, close in spirit to the GOL palette.
- Allow source-derived oranges, greens, browns, reds, and other material colors when they make the object recognizable.
- Avoid smooth gradients; use deliberate pixel clusters and flat color ramps.
- The final quality gate is visual readability and material identity at target size, not palette compliance alone.

## Reference Palette (10 Colors)

| Hex | RGB | Name | Use |
|-----|-----|------|-----|
| #111a24 | (17, 26, 36) | Dark blue-black | Deep shadows |
| #102e58 | (16, 46, 88) | Dark blue | Mid shadows |
| #11767f | (17, 118, 127) | Teal | Accent, water, highlights |
| #a02342 | (160, 35, 66) | Crimson | Danger, blood, alerts |
| #83b5b5 | (131, 181, 181) | Muted cyan | Mid-tone cool |
| #b0c2c2 | (176, 194, 194) | Light gray-cyan | Highlights cool |
| #b68d7b | (182, 141, 123) | Dusty rose | Mid-tone warm |
| #a27b6b | (162, 123, 107) | Taupe | Shadows warm |
| #091018 | (9, 16, 24) | Near black | Outlines, darkest |
| #b8cccc | (184, 204, 204) | Pale cyan | Lightest highlight |

Use this palette as the default reference for mood and lighting. Use exact indexed mapping only when it preserves the asset's identity.

## Aesthetic Rules

- Muted, desaturated palette similar to Game Boy-style indie pixel art; source-derived colors are allowed when needed for readability
- Simple geometric shapes with strong silhouettes
- No gradients or smooth color transitions
- No dithering — flat, clean color fills only
- Transparent background (RGBA PNG)
- Light wear details: small pixel chips, faded edges, nothing noisy
- Elegant, minimalist, restrained aesthetic
- Brutalist architecture influence for buildings and structures

## Texture Filter

All sprites use nearest-neighbor filtering. Never use bilinear or trilinear.

## Animation Conventions

| Animation | Frames | FPS | Layout |
|-----------|--------|-----|--------|
| idle | 2 | 2.0 | Horizontal strip |
| walk | 4 | 7.0 | Horizontal strip |
| death | 22 | 14.0 | Horizontal strip |

Sprite sheets are always horizontal strips. Frame dimensions match the asset type.

## File Format

- Format: PNG (RGBA 8-bit)
- Compression: None (Godot handles import compression)
- Mipmaps: Disabled
- Import filter: Nearest-neighbor

## Naming Convention

- Lowercase with underscores: `character_movement_01.png`
- Sprite sheets: `<entity>_<animation>_<variant>.png`
- Single sprites: `<entity>_<size>.png` (e.g., `character_32x.png`)
- Tiles: `<surface_type>/base.png` or `<transition>/<direction>/base.png`

## Elemental Colors (In-Game Shader)

| Element | Color | Note |
|---------|-------|------|
| Fire | (255, 77, 13) | Applied via shader, not baked into sprites |
| Wet | (38, 166, 255) | Applied via shader |
| Cold | (128, 230, 255) | Applied via shader |
| Electric | (255, 230, 26) | Applied via shader |

These are NOT part of the 10-color palette — they're applied as shader overlays at runtime.

## Day/Night Lighting

| Time | Ambient Color |
|------|--------------|
| Night | (77, 89, 128) |
| Day | (255, 255, 255) |
| Sunrise | (255, 217, 179) |
| Sunset | (230, 153, 102) |

Sprites should look good under all lighting conditions. Design for the Day (neutral white) lighting.
