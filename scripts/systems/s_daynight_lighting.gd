class_name SDaynightLighting
extends System

## 昼夜光照系统 - 使用着色器实现昼夜效果和动态光源
##
## 功能：
## - 全屏后处理着色器实现昼夜变化
## - 收集场景中所有光源（营火等）
## - 同步光源数据到着色器

const SHADER_PATH := "res://shaders/daynight_lighting.gdshader"
const MAX_LIGHTS := 16

# 夜晚环境光颜色 (深蓝色调，保持 30% 可见度)
const NIGHT_COLOR := Color(0.3, 0.35, 0.5, 1.0)
# 白天环境光颜色
const DAY_COLOR := Color(1.0, 1.0, 1.0, 1.0)
# 日出颜色
const SUNRISE_COLOR := Color(1.0, 0.85, 0.7, 1.0)
# 日落颜色
const SUNSET_COLOR := Color(0.9, 0.6, 0.4, 1.0)

# 营火光源默认参数
const CAMPFIRE_LIGHT_RADIUS := 200.0
const CAMPFIRE_LIGHT_INTENSITY := 1.2
const CAMPFIRE_LIGHT_COLOR := Color(1.0, 0.9, 0.7, 1.0)

var _canvas_layer: CanvasLayer
var _color_rect: ColorRect
var _shader_material: ShaderMaterial
var _tod_component: CDayNightCycle

# 时间点缓存
var _cached_night_weight: float = -1.0
var _cached_day_weight: float = -1.0
var _cached_duration: float = -1.0
var _sunrise_point: float = 0.0
var _sunset_point: float = 0.0
var _night_point_to_sunrise: float = 0.0
var _night_point_to_sunset: float = 0.0
var _day_point_to_sunrise: float = 0.0
var _day_point_to_sunset: float = 0.0


func _ready() -> void:
	group = "render"
	_setup_shader()


func query() -> QueryBuilder:
	# 查询昼夜循环组件
	return q.with_all([CDayNightCycle])


func process(_entity: Entity, _delta: float) -> void:
	if not _shader_material:
		return
	
	# 获取昼夜循环组件
	if not _tod_component:
		var entities := ECS.world.query.with_all([CDayNightCycle]).execute()
		if not entities.is_empty():
			_tod_component = entities[0].get_component(CDayNightCycle)
	
	# 更新环境光颜色
	_update_ambient_color()
	
	# 收集并更新光源数据
	_update_light_sources()


func _setup_shader() -> void:
	# 创建 CanvasLayer (最高层，覆盖所有内容)
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "DaynightLightingLayer"
	_canvas_layer.layer = 100  # 最高层
	
	# 创建全屏 ColorRect
	_color_rect = ColorRect.new()
	_color_rect.name = "LightingRect"
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 加载并应用着色器
	var shader := load(SHADER_PATH) as Shader
	if not shader:
		push_error("SDaynightLighting: Failed to load shader from %s" % SHADER_PATH)
		return
	
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	_color_rect.material = _shader_material
	
	# 添加到场景
	_canvas_layer.add_child(_color_rect)
	
	# 延迟添加到场景树，确保场景已准备好
	if ECS.world:
		ECS.world.add_child.call_deferred(_canvas_layer)
	else:
		push_error("SDaynightLighting: ECS.world not available")


func _update_ambient_color() -> void:
	if not _tod_component or not _shader_material:
		return
	
	var ambient := _calculate_ambient_color(_tod_component.current_time)
	_shader_material.set_shader_parameter("ambient_color", ambient)


