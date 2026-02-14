# service_console.gd - Console Command Service
# Provides CLI-style command execution with auto-registration
class_name Service_Console
extends ServiceBase

## Command registry: { "cmd_name": { "method": "cmd_xxx", "args": [...], "desc": "..." } }
var _commands: Dictionary = {}


func setup() -> void:
	_register_commands()


func teardown() -> void:
	_commands.clear()


func _register_commands() -> void:
	# Scan all cmd_ prefixed methods and register them
	for method in get_method_list():
		var method_name: String = method.name
		if method_name.begins_with("cmd_"):
			var cmd_name := method_name.substr(4)  # Remove "cmd_" prefix
			_commands[cmd_name] = {
				"method": method_name,
				"args": _extract_arg_info(method),
				"desc": _get_command_desc(cmd_name)
			}


func _extract_arg_info(method: Dictionary) -> Array:
	var args: Array = []
	for arg in method.args:
		args.append({
			"name": arg.name,
			"type": arg.type
		})
	return args


func _get_command_desc(cmd_name: String) -> String:
	var descs := {
		"help": "Show available commands or help for a specific command",
		"kill": "Kill entity by name filter",
		"heal": "Heal player (amount or 'full')",
		"god": "Toggle god mode",
		"spawn": "Spawn entity (prefab, count)",
		"tp": "Teleport player to position (x, y)",
		"list": "List entities matching filter",
		"night": "Set time to night",
		"day": "Set time to day",
		"time": "Set or show current time (0-24)",
	}
	return descs.get(cmd_name, "")


## Execute a command string and return result
func execute(input: String) -> String:
	var parts := input.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	
	var cmd := parts[0].to_lower()
	var args: Array = []
	for i in range(1, parts.size()):
		args.append(parts[i])
	
	if not _commands.has(cmd):
		return "Unknown command: %s. Type 'help' for available commands." % cmd
	
	var method_name: String = _commands[cmd].method
	return callv(method_name, args)


## Get command completions for partial input
func get_completions(partial: String) -> Array[String]:
	var results: Array[String] = []
	var partial_lower := partial.to_lower()
	
	# If empty, return all commands
	if partial_lower.is_empty():
		for cmd in _commands.keys():
			results.append(cmd)
	else:
		for cmd in _commands.keys():
			if cmd.begins_with(partial_lower):
				results.append(cmd)
	
	results.sort()
	return results


## Get all registered command names
func get_command_names() -> Array[String]:
	var names: Array[String] = []
	for cmd in _commands.keys():
		names.append(cmd)
	names.sort()
	return names


# ============================================================
# Built-in Commands (cmd_ prefix auto-registers)
# ============================================================

func cmd_help(cmd_name: String = "") -> String:
	if cmd_name.is_empty():
		var lines: Array[String] = ["Available commands:"]
		for name in get_command_names():
			var desc: String = _commands[name].desc
			if desc.is_empty():
				lines.append("  " + name)
			else:
				lines.append("  %s - %s" % [name, desc])
		return "\n".join(lines)
	
	if not _commands.has(cmd_name):
		return "Unknown command: " + cmd_name
	
	var info: Dictionary = _commands[cmd_name]
	var args_str := ""
	for arg in info.args:
		args_str += " <%s>" % arg.name
	
	var result := "%s%s" % [cmd_name, args_str]
	if not info.desc.is_empty():
		result += "\n  " + info.desc
	return result


func cmd_kill(entity_filter: String = "") -> String:
	if not ECS.world:
		return "Error: World not initialized"
	
	var killed := 0
	for entity in ECS.world.entities:
		if not is_instance_valid(entity):
			continue
		if entity.has_component(CDead):
			continue
		
		var entity_name := _get_entity_display_name(entity)
		if entity_filter.is_empty() or entity_name.to_lower().find(entity_filter.to_lower()) != -1:
			var dead := CDead.new()
			entity.add_component(dead)
			killed += 1
	
	if killed == 0:
		return "No entities matched filter: " + entity_filter
	return "Killed %d entity(s)" % killed


func cmd_heal(amount: String = "full") -> String:
	var player := _find_player()
	if not player:
		return "Error: Player not found"
	
	var hp: CHP = player.get_component(CHP)
	if not hp:
		return "Error: Player has no HP component"
	
	if amount == "full":
		hp.hp = hp.max_hp
		return "Healed player to full (%d HP)" % hp.hp
	
	if amount.is_valid_int():
		var heal_amount := amount.to_int()
		hp.hp = mini(hp.hp + heal_amount, hp.max_hp)
		return "Healed player by %d (now %d/%d)" % [heal_amount, hp.hp, hp.max_hp]
	
	return "Invalid amount: " + amount


