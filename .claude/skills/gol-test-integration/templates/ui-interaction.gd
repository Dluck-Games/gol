class_name TestUIInteractionTemplate
extends SceneConfig

## Template: UI / node-tree interaction test pattern.
## Based on: test_flow_composer_interaction_scene.gd (184 lines, 8 helpers, most complex)
## Advanced: input simulation, signal emission, HUD reactivity, node traversal by script type

func scene_name() -> String:
	return "test"


func systems() -> Variant:
	return [
		"res://scripts/systems/ui/s_ui.gd",
		"res://scripts/systems/s_dialogue.gd",
		# Add more UI systems as needed:
		# "res://scripts/systems/s_inventory.gd",
	]


func enable_pcg() -> bool:
	return false


func entities() -> Variant:
	return null  # Uses DEFAULT scene spawning (Player + NPCs from scene)


func test_run(world: GOLWorld) -> Variant:
	var result := TestResult.new()
	await world.get_tree().process_frame
	await world.get_tree().process_frame

	# Save initial mouse mode for restore check
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var initial_mouse_mode: Input.MouseMode = Input.get_mouse_mode()

	# --- Find UI nodes by script type (NOT name) ---
	var {{UI_NODE_VAR}} := _find_node_by_script(world, {{UI_NODE_SCRIPT_CLASS}})
	result.assert_true({{UI_NODE_VAR}} != null, "{{UI_NODE_DESC}} found")
	if {{UI_NODE_VAR}} == null:
		return result

	# --- Simulate user input ---
	_push_key(world, {{KEY_CODE}})
	await world.get_tree().process_frame
	await world.get_tree().process_frame

	# Assert UI state changed after input
	result.assert_true({{CONDITION_AFTER_INPUT}}, "{{ASSERTION_DESCRIPTION}}")

	# --- Signal-driven interaction (button press, dialogue open, etc.) ---
	# {{SIGNAL_INTERACTION_BLOCK}}

	# --- HUD reactivity check (mutate state, emit signal, verify label) ---
	# {{HUD_REACTIVITY_BLOCK}}

	return result


# --- UI Helpers ---

func _find_node_by_script(world: GOLWorld, script_class: GDScript) -> Node:
	## Traverse world tree to find first Node with matching script class.
	## Pattern from: composer_interaction test (finds dialogue views, hints, HP bars)
	var stack: Array[Node] = [world]
	while stack.size() > 0:
		var current: Node = stack.pop_back()
		if current.get_script() == script_class:
			return current
		for child in current.get_children():
			stack.append(child)
	return null


func _push_key(world: GOLWorld, keycode: int) -> void:
	## Simulate a key press event via viewport input.
	## Pattern from: composer_interaction test (KEY_E for interaction)
	var press_event := InputEventKey.new()
	press_event.keycode = keycode
	press_event.physical_keycode = keycode
	press_event.pressed = true
	world.get_viewport().push_input(press_event)


func _find_child_with_text(control: Control, text: String) -> Control:
	## Find a Label/RichTextLabel child containing specific text.
	## Useful for HUD label verification without hardcoding node paths.
	for child in control.get_children():
		if child is Label and (child as Label).text.contains(text):
			return child as Control
		if child is RichTextLabel and (child as RichTextLabel).text.contains(text):
			return child as Control
		var found := _find_child_with_text(child, text)
		if found != null:
			return found
	return null


## Extension Patterns (commented examples from composer_interaction test)

## 1. Signal-driven button press (emit pressed, await frames, assert result):
# var close_button := _find_dialogue_button({{UI_NODE_VAR}}, "离开")
# if close_button != null:
#     close_button.pressed.emit()
#     await world.get_tree().process_frame
#     await world.get_tree().process_frame
#     result.assert_true(_find_node_by_script(world, {{UI_NODE_SCRIPT_CLASS}}) == null,
#         "Dialogue dismissed after close")

## 2. HUD reactivity (mutate game state, emit signal, verify label update):
# GOL.Player.component_points = CONFIG.CRAFT_COST
# GOL.Player.points_changed.emit(GOL.Player.component_points)
# await world.get_tree().process_frame
# var hud_label := _find_child_with_text(ServiceContext.ui().hud_layer, "组件点")
# if hud_label != null:
#     result.assert_equal((hud_label as Label).text, "组件点: 2", "HUD updated after points change")

## 3. Mouse mode save/restore (capture before, assert during, verify after):
# result.assert_equal(Input.get_mouse_mode(), Input.MOUSE_MODE_VISIBLE,
#     "Opening dialogue releases mouse for UI")
# ... after close ...
# result.assert_equal(Input.get_mouse_mode(), initial_mouse_mode,
#     "Closing dialogue restores previous mouse mode")

## 4. Distance-based interaction range assertion:
# var player_transform: CTransform = player.get_component(CTransform)
# var npc_transform: CTransform = npc.get_component(CTransform)
# var distance: float = player_transform.position.distance_to(npc_transform.position)
# result.assert_true(distance <= CONFIG.DIALOGUE_RANGE,
#     "NPC within dialogue range (%.2f <= %.2f)" % [distance, CONFIG.DIALOGUE_RANGE])

## 5. Dialogue option counting and content verification:
# var options_container := dialogue.get_node_or_null("CenterContainer/Panel/MarginContainer/VBoxContainer/OptionsContainer")
# if options_container != null:
#     result.assert_true(options_container.get_child_count() >= 1, "Dialogue has at least one option")
#     for option in options_container.get_children():
#         var btn := option as Button
#         if btn != null:
#             result.assert_true(btn.text.length() > 0, "Option has visible text: %s" % btn.text)

## 6. When to use entities()=null vs explicit entities:
#   entities()=null  → Use when testing scene-default spawns (Player + placed NPCs).
#                       The scene's own setup provides the entities you need.
#                       Best for: dialogue tests, HUD tests, interaction flow tests.
#   explicit list    → Use when you need controlled entity placement at specific positions,
#                       custom component overrides, or no default scene entities exist.
#                       Best for: combat tests, pickup tests, PCG-dependent tests.
