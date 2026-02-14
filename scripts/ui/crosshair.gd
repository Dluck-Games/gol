class_name CrosshairView
extends CanvasLayer

## 准心 View - 纯渲染，样式配置在此，数据从 ViewModel 获取

## 样式配置
@export var color: Color = Color.WHITE
@export var line_length: float = 8.0
@export var gap: float = 6.0
@export var thickness: float = 2.0

var _view_model: CrosshairViewModel
var _bound_entity: Entity = null
var _draw_node: Node2D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	layer = 100  # 确保在最上层
	
	# 创建绘制节点
	_draw_node = Node2D.new()
	_draw_node.z_index = 100
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)
	
	_view_model = CrosshairViewModel.new()
	_view_model.setup()
	_view_model.aim_position.subscribe(_on_aim_position_changed)


func _process(_delta: float) -> void:
	_try_bind_entity()


func _on_draw() -> void:
	var pos: Vector2 = _view_model.aim_position.value
	
	# 上线
	_draw_node.draw_line(pos + Vector2(0, -gap), pos + Vector2(0, -gap - line_length), color, thickness)
	# 下线
	_draw_node.draw_line(pos + Vector2(0, gap), pos + Vector2(0, gap + line_length), color, thickness)
	# 左线
	_draw_node.draw_line(pos + Vector2(-gap, 0), pos + Vector2(-gap - line_length, 0), color, thickness)
	# 右线
	_draw_node.draw_line(pos + Vector2(gap, 0), pos + Vector2(gap + line_length, 0), color, thickness)


func _try_bind_entity() -> void:
	# 检查当前绑定的实体是否仍然有效
	if _bound_entity and is_instance_valid(_bound_entity) and _bound_entity.is_inside_tree():
		return
	
	# 实体无效，需要重新绑定
	if _bound_entity:
		_view_model.unbind()
		_bound_entity = null
	
	# 查找玩家实体上的 CAim 组件（玩家有 CPlayer 组件）
	var entities: Array = ECS.world.query.with_all([CPlayer, CAim]).execute()
	if entities.size() > 0:
		_bound_entity = entities[0]
		_view_model.bind_to_entity(_bound_entity)


func _on_aim_position_changed(_new_pos: Vector2) -> void:
	_draw_node.queue_redraw()


func _exit_tree() -> void:
	_view_model.teardown()
	_bound_entity = null
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
