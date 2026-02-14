class_name ZoneMap
extends RefCounted

## Minimal PCG zone classification map.


enum ZoneType {
	WILDERNESS = 0,
	SUBURBS = 1,
	URBAN = 2,
}

## Dictionary mapping grid coordinates (Vector2i) to ZoneType (stored as int).
var zones: Dictionary = {}


func set_zone(cell: Vector2i, zone_type: int) -> void:
	zones[cell] = zone_type


func get_zone(cell: Vector2i) -> int:
	return int(zones.get(cell, ZoneType.WILDERNESS))


func get_zones_in_rect(rect: Rect2i) -> Dictionary:
	var found: Dictionary = {}
	for cell: Vector2i in zones.keys():
		if rect.has_point(cell):
			found[cell] = int(zones[cell])
	return found
