# scripts/pcg/wfc/wfc_solver.gd
class_name WFCSolver
extends RefCounted
## Wave Function Collapse solver for tile variant selection.
## Uses constraint propagation to select valid tile variants.

const _WFCTypes := preload("res://scripts/pcg/wfc/wfc_types.gd")
const _WFCDomain := preload("res://scripts/pcg/wfc/wfc_domain.gd")
const _WFCRules := preload("res://scripts/pcg/wfc/wfc_rules.gd")

## Solver state
enum State {
	READY,
	RUNNING,
	COMPLETED,
	CONTRADICTION,
}

## Rules defining tile adjacency constraints
var rules: _WFCRules

## Random number generator for deterministic selection
var rng: RandomNumberGenerator

## Grid of domains: position -> WFCDomain
var _domains: Dictionary = {}

## Positions that need propagation (stack)
var _propagation_stack: Array[Vector2i] = []

## Current state
var _state: State = State.READY

## Backtrack history (for future backtracking support)
var _history: Array = []

## Enable backtracking
var backtracking_enabled: bool = false

## Maximum backtrack attempts
var max_backtrack_attempts: int = 100

## Current backtrack count
var _backtrack_count: int = 0


func _init(p_rules: _WFCRules = null, p_rng: RandomNumberGenerator = null) -> void:
	rules = p_rules if p_rules else _WFCRules.new()
	rng = p_rng if p_rng else RandomNumberGenerator.new()


func reset() -> void:
	## Reset solver state for new run.
	_domains.clear()
	_propagation_stack.clear()
	_history.clear()
	_state = State.READY
	_backtrack_count = 0


func initialize_cell(pos: Vector2i, candidates: Array[String]) -> void:
	## Initialize a cell with given candidates as its domain.
	var all_tiles := rules.get_all_tiles()
	
	# Filter candidates to only those in rules
	var valid_candidates: Array[String] = []
	for c in candidates:
		if c in all_tiles:
			valid_candidates.append(c)
	
	if valid_candidates.is_empty():
		# Fallback: if no candidates match rules, use first candidate
		if not candidates.is_empty():
			valid_candidates.append(candidates[0])
			if candidates[0] not in all_tiles:
				rules.register_tile(candidates[0])
	
	var domain := _WFCDomain.new(valid_candidates, all_tiles)
	_domains[pos] = domain


func set_precondition(pos: Vector2i, tile_id: String) -> void:
	## Force a cell to a specific tile (precondition).
	## Used for tiles that must be a certain value (e.g., known crosswalks).
	if not _domains.has(pos):
		return
	
	var domain: _WFCDomain = _domains[pos]
	if domain.has_tile(tile_id):
		domain.collapse_to(tile_id)
		_queue_propagation(pos)


func bias_toward(pos: Vector2i, tile_id: String, factor: float = 10.0) -> void:
	## Bias selection toward a specific tile (soft constraint).
	## This doesn't force selection but increases probability.
	## For now, just a marker - actual implementation would use weighted selection.
	# TODO: Implement weighted selection
	pass


func solve() -> State:
	## Run WFC to completion.
	## Returns final state (COMPLETED or CONTRADICTION).
	_state = State.RUNNING
	
	while _state == State.RUNNING:
		# Step 1: Propagate constraints
		if not _propagate():
			# Contradiction during propagation
			if backtracking_enabled and _try_backtrack():
				continue
			_state = State.CONTRADICTION
			break
		
		# Step 2: Check if done
		if _is_all_collapsed():
			_state = State.COMPLETED
			break
		
		# Step 3: Find cell with minimum entropy and collapse it
		var min_pos := _find_min_entropy_cell()
		if min_pos == Vector2i(-99999, -99999):
			# No uncollapsed cells found (shouldn't happen if not all collapsed)
			_state = State.COMPLETED
			break
		
		# Save state for potential backtracking
		if backtracking_enabled:
			_save_state(min_pos)
		
		# Collapse the cell
		var domain: _WFCDomain = _domains[min_pos]
		var tile := domain.collapse_random(rng)
		if tile.is_empty():
			if backtracking_enabled and _try_backtrack():
				continue
			_state = State.CONTRADICTION
			break
		
		_queue_propagation(min_pos)
	
	return _state


