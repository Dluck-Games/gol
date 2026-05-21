# Handoff: Pixel Art Pipeline Redesign — Python Drawing Functions

Date: 2026-04-23
Session focus: Built complete pixel art pipeline (Gemini/ComfyUI → Aseprite → export), now redesigning drawing approach from JSON ops to Python drawing functions for quality.

## User Requests (Verbatim)

- "design me a skill to draw production useable skill with create pixel art of our game"
- "if gemini is avaliable, generate the concept 2d asset image, or we can use comfy UI run local LoRA models, then use subagent to evaluate it if it's ok for our style or purpose, once it's accepted, we use a subagent to read the image, then draw really asset png file with cli tool"
- "change tools to strictly follow this path rule. don't let agent can decide the path themself. simplify tools."
- "the quality still bad at second shot. keep optimization."
- "you might need to search internet, to find a really artist prompt to do this work. find solution on github. keep optimize."
- User chose "Python drawing functions (Recommended)" for the redesign

## Goal

Redesign the pixel art drawing pipeline: instead of agents writing JSON drawing commands for Aseprite, agents write Python drawing functions using Pillow that render sprites pixel-by-pixel, then import into Aseprite for indexed palette enforcement and .aseprite export.

## Work Completed

### Phase 1: Full Pipeline Built (5 commits in gol-tools)
- `gol-tools/pixel-art/` — Complete Python CLI tool with Node.js shim
- Gemini backend: generates 1024×1024 concept images (working, tested E2E)
- ComfyUI backend: real HTTP client with SD 1.5 + Sprites_64 LoRA workflow
- Aseprite drawing backend: Lua executor, JSON ops, batch mode
- Renderer: downscale + palette quantize (deprecated — produces blurry results)
- Evaluator: dimensions, palette compliance, silhouette, alpha checks
- Assembler: sprite sheet strip assembly
- 74 pytest tests passing

### Phase 2: Ecosystem Enhancement
- `docs/arts/` — Art standards SSOT (style guide, asset paths, commit convention, 8 prompt templates)
- `.env` + `.env.example` for GEMINI_API_KEY
- 3 hooks: block .original.png in gol-project, block .env commits, validate art placement
- `.claude/skills/gol-pixel-art/SKILL.md` — Full skill with workflow docs

### Phase 3: Strict Paths + Workspace
- `.art-workspace/{concepts,aseprite,export}/` — strict workspace structure (gitignored)
- CLI commands take `--name` only, paths auto-resolve via `config.py` functions
- Aseprite installed via DMG at `/Applications/Aseprite.app/Contents/MacOS/aseprite` v1.3.17.1
- ComfyUI installed at `/Applications/ComfyUI.app/`
- LoRA model at `ComfyUI/models/loras/Sprites_64.safetensors`
- Fixed Aseprite `--script-param` must come BEFORE `--script`
- Fixed evaluator P-mode → RGBA conversion for indexed palette PNGs

### Phase 4: Quality Investigation
- Tested drawing with artistry subagent 3 times — results consistently mediocre
- JSON ops approach produces mechanical, repetitive sprites (flat fills, no character)
- Researched alternatives: found `claude-fairy-pixel-art`, `pixel-plugin`, `pixel-mcp`, `yoyopixel`, `SpriteCook`, `PixelLab`
- Key insight from `dbinky/claude-fairy-pixel-art`: Claude writes Python drawing FUNCTIONS, not JSON commands
- Oracle consultation: multi-phase prompt (analyze → plan → block-in → refine → QC) with 3 passes
- Created `references/drawing-prompt-template.md` with Oracle's recommended prompt structure

## Current State

- All code committed and pushed (gol-tools + gol parent)
- 74 tests passing
- E2E pipeline works: `concept test_crate` → `create test_crate` → `apply test_crate` → `export test_crate` → `evaluate test_crate` = PASS
- But drawing QUALITY is not production-ready — the JSON ops approach is fundamentally limited
- User approved redesign to Python drawing functions approach

## Pending Tasks

### The Redesign: Python Drawing Functions

Based on `claude-fairy-pixel-art` pattern, implement:

1. **Drawing primitives module** (`pixel_art/draw_lib.py`):
   - `px(img, x, y, color_name)` — set pixel by palette name
   - `fill_rect(img, x1, y1, x2, y2, color_name)` — filled rectangle
   - `outline_rect(img, x1, y1, x2, y2, color_name)` — rectangle outline
   - `draw_line(img, x1, y1, x2, y2, color_name)` — Bresenham's line
   - `draw_ellipse(img, cx, cy, rx, ry, color_name)` — ellipse
   - `scatter_pixels(img, region, color_name, density, seed)` — seeded random scatter
   - `mirror_h(img)` — horizontal mirror
   - Named palette: `'wood'`, `'wood_shadow'`, `'outline'`, `'highlight'`, etc.

