class_name STrackLocation
extends System

## 追踪位置系统 - 更新 CTracker 组件的追踪目标
##
## 当实体同时拥有 CAim 组件时，会将追踪目标位置转换为屏幕坐标更新到 CAim，
## 让拥有 CTracker 的实体（如玩家、守卫）能自动瞄准目标。


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CTracker, CCollision])


func process(entity: Entity, _delta: float) -> void:
	# 获取组件
	var c_tracker: CTracker = entity.get_component(CTracker)

	var nearest_target_location: Vector2 = Vector2.ZERO
	var nearest_target_distance: float = c_tracker.track_range
	var position: Vector2 = Vector2.ZERO
	var camp: int = 0

	if entity.has_component(CTransform):
		var transform: CTransform = entity.get_component(CTransform)
		position = transform.position
	else:
		return

	if entity.has_component(CCamp):
		var pawn_comp: CCamp = entity.get_component(CCamp)
		camp = pawn_comp.camp
	else:
		return
	
	for overlap_entity in ECS.world.query.with_all([CCamp]).execute():
		if overlap_entity.has_component(CTransform) and overlap_entity.has_component(CCamp):

			var current_target_location: Vector2 = overlap_entity.get_component(CTransform).position
			var current_distance: float = position.distance_to(current_target_location)
			var target_camp = overlap_entity.get_component(CCamp).camp

			if camp != target_camp and current_distance < nearest_target_distance:
				nearest_target_location = current_target_location
				nearest_target_distance = current_distance
	
	if nearest_target_distance < c_tracker.track_range:
		c_tracker.has_target = true
		c_tracker.target_location = nearest_target_location
	else:
		c_tracker.has_target = false
		c_tracker.target_location = Vector2.ZERO
		nearest_target_location = Vector2.ZERO
		nearest_target_distance = c_tracker.track_range
	
	# 如果实体有 CAim 组件，更新瞄准位置
	_update_aim_position(entity, c_tracker)


func _update_aim_position(entity: Entity, c_tracker: CTracker) -> void:
	var aim: CAim = entity.get_component(CAim)
	if aim == null:
		return
	
	if c_tracker.has_target:
		# 将世界坐标转换为屏幕坐标
		var viewport := entity.get_viewport()
		if viewport:
			var canvas_transform := viewport.get_canvas_transform()
			aim.aim_position = canvas_transform * c_tracker.target_location
	else:
		# 没有目标时，回退到鼠标位置，由玩家手动控制
		var viewport := entity.get_viewport()
		if viewport:
			aim.aim_position = viewport.get_mouse_position()
