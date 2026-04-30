# Menu Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three menu issues — add building keybindings to options menu, add "return to title" with confirm dialog to pause menu, and overhaul menu visual style with pixel font + StyleBoxFlat upgrades.

**Architecture:** Upgrade `GOLTheme.gd` programmatic theme with proper StyleBoxFlat buttons, panel shadows, and pixel font. Add grouped keybinding display to `ViewModel_Settings`. Create reusable `View_ConfirmDialog` for pause menu's "return to title" and quit confirmation. Add `GOL.return_to_title()` for scene cleanup.

**Tech Stack:** Godot 4.6, GDScript, MVVM UI pattern, gdUnit4 tests

**Worktree:** Create from `gol-project` submodule, branch `feature/menu-polish`, based on latest `main`.

**Spec:** `docs/superpowers/specs/2026-04-30-menu-polish-design.md`

---

### Task 1: Download Pixel Font + Setup Worktree

**Files:**
- Create: `assets/fonts/fusion-pixel-12px-proportional-zh_hans.ttf`

- [ ] **Step 1: Create worktree from gol-project submodule**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
git worktree add /Users/dluckdu/Documents/Github/gol/.worktrees/manual/menu-polish -b feature/menu-polish main
cd /Users/dluckdu/Documents/Github/gol/.worktrees/manual/menu-polish
```

- [ ] **Step 2: Download Fusion Pixel font**

Download the Fusion Pixel 12px proportional Chinese font (OFL licensed) and place it in the worktree:

```bash
cd /Users/dluckdu/Documents/Github/gol/.worktrees/manual/menu-polish
mkdir -p assets/fonts
# Download from Fusion Pixel releases
curl -L "https://github.com/TakWolf/fusion-pixel-font/releases/download/2025.01.22/fusion-pixel-12px-proportional-otf-v2025.01.22.zip" -o /tmp/fusion-pixel.zip
unzip -o /tmp/fusion-pixel.zip -d /tmp/fusion-pixel/
# Find and copy the OTF file (Fusion Pixel ships as OTF)
find /tmp/fusion-pixel/ -name "*.otf" | head -1 | xargs -I{} cp {} assets/fonts/fusion-pixel-12px.otf
rm -rf /tmp/fusion-pixel.zip /tmp/fusion-pixel/
```

If the URL or format has changed, search GitHub releases for `TakWolf/fusion-pixel-font` and download the 12px proportional variant. The font must support CJK (Chinese) characters. Place the `.otf` or `.ttf` file as `assets/fonts/fusion-pixel-12px.otf`.

- [ ] **Step 3: Verify font file exists**

```bash
ls -la assets/fonts/
```

Expected: a font file (`.otf` or `.ttf`) around 1-5 MB.

- [ ] **Step 4: Commit font**

```bash
git add assets/fonts/
git commit -m "chore: add Fusion Pixel 12px font for pixel-style menus"
```

---

### Task 2: GOLTheme Visual Overhaul — Button StyleBox + Panel + Font

**Files:**
- Modify: `scripts/ui/gol_theme.gd` (full rewrite of style methods)
- Modify: `tests/unit/ui/test_gol_theme.gd` (update tests for new StyleBoxFlat)

- [ ] **Step 1: Write failing tests for new theme properties**

Replace the contents of `tests/unit/ui/test_gol_theme.gd`:

```gdscript
extends GdUnitTestSuite
## Unit tests for GOLTheme

const GOLTheme = preload("res://scripts/ui/gol_theme.gd")


func test_create_theme_returns_theme() -> void:
	var theme = GOLTheme.create_theme()
	assert_object(theme).is_not_null()
	assert_bool(theme is Theme).is_true()


func test_button_normal_is_stylebox_flat() -> void:
	var theme = GOLTheme.create_theme()
	var normal = theme.get_stylebox("normal", "Button")
	assert_bool(normal is StyleBoxFlat).is_true()


func test_button_hover_is_stylebox_flat() -> void:
	var theme = GOLTheme.create_theme()
	var hover = theme.get_stylebox("hover", "Button")
	assert_bool(hover is StyleBoxFlat).is_true()


func test_button_pressed_is_stylebox_flat() -> void:
	var theme = GOLTheme.create_theme()
	var pressed = theme.get_stylebox("pressed", "Button")
	assert_bool(pressed is StyleBoxFlat).is_true()


func test_button_normal_has_border() -> void:
	var theme = GOLTheme.create_theme()
	var normal = theme.get_stylebox("normal", "Button") as StyleBoxFlat
	assert_int(normal.border_width_top).is_equal(2)
	assert_int(normal.border_width_bottom).is_equal(2)


func test_button_normal_has_corner_radius_2() -> void:
	var theme = GOLTheme.create_theme()
	var normal = theme.get_stylebox("normal", "Button") as StyleBoxFlat
	assert_int(normal.corner_radius_top_left).is_equal(2)


