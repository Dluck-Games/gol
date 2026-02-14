# scripts/pcg/wfc/wfc_rules.gd
class_name WFCRules
extends RefCounted
## Defines adjacency constraints for WFC tiles.
## Specifies which tiles can be placed adjacent to each other in each direction.

const _WFCTypes := preload("res://scripts/pcg/wfc/wfc_types.gd")

## All registered tile IDs
var _all_tiles: Array[String] = []

## Tile ID to index mapping
var _tile_to_index: Dictionary = {}

## Adjacency rules: _allowed[tile_index][direction] = bitmask of allowed neighbors
var _allowed: Array = []  # Array[Array[int]] - outer is tile index, inner is direction


func _init() -> void:
	pass


func register_tile(tile_id: String) -> void:
	## Register a tile ID. Must be called before add_constraint.
	if _tile_to_index.has(tile_id):
		return
	
	var index := _all_tiles.size()
	_tile_to_index[tile_id] = index
	_all_tiles.append(tile_id)
	
	# Add empty adjacency arrays for this tile
	_allowed.append([0, 0, 0, 0])  # NW, SE, SW, NE


func register_tiles(tile_ids: Array[String]) -> void:
	## Register multiple tile IDs.
	for tile_id in tile_ids:
		register_tile(tile_id)


func add_constraint(from_tile: String, direction: int, to_tile: String) -> void:
	## Allow from_tile to have to_tile as neighbor in given direction.
	## Automatically adds reverse constraint.
	
	if not _tile_to_index.has(from_tile):
		register_tile(from_tile)
	if not _tile_to_index.has(to_tile):
		register_tile(to_tile)
	
	var from_idx: int = _tile_to_index[from_tile]
	var to_idx: int = _tile_to_index[to_tile]
	var opposite: int = _WFCTypes.get_opposite(direction)
	
	# Add constraint: from_tile can have to_tile in direction
	_allowed[from_idx][direction] |= (1 << to_idx)
	
	# Add reverse: to_tile can have from_tile in opposite direction
	_allowed[to_idx][opposite] |= (1 << from_idx)


func add_bidirectional_constraint(tile_a: String, direction: int, tile_b: String) -> void:
	## Convenience: tile_a can have tile_b in direction, and vice versa.
	add_constraint(tile_a, direction, tile_b)


func add_self_constraint(tile_id: String, direction: int) -> void:
	## Allow tile to be adjacent to itself in given direction.
	add_constraint(tile_id, direction, tile_id)


func add_all_directions(tile_a: String, tile_b: String) -> void:
	## Allow tile_a and tile_b to be adjacent in all directions.
	for dir in range(_WFCTypes.DIR_COUNT):
		add_constraint(tile_a, dir, tile_b)


func add_self_all_directions(tile_id: String) -> void:
	## Allow tile to be adjacent to itself in all directions.
	for dir in range(_WFCTypes.DIR_COUNT):
		add_self_constraint(tile_id, dir)


func get_allowed_neighbors(tile_id: String, direction: int) -> int:
	## Get bitmask of tiles allowed as neighbors in given direction.
	if not _tile_to_index.has(tile_id):
		return 0
	return _allowed[_tile_to_index[tile_id]][direction]


func get_allowed_neighbor_tiles(tile_id: String, direction: int) -> Array[String]:
	## Get array of tile IDs allowed as neighbors in given direction.
	var mask := get_allowed_neighbors(tile_id, direction)
	var result: Array[String] = []
	for i in range(_all_tiles.size()):
		if (mask & (1 << i)) != 0:
			result.append(_all_tiles[i])
	return result


func get_all_tiles() -> Array[String]:
	## Get all registered tile IDs.
	return _all_tiles.duplicate()


func get_tile_index(tile_id: String) -> int:
	## Get index for a tile ID.
	if not _tile_to_index.has(tile_id):
		return -1
	return _tile_to_index[tile_id]


func get_tile_by_index(index: int) -> String:
	## Get tile ID by index.
	if index < 0 or index >= _all_tiles.size():
		return ""
	return _all_tiles[index]


func compute_union_mask(tiles: Array[String], direction: int) -> int:
	## Get union of allowed neighbors for multiple tiles in a direction.
	var result := 0
	for tile in tiles:
		result |= get_allowed_neighbors(tile, direction)
	return result


func compute_intersection_mask(tiles: Array[String], direction: int) -> int:
	## Get intersection of allowed neighbors for multiple tiles in a direction.
	if tiles.is_empty():
		return 0
	
	var result := get_allowed_neighbors(tiles[0], direction)
	for i in range(1, tiles.size()):
		result &= get_allowed_neighbors(tiles[i], direction)
	return result


func debug_print() -> void:
	## Print all constraints for debugging.
	print("WFCRules: %d tiles registered" % _all_tiles.size())
	for tile_idx in range(_all_tiles.size()):
		var tile := _all_tiles[tile_idx]
		print("  %s:" % tile)
		for dir in range(_WFCTypes.DIR_COUNT):
			var neighbors := get_allowed_neighbor_tiles(tile, dir)
			print("    %s: %s" % [_WFCTypes.direction_name(dir), neighbors])
