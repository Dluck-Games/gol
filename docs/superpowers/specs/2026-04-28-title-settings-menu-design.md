# Title Screen, Settings Menu & Pause Menu Settings Entry Design

> Date: 2026-04-28
> Status: Draft
> Scope: Title screen, settings menu, pause menu settings entry, global Theme, CLI argument pass-through, documentation updates

## Overview

Add a complete menu system to GOL: title screen as game entry point, settings menu accessible from both title and pause, and configuration persistence. Additionally, extend `gol` CLI to support Godot argument pass-through, so future game-side arguments (like `--skip-menu`) never require CLI code changes.

### Design Principles

- **First version solves zero-to-one** — get it working, polish later
- **Follow existing MVVM pattern** — all new UI uses ViewBase/ViewModelBase/ObservableProperty
- **Theme-driven styling** — create a global Theme via GDScript constants, replace all inline `theme_override_*`
- **Godot built-in tools only** — Tween, ShaderMaterial, CanvasLayer, Theme. No external art dependencies
- **Modern minimalist aesthetic** — inspired by Hollow Knight / Limbo / Stray: large spacing, low information density, highlighted selection, dark surroundings
- **CLI transparency** — `gol run` passes arbitrary arguments to Godot via `--` separator

## Architecture

### Startup Flow

```
main.tscn (_ready)
  → GOL.setup()               # Idempotent: services init, settings load & apply
  → GOL.show_title_screen()   # Push title screen View to MENU layer

F6 (run map scene directly)
  → GOL._ready() calls setup() automatically (autoload)
  → No title screen — directly into gameplay
  → Services are initialized, settings applied

CLI: gol run game --windowed -- --skip-menu
  → Godot receives --skip-menu via OS.get_cmdline_user_args()
  → GOL.setup() parses args, skips title screen, calls start_game()
```

Key change: move `GOL.setup()` from `main.gd._ready()` into `GOL._ready()` (autoload), making it always execute regardless of entry point. `main.gd` only calls `GOL.show_title_screen()`.

```gdscript
# gol.gd (autoload)
var _is_setup := false

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

func show_title_screen() -> void:
    var args := _parse_launch_args()
    if args.get("skip_menu", false):
        start_game()
        return
    var title_scene: PackedScene = load("res://scenes/ui/menus/title_screen.tscn")
    ServiceContext.ui().create_and_push_view(Service_UI.LayerType.MENU, title_scene)

func _parse_launch_args() -> Dictionary:
    var result := {}
    for arg in OS.get_cmdline_user_args():
        if arg == "--skip-menu":
            result["skip_menu"] = true
    return result

# main.gd
func _ready() -> void:
    await get_tree().process_frame
    GOL.show_title_screen()

func _exit_tree() -> void:
    GOL.teardown()
```

### Service_UI: New MENU Layer

Add `MENU` to `LayerType` enum. MENU layer sits above HUD and GAME layers.

```gdscript
enum LayerType {
    HUD,     # In-game HUD (resource bar, clock)
    GAME,    # In-game overlays (dialogue, hints)
    MENU,    # Full-screen menus (title, settings, pause) — NEW
}
```

MENU layer uses its own CanvasLayer with a higher `layer` value than HUD/GAME. Pause menu migrates from HUD to MENU layer. `GOLGameState._show_pause_menu()` updated accordingly.

### File Structure (New Files)

```
gol-project/
├── scripts/
│   ├── ui/
│   │   ├── gol_theme.gd                       # Global Theme builder (GDScript constants)
│   │   ├── views/menu/
│   │   │   ├── view_title_screen.gd            # Title screen View
│   │   │   └── view_settings_menu.gd           # Settings menu View
│   │   └── view_models/
│   │       └── vm_settings.gd                  # Settings ViewModel
│   ├── services/impl/
│   │   └── service_settings.gd                 # Settings persistence service
│   └── gol.gd                                  # Modified: startup flow
├── scenes/ui/menus/
│   ├── title_screen.tscn                       # Title screen scene
│   └── settings_menu.tscn                      # Settings menu scene
└── shaders/
    ├── ui_glow.gdshader                        # Text/element glow effect
    └── ui_vignette.gdshader                    # Vignette darkening effect
```

