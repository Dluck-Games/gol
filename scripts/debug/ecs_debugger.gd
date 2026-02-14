# ecs_debugger.gd - ImGui ECS Debugger Panel
# Displays Entity list, Component inspection, and GOAP debugging
class_name ECSDebugger
extends RefCounted

var _selected_entity: Entity = null
var _entity_filter: String = ""
var _component_filter: String = ""
var _show_disabled: bool = false


func get_selected_entity() -> Entity:
	return _selected_entity if is_instance_valid(_selected_entity) else null

func draw() -> void:
	if not ECS.world:
		ImGui.TextDisabled("(World not initialized)")
		return
	
	# Filter controls
	var filter_arr := [_entity_filter]
	if ImGui.InputText("Filter Entities", filter_arr, 256):
		_entity_filter = filter_arr[0]
	
	var show_disabled_arr := [_show_disabled]
	if ImGui.Checkbox("Show Disabled", show_disabled_arr):
		_show_disabled = show_disabled_arr[0]
	
	ImGui.Separator()
	
	# Two column layout using Begin/End Child
	var avail: Vector2 = ImGui.GetContentRegionAvail()
	
	# Left panel - Entity List (wider for long names)
	if ImGui.BeginChild("EntityList", Vector2(280, avail.y - 4), true):
		_draw_entity_list()
	ImGui.EndChild()
	
	ImGui.SameLine()
	
	# Right panel - Entity Details
	if ImGui.BeginChild("EntityDetails", Vector2(0, avail.y - 4), true):
		_draw_entity_details()
	ImGui.EndChild()


func _draw_entity_list() -> void:
	var entities: Array[Entity] = ECS.world.entities if ECS.world else []
	
	ImGui.Text("Entities (%d)" % entities.size())
	ImGui.Separator()
	
	for entity in entities:
		if not is_instance_valid(entity):
			continue
		
		# Filter by enabled state
		if not _show_disabled and not entity.enabled:
			continue
		
		# Filter by name
		var entity_name := _get_entity_display_name(entity)
		if _entity_filter.length() > 0 and entity_name.to_lower().find(_entity_filter.to_lower()) == -1:
			continue
		
		# Build label with component count
		var comp_count := entity.components.size()
		var label := "%s [%d]" % [entity_name, comp_count]
		
		# Disabled entities show differently
		if not entity.enabled:
			label = "(D) " + label
		
		# Selectable item - use unique label with selection indicator
		var is_selected := _selected_entity == entity
		var sel_label := ("* " if is_selected else "  ") + label
		if ImGui.Selectable(sel_label):
			_selected_entity = entity
		
		# Tooltip with component list
		if ImGui.IsItemHovered():
			ImGui.BeginTooltip()
			ImGui.Text("Components:")
			for comp_key in entity.components.keys():
				var comp_name := _get_component_name(comp_key)
				ImGui.BulletText(comp_name)
			ImGui.EndTooltip()


func _draw_entity_details() -> void:
	if not is_instance_valid(_selected_entity):
		ImGui.TextDisabled("(Select an entity)")
		_selected_entity = null
		return
	
	var entity := _selected_entity
	
	# Header
	ImGui.Text("Entity: %s" % _get_entity_display_name(entity))
	ImGui.TextDisabled("Node: %s" % entity.get_path())
	
	var enabled_arr := [entity.enabled]
	if ImGui.Checkbox("Enabled##entity", enabled_arr):
		entity.enabled = enabled_arr[0]
	
	ImGui.Separator()
	
	# Component filter
	var comp_filter_arr := [_component_filter]
	if ImGui.InputText("Filter Components", comp_filter_arr, 128):
		_component_filter = comp_filter_arr[0]
	
	ImGui.Separator()
	
	# Draw each component
	for comp_key in entity.components.keys():
		var component: Component = entity.components[comp_key]
		if not is_instance_valid(component):
			continue
		
		var comp_name := _get_component_name(comp_key)
		
		# Filter
		if _component_filter.length() > 0 and comp_name.to_lower().find(_component_filter.to_lower()) == -1:
			continue
		
		# Special handling for GOAP Agent
		if component is CGoapAgent:
			_draw_goap_agent(component as CGoapAgent, comp_name)
		else:
			_draw_component(component, comp_name)


