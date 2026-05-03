---
name: gol-pixel-art
description: "Production pixel art asset creation pipeline for God of Lego. Use this skill whenever creating pixel art sprites, generating game assets, producing character/enemy/tile/VFX sprites, designing pixel art for GOL, or converting AI-generated concepts into production-ready pixel art. Triggers: 'pixel art', 'create sprite', 'generate sprite', 'make game art', 'pixel art asset', 'create asset', 'game asset', 'sprite sheet', 'draw sprite', 'new sprite', 'art asset'."
---

# gol-pixel-art

AI-driven pipeline that generates concept art (GPT semi-manual / Gemini Nano Banana / ComfyUI) and produces production-ready pixel art through a normalize-first workflow. The default path is GPT semi-manual: the agent prepares an optimized prompt, the user generates/downloads the image in ChatGPT, then the agent continues with normalization. Automatic Gemini and ComfyUI paths remain available when requested.

## When to Use

- Creating new sprites (characters, enemies, items, tiles, VFX, bullets, icons, boxes)
- Converting AI-generated concept images into GOL-compatible pixel art
- Generating sprite sheets for animations
- Producing any visual asset for the GOL game

## Pipeline Overview

```
1. CHOOSE CONCEPT PATH — default GPT semi-manual; optional Gemini or ComfyUI automatic
2. CONCEPT — image saved to gol-arts/artworks/<name>.original.png
3. NORMALIZE — Downscale + palette map + Aseprite indexed → gol-arts/assets/<name>.aseprite
4. EVALUATE — Automated quality checks → PASS or FAIL
5. TOUCH-UP (if needed) — Human opens .aseprite, edits manually
6. EXPORT (user-invoked) — Export .aseprite to production PNG → gol-project/assets/
```

## Concept Path Choice

When this skill is triggered for art creation, ask the user which concept-generation path to use unless they already specified one. Use the interactive question tool when available. Present these choices in this order, with GPT semi-manual as the default/recommended option:

1. **GPT semi-manual (default)** — Agent prints an optimized prompt and ChatGPT link. User manually generates the image with their GPT Pro subscription, downloads it, and saves it to the target `gol-arts/artworks/<name>.original.png` path. This avoids API costs and browser automation.
2. **Gemini Nano Banana automatic** — Agent runs the Gemini backend (`--backend gemini`) using `GEMINI_API_KEY`. Use when the user wants a fully automatic cloud path.
3. **ComfyUI automatic** — Agent runs local ComfyUI (`--backend comfyui`) with the Sprites_64 LoRA. Use when the local server and model stack are ready.

If the user gives no preference, use GPT semi-manual. If the user says Gemini, Nano Banana, 纳米香蕉, 纳米橡胶, or automatic cloud generation, use `--backend gemini`. If the user says ComfyUI or local generation, use `--backend comfyui`.

## Source File Structure

```
gol-arts/
├── artworks/    # AI-generated images + prompts
│   ├── <name>.png
│   ├── <name>.prompt
│   └── <category>/   # Nested by game asset path
└── assets/      # Aseprite sources (mirrors gol-project/assets/)
    └── <type>/<name>.aseprite
```

Art source files are version-controlled in `gol-arts/` (Git LFS). Production PNGs are exported separately to `gol-project/assets/` via the explicit `export` command.

## Prerequisites

- **Aseprite**: `/Applications/Aseprite.app/Contents/MacOS/aseprite` (installed via DMG)
- **ComfyUI**: `/Applications/ComfyUI.app/` with Sprites_64.safetensors LoRA
- **GPT semi-manual backend**: GPT Pro subscription in ChatGPT; no API key required because the user generates/downloads the image manually
- **Gemini backend**: `GEMINI_API_KEY` env var (set in `.env` at project root). Get key: https://aistudio.google.com/apikey
- **ComfyUI backend**: Local ComfyUI server running at `http://127.0.0.1:8188` with SD 1.5 + Sprites_64 LoRA. Set `COMFYUI_URL` env var for custom address.

## Quick Start

