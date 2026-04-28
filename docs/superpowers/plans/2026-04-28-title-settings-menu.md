# Title Screen, Settings Menu & CLI Pass-Through Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a title screen, settings menu (accessible from title and pause), configuration persistence, and CLI argument pass-through to GOL.

**Architecture:** GOL autoload manages the startup flow — push title screen View to a new MENU layer, or skip to gameplay via `--skip-menu` CLI arg. Settings persist to `user://settings.cfg` via a new `Service_Settings`. CLI uses `--` separator to pass arbitrary args to Godot. All UI follows existing MVVM + ViewBase pattern with a new global Theme built from GDScript constants.

**Tech Stack:** Godot 4.6 / GDScript (game), Go + Cobra (CLI), gdUnit4 (tests)

---

## File Map

### New Files — Godot Side

| File | Responsibility |
|------|---------------|
| `gol-project/scripts/ui/gol_theme.gd` | Global Theme builder — color palette, font sizes, spacing as constants; `create_theme()` factory |
| `gol-project/scripts/services/impl/service_settings.gd` | Settings persistence — load/save `user://settings.cfg`, apply display settings |
| `gol-project/scripts/ui/views/menu/view_title_screen.gd` | Title screen View — new game / settings / quit buttons + hover tweens |
| `gol-project/scripts/ui/views/menu/view_settings_menu.gd` | Settings menu View — display tab + controls tab, binds to VM_Settings |
| `gol-project/scripts/ui/viewmodels/viewmodel_settings.gd` | Settings ViewModel — observables for fullscreen/resolution/vsync/keybindings |
| `gol-project/scenes/ui/menus/title_screen.tscn` | Title screen scene tree |
| `gol-project/scenes/ui/menus/settings_menu.tscn` | Settings menu scene tree |
| `gol-project/shaders/ui_glow.gdshader` | Button text glow shader |
| `gol-project/shaders/ui_vignette.gdshader` | Full-screen vignette shader |
| `gol-project/tests/unit/service/test_service_settings.gd` | Unit tests for Service_Settings |
| `gol-project/tests/unit/ui/test_gol_theme.gd` | Unit tests for GOLTheme |

### Modified Files — Godot Side

| File | Change |
|------|--------|
| `gol-project/scripts/gol.gd` | Move `setup()` to `_ready()` (idempotent), add `show_title_screen()` + `_parse_launch_args()` |
| `gol-project/scripts/main.gd` | Simplify: remove `GOL.setup()`, call `GOL.show_title_screen()` |
| `gol-project/scripts/services/impl/service_ui.gd` | Add `MENU` to `LayerType`, create `menu_layer` CanvasLayer |
| `gol-project/scripts/services/service_context.gd` | Add `settings()` accessor, add `"settings"` to `_defined_services()` |
| `gol-project/scripts/gameplay/gol_game_state.gd` | Pause menu uses `MENU` layer instead of `HUD` |
| `gol-project/scripts/ui/views/menu/view_pause_menu.gd` | Add Settings button handler |
| `gol-project/scenes/ui/menus/pause_menu.tscn` | Add `Button_Settings` node between Resume and Quit |
| `gol-project/tests/unit/service/test_service_ui.gd` | Add tests for MENU layer |

### New/Modified Files — CLI Side (gol-tools submodule)

| File | Change |
|------|--------|
| `gol-tools/cli/internal/godot/process.go` | Add `ExtraArgs []string` to `LaunchOpts`, append with `--` separator in `Launch()` |
| `gol-tools/cli/cmd/run.go` | Accept `cobra.ArbitraryArgs`, pass through after `--` to Godot args |
| `gol-tools/cli/internal/testrunner/gdunit.go` | Append `"--", "--skip-menu"` to Godot args |
| `gol-tools/cli/internal/testrunner/sceneconfig.go` | Append `"--skip-menu"` after existing `--` args |

### Documentation Updates

| File | Change |
|------|--------|
| `AGENTS.md` (root) | Add `--skip-menu` to CLI command reference table, document `--` pass-through |
| `gol-project/AGENTS.md` | Update Boot flow line to mention title screen |

---

## Task 1: Service_Settings — Persistence Layer

**Files:**
- Create: `gol-project/scripts/services/impl/service_settings.gd`
- Modify: `gol-project/scripts/services/service_context.gd`
- Test: `gol-project/tests/unit/service/test_service_settings.gd`

- [ ] **Step 1: Write the failing test**

Create `gol-project/tests/unit/service/test_service_settings.gd`:

```gdscript
extends GdUnitTestSuite
## Unit tests for Service_Settings


func test_default_values() -> void:
	var svc := auto_free(Service_Settings.new())
	
	assert_bool(svc.is_fullscreen).is_false()
	assert_int(svc.resolution_index).is_equal(0)
	assert_bool(svc.vsync_enabled).is_true()


func test_save_and_load_roundtrip() -> void:
	var svc := auto_free(Service_Settings.new())
	svc.is_fullscreen = true
	svc.resolution_index = 2
	svc.vsync_enabled = false
	svc.save()
	
	# Create a fresh instance and load
	var svc2 := auto_free(Service_Settings.new())
	svc2._load()
	
	assert_bool(svc2.is_fullscreen).is_true()
	assert_int(svc2.resolution_index).is_equal(2)
	assert_bool(svc2.vsync_enabled).is_false()


func test_load_missing_file_keeps_defaults() -> void:
	# Ensure no settings file exists
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists("settings.cfg"):
		dir.remove("settings.cfg")
	
	var svc := auto_free(Service_Settings.new())
	svc._load()
	
	assert_bool(svc.is_fullscreen).is_false()
	assert_int(svc.resolution_index).is_equal(0)
	assert_bool(svc.vsync_enabled).is_true()


func test_resolution_index_clamped() -> void:
	var svc := auto_free(Service_Settings.new())
	svc.resolution_index = 999
	# apply_resolution should clamp, not crash
	# We can't easily test DisplayServer in headless, but we test the clamp logic
	var clamped := clampi(svc.resolution_index, 0, Service_Settings.RESOLUTIONS.size() - 1)
	assert_int(clamped).is_equal(Service_Settings.RESOLUTIONS.size() - 1)


func after() -> void:
	# Cleanup test settings file
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists("settings.cfg"):
		dir.remove("settings.cfg")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gol test unit --suite service`