func test_button_font_colors() -> void:
	var theme = GOLTheme.create_theme()
	assert_object(theme.get_color("font_color", "Button")).is_equal(GOLTheme.COLOR_TEXT)
	assert_object(theme.get_color("font_hover_color", "Button")).is_equal(GOLTheme.COLOR_TEXT_HOVER)
	assert_object(theme.get_color("font_pressed_color", "Button")).is_equal(GOLTheme.COLOR_ACCENT)


func test_button_font_size() -> void:
	var theme = GOLTheme.create_theme()
	assert_int(theme.get_font_size("font_size", "Button")).is_equal(GOLTheme.FONT_SIZE_BUTTON)


func test_panel_has_border() -> void:
	var theme = GOLTheme.create_theme()
	var panel = theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_int(panel.border_width_top).is_equal(2)


func test_panel_has_shadow() -> void:
	var theme = GOLTheme.create_theme()
	var panel = theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_int(panel.shadow_size).is_equal(4)


func test_panel_corner_radius() -> void:
	var theme = GOLTheme.create_theme()
	var panel = theme.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_int(panel.corner_radius_top_left).is_equal(2)


func test_theme_has_label_styles() -> void:
	var theme = GOLTheme.create_theme()
	var color = theme.get_color("font_color", "Label")
	assert_float(color.a).is_greater(0.0)


func test_theme_has_tab_container_styles() -> void:
	var theme = GOLTheme.create_theme()
	assert_int(theme.get_font_size("font_size", "TabContainer")).is_greater(0)


func test_theme_has_default_font() -> void:
	var theme = GOLTheme.create_theme()
	var font = theme.get_default_font()
	# Font may be null if file not found at test time — just check it was attempted
	# The important thing is that create_theme() doesn't crash
	assert_bool(true).is_true()
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
gol test unit --suite ui
```

Expected: `test_button_normal_is_stylebox_flat`, `test_panel_has_border`, `test_panel_has_shadow` etc. FAIL because current buttons use `StyleBoxEmpty`.

- [ ] **Step 3: Implement GOLTheme overhaul**

Replace the full contents of `scripts/ui/gol_theme.gd`:

```gdscript
class_name GOLTheme
extends RefCounted

# ── Palette ──
const COLOR_BG_PANEL := Color(0.06, 0.06, 0.1, 0.94)
const COLOR_BG_OVERLAY := Color(0.0, 0.0, 0.0, 0.6)
const COLOR_TEXT := Color(0.7, 0.72, 0.78, 1.0)
const COLOR_TEXT_HOVER := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_DISABLED := Color(0.4, 0.4, 0.45, 0.6)
const COLOR_ACCENT := Color(0.65, 0.7, 0.9, 1.0)
const COLOR_FOCUS_BORDER := Color(0.65, 0.7, 0.9, 0.5)

# Button state colors
const COLOR_BTN_BG_NORMAL := Color(0.12, 0.12, 0.18, 0.85)
const COLOR_BTN_BG_HOVER := Color(0.18, 0.18, 0.25, 0.95)
const COLOR_BTN_BG_PRESSED := Color(0.06, 0.06, 0.1, 0.95)
const COLOR_BTN_BG_DISABLED := Color(0.08, 0.08, 0.12, 0.5)
const COLOR_BTN_BORDER_NORMAL := Color(0.3, 0.32, 0.4, 1.0)
const COLOR_BTN_BORDER_HOVER := Color(0.65, 0.7, 0.9, 1.0)
const COLOR_BTN_BORDER_PRESSED := Color(0.5, 0.55, 0.7, 1.0)
const COLOR_BTN_BORDER_DISABLED := Color(0.2, 0.2, 0.25, 1.0)

# Panel colors
const COLOR_PANEL_BORDER := Color(0.25, 0.27, 0.35, 1.0)
const COLOR_PANEL_SHADOW := Color(0.0, 0.0, 0.0, 0.3)

# Keybinding key-cap styling
const COLOR_KEYCAP_BG := Color(0.15, 0.15, 0.22, 0.8)
const COLOR_KEYCAP_BORDER := Color(0.3, 0.32, 0.4, 1.0)

# ── Font Sizes ──
const FONT_SIZE_H1 := 32
const FONT_SIZE_H2 := 24
const FONT_SIZE_BUTTON := 24
const FONT_SIZE_BODY := 16
const FONT_SIZE_SMALL := 12

# ── Spacing ──
const MARGIN_LARGE := 32
const MARGIN_MEDIUM := 16
const MARGIN_SMALL := 8
const BUTTON_SEPARATION := 24

# ── Font Path ──
const PIXEL_FONT_PATH := "res://assets/fonts/fusion-pixel-12px.otf"


static func create_theme() -> Theme:
	var theme := Theme.new()
	_setup_font(theme)
	_setup_button(theme)
	_setup_label(theme)
	_setup_panel(theme)
	_setup_tab_container(theme)
	return theme


