# Pipeline Guide

## Prerequisites

- `GEMINI_API_KEY` environment variable set (get from https://aistudio.google.com/apikey)
- `uv` installed (Python package manager)
- Node.js 18+ installed

## Step-by-Step Pipeline

### Step 1: Generate Concept

```bash
node gol-tools/pixel-art/pixel-art.mjs generate \
  --prompt "Description of the asset" \
  --backend gemini \
  --output path/to/asset_name
```

This creates:
- `path/to/asset_name.prompt` — the full prompt text
- `path/to/asset_name.original.png` — 1024×1024 concept image

### Step 2: Render to Pixel Art

```bash
node gol-tools/pixel-art/pixel-art.mjs render \
  --input path/to/asset_name.original.png \
  --type box \
  --output path/to/asset_name.png
```

Options:
- `--type`: Asset type determines target dimensions
- `--outline`: Add 1px dark outline around the sprite

### Step 3: Evaluate Quality

```bash
node gol-tools/pixel-art/pixel-art.mjs evaluate \
  --image path/to/asset_name.png \
  --type box
```

Checks:
- ✓ Dimensions match asset type
- ✓ ≥90% palette compliance
- ✓ ≤10 unique colors
- ✓ 15-85% silhouette fill ratio
- ✓ No semi-transparent pixels

### Step 4: Assemble (Animation Only)

```bash
node gol-tools/pixel-art/pixel-art.mjs assemble \
  --frames frame_01.png --frames frame_02.png \
  --direction horizontal \
  --output sprite_sheet.png
```

### Full Pipeline (Automated)

```bash
node gol-tools/pixel-art/pixel-art.mjs pipeline \
  --prompt "Description" \
  --type box \
  --backend gemini \
  --output path/to/asset_name \
  --max-attempts 3
```

Runs generate → render → evaluate in sequence.

## Configuration Inspection

```bash
# View palette
node gol-tools/pixel-art/pixel-art.mjs config palette

# View dimensions for a type
node gol-tools/pixel-art/pixel-art.mjs config dimensions box

# List all asset types
node gol-tools/pixel-art/pixel-art.mjs config types
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "GEMINI_API_KEY not set" | Export the env var: `export GEMINI_API_KEY=your_key` |
| "ComfyUI not implemented" | Use `--backend gemini` (ComfyUI support coming later) |
| Palette compliance < 90% | Re-render or adjust prompt for simpler colors |
| Silhouette too sparse/dense | Adjust prompt: "larger subject" or "more negative space" |
| Wrong dimensions | Check `--type` flag matches intended asset type |
| Semi-transparent pixels | Re-render; the pipeline should clean these automatically |

## File Placement Guide

After generating and approving an asset, place it in the correct directory:

| Asset Type | Target Directory |
|------------|-----------------|
| character sprite | `gol-project/assets/sprites/characters/` |
| character sheet | `gol-project/assets/sprite_sheets/characters/` |
| enemy sprite | `gol-project/assets/sprites/enemies/` |
| enemy sheet | `gol-project/assets/sprite_sheets/enemies/` |
| box/container | `gol-project/assets/sprite_sheets/boxes/` |
| tile | `gol-project/assets/tiles/<type>/` |
| vfx | `gol-project/assets/sprite_sheets/vfx/` |
| bullet | `gol-project/assets/sprites/bullets/` |
| icon | `gol-project/assets/icons/` |
| item | `gol-project/assets/sprites/items/` |
