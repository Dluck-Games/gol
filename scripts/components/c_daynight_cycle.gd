class_name CDayNightCycle
extends Component

# ============================================================
# 时间周期
# ============================================================
enum TimePhase { NIGHT, SUNRISE, DAY, SUNSET }

#一天时长
@export var duration : float = 24.0 :
	set(value):
		duration = value
		duration_observable.value = value
var duration_observable : ObservableProperty = ObservableProperty.new(duration)
#当前时间
@export var current_time : float = 0 :
	set(value):
		current_time = value
		current_time_observable.value = value
var current_time_observable : ObservableProperty = ObservableProperty.new(current_time)

# 白天黑夜权重值，二者相加 < 24，
# 如：day_weight = 12  night_weight = 6 剩余时间则分配为日出和日落时间
# 用于对每个时间段的时长分别调整

# 夜晚时间权重
@export var night_weight : float:
	set(value):
		night_weight = value
		night_weight_observable.value = value
var night_weight_observable : ObservableProperty = ObservableProperty.new(night_weight)


# 白天时间权重
@export var day_weight : float:
	set(value):
		day_weight = value
		day_weight_observable.value = value
var day_weight_observable : ObservableProperty = ObservableProperty.new(day_weight)

#时间流逝速度  现实 1s = 游戏 x 小时
# 24分钟完整循环: 24.0 / (24 * 60) = 0.0167
@export var speed_of_time : float = 0.0167