### Modified Files

```
gol-project/
├── scripts/
│   ├── gol.gd                                 # setup() moved to _ready(), show_title_screen()
│   ├── main.gd                                # Simplified: only calls show_title_screen()
│   ├── gameplay/gol_game_state.gd             # Pause menu → MENU layer
│   ├── services/impl/service_ui.gd            # Add MENU LayerType
│   └── services/service_context.gd            # Add settings() accessor
├── scenes/ui/menus/
│   └── pause_menu.tscn                        # Add Settings button
│   └── view_pause_menu.gd                     # Add settings button handler
gol-tools/
├── cli/
│   ├── cmd/run.go                             # Add -- pass-through
│   └── internal/godot/process.go              # LaunchOpts.ExtraArgs
│   └── internal/testrunner/gdunit.go          # Auto-inject --skip-menu
│   └── internal/testrunner/sceneconfig.go     # Auto-inject --skip-menu
├── AGENTS.md                                  # Document new CLI args
```

## Title Screen

### Scene Structure

```
title_screen.tscn (View_TitleScreen extends ViewBase)
├── TextureRect_Background        # assets/artworks/title.png, expand KEEP_ASPECT_COVERED
├── ColorRect_Vignette            # Full-screen, ShaderMaterial(ui_vignette.gdshader)
├── VBoxContainer_Buttons         # Left-side, anchored ~(0.05, 0.55)-(0.35, 0.85)
│   ├── Button_NewGame            # "新游戏"
│   ├── Button_Settings           # "设置"
│   └── Button_Quit               # "退出"
```

### Layout

- **Background**: `TextureRect` with `title.png`, stretch mode `KEEP_ASPECT_COVERED`, fills viewport
- **Vignette overlay**: `ColorRect` full-screen with `ui_vignette.gdshader`, creates cinematic edge darkening
- **Button group**: Left-aligned, vertically stacked, 24px separation between buttons
- **Button style**: Theme-driven, transparent background (StyleBoxEmpty), pure text. No image buttons.

### Button Animation (Tween)

```
Default state:
  - Text color: GOLTheme.COLOR_TEXT (muted gray-white)
  - Position: origin

Hover state (0.15s Tween):
  - Text color → GOLTheme.COLOR_TEXT_HOVER (pure white)
  - X offset +8px (subtle rightward shift indicating selection)
  - ShaderMaterial glow_intensity 0→0.5 (soft glow via ui_glow.gdshader)

Focus state (keyboard/gamepad):
  - Same as Hover, ensures keyboard navigation works
```

### View Implementation

No ViewModel needed — title screen logic is trivial (three button handlers).

```gdscript
class_name View_TitleScreen
extends ViewBase

@onready var button_new_game: Button = $VBoxContainer_Buttons/Button_NewGame
@onready var button_settings: Button = $VBoxContainer_Buttons/Button_Settings
@onready var button_quit: Button = $VBoxContainer_Buttons/Button_Quit

func setup() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
    button_new_game.pressed.connect(_on_new_game)
    button_settings.pressed.connect(_on_settings)
    button_quit.pressed.connect(_on_quit)
    # Setup hover tweens for each button
    _setup_button_hover(button_new_game)
    _setup_button_hover(button_settings)
    _setup_button_hover(button_quit)

func _on_new_game() -> void:
    ServiceContext.ui().pop_view(self)
    GOL.start_game()

func _on_settings() -> void:
    var settings_scene: PackedScene = load("res://scenes/ui/menus/settings_menu.tscn")
    ServiceContext.ui().create_and_push_view(Service_UI.LayerType.MENU, settings_scene)

func _on_quit() -> void:
    get_tree().quit()

var _button_origins: Dictionary = {}  # Button → float (original X position)

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
        # Glow intensity via ShaderMaterial if attached
    else:
        tween.tween_property(button, "position:x", origin_x, 0.15)
```

