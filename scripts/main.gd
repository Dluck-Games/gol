# Main.gd - Entry Scene Controller
# This is the default startup scene that begins the game flow
extends Node


func _ready() -> void:
	await get_tree().process_frame
	GOL.setup()
	GOL.start_game()

func _exit_tree() -> void:
	GOL.teardown()