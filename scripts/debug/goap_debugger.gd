# goap_debugger.gd - ImGui GOAP Debugger Panel
# World State inspector with force state toggle and goal satisfaction indicators
class_name GoapDebugger
extends RefCounted

## Currently selected GOAP agent to inspect
var _selected_agent: CGoapAgent = null
## Track which entity owns the selected agent
var _selected_entity: Entity = null

## Entity filter string
var _entity_filter: String = ""


func get_selected_entity() -> Entity:
	return _selected_entity if is_instance_valid(_selected_entity) else null

## Replan tracking per agent (entity_id -> tracking data)
var _replan_tracking: Dictionary = {}

## Time window for replan detection (seconds)
const REPLAN_WINDOW := 5.0
## Threshold for "thrashing" warning
const REPLAN_THRASH_THRESHOLD := 3


func draw() -> void:
	if not ECS.world:
		ImGui.TextDisabled("(World not initialized)")
		return
	
	# Agent selector with filter
	_draw_agent_selector()
	
	ImGui.Separator()
	
	if not _selected_agent or not is_instance_valid(_selected_agent):
		ImGui.TextDisabled("(Select a GOAP Agent)")
		return
	
	# Action buttons
	_draw_action_buttons()
	
	ImGui.Separator()
	
	# Performance & Error tracking section
	_draw_performance_tracking()
	
	ImGui.Separator()
	
	# World State section with force toggle
	_draw_world_state()
	
	ImGui.Separator()
	
	# Goals with satisfaction status
	_draw_goals()
	
	ImGui.Separator()
	
	# Current Plan with detailed action info
	_draw_current_plan()
	
	ImGui.Separator()
	
	# Blackboard
	_draw_blackboard()


func _draw_agent_selector() -> void:
	# Filter input
	var filter_arr := [_entity_filter]
	if ImGui.InputText("Filter##agent_filter", filter_arr, 128):
		_entity_filter = filter_arr[0]
	
	ImGui.Separator()
	
	# Find all entities with CGoapAgent
	var agents: Array[Entity] = []
	if ECS.world:
		for entity in ECS.world.entities:
			if is_instance_valid(entity) and entity.has_component(CGoapAgent):
				agents.append(entity)
	
	if agents.is_empty():
		ImGui.TextDisabled("(No GOAP agents found)")
		return
	
	# Update tracking for all agents (needed for status display)
	var current_time := Time.get_ticks_msec() / 1000.0
	for entity in agents:
		_update_agent_tracking(entity, current_time)
	
	# Count filtered results
	var filtered_count := 0
	for entity in agents:
		var label := _get_entity_display_name(entity)
		if _entity_filter.length() == 0 or label.to_lower().find(_entity_filter.to_lower()) != -1:
			filtered_count += 1
	
	ImGui.Text("Agents: %d/%d" % [filtered_count, agents.size()])
	
	# Scrollable agent list
	if ImGui.BeginChild("AgentList", Vector2(0, 120), true):
		for entity in agents:
			var agent: CGoapAgent = entity.get_component(CGoapAgent)
			if not agent:
				continue
			
			var label := _get_entity_display_name(entity)
			
			# Apply filter
			if _entity_filter.length() > 0 and label.to_lower().find(_entity_filter.to_lower()) == -1:
				continue
			
			# Build status indicators
			var status_prefix := ""
			var entity_id := entity.get_instance_id()
			
			if _replan_tracking.has(entity_id):
				var tracking: Dictionary = _replan_tracking[entity_id]
				var replan_count: int = tracking["timestamps"].size()
				
				# Thrashing warning
				if replan_count >= REPLAN_THRASH_THRESHOLD:
					status_prefix += "[!T] "
				
				# Plan invalidated
				if agent.plan_invalidated:
					status_prefix += "[!P] "
				
				# No plan
				if not agent.plan:
					status_prefix += "[?] "
			
			var is_selected := _selected_entity == entity
			var sel_marker := ">> " if is_selected else "   "
			var full_label := sel_marker + status_prefix + label
			
			if ImGui.Selectable(full_label):
				_selected_entity = entity
				_selected_agent = agent
			
			# Tooltip with quick status
			if ImGui.IsItemHovered():
				_draw_agent_tooltip(entity, agent)
	
	ImGui.EndChild()
	
	# Legend
	ImGui.TextDisabled("[!T]=Thrashing [!P]=PlanInvalid [?]=NoPlan")