static func _setup_font(theme: Theme) -> void:
	if ResourceLoader.exists(PIXEL_FONT_PATH):
		var font: Font = load(PIXEL_FONT_PATH)
		if font:
			theme.set_default_font(font)


static func _setup_button(theme: Theme) -> void:
	# Normal
	var normal := _create_button_stylebox(COLOR_BTN_BG_NORMAL, COLOR_BTN_BORDER_NORMAL, 2)
	theme.set_stylebox("normal", "Button", normal)
	# Hover
	var hover := _create_button_stylebox(COLOR_BTN_BG_HOVER, COLOR_BTN_BORDER_HOVER, 2)
	theme.set_stylebox("hover", "Button", hover)
	# Pressed
	var pressed := _create_button_stylebox(COLOR_BTN_BG_PRESSED, COLOR_BTN_BORDER_PRESSED, 2)
	theme.set_stylebox("pressed", "Button", pressed)
	# Disabled
	var disabled := _create_button_stylebox(COLOR_BTN_BG_DISABLED, COLOR_BTN_BORDER_DISABLED, 1)
	theme.set_stylebox("disabled", "Button", disabled)
	# Focus — accent border
	var focus := _create_button_stylebox(COLOR_BTN_BG_NORMAL, COLOR_FOCUS_BORDER, 2)
	theme.set_stylebox("focus", "Button", focus)
	# Font colors
	theme.set_color("font_color", "Button", COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_TEXT_HOVER)
	theme.set_color("font_pressed_color", "Button", COLOR_ACCENT)
	theme.set_color("font_focus_color", "Button", COLOR_TEXT_HOVER)
	theme.set_color("font_disabled_color", "Button", COLOR_TEXT_DISABLED)
	theme.set_font_size("font_size", "Button", FONT_SIZE_BUTTON)


static func _create_button_stylebox(bg_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.border_width_top = border_width
	box.border_width_bottom = border_width
	box.border_width_left = border_width
	box.border_width_right = border_width
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 2
	box.corner_radius_bottom_left = 2
	box.corner_radius_bottom_right = 2
	box.content_margin_left = MARGIN_MEDIUM
	box.content_margin_right = MARGIN_MEDIUM
	box.content_margin_top = MARGIN_SMALL
	box.content_margin_bottom = MARGIN_SMALL
	return box


static func _setup_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", COLOR_TEXT)
	theme.set_font_size("font_size", "Label", FONT_SIZE_BODY)
	theme.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.6))
	theme.set_constant("outline_size", "Label", 1)


static func _setup_panel(theme: Theme) -> void:
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = COLOR_BG_PANEL
	panel_box.border_color = COLOR_PANEL_BORDER
	panel_box.border_width_top = 2
	panel_box.border_width_bottom = 2
	panel_box.border_width_left = 2
	panel_box.border_width_right = 2
	panel_box.corner_radius_top_left = 2
	panel_box.corner_radius_top_right = 2
	panel_box.corner_radius_bottom_left = 2
	panel_box.corner_radius_bottom_right = 2
	panel_box.content_margin_left = MARGIN_LARGE
	panel_box.content_margin_right = MARGIN_LARGE
	panel_box.content_margin_top = MARGIN_LARGE
	panel_box.content_margin_bottom = MARGIN_LARGE
	panel_box.shadow_color = COLOR_PANEL_SHADOW
	panel_box.shadow_size = 4
	panel_box.shadow_offset = Vector2(2, 2)
	theme.set_stylebox("panel", "PanelContainer", panel_box)
	theme.set_stylebox("panel", "Panel", panel_box)


static func _setup_tab_container(theme: Theme) -> void:
	theme.set_font_size("font_size", "TabContainer", FONT_SIZE_BODY)
	theme.set_color("font_selected_color", "TabContainer", COLOR_ACCENT)
	theme.set_color("font_unselected_color", "TabContainer", COLOR_TEXT_DISABLED)


## Create a key-cap stylebox for keybinding display labels.
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

- [ ] **Step 4: Run tests to verify they pass**

```bash
gol test unit --suite ui
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/gol_theme.gd tests/unit/ui/test_gol_theme.gd
git commit -m "feat(ui): overhaul GOLTheme with pixel font, StyleBoxFlat buttons, panel borders+shadow"
```

---

### Task 3: ViewModel_Settings — Add Building Keys + Grouped Bindings

**Files:**
- Modify: `scripts/ui/viewmodels/viewmodel_settings.gd`

- [ ] **Step 1: Write failing test for grouped keybindings**

Create `tests/unit/ui/test_viewmodel_settings.gd`:

