# UI Design System Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing cold-blue flat UI with a post-apocalyptic warm-gray design system featuring 9-patch pixel borders, theme-switching architecture, and unified design tokens — visible in-game immediately after completion.

**Architecture:** Config → Builder → Manager pattern. `ThemeConfig` (Resource) holds all design tokens. `ThemeBuilder` (static) converts config into a Godot Theme. `ThemeManager` (RefCounted) applies themes at runtime and signals changes. A backward-compat shim keeps existing `GOLTheme` references working during migration.

**Tech Stack:** Godot 4.6, GDScript, StyleBoxTexture (9-patch), StyleBoxFlat (fallback), pixel-art pipeline (gol-tools/pixel-art) for asset creation.

**Spec:** `docs/superpowers/specs/2026-05-05-ui-design-system-design.md`
**Art Bible:** `docs/arts/ui-art-bible.md`
**Concept Reference:** `gol-arts/artworks/ui-concepts/variant-h-minimal-9patch.png`

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `assets/ui/sprites/ui_panel_9patch.png` | 16×16 panel border texture |
| `assets/ui/sprites/ui_button_9patch.png` | 16×16 button border texture |
| `assets/ui/sprites/ui_cursor_arrow.png` | 8×8 selection arrow |
| `assets/ui/sprites/ui_slider_handle.png` | 12×12 slider grabber |
| `assets/ui/sprites/ui_check_icon.png` | 8×8 checkmark |
| `scripts/ui/theme_config.gd` | ThemeConfig Resource — design token data |
| `scripts/ui/theme_builder.gd` | Converts ThemeConfig → Godot Theme |
| `scripts/ui/theme_manager.gd` | Runtime theme application + signals |
| `scripts/ui/themes/theme_wasteland.gd` | "Wasteland" skin factory |
| `tests/unit/ui/test_theme_config.gd` | ThemeConfig tests |
| `tests/unit/ui/test_theme_builder.gd` | ThemeBuilder tests |

### Modified Files

| File | Change |
|------|--------|
| `scripts/gol.gd` | Use ThemeManager instead of direct GOLTheme call |
| `scripts/ui/gol_theme.gd` | Deprecate → thin forwarding shim |
| `scenes/ui/menus/title_screen.tscn` | Remove scattered theme overrides |
| `scenes/ui/menus/pause_menu.tscn` | Remove scattered theme overrides |
| `scenes/ui/menus/settings_menu.tscn` | Remove scattered theme overrides |
| `scenes/ui/menus/game_over.tscn` | Remove LabelSettings + overrides |
| `scenes/ui/menus/confirm_dialog.tscn` | Remove separation overrides |
| `scenes/ui/hud.tscn` | Remove color/font overrides |
| `scripts/ui/views/menu/view_settings_menu.gd` | Use forwarded constants |
| `scripts/ui/views/menu/view_build_hotbar.gd` | Use theme palette colors |
| `scripts/ui/views/view_hp_bar.gd` | Use theme palette colors |
| `scripts/ui/views/view_speech_bubble.gd` | Use theme palette colors |
| `tests/unit/ui/test_gol_theme.gd` | Update for new architecture |

---

## Task 1: Create UI Sprite Assets

**Files:**
- Create: `assets/ui/sprites/ui_panel_9patch.png`
- Create: `assets/ui/sprites/ui_button_9patch.png`
- Create: `assets/ui/sprites/ui_cursor_arrow.png`
- Create: `assets/ui/sprites/ui_slider_handle.png`
- Create: `assets/ui/sprites/ui_check_icon.png`
- Create: `gol-arts/assets/ui/` (Aseprite sources)

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p gol-project/assets/ui/sprites
mkdir -p gol-arts/assets/ui
```

- [ ] **Step 2: Create panel 9-patch (16×16) using pixel-art pipeline**

Use the `gol-pixel-art` skill or the pixel-art CLI. The sprite needs:
- 4px margins on each side (8×8 stretchable center)
- Border: 1px `#3a3a3a` outline
- Inner bevel: top/left 1px `#2e2e28`, bottom/right 1px `#1a1a16`
- Fill: `#242420`
- Corner cuts: 2px diagonal (transparent at each corner)

If the pipeline's fixed 10-color palette can't match these exact hex values, create the PNG directly using Python/Pillow:

```python
from PIL import Image
img = Image.new('RGBA', (16, 16), (0, 0, 0, 0))
# Border (#3a3a3a)
for i in range(16):
    for j in range(16):
        if i == 0 or i == 15 or j == 0 or j == 15:
            img.putpixel((i, j), (0x3a, 0x3a, 0x3a, 255))
# Inner bevel - top/left highlight (#2e2e28)
for i in range(1, 15):
    img.putpixel((i, 1), (0x2e, 0x2e, 0x28, 255))
    img.putpixel((1, i), (0x2e, 0x2e, 0x28, 255))
# Inner bevel - bottom/right shadow (#1a1a16)
for i in range(1, 15):
    img.putpixel((i, 14), (0x1a, 0x1a, 0x16, 255))
    img.putpixel((14, i), (0x1a, 0x1a, 0x16, 255))
# Fill center (#242420)
for i in range(2, 14):
    for j in range(2, 14):
        img.putpixel((i, j), (0x24, 0x24, 0x20, 255))
# Corner cuts (transparent) - 2px diagonal at each corner
for offset in range(2):
    img.putpixel((offset, 0), (0, 0, 0, 0))
    img.putpixel((0, offset), (0, 0, 0, 0))
    img.putpixel((15 - offset, 0), (0, 0, 0, 0))
    img.putpixel((15, offset), (0, 0, 0, 0))
    img.putpixel((offset, 15), (0, 0, 0, 0))
    img.putpixel((0, 15 - offset), (0, 0, 0, 0))
    img.putpixel((15 - offset, 15), (0, 0, 0, 0))
    img.putpixel((15, 15 - offset), (0, 0, 0, 0))
img.save('gol-project/assets/ui/sprites/ui_panel_9patch.png')
```

