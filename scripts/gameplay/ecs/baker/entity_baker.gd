class_name EntityBaker
extends Node


# Finds all 'AuthoringNode' instances within the 'ecs_world.entity_nodes_root' path,
# bakes them into entities, and then removes the authoring nodes from the scene.
#
# @param world: The GOLWorld instance to bake entities into.
static func bake_world(world: GOLWorld) -> void:
	var entity_nodes_root = world.get_node(world.entity_nodes_root)

	if not entity_nodes_root:
		push_warning("GOLWorld.entity_nodes_root is not set. No authoring nodes will be baked.")
		return

	# Iterate over the children of the container node.
	# We copy the array because the original collection will be modified (queue_free).
	for node in entity_nodes_root.get_children():
		# Ensure the node is a valid authoring node by checking for the bake method (Duck Typing).
		if not node.has_method("bake"):
			continue

		# Create a new entity.
		var e := Entity.new()

		# The authoring node is responsible for adding its components.
		node.bake(e)

		# Add the entity to the world.
		world.add_entity(e)
		
		# Set entity name from the authoring node AFTER adding to tree
		# (add_child may rename nodes on conflict, so we force the name here)
		e.name = node.name
		
		print("LogEntityBaker: Baked = ", node.name)
		
		# The authoring node has served its purpose and can be removed from the scene tree.
		node.queue_free()
