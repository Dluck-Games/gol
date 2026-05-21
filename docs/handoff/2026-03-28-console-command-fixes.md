# Handoff: Console Command Fixes

Date: 2026-03-28
Session focus: Fix Tab completion, macOS Retina DPI scaling, spawn recipe autocomplete, and Ctrl+P shortcut in debug console — PR #218 resolving issues #213, #215, #217.

## User Requests (Verbatim)

- "抓一下目前和 console command 相关的所有 open 的 issue，为我评估一个修改方案。这个 plan 需要一次性改动解决多个 issue 单。"
- "目前运行的游戏似乎没有修复。还发现个新问题：输入框有字符时，无法按 ctrl p 快捷键关闭窗口。窗口大小还是很小，tab 键按下后窗口会闪烁但是没有补全成功。"
- "DPI 没有生效，依旧很小。快捷键工作正常了，补全正常了。recipe id 补全没有生效。另付一个 bug：当第一个词补全后，整个词会被选中并且附带一个空格一起，随后再输入，可能会误操作将选中的内容替换为新输入的字幕，如果手动消除选中给，补全的内容提示是基于所有 command 来的，并不是 param。我希望可以复刻原生终端补全的用户体验。"
- "好，DPI 缩放修好了，RecipeID 补全也修好了。新问题：补全后的 spawn xxxx 命令，按下 enter 无法打出去，无法生效，UI 会像刷新了一样闪烁一次，然后命令并没有发出；另外有个体验问题，命令面板出现时，我按下 s 会导致人物往下移动，甚至可能松开还会不停的移动，这种阻塞键盘操作的界面出现时，不应该能继续响应游戏输入。先总结交接文档，记录我说的问题和上面的所有内容。暂不继续修复。"

## Goal

Fix the two remaining bugs: (1) Enter key not executing commands after guard-protected completion, (2) game input not blocked when console panel is open — then merge PR #218.

## Work Completed

- Created implementation plan at `docs/superpowers/plans/2026-03-28-console-command-fixes.md`
- Replaced `Input.is_key_pressed(KEY_TAB)` with `ImGui.IsKeyPressed(ImGui.Key_Tab)` for Tab detection
- Removed dead code `_handle_tab_completion()` and `_tab_was_pressed` variable
- Added dynamic widget ID (`_input_id` counter) to force ImGui InputText buffer re-read after completion
- Moved Ctrl+P shortcut from `_input()` to `_process()` with `Input.is_key_pressed()` hardware polling to bypass ImGui event consumption
- Fixed DPI scaling: switched from `screen_get_dpi()` to `screen_get_scale()`, added explicit `RebuildFontAtlas()` call
- Fixed recipe ID completion: `_update_completions()` now checks raw input for spaces to detect argument mode
- Added completion guard mechanism to protect completed text from ImGui's auto-select-all replacement
- Ran spec compliance review (7/7 pass) and code quality review (addressed minor issues)
- Created PR #218 linked to issues #213, #215, #217

## Current State

- Branch: `fix/console-command-improvements` in `gol-project` (5 commits ahead of main)
- PR #218 is open: https://github.com/Dluck-Games/god-of-lego/pull/218
- Working tree is clean, all changes pushed
- User-confirmed working: DPI scaling, Tab completion, Ctrl+P shortcut, recipe ID completion
- User-confirmed broken: Enter key after guard-protected completion, game input not blocked when console is open

## Pending Tasks

### Bug 1: Enter key not executing after guard-protected completion

The guard mechanism (`_guard_completion`) likely interferes with Enter execution. When Enter is pressed:
1. `enter_pressed = true` branch runs, clears `_guard_completion`
2. BUT `_show_completions` might be true (recipe completions auto-show after command completion)
3. So Enter hits `_apply_completion()` again instead of `_execute_input()`
4. This creates an infinite completion loop — the "flicker" the user sees

Root cause analysis: After Tab completes "spawn ", `_last_input = ""` forces `_update_completions()` which shows recipe completions. Then pressing Enter with completions showing triggers `_apply_completion()` instead of `_execute_input()`. The fix likely needs to differentiate between "completions shown because user is browsing" vs "completions shown as suggestions while typing".

Possible fix: When Enter is pressed and `_show_completions` is true but the user hasn't navigated the completion list (no Up/Down arrow), execute the input instead of applying completion. Or: only apply completion on Enter if `_completion_index` was actively changed by the user.

