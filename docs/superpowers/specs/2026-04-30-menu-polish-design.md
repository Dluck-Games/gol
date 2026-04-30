# Menu Polish Design — Building Keys, Return to Title, Pixel-Style UI

**Date:** 2026-04-30
**Status:** Approved
**Scope:** Options menu keybinding gap, pause menu "return to title", menu visual overhaul

---

## 1. Problem Statement

Three issues with the current menu system:

1. **Options menu missing building keys**: `ViewModel_Settings.ACTION_DISPLAY_NAMES` does not include `build_menu` (B key). Players cannot see building-related keybindings in the settings menu.

2. **Pause menu lacks "Return to Title"**: The only way to leave a game session is to quit the application entirely. No way to return to the title screen for a new game.

3. **Menu styling is too plain**: `GOLTheme` uses `StyleBoxEmpty` for buttons (invisible backgrounds), minimal panel styling, and Godot's default font. This looks generic and out of place in a pixel-art survival game.

---

## 2. Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Styling approach | Pure programmatic (StyleBoxFlat + shader) | No UI texture pipeline exists; code-only is maintainable and flexible |
| Pixel font | Yes, open-source CJK pixel font (Fusion Pixel 12px or similar) | Core to pixel aesthetic; needed for Chinese UI text |
| Return-to-title confirmation | Modal confirm dialog | Prevents accidental progress loss |
| Confirm dialog reusability | Generic `View_ConfirmDialog` scene | Reusable for quit confirmation and future use |
| Keybinding grouping | Categorized with separator headers | Better UX as action count grows |
| Language | Unified Chinese | Fixes English/Chinese inconsistency in pause menu |

---

## 3. Feature: Options Menu — Building Keybindings

### 3.1 Changes to `ViewModel_Settings`

Add `build_menu` to `ACTION_DISPLAY_NAMES` and restructure as grouped categories:

```gdscript
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
```

`_read_key_bindings()` returns a new structure: array of `{group_name, bindings: [{display_name, key}]}`.

### 3.2 Changes to `View_SettingsMenu._rebuild_keybinding_rows()`

For each group:
1. Add a `Label` separator with the group name (styled: smaller font, accent color, left-aligned)
2. Add the keybinding rows as before (display_name left, key right)

---

## 4. Feature: Pause Menu — Return to Title

### 4.1 Button Layout

```
暂停 (title)
继续游戏
设置
返回标题     ← NEW
退出游戏
```

### 4.2 Confirm Dialog Component

New reusable scene `scenes/ui/menus/confirm_dialog.tscn`:

```
ConfirmDialog (Control, full-screen, PROCESS_MODE_ALWAYS)
├── ColorRect_Overlay        — Color(0,0,0, 0.4) additional dim
└── CenterContainer
    └── PanelContainer       — min 400×200, uses GOLTheme panel style
        └── VBoxContainer    — separation=24
            ├── Label_Message   — centered, multi-line, font_size body
            └── HBoxContainer   — centered, separation=16
                ├── Button_Confirm  — "确定"
                └── Button_Cancel   — "取消"
```

Script `View_ConfirmDialog extends ViewBase`:
- Static factory: `create(message: String, on_confirm: Callable) -> View_ConfirmDialog`
- `setup()`: sets message text, connects buttons
- Confirm: calls `on_confirm`, then pops self
- Cancel: pops self
- Focus grabs "取消" by default (safer default)

### 4.3 Return-to-Title Flow

In `View_PauseMenu._on_return_to_title()`:
1. Create confirm dialog with message "当前进度将丢失，确定返回标题画面？"
2. Push to `LayerType.MENU`
3. On confirm callback:
   - `get_tree().paused = false`
   - `GOL.return_to_title()` (new method)

### 4.4 `GOL.return_to_title()`

New method on the GOL autoload:
1. Pop all views from UI service (clear menu stack)
2. Clean up current game state (`GOL.Game` teardown)
3. Reset scene to initial state
4. Call `GOL.show_title_screen()`

### 4.5 Quit Button Also Gets Confirmation

Reuse `View_ConfirmDialog`:
- Message: "确定退出游戏？"
- On confirm: `get_tree().quit()`

### 4.6 Unified Chinese Text

| Before | After |
|--------|-------|
| "PAUSED" | "暂停" |
| "Resume" | "继续游戏" |
| "Settings" | "设置" |
| "Quit" | "退出游戏" |

---