func _draw_component(component: Component, comp_name: String) -> void:
	if ImGui.CollapsingHeader(comp_name):
		ImGui.Indent()
		_draw_component_properties(component)
		ImGui.Unindent()


func _draw_component_properties(component: Component) -> void:
	var props := component.get_property_list()
	var drawn_any := false
	
	for prop in props:
		# Only show script variables (user-defined)
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		
		# Skip Observable wrappers and internal vars
		var prop_name: String = prop.name
		if prop_name.ends_with("_observable") or prop_name.begins_with("_"):
			continue
		
		var value: Variant = component.get(prop_name)
		_draw_property(component, prop_name, prop.type, value)
		drawn_any = true
	
	if not drawn_any:
		ImGui.TextDisabled("(No editable properties)")


func _draw_property(obj: Object, name: String, type: int, value: Variant) -> void:
	var label := name + "##" + str(obj.get_instance_id())
	
	match type:
		TYPE_FLOAT:
			var arr := [value as float]
			if ImGui.DragFloat(label, arr):
				obj.set(name, arr[0])
		
		TYPE_INT:
			var arr := [value as int]
			if ImGui.DragInt(label, arr):
				obj.set(name, arr[0])
		
		TYPE_BOOL:
			var arr := [value as bool]
			if ImGui.Checkbox(label, arr):
				obj.set(name, arr[0])
		
		TYPE_STRING, TYPE_STRING_NAME:
			var arr := [str(value)]
			if ImGui.InputText(label, arr, 256):
				obj.set(name, arr[0])
		
		TYPE_VECTOR2:
			var v: Vector2 = value
			var arr := [v.x, v.y]
			if ImGui.DragFloat2(label, arr):
				obj.set(name, Vector2(arr[0], arr[1]))
		
		TYPE_VECTOR3:
			var v: Vector3 = value
			var arr := [v.x, v.y, v.z]
			if ImGui.DragFloat3(label, arr):
				obj.set(name, Vector3(arr[0], arr[1], arr[2]))
		
		TYPE_COLOR:
			var c: Color = value
			var arr := [c.r, c.g, c.b, c.a]
			if ImGui.ColorEdit4(label, arr):
				obj.set(name, Color(arr[0], arr[1], arr[2], arr[3]))
		
		TYPE_OBJECT:
			if value == null:
				ImGui.TextDisabled("%s: null" % name)
			elif value is Entity:
				var ent: Entity = value
				var ent_name := _get_entity_display_name(ent) if is_instance_valid(ent) else "(freed)"
				ImGui.Text("%s: %s" % [name, ent_name])
				if is_instance_valid(ent) and ImGui.IsItemClicked():
					_selected_entity = ent
			elif value is Resource:
				var res: Resource = value
				ImGui.Text("%s: %s" % [name, res.resource_path.get_file()])
			else:
				ImGui.Text("%s: %s" % [name, value.get_class()])
		
		TYPE_ARRAY:
			var arr: Array = value
			if ImGui.TreeNode("%s [%d]##%s" % [name, arr.size(), str(obj.get_instance_id())]):
				for i in range(mini(arr.size(), 20)):  # Limit display
					ImGui.Text("[%d]: %s" % [i, str(arr[i])])
				if arr.size() > 20:
					ImGui.TextDisabled("... and %d more" % (arr.size() - 20))
				ImGui.TreePop()
		
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			if ImGui.TreeNode("%s {%d}##%s" % [name, dict.size(), str(obj.get_instance_id())]):
				var keys := dict.keys()
				for i in range(mini(keys.size(), 20)):
					var k: Variant = keys[i]
					ImGui.Text("%s: %s" % [str(k), str(dict[k])])
				if keys.size() > 20:
					ImGui.TextDisabled("... and %d more" % (keys.size() - 20))
				ImGui.TreePop()
		
		_:
			ImGui.Text("%s: %s" % [name, str(value)])


