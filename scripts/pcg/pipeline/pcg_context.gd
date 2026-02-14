# scripts/pcg/pipeline/pcg_context.gd
class_name PCGContext
extends RefCounted

const PCGCell := preload("res://scripts/pcg/data/pcg_cell.gd")

var road_graph: RoadGraph
var rng: RandomNumberGenerator

## Unified grid: Dictionary[Vector2i, PCGCell] - single source of truth
var grid: Dictionary = {}



## Road cells - generated on demand from unified grid
var road_cells: Dictionary[Vector2i, bool]:
	get:
		return _build_road_cells_from_grid()
	set(value):
		# No-op: road_cells is now a view, not a writable property
		pass


## Builds road_cells Dictionary from the unified grid
func _build_road_cells_from_grid() -> Dictionary[Vector2i, bool]:
	var rc: Dictionary[Vector2i, bool] = {}
	
	for pos: Variant in grid.keys():
		if pos is Vector2i:
			var cell: PCGCell = grid[pos]
			if cell.is_road():
				rc[pos] = true
	
	return rc


func _init(p_seed: int) -> void:
	road_graph = RoadGraph.new()

	rng = RandomNumberGenerator.new()
	rng.seed = p_seed


func _get_grid_size() -> int:
	# Default grid size - phases should set this if needed
	return 100


func _get_tile_size() -> int:
	# Default tile size
	return 32


func randi() -> int:
	return rng.randi()


func randf() -> float:
	return rng.randf()


func randi_range(from: int, to: int) -> int:
	return rng.randi_range(from, to)


func randf_range(from: float, to: float) -> float:
	return rng.randf_range(from, to)


# -- Unified grid helpers -------------------------------------------------
func get_cell(pos: Vector2i) -> PCGCell:
	# Return the cell at `pos` if present, otherwise return null.
	# This does NOT create or store a new cell — use get_or_create_cell for that.
	if grid.has(pos):
		return grid[pos]
	return null


func set_cell(pos: Vector2i, cell: PCGCell) -> void:
	# Store/replace the PCGCell at `pos` in the unified grid.
	grid[pos] = cell


func has_cell(pos: Vector2i) -> bool:
	return grid.has(pos)


func get_or_create_cell(pos: Vector2i) -> PCGCell:
	# Lazily create a PCGCell at `pos` when it doesn't exist, store and return it.
	if grid.has(pos):
		return grid[pos]
	var cell: PCGCell = PCGCell.new()
	grid[pos] = cell
	return cell
