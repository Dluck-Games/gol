# UI Design System Spec — God of Lego

**Date:** 2026-05-05
**Status:** Approved
**Style:** Minimal Pixel 9-Patch + Post-Apocalyptic Warm Palette
**Reference:** Variant H concept (ChatGPT session `69f9bfce`)

## Overview

A complete UI design system for GOL that balances visual richness with minimal art asset requirements. The style sits between pure flat design and skeuomorphic — using only 5 tiny pixel sprites to give all UI components a cohesive, game-world-appropriate feel.

**Aesthetic keywords:** Post-apocalyptic urban, concrete bunker utility interface, warm minimalism, pixel beveled edges.

**Inspiration:** Into the Breach (information clarity), Metal Gear codec (corner cuts), GBA/SNES menu systems (9-patch pixel borders).

## 1. Color Palette

| Role | Hex | CSS Variable | Usage |
|------|-----|--------------|-------|
| Background | `#1f1f1f` | `--bg-primary` | Global/panel background |
| Background Alt | `#242420` | `--bg-secondary` | Nested panels, sub-areas |
| Border Dark | `#3a3a3a` | `--border` | Borders, separators |
| Text Disabled | `#5a5a5a` | `--text-disabled` | Disabled state, secondary text |
| Text Muted | `#8a8a8a` | `--text-muted` | Placeholder, decorative |
| Accent Primary (Rust) | `#c56a44` | `--accent-primary` | Primary buttons, highlights, selection |
| Accent Secondary (Oxide) | `#5e8a6e` | `--accent-secondary` | Success, checkmarks, positive actions |
| Accent Tertiary (Warning) | `#d4a843` | `--accent-tertiary` | Warnings, special prompts |
| Text Primary | `#e8e4df` | `--text-primary` | Body text (warm off-white) |
| Danger | `#8a3a3a` | `--danger` | Destructive actions, critical warnings |

**Palette notes:**
- Warm grays (not blue-tinted) — evokes concrete, not sci-fi
- Primary accent is rust/oxide orange — like rusted metal in sunlight
- Text is warm off-white, never clinical pure white
- All colors are desaturated/muted — no neon, no vibrant

## 2. Typography

### Font

- **Primary:** Chinese pixel bitmap font (CJK-compatible)
- **Fallback:** fusion-pixel-12px or similar pixel font
- **Rendering:** Nearest-neighbor filtering (no anti-aliasing)
- **Note:** Font must support full CJK character set for Chinese UI

### Scale

| Level | Size | Line Height | Usage | Example |
|-------|------|-------------|-------|---------|
| H1 | 24px | 32px | Menu titles, screen headers | "设置" |
| H2 | 20px | 28px | Section titles | "音频设置" |
| Body | 16px | 24px | Buttons, list items, content | "继续游戏" |
| Small | 12px | 16px | Tooltips, annotations, hints | "确认退出？" |

### Rules
- All font sizes are multiples of 4
- Never use font sizes between tiers (no 14px, no 18px)
- H1 color: `--text-primary`
- Body color: `--text-primary`
- Small color: `--text-muted` or `--text-primary` depending on importance

## 3. Spacing System

**Base unit: 4px**

All spacing values must be multiples of 4:

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4px | Tight spacing, icon gaps |
| `sm` | 8px | Compact element spacing |
| `md` | 16px | Standard padding, element gaps |
| `lg` | 24px | Section spacing |
| `xl` | 32px | Major section gaps |

### Application
- **Panel padding:** 16px (all sides)
- **Panel header height:** 28-32px
- **Button padding:** 8px vertical, 16px horizontal
- **Control spacing (between controls):** 8px (compact) / 16px (standard)
- **Section gaps:** 24px

## 4. Component Specifications

### 4.1 Button (Primary)

```
Height: 32px
Horizontal padding: 16px
Border: 1px pixel 9-patch (inner highlight top-left, shadow bottom-right)
Corner style: 2px diagonal cut (not rounded)
Text: Body size (16px), centered
Selection indicator: ▶ arrow left of text (when focused/active)
```

**States:**

| State | Background | Border | Text |
|-------|-----------|--------|------|
| Normal | `#2a2a25` (dark) | `#4a4a44` (muted) | `--text-primary` |
| Hover | `#3a3a34` (lighter) | `#c56a44` (rust orange) | `--text-primary` |
| Pressed | `#1a1a16` (darkest) | `#a05535` (dark rust) | `--text-primary` |
| Disabled | `#222220` | `#333330` | `--text-disabled` |
| Focused | `#2a2a25` | `#c56a44` (rust) | `--text-primary` |