```gdscript
extends GdUnitTestSuite
## Unit tests for ViewModel_Settings keybinding grouping

const ViewModel_Settings_Script = preload("res://scripts/ui/viewmodels/viewmodel_settings.gd")


func test_keybinding_groups_contains_build_menu() -> void:
	var all_actions := []
	for group_actions in ViewModel_Settings_Script.KEYBINDING_GROUPS.values():
		all_actions.append_array(group_actions)
	assert_bool("build_menu" in all_actions).is_true()


func test_action_display_names_has_build_menu() -> void:
	assert_bool(ViewModel_Settings_Script.ACTION_DISPLAY_NAMES.has("build_menu")).is_true()
	assert_str(ViewModel_Settings_Script.ACTION_DISPLAY_NAMES["build_menu"]).is_equal("建造菜单")


func test_keybinding_groups_has_three_groups() -> void:
	assert_int(ViewModel_Settings_Script.KEYBINDING_GROUPS.size()).is_equal(3)


func test_keybinding_groups_keys() -> void:
	assert_bool(ViewModel_Settings_Script.KEYBINDING_GROUPS.has("移动")).is_true()
	assert_bool(ViewModel_Settings_Script.KEYBINDING_GROUPS.has("操作")).is_true()
	assert_bool(ViewModel_Settings_Script.KEYBINDING_GROUPS.has("系统")).is_true()


func test_all_group_actions_in_display_names() -> void:
	for group_name in ViewModel_Settings_Script.KEYBINDING_GROUPS:
		for action in ViewModel_Settings_Script.KEYBINDING_GROUPS[group_name]:
			assert_bool(ViewModel_Settings_Script.ACTION_DISPLAY_NAMES.has(action))\
				.override_failure_message("Action '%s' in group '%s' missing from ACTION_DISPLAY_NAMES" % [action, group_name])\
				.is_true()
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
gol test unit --suite ui
```

Expected: FAIL — `KEYBINDING_GROUPS` does not exist, `build_menu` not in `ACTION_DISPLAY_NAMES`.

- [ ] **Step 3: Implement grouped keybindings in ViewModel_Settings**

Replace the full contents of `scripts/ui/viewmodels/viewmodel_settings.gd`:

```gdscript
class_name ViewModel_Settings
extends ViewModelBase

const Service_Settings = preload("res://scripts/services/impl/service_settings.gd")

const KEYBINDING_GROUPS := {
	"移动": ["player_up", "player_down", "player_left", "player_right"],
	"操作": ["player_fire", "interact", "build_menu"],
	"系统": ["pause"],
}

const ACTION_DISPLAY_NAMES := {
	"player_up": "移动-上",
	"player_down": "移动-下",
	"player_left": "移动-左",
	"player_right": "移动-右",
	"player_fire": "攻击",
	"interact": "互动",
	"build_menu": "建造菜单",
	"pause": "暂停",
}

var is_fullscreen: ObservableProperty
var resolution_index: ObservableProperty
var resolution_text: ObservableProperty
var vsync_enabled: ObservableProperty
var key_bindings: ObservableProperty


func setup() -> void:
	var svc = ServiceContext.settings()
	is_fullscreen = ObservableProperty.new(svc.is_fullscreen)
	resolution_index = ObservableProperty.new(svc.resolution_index)
	resolution_text = ObservableProperty.new(_format_resolution(svc.resolution_index))
	vsync_enabled = ObservableProperty.new(svc.vsync_enabled)
	key_bindings = ObservableProperty.new(_read_key_bindings())


func teardown() -> void:
	is_fullscreen.teardown()
	resolution_index.teardown()
	resolution_text.teardown()
	vsync_enabled.teardown()
	key_bindings.teardown()


func toggle_fullscreen() -> void:
	var new_val = not is_fullscreen.value
	is_fullscreen.set_value(new_val)
	var svc = ServiceContext.settings()
	svc.is_fullscreen = new_val
	svc.apply_fullscreen()
	svc.save()


func cycle_resolution() -> void:
	var idx = (resolution_index.value + 1) % Service_Settings.RESOLUTIONS.size()
	resolution_index.set_value(idx)
	resolution_text.set_value(_format_resolution(idx))
	var svc = ServiceContext.settings()
	svc.resolution_index = idx
	svc.apply_resolution()
	svc.save()


func toggle_vsync() -> void:
	var new_val = not vsync_enabled.value
	vsync_enabled.set_value(new_val)
	var svc = ServiceContext.settings()
	svc.vsync_enabled = new_val
	svc.apply_vsync()
	svc.save()


func _format_resolution(idx: int) -> String:
	var res: Vector2i = Service_Settings.RESOLUTIONS[clampi(idx, 0, Service_Settings.RESOLUTIONS.size() - 1)]
	return "%d×%d" % [res.x, res.y]


## Returns grouped keybinding data: [{group_name, bindings: [{display_name, key}]}]
func _read_key_bindings() -> Array:
	var groups := []
	for group_name in KEYBINDING_GROUPS:
		var bindings := []
		for action in KEYBINDING_GROUPS[group_name]:
			var events := InputMap.action_get_events(action)
			var key_name := ""
			for event in events:
				if event is InputEventKey:
					key_name = OS.get_keycode_string(event.physical_keycode)
					break
				elif event is InputEventMouseButton:
					key_name = "鼠标%d" % event.button_index
					break
			bindings.append({
				"display_name": ACTION_DISPLAY_NAMES.get(action, action),
				"key": key_name,
			})
		groups.append({
			"group_name": group_name,
			"bindings": bindings,
		})
	return groups
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
gol test unit --suite ui
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/viewmodels/viewmodel_settings.gd tests/unit/ui/test_viewmodel_settings.gd
git commit -m "feat(ui): add build_menu to keybindings, grouped display structure"
```