- [ ] **Step 3: Create button 9-patch (16×16)**

Similar to panel but with more contrast for the raised appearance:
- Border: 1px `#4a4a44`
- Top/left highlight: 1px `#3a3a34`
- Bottom/right shadow: 1px `#1a1a16`
- Fill: `#2a2a25`
- Same 2px corner cuts

```python
from PIL import Image
img = Image.new('RGBA', (16, 16), (0, 0, 0, 0))
# Border (#4a4a44)
for i in range(16):
    for j in range(16):
        if i == 0 or i == 15 or j == 0 or j == 15:
            img.putpixel((i, j), (0x4a, 0x4a, 0x44, 255))
# Top/left highlight (#3a3a34)
for i in range(1, 15):
    img.putpixel((i, 1), (0x3a, 0x3a, 0x34, 255))
    img.putpixel((1, i), (0x3a, 0x3a, 0x34, 255))
# Bottom/right shadow (#1a1a16)
for i in range(1, 15):
    img.putpixel((i, 14), (0x1a, 0x1a, 0x16, 255))
    img.putpixel((14, i), (0x1a, 0x1a, 0x16, 255))
# Fill center (#2a2a25)
for i in range(2, 14):
    for j in range(2, 14):
        img.putpixel((i, j), (0x2a, 0x2a, 0x25, 255))
# Corner cuts (same as panel)
for offset in range(2):
    img.putpixel((offset, 0), (0, 0, 0, 0))
    img.putpixel((0, offset), (0, 0, 0, 0))
    img.putpixel((15 - offset, 0), (0, 0, 0, 0))
    img.putpixel((15, offset), (0, 0, 0, 0))
    img.putpixel((offset, 15), (0, 0, 0, 0))
    img.putpixel((0, 15 - offset), (0, 0, 0, 0))
    img.putpixel((15 - offset, 15), (0, 0, 0, 0))
    img.putpixel((15, 15 - offset), (0, 0, 0, 0))
img.save('gol-project/assets/ui/sprites/ui_button_9patch.png')
```

- [ ] **Step 4: Create cursor arrow (8×8)**

A ▶ selection arrow pointing right, filled with rust orange `#c56a44`, 1px dark outline `#1f1f1f`:

```python
from PIL import Image
img = Image.new('RGBA', (8, 8), (0, 0, 0, 0))
# Arrow shape (pointing right): rows from top
# Row 0:   X . . . . . . .
# Row 1:   X X . . . . . .
# Row 2:   X X X . . . . .
# Row 3:   X X X X . . . .
# Row 4:   X X X X . . . .
# Row 5:   X X X . . . . .
# Row 6:   X X . . . . . .
# Row 7:   X . . . . . . .
arrow_pixels = [
    (0,0),(1,0),
    (0,1),(1,1),(2,1),
    (0,2),(1,2),(2,2),(3,2),
    (0,3),(1,3),(2,3),(3,3),(4,3),
    (0,4),(1,4),(2,4),(3,4),(4,4),
    (0,5),(1,5),(2,5),(3,5),
    (0,6),(1,6),(2,6),
    (0,7),(1,7),
]
outline = (0x1f, 0x1f, 0x1f, 255)
fill = (0xc5, 0x6a, 0x44, 255)
# Draw outline first (1px border around arrow shape)
for x, y in arrow_pixels:
    img.putpixel((x, y), fill)
# Simple outline: darken edge pixels (left column and tips)
img.putpixel((0, 0), outline)
img.putpixel((0, 7), outline)
img.putpixel((4, 3), outline)
img.putpixel((4, 4), outline)
img.save('gol-project/assets/ui/sprites/ui_cursor_arrow.png')
```

- [ ] **Step 5: Create slider handle (12×12)**

A rounded square / diamond shape in oxide green `#5e8a6e`:

```python
from PIL import Image
img = Image.new('RGBA', (12, 12), (0, 0, 0, 0))
fill = (0x5e, 0x8a, 0x6e, 255)
border = (0x3d, 0x5c, 0x48, 255)
highlight = (0x7a, 0xab, 0x8a, 255)
# Draw a rounded square (corner radius ~2px)
for y in range(12):
    for x in range(12):
        # Skip corners (2px radius)
        if (x < 2 and y < 2) or (x > 9 and y < 2) or (x < 2 and y > 9) or (x > 9 and y > 9):
            if (x == 0 and y == 0) or (x == 11 and y == 0) or (x == 0 and y == 11) or (x == 11 and y == 11):
                continue
            if (x == 1 and y == 0) or (x == 0 and y == 1):
                continue
            if (x == 10 and y == 0) or (x == 11 and y == 1):
                continue
            if (x == 0 and y == 10) or (x == 1 and y == 11):
                continue
            if (x == 10 and y == 11) or (x == 11 and y == 10):
                continue
        # Border (outer 1px)
        if x == 0 or x == 11 or y == 0 or y == 11:
            img.putpixel((x, y), border)
        elif x == 1 or y == 1:  # Highlight top/left inner
            img.putpixel((x, y), highlight)
        else:
            img.putpixel((x, y), fill)
# Center dot highlight
img.putpixel((5, 5), highlight)
img.putpixel((6, 5), highlight)
img.putpixel((5, 6), highlight)
img.putpixel((6, 6), highlight)
img.save('gol-project/assets/ui/sprites/ui_slider_handle.png')
```