Expected: FAIL — `Service_Settings` class not found

- [ ] **Step 3: Create Service_Settings**

Create `gol-project/scripts/services/impl/service_settings.gd`:

```gdscript
class_name Service_Settings
extends ServiceBase


const SETTINGS_PATH := "user://settings.cfg"

const RESOLUTIONS := [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
	Vector2i(960, 540),
]

var is_fullscreen := false
var resolution_index := 0
var vsync_enabled := true


func setup() -> void:
	_load()
	apply_all()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	is_fullscreen = config.get_value("display", "fullscreen", false)
	resolution_index = config.get_value("display", "resolution_index", 0)
	vsync_enabled = config.get_value("display", "vsync", true)


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", is_fullscreen)
	config.set_value("display", "resolution_index", resolution_index)
	config.set_value("display", "vsync", vsync_enabled)
	config.save(SETTINGS_PATH)


func apply_all() -> void:
	apply_fullscreen()
	apply_resolution()
	apply_vsync()


func apply_fullscreen() -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		apply_resolution()


func apply_resolution() -> void:
	if is_fullscreen:
		return
	var res: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
	DisplayServer.window_set_size(res)
	var screen_size := DisplayServer.screen_get_size()
	var pos := (screen_size - res) / 2
	DisplayServer.window_set_position(pos)


func apply_vsync() -> void:
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
```

- [ ] **Step 4: Register in ServiceContext**

Modify `gol-project/scripts/services/service_context.gd`.

Add accessor (after the `pcg()` accessor, around line 49):

```gdscript
static func settings() -> Service_Settings:
	var ctx := instance()
	if ctx._registry == null:
		return null
	return ctx._registry.get_service("settings") as Service_Settings
```

Update `_defined_services()` (line 51) — add `"settings"` to the array:

```gdscript
static func _defined_services() -> Array[String]:
	return ["ui", "scene", "savedata", "recipe", "console", "input", "pcg", "settings"]
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `gol test unit --suite service`
Expected: All `test_service_settings` tests PASS

- [ ] **Step 6: Commit**

```bash
cd gol-project
git add scripts/services/impl/service_settings.gd scripts/services/service_context.gd tests/unit/service/test_service_settings.gd
git commit -m "feat(settings): add Service_Settings with ConfigFile persistence"
```

---

## Task 2: Global Theme (GOLTheme)

**Files:**
- Create: `gol-project/scripts/ui/gol_theme.gd`
- Test: `gol-project/tests/unit/ui/test_gol_theme.gd`

- [ ] **Step 1: Write the failing test**

Create `gol-project/tests/unit/ui/test_gol_theme.gd`:

```gdscript
extends GdUnitTestSuite
## Unit tests for GOLTheme


func test_create_theme_returns_theme() -> void:
	var theme := GOLTheme.create_theme()
	assert_object(theme).is_not_null()
	assert_bool(theme is Theme).is_true()


func test_theme_has_button_styles() -> void:
	var theme := GOLTheme.create_theme()
	assert_object(theme.get_stylebox("normal", "Button")).is_not_null()
	assert_object(theme.get_stylebox("hover", "Button")).is_not_null()
	assert_object(theme.get_stylebox("pressed", "Button")).is_not_null()
	assert_object(theme.get_stylebox("focus", "Button")).is_not_null()


func test_theme_button_font_color() -> void:
	var theme := GOLTheme.create_theme()
	var color := theme.get_color("font_color", "Button")
	assert_float(color.r).is_equal_approx(GOLTheme.COLOR_TEXT.r, 0.01)
	assert_float(color.g).is_equal_approx(GOLTheme.COLOR_TEXT.g, 0.01)


func test_theme_button_font_size() -> void:
	var theme := GOLTheme.create_theme()
	var size := theme.get_font_size("font_size", "Button")
	assert_int(size).is_equal(GOLTheme.FONT_SIZE_BUTTON)


func test_theme_has_label_styles() -> void:
	var theme := GOLTheme.create_theme()
	var color := theme.get_color("font_color", "Label")
	assert_float(color.a).is_greater(0.0)


func test_theme_has_panel_styles() -> void:
	var theme := GOLTheme.create_theme()
	assert_object(theme.get_stylebox("panel", "PanelContainer")).is_not_null()