2. **New CLI command** (`draw-script`):
   - Agent writes a Python file with a `draw(img, palette)` function
   - CLI executes it, renders to PNG via Pillow
   - Then imports into Aseprite for indexed palette enforcement
   - Output: `.art-workspace/aseprite/<name>.aseprite` + `.art-workspace/export/<name>.png`

3. **Updated skill prompt template**:
   - Agent writes a complete Python drawing function, not JSON ops
   - Function uses named palette colors and drawing primitives
   - Iterative: agent can read the function, adjust, re-run
   - Deterministic: same function = same output

4. **Keep existing JSON ops** as fallback for simple edits (touch-ups on existing sprites)

### Key Design Decision: Python Functions vs JSON Ops

| Aspect | JSON Ops (current) | Python Functions (new) |
|--------|-------------------|----------------------|
| Expressiveness | Limited (pixel, rect, line, fill) | Full (loops, math, conditionals) |
| Quality | Mechanical, repetitive | Artistic, intentional |
| Iteration | Edit JSON, re-apply | Edit function, re-run |
| Determinism | Yes | Yes (with seeded random) |
| Agent skill | Writing abstract instructions | Writing code (Claude's strength) |
| Proven at scale | No | Yes (163 sprites, claude-fairy-pixel-art) |

## Key Files

- `gol-tools/pixel-art/pixel_art/cli.py` — CLI entry point (will add `draw-script` command)
- `gol-tools/pixel-art/pixel_art/config.py` — Palette, dimensions, workspace path resolution
- `gol-tools/pixel-art/pixel_art/aseprite_backend.py` — Aseprite CLI driver
- `gol-tools/pixel-art/pixel_art/gemini_backend.py` — Gemini concept generation
- `gol-tools/pixel-art/pixel_art/comfyui_backend.py` — ComfyUI generation
- `gol-tools/pixel-art/pixel_art/evaluator.py` — Quality checks
- `.claude/skills/gol-pixel-art/SKILL.md` — Skill definition
- `.claude/skills/gol-pixel-art/references/drawing-prompt-template.md` — Drawing prompt template
- `docs/arts/` — Art standards SSOT (style guide, asset paths, prompts)

## Important Decisions

- **Python drawing functions over JSON ops** — Claude is better at writing code that draws than abstract drawing instructions. Proven by claude-fairy-pixel-art (163 sprites).
- **Aseprite for palette enforcement only** — Creative drawing in Pillow, palette indexing in Aseprite. Aseprite's Lua JSON ops are too limited for artistic work.
- **Strict workspace paths** — Agents cannot choose output paths. `concept_path(name)`, `sprite_path(name)`, `export_path(name)` resolve automatically.
- **artistry category for drawing subagent** — Drawing requires creative visual reasoning, not just code execution.
- **Concept images are references only** — Direct downscaling produces blurry unusable results. All final art must be drawn pixel-by-pixel.
- **3-pass iterative workflow** (from Oracle): block-in → volume/material → cleanup/QC

## Constraints

- 32×32 canvas (most asset types), 12×12 bullets, 16×16 icons
- 10-color indexed GOL palette (no RGB freedom)
- Aseprite v1.3.17.1 at `/Applications/Aseprite.app/Contents/MacOS/aseprite`
- ComfyUI at `/Applications/ComfyUI.app/` with Sprites_64 LoRA
- GEMINI_API_KEY in `.env`
- Front-facing sprites (not isometric) — GOL uses top-down/front-facing perspective
- Sprites must fill 70-90% of canvas

## Context for Continuation

- The `claude-fairy-pixel-art` repo at https://github.com/dbinky/claude-fairy-pixel-art is the reference implementation. Study its `generate-art.py` (2700 lines) for the drawing primitives pattern.
- The existing JSON ops + Aseprite Lua executor still works and should be kept as a fallback for simple edits.
- The new `draw_lib.py` module should provide named-palette drawing primitives that match GOL's 10 colors.
- The artistry subagent prompt needs to instruct the agent to write a Python `draw()` function, not JSON ops.
- Also consider: `pixel-plugin` (willibrandon/pixel-plugin) uses an MCP server with 40+ Aseprite tools — could be useful as additional reference.
- Also consider: `yoyopixel` teaches LLMs to generate pixel art as HTML/CSS — interesting but not directly applicable.

---

To continue: open a new session and paste this file's content as the first message, then say "implement the Python drawing functions redesign".