func _draw_agent_tooltip(entity: Entity, agent: CGoapAgent) -> void:
	ImGui.BeginTooltip()
	
	var entity_id := entity.get_instance_id()
	
	# Current goal
	var goal_name := _get_current_goal_name(agent)
	if goal_name != "":
		ImGui.Text("Goal: %s" % goal_name)
	else:
		ImGui.TextDisabled("No active goal")
	
	# Current action
	if agent.running_action:
		var action_name: String = agent.running_action.get_script().resource_path.get_file().get_basename()
		ImGui.Text("Action: %s" % action_name)
	
	# Tracking status
	if _replan_tracking.has(entity_id):
		var tracking: Dictionary = _replan_tracking[entity_id]
		var replan_count: int = tracking["timestamps"].size()
		
		ImGui.Separator()
		
		if replan_count >= REPLAN_THRASH_THRESHOLD:
			ImGui.Text("[!] THRASHING: %d replans in %.0fs" % [replan_count, REPLAN_WINDOW])
		else:
			ImGui.Text("Replans: %d" % replan_count)
		
		if agent.plan_invalidated:
			ImGui.Text("[!] Plan Invalid: %s" % agent.plan_invalidated_reason)
	
	ImGui.EndTooltip()


func _draw_action_buttons() -> void:
	# Force replan button
	if ImGui.Button("Force Replan"):
		_selected_agent.plan_invalidated = true
		_selected_agent.plan_invalidated_reason = "Debug: Manual replan"
	
	ImGui.SameLine()
	
	# Clear plan button
	if ImGui.Button("Clear Plan"):
		_selected_agent.plan = null
		_selected_agent.running_action = null
		_selected_agent.plan_invalidated = true
		_selected_agent.plan_invalidated_reason = "Debug: Plan cleared"
	
	ImGui.SameLine()
	
	# Reset world state button
	if ImGui.Button("Reset Tracking"):
		var entity_id := _selected_entity.get_instance_id()
		if _replan_tracking.has(entity_id):
			_replan_tracking[entity_id]["timestamps"] = []
			_replan_tracking[entity_id]["failure_reason"] = ""


func _update_agent_tracking(entity: Entity, current_time: float) -> void:
	var agent: CGoapAgent = entity.get_component(CGoapAgent)
	if not agent:
		return
	
	var entity_id := entity.get_instance_id()
	
	# Initialize tracking if needed
	if not _replan_tracking.has(entity_id):
		_replan_tracking[entity_id] = {
			"timestamps": [],
			"last_plan_hash": 0,
			"last_goal_name": "",
			"failure_reason": "",
			"failure_time": 0.0
		}
	
	var tracking: Dictionary = _replan_tracking[entity_id]
	
	# Detect replan by checking if plan changed
	var current_plan_hash := _get_plan_hash(agent)
	var current_goal := _get_current_goal_name(agent)
	
	if current_plan_hash != tracking["last_plan_hash"] and tracking["last_plan_hash"] != 0:
		tracking["timestamps"].append(current_time)
		
		if current_goal != tracking["last_goal_name"] and tracking["last_goal_name"] != "":
			tracking["goal_switch"] = {
				"from": tracking["last_goal_name"],
				"to": current_goal,
				"time": current_time
			}
	
	tracking["last_plan_hash"] = current_plan_hash
	tracking["last_goal_name"] = current_goal
	
	# Clean old timestamps
	var valid_timestamps: Array = []
	for ts in tracking["timestamps"]:
		if current_time - ts < REPLAN_WINDOW:
			valid_timestamps.append(ts)
	tracking["timestamps"] = valid_timestamps
	
	# Track plan failure
	if agent.plan_invalidated and agent.plan_invalidated_reason != "":
		tracking["failure_reason"] = agent.plan_invalidated_reason
		tracking["failure_time"] = current_time


