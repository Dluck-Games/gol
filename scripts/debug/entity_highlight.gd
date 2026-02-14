# entity_highlight.gd - Draws highlight around selected entity
class_name EntityHighlight
extends Node2D

var target_entity: Entity = null
var pulse_time: float = 0.0

func _process(delta: float) -> void:
	pulse_time += delta * 4.0
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(target_entity):
		return
	
	var world_pos := _get_entity_position(target_entity)
	if world_pos == Vector2.INF:
		return
	
	# Convert world position to local (this node is child of the game world)
	var local_pos := world_pos
	
	# Pulsing effect
	var pulse := (sin(pulse_time) + 1.0) / 2.0
	var base_radius := 18.0
	var radius := base_radius + pulse * 5.0
	var alpha := 0.4 + pulse * 0.3
	
	# Draw highlight circles
	var color := Color(1.0, 0.8, 0.0, alpha)  # Yellow/gold
	var white := Color(1.0, 1.0, 1.0, alpha * 0.4)
	
	draw_arc(local_pos, radius, 0, TAU, 24, color, 2.0)
	draw_arc(local_pos, radius + 3, 0, TAU, 24, white, 1.0)
	
	# Draw crosshair
	var cross_size := 8.0
	draw_line(local_pos + Vector2(-cross_size, 0), local_pos + Vector2(cross_size, 0), color, 1.5)
	draw_line(local_pos + Vector2(0, -cross_size), local_pos + Vector2(0, cross_size), color, 1.5)
	
	# Draw label above (smaller)
	var label := target_entity.name
	var font := ThemeDB.fallback_font
	var font_size := 12
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var label_pos := local_pos + Vector2(-text_size.x / 2, -radius - 15)
	
	# Background
	var bg_rect := Rect2(label_pos - Vector2(3, font_size + 1), text_size + Vector2(6, 4))
	draw_rect(bg_rect, Color(0, 0, 0, 0.6))
	draw_rect(bg_rect, color, false, 1.0)
	
	# Text
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


func _get_entity_position(entity: Entity) -> Vector2:
	if not is_instance_valid(entity):
		return Vector2.INF
	
	# Try CTransform component first
	if entity.has_component(CTransform):
		var transform_comp: CTransform = entity.get_component(CTransform)
		if transform_comp:
			return transform_comp.position
	
	# Fallback: check parent chain for Node2D
	var node: Node = entity
	while node:
		if node is Node2D:
			return (node as Node2D).global_position
		node = node.get_parent()
	
	return Vector2.INF