- [ ] **Step 6: Create checkmark icon (8×8)**

```python
from PIL import Image
img = Image.new('RGBA', (8, 8), (0, 0, 0, 0))
color = (0xe8, 0xe4, 0xdf, 255)
# Classic checkmark ✓ shape (2px thick)
check_pixels = [
    (1,4),(1,5),
    (2,5),(2,6),
    (3,6),(3,7),
    (4,5),(4,6),
    (5,4),(5,5),
    (6,3),(6,4),
    (7,2),(7,3),
]
for x, y in check_pixels:
    img.putpixel((x, y), color)
img.save('gol-project/assets/ui/sprites/ui_check_icon.png')
```

- [ ] **Step 7: Create Godot .import files for all sprites**

For each sprite, create an `.import` file ensuring nearest-neighbor filtering:

```ini
[remap]
importer="texture"
type="CompressedTexture2D"
uid="uid://placeholder"
path="res://.godot/imported/ui_panel_9patch.png-hash.ctex"

[deps]
source_file="res://assets/ui/sprites/ui_panel_9patch.png"
dest_files=["res://.godot/imported/ui_panel_9patch.png-hash.ctex"]

[params]
compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/normal_map=0
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/size_limit=0
detect_3d/compress_to=0
texture/filter=0
texture/repeat=0
```

Alternative: run `gol reimport` after placing PNGs — Godot auto-generates these on import.

- [ ] **Step 8: Commit asset creation**

```bash
cd gol-project
git add assets/ui/sprites/
git commit -m "art(ui): add 5 pixel-art UI sprites for design system

- ui_panel_9patch.png (16x16) — panel borders
- ui_button_9patch.png (16x16) — button borders
- ui_cursor_arrow.png (8x8) — selection indicator
- ui_slider_handle.png (12x12) — slider grabber
- ui_check_icon.png (8x8) — checkbox checkmark"
```

---

## Task 2: Create ThemeConfig Resource

**Files:**
- Create: `scripts/ui/theme_config.gd`
- Test: `tests/unit/ui/test_theme_config.gd`

- [ ] **Step 1: Write ThemeConfig test**

```gdscript
# tests/unit/ui/test_theme_config.gd
extends GdUnitTestSuite

func test_theme_config_instantiates() -> void:
	var config := ThemeConfig.new()
	assert_object(config).is_not_null()
	assert_bool(config is Resource).is_true()

func test_theme_config_has_default_spacing() -> void:
	var config := ThemeConfig.new()
	assert_int(config.spacing_xs).is_equal(4)
	assert_int(config.spacing_sm).is_equal(8)
	assert_int(config.spacing_md).is_equal(16)
	assert_int(config.spacing_lg).is_equal(24)
	assert_int(config.spacing_xl).is_equal(32)

func test_theme_config_has_default_font_sizes() -> void:
	var config := ThemeConfig.new()
	assert_int(config.font_size_h1).is_equal(24)
	assert_int(config.font_size_h2).is_equal(20)
	assert_int(config.font_size_body).is_equal(16)
	assert_int(config.font_size_small).is_equal(12)

func test_theme_config_textures_default_null() -> void:
	var config := ThemeConfig.new()
	assert_object(config.panel_texture).is_null()
	assert_object(config.button_texture).is_null()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gol test unit --suite ui`
Expected: FAIL — `ThemeConfig` class not found

- [ ] **Step 3: Write ThemeConfig implementation**

```gdscript
# scripts/ui/theme_config.gd
class_name ThemeConfig
extends Resource
## Design token container for a UI theme skin.
## Each theme (Wasteland, etc.) is an instance of this resource with specific values.

# ── Palette ──
@export var color_bg_primary := Color("#1f1f1f")
@export var color_bg_secondary := Color("#242420")
@export var color_bg_overlay := Color(0.0, 0.0, 0.0, 0.6)
@export var color_border := Color("#3a3a3a")
@export var color_text_primary := Color("#e8e4df")
@export var color_text_secondary := Color("#b0aca5")
@export var color_text_disabled := Color("#5a5a5a")
@export var color_text_muted := Color("#8a8a8a")
@export var color_accent := Color("#c56a44")
@export var color_accent_hover := Color("#d4784a")
@export var color_success := Color("#5e8a6e")
@export var color_warning := Color("#d4a843")
@export var color_danger := Color("#8a3a3a")

# ── Button state colors ──
@export var color_btn_bg_normal := Color("#2a2a25")
@export var color_btn_bg_hover := Color("#3a3a34")
@export var color_btn_bg_pressed := Color("#1a1a16")
@export var color_btn_bg_disabled := Color("#222220")
@export var color_btn_border_normal := Color("#4a4a44")
@export var color_btn_border_hover := Color("#c56a44")
@export var color_btn_border_pressed := Color("#a05535")
@export var color_btn_border_disabled := Color("#333330")

# ── Panel ──
@export var color_panel_border := Color("#3a3a35")

# ── Font sizes ──
@export var font_size_h1 := 24
@export var font_size_h2 := 20
@export var font_size_button := 16
@export var font_size_body := 16
@export var font_size_small := 12
@export var font_size_caption := 10

# ── Spacing (4px grid) ──
@export var spacing_xs := 4
@export var spacing_sm := 8
@export var spacing_md := 16
@export var spacing_lg := 24
@export var spacing_xl := 32

# ── Textures (null = use StyleBoxFlat fallback) ──
@export var panel_texture: Texture2D
@export var button_texture: Texture2D
@export var cursor_texture: Texture2D
@export var slider_handle_texture: Texture2D
@export var check_icon_texture: Texture2D

# ── 9-patch margins ──
@export var ninepatch_margin := 4

# ── Font ──
@export var font: Font

# ── Animation durations (ms) ──
@export var transition_fast_ms := 50
@export var transition_normal_ms := 100
@export var transition_slow_ms := 150
```