func _draw_performance_tracking() -> void:
	if not ImGui.CollapsingHeader("Performance & Errors"):
		return
	
	ImGui.Indent()
	
	var entity_id := _selected_entity.get_instance_id()
	var tracking: Dictionary = _replan_tracking.get(entity_id, {})
	var current_time := Time.get_ticks_msec() / 1000.0
	
	# Display replan count
	var replan_count: int = tracking.get("timestamps", []).size()
	var replan_text := "Replans (last %.0fs): %d" % [REPLAN_WINDOW, replan_count]
	
	if replan_count >= REPLAN_THRASH_THRESHOLD:
		ImGui.Text("[!] %s - THRASHING!" % replan_text)
	else:
		ImGui.Text(replan_text)
	
	# Show goal switch warning
	if tracking.has("goal_switch"):
		var switch_data: Dictionary = tracking["goal_switch"]
		if current_time - switch_data["time"] < 3.0:
			ImGui.Text("[!] Goal switch: %s -> %s" % [switch_data["from"], switch_data["to"]])
	
	# Show recent failure
	var failure_reason: String = tracking.get("failure_reason", "")
	var failure_time: float = tracking.get("failure_time", 0.0)
	if failure_reason != "" and current_time - failure_time < 10.0:
		ImGui.Separator()
		ImGui.Text("[X] Plan Failed:")
		ImGui.TextWrapped("    %s" % failure_reason)
	
	# Show if no plan could be generated
	if not _selected_agent.plan and not _selected_agent.plan_invalidated:
		ImGui.Separator()
		ImGui.Text("[X] No Plan Generated")
		_draw_unsatisfied_preconditions()
	
	ImGui.Unindent()


func _draw_unsatisfied_preconditions() -> void:
	var world_state := _selected_agent.world_state.facts if _selected_agent.world_state else {}
	var goals := _selected_agent.goals
	
	# Find highest priority unsatisfied goal
	var target_goal: GoapGoal = null
	for goal in goals:
		if is_instance_valid(goal) and not goal.is_satisfied(world_state):
			if target_goal == null or goal.priority > target_goal.priority:
				target_goal = goal
	
	if not target_goal:
		ImGui.TextDisabled("    (All goals satisfied)")
		return
	
	var goal_name: String = target_goal.goal_name if target_goal.goal_name else "Unknown"
	ImGui.Text("    Target: %s" % goal_name)
	
	# Find what states are needed but no action provides
	var needed_states: Dictionary = {}
	for key in target_goal.desired_state.keys():
		var desired: bool = target_goal.desired_state[key]
		var current: bool = world_state.get(key, false)
		if current != desired:
			needed_states[key] = desired
	
	if needed_states.is_empty():
		return
	
	ImGui.Text("    Unsatisfied conditions:")
	
	var actions := GoapPlanner.get_all_actions()
	for key in needed_states.keys():
		var needed_val: bool = needed_states[key]
		var providers: Array[String] = []
		
		for action in actions:
			if action.effects.has(key) and action.effects[key] == needed_val:
				var action_name: String = action.get_script().resource_path.get_file().get_basename()
				providers.append(action_name)
		
		if providers.is_empty():
			ImGui.Text("      [!] %s=%s - NO ACTION PROVIDES THIS" % [key, str(needed_val)])
		else:
			ImGui.Text("      %s=%s (providers: %s)" % [key, str(needed_val), ", ".join(providers)])


func _draw_world_state() -> void:
	if not ImGui.CollapsingHeader("World State (Click to Force Toggle)"):
		return
	
	ImGui.Indent()
	
	var world_state := _selected_agent.world_state
	if not world_state or world_state.facts.is_empty():
		ImGui.TextDisabled("(empty)")
		ImGui.Unindent()
		return
	
	var desired_states := _collect_desired_states()
	var keys := world_state.facts.keys()
	keys.sort()
	
	for key in keys:
		var value: bool = world_state.facts[key]
		var unique_id: String = "##ws_" + key
		
		var indicator := _get_state_indicator(key, value, desired_states)
		ImGui.Text(indicator)
		ImGui.SameLine()
		
		var val_arr := [value]
		if ImGui.Checkbox(key + unique_id, val_arr):
			world_state.update_fact(key, val_arr[0])
			_selected_agent.plan_invalidated = true
			_selected_agent.plan_invalidated_reason = "Debug: Forced state change on '%s'" % key
		
		if ImGui.IsItemHovered():
			_draw_state_tooltip(key, value, desired_states)
	
	ImGui.Unindent()


