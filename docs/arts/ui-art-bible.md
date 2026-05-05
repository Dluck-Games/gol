# GOL UI Art Bible

## Overview

This document defines the visual language for all UI elements in God of Lego. It serves as the single source of truth for UI appearance — both for implementation (code) and asset creation (pixel art).

**Style:** Minimal Pixel 9-Patch — a middle ground between pure flat and skeuomorphic. Only 5 micro pixel sprites power the entire design system.

**Mood:** Post-apocalyptic urban. A clean utility interface inside a concrete bunker. Warm, utilitarian, grounded. Not sci-fi, not fantasy — earthy and functional.

## Visual References

Concept exploration produced 8 variants. The final selected direction is **Variant H**.

| Variant | Style | File |
|---------|-------|------|
| A | Pixel terminal (dark, teal accent) | `gol-arts/artworks/ui-concepts/variant-a-pixel-terminal.png` |
| D | Urban decay (textured, warm grays) | `gol-arts/artworks/ui-concepts/variant-d-urban-decay.png` |
| F | Pure flat (sci-fi, cold teal) | `gol-arts/artworks/ui-concepts/variant-f-flat-scifi.png` |
| G | Flat + post-apocalyptic palette | `gol-arts/artworks/ui-concepts/variant-g-flat-postapoc.png` |
| **H** | **Minimal 9-patch + post-apoc (SELECTED)** | `gol-arts/artworks/ui-concepts/variant-h-minimal-9patch.png` |

**Key design references:**
- Into the Breach — information clarity, typographic hierarchy
- Metal Gear Solid codec — corner cuts, panel framing
- GBA/SNES RPG menus — 9-patch pixel borders, selection arrows

## UI Color Palette

The UI palette is **separate** from the sprite palette (defined in `style-guide.md`). UI colors are optimized for readability and contrast on dark backgrounds.

| Role | Hex | Godot Color | Usage |
|------|-----|-------------|-------|
| BG Primary | `#1f1f1f` | `Color(0.122, 0.122, 0.122)` | Screen/panel backgrounds |
| BG Secondary | `#242420` | `Color(0.141, 0.141, 0.125)` | Nested panels, sub-areas |
| Border | `#3a3a3a` | `Color(0.227, 0.227, 0.227)` | Borders, dividers |
| Disabled | `#5a5a5a` | `Color(0.353, 0.353, 0.353)` | Disabled states |
| Muted | `#8a8a8a` | `Color(0.541, 0.541, 0.541)` | Placeholders, annotations |
| Rust (Primary) | `#c56a44` | `Color(0.773, 0.416, 0.267)` | Primary buttons, focus |
| Oxide (Secondary) | `#5e8a6e` | `Color(0.369, 0.541, 0.431)` | Success, checkmarks |
| Warning | `#d4a843` | `Color(0.831, 0.659, 0.263)` | Warnings, caution |
| Text | `#e8e4df` | `Color(0.910, 0.894, 0.875)` | Body text (warm off-white) |
| Danger | `#8a3a3a` | `Color(0.541, 0.227, 0.227)` | Destructive actions |

### Palette Rules

- **Warm grays only** — never blue-tinted. These are concrete, not steel.
- **Rust orange is the hero color** — used for anything interactive/focused.
- **Green = positive completion** — checkmarks, success states.
- **Text is NEVER pure white** — always warm off-white `#e8e4df`.
- **Dark background NEVER pure black** — always slightly warm `#1f1f1f`.

### Do's and Don'ts

