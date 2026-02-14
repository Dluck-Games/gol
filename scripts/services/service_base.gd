class_name ServiceBase
extends Object


# Get a node in world to access scene tree methods
func root_node() -> Node:
	if not ServiceContext.root_node:
		push_error("ServiceContext.bootloader is not set!")
	return ServiceContext.root_node

func setup() -> void:
	pass

func teardown() -> void:
	pass