**Design rationale:** Buttons are dark and subdued by default. The rust orange accent appears on hover/focus as the border highlight — drawing attention only when interacted with. This keeps the UI low-key and lets content breathe.

### 4.1b Button (Secondary / Outline)

```
Same dimensions as primary.
Background: transparent / #1f1f1f
Border: 1px #5a5a5a (muted gray)
Hover border: #8a8a8a (lighter gray)
Text: --text-muted (normal), --text-primary (hover)
```

Used for: cancel buttons, less important actions, dialog "No" buttons.

### 4.2 Panel / Container

```
Background: #242420
Border: 9-patch pixel border (1px with corner cuts)
Corner cut: 2px diagonal on all 4 corners
Header area: height 28px, background #1f1f1f, contains title text (Body size)
Content area: padding 16px all sides
```

**Panel hierarchy:**
- Level 0 (screen bg): `#1f1f1f`
- Level 1 (main panel): `#242420` with border
- Level 2 (nested): `#1f1f1f` with subtle border

### 4.3 Slider

```
Track: height 4px, color #3a3a3a, full width
Fill: height 4px, color #c56a44 (rust), from left to handle
Handle: 12x12 pixel diamond sprite, color #e8e4df
Value label: Small size (12px), right-aligned
```

### 4.4 Checkbox

```
Box: 12x12px, border 1px #5a5a5a
Unchecked: empty box
Checked: box filled with #5e8a6e + 8x8 check icon (white)
Disabled: box border #3a3a3a, check icon #5a5a5a
Label: Body size (16px), 8px gap from box
```

### 4.5 Toggle Switch

```
Track: 24x12px capsule, border-radius 6px
Off state: track #3a3a3a, handle left, handle #8a8a8a
On state: track #5e8a6e, handle right, handle #e8e4df
Handle: 10x10 circle
```

### 4.6 Tooltip

```
Background: #1f1f1f
Border: 1px solid #5a5a5a
Padding: 8px 12px
Max width: 200px
Title: Body size (16px), color #c56a44 (rust)
Description: Small size (12px), color #e8e4df
Pointer: 6px triangle (bottom-center or contextual)
```

### 4.7 Dropdown / Select

```
Trigger: Same style as secondary button, with ▼ indicator right
Menu: Panel style (Level 2), shadow-free
Items: Body size, 32px height each, 8px padding left
Hover item: background #3a3a3a
Selected item: text color #c56a44, ▶ indicator
```

### 4.8 Dialog / Confirmation Box

```
Overlay: #000000 at 50% opacity
Dialog panel: Level 1 panel style, centered
Title: H2 size (20px), centered
Body text: Body size (16px), centered or left-aligned
Button row: centered, 16px gap between buttons
Primary button: rust orange
Secondary button: outline style
```

## 5. Art Assets Required

Only 5 micro sprites power the entire design system:

| Asset | Size | Purpose |
|-------|------|---------|
| `ui_panel_9patch.png` | 16x16 | Panel/container borders (stretched via 9-patch) |
| `ui_button_9patch.png` | 16x16 | Button borders with highlight/shadow |
| `ui_cursor_arrow.png` | 8x8 | Selection indicator arrow |
| `ui_slider_handle.png` | 12x12 | Slider diamond handle |
| `ui_check_icon.png` | 8x8 | Checkbox checkmark |

**9-Patch details:**
- Center region: 1px fill color (tinted at runtime via `self_modulate`)
- Border region: 1px pixel beveled edge (light top-left, dark bottom-right)
- Corner cut: 2px diagonal on each corner

## 6. Implementation in Godot

### Theme Architecture (Config → Builder → Manager)

```
ThemeConfig (Resource)      ← Pure data: all design tokens as @export properties
    ↓
ThemeBuilder (static)       ← Converts ThemeConfig → Godot Theme object
    ↓
ThemeManager (RefCounted)   ← Runtime: applies theme to root, exposes config, signals changes
```

- `ThemeConfig` — `class_name ThemeConfig extends Resource`. Holds colors, sizes, textures, spacing, font. A "skin" is an instance of this.
- `ThemeWasteland` — Factory that creates the approved "Wasteland" ThemeConfig with all values from this spec.
- `ThemeBuilder` — Static class. `build(config) → Theme`. Uses StyleBoxTexture when textures provided, StyleBoxFlat as fallback.
- `ThemeManager` — Instantiated in `gol.gd`. `apply_theme(config)` sets root window theme + emits `theme_changed` signal.

