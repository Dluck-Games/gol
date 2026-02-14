class_name POIList
extends RefCounted

## POI (Point of Interest) data structures for PCG pipeline
## Stores spawn points for buildings, villages, enemies, and loot

## POI types for procedural placement
enum POIType {
	BUILDING = 0,
	VILLAGE = 1,
	ENEMY_SPAWN = 2,
	LOOT_SPAWN = 3
}

## Individual POI with position, type, and optional metadata
class POI:
	extends RefCounted
	
	var position: Vector2
	var type: int
	var metadata: Dictionary
	
	func _init(p_position: Vector2, p_type: int, p_metadata: Dictionary) -> void:
		position = p_position
		type = p_type
		metadata = p_metadata


## Collection of POIs with query methods
var pois: Array = []


## Add a POI to the list
func add_poi(poi: POI) -> void:
	pois.append(poi)


## Get all POIs of a specific type
func get_pois_by_type(type: int) -> Array:
	var result: Array = []
	for poi in pois:
		if poi.type == type:
			result.append(poi)
	return result


## Get all POIs within range of a center point
func get_pois_in_range(center: Vector2, radius: float) -> Array:
	var result: Array = []
	for poi in pois:
		if poi.position.distance_to(center) <= radius:
			result.append(poi)
	return result
