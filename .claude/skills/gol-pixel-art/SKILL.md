---
name: gol-pixel-art
description: "Production pixel art asset creation pipeline for God of Lego. Use this skill whenever creating pixel art sprites, generating game assets, producing character/enemy/tile/VFX sprites, designing pixel art for GOL, or converting AI-generated concepts into production-ready pixel art. Triggers: 'pixel art', 'create sprite', 'generate sprite', 'make game art', 'pixel art asset', 'create asset', 'game asset', 'sprite sheet', 'draw sprite', 'new sprite', 'art asset'."
---

# gol-pixel-art

AI-driven pipeline that generates concept art (Gemini/ComfyUI) and produces production-ready pixel art through Aseprite drawing. Concept downscaling is not used, it produces blurry unusable results. Only Aseprite drawing produces usable art.

## When to Use

- Creating new sprites (characters, enemies, items, tiles, VFX, bullets, icons, boxes)
- Converting AI-generated concept images into GOL-compatible pixel art
- Generating sprite sheets for animations
- Producing any visual asset for the GOL game

## Pipeline Overview

```
1. GENERATE — AI creates concept image → .art-workspace/concepts/
2. CREATE — New indexed sprite with GOL palette → .art-workspace/aseprite/
3. DRAW — Agent draws pixel art referencing concept (artistry category subagent)
4. PREVIEW — Export preview, inspect via look_at, iterate
5. EXPORT — Final production PNG → .art-workspace/export/
6. COMMIT — Copy to gol-project/assets/, commit with art(category): message
```

## Workspace Structure

```
.art-workspace/
├── concepts/    # AI-generated concept images (Gemini/ComfyUI)
│   ├── <name>.prompt
│   └── <name>.original.png
├── aseprite/    # Aseprite source files (agent-edited)
│   ├── <name>.aseprite
│   └── <name>.preview.png
└── export/      # Final production PNGs
    └── <name>.png
```

Work-in-progress images go to `.art-workspace/` (gitignored). Only commit final `.png` files to `gol-project/assets/`.

## Prerequisites

- **Aseprite**: `/Applications/Aseprite.app/Contents/MacOS/aseprite` (installed via DMG)
- **ComfyUI**: `/Applications/ComfyUI.app/` with Sprites_64.safetensors LoRA
- **Gemini backend**: `GEMINI_API_KEY` env var (set in `.env` at project root). Get key: https://aistudio.google.com/apikey
- **ComfyUI backend**: Local ComfyUI server running at `http://127.0.0.1:8188` with SD 1.5 + Sprites_64 LoRA. Set `COMFYUI_URL` env var for custom address.

## Quick Start

```bash
# Generate concept
node gol-tools/pixel-art/pixel-art.mjs pipeline \
  --prompt "A weathered wooden supply crate" \
  --type box --backend gemini \
  --output .art-workspace/concepts/new_box

# Create sprite
node gol-tools/pixel-art/pixel-art.mjs draw create \
  --type box --output .art-workspace/aseprite/new_box

# Draw (agent writes JSON instructions referencing concept)
# ... draw apply ...

# Export final
node gol-tools/pixel-art/pixel-art.mjs draw export \
  --sprite .art-workspace/aseprite/new_box.aseprite \
  --output .art-workspace/export/new_box.png

# Evaluate
node gol-tools/pixel-art/pixel-art.mjs evaluate \
  --image .art-workspace/export/new_box.png --type box

# Commit to game
cp .art-workspace/export/new_box.png gol-project/assets/sprite_sheets/boxes/new_box.png
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

## Drawing Subagent

Pixel art drawing requires creative visual reasoning. Delegate to an `artistry` category subagent:

```
task(
  category="artistry",
  load_skills=["gol-pixel-art"],
  run_in_background=false,
  description="Draw [asset] pixel art",
  prompt="..."
)
```

The drawing subagent should:
1. Read the concept image via `look_at` tool
2. Plan the sprite composition (which colors, shapes, layers)
3. Write JSON drawing instructions
4. Apply via `draw apply`, preview via `look_at`, iterate until satisfied
5. Export final PNG via `draw export`

## Drawing Workflow (Aseprite)

For pixel-level control, use the `draw` commands:

```bash
# 1. Create a new sprite
node gol-tools/pixel-art/pixel-art.mjs draw create \
  --type box --output .art-workspace/aseprite/my_box

# 2. Write JSON instructions (agent generates this)
cat > /tmp/ops.json << 'EOF'
{"operations": [
  {"op": "clear", "color": 10},
  {"op": "rect", "x1": 4, "y1": 4, "x2": 27, "y2": 27, "color": 6, "filled": true},
  {"op": "rect", "x1": 4, "y1": 4, "x2": 27, "y2": 27, "color": 8, "filled": false},
  {"op": "line", "x1": 4, "y1": 15, "x2": 27, "y2": 15, "color": 7},
  {"op": "pixels", "data": [[8,8,2],[9,8,2],[8,9,2],[9,9,2]]}
]}
EOF

# 3. Apply instructions
node gol-tools/pixel-art/pixel-art.mjs draw apply \
  --sprite .art-workspace/aseprite/my_box.aseprite \
  --instructions /tmp/ops.json

# 4. Inspect preview (agent uses look_at on .preview.png)
# 5. Iterate: write new ops.json, apply again
# 6. Export final
node gol-tools/pixel-art/pixel-art.mjs draw export \
  --sprite .art-workspace/aseprite/my_box.aseprite \
  --output .art-workspace/export/my_box.png
```

### Drawing Operations

| Op | Fields | Description |
|----|--------|-------------|
| `pixel` | x, y, color | Single pixel |
| `rect` | x1, y1, x2, y2, color, filled | Rectangle |
| `line` | x1, y1, x2, y2, color | Line |
| `fill` | x, y, color | Flood fill |
| `clear` | color | Clear entire canvas |
| `layer_new` | name | Create new layer |
| `layer_select` | name | Switch active layer |
| `pixels` | data: [[x,y,color],...] | Batch pixels |

Colors are palette indices: 0-9 = GOL palette, 10 = transparent.

## ComfyUI Backend

Use local Stable Diffusion with the 2D Pixel Toolkit LoRA:

```bash
node gol-tools/pixel-art/pixel-art.mjs generate \
  --prompt "A supply crate" \
  --backend comfyui \
  --output .art-workspace/concepts/crate
```

Requires ComfyUI server running locally. Workflow template at `gol-tools/pixel-art/workflows/pixel_art_txt2img.json` — edit to change model, LoRA strength, or generation parameters.

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