func _draw_goap_agent(agent: CGoapAgent, comp_name: String) -> void:
	if ImGui.CollapsingHeader(comp_name):
		ImGui.Indent()
		
		# World State
		if ImGui.TreeNode("World State##goap"):
			if agent.world_state and agent.world_state.facts:
				for key in agent.world_state.facts.keys():
					var val: Variant = agent.world_state.facts[key]
					ImGui.BulletText("%s: %s" % [str(key), str(val)])
			else:
				ImGui.TextDisabled("(empty)")
			ImGui.TreePop()
		
		# Goals
		if ImGui.TreeNode("Goals [%d]##goap" % agent.goals.size()):
			for goal in agent.goals:
				if not is_instance_valid(goal):
					continue
				var goal_name: String = goal.get_script().resource_path.get_file().get_basename()
				var priority: int = goal.priority if "priority" in goal else 0
				ImGui.BulletText("%s (P:%d)" % [goal_name, priority])
				if ImGui.IsItemHovered() and "desired_state" in goal:
					ImGui.BeginTooltip()
					ImGui.Text("Desired State:")
					for k in goal.desired_state.keys():
						ImGui.Text("  %s: %s" % [str(k), str(goal.desired_state[k])])
					ImGui.EndTooltip()
			ImGui.TreePop()
		
		# Current Plan
		if ImGui.TreeNode("Current Plan##goap"):
			if agent.plan and agent.plan.steps.size() > 0:
				var step_idx := 0
				for step in agent.plan.steps:
					var action: GoapAction = step.action if step else null
					if not is_instance_valid(action):
						continue
					var action_name: String = action.get_script().resource_path.get_file().get_basename()
					var is_running := agent.running_action == action
					var prefix := ">> " if is_running else "   "
					ImGui.Text("%s%d. %s" % [prefix, step_idx, action_name])
					step_idx += 1
			else:
				ImGui.TextDisabled("(no plan)")
			
			if agent.plan_invalidated:
				ImGui.Text("! Plan Invalidated: %s" % agent.plan_invalidated_reason)
			ImGui.TreePop()
		
		# Running Action Details
		if agent.running_action and is_instance_valid(agent.running_action):
			if ImGui.TreeNode("Running Action##goap"):
				var action := agent.running_action
				var action_name: String = action.get_script().resource_path.get_file().get_basename()
				ImGui.Text("Action: %s" % action_name)
				ImGui.Text("Cost: %d" % action.cost)
				
				if action.preconditions:
					ImGui.Text("Preconditions:")
					for k in action.preconditions.keys():
						ImGui.BulletText("%s: %s" % [str(k), str(action.preconditions[k])])
				
				if action.effects:
					ImGui.Text("Effects:")
					for k in action.effects.keys():
						ImGui.BulletText("%s: %s" % [str(k), str(action.effects[k])])
				
				ImGui.TreePop()
		
		# Blackboard
		if ImGui.TreeNode("Blackboard##goap"):
			if agent.blackboard.size() > 0:
				for key in agent.blackboard.keys():
					var val: Variant = agent.blackboard[key]
					var val_str: String
					if val is Entity and is_instance_valid(val):
						val_str = _get_entity_display_name(val)
					elif val is WeakRef:
						var ref: Variant = val.get_ref()
						if ref and ref is Entity:
							val_str = _get_entity_display_name(ref) + " (weak)"
						else:
							val_str = "(freed)"
					else:
						val_str = str(val)
					ImGui.BulletText("%s: %s" % [str(key), val_str])
			else:
				ImGui.TextDisabled("(empty)")
			ImGui.TreePop()
		
		ImGui.Unindent()


func _get_entity_display_name(entity: Entity) -> String:
	if not is_instance_valid(entity):
		return "(freed)"
	
	# 直接使用 Entity 节点名称，保持与编辑器中 Authoring 节点名称一致
	return entity.name


func _get_component_name(resource_path: String) -> String:
	# Extract class name from path like "res://scripts/components/c_hp.gd"
	var file_name := resource_path.get_file().get_basename()
	return file_name
