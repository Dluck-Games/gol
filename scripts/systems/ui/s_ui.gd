class_name SUI
extends System

@warning_ignore("unused_private_class_variable")
var _initialized := false

func _ready() -> void:
	group = "ui"

func process(_entity: Entity, _delta: float) -> void:
	if _initialized:
		return
	if ECS.world == null:
		return
	ECS.world.add_system(SUI_Hpbar.new())
	ServiceContext.ui().create_and_push_view(
		Service_UI.LayerType.HUD,
		preload("res://scenes/ui/hud.tscn")
	)
	ServiceContext.ui().create_and_push_view(
		Service_UI.LayerType.HUD,
		preload("res://scenes/ui/daynight_cycle.tscn")
	)
	_initialized = true