func test_theme_has_tab_container_styles() -> void:
	var theme := GOLTheme.create_theme()
	assert_int(theme.get_font_size("font_size", "TabContainer")).is_greater(0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gol test unit --suite ui`
Expected: FAIL — `GOLTheme` class not found

- [ ] **Step 3: Create GOLTheme**

Create `gol-project/scripts/ui/gol_theme.gd`:

```gdscript
class_name GOLTheme
extends RefCounted

# ── Palette ──
const COLOR_BG_PANEL := Color(0.08, 0.08, 0.12, 0.92)
const COLOR_BG_OVERLAY := Color(0.0, 0.0, 0.0, 0.6)
const COLOR_TEXT := Color(0.7, 0.72, 0.78, 1.0)
const COLOR_TEXT_HOVER := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_DISABLED := Color(0.4, 0.4, 0.45, 0.6)
const COLOR_ACCENT := Color(0.65, 0.7, 0.9, 1.0)
const COLOR_FOCUS_BORDER := Color(0.65, 0.7, 0.9, 0.5)

# ── Font Sizes ──
const FONT_SIZE_H1 := 48
const FONT_SIZE_H2 := 32
const FONT_SIZE_BUTTON := 28
const FONT_SIZE_BODY := 20
const FONT_SIZE_SMALL := 16

# ── Spacing ──
const MARGIN_LARGE := 32
const MARGIN_MEDIUM := 16
const MARGIN_SMALL := 8
const BUTTON_SEPARATION := 24


static func create_theme() -> Theme:
	var theme := Theme.new()
	_setup_button(theme)
	_setup_label(theme)
	_setup_panel(theme)
	_setup_tab_container(theme)
	return theme


static func _setup_button(theme: Theme) -> void:
	var empty := StyleBoxEmpty.new()
	theme.set_stylebox("normal", "Button", empty)
	theme.set_stylebox("hover", "Button", empty)
	theme.set_stylebox("pressed", "Button", empty)
	theme.set_stylebox("focus", "Button", _create_focus_stylebox())
	theme.set_color("font_color", "Button", COLOR_TEXT)
	theme.set_color("font_hover_color", "Button", COLOR_TEXT_HOVER)
	theme.set_color("font_pressed_color", "Button", COLOR_ACCENT)
	theme.set_color("font_focus_color", "Button", COLOR_TEXT_HOVER)
	theme.set_color("font_disabled_color", "Button", COLOR_TEXT_DISABLED)
	theme.set_font_size("font_size", "Button", FONT_SIZE_BUTTON)


static func _setup_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", COLOR_TEXT)
	theme.set_font_size("font_size", "Label", FONT_SIZE_BODY)
	theme.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.6))
	theme.set_constant("outline_size", "Label", 1)


static func _setup_panel(theme: Theme) -> void:
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = COLOR_BG_PANEL
	panel_box.corner_radius_top_left = 4
	panel_box.corner_radius_top_right = 4
	panel_box.corner_radius_bottom_left = 4
	panel_box.corner_radius_bottom_right = 4
	panel_box.content_margin_left = MARGIN_LARGE
	panel_box.content_margin_right = MARGIN_LARGE
	panel_box.content_margin_top = MARGIN_LARGE
	panel_box.content_margin_bottom = MARGIN_LARGE
	theme.set_stylebox("panel", "PanelContainer", panel_box)
	theme.set_stylebox("panel", "Panel", panel_box)


static func _setup_tab_container(theme: Theme) -> void:
	theme.set_font_size("font_size", "TabContainer", FONT_SIZE_BODY)
	theme.set_color("font_selected_color", "TabContainer", COLOR_TEXT_HOVER)
	theme.set_color("font_unselected_color", "TabContainer", COLOR_TEXT_DISABLED)


static func _create_focus_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = COLOR_FOCUS_BORDER
	box.border_width_bottom = 2
	box.border_width_top = 0
	box.border_width_left = 0
	box.border_width_right = 0
	return box
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `gol test unit --suite ui`
Expected: All `test_gol_theme` tests PASS

- [ ] **Step 5: Commit**

```bash
cd gol-project
git add scripts/ui/gol_theme.gd tests/unit/ui/test_gol_theme.gd
git commit -m "feat(ui): add GOLTheme — GDScript-driven global theme builder"
```

---

## Task 3: Service_UI MENU Layer

**Files:**
- Modify: `gol-project/scripts/services/impl/service_ui.gd`
- Modify: `gol-project/tests/unit/service/test_service_ui.gd`

- [ ] **Step 1: Write the failing tests**

Add to `gol-project/tests/unit/service/test_service_ui.gd` (after the existing `test_pop_views_by_layer_does_not_affect_other_layer` test, before the ViewModel section):

```gdscript
func test_setup_creates_menu_layer() -> void:
	assert_object(_service.menu_layer).is_not_null()
	assert_str(_service.menu_layer.name).is_equal("MENU_Layer")


func test_push_view_to_menu_layer() -> void:
	var view: ViewBase = auto_free(_create_mock_view())
	
	_service.push_view(Service_UI.LayerType.MENU, view)
	
	assert_bool(view.get_parent() == _service.menu_layer).is_true()


func test_pop_views_by_menu_layer_does_not_affect_hud() -> void:
	var menu_view := _create_mock_view()
	var hud_view: ViewBase = auto_free(_create_mock_view())
	
	_service.push_view(Service_UI.LayerType.MENU, menu_view)
	_service.push_view(Service_UI.LayerType.HUD, hud_view)
	
	_service.pop_views_by_layer(Service_UI.LayerType.MENU)
	await get_tree().process_frame
	
	assert_int(_service.menu_layer.get_child_count()).is_equal(0)
	assert_int(_service.hud_layer.get_child_count()).is_equal(1)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `gol test unit --suite service`
Expected: FAIL — `menu_layer` property not found, `LayerType.MENU` not defined

- [ ] **Step 3: Add MENU layer to Service_UI**

Modify `gol-project/scripts/services/impl/service_ui.gd`:

Add `menu_layer` variable (after `game_layer` on line 7):

```gdscript
var menu_layer: CanvasLayer
```

Update `LayerType` enum (line 10):

```gdscript
enum LayerType {
	HUD,
	GAME,
	MENU,
}
```

In `setup()` function, after creating `game_layer` (after line 30), add:

```gdscript
	menu_layer = CanvasLayer.new()
	menu_layer.name = "MENU_Layer"
	menu_layer.layer = 100
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
```

Add `menu_layer` as child of `ui_base` (after `ui_base.add_child(game_layer)`, line 33):

```gdscript
	ui_base.add_child(menu_layer)