| ✅ Do | ❌ Don't |
|-------|---------|
| Use rust orange for primary actions | Use bright/saturated colors |
| Keep text warm off-white | Use pure white (#ffffff) for text |
| Use color to indicate state (hover/focus) | Use glow, shadow, or bloom effects |
| Apply color sparingly — most is gray | Make everything colorful |
| Use warm dark backgrounds | Use cold blue-black backgrounds |

## Typography

### Font Requirements

- **Type:** Pixel bitmap font with full CJK (Chinese) support
- **Rendering:** Nearest-neighbor, antialiasing = OFF
- **Format:** BitmapFont (.fnt) or DynamicFont with pixel snapping

### Size Scale (4px-multiple grid)

| Level | Size | Line Height | Weight | Usage |
|-------|------|-------------|--------|-------|
| H1 | 24px | 32px | Regular | Screen titles: "设置" |
| H2 | 20px | 28px | Regular | Section headers: "音频设置" |
| Body | 16px | 24px | Regular | Buttons, lists: "继续游戏" |
| Small | 12px | 16px | Regular | Tips, annotations: "确认退出？" |

### Typography Rules

- All sizes must be multiples of 4
- No intermediate sizes (no 14px, 18px)
- Chinese characters must remain legible at 12px minimum
- Single font family across entire UI — no mixing
- Color follows role: H1 = Text, Body = Text, Small = Muted (context-dependent)

## Component Visual Specs

### Buttons

```
┌─────────────────────┐
│▸ 继续游戏            │  ← Selection arrow + text (centered)
└─────────────────────┘
  Height: 32px
  H-padding: 16px
  Border: 9-patch with pixel bevel (1px highlight top-left, 1px shadow bottom-right)
  Corners: 2px diagonal cut (not rounded)
```

**States (color only — shape doesn't change):**

| State | Fill | Border Highlight | Text |
|-------|------|-----------------|------|
| Normal | `#c56a44` | Light rust | Warm white |
| Hover | `#d4784a` | Brighter | Warm white |
| Pressed | `#a55a38` | Darker | Warm white |
| Disabled | `#5a5a5a` | Dark gray | `#8a8a8a` |

### Panels

```
╔══ 面板标题 ═══════╗  ← Header: 28px, bg #1f1f1f, corner cuts
║                    ║
║   Content area     ║  ← Body: bg #242420, padding 16px all sides
║   内容区域示例     ║
║                    ║
╚════════════════════╝
  Border: 9-patch pixel frame (1px with 2px corner cuts)
  Levels: bg-primary (L0) → bg-secondary (L1) → bg-primary (L2 nested)
```

### Slider

```
  音量 ████████████████○─────── 65%
       ├── Filled (#c56a44) ──┤├─ Track (#3a3a3a) ─┤
  Track height: 4px
  Handle: 12x12 pixel diamond sprite
  Value label: Small text, right-aligned
```

### Checkbox & Toggle

```
  Checkbox:                    Toggle:
  □ 未选中                     ○──── 关闭 (track: #3a3a3a)
  ☑ 已选中 (#5e8a6e + check)  ────○ 开启 (track: #5e8a6e)
  ☑ 禁用   (#5a5a5a + check)

  Checkbox box: 12x12, 1px border
  Toggle track: 24x12 capsule
  Toggle handle: 10x10 circle
```

### Tooltip

```
  ┌────────────────────────┐
  │ 废弃药箱                │  ← Title: Body 16px, color Rust
  │ 打开后可获得少量补给。  │  ← Desc: Small 12px, color Text
  └──────────▽─────────────┘  ← 6px triangle pointer
  Background: #1f1f1f, border: 1px #5a5a5a
  Padding: 8px 12px, max-width: 200px
```

## Required Art Assets

The entire UI design system requires only **5 micro pixel sprites**:

| Asset | Dimensions | Description | File |
|-------|-----------|-------------|------|
| Panel 9-patch | 16×16 | Beveled border with 2px corner cuts | `ui_panel_9patch.png` |
| Button 9-patch | 16×16 | Highlight top-left, shadow bottom-right | `ui_button_9patch.png` |
| Cursor arrow | 8×8 | Selection indicator (▶ pixel arrow) | `ui_cursor_arrow.png` |
| Slider handle | 12×12 | Diamond/rhombus shape | `ui_slider_handle.png` |
| Check icon | 8×8 | Simple checkmark | `ui_check_icon.png` |

### 9-Patch Structure

```
  Corner (fixed) │ Edge (stretch H) │ Corner (fixed)
  ───────────────┼──────────────────┼───────────────
  Edge (stretch V)│ Center (stretch) │ Edge (stretch V)
  ───────────────┼──────────────────┼───────────────
  Corner (fixed) │ Edge (stretch H) │ Corner (fixed)

  - Margins: 4px on each side (for a 16x16 source)
  - Center: 8x8 (fills with tint color at runtime via self_modulate)
  - Corners: 2px diagonal cut
  - Edges: 1px bevel (light top/left, dark bottom/right)
```

### Asset Placement

```
gol-project/assets/ui/sprites/
├── ui_panel_9patch.png
├── ui_button_9patch.png
├── ui_cursor_arrow.png
├── ui_slider_handle.png
└── ui_check_icon.png
```

Source Aseprite files go to:
```
gol-arts/assets/ui/
├── ui_panel_9patch.aseprite
├── ui_button_9patch.aseprite
├── ui_cursor_arrow.aseprite
├── ui_slider_handle.aseprite
└── ui_check_icon.aseprite
```

## Spacing & Grid

**Base unit: 4px** — all dimensions, margins, padding must be multiples of 4.

| Token | Value | Use |
|-------|-------|-----|
| xs | 4px | Icon gaps, tight spacing |
| sm | 8px | Compact elements |
| md | 16px | Standard padding |
| lg | 24px | Section spacing |
| xl | 32px | Major gaps |

## Animation & Transitions

| Action | Effect | Duration | Easing |
|--------|--------|----------|--------|
| Hover | Color shift | 50ms | Linear |
| Press | Darken + 1px down | Instant | — |
| Focus move | Arrow slides | 100ms | Ease-out |
| Panel open | Fade alpha 0→1 | 150ms | Ease-out |
| Panel close | Fade alpha 1→0 | 100ms | Linear |
| Toggle | Handle slides | 100ms | Ease-out |
| Tooltip show | Fade in (300ms delay) | 100ms | Ease-out |

### Animation Rules

- **No bounce, no elastic** — linear or ease-out only
- **Short durations** (50-150ms) — functional, not decorative
- **No particle effects** on UI elements
- **Hover = instant or near-instant** — the user should never wait

## Accessibility

- Minimum hit area: 32×32px for all interactive elements
- Focus always visible: arrow indicator + color change
- No color-only information — always paired with icon or text
- Support keyboard/gamepad navigation in all menus
- Text contrast: primary text on bg-primary ≥ 7:1

## Relationship to Sprite Palette

The UI palette (`docs/arts/ui-art-bible.md`) and sprite palette (`docs/arts/style-guide.md`) are **independent**:

- Sprite palette: 10 muted colors for game-world art
- UI palette: 10 warm-gray colors for interface elements
- They may overlap in spirit (both desaturated/muted) but are not required to share exact hex values
- UI overlays the game world — contrast between UI and sprites is intentional
