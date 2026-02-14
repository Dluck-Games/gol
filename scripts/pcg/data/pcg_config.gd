class_name PCGConfig
extends RefCounted

## Configuration data for the PCG pipeline (no Node dependencies).

# PCG core parameters
var pcg_seed: int = 0
var grid_size: int = 100

# Grid-based road generation parameters
var grid_arterial_spacing: int = 16
var arterial_min_spacing: int = 10
var arterial_split_jitter: float = 0.25
var arterial_split_max_depth: int = 3
var arterial_split_bias: float = 0.5  # 0.5 = neutral, >0.5 vertical bias

var grid_local_subdivision_urban: int = 2
var grid_local_subdivision_suburbs: int = 1
var grid_local_subdivision_wilderness: int = 0

var local_split_ratio_min: float = 0.3
var local_split_ratio_max: float = 0.7
var local_split_min_block_size: int = 6

var road_width_arterial: float = 2.0
var road_width_local: float = 1.0

# Zone thresholds (normalized 0..1)
var zone_threshold_suburbs: float = 0.35
var zone_threshold_urban: float = 0.7

# POI Generation Counts
var building_count_urban: int = 15
var building_count_suburbs: int = 10
var village_count_suburbs: int = 3
var enemy_spawn_count_wilderness: int = 8

# Minimum spacing between POIs (in cells)
# Key: POIType (int), Value: spacing (int)
# 0: BUILDING, 1: VILLAGE, 2: ENEMY_SPAWN
var min_spacing_cells_by_type: Dictionary = {
	0: 3, 
	1: 15,
	2: 10
}

# Minimum spacing between different POI types (in cells)
# Key: String "type_a,type_b" (sorted pair), Value: spacing (int)
# Ensures safe distance between player starting area (VILLAGE) and enemy spawners (ENEMY_SPAWN)
var min_spacing_cross_type: Dictionary = {
	"1,2": 20,  # VILLAGE to ENEMY_SPAWN minimum distance
}


func validate() -> Array[String]:
	var errors: Array[String] = []

	# Threshold range checks
	if zone_threshold_suburbs < 0.0 or zone_threshold_suburbs > 1.0:
		errors.append("zone_threshold_suburbs must be within 0..1")
	if zone_threshold_urban < 0.0 or zone_threshold_urban > 1.0:
		errors.append("zone_threshold_urban must be within 0..1")

	# Threshold ordering check (only meaningful when both are in range)
	if (
		zone_threshold_suburbs >= 0.0 and zone_threshold_suburbs <= 1.0
		and zone_threshold_urban >= 0.0 and zone_threshold_urban <= 1.0
		and zone_threshold_urban <= zone_threshold_suburbs
	):
		errors.append("zone_threshold_urban must be greater than zone_threshold_suburbs")

	# Grid parameter sanity checks
	if grid_arterial_spacing <= 0:
		errors.append("grid_arterial_spacing must be > 0")
	if arterial_min_spacing <= 0:
		errors.append("arterial_min_spacing must be > 0")
	if arterial_split_jitter < 0.0 or arterial_split_jitter >= 0.5:
		errors.append("arterial_split_jitter must be 0..0.5")
	
	if local_split_ratio_min < 0.1 or local_split_ratio_min > 0.5:
		errors.append("local_split_ratio_min must be 0.1..0.5")
	if local_split_ratio_max < 0.5 or local_split_ratio_max > 0.9:
		errors.append("local_split_ratio_max must be 0.5..0.9")
	if local_split_ratio_min >= local_split_ratio_max:
		errors.append("local_split_ratio_min must be < local_split_ratio_max")
		
	if grid_local_subdivision_urban < 0:
		errors.append("grid_local_subdivision_urban must be >= 0")
	if grid_local_subdivision_suburbs < 0:
		errors.append("grid_local_subdivision_suburbs must be >= 0")
	if grid_local_subdivision_wilderness < 0:
		errors.append("grid_local_subdivision_wilderness must be >= 0")
	if road_width_arterial <= 0.0:
		errors.append("road_width_arterial must be > 0")
	if road_width_local <= 0.0:
		errors.append("road_width_local must be > 0")

	return errors