- [ ] **Step 4: Run test to verify it passes**

Run: `gol test unit --suite ui`
Expected: PASS — all 4 ThemeConfig tests green

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/theme_config.gd tests/unit/ui/test_theme_config.gd
git commit -m "feat(ui): add ThemeConfig resource class for design tokens"
```

---

## Task 3: Create ThemeWasteland Factory

**Files:**
- Create: `scripts/ui/themes/theme_wasteland.gd`
- Test: `tests/unit/ui/test_theme_config.gd` (add tests)

- [ ] **Step 1: Add tests for ThemeWasteland**

Append to `tests/unit/ui/test_theme_config.gd`:

```gdscript
func test_wasteland_creates_valid_config() -> void:
	var config := ThemeWasteland.create()
	assert_object(config).is_not_null()
	assert_bool(config is ThemeConfig).is_true()

func test_wasteland_has_rust_accent() -> void:
	var config := ThemeWasteland.create()
	# Rust orange accent: #c56a44
	assert_float(config.color_accent.r).is_equal_approx(0.773, 0.01)
	assert_float(config.color_accent.g).is_equal_approx(0.416, 0.01)
	assert_float(config.color_accent.b).is_equal_approx(0.267, 0.01)

func test_wasteland_has_font() -> void:
	var config := ThemeWasteland.create()
	assert_object(config.font).is_not_null()

func test_wasteland_has_textures() -> void:
	var config := ThemeWasteland.create()
	assert_object(config.panel_texture).is_not_null()
	assert_object(config.button_texture).is_not_null()
	assert_object(config.cursor_texture).is_not_null()
	assert_object(config.slider_handle_texture).is_not_null()
	assert_object(config.check_icon_texture).is_not_null()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gol test unit --suite ui`
Expected: FAIL — `ThemeWasteland` class not found

- [ ] **Step 3: Write ThemeWasteland implementation**

```gdscript
# scripts/ui/themes/theme_wasteland.gd
class_name ThemeWasteland
extends RefCounted
## Factory for the "Wasteland" theme — post-apocalyptic warm palette.

static func create() -> ThemeConfig:
	var config := ThemeConfig.new()
	# Palette (all defaults in ThemeConfig already match Wasteland spec)
	# Only override if ThemeConfig defaults diverge from Wasteland values.
	# Since ThemeConfig defaults ARE Wasteland values, we only need to set
	# the non-defaultable resources:
	config.font = preload("res://assets/fonts/fusion-pixel-12px.otf")
	config.panel_texture = preload("res://assets/ui/sprites/ui_panel_9patch.png")
	config.button_texture = preload("res://assets/ui/sprites/ui_button_9patch.png")
	config.cursor_texture = preload("res://assets/ui/sprites/ui_cursor_arrow.png")
	config.slider_handle_texture = preload("res://assets/ui/sprites/ui_slider_handle.png")
	config.check_icon_texture = preload("res://assets/ui/sprites/ui_check_icon.png")
	return config
```

- [ ] **Step 4: Run test to verify it passes**

Run: `gol test unit --suite ui`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/themes/theme_wasteland.gd tests/unit/ui/test_theme_config.gd
git commit -m "feat(ui): add ThemeWasteland factory with post-apocalyptic palette"
```

---

## Task 4: Create ThemeBuilder

**Files:**
- Create: `scripts/ui/theme_builder.gd`
- Test: `tests/unit/ui/test_theme_builder.gd`

- [ ] **Step 1: Write ThemeBuilder tests**

```gdscript
# tests/unit/ui/test_theme_builder.gd
extends GdUnitTestSuite

func test_build_returns_theme() -> void:
	var config := ThemeWasteland.create()
	var theme := ThemeBuilder.build(config)
	assert_object(theme).is_not_null()
	assert_bool(theme is Theme).is_true()

func test_build_sets_default_font() -> void:
	var config := ThemeWasteland.create()
	var theme := ThemeBuilder.build(config)
	assert_object(theme.default_font).is_not_null()

func test_build_button_normal_is_stylebox_texture() -> void:
	var config := ThemeWasteland.create()
	var theme := ThemeBuilder.build(config)
	var sb = theme.get_stylebox("normal", "Button")
	assert_object(sb).is_not_null()
	assert_bool(sb is StyleBoxTexture).is_true()

func test_build_button_uses_ninepatch_margins() -> void:
	var config := ThemeWasteland.create()
	var theme := ThemeBuilder.build(config)
	var sb: StyleBoxTexture = theme.get_stylebox("normal", "Button")
	assert_int(int(sb.texture_margin_left)).is_equal(config.ninepatch_margin)

func test_build_panel_is_stylebox_texture() -> void:
	var config := ThemeWasteland.create()
	var theme := ThemeBuilder.build(config)
	var sb = theme.get_stylebox("panel", "PanelContainer")
	assert_bool(sb is StyleBoxTexture).is_true()

func test_build_without_textures_falls_back_to_flat() -> void:
	var config := ThemeConfig.new()
	config.font = preload("res://assets/fonts/fusion-pixel-12px.otf")
	# No textures set — should use StyleBoxFlat
	var theme := ThemeBuilder.build(config)
	var sb = theme.get_stylebox("normal", "Button")
	assert_bool(sb is StyleBoxFlat).is_true()

func test_build_button_font_color() -> void:
	var config := ThemeWasteland.create()
	var theme := ThemeBuilder.build(config)
	var color = theme.get_color("font_color", "Button")
	assert_float(color.r).is_equal_approx(config.color_text_primary.r, 0.01)

func test_build_label_font_size() -> void:
	var config := ThemeWasteland.create()
	var theme := ThemeBuilder.build(config)
	var size = theme.get_font_size("font_size", "Label")
	assert_int(size).is_equal(config.font_size_body)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gol test unit --suite ui`
