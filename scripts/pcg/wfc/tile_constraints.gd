# scripts/pcg/wfc/tile_constraints.gd
class_name TileConstraints
extends RefCounted
## Defines WFC adjacency constraints for tile transitions.
## Each tile variant specifies which neighbors it allows in each direction.
##
## Transition Types (based on neighbor differences):
## - EDGE: 1 side differs (direction points to different neighbor)
## - CORNER: 2 adjacent sides differ (direction points to corner)
## - OPPOSITE: 2 opposite sides differ (corridor/path)
## - END: 3 sides differ (dead end)
## - ISOLATED: 4 sides differ (island)
##
## Direction Convention:
## - NW, NE, SW, SE are the 4 isometric directions
## - Direction indicates WHERE the different neighbor is

const WFCRules := preload("res://scripts/pcg/wfc/wfc_rules.gd")
const WFCTypes := preload("res://scripts/pcg/wfc/wfc_types.gd")

## Direction aliases
const NW := WFCTypes.Direction.NW
const NE := WFCTypes.Direction.NE
const SW := WFCTypes.Direction.SW
const SE := WFCTypes.Direction.SE


## Build constraints for road tiles
static func build_road_rules() -> WFCRules:
	var rules := WFCRules.new()
	
	# Road tile variants
	var tiles: Array[String] = [
		"basic",       # Plain road, no markings
		"center_v",    # Vertical lane marking (NW-SE axis)
		"center_h",    # Horizontal lane marking (SW-NE axis)
		"crosswalk",   # Crosswalk marking
	]
	rules.register_tiles(tiles)
	
	# center_v: vertical lane - connects along NW-SE axis
	_connect_along_axis(rules, "center_v", NW, SE)
	_connect_perpendicular(rules, "center_v", SW, NE, ["basic", "crosswalk"])
	
	# center_h: horizontal lane - connects along SW-NE axis
	_connect_along_axis(rules, "center_h", SW, NE)
	_connect_perpendicular(rules, "center_h", NW, SE, ["basic", "crosswalk"])
	
	# crosswalk: can connect to any road tile
	rules.add_all_directions("crosswalk", "basic")
	rules.add_all_directions("crosswalk", "center_v")
	rules.add_all_directions("crosswalk", "center_h")
	rules.add_all_directions("crosswalk", "crosswalk")
	
	# basic: generic road, connects to anything
	for tile in tiles:
		rules.add_all_directions("basic", tile)
	
	return rules