## Settings Menu

### Scene Structure

```
settings_menu.tscn (View_SettingsMenu extends ViewBase)
├── ColorRect_Overlay              # Semi-transparent dark background
├── PanelContainer_Main            # Centered panel, fixed size
│   └── VBoxContainer
│       ├── Label_Title            # "设置"
│       ├── TabContainer
│       │   ├── Tab "画面"
│       │   │   └── VBoxContainer
│       │   │       ├── HBoxContainer   # Fullscreen toggle
│       │   │       │   ├── Label "显示模式"
│       │   │       │   └── Button_Fullscreen ("全屏"/"窗口")
│       │   │       ├── HBoxContainer   # Resolution cycle
│       │   │       │   ├── Label "分辨率"
│       │   │       │   └── Button_Resolution ("1920×1080")
│       │   │       └── HBoxContainer   # VSync toggle
│       │   │           ├── Label "垂直同步"
│       │   │           └── Button_VSync ("开"/"关")
│       │   └── Tab "操作"
│       │       └── ScrollContainer
│       │           └── VBoxContainer   # Key binding rows (read-only)
│       │               ├── HBoxContainer { Label "移动-上", Label "W" }
│       │               ├── HBoxContainer { Label "移动-下", Label "S" }
│       │               └── ... (all input actions)
│       └── Button_Back            # "返回"
```

### MVVM Integration

**ViewModel: `VM_Settings`**

```gdscript
class_name VM_Settings
extends ViewModelBase

var is_fullscreen: ObservableProperty     # bool
var resolution_index: ObservableProperty  # int
var resolution_text: ObservableProperty   # String ("1920×1080")
var vsync_enabled: ObservableProperty     # bool
var key_bindings: ObservableProperty      # Array[Dictionary]

const RESOLUTIONS := [
    Vector2i(1920, 1080),
    Vector2i(1600, 900),
    Vector2i(1280, 720),
    Vector2i(960, 540),
]

func setup() -> void:
    var svc := ServiceContext.settings()
    is_fullscreen = ObservableProperty.new(svc.is_fullscreen)
    resolution_index = ObservableProperty.new(svc.resolution_index)
    resolution_text = ObservableProperty.new(_format_resolution(svc.resolution_index))
    vsync_enabled = ObservableProperty.new(svc.vsync_enabled)
    key_bindings = ObservableProperty.new(_read_key_bindings())

func toggle_fullscreen() -> void:
    var new_val := not is_fullscreen.value
    is_fullscreen.set_value(new_val)
    var svc := ServiceContext.settings()
    svc.is_fullscreen = new_val
    svc.apply_fullscreen()
    svc.save()

func cycle_resolution() -> void:
    var idx := (resolution_index.value + 1) % RESOLUTIONS.size()
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
```

**Display settings take effect immediately** — no "apply" button. Each toggle/cycle calls the service to persist and apply.

### Controls Tab: Key Binding Display

Read-only display of all input actions and their current bindings. Data sourced from `InputMap` at runtime.

```gdscript
const ACTION_DISPLAY_NAMES := {
    "player_up": "移动-上",
    "player_down": "移动-下",
    "player_left": "移动-左",
    "player_right": "移动-右",
    "player_fire": "攻击",
    "interact": "互动",
    "pause": "暂停",
}

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
            "key": key_name
        })
    return bindings
```

Rebinding functionality is deliberately excluded from v1 — interface reserved for future iteration.

### Settings Menu Navigation

Settings menu is pushed on top of the calling menu (title or pause). Closing settings pops it, revealing the caller underneath. No explicit origin tracking needed.

```
Title Screen (MENU layer)
  → push Settings Menu (MENU layer, on top)
    → "返回" → pop Settings Menu
  ← Title Screen visible again

Pause Menu (MENU layer)
  → push Settings Menu (MENU layer, on top)
    → "返回" → pop Settings Menu
  ← Pause Menu visible again
```

## Pause Menu Modification

### Changes

Add "设置" button between "继续" and "退出":

