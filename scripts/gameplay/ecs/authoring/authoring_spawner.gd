@tool
class_name AuthoringSpawner
extends AuthoringNode2D


## The texture to be displayed for the spawner.
var _texture: Texture2D = preload("res://assets/sprites/items/zombie_basement_01.png")
@export var texture: Texture2D:
	set(value):
		_texture = value
		if Engine.is_editor_hint():
			_update_preview_texture(_texture)
	get:
		return _texture

## 刷怪配方 ID
@export var spawn_recipe_id: String = ""

## 刷怪间隔 (秒)
@export var spawn_interval: float = 4.0
## 刷怪间隔随机偏差
@export var spawn_interval_variance: float = 0.5

## 每波刷怪数量
@export var spawn_count: int = 1
## 刷怪半径 (距离刷怪器中心)
@export var spawn_radius: float = 0.0

## 最大存活数量限制 (0 = 不限制)
@export var max_spawn_count: int = 10

## 激活条件
@export var active_condition: CSpawner.ActiveCondition = CSpawner.ActiveCondition.ALWAYS


func _enter_tree() -> void:
	super._enter_tree()
	if Engine.is_editor_hint():
		# On first load, _texture has the default value, but the inspector
		# property 'texture' is not set.
		# Calling the setter populates the inspector and updates the preview.
		self.texture = _texture


func bake(entity: Entity) -> void:
	super.bake(entity)
	_bake_view(entity)
	_bake_spawner(entity)


func _bake_view(entity: Entity) -> void:
	var render_comp: CSprite = get_or_add_component(entity, CSprite)
	if texture:
		render_comp.texture = texture


func _bake_spawner(entity: Entity) -> void:
	var spawner_comp: CSpawner = get_or_add_component(entity, CSpawner)
	spawner_comp.spawn_recipe_id = spawn_recipe_id
	spawner_comp.spawn_interval = spawn_interval
	spawner_comp.spawn_interval_variance = spawn_interval_variance
	spawner_comp.spawn_count = spawn_count
	spawner_comp.spawn_radius = spawn_radius
	spawner_comp.max_spawn_count = max_spawn_count
	spawner_comp.active_condition = active_condition