## Build constraints for sidewalk tiles
static func build_sidewalk_rules() -> WFCRules:
	var rules := WFCRules.new()
	
	# Sidewalk tile variants - naming convention
	# edge_road_{dir}: single edge facing road in direction {dir}
	# edge_grassground_{dir}: single edge facing grassground in direction {dir}
	# corner_road_{dir}: corner where two edges meet at {dir}
	# corner_grassground_{dir}: corner bordering grassground
	# outcorner_road_{dir}: out-corner where sidewalk protrudes into road
	# grassground_N: grassground variants used as sidewalk base
	var tiles: Array[String] = [
		"basic",
		# Grassground variants (plain sidewalk alternatives)
		"grassground_1", "grassground_2", "grassground_3", "grassground_4",
		# Edge tiles (1 side borders road)
		"edge_road_nw", "edge_road_ne", "edge_road_sw", "edge_road_se",
		# Edge grassground tiles (1 side borders grassground)
		"edge_grassground_nw", "edge_grassground_ne", "edge_grassground_sw", "edge_grassground_se",
		# Corner tiles (2 adjacent sides border road) - naming: corner points in cardinal direction
		"corner_road_n", "corner_road_s", "corner_road_e", "corner_road_w",
		# Corner grassground tiles (2 adjacent sides border grassground)
		"corner_grassground_n", "corner_grassground_s", "corner_grassground_e", "corner_grassground_w",
		# Outcorner tiles (sidewalk protrudes into road) - naming: outcorner points in cardinal direction
		"outcorner_road_n", "outcorner_road_s", "outcorner_road_e", "outcorner_road_w",
		# Crosswalk edge variants
		"edge_road_nw_crosswalk", "edge_road_ne_crosswalk",
		"edge_road_sw_crosswalk", "edge_road_se_crosswalk",
	]
	rules.register_tiles(tiles)
	
	# Basic sidewalk - connects to any sidewalk
	for tile in tiles:
		rules.add_all_directions("basic", tile)
	
	# Grassground variants - same as basic, can connect to anything
	for i in range(1, 5):
		var grassground := "grassground_%d" % i
		for tile in tiles:
			rules.add_all_directions(grassground, tile)
	
	# Edge tiles: curb faces one direction (toward road)
	# The edge continues along perpendicular directions
	_add_edge_tile_rules(rules, "edge_road_nw", NW)
	_add_edge_tile_rules(rules, "edge_road_ne", NE)
	_add_edge_tile_rules(rules, "edge_road_sw", SW)
	_add_edge_tile_rules(rules, "edge_road_se", SE)
	
	# Edge grassground tiles - same rules as regular edges
	_add_edge_tile_rules(rules, "edge_grassground_nw", NW)
	_add_edge_tile_rules(rules, "edge_grassground_ne", NE)
	_add_edge_tile_rules(rules, "edge_grassground_sw", SW)
	_add_edge_tile_rules(rules, "edge_grassground_se", SE)
	
	# Crosswalk edge variants - same rules as regular edges
	_add_edge_tile_rules(rules, "edge_road_nw_crosswalk", NW)
	_add_edge_tile_rules(rules, "edge_road_ne_crosswalk", NE)
	_add_edge_tile_rules(rules, "edge_road_sw_crosswalk", SW)
	_add_edge_tile_rules(rules, "edge_road_se_crosswalk", SE)
	
	# Corner tiles: two adjacent edges meet - naming: corner points in cardinal direction (n, s, e, w)
	# corner_road_n: points North, has roads at NW and NE
	# corner_road_s: points South, has roads at SW and SE
	# corner_road_e: points East, has roads at NE and SE
	# corner_road_w: points West, has roads at NW and SW
	_add_cardinal_corner_tile_rules(rules, "corner_road_n", NW, NE)
	_add_cardinal_corner_tile_rules(rules, "corner_road_s", SW, SE)
	_add_cardinal_corner_tile_rules(rules, "corner_road_e", NE, SE)
	_add_cardinal_corner_tile_rules(rules, "corner_road_w", NW, SW)
	
	# Corner grassground tiles - same rules as regular corners
	_add_cardinal_corner_tile_rules(rules, "corner_grassground_n", NW, NE)
	_add_cardinal_corner_tile_rules(rules, "corner_grassground_s", SW, SE)
	_add_cardinal_corner_tile_rules(rules, "corner_grassground_e", NE, SE)
	_add_cardinal_corner_tile_rules(rules, "corner_grassground_w", NW, SW)
	
	# Note: corner_grassground uses cardinal naming without road prefix
	
	# Outcorner tiles: sidewalk protrudes into road area
	# These are like inverted corners - road is on three sides
	_add_cardinal_outcorner_tile_rules(rules, "outcorner_road_n", NW, NE)
	_add_cardinal_outcorner_tile_rules(rules, "outcorner_road_s", SW, SE)
	_add_cardinal_outcorner_tile_rules(rules, "outcorner_road_e", NE, SE)
	_add_cardinal_outcorner_tile_rules(rules, "outcorner_road_w", NW, SW)
	
	return rules


## Helper: Connect tile along an axis (both directions)
static func _connect_along_axis(rules: WFCRules, tile: String, dir1: int, dir2: int) -> void:
	rules.add_constraint(tile, dir1, tile)
	rules.add_constraint(tile, dir2, tile)
	# Also allow crosswalk along the axis
	if rules.get_all_tiles().has("crosswalk"):
		rules.add_constraint(tile, dir1, "crosswalk")
		rules.add_constraint(tile, dir2, "crosswalk")