### Key Technical Decisions

1. **StyleBoxTexture** for panels and buttons (9-patch stretching with `modulate_color` for state variants)
2. **StyleBoxFlat** as fallback and for simple fills (slider track, toggle track)
3. **`modulate_color`** on StyleBoxTexture for button state changes (one texture, multiple colors)
4. **4px grid** enforced in all Control node sizing
5. **Existing font** — `fusion-pixel-12px.otf` already supports CJK/Chinese characters; no new font needed
6. **Godot root theme cascade** — theme set on Window root automatically cascades to all Control nodes
7. **No `.tres` file** — theme built programmatically for flexibility (swap config = swap entire look)

### File Structure

```
scripts/ui/
├── theme_config.gd              # ThemeConfig resource class
├── theme_builder.gd             # Config → Theme converter
├── theme_manager.gd             # Runtime manager + signals
├── themes/
│   └── theme_wasteland.gd       # "Wasteland" skin factory
├── gol_theme.gd                 # DEPRECATED — backward-compat shim
├── viewmodels/                   # (unchanged)
└── views/                        # (unchanged — migrated to use theme cascade)

assets/
├── fonts/
│   └── fusion-pixel-12px.otf    # Existing pixel font (CJK-capable)
└── ui/
    └── sprites/
        ├── ui_panel_9patch.png
        ├── ui_button_9patch.png
        ├── ui_cursor_arrow.png
        ├── ui_slider_handle.png
        └── ui_check_icon.png
```

### Theme Switching (Future)

To add a new theme skin:
1. Create `scripts/ui/themes/theme_<name>.gd` with a `create() -> ThemeConfig` factory
2. Optionally add new texture sprites
3. Call `theme_manager.apply_theme(ThemeNewSkin.create())`
4. All UI updates automatically via Godot's theme cascade + `theme_changed` signal

## 7. Animation & Feedback Guidelines

| Interaction | Feedback | Duration |
|-------------|----------|----------|
| Button hover | Color shift (instant or 50ms tween) | 50ms |
| Button press | Color darken + 1px downward offset | Instant |
| Panel open | Fade in (alpha 0→1) | 150ms |
| Panel close | Fade out (alpha 1→0) | 100ms |
| Focus change | Arrow indicator slides to new position | 100ms |
| Toggle switch | Handle slides left↔right | 100ms |
| Tooltip appear | Fade in after 300ms hover delay | 100ms |

**Rules:**
- No bouncing, no elastic easing — linear or ease-out only
- Transitions are SHORT (50-150ms) — functional, not decorative
- Color changes can be instant (no tween needed for hover)

## 8. Accessibility Notes

- All interactive elements must have at least 32px hit area
- Text contrast ratio: primary text on bg-primary > 7:1
- Focus states always visible (arrow indicator + color change)
- Keyboard/gamepad navigation support for all menus
- No information conveyed by color alone (always paired with icon/text)

## Reference Images

Concept art stored in `gol-arts/artworks/ui-concepts/`:

| File | Description |
|------|-------------|
| `variant-h-minimal-9patch.png` | **SELECTED** — Final design direction |
| `variant-g-flat-postapoc.png` | Flat reference (same palette, no sprites) |
| `variant-d-urban-decay.png` | Mood/color reference (too textured) |
| `variant-f-flat-scifi.png` | Rejected — too cold/sci-fi |
| `variant-a-pixel-terminal.png` | Early exploration — pixel terminal style |

Full UI Art Bible: `docs/arts/ui-art-bible.md`

## Implementation Plan

See `.claude-internal/plans/calm-jumping-umbrella.md` for the full 22-step plan, or the summary below:

### Architecture: Config → Builder → Manager

```
ThemeConfig (Resource)     ← Data: colors, sizes, textures, spacing tokens
ThemeBuilder (static)      ← Logic: converts config → Godot Theme
ThemeManager (RefCounted)  ← Runtime: holds current config, applies to root, signals changes
```

### Phases

1. **Asset Creation** (5 pixel sprites via gol-tools/pixel-art pipeline)
2. **Theme Architecture** (ThemeConfig, ThemeWasteland, ThemeBuilder, ThemeManager)
3. **StyleBox Implementation** (9-patch panels/buttons, slider, checkbox)
4. **Menu & HUD Migration** (remove 44+ scattered overrides across 16 files)
5. **Testing & Verification** (unit tests + visual verification)

Phase 1 & 2 are independent (parallelizable). Phase 3 requires both. Phase 4→5 sequential.
