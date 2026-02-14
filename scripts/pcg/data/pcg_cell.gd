class_name PCGCell
extends RefCounted

## Atomic unit of the unified PCG grid.
## Contains all data for a single cell (road, zone, POI, metadata).

const TileAssetResolver := preload("res://scripts/pcg/tile_asset_resolver.gd")

# -- Properties --
var logic_type: int = TileAssetResolver.LogicType.GRASS  # Replaces is_road, unifies tile type
var has_lane: bool = false  # Whether this road cell has lane markings
var zone_type: int = 0      # ZoneMap.ZoneType values (0=WILDERNESS, 1=SUBURBS, 2=URBAN)
var poi_type: int = -1      # POIList.POIType values (-1=NONE)
var data: Dictionary = {}   # Extensible metadata

# -- Helpers --
func has_poi() -> bool:
	return poi_type >= 0

func is_wilderness() -> bool:
	return zone_type == 0

func is_urban() -> bool:
	return zone_type == 2

## Check if this cell is a road (backward compatibility)
func is_road() -> bool:
	return logic_type == TileAssetResolver.LogicType.ROAD

## Check if this cell is a building (backward compatibility)
func is_building() -> bool:
	return logic_type == TileAssetResolver.LogicType.BUILDING

## Check if this cell is a sidewalk (backward compatibility)
func is_sidewalk() -> bool:
	return logic_type == TileAssetResolver.LogicType.SIDEWALK
