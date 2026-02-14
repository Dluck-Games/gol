class_name SCrosshair
extends System

## 准心输入系统 - 更新 CAim 组件的瞄准位置
##
## 当实体拥有 CTracker 组件时，该系统不会更新 aim 位置，
## 让 STrackLocation 系统负责更新，避免鼠标和自动瞄准的功能冲突。


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CAim])


func process(entity: Entity, _delta: float) -> void:
	# 如果实体有 CTracker，则由 STrackLocation 负责更新 aim
	if entity.has_component(CTracker):
		return
	
	var aim := entity.get_component(CAim) as CAim
	aim.aim_position = get_viewport().get_mouse_position()
