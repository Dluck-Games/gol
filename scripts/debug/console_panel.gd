# console_panel.gd - Console UI Panel for ImGui
# Provides input field with auto-completion and command history
class_name ConsolePanel
extends RefCounted

const MAX_HISTORY := 50
const MAX_OUTPUT_LINES := 100

var _input: String = ""
var _history: Array[String] = []
var _history_index: int = -1
var _output_lines: Array[String] = []
var _show_completions: bool = false
var _completions: Array[String] = []
var _completion_index: int = 0
var _scroll_to_bottom: bool = false
var _reclaim_focus: bool = false  # Reclaim focus without selecting all
var _last_input: String = ""
var _input_rect_min: Vector2 = Vector2.ZERO
var _tab_was_pressed: bool = false  # Track Tab key state for edge detection


func _get_console() -> Service_Console:
	return ServiceContext.console()


## Draw the console panel (embedded mode - just input + output)
func draw() -> void:
	_draw_input()
	ImGui.Separator()
	_draw_output()


## Draw only the input field (for compact mode)
func draw_input_only() -> void:
	_draw_input()


## Draw the full console window (standalone mode)
func draw_window(visible: Array) -> void:
	ImGui.SetNextWindowSize(Vector2(500, 300), ImGui.Cond_FirstUseEver)
	
	if ImGui.Begin("Console", visible):
		_draw_input()
		ImGui.Separator()
		_draw_output()
	ImGui.End()


## Request focus on next frame
func request_focus() -> void:
	_reclaim_focus = true


func _draw_input() -> void:
	ImGui.PushItemWidth(-1)
	
	# Reclaim focus
	if _reclaim_focus:
		ImGui.SetKeyboardFocusHere()
		_reclaim_focus = false
	
	var input_arr := [_input]
	
	# Simple input - just EnterReturnsTrue
	var enter_pressed := ImGui.InputTextWithHint("##console_input", "Enter command...", input_arr, 256, ImGui.InputTextFlags_EnterReturnsTrue)
	
	# Store positions
	_input_rect_min = ImGui.GetItemRectMin()
	var is_focused := ImGui.IsItemFocused()
	var is_active := ImGui.IsItemActive()
	
	if enter_pressed:
		if _show_completions and _completions.size() > 0:
			_apply_completion()
		else:
			_execute_input(input_arr[0])
			_input = ""
			_history_index = -1
			_show_completions = false
			_last_input = _input
		_reclaim_focus = true
	else:
		_input = input_arr[0]
		if _input != _last_input:
			_last_input = _input
			_update_completions()
	
	# Handle keys when focused
	if is_focused or is_active:
		if _show_completions and _completions.size() > 0:
			# Tab confirms completion - use Godot Input since ImGui consumes Tab
			if Input.is_key_pressed(KEY_TAB) and not _tab_was_pressed:
				_apply_completion()
				_tab_was_pressed = true
			elif not Input.is_key_pressed(KEY_TAB):
				_tab_was_pressed = false
			
			if ImGui.IsKeyPressed(ImGui.Key_UpArrow):
				_completion_index = (_completion_index - 1 + _completions.size()) % _completions.size()
			elif ImGui.IsKeyPressed(ImGui.Key_DownArrow):
				_completion_index = (_completion_index + 1) % _completions.size()
			elif ImGui.IsKeyPressed(ImGui.Key_Escape):
				_show_completions = false
		else:
			_tab_was_pressed = false
			if ImGui.IsKeyPressed(ImGui.Key_UpArrow):
				_navigate_history(-1)
			elif ImGui.IsKeyPressed(ImGui.Key_DownArrow):
				_navigate_history(1)
	
	ImGui.PopItemWidth()
	
	# Draw completions inline (not as separate window to avoid flicker)
	if _show_completions and _completions.size() > 0:
		_draw_completions_inline()


func _draw_output() -> void:
	# Scrollable output area
	var available := ImGui.GetContentRegionAvail()
	if ImGui.BeginChild("console_output", Vector2(available.x, available.y), false, ImGui.WindowFlags_HorizontalScrollbar):
		for line in _output_lines:
			# Color code output
			if line.begins_with("> "):
				ImGui.PushStyleColor(ImGui.Col_Text, Color(0.6, 0.8, 1.0, 1.0))
				ImGui.TextWrapped(line)
				ImGui.PopStyleColor()
			elif line.begins_with("Error"):
				ImGui.PushStyleColor(ImGui.Col_Text, Color(1.0, 0.4, 0.4, 1.0))
				ImGui.TextWrapped(line)
				ImGui.PopStyleColor()
			else:
				ImGui.TextWrapped(line)
		
		if _scroll_to_bottom:
			ImGui.SetScrollHereY(1.0)
			_scroll_to_bottom = false
	ImGui.EndChild()


func _draw_completions_inline() -> void:
	# Draw completions as simple text list (no separate window = no flicker)
	ImGui.PushStyleColor(ImGui.Col_ChildBg, Color(0.15, 0.15, 0.15, 0.95))
	var height := mini(_completions.size(), 8) * ImGui.GetTextLineHeightWithSpacing() + 8
	if ImGui.BeginChild("##completions", Vector2(0, height), true):
		for i in range(_completions.size()):
			if i == _completion_index:
				ImGui.TextColored(Color(1.0, 1.0, 0.4, 1.0), "> " + _completions[i])
			else:
				ImGui.Text("  " + _completions[i])
	ImGui.EndChild()
	ImGui.PopStyleColor()


func _execute_input(input: String) -> void:
	var trimmed := input.strip_edges()
	if trimmed.is_empty():
		return
	
	# Add to history
	if _history.is_empty() or _history[0] != trimmed:
		_history.insert(0, trimmed)
		if _history.size() > MAX_HISTORY:
			_history.resize(MAX_HISTORY)
	
	# Add input to output
	_add_output("> " + trimmed)
	
	# Execute and add result
	var result := _get_console().execute(trimmed)
	if not result.is_empty():
		_add_output(result)


func _add_output(text: String) -> void:
	# Split multiline output
	var lines := text.split("\n")
	for line in lines:
		_output_lines.append(line)
	
	# Trim old lines
	while _output_lines.size() > MAX_OUTPUT_LINES:
		_output_lines.remove_at(0)
	
	_scroll_to_bottom = true


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


func _update_completions() -> void:
	# Only auto-complete command (first word), not arguments
	var parts := _input.strip_edges().split(" ", false)
	if parts.size() > 1:
		# Already typing arguments, hide completions
		_show_completions = false
		return
	
	var partial := parts[0] if parts.size() > 0 else ""
	_completions = _get_console().get_completions(partial)
	
	if _completions.size() > 0:
		_show_completions = true
		_completion_index = 0
	else:
		_show_completions = false


func _apply_completion() -> void:
	if _completions.size() > 0 and _completion_index < _completions.size():
		_input = _completions[_completion_index] + " "
		_last_input = _input
		_show_completions = false
		# Don't set reclaim_focus here to avoid text selection


func _navigate_history(direction: int) -> void:
	if _history.is_empty():
		return
	
	_history_index += direction
	_history_index = clampi(_history_index, -1, _history.size() - 1)
	
	if _history_index >= 0:
		_input = _history[_history_index]
	else:
		_input = ""
	
	_show_completions = false


## Clear output
func clear() -> void:
	_output_lines.clear()
