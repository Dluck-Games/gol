@tool
class_name CAnimation
extends Component

var frames: SpriteFrames = SpriteFrames.new():
	set = set_frames, get = get_frames

var current_animation: StringName = ""

var animated_sprite_node: AnimatedSprite2D = null

## 染色颜色
@export var modulate: Color = Color.WHITE

## 缩放比例
@export var visual_scale: Vector2 = Vector2.ONE


func set_frames(value: SpriteFrames) -> void:
	frames = value if value else SpriteFrames.new()
	
	# Automatically select first animation as current
	var anim_names := frames.get_animation_names()
	if anim_names and anim_names.size() > 0:
		current_animation = anim_names[0]
	else:
		current_animation = ""

func get_frames() -> SpriteFrames:
	return frames


func _get_property_list() -> Array:
	return [
		{
			"name": "frames",
			"type": TYPE_OBJECT,
			"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_EDITOR,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "SpriteFrames"
		}
	]