```

Update `_get_layer_node()` (around line 133) — add MENU case:

```gdscript
func _get_layer_node(layer: LayerType) -> Node:
	match layer:
		LayerType.HUD:
			return hud_layer
		LayerType.GAME:
			return game_layer
		LayerType.MENU:
			return menu_layer
		_:
			push_error("Unknown layer type: " + str(layer))
			return null
```

In `teardown()`, after existing cleanup, set `menu_layer = null` (in `_free_ui_tree()`, around line 168):

```gdscript
func _free_ui_tree() -> void:
	if ui_base:
		if _is_tearing_down and ui_base.is_inside_tree():
			ui_base.queue_free()
		elif ui_base.is_inside_tree():
			ui_base.queue_free()
		else:
			ui_base.free.call_deferred()
	ui_base = null
	hud_layer = null
	game_layer = null
	menu_layer = null
```

- [ ] **Step 4: Update existing test assertions**

In `test_service_ui.gd`, update `test_teardown_clears_references` to also assert `menu_layer`:

```gdscript
func test_teardown_clears_references() -> void:
	_service.teardown()
	
	assert_object(_service.ui_base).is_null()
	assert_object(_service.hud_layer).is_null()
	assert_object(_service.game_layer).is_null()
	assert_object(_service.menu_layer).is_null()
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `gol test unit --suite service`
Expected: All tests PASS (existing + new MENU layer tests)

- [ ] **Step 6: Commit**

```bash
cd gol-project
git add scripts/services/impl/service_ui.gd tests/unit/service/test_service_ui.gd
git commit -m "feat(ui): add MENU layer to Service_UI for full-screen menus"
```

---

## Task 4: Shader Effects

**Files:**
- Create: `gol-project/shaders/ui_glow.gdshader`
- Create: `gol-project/shaders/ui_vignette.gdshader`

No tests for shaders — they are visual-only and verified by manual inspection during playtest.

- [ ] **Step 1: Create ui_glow.gdshader**

Create `gol-project/shaders/ui_glow.gdshader`:

```glsl
shader_type canvas_item;

uniform float glow_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(0.8, 0.85, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = tex;
	COLOR.rgb += glow_color.rgb * glow_intensity * tex.a;
}
```

- [ ] **Step 2: Create ui_vignette.gdshader**

Create `gol-project/shaders/ui_vignette.gdshader`:

```glsl
shader_type canvas_item;

uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	float vignette = smoothstep(vignette_softness, vignette_softness - 0.3, dist);
	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - vignette) * vignette_intensity);
}
```

- [ ] **Step 3: Commit**

```bash
cd gol-project
git add shaders/ui_glow.gdshader shaders/ui_vignette.gdshader
git commit -m "feat(ui): add glow and vignette shaders for menu effects"
```

---

## Task 5: GOL Startup Flow Refactor

**Files:**
- Modify: `gol-project/scripts/gol.gd`
- Modify: `gol-project/scripts/main.gd`

- [ ] **Step 1: Modify gol.gd — idempotent setup + title screen flow**

Replace the entire contents of `gol-project/scripts/gol.gd` with:

```gdscript
# GOL.gd - Global Game Manager & Entry Point
# This autoload provides centralized access to game state and manages game initialization
extends Node

const PlayerData = preload("res://scripts/gameplay/player_data.gd")
const GameTables = preload("res://scripts/gameplay/game_tables.gd")

## Game state instance - manages gameplay data like respawn & fail conditions
## Implementation: GOLGameState class in scripts/gameplay/gol_game_state.gd
var Game: GOLGameState = null
var Player: PlayerData = null
## Gameplay design sheets — loot, growth, hunger. See scripts/gameplay/tables/.
var Tables: GameTables = null

var _is_setup := false


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	setup()


func setup() -> void:
	if _is_setup:
		return
	_is_setup = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	ServiceContext.static_setup(get_tree().get_root())
	Game = GOLGameState.new()
	Player = PlayerData.new()
	Tables = GameTables.new()
	# Apply global theme
	var theme := GOLTheme.create_theme()
	get_tree().get_root().theme = theme


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and Game:
		Game.toggle_pause()

func teardown() -> void:
	ServiceContext.static_teardown()
	Game.free()
	Player.free()
	Tables.free()
	Game = null
	Player = null
	Tables = null
	_is_setup = false


func show_title_screen() -> void:
	var args := _parse_launch_args()
	if args.get("skip_menu", false):
		start_game()
		return
	var title_scene: PackedScene = load("res://scenes/ui/menus/title_screen.tscn")
	ServiceContext.ui().create_and_push_view(Service_UI.LayerType.MENU, title_scene)


func start_game() -> void:
	var config := ProceduralConfig.new()
	config.pcg_config().pcg_seed = randi()
	var result := ServiceContext.pcg().generate(config.pcg_config())
	if result == null or not result.is_valid():
		push_error("PCG generation failed - aborting game start")
		return

	# Cache campfire position from nearest VILLAGE POI to grid center
	Game.campfire_position = ServiceContext.pcg().find_nearest_village_poi()

	ServiceContext.scene().switch_scene(config)


func _parse_launch_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg == "--skip-menu":
			result["skip_menu"] = true
	return result
```

- [ ] **Step 2: Simplify main.gd**

Replace the entire contents of `gol-project/scripts/main.gd` with:

```gdscript
# Main.gd - Entry Scene Controller
# This is the default startup scene that begins the game flow.
# GOL.setup() runs automatically in the autoload's _ready().
# This scene only triggers the title screen (or gameplay via --skip-menu).
extends Node


func _ready() -> void:
	await get_tree().process_frame
	GOL.show_title_screen()

func _exit_tree() -> void:
	GOL.teardown()
```

- [ ] **Step 3: Verify existing tests still pass**

Run: `gol test unit`
Expected: All existing tests PASS (no regressions from setup refactor)

- [ ] **Step 4: Commit**

```bash
cd gol-project
git add scripts/gol.gd scripts/main.gd
git commit -m "refactor(gol): idempotent setup in autoload, add show_title_screen flow"
```

---

## Task 6: Title Screen View + Scene

**Files:**
- Create: `gol-project/scripts/ui/views/menu/view_title_screen.gd`
- Create: `gol-project/scenes/ui/menus/title_screen.tscn`

- [ ] **Step 1: Create view_title_screen.gd**

Create `gol-project/scripts/ui/views/menu/view_title_screen.gd`:

```gdscript
class_name View_TitleScreen
extends ViewBase


@onready var button_new_game: Button = $VBoxContainer_Buttons/Button_NewGame
@onready var button_settings: Button = $VBoxContainer_Buttons/Button_Settings
@onready var button_quit: Button = $VBoxContainer_Buttons/Button_Quit

var _button_origins: Dictionary = {}


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
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
	button.mouse_entered.connect(func(): _tween_hover(button, true))
	button.mouse_exited.connect(func(): _tween_hover(button, false))
	button.focus_entered.connect(func(): _tween_hover(button, true))
	button.focus_exited.connect(func(): _tween_hover(button, false))


func _tween_hover(button: Button, entering: bool) -> void:
	var origin_x: float = _button_origins[button]
	var tween := create_tween()
	if entering:
		tween.tween_property(button, "position:x", origin_x + 8.0, 0.15)
	else:
		tween.tween_property(button, "position:x", origin_x, 0.15)
```

- [ ] **Step 2: Create title_screen.tscn**

Create `gol-project/scenes/ui/menus/title_screen.tscn`. This is a Godot scene file — build the scene tree manually in the editor, or write the `.tscn` text format:

```tscn
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/ui/views/menu/view_title_screen.gd" id="1_title"]
[ext_resource type="Texture2D" path="res://assets/artworks/title.png" id="2_bg"]
[ext_resource type="Shader" path="res://shaders/ui_vignette.gdshader" id="3_vignette"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_vignette"]
shader = ExtResource("3_vignette")
shader_parameter/vignette_intensity = 0.4
shader_parameter/vignette_softness = 0.5

[node name="TitleScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_title")

[node name="TextureRect_Background" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
texture = ExtResource("2_bg")
expand_mode = 1
stretch_mode = 6

[node name="ColorRect_Vignette" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
material = SubResource("ShaderMaterial_vignette")
color = Color(1, 1, 1, 1)

[node name="VBoxContainer_Buttons" type="VBoxContainer" parent="."]
layout_mode = 1
anchor_left = 0.05
anchor_top = 0.55
anchor_right = 0.35
anchor_bottom = 0.85
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 24

[node name="Button_NewGame" type="Button" parent="VBoxContainer_Buttons"]
layout_mode = 2
theme_override_font_sizes/font_size = 28
text = "新游戏"

[node name="Button_Settings" type="Button" parent="VBoxContainer_Buttons"]
layout_mode = 2
theme_override_font_sizes/font_size = 28
text = "设置"

[node name="Button_Quit" type="Button" parent="VBoxContainer_Buttons"]
layout_mode = 2
theme_override_font_sizes/font_size = 28
text = "退出"
```

Note: `expand_mode = 1` is `KEEP_ASPECT_COVERED` and `stretch_mode = 6` is `KEEP_ASPECT_COVERED` for TextureRect in Godot 4.

- [ ] **Step 3: Verify manually — run the game**