func _calculate_ambient_color(current_time: float) -> Color:
	_calculate_time_points_if_needed()
	
	var new_color: Color
	var time_modifier: float
	
	# 黑夜 -> 黎明
	if current_time > _night_point_to_sunrise and current_time <= _sunrise_point:
		time_modifier = remap(current_time, _night_point_to_sunrise, _sunrise_point, 0.0, 1.0)
		new_color = NIGHT_COLOR.lerp(SUNRISE_COLOR, time_modifier)
	# 黎明 -> 白天
	elif current_time > _sunrise_point and current_time <= _day_point_to_sunrise:
		time_modifier = remap(current_time, _sunrise_point, _day_point_to_sunrise, 0.0, 1.0)
		new_color = SUNRISE_COLOR.lerp(DAY_COLOR, time_modifier)
	# 白天
	elif current_time > _day_point_to_sunrise and current_time <= _day_point_to_sunset:
		new_color = DAY_COLOR
	# 白天 -> 黄昏
	elif current_time > _day_point_to_sunset and current_time <= _sunset_point:
		time_modifier = remap(current_time, _day_point_to_sunset, _sunset_point, 0.0, 1.0)
		new_color = DAY_COLOR.lerp(SUNSET_COLOR, time_modifier)
	# 黄昏 -> 黑夜
	elif current_time > _sunset_point and current_time <= _night_point_to_sunset:
		time_modifier = remap(current_time, _sunset_point, _night_point_to_sunset, 0.0, 1.0)
		new_color = SUNSET_COLOR.lerp(NIGHT_COLOR, time_modifier)
	# 黑夜
	else:
		new_color = NIGHT_COLOR
	
	return new_color


func _calculate_time_points_if_needed() -> void:
	if not _tod_component:
		return
	
	var night_weight: float = _tod_component.night_weight
	var day_weight: float = _tod_component.day_weight
	var duration: float = _tod_component.duration
	
	if night_weight == _cached_night_weight and day_weight == _cached_day_weight and duration == _cached_duration:
		return
	
	_cached_night_weight = night_weight
	_cached_day_weight = day_weight
	_cached_duration = duration
	
	_night_point_to_sunrise = night_weight / 2
	_night_point_to_sunset = duration - _night_point_to_sunrise
	
	_day_point_to_sunrise = (duration / 2) - (day_weight / 2)
	_day_point_to_sunset = (duration / 2) + (day_weight / 2)
	
	_sunrise_point = (_night_point_to_sunrise + _day_point_to_sunrise) / 2
	_sunset_point = (_night_point_to_sunset + _day_point_to_sunset) / 2


func _update_light_sources() -> void:
	if not _shader_material:
		return
	
	# 收集所有营火光源
	var campfires := ECS.world.query.with_all([CCampfire, CTransform]).execute()
	
	var positions: Array[Vector2] = []
	var colors: Array[Color] = []
	var radii: Array[float] = []
	var intensities: Array[float] = []
	
	var viewport := ECS.world.get_viewport()
	if not viewport:
		return
	
	var canvas_transform := viewport.get_canvas_transform()
	var screen_size := viewport.get_visible_rect().size
	
	# 传递屏幕尺寸给着色器
	_shader_material.set_shader_parameter("screen_size", screen_size)
	
	for campfire in campfires:
		if campfire.has_component(CDead):
			continue
		
		var transform := campfire.get_component(CTransform) as CTransform
		var campfire_comp := campfire.get_component(CCampfire) as CCampfire
		
		# 将世界坐标转换为屏幕坐标
		var screen_pos: Vector2 = canvas_transform * transform.position
		
		positions.append(screen_pos)
		colors.append(CAMPFIRE_LIGHT_COLOR)
		radii.append(CAMPFIRE_LIGHT_RADIUS * campfire_comp.fire_intensity)
		intensities.append(CAMPFIRE_LIGHT_INTENSITY * campfire_comp.fire_intensity)
		
		if positions.size() >= MAX_LIGHTS:
			break
	
	# 填充数组到固定大小 (着色器需要固定大小数组)
	while positions.size() < MAX_LIGHTS:
		positions.append(Vector2.ZERO)
		colors.append(Color.WHITE)
		radii.append(0.0)
		intensities.append(0.0)
	
	# 传递数据到着色器
	_shader_material.set_shader_parameter("light_count", mini(campfires.size(), MAX_LIGHTS))
	_shader_material.set_shader_parameter("light_positions", positions)
	_shader_material.set_shader_parameter("light_colors", colors)
	_shader_material.set_shader_parameter("light_radii", radii)
	_shader_material.set_shader_parameter("light_intensities", intensities)


func _exit_tree() -> void:
	if _canvas_layer and is_instance_valid(_canvas_layer):
		_canvas_layer.queue_free()