func _draw_goals() -> void:
	if not ImGui.CollapsingHeader("Goals"):
		return
	
	ImGui.Indent()
	
	if _selected_agent.goals.is_empty():
		ImGui.TextDisabled("(no goals)")
		ImGui.Unindent()
		return
	
	var sorted_goals := _selected_agent.goals.duplicate()
	sorted_goals.sort_custom(func(a: GoapGoal, b: GoapGoal) -> bool: return a.priority > b.priority)
	
	var current_world := _selected_agent.world_state.facts if _selected_agent.world_state else {}
	
	for goal in sorted_goals:
		if not is_instance_valid(goal):
			continue
		
		var goal_name: String = goal.goal_name if goal.goal_name else goal.get_script().resource_path.get_file().get_basename()
		var is_satisfied: bool = goal.is_satisfied(current_world)
		
		var status := "[OK]" if is_satisfied else "[X]"
		ImGui.Text("%s %s (P:%d)" % [status, goal_name, goal.priority])
		
		if ImGui.IsItemHovered():
			ImGui.BeginTooltip()
			ImGui.Text("Desired State:")
			for k in goal.desired_state.keys():
				var desired_val: Variant = goal.desired_state[k]
				var current_val: Variant = current_world.get(k, "(missing)")
				var matches: bool = current_world.has(k) and current_world[k] == desired_val
				var match_str := "[OK]" if matches else "[X]"
				ImGui.Text("  %s %s: %s (current: %s)" % [match_str, str(k), str(desired_val), str(current_val)])
			ImGui.EndTooltip()
	
	ImGui.Unindent()


func _draw_current_plan() -> void:
	if not ImGui.CollapsingHeader("Current Plan"):
		return
	
	ImGui.Indent()
	
	if _selected_agent.plan_invalidated:
		ImGui.Text("[!] Plan Invalidated: %s" % _selected_agent.plan_invalidated_reason)
	
	if not _selected_agent.plan or _selected_agent.plan.steps.is_empty():
		ImGui.TextDisabled("(no plan)")
		ImGui.Unindent()
		return
	
	if _selected_agent.plan.goal:
		var goal_name: String = _selected_agent.plan.goal.goal_name if _selected_agent.plan.goal.goal_name else "Unknown"
		ImGui.Text("Goal: %s" % goal_name)
		ImGui.Separator()
	
	var current_world := _selected_agent.world_state.facts if _selected_agent.world_state else {}
	var step_idx := 0
	
	for step in _selected_agent.plan.steps:
		var action: GoapAction = step.action if step else null
		if not is_instance_valid(action):
			step_idx += 1
			continue
		
		var action_name: String = action.get_script().resource_path.get_file().get_basename()
		var is_running := _selected_agent.running_action == action
		
		var node_label: String
		if is_running:
			node_label = ">> %d. %s [RUNNING]##action%d" % [step_idx, action_name, step_idx]
		else:
			node_label = "   %d. %s##action%d" % [step_idx, action_name, step_idx]
		
		if ImGui.TreeNode(node_label):
			ImGui.Indent()
			
			ImGui.Text("Cost: %.1f" % action.cost)
			
			if not action.preconditions.is_empty():
				ImGui.Text("Preconditions:")
				for k in action.preconditions.keys():
					var required: bool = action.preconditions[k]
					var current: bool = current_world.get(k, false)
					var met := current == required
					var status := "[OK]" if met else "[X]"
					ImGui.Text("  %s %s = %s" % [status, str(k), str(required)])
			
			if not action.effects.is_empty():
				ImGui.Text("Effects:")
				for k in action.effects.keys():
					ImGui.Text("  -> %s = %s" % [str(k), str(action.effects[k])])
			
			ImGui.Unindent()
			ImGui.TreePop()
		
		step_idx += 1
	
	ImGui.Unindent()


