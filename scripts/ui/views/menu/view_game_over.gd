class_name View_GameOver
extends ViewBase

@onready var button_exit: Button = $Panel/Button_Exit

func setup() -> void:
	# 显示鼠标指针，确保玩家能够点击 UI 按钮
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	button_exit.pressed.connect(_on_button_exit_pressed)

func teardown() -> void:
	button_exit.pressed.disconnect(_on_button_exit_pressed)

func _on_button_exit_pressed() -> void:
	get_tree().quit()