Expected: FAIL — `ThemeBuilder` class not found

- [ ] **Step 3: Write ThemeBuilder implementation**

```gdscript
# scripts/ui/theme_builder.gd
class_name ThemeBuilder
extends RefCounted
## Converts a ThemeConfig into a Godot Theme object.
## Uses StyleBoxTexture (9-patch) when textures are available, StyleBoxFlat as fallback.

static func build(config: ThemeConfig) -> Theme:
	var theme := Theme.new()
	_setup_font(theme, config)
	_setup_button(theme, config)
	_setup_label(theme, config)
	_setup_panel(theme, config)
	_setup_tab_container(theme, config)
	_setup_slider(theme, config)
	_setup_checkbox(theme, config)
	return theme


static func _setup_font(theme: Theme, config: ThemeConfig) -> void:
	if config.font == null:
		return
	theme.default_font = config.font
	theme.set_font("font", "Button", config.font)
	theme.set_font("font", "Label", config.font)
	theme.set_font("font", "TabContainer", config.font)


static func _setup_button(theme: Theme, config: ThemeConfig) -> void:
	if config.button_texture != null:
		theme.set_stylebox("normal", "Button", _create_texture_stylebox(
			config.button_texture, config.ninepatch_margin, config.color_btn_bg_normal, config.spacing_md, config.spacing_sm))
		theme.set_stylebox("hover", "Button", _create_texture_stylebox(
			config.button_texture, config.ninepatch_margin, config.color_btn_bg_hover, config.spacing_md, config.spacing_sm))
		theme.set_stylebox("pressed", "Button", _create_texture_stylebox(
			config.button_texture, config.ninepatch_margin, config.color_btn_bg_pressed, config.spacing_md, config.spacing_sm))
		theme.set_stylebox("disabled", "Button", _create_texture_stylebox(
			config.button_texture, config.ninepatch_margin, config.color_btn_bg_disabled, config.spacing_md, config.spacing_sm))
		theme.set_stylebox("focus", "Button", _create_texture_stylebox(
			config.button_texture, config.ninepatch_margin, config.color_btn_bg_normal, config.spacing_md, config.spacing_sm))
	else:
		theme.set_stylebox("normal", "Button", _create_flat_stylebox(config.color_btn_bg_normal, config.color_btn_border_normal, config.spacing_md, config.spacing_sm))
		theme.set_stylebox("hover", "Button", _create_flat_stylebox(config.color_btn_bg_hover, config.color_btn_border_hover, config.spacing_md, config.spacing_sm))
		theme.set_stylebox("pressed", "Button", _create_flat_stylebox(config.color_btn_bg_pressed, config.color_btn_border_pressed, config.spacing_md, config.spacing_sm))
		theme.set_stylebox("disabled", "Button", _create_flat_stylebox(config.color_btn_bg_disabled, config.color_btn_border_disabled, config.spacing_md, config.spacing_sm))
		theme.set_stylebox("focus", "Button", _create_flat_stylebox(config.color_btn_bg_normal, config.color_accent, config.spacing_md, config.spacing_sm))
	# Font colors
	theme.set_color("font_color", "Button", config.color_text_primary)
	theme.set_color("font_hover_color", "Button", config.color_text_primary)
	theme.set_color("font_pressed_color", "Button", config.color_accent)
	theme.set_color("font_focus_color", "Button", config.color_text_primary)
	theme.set_color("font_disabled_color", "Button", config.color_text_disabled)
	theme.set_font_size("font_size", "Button", config.font_size_button)


static func _setup_label(theme: Theme, config: ThemeConfig) -> void:
	theme.set_color("font_color", "Label", config.color_text_primary)
	theme.set_font_size("font_size", "Label", config.font_size_body)
	theme.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.6))
	theme.set_constant("outline_size", "Label", 1)


static func _setup_panel(theme: Theme, config: ThemeConfig) -> void:
	var sb: StyleBox
	if config.panel_texture != null:
		sb = _create_texture_stylebox(config.panel_texture, config.ninepatch_margin, config.color_bg_secondary, config.spacing_lg, config.spacing_lg)
	else:
		sb = _create_flat_stylebox(config.color_bg_secondary, config.color_panel_border, config.spacing_lg, config.spacing_lg)
	theme.set_stylebox("panel", "PanelContainer", sb)
	theme.set_stylebox("panel", "Panel", sb)


static func _setup_tab_container(theme: Theme, config: ThemeConfig) -> void:
	theme.set_font_size("font_size", "TabContainer", config.font_size_body)
	theme.set_color("font_selected_color", "TabContainer", config.color_accent)
	theme.set_color("font_unselected_color", "TabContainer", config.color_text_disabled)


static func _setup_slider(theme: Theme, config: ThemeConfig) -> void:
	# Track (background)
	var track := StyleBoxFlat.new()
	track.bg_color = config.color_border
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	theme.set_stylebox("slider", "HSlider", track)
	# Grabber
	if config.slider_handle_texture != null:
		theme.set_icon("grabber", "HSlider", config.slider_handle_texture)
		theme.set_icon("grabber_highlight", "HSlider", config.slider_handle_texture)


static func _setup_checkbox(theme: Theme, config: ThemeConfig) -> void:
	if config.check_icon_texture != null:
		theme.set_icon("checked", "CheckBox", config.check_icon_texture)
	theme.set_color("font_color", "CheckBox", config.color_text_primary)
	theme.set_color("font_hover_color", "CheckBox", config.color_text_primary)
	theme.set_font_size("font_size", "CheckBox", config.font_size_body)


# ── Private Helpers ──

static func _create_texture_stylebox(texture: Texture2D, margin: int, modulate: Color, h_padding: int, v_padding: int) -> StyleBoxTexture:
	var sbt := StyleBoxTexture.new()
	sbt.texture = texture
	sbt.texture_margin_left = margin
	sbt.texture_margin_right = margin
	sbt.texture_margin_top = margin
	sbt.texture_margin_bottom = margin
	sbt.content_margin_left = h_padding
	sbt.content_margin_right = h_padding
	sbt.content_margin_top = v_padding
	sbt.content_margin_bottom = v_padding
	sbt.modulate_color = modulate
	sbt.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sbt.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return sbt


static func _create_flat_stylebox(bg_color: Color, border_color: Color, h_padding: int, v_padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.border_width_top = 1
	box.border_width_bottom = 1
	box.border_width_left = 1
	box.border_width_right = 1
	box.content_margin_left = h_padding
	box.content_margin_right = h_padding
	box.content_margin_top = v_padding
	box.content_margin_bottom = v_padding
	return box
```