### Bug 2: Game input not blocked when console is open

When the console panel is visible, keyboard events (like 's' for movement) still reach the game's input actions. The debug panel needs to block game input when it has focus.

Possible approaches:
- Set `Input.set_mouse_mode()` already happens, but keyboard input is not blocked
- The `_input()` handler calls `get_viewport().set_input_as_handled()` for tilde, but not for all keys when console is open
- Consider adding `get_viewport().set_input_as_handled()` in `_input()` for ALL key events when `_visible[0]` or `_console_visible[0]` is true
- OR use `set_process_input(false)` on game nodes when debug panel is active
- OR use Godot's input action system — `Input.action_release()` for any held actions when panel opens, then block `_unhandled_input` propagation

### Other remaining items

- Manual verification of all fixes after Enter bug is resolved
- Merge PR #218 after all fixes pass
- Close issues #213, #215, #217 (auto-close via PR)

## Key Files

- `gol-project/scripts/debug/console_panel.gd` — Console UI panel with ImGui InputText, completion logic, guard mechanism
- `gol-project/scripts/debug/debug_panel.gd` — Main debug panel autoload, DPI scaling, Ctrl+P handler, toggle logic
- `gol-project/scripts/services/impl/service_console.gd` — Console command service (NOT modified, has `get_completions()`, `get_recipe_completions()`)
- `gol-project/tests/unit/service/test_service_console.gd` — Unit tests for console service (NOT modified, all passing)
- `docs/superpowers/plans/2026-03-28-console-command-fixes.md` — Original implementation plan

## Important Decisions

- **ImGui.IsKeyPressed vs Input.is_key_pressed**: ImGui-native key detection is used for keys that ImGui intercepts (Tab, arrows, Escape inside InputText). Godot hardware polling is used for global shortcuts that must bypass ImGui (Ctrl+P, tilde).
- **Dynamic widget ID for buffer persistence**: ImGui InputText maintains an internal buffer keyed by widget ID. When the widget is active, it ignores the external buffer. Incrementing `_input_id` forces a new widget that reads from the external buffer.
- **Guard mechanism for auto-select protection**: ImGui 1.91.6 hardcodes select-all when InputText receives keyboard focus via `SetKeyboardFocusHere()`. No `NoAutoSelectAll` flag exists. The guard detects when typed input replaces selected completion text (input shorter than guard and not a prefix) and restores the completion + appends the typed character.
- **DPI: screen_get_scale() over screen_get_dpi()**: macOS returns non-standard values from `screen_get_dpi()`. The imgui-godot addon internally uses `DisplayServer.ScreenGetScale()` (C#). The GDScript equivalent `screen_get_scale()` returns 2.0 on Retina.
- **RebuildFontAtlas() must be called explicitly**: The native GDExtension singleton does NOT automatically rebuild fonts when `Scale` is set. The C# wrapper does this, but GDScript bypasses C# and accesses the native singleton directly.

## Constraints

- imgui-godot addon v6.3.2 (ImGui v1.91.6-docking) — native GDExtension, NOT C# plugin
- ImGui InputText auto-selects all text on keyboard focus — no flag to disable this in v1.91.6
- `ImGuiRoot` autoload processes `_input()` before `DebugPanel` — ImGui consumes keyboard events before game code
- GDScript changes require game restart to take effect

## Context for Continuation

- The guard mechanism (`_guard_completion` in `console_panel.gd`) is the likely cause of the Enter bug. When completions auto-show after Tab completion (because `_last_input = ""` forces `_update_completions`), pressing Enter applies completion instead of executing. Consider tracking whether the user actively navigated the completion list vs it being shown passively.
- For the game input blocking bug, look at how `_input()` in `debug_panel.gd` handles events. Currently only tilde calls `set_input_as_handled()`. When the console is open, ALL key events should be consumed to prevent game input.
- The `_update_mouse_mode()` in `debug_panel.gd` already handles mouse visibility. A similar approach for keyboard blocking would be to add `get_viewport().set_input_as_handled()` for all `InputEventKey` events when the panel is visible.
- Be aware that `Input.is_key_pressed()` (used for Ctrl+P) bypasses event consumption — so Ctrl+P will still work even if events are consumed. This is the desired behavior.
- The PR has 5 commits on branch `fix/console-command-improvements`. After fixing the remaining bugs, consider squashing or keeping the history as-is.

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
