# scripts/pcg/wfc/wfc_domain.gd
class_name WFCDomain
extends RefCounted
## Represents the domain (possible tile variants) for a single cell.
## Uses bitmask for efficient constraint operations.

const _WFCDomain := preload("res://scripts/pcg/wfc/wfc_domain.gd")

## Maximum supported tiles (64 bits)
const MAX_TILES := 64

## Bitmask of valid tiles (bit i set = tile i is valid)
var _mask: int = 0

## Cached entropy (number of valid tiles)
var _entropy: int = 0

## Tile ID to index mapping (shared across all domains)
var _tile_to_index: Dictionary = {}

## Index to tile ID mapping
var _index_to_tile: Array[String] = []


func _init(tiles: Array[String] = [], all_tiles: Array[String] = []) -> void:
	## Initialize with specific tiles as valid, using all_tiles for indexing.
	## If tiles is empty, all tiles are valid.
	
	if all_tiles.is_empty():
		all_tiles = tiles
	
	# Build tile index mappings
	for i in range(all_tiles.size()):
		_tile_to_index[all_tiles[i]] = i
	_index_to_tile = all_tiles.duplicate()
	
	# Set valid tiles
	if tiles.is_empty():
		# All tiles valid
		_mask = (1 << all_tiles.size()) - 1
	else:
		for tile in tiles:
			if _tile_to_index.has(tile):
				_mask |= (1 << _tile_to_index[tile])
	
	_update_entropy()


func duplicate() -> WFCDomain:
	## Create a copy of this domain.
	var copy := _WFCDomain.new()
	copy._mask = _mask
	copy._entropy = _entropy
	copy._tile_to_index = _tile_to_index
	copy._index_to_tile = _index_to_tile
	return copy


func is_collapsed() -> bool:
	## Returns true if exactly one tile is valid.
	return _entropy == 1


func is_contradiction() -> bool:
	## Returns true if no tiles are valid.
	return _entropy == 0


func entropy() -> int:
	## Returns the number of valid tiles.
	return _entropy


func get_collapsed_tile() -> String:
	## Returns the single valid tile (only valid if is_collapsed() is true).
	if not is_collapsed():
		return ""
	
	for i in range(_index_to_tile.size()):
		if (_mask & (1 << i)) != 0:
			return _index_to_tile[i]
	return ""


func get_valid_tiles() -> Array[String]:
	## Returns array of all valid tile IDs.
	var result: Array[String] = []
	for i in range(_index_to_tile.size()):
		if (_mask & (1 << i)) != 0:
			result.append(_index_to_tile[i])
	return result


func has_tile(tile_id: String) -> bool:
	## Check if a specific tile is valid.
	if not _tile_to_index.has(tile_id):
		return false
	return (_mask & (1 << _tile_to_index[tile_id])) != 0


func collapse_to(tile_id: String) -> void:
	## Collapse domain to a single tile.
	if not _tile_to_index.has(tile_id):
		push_error("WFCDomain: Cannot collapse to unknown tile: " + tile_id)
		return
	
	_mask = 1 << _tile_to_index[tile_id]
	_entropy = 1


func collapse_random(rng: RandomNumberGenerator) -> String:
	## Collapse to a random valid tile.
	var valid_tiles := get_valid_tiles()
	if valid_tiles.is_empty():
		return ""
	
	var tile := valid_tiles[rng.randi() % valid_tiles.size()]
	collapse_to(tile)
	return tile


func intersect_with(allowed_mask: int) -> bool:
	## Intersect domain with allowed tiles (bitmask).
	## Returns true if domain changed.
	var old_mask := _mask
	_mask &= allowed_mask
	if _mask != old_mask:
		_update_entropy()
		return true
	return false


func restrict_to(allowed_tiles: Array[String]) -> bool:
	## Restrict domain to only these tiles.
	## Returns true if domain changed.
	var allowed_mask := 0
	for tile in allowed_tiles:
		if _tile_to_index.has(tile):
			allowed_mask |= (1 << _tile_to_index[tile])
	return intersect_with(allowed_mask)


func remove_tile(tile_id: String) -> bool:
	## Remove a tile from the domain.
	## Returns true if domain changed.
	if not _tile_to_index.has(tile_id):
		return false
	
	var bit: int = 1 << int(_tile_to_index[tile_id])
	if (_mask & bit) != 0:
		_mask &= ~bit
		_update_entropy()
		return true
	return false


func get_mask() -> int:
	## Get the raw bitmask.
	return _mask


func _update_entropy() -> void:
	## Recalculate entropy from mask.
	_entropy = 0
	var m := _mask
	while m != 0:
		_entropy += m & 1
		m >>= 1