## Helper: Connect to tiles in perpendicular directions
static func _connect_perpendicular(rules: WFCRules, tile: String, dir1: int, dir2: int, neighbors: Array[String]) -> void:
	for neighbor in neighbors:
		if rules.get_all_tiles().has(neighbor):
			rules.add_constraint(tile, dir1, neighbor)
			rules.add_constraint(tile, dir2, neighbor)


## Helper: Add rules for an edge tile
## Edge tile has road on one side (road_dir) and sidewalk on others
static func _add_edge_tile_rules(rules: WFCRules, tile: String, road_dir: int) -> void:
	var all_tiles := rules.get_all_tiles()
	var opposite_dir := WFCTypes.get_opposite(road_dir)
	
	# Get perpendicular directions
	var perp1: int
	var perp2: int
	if road_dir == NW or road_dir == SE:
		perp1 = SW
		perp2 = NE
	else:
		perp1 = NW
		perp2 = SE
	
	# Toward sidewalk (opposite of road): connect to basic or same-direction edge
	rules.add_constraint(tile, opposite_dir, "basic")
	rules.add_constraint(tile, opposite_dir, tile)
	
	# Perpendicular: connect to edges, corners, basic
	for other_tile in all_tiles:
		if other_tile == "basic" or other_tile.begins_with("edge_") or other_tile.begins_with("corner_"):
			rules.add_constraint(tile, perp1, other_tile)
			rules.add_constraint(tile, perp2, other_tile)


## Helper: Add rules for a corner tile
## Corner tile has roads on two adjacent sides meeting at the corner
static func _add_corner_tile_rules(rules: WFCRules, tile: String, corner_dir: int) -> void:
	var all_tiles := rules.get_all_tiles()
	
	# Corner direction determines which two edges form the corner
	# e.g., corner_nw means roads are at NW and one of SW/NE
	# The corner "points" toward the road corner
	
	# For corner tiles, the opposite direction is toward sidewalk
	var opposite_dir := WFCTypes.get_opposite(corner_dir)
	
	# Determine adjacent directions based on corner
	var adj1: int
	var adj2: int
	match corner_dir:
		NW:
			adj1 = SW
			adj2 = NE
		NE:
			adj1 = NW
			adj2 = SE
		SW:
			adj1 = NW
			adj2 = SE
		SE:
			adj1 = SW
			adj2 = NE
	
	# Toward sidewalk interior: basic or edges/corners
	rules.add_constraint(tile, opposite_dir, "basic")
	
	# Adjacent directions: edges and other corners
	for other_tile in all_tiles:
		if other_tile == "basic" or other_tile.begins_with("edge_") or other_tile.begins_with("corner_"):
			rules.add_constraint(tile, adj1, other_tile)
			rules.add_constraint(tile, adj2, other_tile)


## Helper: Add rules for an outcorner tile
## Outcorner tile has sidewalk protruding into the road (road on 3 sides, sidewalk on 1)
static func _add_outcorner_tile_rules(rules: WFCRules, tile: String, protrude_dir: int) -> void:
	var all_tiles := rules.get_all_tiles()
	
	# The protrude direction is where the sidewalk sticks out (only sidewalk neighbor there)
	# Other 3 directions have road
	var opposite_dir := WFCTypes.get_opposite(protrude_dir)
	
	# Determine adjacent directions based on protrusion
	var adj1: int
	var adj2: int
	match protrude_dir:
		NW:
			adj1 = SW
			adj2 = NE
		NE:
			adj1 = NW
			adj2 = SE
		SW:
			adj1 = NW
			adj2 = SE
		SE:
			adj1 = SW
			adj2 = NE
	
	# In the protrusion direction: connect to edges that face back toward this outcorner
	# e.g., outcorner_nw connects to edge_se in the NW direction
	var matching_edge := "edge_" + WFCTypes.direction_name(opposite_dir).to_lower()
	rules.add_constraint(tile, protrude_dir, matching_edge)
	rules.add_constraint(tile, protrude_dir, "basic")
	
	# In adjacent directions: can connect to edges and corners
	for other_tile in all_tiles:
		if other_tile == "basic" or other_tile.begins_with("edge_") or other_tile.begins_with("corner_") or other_tile.begins_with("outcorner_"):
			rules.add_constraint(tile, adj1, other_tile)
			rules.add_constraint(tile, adj2, other_tile)


