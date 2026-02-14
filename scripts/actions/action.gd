class_name Action
extends Resource


var action_name: String = "None"


func execute(causer: Entity) -> void:
	# This method should be overridden by subclasses to define the action's behavior.
	print("Executing action: %s by causer: %s" % [action_name, causer])
	pass