func _draw_blackboard() -> void:
	if not ImGui.CollapsingHeader("Blackboard"):
		return
	
	ImGui.Indent()
	
	if _selected_agent.blackboard.is_empty():
		ImGui.TextDisabled("(empty)")
		ImGui.Unindent()
		return
	
	for key in _selected_agent.blackboard.keys():
		var val: Variant = _selected_agent.blackboard[key]
		var val_str := _format_blackboard_value(val)
		ImGui.BulletText("%s: %s" % [str(key), val_str])
	
	ImGui.Unindent()


func _collect_desired_states() -> Dictionary:
	var result := {}
	for goal in _selected_agent.goals:
		if not is_instance_valid(goal):
			continue
		for k in goal.desired_state.keys():
			if not result.has(k):
				result[k] = []
			result[k].append({
				"goal": goal,
				"value": goal.desired_state[k]
			})
	return result


func _get_state_indicator(key: String, value: bool, desired_states: Dictionary) -> String:
	if not desired_states.has(key):
		return "[-]"
	
	for entry in desired_states[key]:
		if entry["value"] != value:
			return "[X]"
	
	return "[OK]"


func _draw_state_tooltip(key: String, value: bool, desired_states: Dictionary) -> void:
	ImGui.BeginTooltip()
	ImGui.Text("Current: %s = %s" % [key, str(value)])
	
	if desired_states.has(key):
		ImGui.Separator()
		ImGui.Text("Goals requiring this state:")
		for entry in desired_states[key]:
			var goal: GoapGoal = entry["goal"]
			var desired_val: bool = entry["value"]
			var goal_name: String = goal.goal_name if goal.goal_name else goal.get_script().resource_path.get_file().get_basename()
			var matches := value == desired_val
			var match_str := "[OK]" if matches else "[X]"
			ImGui.Text("  %s %s wants %s" % [match_str, goal_name, str(desired_val)])
	else:
		ImGui.TextDisabled("(No goals depend on this state)")
	
	ImGui.Text("")
	ImGui.TextDisabled("Click checkbox to force toggle")
	ImGui.EndTooltip()


func _get_plan_hash(agent: CGoapAgent) -> int:
	if not agent.plan or agent.plan.steps.is_empty():
		return 0
	
	var hash_str := ""
	for step in agent.plan.steps:
		if step and step.action:
			hash_str += step.action.get_script().resource_path
	return hash_str.hash()


func _get_current_goal_name(agent: CGoapAgent) -> String:
	if agent.plan and agent.plan.goal:
		return agent.plan.goal.goal_name if agent.plan.goal.goal_name else "Unknown"
	return ""


func _format_blackboard_value(val: Variant) -> String:
	if val == null:
		return "null"
	
	if val is WeakRef:
		var ref: Variant = val.get_ref()
		if ref and is_instance_valid(ref) and ref is Entity:
			return _get_entity_display_name(ref) + " (weak)"
		return "(freed)"
	
	if typeof(val) == TYPE_OBJECT:
		if not is_instance_valid(val):
			return "(freed)"
		if val is Entity:
			return _get_entity_display_name(val)
		return str(val)
	
	if val is Vector2:
		return "(%.1f, %.1f)" % [val.x, val.y]
	if val is Vector3:
		return "(%.1f, %.1f, %.1f)" % [val.x, val.y, val.z]
	
	return str(val)


func _get_entity_display_name(entity: Entity) -> String:
	if not is_instance_valid(entity):
		return "(freed)"
	
	var node_name := entity.name
	
	if entity.has_component(CPlayer):
		return "Player_" + node_name
	elif entity.has_component(CGuard):
		return "Guard_" + node_name
	elif entity.has_component(CCampfire):
		return "Campfire_" + node_name
	elif entity.has_component(CGoapAgent):
		var camp_comp: CCamp = entity.get_component(CCamp)
		if camp_comp and camp_comp.camp == CCamp.CampType.ENEMY:
			return "Enemy_" + node_name
		return "AI_" + node_name
	
	return node_name