func cmd_god() -> String:
	var player := _find_player()
	var campfire := _find_campfire()
	
	if not player and not campfire:
		return "Error: Player and campfire not found"
	
	# 检查当前是否为无敌模式（通过玩家或营火判断）
	var is_god_mode := false
	if player:
		var player_hp: CHP = player.get_component(CHP)
		if player_hp and player_hp.max_hp >= 99999:
			is_god_mode = true
	
	if is_god_mode:
		# Disable god mode
		var result: Array[String] = []
		if player:
			var hp: CHP = player.get_component(CHP)
			if hp:
				hp.max_hp = 100
				hp.hp = 100
				result.append("Player")
		if campfire:
			var hp: CHP = campfire.get_component(CHP)
			if hp:
				hp.max_hp = 500
				hp.hp = 500
				result.append("Campfire")
		return "God mode: OFF (%s)" % ", ".join(result)
	else:
		# Enable god mode
		var result: Array[String] = []
		if player:
			var hp: CHP = player.get_component(CHP)
			if hp:
				hp.max_hp = 99999
				hp.hp = 99999
				result.append("Player")
		if campfire:
			var hp: CHP = campfire.get_component(CHP)
			if hp:
				hp.max_hp = 99999
				hp.hp = 99999
				result.append("Campfire")
		return "God mode: ON (%s)" % ", ".join(result)


func cmd_list(filter: String = "") -> String:
	if not ECS.world:
		return "Error: World not initialized"
	
	var lines: Array[String] = []
	var count := 0
	
	for entity in ECS.world.entities:
		if not is_instance_valid(entity):
			continue
		
		var entity_name := _get_entity_display_name(entity)
		if filter.is_empty() or entity_name.to_lower().find(filter.to_lower()) != -1:
			lines.append("  " + entity_name)
			count += 1
			if count >= 20:
				lines.append("  ... (showing first 20)")
				break
	
	if count == 0:
		return "No entities found" + (" matching: " + filter if not filter.is_empty() else "")
	
	return "Entities (%d):\n%s" % [count, "\n".join(lines)]


func cmd_tp(x: String = "", y: String = "") -> String:
	if x.is_empty() or y.is_empty():
		return "Usage: tp <x> <y>"
	
	if not x.is_valid_float() or not y.is_valid_float():
		return "Invalid coordinates"
	
	var player := _find_player()
	if not player:
		return "Error: Player not found"
	
	var pos := Vector2(x.to_float(), y.to_float())
	player.global_position = pos
	return "Teleported to (%.1f, %.1f)" % [pos.x, pos.y]


func cmd_night() -> String:
	var tod := ECSUtils.get_day_night_cycle()
	if not tod:
		return "Error: Day/night cycle not found"
	
	# 设置到午夜 (0点)
	tod.current_time = 0.0
	return "Time set to night (00:00)"


func cmd_day() -> String:
	var tod := ECSUtils.get_day_night_cycle()
	if not tod:
		return "Error: Day/night cycle not found"
	
	# 设置到正午 (12点)
	tod.current_time = tod.duration / 2.0
	return "Time set to day (12:00)"


func cmd_time(hour: String = "") -> String:
	var tod := ECSUtils.get_day_night_cycle()
	if not tod:
		return "Error: Day/night cycle not found"
	
	# 无参数时显示当前时间
	if hour.is_empty():
		var current_hour := (tod.current_time / tod.duration) * 24.0
		var is_night := ECSUtils.is_night()
		return "Current time: %.1f:00 (%s)" % [current_hour, "Night" if is_night else "Day"]
	
	# 设置时间
	if not hour.is_valid_float():
		return "Invalid hour: " + hour
	
	var h := hour.to_float()
	if h < 0 or h >= 24:
		return "Hour must be between 0 and 24"
	
	tod.current_time = (h / 24.0) * tod.duration
	var is_night := ECSUtils.is_night()
	return "Time set to %.1f:00 (%s)" % [h, "Night" if is_night else "Day"]


# ============================================================
# Helper Methods
# ============================================================

func _find_player() -> Entity:
	if not ECS.world:
		return null
	
	for entity in ECS.world.entities:
		if is_instance_valid(entity) and entity.has_component(CPlayer):
			var camp: CCamp = entity.get_component(CCamp)
			if camp and camp.camp == CCamp.CampType.PLAYER:
				return entity
	return null


func _find_campfire() -> Entity:
	if not ECS.world:
		return null
	
	for entity in ECS.world.entities:
		if is_instance_valid(entity) and entity.has_component(CCampfire):
			if not entity.has_component(CDead):
				return entity
	return null


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
	elif entity.has_component(CBullet):
		return "Bullet_" + node_name
	elif entity.has_component(CGoapAgent):
		var camp_comp: CCamp = entity.get_component(CCamp)
		if camp_comp and camp_comp.camp == CCamp.CampType.ENEMY:
			return "Enemy_" + node_name
		return "AI_" + node_name
	
	return node_name
