# debug_panel.gd - ImGui Debug Panel
# Press ~ (tilde/grave) to toggle the debug panel
extends Node

const ECSDebuggerClass = preload("res://scripts/debug/ecs_debugger.gd")
const GoapDebuggerClass = preload("res://scripts/debug/goap_debugger.gd")
const EntityHighlightClass = preload("res://scripts/debug/entity_highlight.gd")
const ConsolePanelClass = preload("res://scripts/debug/console_panel.gd")

const CONFIG_PATH := "user://debug_panel.cfg"

var _visible := [false]
var _ecs_debugger_visible := [false]
var _goap_debugger_visible := [false]
var _console_visible := [false]
var _console_was_visible := false  # Track state change for focus
var _ecs_debugger: RefCounted = null
var _goap_debugger: RefCounted = null
var _console_panel: RefCounted = null
var _entity_highlight: Node2D = null

# Window state persistence
var _window_config := ConfigFile.new()
var _save_timer: float = 0.0
var _needs_save: bool = false

func _ready() -> void:
	# Check if ImGui is available (native library loaded)
	if not ClassDB.class_exists("ImGuiController"):
		return

	print("[DebugPanel] Ready - press ~ to toggle")
	_setup_entity_highlight()
	_load_window_config()


func _ensure_debuggers_initialized() -> void:
	if not _ecs_debugger:
		_ecs_debugger = ECSDebuggerClass.new()
	if not _goap_debugger:
		_goap_debugger = GoapDebuggerClass.new()
	if not _console_panel:
		_console_panel = ConsolePanelClass.new()


func _find_node_by_class(node: Node, target_class_name: String) -> Node:
	# Recursively search for node by class name
	if node.get_class() == target_class_name or (node.get_script() and node.get_script().get_global_name() == target_class_name):
		return node
	for child in node.get_children():
		var result := _find_node_by_class(child, target_class_name)
		if result:
			return result
	return null


func _input(event: InputEvent) -> void:
	# Toggle with ~ key (grave/tilde)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT or event.physical_keycode == KEY_QUOTELEFT:
			_visible[0] = not _visible[0]
			_update_mouse_mode()
			get_viewport().set_input_as_handled()
		# Ctrl+P to toggle console window
		elif event.keycode == KEY_P and event.ctrl_pressed:
			_console_visible[0] = not _console_visible[0]
			_update_mouse_mode()
			get_viewport().set_input_as_handled()