```
VBoxContainer
├── Label_Title ("暂停")
├── Button_Resume ("继续")
├── Button_Settings ("设置")    ← NEW
└── Button_Quit ("退出")
```

### Code Change

```gdscript
# view_pause_menu.gd — add to setup()
@onready var button_settings: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/Button_Settings

func setup() -> void:
    # ... existing code
    button_settings.pressed.connect(_on_button_settings_pressed)

func _on_button_settings_pressed() -> void:
    var settings_scene: PackedScene = load("res://scenes/ui/menus/settings_menu.tscn")
    ServiceContext.ui().create_and_push_view(Service_UI.LayerType.MENU, settings_scene)
```

### Layer Migration

Pause menu moves from `Service_UI.LayerType.HUD` to `Service_UI.LayerType.MENU`. Update `GOLGameState._show_pause_menu()`:

```gdscript
func _show_pause_menu() -> void:
    var pause_menu_scene: PackedScene = load("res://scenes/ui/menus/pause_menu.tscn")
    ServiceContext.ui().create_and_push_view(Service_UI.LayerType.MENU, pause_menu_scene)
```

## Service_Settings (Configuration Persistence)

New service for loading, saving, and applying display settings.

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

# ── State ──
var is_fullscreen := false
var resolution_index := 0
var vsync_enabled := true

func _setup() -> void:
    _load()
    apply_all()

func _load() -> void:
    var config := ConfigFile.new()
    if config.load(SETTINGS_PATH) != OK:
        return  # First run, use defaults
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
        apply_resolution()  # Restore window size when exiting fullscreen

func apply_resolution() -> void:
    if is_fullscreen:
        return  # Fullscreen uses native resolution
    var res: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
    DisplayServer.window_set_size(res)
    # Center window on screen
    var screen_size := DisplayServer.screen_get_size()
    var pos := (screen_size - res) / 2
    DisplayServer.window_set_position(pos)

func apply_vsync() -> void:
    if vsync_enabled:
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
    else:
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
```

Registered in `ServiceContext` with `ServiceContext.settings()` accessor.

## Global Theme (GDScript)

Theme built via GDScript constants instead of `.tres` file. Better for version control and code review.

```gdscript
class_name GOLTheme

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
    # Transparent background for menu buttons
    var empty := StyleBoxEmpty.new()
    theme.set_stylebox("normal", "Button", empty)
    theme.set_stylebox("hover", "Button", empty)
    theme.set_stylebox("pressed", "Button", empty)
    theme.set_stylebox("focus", "Button", empty)
    theme.set_color("font_color", "Button", COLOR_TEXT)
    theme.set_color("font_hover_color", "Button", COLOR_TEXT_HOVER)
    theme.set_color("font_pressed_color", "Button", COLOR_ACCENT)
    theme.set_font_size("font_size", "Button", FONT_SIZE_BUTTON)

# ... _setup_label, _setup_panel, _setup_tab_container follow same pattern
```

Theme applied at startup in `GOL.setup()` via `ThemeDB.project_theme` or root node's `theme` property.

## Shader Effects

### ui_glow.gdshader (Text/Element Glow)

Applied to buttons via ShaderMaterial. `glow_intensity` animated by Tween on hover.

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

### ui_vignette.gdshader (Edge Darkening)

Applied to a full-screen ColorRect on the title screen.

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

## GOL CLI: Argument Pass-Through

### Design

Use `--` separator (Unix standard) to pass arbitrary arguments through to Godot. This ensures future game-side arguments never require CLI code changes.

```bash
# Normal launch (with title screen)
gol run game --windowed

# Skip title screen
gol run game --windowed -- --skip-menu

# Future: any new Godot-side arguments work without CLI changes
gol run game -- --skip-menu --custom-level=l_battle --debug-mode
```

### Code Changes

**`internal/godot/process.go`** — Extend LaunchOpts:

```go
type LaunchOpts struct {
    Headless   bool
    Editor     bool
    ProjectDir string
    Detach     bool
    ExtraArgs  []string  // NEW: pass-through arguments for Godot
}