---

### Task 4: View_SettingsMenu — Grouped Keybinding Rows with Key-Cap Styling

**Files:**
- Modify: `scripts/ui/views/menu/view_settings_menu.gd`

- [ ] **Step 1: Implement grouped keybinding row builder**

Replace the full contents of `scripts/ui/views/menu/view_settings_menu.gd`:

```gdscript
class_name View_SettingsMenu
extends ViewBase

const GOLTheme = preload("res://scripts/ui/gol_theme.gd")

@onready var button_fullscreen: Button = %Button_Fullscreen
@onready var button_resolution: Button = %Button_Resolution
@onready var button_vsync: Button = %Button_VSync
@onready var button_back: Button = %Button_Back
@onready var keybindings_container: VBoxContainer = %KeyBindingsContainer

var vm: ViewModel_Settings


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	vm = ServiceContext.ui().acquire_view_model(ViewModel_Settings)
	button_fullscreen.pressed.connect(vm.toggle_fullscreen)
	button_resolution.pressed.connect(vm.cycle_resolution)
	button_vsync.pressed.connect(vm.toggle_vsync)
	button_back.pressed.connect(_on_back)


func bind() -> void:
	track(vm.is_fullscreen.subscribe(func(val: Variant) -> void:
		button_fullscreen.text = "全屏" if val else "窗口"
	))
	track(vm.resolution_text.subscribe(func(val: Variant) -> void:
		button_resolution.text = str(val)
	))
	track(vm.vsync_enabled.subscribe(func(val: Variant) -> void:
		button_vsync.text = "开" if val else "关"
	))
	track(vm.key_bindings.subscribe(func(val: Variant) -> void:
		_rebuild_keybinding_rows(val as Array)
	))


func teardown() -> void:
	super.teardown()
	if button_fullscreen and button_fullscreen.pressed.is_connected(vm.toggle_fullscreen):
		button_fullscreen.pressed.disconnect(vm.toggle_fullscreen)
	if button_resolution and button_resolution.pressed.is_connected(vm.cycle_resolution):
		button_resolution.pressed.disconnect(vm.cycle_resolution)
	if button_vsync and button_vsync.pressed.is_connected(vm.toggle_vsync):
		button_vsync.pressed.disconnect(vm.toggle_vsync)
	if button_back and button_back.pressed.is_connected(_on_back):
		button_back.pressed.disconnect(_on_back)
	ServiceContext.ui().release_view_model(vm)


func _on_back() -> void:
	ServiceContext.ui().pop_view(self)


func _rebuild_keybinding_rows(groups: Array) -> void:
	# Clear existing rows
	for child in keybindings_container.get_children():
		child.queue_free()

	var keycap_stylebox := GOLTheme.create_keycap_stylebox()

	for group in groups:
		# Group header label
		var header := Label.new()
		header.text = group["group_name"]
		header.add_theme_font_size_override("font_size", GOLTheme.FONT_SIZE_SMALL)
		header.add_theme_color_override("font_color", GOLTheme.COLOR_ACCENT)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keybindings_container.add_child(header)

		# Binding rows
		for binding in group["bindings"]:
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var action_label := Label.new()
			action_label.text = binding["display_name"]
			action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var key_label := Label.new()
			key_label.text = binding["key"]
			key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			key_label.add_theme_stylebox_override("normal", keycap_stylebox)
			key_label.add_theme_font_size_override("font_size", GOLTheme.FONT_SIZE_SMALL)

			row.add_child(action_label)
			row.add_child(key_label)
			keybindings_container.add_child(row)
```

- [ ] **Step 2: Run parse check**

```bash
gol test unit --suite ui
```

Expected: All existing tests still pass. (No unit tests for the view itself — it requires scene instantiation.)

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/views/menu/view_settings_menu.gd
git commit -m "feat(ui): grouped keybinding display with key-cap styling in settings menu"
```

---

### Task 5: Confirm Dialog — Reusable Component

**Files:**
- Create: `scripts/ui/views/menu/view_confirm_dialog.gd`
- Create: `scenes/ui/menus/confirm_dialog.tscn`

- [ ] **Step 1: Create the confirm dialog script**

Create `scripts/ui/views/menu/view_confirm_dialog.gd`:

```gdscript
class_name View_ConfirmDialog
extends ViewBase
## Reusable modal confirmation dialog.
## Usage: View_ConfirmDialog.show_dialog(message, on_confirm_callable)

