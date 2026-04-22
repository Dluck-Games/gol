---
name: gol-pixel-art
description: "Production pixel art asset creation pipeline for God of Lego. Use this skill whenever creating pixel art sprites, generating game assets, producing character/enemy/tile/VFX sprites, designing pixel art for GOL, or converting AI-generated concepts into production-ready pixel art. Triggers: 'pixel art', 'create sprite', 'generate sprite', 'make game art', 'pixel art asset', 'create asset', 'game asset', 'sprite sheet', 'draw sprite', 'new sprite', 'art asset'."
---

# gol-pixel-art

AI-driven pipeline that generates concept art (Gemini/ComfyUI), evaluates it against GOL art standards, and renders production-ready pixel art PNGs.

## When to Use

- Creating new sprites (characters, enemies, items, tiles, VFX, bullets, icons, boxes)
- Converting AI-generated concept images into GOL-compatible pixel art
- Generating sprite sheets for animations
- Producing any visual asset for the GOL game

## Pipeline Overview

```
1. GENERATE — AI creates concept image (1024×1024)
   └── Gemini (default) or ComfyUI (local LoRA)
2. EVALUATE — Automated checks + visual review
   └── Palette compliance, dimensions, silhouette, alpha
3. RENDER — Convert concept to production pixel art
   └── Downscale → palette quantize → grid normalize
4. ASSEMBLE — Combine frames into sprite sheets (optional)
   └── Horizontal strips matching Godot SpriteFrames
```

## Prerequisites

- `GEMINI_API_KEY` environment variable (set in `.env` at project root, or export in shell)
- Get a key at: https://aistudio.google.com/apikey

## Quick Start

```bash
# Full pipeline (most common)
node gol-tools/pixel-art/pixel-art.mjs pipeline \
  --prompt "A weathered wooden supply crate" \
  --type box \
  --backend gemini \
  --output .debug/art-workspace/new_box

# Step-by-step
node gol-tools/pixel-art/pixel-art.mjs generate \
  --prompt "A small healing potion bottle" \
  --backend gemini \
  --output /tmp/potion_concept

node gol-tools/pixel-art/pixel-art.mjs render \
  --input /tmp/potion_concept.original.png \
  --type item \
  --output gol-project/assets/sprites/items/potion.png

node gol-tools/pixel-art/pixel-art.mjs evaluate \
  --image gol-project/assets/sprites/items/potion.png \
  --type item
```

## Asset Types

| Type | Size | Use |
|------|------|-----|
| character | 32×32 | Player/NPC sprites |
| enemy | 32×32 | Enemy sprites |
| box | 32×32 | Supply crates/containers |
| tile | 32×32 | Map tiles |
| vfx | 32×32 | Visual effects |
| bullet | 12×12 | Projectiles |
| icon | 16×16 | UI icons |
| item | 32×32 | Inventory items |

## GOL Art Style

- Muted, desaturated palette (10 colors only)
- Game Boy-style indie pixel art aesthetic
- 3-5 tones per sprite, no gradients
- Strong silhouette, simple geometric shapes
- No dithering — flat, clean colors
- Transparent background (RGBA PNG)

## Artifact Pattern

Every generated asset produces three files:
```
<name>.prompt       — Generation prompt text
<name>.original.png — Raw AI concept (1024×1024)
<name>.png          — Production pixel art (target dimensions)
```

## Workspace

Work-in-progress images go to `.debug/art-workspace/` (gitignored). Only commit final `.png` files to `gol-project/assets/`.

```bash
# Generate to workspace (default)
node gol-tools/pixel-art/pixel-art.mjs pipeline \
  --prompt "A healing potion bottle" \
  --type item --backend gemini \
  --output .debug/art-workspace/potion

# After review, copy final to gol-project
cp .debug/art-workspace/potion.png gol-project/assets/sprites/items/potion.png
```

## Evaluation Protocol

When using the skill as an orchestrator:

1. Run `pipeline` command to generate + render
2. Use `look_at` tool on the rendered `.png` to visually inspect
3. Check: Does the sprite match the prompt intent? Is the silhouette readable? Does it fit GOL's muted aesthetic?
4. If rejected: regenerate with adjusted prompt
5. If accepted: move to final asset location in `gol-project/assets/`

## Sprite Sheet Assembly

For animated sprites:
```bash
# Generate individual frames
node gol-tools/pixel-art/pixel-art.mjs pipeline --prompt "Walking character frame 1" --type character --output /tmp/walk_01
node gol-tools/pixel-art/pixel-art.mjs pipeline --prompt "Walking character frame 2" --type character --output /tmp/walk_02
# ... repeat for all frames

# Assemble into strip
node gol-tools/pixel-art/pixel-art.mjs assemble \
  --frames /tmp/walk_01.png --frames /tmp/walk_02.png \
  --frames /tmp/walk_03.png --frames /tmp/walk_04.png \
  --direction horizontal \
  --output gol-project/assets/sprite_sheets/characters/new_walk.png
```

GOL animation conventions: idle=2 frames, walk=4 frames, death=22 frames.

## Color Palette

```
#111a24  #102e58  #11767f  #a02342  #83b5b5
#b0c2c2  #b68d7b  #a27b6b  #091018  #b8cccc
```

## Common Mistakes

- Forgetting `--type` flag (each asset type has different target dimensions)
- Using ComfyUI backend without local server running
- Not checking palette compliance after manual edits
- Placing assets in wrong directory (check `gol-project/assets/` structure)
- Generating animation frames with inconsistent prompts

## Resources

Art standards live in `docs/arts/` (single source of truth):
- `docs/arts/style-guide.md` — Color palette, aesthetic rules, animation conventions
- `docs/arts/asset-paths.md` — Where each asset type belongs in gol-project/
- `docs/arts/commit-convention.md` — Commit message format for art changes
- `docs/arts/prompts/` — Per-category prompt templates (character, enemy, box, tile, vfx, bullet, icon, item)

Update art standards by editing `docs/arts/` — no need to modify this skill.
