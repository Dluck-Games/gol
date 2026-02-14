@tool
class_name AuthoringCampfire
extends AuthoringNode2D
## 营火 Authoring Node - 用于在编辑器中配置营火实体
##
## 营火使用自定义渲染系统，包含：
## - 木柴底座 (代码绘制)
## - 像素风格火焰动画
## - 动态点光源
## - 火星粒子效果


## 火焰强度 (影响光照亮度)
@export_range(0.1, 3.0, 0.1) var fire_intensity: float = 1.5

## 火焰高度 (预留参数，暂未使用)
@export_range(10.0, 100.0, 5.0) var flame_height: float = 50.0

## 是否启用闪烁效果
@export var enable_flicker: bool = true

## 闪烁速度 (数值越大闪烁越快)
@export_range(1.0, 20.0, 0.5) var flicker_speed: float = 12.0

## 最大生命值
@export var max_hp: float = 500.0


func bake(entity: Entity) -> void:
	super.bake(entity)
	
	var campfire: CCampfire = get_or_add_component(entity, CCampfire)
	campfire.fire_intensity = fire_intensity
	campfire.flame_height = flame_height
	campfire.enable_flicker = enable_flicker
	campfire.flicker_speed = flicker_speed
	
	var camp: CCamp = get_or_add_component(entity, CCamp)
	camp.camp = CCamp.CampType.PLAYER
	
	# 添加生命值组件 - 当前HP自动等于最大HP
	var hp_comp: CHP = get_or_add_component(entity, CHP)
	hp_comp.max_hp = max_hp
	hp_comp.hp = max_hp  # 自动设置为满血
	
	# 添加碰撞组件以便敌人可以攻击营火
	var collision: CCollision = get_or_add_component(entity, CCollision)
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = 20.0  # 营火碰撞半径
	collision.collision_shape = circle_shape
	
	# 营火使用自定义渲染，移除默认精灵组件
	if entity.has_component(CSprite):
		entity.remove_component(entity.get_component(CSprite))