func Launch(godotBin string, opts LaunchOpts) (*exec.Cmd, error) {
    args := []string{}
    if opts.Headless {
        args = append(args, "--headless")
    }
    if opts.Editor {
        args = append(args, "--editor")
    }
    args = append(args, "--path", opts.ProjectDir)
    // Pass-through: append "--" separator then extra args
    if len(opts.ExtraArgs) > 0 {
        args = append(args, "--")
        args = append(args, opts.ExtraArgs...)
    }
    cmd := exec.Command(godotBin, args...)
    // ... rest unchanged
}
```

**`cmd/run.go`** — Capture arbitrary args:

```go
var runGameCmd = &cobra.Command{
    Use:   "game [-- godot-args...]",
    Short: "Run the game",
    Args:  cobra.ArbitraryArgs,
    RunE: func(cmd *cobra.Command, args []string) error {
        // args contains everything after "--"
        // ... existing logic to build godotArgs
        godotArgs = append(godotArgs, args...)  // pass-through
        // ...
    },
}
```

Note: `cmd/run.go` currently builds `godotArgs` inline for `newStreamingProcess()` (not via `godot.Launch()`). The pass-through must be applied to the `newStreamingProcess` call path as well:

```go
// In runGameCmd.RunE, after building godotArgs:
godotArgs = append(godotArgs, "--path", projectDir)
if len(args) > 0 {
    godotArgs = append(godotArgs, "--")
    godotArgs = append(godotArgs, args...)
}
proc := newStreamingProcess(godotBin, godotArgs, logFile)
```

**`internal/testrunner/gdunit.go`** — Auto-inject `--skip-menu`:

```go
args := []string{
    "--headless",
    "-s", "addons/gdUnit4/bin/GdUnitCmdTool.gd",
}
args = append(args, addArgs...)
args = append(args, "--ignoreHeadlessMode")
// Inject --skip-menu for all test runs
args = append(args, "--", "--skip-menu")
```

**`internal/testrunner/sceneconfig.go`** — Auto-inject `--skip-menu`:

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

### Godot-Side Argument Parsing

```gdscript
# gol.gd
func _parse_launch_args() -> Dictionary:
    var result := {}
    for arg in OS.get_cmdline_user_args():
        if arg == "--skip-menu":
            result["skip_menu"] = true
        # Future args parsed here without CLI changes
    return result
```

`OS.get_cmdline_user_args()` in Godot 4 returns arguments after `--`, aligning perfectly with the CLI's `--` pass-through.

## Documentation Updates

### Files to Update

1. **`gol-tools/AGENTS.md`** — Add `--` pass-through documentation, `--skip-menu` usage
2. **`gol-project/tests/AGENTS.md`** — Note that `--skip-menu` is auto-injected in test runs
3. **Root `AGENTS.md`** — Reference new menu system in project overview
4. **Skills documentation** — Update `gol-test-runner`, `gol-debug`, and other skills that reference game launch commands

### New Documentation Content

For `gol-tools/AGENTS.md`, add section:

```markdown
## Argument Pass-Through

`gol run game` supports passing arbitrary arguments to Godot via `--` separator:

    gol run game --windowed -- --skip-menu --custom-arg=value

Arguments after `--` are forwarded directly to Godot. The game reads
them via `OS.get_cmdline_user_args()`.

### Available Game Arguments

| Argument       | Description                                    |
|----------------|------------------------------------------------|
| `--skip-menu`  | Skip title screen, go directly to gameplay     |

### Test Runs

All test commands (`gol test unit`, `gol test scene`) automatically
inject `--skip-menu`. No manual action needed.
```

## Explicitly Out of Scope (YAGNI)

- ❌ Particle effects on title screen
- ❌ Button sound effects
- ❌ Title screen entry animations (text fade-in, etc.)
- ❌ Key rebinding functionality (controls tab is display-only)
- ❌ Advanced display settings (anti-aliasing, shadows, etc.)
- ❌ Audio/music volume settings
- ❌ Level selection from title screen
- ❌ `gol run editor` argument pass-through (can be added later with same pattern)