## 根据调试面板状态更新鼠标指针可见性
func _update_mouse_mode() -> void:
	if _visible[0] or _console_visible[0]:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func _process(_delta: float) -> void:
	# Delayed save to avoid saving every frame
	if _needs_save:
		_save_timer += _delta
		if _save_timer > 1.0:  # Save after 1 second of no changes
			_save_window_config()
			_needs_save = false
			_save_timer = 0.0
	
	# Check if ImGui is available (native library loaded)
	if not ClassDB.class_exists("ImGuiController"):
		return
	
	# Lazy init debuggers when any panel opens
	if _visible[0] or _console_visible[0]:
		_ensure_debuggers_initialized()
	
	# Console window can be shown independently (Ctrl+P)
	if _console_visible[0] and _console_panel:
		# Request focus when console just opened
		if not _console_was_visible:
			_console_panel.request_focus()
		_console_panel.draw_window(_console_visible)
	_console_was_visible = _console_visible[0]
	
	if not _visible[0]:
		_update_highlight_target(null)
		return
	
	# Main debug panel
	if ImGui.Begin("Debug Panel", _visible):
		# Console input at top (only if console window is NOT open)
		if _console_panel and not _console_visible[0]:
			_console_panel.draw_input_only()
			ImGui.Separator()
		ImGui.Text("God of Lego - Debug")
		ImGui.Separator()
		
	# Quick access debugger buttons (compact, inline)
	var ecs_label := "[ECS]" if _ecs_debugger_visible[0] else "ECS"
	var goap_label := "[GOAP]" if _goap_debugger_visible[0] else "GOAP"
	var console_label := "[Console]" if _console_visible[0] else "Console"
	
	if ImGui.SmallButton(ecs_label):
		_ecs_debugger_visible[0] = not _ecs_debugger_visible[0]
	ImGui.SameLine()
	if ImGui.SmallButton(goap_label):
		_goap_debugger_visible[0] = not _goap_debugger_visible[0]
	ImGui.SameLine()
	if ImGui.SmallButton(console_label):
		_console_visible[0] = not _console_visible[0]
	
	ImGui.Separator()
	
	# FPS display
	if ImGui.CollapsingHeader("Stats", true):
		ImGui.Text("FPS: %d" % Engine.get_frames_per_second())
		ImGui.Text("Delta: %.2f ms" % (_delta * 1000.0))
	
	# ECS Summary section
	if ImGui.CollapsingHeader("ECS Info"):
		_draw_ecs_summary()
	
	# Performance section
	if ImGui.CollapsingHeader("Performance"):
		_draw_performance()
	
	ImGui.End()
	
	# ECS Debugger as separate window (right side, 1/3 screen)
	var highlight_target: Entity = null
	if _ecs_debugger_visible[0] and _ecs_debugger:
		_draw_ecs_debugger_window()
		highlight_target = _ecs_debugger.get_selected_entity()
	
	# GOAP Debugger as separate window
	if _goap_debugger_visible[0] and _goap_debugger:
		_draw_goap_debugger_window()
		# GOAP debugger takes priority if both open
		var goap_target: Entity = _goap_debugger.get_selected_entity()
		if goap_target:
			highlight_target = goap_target
	
	
	_update_highlight_target(highlight_target)


func _draw_ecs_summary() -> void:
	if not ECS.world:
		ImGui.TextDisabled("(World not initialized)")
		return
	
	var entity_count := ECS.world.entities.size() if ECS.world.entities else 0
	var system_count := ECS.world.systems.size() if ECS.world.systems else 0
	var component_types := ECS.world.component_entity_index.size() if ECS.world.component_entity_index else 0
	
	ImGui.Text("Entities: %d" % entity_count)
	ImGui.Text("Systems: %d" % system_count)
	ImGui.Text("Component Types: %d" % component_types)


var _ecs_window_initialized := false
var _goap_window_initialized := false
var _ecs_window_pos: Vector2 = Vector2.ZERO
var _ecs_window_size: Vector2 = Vector2.ZERO
var _goap_window_pos: Vector2 = Vector2.ZERO
var _goap_window_size: Vector2 = Vector2.ZERO

func _draw_ecs_debugger_window() -> void:
	# Calculate default window position and size (right 40% of screen)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Set initial position and size only once
	if not _ecs_window_initialized:
		# Use saved values or defaults
		if _ecs_window_size == Vector2.ZERO:
			_ecs_window_size = Vector2(viewport_size.x * 0.4, viewport_size.y - 40)
			_ecs_window_pos = Vector2(viewport_size.x - _ecs_window_size.x - 10, 30)
		ImGui.SetNextWindowPos(_ecs_window_pos)
		ImGui.SetNextWindowSize(_ecs_window_size)
		_ecs_window_initialized = true
	
	# Window with close button
	if ImGui.Begin("ECS Debugger", _ecs_debugger_visible):
		_ecs_debugger.draw()
		
		# Track window changes
		var new_pos: Vector2 = ImGui.GetWindowPos()
		var new_size: Vector2 = ImGui.GetWindowSize()
		if new_pos != _ecs_window_pos or new_size != _ecs_window_size:
			_ecs_window_pos = new_pos
			_ecs_window_size = new_size
			_mark_needs_save()
	ImGui.End()