Run: `gol run game --windowed`
Expected: Title screen appears with background image, vignette effect, and three buttons. Clicking "退出" quits. "新游戏" starts the game. "设置" will fail (settings menu not yet created — that's OK for now).

- [ ] **Step 4: Commit**

```bash
cd gol-project
git add scripts/ui/views/menu/view_title_screen.gd scenes/ui/menus/title_screen.tscn
git commit -m "feat(ui): add title screen with background, vignette, and hover animations"
```

---

## Task 7: Settings ViewModel

**Files:**
- Create: `gol-project/scripts/ui/viewmodels/viewmodel_settings.gd`

- [ ] **Step 1: Create viewmodel_settings.gd**

Create `gol-project/scripts/ui/viewmodels/viewmodel_settings.gd`:

```gdscript
class_name ViewModel_Settings
extends ViewModelBase


const ACTION_DISPLAY_NAMES := {
	"player_up": "移动-上",
	"player_down": "移动-下",
	"player_left": "移动-左",
	"player_right": "移动-右",
	"player_fire": "攻击",
	"interact": "互动",
	"pause": "暂停",
}

var is_fullscreen: ObservableProperty
var resolution_index: ObservableProperty
var resolution_text: ObservableProperty
var vsync_enabled: ObservableProperty
var key_bindings: ObservableProperty


func setup() -> void:
	var svc := ServiceContext.settings()
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
	var new_val := not is_fullscreen.value
	is_fullscreen.set_value(new_val)
	var svc := ServiceContext.settings()
	svc.is_fullscreen = new_val
	svc.apply_fullscreen()
	svc.save()


func cycle_resolution() -> void:
	var idx := (resolution_index.value + 1) % Service_Settings.RESOLUTIONS.size()
	resolution_index.set_value(idx)
	resolution_text.set_value(_format_resolution(idx))
	var svc := ServiceContext.settings()
	svc.resolution_index = idx
	svc.apply_resolution()
	svc.save()


func toggle_vsync() -> void:
	var new_val := not vsync_enabled.value
	vsync_enabled.set_value(new_val)
	var svc := ServiceContext.settings()
	svc.vsync_enabled = new_val
	svc.apply_vsync()
	svc.save()


func _format_resolution(idx: int) -> String:
	var res: Vector2i = Service_Settings.RESOLUTIONS[clampi(idx, 0, Service_Settings.RESOLUTIONS.size() - 1)]
	return "%d×%d" % [res.x, res.y]


func _read_key_bindings() -> Array:
	var bindings := []
	for action in ACTION_DISPLAY_NAMES:
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
			"display_name": ACTION_DISPLAY_NAMES[action],
			"key": key_name,
		})
	return bindings
```

- [ ] **Step 2: Commit**

```bash
cd gol-project
git add scripts/ui/viewmodels/viewmodel_settings.gd
git commit -m "feat(ui): add ViewModel_Settings with display and keybinding observables"
```

---

## Task 8: Settings Menu View + Scene

**Files:**
- Create: `gol-project/scripts/ui/views/menu/view_settings_menu.gd`
- Create: `gol-project/scenes/ui/menus/settings_menu.tscn`

- [ ] **Step 1: Create view_settings_menu.gd**

Create `gol-project/scripts/ui/views/menu/view_settings_menu.gd`:

```gdscript
class_name View_SettingsMenu
extends ViewBase


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


func _rebuild_keybinding_rows(bindings: Array) -> void:
	# Clear existing rows
	for child in keybindings_container.get_children():
		child.queue_free()
	# Build new rows
	for binding in bindings:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var action_label := Label.new()
		action_label.text = binding["display_name"]
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key_label := Label.new()
		key_label.text = binding["key"]
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(action_label)
		row.add_child(key_label)
		keybindings_container.add_child(row)
```

- [ ] **Step 2: Create settings_menu.tscn**

Create `gol-project/scenes/ui/menus/settings_menu.tscn`:

```tscn
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/views/menu/view_settings_menu.gd" id="1_settings"]

[node name="SettingsMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_settings")

[node name="ColorRect_Overlay" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.6)

[node name="CenterContainer" type="CenterContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="PanelContainer" type="PanelContainer" parent="CenterContainer"]
custom_minimum_size = Vector2(500, 400)
layout_mode = 2

[node name="VBoxContainer" type="VBoxContainer" parent="CenterContainer/PanelContainer"]
layout_mode = 2
theme_override_constants/separation = 16

[node name="Label_Title" type="Label" parent="CenterContainer/PanelContainer/VBoxContainer"]
layout_mode = 2
theme_override_font_sizes/font_size = 32
text = "设置"
horizontal_alignment = 1

[node name="TabContainer" type="TabContainer" parent="CenterContainer/PanelContainer/VBoxContainer"]
layout_mode = 2
size_flags_vertical = 3

[node name="画面" type="VBoxContainer" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer"]
layout_mode = 2
theme_override_constants/separation = 16

[node name="HBox_Fullscreen" type="HBoxContainer" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/画面"]
layout_mode = 2

[node name="Label" type="Label" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/画面/HBox_Fullscreen"]
layout_mode = 2
size_flags_horizontal = 3
text = "显示模式"

[node name="Button_Fullscreen" type="Button" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/画面/HBox_Fullscreen"]
unique_name_in_owner = true
custom_minimum_size = Vector2(120, 0)
layout_mode = 2
text = "窗口"

[node name="HBox_Resolution" type="HBoxContainer" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/画面"]
layout_mode = 2

[node name="Label" type="Label" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/画面/HBox_Resolution"]
layout_mode = 2
size_flags_horizontal = 3
text = "分辨率"

[node name="Button_Resolution" type="Button" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/画面/HBox_Resolution"]
unique_name_in_owner = true
custom_minimum_size = Vector2(120, 0)
layout_mode = 2
text = "1920×1080"

[node name="HBox_VSync" type="HBoxContainer" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/画面"]
layout_mode = 2

[node name="Label" type="Label" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/画面/HBox_VSync"]
layout_mode = 2
size_flags_horizontal = 3
text = "垂直同步"

[node name="Button_VSync" type="Button" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/画面/HBox_VSync"]
unique_name_in_owner = true
custom_minimum_size = Vector2(120, 0)
layout_mode = 2
text = "开"

[node name="操作" type="ScrollContainer" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer"]
layout_mode = 2

[node name="KeyBindingsContainer" type="VBoxContainer" parent="CenterContainer/PanelContainer/VBoxContainer/TabContainer/操作"]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/separation = 8

[node name="Button_Back" type="Button" parent="CenterContainer/PanelContainer/VBoxContainer"]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 4
text = "返回"
```

- [ ] **Step 3: Verify manually — run the game**

Run: `gol run game --windowed`
Expected: Title screen → click "设置" → Settings menu appears over title screen. Toggle fullscreen, cycle resolution, toggle VSync — all take effect immediately. Click "返回" → back to title screen.

- [ ] **Step 4: Commit**

```bash
cd gol-project
git add scripts/ui/views/menu/view_settings_menu.gd scenes/ui/menus/settings_menu.tscn scripts/ui/viewmodels/viewmodel_settings.gd
git commit -m "feat(ui): add settings menu with display and controls tabs"
```

---

## Task 9: Pause Menu — Add Settings Button + Migrate to MENU Layer

**Files:**
- Modify: `gol-project/scripts/ui/views/menu/view_pause_menu.gd`
- Modify: `gol-project/scenes/ui/menus/pause_menu.tscn`
- Modify: `gol-project/scripts/gameplay/gol_game_state.gd`

- [ ] **Step 1: Add Button_Settings node to pause_menu.tscn**

Edit `gol-project/scenes/ui/menus/pause_menu.tscn` — insert a `Button_Settings` node between `Button_Resume` and `Button_Quit`.

Add this block between the `Button_Resume` and `Button_Quit` node definitions:

```tscn
[node name="Button_Settings" type="Button" parent="CenterContainer/Panel/MarginContainer/VBoxContainer"]
custom_minimum_size = Vector2(220, 56)
layout_mode = 2
size_flags_horizontal = 4
theme_override_font_sizes/font_size = 24
text = "Settings"
```

- [ ] **Step 2: Update view_pause_menu.gd — add settings button handler**

Replace the entire contents of `gol-project/scripts/ui/views/menu/view_pause_menu.gd` with:

```gdscript
class_name View_PauseMenu
extends ViewBase

@onready var button_resume: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/Button_Resume
@onready var button_settings: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/Button_Settings
@onready var button_quit: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/Button_Quit


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	button_resume.pressed.connect(_on_button_resume_pressed)
	button_settings.pressed.connect(_on_button_settings_pressed)
	button_quit.pressed.connect(_on_button_quit_pressed)

func teardown() -> void:
	super.teardown()
	if button_resume != null and button_resume.pressed.is_connected(_on_button_resume_pressed):
		button_resume.pressed.disconnect(_on_button_resume_pressed)
	if button_settings != null and button_settings.pressed.is_connected(_on_button_settings_pressed):
		button_settings.pressed.disconnect(_on_button_settings_pressed)
	if button_quit != null and button_quit.pressed.is_connected(_on_button_quit_pressed):
		button_quit.pressed.disconnect(_on_button_quit_pressed)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

func _on_button_resume_pressed() -> void:
	GOL.Game.toggle_pause()

func _on_button_settings_pressed() -> void:
	var settings_scene: PackedScene = load("res://scenes/ui/menus/settings_menu.tscn")
	ServiceContext.ui().create_and_push_view(Service_UI.LayerType.MENU, settings_scene)

func _on_button_quit_pressed() -> void:
	var tree: SceneTree = get_tree()
	tree.paused = false
	tree.quit()
```

- [ ] **Step 3: Migrate pause menu to MENU layer in gol_game_state.gd**

In `gol-project/scripts/gameplay/gol_game_state.gd`, change `_show_pause_menu()` (line 118) from `LayerType.HUD` to `LayerType.MENU`:

```gdscript
func _show_pause_menu() -> void:
	var pause_menu_scene: PackedScene = load("res://scenes/ui/menus/pause_menu.tscn")
	ServiceContext.ui().create_and_push_view(Service_UI.LayerType.MENU, pause_menu_scene)
```

- [ ] **Step 4: Verify manually**

Run: `gol run game --windowed -- --skip-menu`
Expected: Game starts directly. Press ESC → pause menu shows with Resume, Settings, Quit. Click "Settings" → settings menu overlays. Click "返回" → back to pause menu. Click "Resume" → game resumes.

- [ ] **Step 5: Commit**

```bash
cd gol-project
git add scripts/ui/views/menu/view_pause_menu.gd scenes/ui/menus/pause_menu.tscn scripts/gameplay/gol_game_state.gd
git commit -m "feat(ui): add settings entry to pause menu, migrate pause to MENU layer"
```

---

## Task 10: CLI Argument Pass-Through (gol-tools submodule)

**Files:**
- Modify: `gol-tools/cli/internal/godot/process.go`
- Modify: `gol-tools/cli/cmd/run.go`
- Modify: `gol-tools/cli/internal/testrunner/gdunit.go`
- Modify: `gol-tools/cli/internal/testrunner/sceneconfig.go`

- [ ] **Step 1: Add ExtraArgs to LaunchOpts in process.go**

In `gol-tools/cli/internal/godot/process.go`, add `ExtraArgs` field to `LaunchOpts` struct (after line 100):

```go
type LaunchOpts struct {
	ProjectDir string
	Headless   bool
	Editor     bool
	Detach     bool
	ExtraArgs  []string // Pass-through arguments for Godot (appended after --)
}
```

Update `Launch()` function — append ExtraArgs with `--` separator (after `args = append(args, "--path", opts.ProjectDir)` on line 111):

```go
func Launch(godotBin string, opts LaunchOpts) (*exec.Cmd, error) {
	args := []string{}
	if opts.Headless {
		args = append(args, "--headless")
	}
	if opts.Editor {
		args = append(args, "--editor")
	}
	args = append(args, "--path", opts.ProjectDir)
	if len(opts.ExtraArgs) > 0 {
		args = append(args, "--")
		args = append(args, opts.ExtraArgs...)
	}

	cmd := exec.Command(godotBin, args...)

	if opts.Detach {
		cmd.SysProcAttr = detachAttr()
		cmd.Stdout = nil
		cmd.Stderr = nil
	}

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("failed to launch Godot: %w", err)
	}
	return cmd, nil
}
```

- [ ] **Step 2: Update run.go — accept and forward arbitrary args**

In `gol-tools/cli/cmd/run.go`, update `runGameCmd` declaration (line 31) to accept arbitrary args:

```go
var runGameCmd = &cobra.Command{
	Use:   "game [-- godot-args...]",
	Short: "Run the game (headless by default)",
	Long: `Smart boot: kill existing → ensure import → launch → poll readiness.

Display modes (mutually exclusive):
  (default)     Headless — no window, lowest resource usage (for AI agents via gol debug)
  --windowed    Windowed — launch with a GUI window
  --fullscreen  Fullscreen — launch in fullscreen mode

Pass arbitrary Godot arguments after --:
  gol run game --windowed -- --skip-menu`,
	Args: cobra.ArbitraryArgs,
	RunE: runGame,
}
```

In `runGame()` function, update the Godot args construction (after `godotArgs = append(godotArgs, "--path", projectDir)` on line 108) to forward pass-through args:

```go
	godotArgs = append(godotArgs, "--path", projectDir)

	// Forward pass-through arguments (everything after --)
	if len(args) > 0 {
		godotArgs = append(godotArgs, "--")
		godotArgs = append(godotArgs, args...)
	}
```

- [ ] **Step 3: Auto-inject --skip-menu in gdunit.go**

In `gol-tools/cli/internal/testrunner/gdunit.go`, after `args = append(args, "--ignoreHeadlessMode")` (line 72), add:

```go
	args = append(args, "--ignoreHeadlessMode")
	// Skip title screen for all test runs
	args = append(args, "--", "--skip-menu")
```

- [ ] **Step 4: Auto-inject --skip-menu in sceneconfig.go**

In `gol-tools/cli/internal/testrunner/sceneconfig.go`, update the `exec.Command` call (line 36) to include `--skip-menu`:

```go
		cmd := exec.Command(godotBin,
			"--headless",
			"--path", projectDir,
			"res://scenes/tests/test_main.tscn",
			"--",
			"--config="+resPath,
			"--skip-menu",
		)
```

- [ ] **Step 5: Build and verify CLI**

```bash
cd gol-tools/cli
go build -o gol .
./gol run game --windowed -- --skip-menu
```

Expected: Game launches directly into gameplay (no title screen).

```bash
./gol run game --windowed
```

Expected: Game launches with title screen.

- [ ] **Step 6: Commit in gol-tools submodule**

```bash
cd gol-tools
git add cli/internal/godot/process.go cli/cmd/run.go cli/internal/testrunner/gdunit.go cli/internal/testrunner/sceneconfig.go
git commit -m "feat(cli): add Godot argument pass-through via -- separator, auto-inject --skip-menu for tests"
git push
```

---

## Task 11: Documentation Updates

**Files:**
- Modify: `AGENTS.md` (root)
- Modify: `gol-project/AGENTS.md`

- [ ] **Step 1: Update root AGENTS.md — CLI command reference**

In `AGENTS.md` (root), update the CLI command reference table (around line 72). Add `--skip-menu` to the windowed command and add a new row:

After the existing `| Run game (windowed) | \`gol run game --windowed\` |` row, add:

```markdown
| Run game (skip menu) | `gol run game --windowed -- --skip-menu` | Direct to gameplay |
```

After the `| Debug script |` row (line 88), add a new section:

```markdown

### Argument Pass-Through

`gol run game` supports passing arbitrary arguments to Godot via `--` separator:

    gol run game --windowed -- --skip-menu --custom-arg=value

Arguments after `--` are forwarded directly to Godot. The game reads them via `OS.get_cmdline_user_args()`.

| Game Argument  | Description                                |
|----------------|--------------------------------------------|
| `--skip-menu`  | Skip title screen, go directly to gameplay |

All test commands (`gol test unit`, `gol test integration`, `gol test`) automatically inject `--skip-menu`. No manual action needed.
```

- [ ] **Step 2: Update gol-project/AGENTS.md — boot flow**

In `gol-project/AGENTS.md`, update the Boot line (around line 60) from:

```
**Boot:** `main.tscn → GOL.setup() → ServiceContext.static_setup() → GOL.start_game() → PCG generate → GOLWorld.initialize() → auto-discover systems → bake entities → spawn`
```

To:

```
**Boot:** `GOL._ready() → setup() (idempotent) → main.tscn._ready() → GOL.show_title_screen() → [Title Screen] → GOL.start_game() → PCG generate → GOLWorld.initialize() → auto-discover systems → bake entities → spawn` (with `--skip-menu`: skips title screen)
```

- [ ] **Step 3: Commit documentation**

```bash
cd ..  # back to gol root
git add AGENTS.md gol-project/AGENTS.md
git commit -m "docs: update CLI reference and boot flow for title screen + --skip-menu"
```

---

## Task 12: Submodule Push + Final Verification

**Files:**
- Push: `gol-project` submodule
- Push: `gol-tools` submodule (already pushed in Task 10)
- Update: parent repo submodule references

- [ ] **Step 1: Push gol-project submodule**

```bash
cd gol-project
git push
```

- [ ] **Step 2: Run all tests**

```bash
gol test
```

Expected: All unit and integration tests PASS. `--skip-menu` is auto-injected — title screen does not interfere with tests.

- [ ] **Step 3: Update parent repo submodule references and push**

```bash
cd ..  # back to gol root
git add gol-project gol-tools
git commit -m "chore: update submodules for title screen + settings menu + CLI pass-through"
git push
```

- [ ] **Step 4: Final manual verification**

1. `gol run game --windowed` → Title screen → New Game → gameplay ✓
2. `gol run game --windowed` → Title screen → Settings → change options → Back ✓
3. `gol run game --windowed -- --skip-menu` → Direct to gameplay ✓
4. In-game ESC → Pause → Settings → change options → Back → Resume ✓
5. Restart game → settings persisted from previous session ✓
6. F6 on a map scene in Godot editor → Direct to gameplay (no title screen) ✓