func get_result(pos: Vector2i) -> String:
	## Get the collapsed tile for a position.
	## Returns empty string if not collapsed or position not initialized.
	if not _domains.has(pos):
		return ""
	
	var domain: _WFCDomain = _domains[pos]
	if domain.is_collapsed():
		return domain.get_collapsed_tile()
	return ""


func get_state() -> State:
	return _state


func _queue_propagation(pos: Vector2i) -> void:
	## Add position to propagation stack.
	if pos not in _propagation_stack:
		_propagation_stack.append(pos)


func _propagate() -> bool:
	## Propagate constraints from collapsed cells.
	## Returns false if contradiction detected.
	
	while not _propagation_stack.is_empty():
		var pos: Vector2i = _propagation_stack.pop_back()
		
		if not _domains.has(pos):
			continue
		
		var domain: _WFCDomain = _domains[pos]
		var valid_tiles := domain.get_valid_tiles()
		
		if valid_tiles.is_empty():
			return false  # Contradiction
		
		# For each direction, compute allowed neighbors and constrain
		for dir in range(_WFCTypes.DIR_COUNT):
			var neighbor_pos: Vector2i = pos + _WFCTypes.get_offset(dir)
			
			if not _domains.has(neighbor_pos):
				continue
			
			var neighbor_domain: _WFCDomain = _domains[neighbor_pos]
			
			if neighbor_domain.is_collapsed():
				continue  # Already decided
			
			# Compute union of allowed neighbors from all valid tiles
			var allowed_mask := rules.compute_union_mask(valid_tiles, dir)
			
			# Intersect neighbor's domain with allowed
			var changed := neighbor_domain.intersect_with(allowed_mask)
			
			if neighbor_domain.is_contradiction():
				return false  # Contradiction
			
			if changed:
				_queue_propagation(neighbor_pos)
	
	return true


func _is_all_collapsed() -> bool:
	## Check if all cells are collapsed.
	for domain: _WFCDomain in _domains.values():
		if not domain.is_collapsed():
			return false
	return true


func _find_min_entropy_cell() -> Vector2i:
	## Find cell with minimum entropy (>1) for next collapse.
	## Returns sentinel value if all are collapsed.
	var min_entropy := 999
	var candidates: Array[Vector2i] = []
	
	for pos: Vector2i in _domains.keys():
		var domain: _WFCDomain = _domains[pos]
		var entropy := domain.entropy()
		
		if entropy <= 1:
			continue  # Already collapsed or contradiction
		
		if entropy < min_entropy:
			min_entropy = entropy
			candidates.clear()
			candidates.append(pos)
		elif entropy == min_entropy:
			candidates.append(pos)
	
	if candidates.is_empty():
		return Vector2i(-99999, -99999)  # Sentinel for "none found"
	
	# Pick random among ties for determinism with seed
	return candidates[rng.randi() % candidates.size()]


func _save_state(collapse_pos: Vector2i) -> void:
	## Save current state for backtracking.
	var state_snapshot: Dictionary = {}
	for pos: Vector2i in _domains.keys():
		state_snapshot[pos] = _domains[pos].duplicate()
	
	var domain: _WFCDomain = _domains[collapse_pos]
	_history.append({
		"domains": state_snapshot,
		"collapse_pos": collapse_pos,
		"untried": domain.get_mask(),  # Current options
	})


func _try_backtrack() -> bool:
	## Attempt to backtrack to previous state.
	## Returns true if backtrack succeeded, false if no more options.
	_backtrack_count += 1
	
	if _backtrack_count > max_backtrack_attempts:
		return false
	
	while not _history.is_empty():
		var entry: Dictionary = _history.pop_back()
		var collapse_pos: Vector2i = entry["collapse_pos"]
		var untried: int = entry["untried"]
		
		# Restore domains
		_domains.clear()
		for pos: Vector2i in entry["domains"].keys():
			_domains[pos] = entry["domains"][pos].duplicate()
		
		# Remove the tile we just tried from options
		var domain: _WFCDomain = _domains[collapse_pos]
		var tried_tile := domain.get_collapsed_tile()
		
		# Get fresh domain and remove tried tile
		domain = entry["domains"][collapse_pos].duplicate()
		domain.remove_tile(tried_tile)
		_domains[collapse_pos] = domain
		
		if not domain.is_contradiction():
			# Can try another option
			_propagation_stack.clear()
			_queue_propagation(collapse_pos)
			return true
	
	return false