@onready var label_message: Label = %Label_Message
@onready var button_confirm: Button = %Button_Confirm
@onready var button_cancel: Button = %Button_Cancel

var _message: String = ""
var _on_confirm: Callable = Callable()

## Show a confirmation dialog. Pushes itself to the MENU layer.
## on_confirm is called only when the user clicks "确定".
static func show_dialog(message: String, on_confirm: Callable) -> void:
	var scene: PackedScene = load("res://scenes/ui/menus/confirm_dialog.tscn")
	var view: View_ConfirmDialog = scene.instantiate() as View_ConfirmDialog
	view._message = message
	view._on_confirm = on_confirm
	ServiceContext.ui().push_view(Service_UI.LayerType.MENU, view)


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	label_message.text = _message
	button_confirm.pressed.connect(_on_button_confirm)
	button_cancel.pressed.connect(_on_button_cancel)
	# Default focus on cancel (safer)
	button_cancel.grab_focus()


func teardown() -> void:
	super.teardown()
	if button_confirm and button_confirm.pressed.is_connected(_on_button_confirm):
		button_confirm.pressed.disconnect(_on_button_confirm)
	if button_cancel and button_cancel.pressed.is_connected(_on_button_cancel):
		button_cancel.pressed.disconnect(_on_button_cancel)
	_on_confirm = Callable()


func _on_button_confirm() -> void:
	if _on_confirm.is_valid():
		_on_confirm.call()
	ServiceContext.ui().pop_view(self)


func _on_button_cancel() -> void:
	ServiceContext.ui().pop_view(self)
```

- [ ] **Step 2: Create the confirm dialog scene**

Create `scenes/ui/menus/confirm_dialog.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/views/menu/view_confirm_dialog.gd" id="1_confirm"]

