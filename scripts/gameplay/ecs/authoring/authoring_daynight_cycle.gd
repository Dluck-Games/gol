@tool
class_name AuthoringDaynightCycle
extends AuthoringNode2D

const DEFAULT_RECIPE_ID := "daynight_cycle"

#一天时长
@export var duration : float = 24.0
#当前时间
@export var current_time : float = 0
#时间流逝速度  现实 1s = 游戏 x 小时
# 24分钟完整循环: 24.0 / (24 * 60) = 0.0167
@export var speed_of_time : float = 0.0167

# 夜晚时间权重 (8分钟 = 8/24 * 24 = 8)
@export var night_weight : float = 8
# 白天时间权重 (16分钟 = 16/24 * 24 = 16)
@export var day_weight : float = 16



func _get_default_recipe_id() -> String:
	return DEFAULT_RECIPE_ID


func bake(entity: Entity) -> void:
	super.bake(entity)
	
	# Override with custom settings
	var day_night_cycle: CDayNightCycle = entity.get_component(CDayNightCycle)
	if day_night_cycle:
		day_night_cycle.duration = duration
		day_night_cycle.current_time = current_time
		day_night_cycle.speed_of_time = speed_of_time

		day_night_cycle.night_weight = night_weight
		day_night_cycle.day_weight = day_weight