- [ ] **Step 4: Run test to verify it passes**

Run: `gol test unit --suite ui`
Expected: PASS — all 8 ThemeBuilder tests green

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/theme_builder.gd tests/unit/ui/test_theme_builder.gd
git commit -m "feat(ui): add ThemeBuilder converting ThemeConfig to Godot Theme"
```

---

## Task 5: Create ThemeManager & Wire into Startup

**Files:**
- Create: `scripts/ui/theme_manager.gd`
- Modify: `scripts/gol.gd`
- Modify: `scripts/ui/gol_theme.gd`

- [ ] **Step 1: Write ThemeManager**

```gdscript
# scripts/ui/theme_manager.gd
class_name ThemeManager
extends RefCounted
## Runtime theme manager. Applies themes to the scene root and signals changes.

signal theme_changed(config: ThemeConfig)

var _current_config: ThemeConfig
var _current_theme: Theme
var _root: Window


func setup(root: Window) -> void:
	_root = root


func get_config() -> ThemeConfig:
	return _current_config


func apply_theme(config: ThemeConfig) -> void:
	_current_config = config
	_current_theme = ThemeBuilder.build(config)
	if _root:
		_root.theme = _current_theme
	theme_changed.emit(config)


func get_transition_duration(speed: String = "normal") -> float:
	if _current_config == null:
		return 0.1
	match speed:
		"fast":
			return _current_config.transition_fast_ms / 1000.0
		"slow":
			return _current_config.transition_slow_ms / 1000.0
		_:
			return _current_config.transition_normal_ms / 1000.0
```

- [ ] **Step 2: Modify `scripts/gol.gd` to use ThemeManager**

Replace the theme section (around line 7 and lines 37-39):

Remove:
```gdscript
const GOLTheme = preload("res://scripts/ui/gol_theme.gd")
```

Add member variable:
```gdscript
var _theme_manager: ThemeManager
```

Replace in `setup()`:
```gdscript
# Before:
# var theme = GOLTheme.create_theme()
# get_tree().get_root().theme = theme

# After:
_theme_manager = ThemeManager.new()
_theme_manager.setup(get_tree().get_root())
_theme_manager.apply_theme(ThemeWasteland.create())
# Set custom cursor
if _theme_manager.get_config().cursor_texture:
    Input.set_custom_mouse_cursor(
        _theme_manager.get_config().cursor_texture,
        Input.CURSOR_ARROW, Vector2(0, 0))
```

- [ ] **Step 3: Deprecate `gol_theme.gd` as forwarding shim**

Replace `scripts/ui/gol_theme.gd` content with:

```gdscript
class_name GOLTheme
extends RefCounted
## DEPRECATED — Backward-compatibility shim.
## Use ThemeConfig + ThemeManager for new code.
## This class forwards to Wasteland palette values.

# ── Palette (forwarded to Wasteland values) ──
const COLOR_BG_PANEL := Color("#242420")
const COLOR_BG_OVERLAY := Color(0.0, 0.0, 0.0, 0.6)
const COLOR_TEXT := Color("#e8e4df")
const COLOR_TEXT_HOVER := Color("#ffffff")
const COLOR_TEXT_DISABLED := Color("#5a5a5a")
const COLOR_ACCENT := Color("#c56a44")
const COLOR_FOCUS_BORDER := Color("#c56a44")

const COLOR_BTN_BG_NORMAL := Color("#2a2a25")
const COLOR_BTN_BG_HOVER := Color("#3a3a34")
const COLOR_BTN_BG_PRESSED := Color("#1a1a16")
const COLOR_BTN_BG_DISABLED := Color("#222220")
const COLOR_BTN_BORDER_NORMAL := Color("#4a4a44")
const COLOR_BTN_BORDER_HOVER := Color("#c56a44")
const COLOR_BTN_BORDER_PRESSED := Color("#a05535")
const COLOR_BTN_BORDER_DISABLED := Color("#333330")