```bash
# Step 1: Prepare GPT semi-manual concept prompt (default backend)
node gol-tools/pixel-art/pixel-art.mjs concept wood_box --type box --prompt "A weathered wooden supply crate"
# → prints ChatGPT instructions; user saves downloaded image to gol-arts/artworks/wood_box.original.png

# Automatic alternatives, only when requested:
node gol-tools/pixel-art/pixel-art.mjs concept wood_box --type box --prompt "A weathered wooden supply crate" --backend gemini
node gol-tools/pixel-art/pixel-art.mjs concept wood_box --type box --prompt "A weathered wooden supply crate" --backend comfyui

# Step 2: Normalize (downscale + palette map — produces .aseprite)
node gol-tools/pixel-art/pixel-art.mjs normalize wood_box --type box
# → saves gol-arts/assets/sprites/boxes/wood_box.aseprite + .preview.png

# Step 3: (Optional) Touch up in Aseprite
open gol-arts/assets/sprites/boxes/wood_box.aseprite

# Step 4: Export to game project (when ready)
node gol-tools/pixel-art/pixel-art.mjs export gol-arts/assets/sprites/boxes/wood_box.aseprite
# → exports to gol-project/assets/sprites/boxes/wood_box.png
```

## Normalize Command

`normalize` is the primary workflow. It takes a concept PNG and runs it through the simplified production pipeline: Python BOX downsample → Aseprite CIELAB palette mapping → indexed `.aseprite` output.

- **What it does:** Converts concept art into a production-ready indexed sprite, including automatic background removal for common AI-generated white, gray, or checkerboard backgrounds.
- **Options:** Use `--no-outline` to skip outline generation.
- **Output:** Writes `gol-arts/assets/<type>/NAME.aseprite` and `NAME.preview.png`.
- **Background removal:** Detects and removes AI-generated backgrounds automatically via corner-based flood fill before palette mapping.

## Export Command

Export an Aseprite file from gol-arts to the matched path in gol-project:

```bash
node gol-tools/pixel-art/pixel-art.mjs export gol-arts/assets/sprites/boxes/wood_box.aseprite
# → gol-project/assets/sprites/boxes/wood_box.png
```

The export command takes one argument: the path to an `.aseprite` file in `gol-arts/assets/`. It automatically mirrors the path to `gol-project/assets/` with `.png` extension. No other options.

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

Most sprites should go through `normalize` first. It usually produces 80-90% quality sprites automatically, and many assets will not need touch-ups at all. Only delegate to an `artistry` category subagent when evaluation fails or when a specific visual detail needs targeted adjustment on the normalized output:

```
task(
  category="artistry",
  load_skills=["gol-pixel-art"],
  run_in_background=false,
  description="Touch up [asset] pixel art",
  prompt="..."
)
```

The touch-up subagent should:
1. Inspect the normalized preview and evaluation result
2. Identify only the failing or weak areas that need adjustment
3. Write targeted JSON drawing instructions against the normalized `.aseprite` file
4. Apply via `draw apply`, preview via `look_at`, iterate until satisfied
5. Export final PNG via `draw export`

Touch-ups use the existing JSON ops workflow on top of normalized output rather than redrawing from scratch.

## Manual Drawing Workflow (Alternative)

This is the legacy approach for drawing from scratch in Aseprite. Keep it for cases where full manual creation is preferred, but use `normalize` by default.

For pixel-level control, use the `draw` commands:

```bash
# 1. Create a new sprite
node gol-tools/pixel-art/pixel-art.mjs create my_box --type box

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
node gol-tools/pixel-art/pixel-art.mjs apply my_box --instructions /tmp/ops.json

# 4. Inspect preview (agent uses look_at on .preview.png)
# 5. Iterate: write new ops.json, apply again
# 6. Export final
node gol-tools/pixel-art/pixel-art.mjs export gol-arts/assets/sprites/boxes/my_box.aseprite
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
node gol-tools/pixel-art/pixel-art.mjs concept crate --type box --prompt "A supply crate" --backend comfyui
```

Requires ComfyUI server running locally. Workflow template at `gol-tools/pixel-art/workflows/pixel_art_txt2img.json` — edit to change model, LoRA strength, or generation parameters.

## Sprite Sheet Assembly

For animated sprites:
```bash
# Generate individual frames
node gol-tools/pixel-art/pixel-art.mjs concept characters/walk_01 --type character --prompt "Walking character frame 1" --backend gemini
node gol-tools/pixel-art/pixel-art.mjs normalize characters/walk_01 --type character
node gol-tools/pixel-art/pixel-art.mjs export gol-arts/assets/characters/walk_01.aseprite

node gol-tools/pixel-art/pixel-art.mjs concept characters/walk_02 --type character --prompt "Walking character frame 2" --backend gemini
node gol-tools/pixel-art/pixel-art.mjs normalize characters/walk_02 --type character
node gol-tools/pixel-art/pixel-art.mjs export gol-arts/assets/characters/walk_02.aseprite
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
