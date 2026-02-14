# scripts/pcg/wfc/wfc_tile_rules_builder.gd
class_name WFCTileRulesBuilder
extends RefCounted
## DEPRECATED: Use TileConstraints instead.
## This file is kept for backward compatibility.
## See tile_constraints.gd for the new manual constraint management system.

const TileConstraints := preload("res://scripts/pcg/wfc/tile_constraints.gd")
const WFCRules := preload("res://scripts/pcg/wfc/wfc_rules.gd")


static func build_road_rules() -> WFCRules:
	## Build rules for road tiles.
	## @deprecated Use TileConstraints.build_road_rules() instead.
	return TileConstraints.build_road_rules()


static func build_sidewalk_rules() -> WFCRules:
	## Build rules for sidewalk tiles.
	## @deprecated Use TileConstraints.build_sidewalk_rules() instead.
	return TileConstraints.build_sidewalk_rules()
