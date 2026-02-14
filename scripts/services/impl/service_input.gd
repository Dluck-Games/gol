## Service_Input
##
## 极简输入服务 - 基于事件队列的输入系统
## 
## 核心特性:
## - 事件队列存储本帧所有输入事件
## - 支持 peek (查看) 和 pop (消费) 两种访问模式
## - 每帧结束自动清理过期事件
## - 支持高级事件检测 (clicked, hold)
## - 内部管理输入监听节点，无需外部系统
##
## 使用方式:
##   # 检查射击事件 (不消费)
##   if ServiceContext.input().has_event("player_fire_pressed"):
##       fire()
##   
##   # 消费交互事件 (防止重复处理)
##   if ServiceContext.input().pop_event("interact_pressed"):
##       interact()
##
class_name Service_Input
extends ServiceBase


## 输入事件结构
class InputEventData:
	var action: String        ## 动作名称，如 "player_fire"
	var type: String          ## 事件类型: "pressed", "released", "clicked", "hold"
	var timestamp: int        ## 事件时间戳 (msec)
	var consumed: bool        ## 是否已被消费
	
	func _init(p_action: String, p_type: String) -> void:
		action = p_action
		type = p_type
		timestamp = Time.get_ticks_msec()
		consumed = false
	
	func get_key() -> String:
		return action + "_" + type


## 内部输入监听节点
class InputListener extends Node:
	var _service: Service_Input
	
	func _init(service: Service_Input) -> void:
		_service = service
	
	func _input(event: InputEvent) -> void:
		if not _service:
			return
		_service._handle_input_event(event)
	
	func _process(_delta: float) -> void:
		if not _service:
			return
		# 每帧结束清理事件队列
		_service.clear_frame_events()


## 本帧事件队列
var _event_queue: Array[InputEventData] = []

## 持续按住状态追踪 (用于检测 hold 和 clicked)
var _held_actions: Dictionary = {}  # action -> press_timestamp

## 点击检测阈值 (毫秒)
const CLICK_THRESHOLD_MS: int = 200

## 长按检测阈值 (毫秒)
const HOLD_THRESHOLD_MS: int = 500

## 需要监听的动作列表
var _watched_actions: Array[String] = []

## 内部输入监听节点
var _input_listener: InputListener = null

## 输入是否启用
var is_enabled: bool = true


# ---------------------
# 生命周期
# ---------------------

func setup() -> void:
	_event_queue.clear()
	_held_actions.clear()
	
	# 默认监听的动作
	_watched_actions = [
		"player_fire",
		"player_left",
		"player_right",
		"player_up",
		"player_down",
	]
	
	# 创建并添加输入监听节点
	_input_listener = InputListener.new(self)
	_input_listener.name = "InputListener"
	# 设置处理优先级，确保在帧末尾清理
	_input_listener.process_priority = 1000
	root_node().add_child(_input_listener)


func teardown() -> void:
	# 移除并释放输入监听节点
	if _input_listener and is_instance_valid(_input_listener):
		_input_listener.queue_free()
		_input_listener = null
	
	_event_queue.clear()
	_held_actions.clear()
	_watched_actions.clear()


# ---------------------
# 输入处理 (由内部 InputListener 调用)
# ---------------------

## 处理 Godot 原生输入事件
func _handle_input_event(event: InputEvent) -> void:
	if not is_enabled:
		return
	
	for action in _watched_actions:
		if event.is_action(action):
			if event.is_action_pressed(action):
				_on_action_pressed(action)
			elif event.is_action_released(action):
				_on_action_released(action)


## 处理动作按下
func _on_action_pressed(action: String) -> void:
	# 防止重复按下
	if _held_actions.has(action):
		return
	
	# 记录按下时间
	_held_actions[action] = Time.get_ticks_msec()
	
	# 生成 pressed 事件
	_push_event(action, "pressed")


## 处理动作释放
func _on_action_released(action: String) -> void:
	var press_time: int = _held_actions.get(action, 0)
	var release_time: int = Time.get_ticks_msec()
	var duration: int = release_time - press_time
	
	# 生成 released 事件
	_push_event(action, "released")
	
	# 检测 clicked (短按)
	if press_time > 0 and duration < CLICK_THRESHOLD_MS:
		_push_event(action, "clicked")
	
	# 清理按住状态
	_held_actions.erase(action)


## 推入事件到队列
func _push_event(action: String, type: String) -> void:
	var evt := InputEventData.new(action, type)
	_event_queue.append(evt)


# ---------------------
# 事件查询 API (peek - 不消费)
# ---------------------

## 检查是否存在指定事件
func has_event(event_key: String) -> bool:
	for evt in _event_queue:
		if not evt.consumed and evt.get_key() == event_key:
			return true
	return false


## 检查动作是否刚被按下
func is_action_just_pressed(action: String) -> bool:
	return has_event(action + "_pressed")


## 检查动作是否刚被释放
func is_action_just_released(action: String) -> bool:
	return has_event(action + "_released")


## 检查动作是否被点击 (短按后释放)
func is_action_clicked(action: String) -> bool:
	return has_event(action + "_clicked")


## 检查动作是否正在被按住
func is_action_held(action: String) -> bool:
	return _held_actions.has(action)


## 检查动作是否长按 (超过阈值)
func is_action_long_held(action: String) -> bool:
	if not _held_actions.has(action):
		return false
	var press_time: int = _held_actions[action]
	var duration: int = Time.get_ticks_msec() - press_time
	return duration >= HOLD_THRESHOLD_MS


## 获取动作按住时长 (毫秒)
func get_action_hold_duration(action: String) -> int:
	if not _held_actions.has(action):
		return 0
	return Time.get_ticks_msec() - _held_actions[action]


# ---------------------
# 事件消费 API (pop - 消费后不再返回)
# ---------------------

## 消费指定事件 (返回是否成功)
func pop_event(event_key: String) -> bool:
	for evt in _event_queue:
		if not evt.consumed and evt.get_key() == event_key:
			evt.consumed = true
			return true
	return false


## 消费 pressed 事件
func pop_action_pressed(action: String) -> bool:
	return pop_event(action + "_pressed")


## 消费 released 事件
func pop_action_released(action: String) -> bool:
	return pop_event(action + "_released")


## 消费 clicked 事件
func pop_action_clicked(action: String) -> bool:
	return pop_event(action + "_clicked")


# ---------------------
# 移动输入特殊处理
# ---------------------

## 获取当前移动方向 (基于按住状态)
func get_move_direction() -> Vector2:
	var direction := Vector2.ZERO
	
	if is_action_held("player_left"):
		direction.x -= 1.0
	if is_action_held("player_right"):
		direction.x += 1.0
	if is_action_held("player_up"):
		direction.y -= 1.0
	if is_action_held("player_down"):
		direction.y += 1.0
	
	return direction


# ---------------------
# 帧清理 (由内部 InputListener 调用)
# ---------------------

## 清理本帧事件队列
func clear_frame_events() -> void:
	_event_queue.clear()


## 添加监听的动作
func watch_action(action: String) -> void:
	if action not in _watched_actions:
		_watched_actions.append(action)


## 移除监听的动作
func unwatch_action(action: String) -> void:
	_watched_actions.erase(action)
