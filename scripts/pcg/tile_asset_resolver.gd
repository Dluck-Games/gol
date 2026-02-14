class_name TileAssetResolver
extends RefCounted
## Maps logical tile states to physical asset paths with hierarchical fallback.
##
## The resolver searches for assets in order of specificity:
## 1. Specific: {logic}/{transaction}/{neighbor}/{direction}/{variant}/base.png
## 2. Neighbor base: {logic}/{transaction}/{neighbor}/base.png
## 3. Transaction base: {logic}/{transaction}/base.png
## 4. Logic base: {logic}/base.png
## 5. Global fallback: default error texture


## Primary material or purpose of the tile
enum LogicType {
	ROAD = 0,
	SIDEWALK = 1,
	CROSSWALK = 2,
	GRASS = 3,
	DIRT = 4,
	WATER = 5,
	FLOOR = 6,
	BUILDING = 7,
}

## Transition type based on neighboring tile layout
## Determines how many sides border a different tile type
enum TransitionType {
	NONE = 0,        # No special transition (center/basic tile)
	EDGE = 1,        # 1 side borders different type
	CORNER = 2,      # 2 adjacent sides border different type
	OPPOSITE = 3,    # 2 opposite sides border different type (corridor/path)
	END = 4,         # 3 sides border different type (dead end)
	ISOLATED = 5,    # 4 sides border different type (island)
}

## Isometric direction (4 diagonal + 4 cardinal directions)
## Direction points TOWARD the neighbor that differs
enum Direction {
	NONE = 0,
	NW = 1,    # North-West (diagonal)
	NE = 2,    # North-East (diagonal)
	SW = 3,    # South-West (diagonal)
	SE = 4,    # South-East (diagonal)
	N = 5,     # North (cardinal) - for corner tiles
	S = 6,     # South (cardinal) - for corner tiles
	E = 7,     # East (cardinal) - for corner tiles
	W = 8,     # West (cardinal) - for corner tiles
}


const ASSET_ROOT := "res://assets/tiles/"
const DEFAULT_PATH := "res://assets/tiles/default/base.png"


## Lookup tables for enum to string conversion (lowercase)
const _LOGIC_NAMES: PackedStringArray = [
	"road", "sidewalk", "crosswalk", "grass", "dirt", "water", "floor", "building"
]

const _TRANSITION_NAMES: PackedStringArray = [
	"none", "edge", "corner", "opposite", "end", "isolated"
]

const _DIRECTION_NAMES: PackedStringArray = [
	"none", "nw", "ne", "sw", "se", "n", "s", "e", "w"
]


## Cache for resolved paths to avoid repeated filesystem checks
var _cache: Dictionary = {}


## Returns the best matching asset path for the given parameters.
## Uses a fallback chain from most specific to least specific.
func resolve(
	logic: LogicType,
	transition: TransitionType,
	neighbor: LogicType,
	direction: Direction,
	variant: String = "base"
) -> String:
	var cache_key := _make_cache_key(logic, transition, neighbor, direction, variant)
	
	if _cache.has(cache_key):
		return _cache[cache_key]
	
	var result := _resolve_uncached(logic, transition, neighbor, direction, variant)
	_cache[cache_key] = result
	return result


## Clears the internal path cache.
func clear_cache() -> void:
	_cache.clear()


## Internal resolution without caching
func _resolve_uncached(
	logic: LogicType,
	transition: TransitionType,
	neighbor: LogicType,
	direction: Direction,
	variant: String
) -> String:
	var logic_name := _LOGIC_NAMES[logic]
	var transition_name := _TRANSITION_NAMES[transition]
	var neighbor_name := _LOGIC_NAMES[neighbor]
	var direction_name := _DIRECTION_NAMES[direction]
	
	# Build fallback path list from most specific to least specific
	var paths: Array[String] = []
	
	# Level 0: Direct variant file under logic folder (e.g., road/center_v.png)
	if variant != "base":
		paths.append("%s%s/%s.png" % [ASSET_ROOT, logic_name, variant])
	
	# Level 1: Full specific path - simplified structure
	# New format: {logic}/{transition}/{neighbor}/{direction}/base.png
	# e.g., sidewalk/corner/road/ne/base.png (NOT sidewalk/corner/road/e/ne/base.png)
	if direction != Direction.NONE and transition != TransitionType.NONE:
		if variant != "base":
			paths.append("%s%s/%s/%s/%s/%s.png" % [
				ASSET_ROOT, logic_name, transition_name, neighbor_name, direction_name, variant
			])
		paths.append("%s%s/%s/%s/%s/base.png" % [
			ASSET_ROOT, logic_name, transition_name, neighbor_name, direction_name
		])
	
	# Level 2: Neighbor base (only if transition is not NONE)
	if transition != TransitionType.NONE:
		if variant != "base":
			paths.append("%s%s/%s/%s/%s/base.png" % [
				ASSET_ROOT, logic_name, transition_name, neighbor_name, variant
			])
		paths.append("%s%s/%s/%s/base.png" % [
			ASSET_ROOT, logic_name, transition_name, neighbor_name
		])
	
	# Level 3: Transition base (only if transition is not NONE)
	if transition != TransitionType.NONE:
		if variant != "base":
			paths.append("%s%s/%s/%s/base.png" % [
				ASSET_ROOT, logic_name, transition_name, variant
			])
		paths.append("%s%s/%s/base.png" % [
			ASSET_ROOT, logic_name, transition_name
		])
	
	# Level 4: Logic base
	paths.append("%s%s/base.png" % [ASSET_ROOT, logic_name])
	
	# Search for first existing file
	for path in paths:
		if FileAccess.file_exists(path):
			return path
	
	# Level 5: Global fallback
	return DEFAULT_PATH


## Creates a unique cache key from parameters
func _make_cache_key(
	logic: LogicType,
	transition: TransitionType,
	neighbor: LogicType,
	direction: Direction,
	variant: String
) -> int:
	# Pack into a hash for fast lookup
	var key := logic
	key = (key << 4) | transition
	key = (key << 4) | neighbor
	key = (key << 4) | direction
	return hash(str(key) + variant)