## Helper: Add rules for a corner tile with cardinal naming (n, s, e, w)
## Corner tile has roads on two adjacent sides
## road_dir1 and road_dir2 are the two isometric directions that have roads
static func _add_cardinal_corner_tile_rules(rules: WFCRules, tile: String, road_dir1: int, road_dir2: int) -> void:
	var all_tiles := rules.get_all_tiles()
	
	# The sidewalk interior is opposite to the corner direction
	# For corner_n (roads at NW, NE), sidewalk is at SE and SW (South)
	var sidewalk_dirs: Array[int] = []
	for dir in [NW, NE, SW, SE]:
		if dir != road_dir1 and dir != road_dir2:
			sidewalk_dirs.append(dir)
	
	# Toward sidewalk interior: basic or edges/corners
	for sidewalk_dir in sidewalk_dirs:
		rules.add_constraint(tile, sidewalk_dir, "basic")
		for other_tile in all_tiles:
			if other_tile == "basic" or other_tile.begins_with("edge_") or other_tile.begins_with("corner_") or other_tile.begins_with("outcorner_"):
				rules.add_constraint(tile, sidewalk_dir, other_tile)
	
	# Toward roads: connect to edge tiles that face the road
	# A corner at NW should connect to edge_nw (which faces NW toward the road)
	for road_dir in [road_dir1, road_dir2]:
		var edge_name := "edge_" + WFCTypes.direction_name(road_dir).to_lower()
		rules.add_constraint(tile, road_dir, edge_name)
		# Also allow connection to basic sidewalk tiles
		rules.add_constraint(tile, road_dir, "basic")
	
	# CRITICAL: Perpendicular directions (between road and sidewalk)
	# These are the directions where corners connect to edges
	# For corner_n (roads at NW, NE), perpendicular directions are SW and SE
	# In these directions, corners should connect to edges that are perpendicular to them
	var perp_dirs: Array[int] = []
	for dir in [NW, NE, SW, SE]:
		if dir != road_dir1 and dir != road_dir2:
			perp_dirs.append(dir)
	
	# In perpendicular directions: connect to edges and other corners
	for perp_dir in perp_dirs:
		for other_tile in all_tiles:
			if other_tile.begins_with("edge_") or other_tile.begins_with("corner_") or other_tile.begins_with("outcorner_"):
				rules.add_constraint(tile, perp_dir, other_tile)


## Helper: Add rules for an outcorner tile with cardinal naming (n, s, e, w)
## Outcorner tile has sidewalk protruding into road (road on 3 sides, sidewalk on 1)
## sidewalk_dir1 and sidewalk_dir2 are the two isometric directions toward sidewalk
static func _add_cardinal_outcorner_tile_rules(rules: WFCRules, tile: String, sidewalk_dir1: int, sidewalk_dir2: int) -> void:
	var all_tiles := rules.get_all_tiles()
	
	# Road directions are the opposite of sidewalk directions
	var road_dirs: Array[int] = []
	for dir in [NW, NE, SW, SE]:
		if dir != sidewalk_dir1 and dir != sidewalk_dir2:
			road_dirs.append(dir)
	
	# Toward sidewalk: connect to basic and matching edges
	for sidewalk_dir in [sidewalk_dir1, sidewalk_dir2]:
		var opposite_dir := WFCTypes.get_opposite(sidewalk_dir)
		var matching_edge := "edge_" + WFCTypes.direction_name(opposite_dir).to_lower()
		rules.add_constraint(tile, sidewalk_dir, matching_edge)
		rules.add_constraint(tile, sidewalk_dir, "basic")
	
	# Toward roads: connect to edges and corners
	for road_dir in road_dirs:
		for other_tile in all_tiles:
			if other_tile.begins_with("edge_") or other_tile.begins_with("corner_") or other_tile.begins_with("outcorner_"):
				rules.add_constraint(tile, road_dir, other_tile)
