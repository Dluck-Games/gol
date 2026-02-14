class_name SCampfireRender
extends System
## 营火渲染系统 - 为营火实体创建和更新视觉效果
##
## 渲染内容：
## - 木柴底座 (使用代码绘制的简单形状)
## - Minecraft 风格像素块火焰 (5个彩色 ColorRect)
## - 火星粒子效果 (GPUParticles2D)
##
## 注意：光照效果由 SDaynightLighting 着色器系统处理


## 存储每个营火实体的视图数据
var _campfire_views: Dictionary = {}


func _ready() -> void:
	group = "render"


func query() -> QueryBuilder:
	return q.with_all([CTransform, CCampfire])


func process(entity: Entity, delta: float) -> void:
	var transform: CTransform = entity.get_component(CTransform)
	var campfire: CCampfire = entity.get_component(CCampfire)
	var view_id: int = entity.get_instance_id()
	
	if not _campfire_views.has(view_id):
		_create_campfire_view(entity, view_id, campfire)
	
	var view_data: Dictionary = _campfire_views[view_id]
	_update_campfire_view(view_data, transform, campfire, delta)


#region 创建视图

## 创建营火视图 - Minecraft 风格的像素火焰
func _create_campfire_view(entity: Entity, view_id: int, _campfire: CCampfire) -> void:
	var root := Node2D.new()
	root.name = "CampfireView_%d" % view_id
	
	# 添加所有视觉元素 (移除了 PointLight2D，光照由着色器处理)
	var logs := _create_logs()  # 使用代码绘制的木柴
	var flame_pixels := _create_flame_pixels()
	var sparks := _create_spark_particles()
	
	root.add_child(logs)
	root.add_child(flame_pixels)
	root.add_child(sparks)
	
	entity.add_child(root)
	
	# 存储视图数据
	_campfire_views[view_id] = {
		"root": root,
		"logs": logs,
		"flame_pixels": flame_pixels,
		"sparks": sparks,
		"time": 0.0,
		"flicker_offset": randf() * 100.0  # 随机偏移使多个营火不同步
	}
	
	entity.component_removed.connect(_on_component_removed.bind(view_id))


## 创建木柴底座 - 简单X形状
func _create_logs() -> Node2D:
	var container := Node2D.new()
	container.name = "Logs"
	container.position = Vector2(0, 6)
	
	# 木柴颜色 - 棕色
	var log_color := Color(0.5, 0.3, 0.15)
	
	var log_width := 24
	var log_height := 5
	
	# 第一条木柴: \ 方向
	var log1 := ColorRect.new()
	log1.size = Vector2(log_width, log_height)
	log1.color = log_color
	log1.pivot_offset = Vector2(log_width / 2.0, log_height / 2.0)  # 中心点旋转
	log1.position = Vector2(-log_width / 2.0, -log_height / 2.0)
	log1.rotation_degrees = 35.0
	container.add_child(log1)
	
	# 第二条木柴: / 方向  
	var log2 := ColorRect.new()
	log2.size = Vector2(log_width, log_height)
	log2.color = log_color
	log2.pivot_offset = Vector2(log_width / 2.0, log_height / 2.0)  # 中心点旋转
	log2.position = Vector2(-log_width / 2.0, -log_height / 2.0)
	log2.rotation_degrees = -35.0
	container.add_child(log2)
	
	return container


## 创建火焰像素块组 - 5个彩色像素块组成
func _create_flame_pixels() -> Node2D:
	var container := Node2D.new()
	container.name = "FlamePixels"
	container.position = Vector2(0, -10)
	
	# 从下到上：黄 -> 橙 -> 红
	container.add_child(_create_pixel_rect(Vector2(-6, 0), Vector2(12, 6), Color(1.5, 1.2, 0.3)))   # 底部黄色
	container.add_child(_create_pixel_rect(Vector2(-10, -6), Vector2(6, 6), Color(1.3, 0.6, 0.1)))  # 中部左橙
	container.add_child(_create_pixel_rect(Vector2(4, -6), Vector2(6, 6), Color(1.3, 0.6, 0.1)))    # 中部右橙
	container.add_child(_create_pixel_rect(Vector2(-5, -12), Vector2(10, 6), Color(1.0, 0.3, 0.1))) # 顶部红色
	container.add_child(_create_pixel_rect(Vector2(-3, -16), Vector2(6, 4), Color(0.9, 0.25, 0.05))) # 最顶深红
	
	return container


## 创建单个像素块
func _create_pixel_rect(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = pos
	rect.size = size
	rect.color = color
	return rect


## 创建火星粒子系统
func _create_spark_particles() -> GPUParticles2D:
	var sparks := GPUParticles2D.new()
	sparks.name = "Sparks"
	sparks.emitting = true
	sparks.amount = 10
	sparks.lifetime = 1.0
	sparks.one_shot = false
	sparks.explosiveness = 0.0
	sparks.randomness = 0.4
	sparks.process_material = _create_spark_material()
	sparks.position = Vector2(0, -8)
	return sparks


## 创建火星粒子材质
func _create_spark_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	
	# 运动参数
	material.direction = Vector3(0, -1, 0)
	material.spread = 25.0
	material.initial_velocity_min = 18.0
	material.initial_velocity_max = 30.0
	material.gravity = Vector3(0, -8, 0)
	
	# 颜色渐变：黄 -> 橙 -> 红 -> 透明
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.8, 1.4, 0.5, 1.0))  # 亮黄
	gradient.add_point(0.6, Color(1.2, 0.4, 0.1, 0.8))  # 橙红
	gradient.add_point(1.0, Color(0.3, 0.1, 0.0, 0.0))  # 透明
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture
	
	# 粒子大小
	material.scale_min = 2.5
	material.scale_max = 3.5
	
	return material

#endregion


#region 更新视图

## 更新营火视图 - 处理位置同步和动画
func _update_campfire_view(view_data: Dictionary, transform: CTransform, campfire: CCampfire, delta: float) -> void:
	var root: Node2D = view_data["root"]
	var flame_pixels: Node2D = view_data["flame_pixels"]
	
	# 同步世界变换
	root.global_position = transform.position
	root.rotation = transform.rotation
	root.scale = transform.scale
	
	# 更新闪烁动画
	if campfire.enable_flicker:
		view_data["time"] += delta * campfire.flicker_speed
		var time: float = view_data["time"] + view_data["flicker_offset"]
		_update_flicker_animation(flame_pixels, time, campfire.fire_intensity)


## 更新闪烁动画效果
func _update_flicker_animation(flame_pixels: Node2D, time: float, intensity: float) -> void:
	var flicker := sin(time * 3.0) * 0.5 + 0.5  # 0.0 ~ 1.0
	
	# 火焰上下浮动
	flame_pixels.position.y = -10 + sin(time * 2.0) * 0.5
	
	# 火焰亮度变化
	var brightness := 0.9 + flicker * 0.15
	flame_pixels.modulate = Color(brightness, brightness, brightness, 1.0)

#endregion


#region 清理

## 组件移除回调 - 清理视图
func _on_component_removed(entity: Entity, component: Variant, view_id: int) -> void:
	if component is CCampfire or component is CTransform:
		if _campfire_views.has(view_id):
			var view_data: Dictionary = _campfire_views[view_id]
			var root: Node2D = view_data["root"]
			
			if entity.has_node(root.get_path()):
				entity.remove_child(root)
			root.queue_free()
			
			_campfire_views.erase(view_id)

#endregion
