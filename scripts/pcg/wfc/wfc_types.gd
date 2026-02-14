# scripts/pcg/wfc/wfc_types.gd
class_name WFCTypes
extends RefCounted
## WFC core data types and constants.
## Provides domain representation and direction utilities for constraint propagation.

## Isometric directions for TILE_LAYOUT_DIAMOND_DOWN
## In diamond-down layout:
##   - Grid X+ goes down-right (SE visually)
##   - Grid Y+ goes down-left (SW visually)
##   - Grid X- goes up-left (NW visually)
##   - Grid Y- goes up-right (NE visually)
enum Direction {
	NE = 0,  # (0, -1) - Grid Y- = up-right visually
	SW = 1,  # (0, 1)  - Grid Y+ = down-left visually
	NW = 2,  # (-1, 0) - Grid X- = up-left visually
	SE = 3,  # (1, 0)  - Grid X+ = down-right visually
}

## Direction count
const DIR_COUNT := 4

## Direction offsets as Vector2i (indexed by Direction enum)
const DIR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),   # NE (index 0)
	Vector2i(0, 1),    # SW (index 1)
	Vector2i(-1, 0),   # NW (index 2)
	Vector2i(1, 0),    # SE (index 3)
]

## Opposite direction lookup (indexed by Direction enum)
const DIR_OPPOSITE: Array[int] = [
	Direction.SW,  # Opposite of NE (index 0)
	Direction.NE,  # Opposite of SW (index 1)
	Direction.SE,  # Opposite of NW (index 2)
	Direction.NW,  # Opposite of SE (index 3)
]


static func get_offset(direction: int) -> Vector2i:
	return DIR_OFFSETS[direction]


static func get_opposite(direction: int) -> int:
	return DIR_OPPOSITE[direction]


static func direction_name(direction: int) -> String:
	match direction:
		Direction.NE: return "NE"
		Direction.SW: return "SW"
		Direction.NW: return "NW"
		Direction.SE: return "SE"
	return "UNKNOWN"