const COLOR_PANEL_BORDER := Color("#3a3a35")
const COLOR_PANEL_SHADOW := Color(0.0, 0.0, 0.0, 0.0)

const COLOR_KEYCAP_BG := Color("#1f1f1f")
const COLOR_KEYCAP_BORDER := Color("#4a4a44")

const FONT_SIZE_H1 := 24
const FONT_SIZE_H2 := 20
const FONT_SIZE_BUTTON := 16
const FONT_SIZE_BODY := 16
const FONT_SIZE_SMALL := 12

const MARGIN_LARGE := 24
const MARGIN_MEDIUM := 16
const MARGIN_SMALL := 8
const BUTTON_SEPARATION := 16

const PIXEL_FONT := preload("res://assets/fonts/fusion-pixel-12px.otf")


## DEPRECATED — use ThemeManager.apply_theme(ThemeWasteland.create()) instead.
static func create_theme() -> Theme:
	return ThemeBuilder.build(ThemeWasteland.create())


## Keycap stylebox for settings menu keybinding display.
static func create_keycap_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_KEYCAP_BG
	box.border_color = COLOR_KEYCAP_BORDER
	box.border_width_top = 1
	box.border_width_bottom = 1
	box.border_width_left = 1
	box.border_width_right = 1
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 2
	box.corner_radius_bottom_left = 2
	box.corner_radius_bottom_right = 2
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box
```

- [ ] **Step 4: Run all tests**

Run: `gol test unit`
Expected: ALL PASS — existing `test_gol_theme.gd` tests may need updates (see Task 6)

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/theme_manager.gd scripts/gol.gd scripts/ui/gol_theme.gd
git commit -m "feat(ui): wire ThemeManager into startup, deprecate GOLTheme

ThemeManager now applies ThemeWasteland at boot.
GOLTheme remains as backward-compat shim with forwarded values."
```

---

## Task 6: Update Existing Theme Tests

**Files:**
- Modify: `tests/unit/ui/test_gol_theme.gd`

- [ ] **Step 1: Rewrite test file for new architecture**

```gdscript
# tests/unit/ui/test_gol_theme.gd
extends GdUnitTestSuite
## Tests for the theme system (ThemeBuilder + GOLTheme backward compat)

func test_create_theme_returns_theme() -> void:
	var theme = GOLTheme.create_theme()
	assert_object(theme).is_not_null()
	assert_bool(theme is Theme).is_true()

func test_button_normal_is_stylebox_texture() -> void:
	var theme = GOLTheme.create_theme()
	var sb = theme.get_stylebox("normal", "Button")
	assert_object(sb).is_not_null()
	# With textures loaded, should be StyleBoxTexture
	assert_bool(sb is StyleBoxTexture).is_true()

func test_button_hover_is_stylebox_texture() -> void:
	var theme = GOLTheme.create_theme()
	var sb = theme.get_stylebox("hover", "Button")
	assert_object(sb).is_not_null()
	assert_bool(sb is StyleBoxTexture).is_true()

func test_button_font_colors() -> void:
	var theme = GOLTheme.create_theme()
	var color = theme.get_color("font_color", "Button")
	assert_float(color.r).is_greater(0.8)  # warm white ~0.91

func test_button_font_size() -> void:
	var theme = GOLTheme.create_theme()
	var size = theme.get_font_size("font_size", "Button")
	assert_int(size).is_equal(16)

func test_panel_is_stylebox_texture() -> void:
	var theme = GOLTheme.create_theme()
	var sb = theme.get_stylebox("panel", "PanelContainer")
	assert_object(sb).is_not_null()
	assert_bool(sb is StyleBoxTexture).is_true()

func test_theme_has_label_styles() -> void:
	var theme = GOLTheme.create_theme()
	var color = theme.get_color("font_color", "Label")
	assert_float(color.a).is_greater(0.0)

func test_theme_has_default_font() -> void:
	var theme = GOLTheme.create_theme()
	assert_object(theme.default_font).is_not_null()

func test_keycap_stylebox() -> void:
	var box = GOLTheme.create_keycap_stylebox()
	assert_object(box).is_not_null()
	assert_bool(box is StyleBoxFlat).is_true()
	assert_int(box.border_width_top).is_equal(1)
```

- [ ] **Step 2: Run tests**

Run: `gol test unit --suite ui`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add tests/unit/ui/test_gol_theme.gd
git commit -m "test(ui): update theme tests for new Config/Builder architecture"
```

---

## Task 7: Migrate Menu Scenes (Remove Scattered Overrides)

**Files:**
- Modify: `scenes/ui/menus/title_screen.tscn`
- Modify: `scenes/ui/menus/pause_menu.tscn`
- Modify: `scenes/ui/menus/settings_menu.tscn`
- Modify: `scenes/ui/menus/game_over.tscn`
- Modify: `scenes/ui/menus/confirm_dialog.tscn`

- [ ] **Step 1: Clean title_screen.tscn**

Remove from each Button node:
```
theme_override_font_sizes/font_size = 28
```

Remove from VBoxContainer:
```
theme_override_constants/separation = 24
```

Buttons will now inherit font_size=16 from root theme (button size). If buttons need to be larger on title screen specifically, add a single override at the VBoxContainer level or use a theme type variation.

- [ ] **Step 2: Clean pause_menu.tscn**

Remove:
- `theme_override_constants/margin_*` from MarginContainer
- `theme_override_constants/separation` from VBoxContainer
- `theme_override_font_sizes/font_size = 32` from title Label (will use H1 via manual override `font_size = 24`)

- [ ] **Step 3: Clean settings_menu.tscn**

Remove:
- `theme_override_font_sizes/font_size = 32` from title Label
- `theme_override_constants/separation` from containers

- [ ] **Step 4: Clean game_over.tscn**

Remove:
- Inline `LabelSettings` sub_resource with `font_size=80`
- Add a `theme_override_font_sizes/font_size = 24` (H1 size) for the "YOU DIED" label
- Replace `font_color` in LabelSettings with theme danger color via `theme_override_colors/font_color`

- [ ] **Step 5: Clean confirm_dialog.tscn**

Remove:
- `theme_override_constants/separation` from VBox/HBox containers

- [ ] **Step 6: Run game to verify visually**

Run: `gol run game --windowed`
Navigate through: Title → Settings → Back → Quit → (restart) → Title
Expected: All menus render with new warm palette, no broken layouts

- [ ] **Step 7: Commit**

```bash
git add scenes/ui/menus/
git commit -m "refactor(ui): remove scattered theme overrides from menu scenes