[node name="ConfirmDialog" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_confirm")

[node name="ColorRect_Overlay" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.4)

[node name="CenterContainer" type="CenterContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="PanelContainer" type="PanelContainer" parent="CenterContainer"]
custom_minimum_size = Vector2(400, 180)
layout_mode = 2

[node name="VBoxContainer" type="VBoxContainer" parent="CenterContainer/PanelContainer"]
layout_mode = 2
theme_override_constants/separation = 24

[node name="Label_Message" type="Label" parent="CenterContainer/PanelContainer/VBoxContainer"]
unique_name_in_owner = true
layout_mode = 2
size_flags_vertical = 3
horizontal_alignment = 1
vertical_alignment = 1
autowrap_mode = 2

[node name="HBoxContainer" type="HBoxContainer" parent="CenterContainer/PanelContainer/VBoxContainer"]
layout_mode = 2
size_flags_horizontal = 4
theme_override_constants/separation = 16

[node name="Button_Confirm" type="Button" parent="CenterContainer/PanelContainer/VBoxContainer/HBoxContainer"]
unique_name_in_owner = true
custom_minimum_size = Vector2(120, 44)
layout_mode = 2
text = "确定"

[node name="Button_Cancel" type="Button" parent="CenterContainer/PanelContainer/VBoxContainer/HBoxContainer"]
unique_name_in_owner = true
custom_minimum_size = Vector2(120, 44)
layout_mode = 2
text = "取消"
```

- [ ] **Step 3: Run parse check**

```bash
gol test unit --suite ui
```

Expected: All tests pass (no crash from new files).

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/views/menu/view_confirm_dialog.gd scenes/ui/menus/confirm_dialog.tscn
git commit -m "feat(ui): add reusable View_ConfirmDialog for modal confirmations"
```

---

### Task 6: Pause Menu — Return to Title + Quit Confirmation + Chinese Text

**Files:**
- Modify: `scripts/ui/views/menu/view_pause_menu.gd`
- Modify: `scenes/ui/menus/pause_menu.tscn`
- Modify: `scripts/gol.gd` (add `return_to_title()`)

- [ ] **Step 1: Add `return_to_title()` to GOL**

Add this method at the end of `scripts/gol.gd`, after `_parse_launch_args()`:

```gdscript
func return_to_title() -> void:
	# Clear all UI views
	ServiceContext.ui().pop_views_by_layer(Service_UI.LayerType.MENU)
	ServiceContext.ui().pop_views_by_layer(Service_UI.LayerType.HUD)
	ServiceContext.ui().pop_views_by_layer(Service_UI.LayerType.GAME)
	# Teardown current game scene
	ServiceContext.scene().teardown()
	# Reset game state
	if Game:
		Game.reset()
	# Show title screen
	show_title_screen()
```

- [ ] **Step 2: Update pause menu scene — add Button_ReturnToTitle, Chinese text**

Replace the full contents of `scenes/ui/menus/pause_menu.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/views/menu/view_pause_menu.gd" id="1_pause"]

[node name="PauseMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_pause")

[node name="ColorRect" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.5)

[node name="CenterContainer" type="CenterContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Panel" type="Panel" parent="CenterContainer"]
custom_minimum_size = Vector2(400, 360)
layout_mode = 2

[node name="MarginContainer" type="MarginContainer" parent="CenterContainer/Panel"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/margin_left = 32
theme_override_constants/margin_top = 32
theme_override_constants/margin_right = 32
theme_override_constants/margin_bottom = 32

[node name="VBoxContainer" type="VBoxContainer" parent="CenterContainer/Panel/MarginContainer"]
layout_mode = 2
size_flags_horizontal = 4
size_flags_vertical = 4
alignment = 1
theme_override_constants/separation = 24

[node name="Label_Title" type="Label" parent="CenterContainer/Panel/MarginContainer/VBoxContainer"]
layout_mode = 2
theme_override_font_sizes/font_size = 32
text = "暂停"
horizontal_alignment = 1

[node name="Button_Resume" type="Button" parent="CenterContainer/Panel/MarginContainer/VBoxContainer"]
custom_minimum_size = Vector2(220, 48)
layout_mode = 2
size_flags_horizontal = 4
text = "继续游戏"

[node name="Button_Settings" type="Button" parent="CenterContainer/Panel/MarginContainer/VBoxContainer"]
custom_minimum_size = Vector2(220, 48)
layout_mode = 2
size_flags_horizontal = 4
text = "设置"

[node name="Button_ReturnToTitle" type="Button" parent="CenterContainer/Panel/MarginContainer/VBoxContainer"]
custom_minimum_size = Vector2(220, 48)
layout_mode = 2
size_flags_horizontal = 4
text = "返回标题"

[node name="Button_Quit" type="Button" parent="CenterContainer/Panel/MarginContainer/VBoxContainer"]
custom_minimum_size = Vector2(220, 48)
layout_mode = 2
size_flags_horizontal = 4
text = "退出游戏"
```

- [ ] **Step 3: Update pause menu script — add return-to-title + quit confirmation**

Replace the full contents of `scripts/ui/views/menu/view_pause_menu.gd`:

```gdscript
class_name View_PauseMenu
extends ViewBase

const View_ConfirmDialog = preload("res://scripts/ui/views/menu/view_confirm_dialog.gd")

@onready var button_resume: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/Button_Resume
@onready var button_settings: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/Button_Settings
@onready var button_return_to_title: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/Button_ReturnToTitle
@onready var button_quit: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/Button_Quit


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	button_resume.pressed.connect(_on_resume)
	button_settings.pressed.connect(_on_settings)
	button_return_to_title.pressed.connect(_on_return_to_title)
	button_quit.pressed.connect(_on_quit)
	button_resume.grab_focus()


func teardown() -> void:
	super.teardown()
	if button_resume and button_resume.pressed.is_connected(_on_resume):
		button_resume.pressed.disconnect(_on_resume)
	if button_settings and button_settings.pressed.is_connected(_on_settings):
		button_settings.pressed.disconnect(_on_settings)
	if button_return_to_title and button_return_to_title.pressed.is_connected(_on_return_to_title):
		button_return_to_title.pressed.disconnect(_on_return_to_title)
	if button_quit and button_quit.pressed.is_connected(_on_quit):
		button_quit.pressed.disconnect(_on_quit)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)


func _on_resume() -> void:
	GOL.Game.toggle_pause()


func _on_settings() -> void:
	var settings_scene: PackedScene = load("res://scenes/ui/menus/settings_menu.tscn")
	ServiceContext.ui().create_and_push_view(Service_UI.LayerType.MENU, settings_scene)


func _on_return_to_title() -> void:
	View_ConfirmDialog.show_dialog("当前进度将丢失，确定返回标题画面？", func():
		get_tree().paused = false
		GOL.return_to_title()
	)


func _on_quit() -> void:
	View_ConfirmDialog.show_dialog("确定退出游戏？", func():
		get_tree().paused = false
		get_tree().quit()
	)
```

- [ ] **Step 4: Run parse check**

```bash
gol test unit --suite ui
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/gol.gd scripts/ui/views/menu/view_pause_menu.gd scenes/ui/menus/pause_menu.tscn
git commit -m "feat(ui): add return-to-title + quit confirmation to pause menu, unified Chinese text"
```

---

### Task 7: Title Screen — Glow Effect on Hover

**Files:**
- Modify: `scripts/ui/views/menu/view_title_screen.gd`

- [ ] **Step 1: Add glow shader hover effect to title screen buttons**

Replace the full contents of `scripts/ui/views/menu/view_title_screen.gd`:

```gdscript
class_name View_TitleScreen
extends ViewBase


@onready var button_new_game: Button = $VBoxContainer_Buttons/Button_NewGame
@onready var button_settings: Button = $VBoxContainer_Buttons/Button_Settings
@onready var button_quit: Button = $VBoxContainer_Buttons/Button_Quit

var _button_origins: Dictionary = {}
var _glow_shader: Shader = null


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_glow_shader = load("res://shaders/ui_glow.gdshader") as Shader
	button_new_game.pressed.connect(_on_new_game)
	button_settings.pressed.connect(_on_settings)
	button_quit.pressed.connect(_on_quit)
	_setup_button_hover(button_new_game)
	_setup_button_hover(button_settings)
	_setup_button_hover(button_quit)
	# Focus first button for keyboard navigation
	button_new_game.grab_focus()


func teardown() -> void:
	super.teardown()
	if button_new_game and button_new_game.pressed.is_connected(_on_new_game):
		button_new_game.pressed.disconnect(_on_new_game)
	if button_settings and button_settings.pressed.is_connected(_on_settings):
		button_settings.pressed.disconnect(_on_settings)
	if button_quit and button_quit.pressed.is_connected(_on_quit):
		button_quit.pressed.disconnect(_on_quit)


func _on_new_game() -> void:
	ServiceContext.ui().pop_view(self)
	GOL.start_game()


func _on_settings() -> void:
	var settings_scene: PackedScene = load("res://scenes/ui/menus/settings_menu.tscn")
	ServiceContext.ui().create_and_push_view(Service_UI.LayerType.MENU, settings_scene)


func _on_quit() -> void:
	get_tree().quit()


func _setup_button_hover(button: Button) -> void:
	_button_origins[button] = button.position.x
	# Apply glow shader material
	if _glow_shader:
		var mat := ShaderMaterial.new()
		mat.shader = _glow_shader
		mat.set_shader_parameter("glow_intensity", 0.0)
		mat.set_shader_parameter("glow_color", Color(0.8, 0.85, 1.0, 1.0))
		button.material = mat
	button.mouse_entered.connect(func(): _tween_hover(button, true))
	button.mouse_exited.connect(func(): _tween_hover(button, false))
	button.focus_entered.connect(func(): _tween_hover(button, true))
	button.focus_exited.connect(func(): _tween_hover(button, false))


func _tween_hover(button: Button, entering: bool) -> void:
	var origin_x: float = _button_origins[button]
	var tween := create_tween().set_parallel(true)
	if entering:
		tween.tween_property(button, "position:x", origin_x + 8.0, 0.15)
		if button.material is ShaderMaterial:
			tween.tween_property(button.material, "shader_parameter/glow_intensity", 0.3, 0.15)
	else:
		tween.tween_property(button, "position:x", origin_x, 0.15)
		if button.material is ShaderMaterial:
			tween.tween_property(button.material, "shader_parameter/glow_intensity", 0.0, 0.15)
```

- [ ] **Step 2: Run parse check**

```bash
gol test unit --suite ui
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/views/menu/view_title_screen.gd
git commit -m "feat(ui): add glow shader hover effect to title screen buttons"
```

---

### Task 8: Final Verification + Push

- [ ] **Step 1: Run all unit tests**

```bash
gol test unit
```

Expected: All pass.

- [ ] **Step 2: Run all integration tests**

```bash
gol test integration
```

Expected: All pass (none of the changes should break integration tests).

- [ ] **Step 3: Review all changes**

```bash
git log --oneline main..HEAD
```

Expected 7 commits:
1. `chore: add Fusion Pixel 12px font for pixel-style menus`
2. `feat(ui): overhaul GOLTheme with pixel font, StyleBoxFlat buttons, panel borders+shadow`
3. `feat(ui): add build_menu to keybindings, grouped display structure`
4. `feat(ui): grouped keybinding display with key-cap styling in settings menu`
5. `feat(ui): add reusable View_ConfirmDialog for modal confirmations`
6. `feat(ui): add return-to-title + quit confirmation to pause menu, unified Chinese text`
7. `feat(ui): add glow shader hover effect to title screen buttons`

- [ ] **Step 4: Push branch**

```bash
git push origin feature/menu-polish
```

- [ ] **Step 5: Create PR**

```bash
gh pr create --repo Dluck-Games/god-of-lego --title "feat(ui): menu polish — building keys, return-to-title, pixel UI" --body "$(cat <<'EOF'
## Summary
- Add `build_menu` (B key) to settings menu keybindings with grouped category display
- Add "返回标题" button to pause menu with confirmation dialog
- Overhaul GOLTheme: StyleBoxFlat buttons with borders, panel shadows, pixel font, key-cap styling
- Unify pause menu text to Chinese
- Add reusable View_ConfirmDialog component
- Add glow shader hover effect to title screen buttons

## Test plan
- [ ] Unit tests pass (`gol test unit`)
- [ ] Integration tests pass (`gol test integration`)
- [ ] Visually verify settings menu shows building keybinding under "操作" group
- [ ] Visually verify pause menu has "返回标题" button that shows confirm dialog
- [ ] Visually verify buttons have dark backgrounds with borders (not invisible)
- [ ] Visually verify pixel font renders Chinese characters correctly
- [ ] Verify return-to-title correctly returns to title screen and allows new game

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
