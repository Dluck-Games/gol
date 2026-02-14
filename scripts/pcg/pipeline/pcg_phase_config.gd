# scripts/pcg/pipeline/pcg_phase_config.gd
class_name PCGPhaseConfig
extends RefCounted
## Centralized configuration for PCG pipeline phases.
## Provides the canonical phase order and names to ensure DRY compliance.

# Phase class references
const IrregularGridGenerator := preload("res://scripts/pcg/phases/irregular_grid_generator.gd")
const RoadRasterizer := preload("res://scripts/pcg/phases/road_rasterizer.gd")
const ZoneCalculator := preload("res://scripts/pcg/phases/zone_calculator.gd")
const ZoneSmoother := preload("res://scripts/pcg/phases/zone_smoother.gd")
const OrganicBlockSubdivider := preload("res://scripts/pcg/phases/organic_block_subdivider.gd")
const POIGenerator := preload("res://scripts/pcg/phases/poi_generator.gd")
const TileResolvePhase := preload("res://scripts/pcg/phases/tile_resolve_phase.gd")
const TileDecidePhase := preload("res://scripts/pcg/phases/tile_decide_phase.gd")


## Phase names for display/debug purposes.
## Index 0 is "Empty" (before any phases run), indices 1-8 are after each phase.
const PHASE_NAMES: Array[String] = [
	"Empty",
	"Irregular Grid",
	"Road Rasterizer",
	"Zone Calculator",
	"Zone Smoother",
	"Organic Subdivider",  # Now includes local street rasterization
	"POI Generator",
	"Tile Resolve",
	"Tile Decide"
]


## Returns a new array of phase instances in the canonical order.
## Callers should store the result; phases are instantiated fresh each call.
static func create_phases() -> Array[PCGPhase]:
	var phases: Array[PCGPhase] = []
	phases.append(IrregularGridGenerator.new())  # Main arterial grid
	phases.append(RoadRasterizer.new())          # Rasterize arterials for zone calc
	phases.append(ZoneCalculator.new())          # Zones from arterials
	phases.append(ZoneSmoother.new())            # Smooth zones
	phases.append(OrganicBlockSubdivider.new())  # Local streets + incremental rasterization
	phases.append(POIGenerator.new())            # POIs last
	phases.append(TileResolvePhase.new())
	phases.append(TileDecidePhase.new())
	return phases


## Returns the display name for a given phase index.
## Index 0 = "Empty", index 1-8 = after corresponding phase.
static func get_phase_name(phase_index: int) -> String:
	if phase_index < 0 or phase_index >= PHASE_NAMES.size():
		push_error("PCGPhaseConfig: Invalid phase index %d" % phase_index)
		return "Unknown"
	return PHASE_NAMES[phase_index]


## Returns the total number of phases (excluding the "Empty" state).
static func get_phase_count() -> int:
	return PHASE_NAMES.size() - 1


## Returns the total number of states (including the "Empty" state).
static func get_state_count() -> int:
	return PHASE_NAMES.size()