## 5. Feature: Menu Visual Overhaul

### 5.1 Pixel Font

- Font: Open-source CJK pixel font (Fusion Pixel 12px recommended)
- License: OFL (SIL Open Font License) — free for commercial use
- Integration: downloaded `.ttf` placed in `assets/fonts/`, loaded in `GOLTheme.create_theme()`
- Size mapping:

| Use | Size |
|-----|------|
| Menu titles (暂停, 设置) | 32px |
| Buttons | 24px |
| Body text / labels | 16px |
| Small / keybinding keys | 12px |

### 5.2 Button StyleBox Upgrade

Replace `StyleBoxEmpty` with `StyleBoxFlat` for all 4 states:

| State | Background | Border | Text Color |
|-------|-----------|--------|------------|
| Normal | `(0.12, 0.12, 0.18, 0.85)` | 2px `(0.3, 0.32, 0.4)` | `COLOR_TEXT` |
| Hover | `(0.18, 0.18, 0.25, 0.95)` | 2px `(0.65, 0.7, 0.9)` | `COLOR_TEXT_HOVER` |
| Pressed | `(0.06, 0.06, 0.1, 0.95)` | 2px `(0.5, 0.55, 0.7)` | `COLOR_ACCENT` |
| Disabled | `(0.08, 0.08, 0.12, 0.5)` | 1px `(0.2, 0.2, 0.25)` | `COLOR_TEXT_DISABLED` |
| Focus | Same as normal bg | 2px accent `(0.65, 0.7, 0.9, 0.5)` | `COLOR_TEXT` |

All with `corner_radius = 2` (pixel-sharp corners).

### 5.3 Panel StyleBox Upgrade

```
Background:     Color(0.06, 0.06, 0.1, 0.94)
Border:         2px Color(0.25, 0.27, 0.35)
Corner radius:  2px
Content margin: 24px all sides
Shadow:         size=4, offset=(2,2), color=Color(0,0,0, 0.3)
```

### 5.4 TabContainer Upgrade

- Selected tab: accent color text + 2px bottom border in accent
- Unselected tab: `COLOR_TEXT_DISABLED`, no border
- Tab bar background: transparent
- Font size: 16px (pixel font body size)

### 5.5 Title Screen Button Variant

Title screen buttons keep their hover slide animation (+8px X) and additionally gain:
- Same StyleBoxFlat as regular buttons but with larger size (font 28px)
- Glow on hover using existing `ui_glow.gdshader` (tween `glow_intensity` 0→0.3 over 0.15s)

### 5.6 Keybinding Row Styling

Keybinding key labels (right side) styled as "key caps":
- Small `StyleBoxFlat` background: `(0.15, 0.15, 0.22, 0.8)`, 1px border `(0.3, 0.32, 0.4)`, 2px corner radius
- Padding: 4px horizontal, 2px vertical
- Gives visual distinction between the action name and its bound key

---

## 6. Files Changed

| File | Change |
|------|--------|
| `scripts/ui/viewmodels/viewmodel_settings.gd` | Add `build_menu` to display names, add `KEYBINDING_GROUPS`, restructure `_read_key_bindings()` |
| `scripts/ui/views/menu/view_settings_menu.gd` | Update `_rebuild_keybinding_rows()` for grouped display + key cap styling |
| `scenes/ui/menus/settings_menu.tscn` | Minor: adjust container sizing if needed |
| `scripts/ui/views/menu/view_pause_menu.gd` | Add "返回标题" button handler, add confirm dialog for quit, Chinese text |
| `scenes/ui/menus/pause_menu.tscn` | Add Button_ReturnToTitle, update button text to Chinese |
| `scripts/ui/views/menu/view_confirm_dialog.gd` | NEW: reusable confirm dialog view |
| `scenes/ui/menus/confirm_dialog.tscn` | NEW: confirm dialog scene |
| `scripts/ui/gol_theme.gd` | Button StyleBoxFlat upgrade, panel shadow, pixel font, TabContainer styling |
| `scripts/gol.gd` | Add `return_to_title()` method |
| `assets/fonts/` | NEW: pixel font `.ttf` file |
| `scripts/ui/views/menu/view_title_screen.gd` | Add glow effect on hover |

---

## 7. Out of Scope

- Keybinding remapping (read-only display only)
- Sound effects (SFX placeholder hooks not included)
- Gamepad/controller navigation
- Save/load system
- Localization system (hardcoded Chinese for now)