Menus now inherit styling from root theme cascade.
Specific deviations (H1 sizes, game-over styling) use minimal overrides."
```

---

## Task 8: Migrate HUD & In-World UI Scripts

**Files:**
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/views/menu/view_build_hotbar.gd`
- Modify: `scripts/ui/views/view_hp_bar.gd`
- Modify: `scripts/ui/views/view_speech_bubble.gd`

- [ ] **Step 1: Clean hud.tscn**

Remove `theme_override_colors/font_color`, `theme_override_colors/font_outline_color`, `theme_override_font_sizes/font_size` from resource counter Labels — these now come from root theme Label defaults.

Keep `theme_override_constants/separation` for HBoxContainer (structural layout).

- [ ] **Step 2: Update view_build_hotbar.gd colors**

In `_init_styles()`, replace hardcoded colors:
```gdscript
# Before:
# Color(1.0, 0.9, 0.3, 1.0) for active
# After:
GOLTheme.COLOR_ACCENT  # for active border (rust orange)
```

Or more accurately, use the forwarded constants from the shim:
- Active slot border: `GOLTheme.COLOR_ACCENT` → `#c56a44`
- Normal bg: `GOLTheme.COLOR_BTN_BG_NORMAL` → `#2a2a25`

- [ ] **Step 3: Update view_hp_bar.gd colors**

Replace:
- `Color.RED` → `Color("#8a3a3a")` (danger from palette)
- Background bar `Color(0.2, 0.2, 0.2, 0.8)` → `Color("#242420")` with alpha

Keep: HP fill color logic (red for characters, blue for buildings) — these are gameplay-semantic.

- [ ] **Step 4: Update view_speech_bubble.gd colors**

In `_apply_theme()` and `_apply_event_label_theme()`:
- `font_color` → `Color("#e8e4df")` (text primary)
- `font_outline_color` → keep `Color(0, 0, 0, 0.85)` (functional)
- Keep `font_size = 8` (intentionally tiny for in-world)

- [ ] **Step 5: Run game & verify HUD**

Run: `gol run game --windowed -- --skip-menu`
Expected: HUD elements (HP bar, resource counters, speech bubbles) display with updated palette

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/hud.tscn scripts/ui/views/menu/view_build_hotbar.gd \
    scripts/ui/views/view_hp_bar.gd scripts/ui/views/view_speech_bubble.gd
git commit -m "refactor(ui): migrate HUD and in-world views to theme palette

Replace hardcoded Color() literals with theme-derived values.
Keep structural pixel sizes for in-world UI (intentional deviations)."
```

---

## Task 9: Final Integration Test & Push

**Files:** None new — verification only.

- [ ] **Step 1: Run full unit test suite**

```bash
gol test unit
```
Expected: ALL PASS

- [ ] **Step 2: Run integration tests**

```bash
gol test integration
```
Expected: ALL PASS (or pre-existing failures only)

- [ ] **Step 3: Visual verification — full menu flow**

```bash
gol run game --windowed
```

Verify:
1. Title screen: warm dark background, buttons with pixel-art 9-patch borders, rust-orange border on hover
2. Settings menu: sliders with green diamond handle, checkboxes with checkmark icon
3. Pause menu: panel with 9-patch border, proper spacing
4. Confirm dialog: centered panel, primary/secondary buttons distinguishable
5. Game Over: danger red text, proper layout
6. HUD: resource counters in warm white, HP bar with dark background
7. Custom cursor: pixel arrow visible

- [ ] **Step 4: Commit any final adjustments**

If visual verification reveals issues, fix them and commit.

- [ ] **Step 5: Push gol-project submodule**

```bash
cd gol-project
git push origin main
```

- [ ] **Step 6: Update main repo submodule pointer**

```bash
cd ..  # back to gol/
git add gol-project
git commit -m "chore: update gol-project submodule (UI redesign)"
git push origin main
```

---

## Dependency Graph

```
Task 1 (Assets) ─────────────┐
                              ├──▶ Task 4 (ThemeBuilder) ──▶ Task 5 (ThemeManager + Wire)
Task 2 (ThemeConfig) ────────┤                                      │
                              │                                      ▼
Task 3 (ThemeWasteland) ─────┘                            Task 6 (Update Tests)
                                                                     │
                                                                     ▼
                                                          Task 7 (Menu Migration)
                                                                     │
                                                                     ▼
                                                          Task 8 (HUD Migration)
                                                                     │
                                                                     ▼
                                                          Task 9 (Final Verification)
```

- Tasks 1, 2, 3 can run in parallel (no dependencies between them)
- Task 4 requires Tasks 1+2+3 (needs ThemeConfig, ThemeWasteland, and textures)
- Tasks 5-9 are sequential
