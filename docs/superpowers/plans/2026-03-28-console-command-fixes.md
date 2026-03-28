# Console Command Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Tab completion, macOS Retina DPI scaling, and spawn recipe autocomplete in a single PR — resolving issues #213, #215, #217.

**Architecture:** Two files changed (`console_panel.gd`, `debug_panel.gd`), both under `scripts/debug/`. The Tab fix replaces broken Godot input polling with ImGui-native key detection. The DPI fix detects screen DPI at startup and sets ImGui's Scale property. Spawn recipe completion (#217) is already implemented — it works once Tab confirmation (#213) is fixed.

**Tech Stack:** GDScript, ImGui-Godot addon (imgui v1.91.6-docking)

**Issues:** [#213](https://github.com/Dluck-Games/god-of-lego/issues/213), [#215](https://github.com/Dluck-Games/god-of-lego/issues/215), [#217](https://github.com/Dluck-Games/god-of-lego/issues/217)

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `scripts/debug/console_panel.gd` | Fix Tab detection, cleanup dead code |
| Modify | `scripts/debug/debug_panel.gd` | Add DPI-aware ImGui scaling |

No new files created. No test files modified (existing tests at `tests/unit/service/test_service_console.gd` and `tests/integration/flow/test_flow_console_spawn_scene.gd` already cover completion logic).

---

## Root Cause Analysis

### #213 — Tab completion broken

The console input uses `ImGui.InputTextWithHint()` for text entry. When Tab is pressed:

1. ImGui internally processes the Tab key event (even without `NavEnableKeyboard`, ImGui's InputText widget consumes Tab)
2. The code at `console_panel.gd:93` tries `Input.is_key_pressed(KEY_TAB)` — Godot's raw input polling
3. Because imgui-godot's input handler intercepts and forwards key events to ImGui, the Tab event never reaches Godot's `Input` state

**Fix:** Replace `Input.is_key_pressed(KEY_TAB)` with `ImGui.IsKeyPressed(ImGui.Key_Tab)`, matching the pattern already used for Up/Down/Escape arrows at lines 99-103. `ImGui.IsKeyPressed()` has built-in edge detection (returns true only on the transition frame), eliminating the need for manual `_tab_was_pressed` tracking.

### #215 — macOS Retina DPI scaling

The imgui-godot addon auto-scales fonts when `display/window/dpi/allow_hidpi` is set in `project.godot`. This setting is not configured in the project (confirmed: no `allow_hidpi` entry in `project.godot`). Enabling it would affect the entire game viewport, not just ImGui.

**Fix:** Detect screen DPI in `debug_panel.gd._ready()` and set ImGui's Scale property directly. This only affects ImGui rendering — no project-wide side effects. The addon's `RebuildFontAtlas()` is triggered automatically when Scale is set.

### #217 — Spawn recipe autocomplete

Already implemented at `console_panel.gd:226-240` (calls `Service_Console.get_recipe_completions(partial)`) and tested at `test_flow_console_spawn_scene.gd:133-141`. The completion list appears when typing `spawn <partial>`, but Tab to confirm is broken (#213). Fixing Tab fixes this issue.

---

## Task 1: Fix Tab Key Detection in Console Panel

**Files:**
- Modify: `scripts/debug/console_panel.gd:20,89-106,189-205,243-259`

### Steps

- [ ] **Step 1.1: Replace Tab detection with ImGui-native key check**

In `console_panel.gd`, replace the `Input.is_key_pressed(KEY_TAB)` polling with `ImGui.IsKeyPressed(ImGui.Key_Tab)`:

```gdscript
# OLD (lines 91-97):
		if _show_completions and _completions.size() > 0:
			# Tab confirms completion - use Godot Input since ImGui consumes Tab
			if Input.is_key_pressed(KEY_TAB) and not _tab_was_pressed:
				_apply_completion()
				_tab_was_pressed = true
			elif not Input.is_key_pressed(KEY_TAB):
				_tab_was_pressed = false

# NEW:
		if _show_completions and _completions.size() > 0:
			# Tab confirms completion
			if ImGui.IsKeyPressed(ImGui.Key_Tab):
				_apply_completion()
				_reclaim_focus = true
```

Key changes:
- `ImGui.IsKeyPressed(ImGui.Key_Tab)` has built-in edge detection — no manual state tracking needed
- `_reclaim_focus = true` ensures cursor position resets properly after completion text is applied (matches Enter-confirm behavior at line 82)

- [ ] **Step 1.2: Remove the `_tab_was_pressed` variable**

Delete the variable declaration and its reset in the else branch:

```gdscript
# DELETE line 20:
var _tab_was_pressed: bool = false  # Track Tab key state for edge detection

# DELETE lines 105-106:
		else:
			_tab_was_pressed = false
```

After this change, the `if is_focused or is_active:` block (lines 90-110) should look like:

```gdscript
	# Handle keys when focused
	if is_focused or is_active:
		if _show_completions and _completions.size() > 0:
			# Tab confirms completion
			if ImGui.IsKeyPressed(ImGui.Key_Tab):
				_apply_completion()
				_reclaim_focus = true

			if ImGui.IsKeyPressed(ImGui.Key_UpArrow):
				_completion_index = (_completion_index - 1 + _completions.size()) % _completions.size()
			elif ImGui.IsKeyPressed(ImGui.Key_DownArrow):
				_completion_index = (_completion_index + 1) % _completions.size()
			elif ImGui.IsKeyPressed(ImGui.Key_Escape):
				_show_completions = false
		else:
			if ImGui.IsKeyPressed(ImGui.Key_UpArrow):
				_navigate_history(-1)
			elif ImGui.IsKeyPressed(ImGui.Key_DownArrow):
				_navigate_history(1)
```

- [ ] **Step 1.3: Remove dead code `_handle_tab_completion()`**

Delete the entire `_handle_tab_completion()` method (lines 189-205). This function is never called — it was an earlier implementation that was replaced by the inline `_update_completions()` system:

```gdscript
# DELETE lines 189-206:
func _handle_tab_completion() -> void:
	# Get the command part (first word)
	var parts := _input.strip_edges().split(" ", false)
	var partial := parts[0] if parts.size() > 0 else ""

	_completions = _get_console().get_completions(partial)

	if _completions.size() == 1:
		# Single match - auto-complete immediately
		_input = _completions[0] + " "
		_show_completions = false
	elif _completions.size() > 1:
		# Multiple matches - show popup
		_show_completions = true
		_completion_index = 0
	else:
		_show_completions = false
```

- [ ] **Step 1.4: Run existing tests to verify no regression**

Run: `cd /Users/dluckdu/Documents/Github/gol/gol-project && godot --headless -s scripts/tests/test_main.gd --test-suite=tests/unit/service/test_service_console.gd 2>&1 | tail -20`

Expected: All tests pass — completion logic in `Service_Console` is unchanged, only the UI key-binding was modified.

- [ ] **Step 1.5: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
git add scripts/debug/console_panel.gd
git commit -m "fix(console): use ImGui-native Tab detection for command completion

Replace Input.is_key_pressed(KEY_TAB) with ImGui.IsKeyPressed(ImGui.Key_Tab)
to fix Tab key not triggering autocomplete confirmation. ImGui's input handler
intercepts Tab before Godot's Input state updates, making the Godot polling
approach unreliable. Remove dead code _handle_tab_completion().

Closes #213
Closes #217"
```

---

## Task 2: Fix macOS Retina DPI Scaling

**Files:**
- Modify: `scripts/debug/debug_panel.gd:30-37`

### Steps

- [ ] **Step 2.1: Add DPI detection and ImGui scale setup**

In `debug_panel.gd`, add a DPI-aware scaling call at the end of `_ready()`:

```gdscript
func _ready() -> void:
	# Check if ImGui is available (native library loaded)
	if not ClassDB.class_exists("ImGuiController"):
		return

	print("[DebugPanel] Ready - press ~ to toggle")
	_setup_entity_highlight()
	_load_window_config()
	_apply_imgui_dpi_scale()
```

Add the new method at the bottom of the file (before `_mark_needs_save()`):

```gdscript
func _apply_imgui_dpi_scale() -> void:
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 96:
		return
	var scale := maxf(1.0, float(dpi) / 96.0)
	# ImGuiGD.Scale triggers RebuildFontAtlas — must be called outside _process
	var imgui_gd := Engine.get_singleton("ImGuiGD")
	if imgui_gd:
		imgui_gd.set("Scale", scale)
		print("[DebugPanel] Applied DPI scale: %.1fx (DPI: %d)" % [scale, dpi])
```

How this works:
- `DisplayServer.screen_get_dpi()` returns the hardware DPI (e.g., 144-220 on Retina)
- `dpi / 96` gives the scale factor (2x for standard Retina)
- Setting `ImGuiGD.Scale` triggers the addon's `RebuildFontAtlas()` internally, which bakes the scale into the font atlas and calls `ImGui.GetStyle().ScaleAllSizes(scale)`
- Safe to call in `_ready()` because the addon's `RebuildFontAtlas()` only errors during `_process()` frames
- Only affects ImGui rendering — no impact on game viewport or project settings

- [ ] **Step 2.2: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
git add scripts/debug/debug_panel.gd
git commit -m "fix(debug): auto-scale ImGui panel for HiDPI/Retina displays

Detect screen DPI at startup and set ImGui Scale accordingly.
On macOS Retina (DPI ~144-220), this scales the debug panel ~2x
to match native resolution. Only affects ImGui, not game viewport.

Closes #215"
```

---

## Task 3: Manual Verification

These changes are UI-level (ImGui key handling and DPI rendering) and cannot be verified by headless unit tests. Manual verification is required.

- [ ] **Step 3.1: Verify Tab completion on commands**

1. Launch the game: `cd /Users/dluckdu/Documents/Github/gol/gol-project && godot`
2. Press `~` to open debug panel
3. Type `he` in console input → completions `heal`, `help` should appear
4. Press **Tab** → should confirm the selected completion (e.g., `heal `)
5. Clear input, type `sp` → `spawn`, `screenshot` should appear
6. Press **Down Arrow** to select `spawn`, then **Tab** → should confirm `spawn `

- [ ] **Step 3.2: Verify spawn recipe autocomplete**

1. Type `spawn e` → recipe completions `enemy_basic`, `enemy_cold`, etc. should appear
2. Use **Up/Down** to navigate, **Tab** to confirm → should insert e.g., `spawn enemy_basic `
3. Type `spawn cam` → `campfire` should appear
4. Press **Enter** to confirm → should insert `spawn campfire `

- [ ] **Step 3.3: Verify DPI scaling (macOS only)**

1. On a macOS Retina display, launch the game
2. Check console output for: `[DebugPanel] Applied DPI scale: 2.0x (DPI: 144)` (values may vary)
3. Press `~` → debug panel text should be legible (approximately 2x the previous size)
4. Open Console window with `Ctrl+P` → text and input should also be scaled
5. On a non-Retina / non-macOS display: no scaling applied, panel looks unchanged

- [ ] **Step 3.4: Verify no regressions**

1. **Up/Down arrow** history navigation still works when completions are not showing
2. **Escape** dismisses the completion list
3. **Enter** still executes commands when completions are not showing
4. **Enter** still confirms completions when they are showing
5. Window position saving/loading still works after DPI scale change