func _draw_goap_debugger_window() -> void:
	# Calculate default window position and size (right 40% of screen)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Set initial position and size only once
	if not _goap_window_initialized:
		# Use saved values or defaults
		if _goap_window_size == Vector2.ZERO:
			_goap_window_size = Vector2(viewport_size.x * 0.4, viewport_size.y * 0.85)
			_goap_window_pos = Vector2(viewport_size.x - _goap_window_size.x - 10, (viewport_size.y - _goap_window_size.y) / 2)
		ImGui.SetNextWindowPos(_goap_window_pos)
		ImGui.SetNextWindowSize(_goap_window_size)
		_goap_window_initialized = true
	
	# Window with close button
	if ImGui.Begin("GOAP Debugger", _goap_debugger_visible):
		_goap_debugger.draw()
		
		# Track window changes
		var new_pos: Vector2 = ImGui.GetWindowPos()
		var new_size: Vector2 = ImGui.GetWindowSize()
		if new_pos != _goap_window_pos or new_size != _goap_window_size:
			_goap_window_pos = new_pos
			_goap_window_size = new_size
			_mark_needs_save()
	ImGui.End()




func _draw_performance() -> void:
	ImGui.Text("Process: %.2f ms" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000))
	ImGui.Text("Physics: %.2f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000))
	ImGui.Text("Objects: %d" % Performance.get_monitor(Performance.OBJECT_COUNT))
	ImGui.Text("Memory: %.1f MiB" % (OS.get_static_memory_usage() / 1048576.0))


func _setup_entity_highlight() -> void:
	# Create highlight node and add to scene tree
	# We need to add it to a CanvasLayer to ensure it renders on top
	_entity_highlight = EntityHighlightClass.new()
	_entity_highlight.z_index = 1000  # Render on top
	
	# Defer adding to tree to ensure scene is ready
	call_deferred("_add_highlight_to_scene")


func _add_highlight_to_scene() -> void:
	# Find the game world or root to add highlight
	var root: Node = get_tree().current_scene
	if not root:
		# Try to find any valid parent in the scene tree
		root = get_tree().root
	if root:
		var canvas := CanvasLayer.new()
		canvas.add_child(_entity_highlight)
		root.add_child(canvas)
	else:
		# Last resort: add as direct child of this node
		add_child(_entity_highlight)


func _update_highlight_target(entity: Entity) -> void:
	if _entity_highlight:
		_entity_highlight.target_entity = entity


func _load_window_config() -> void:
	if _window_config.load(CONFIG_PATH) == OK:
		_ecs_window_pos.x = _window_config.get_value("ecs", "pos_x", 0.0)
		_ecs_window_pos.y = _window_config.get_value("ecs", "pos_y", 0.0)
		_ecs_window_size.x = _window_config.get_value("ecs", "size_x", 0.0)
		_ecs_window_size.y = _window_config.get_value("ecs", "size_y", 0.0)
		
		_goap_window_pos.x = _window_config.get_value("goap", "pos_x", 0.0)
		_goap_window_pos.y = _window_config.get_value("goap", "pos_y", 0.0)
		_goap_window_size.x = _window_config.get_value("goap", "size_x", 0.0)
		_goap_window_size.y = _window_config.get_value("goap", "size_y", 0.0)
		
		print("[DebugPanel] Loaded window config")


func _save_window_config() -> void:
	_window_config.set_value("ecs", "pos_x", _ecs_window_pos.x)
	_window_config.set_value("ecs", "pos_y", _ecs_window_pos.y)
	_window_config.set_value("ecs", "size_x", _ecs_window_size.x)
	_window_config.set_value("ecs", "size_y", _ecs_window_size.y)
	
	_window_config.set_value("goap", "pos_x", _goap_window_pos.x)
	_window_config.set_value("goap", "pos_y", _goap_window_pos.y)
	_window_config.set_value("goap", "size_x", _goap_window_size.x)
	_window_config.set_value("goap", "size_y", _goap_window_size.y)
	
	_window_config.save(CONFIG_PATH)
	print("[DebugPanel] Saved window config")


func _mark_needs_save() -> void:
	_needs_save = true
	_save_timer = 0.0
