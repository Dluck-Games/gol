# PCG Biome-First Map Generation Report

Date: 2026-05-19

## Background

The previous PCG map read too much like a road-centered distance field: roads and urban cells formed the core, suburbs wrapped around them, and wilderness wrapped around the suburbs. The result was structurally clear but visually algorithmic, closer to contour bands than to a naturally grown city.

The target direction is a biome-first city model. The map should start from terrain and regional suitability, then choose city anchors, place villages, connect them with trunk roads, and let roads and nearby civilization pressure evolve the final urban/suburban footprint.

## User Requirements Captured

- Generate terrain/regions before roads. Wilderness, suburbs, and plains-like regions should come from broad noise fields, not from road distance.
- Treat suburbs as a plains-like settlement-support biome. City anchors should emerge from suitable plains, with randomness, like salted probability sampling.
- Pick 2-3 city centers when space allows. Cities should be large enough to read as cities, not tiny dots.
- After city anchors are selected, place villages and generate a true trunk road network connecting villages and city centers.
- Roads may reach city boundaries or wilderness. There should be no fixed gap requirement between urban/suburban borders and road growth.
- Road evolution should still prefer civilized/suitable regions, so roads can reach wilderness but should not over-grow there by default.
- Civilization can spread from roads: cells near roads can become urban land or suburbs based on road pressure, city pull, terrain suitability, and noise.
- The final map should feel like terrain and settlements existed first, then roads grew through and around them.
- The chosen preview scale is the larger `360` grid used in the final comparison samples.
- City roads should show hierarchy. Urban trunk roads can be 3 cells wide, while smaller streets fill city blocks.
- City street layout should not be pure probability scatter. It should encode how cities historically grow around trade crossings, markets, parcel subdivision, and later extensions: a partially gridded core with enough noise and broken continuity to avoid looking mechanical.

## Options Explored

### A: Region-First / Biome-First

This path creates a coarse regional field before road generation. It uses value noise to form wilderness and plains/suburban regions, then samples 2-3 city anchors from high-suitability plains with random salt. Roads then grow with bias toward those regions.

Strengths observed:
- Better wilderness/suburb transitions.
- Cities read as part of a larger landform rather than rings around roads.
- The map is less distance-field-like.
- The final sample set had the strongest overall city/terrain composition.

### C: Settlement-Graph Emphasis

This path focused more on settlement graph structure and village placement. The villages felt natural and road/village distribution was strong, but the visual outcome converged surprisingly close to A after tuning.

Strengths observed:
- Villages and road branches felt organic.
- Good variation between samples.

Reason not selected:
- Compared with A, it retained less of the broad biome/suburb/wilderness transition that solved the original complaint.

## Selected Direction

The selected implementation is A: biome-first region generation with salted city anchors and road-driven civilization growth.

The canonical PCG phase order is now:

1. `RegionFieldGenerator`
2. `EvolvedSettlementGenerator`
3. `RoadRasterizer`
4. `CivilizationZoneGrower`
5. `ZoneSmoother`
6. `WaterSourcePlacer`
7. `CreatureSpawnerPlacer`
8. `PlantPlacer`
9. `POIGenerator`
10. `TileResolvePhase`
11. `TileDecidePhase`

The old `ZoneCalculator` road-distance BFS model is removed from the active pipeline and codebase. There is no compatibility shim or fallback path in the selected implementation.

## Implementation Notes

- `RegionFieldGenerator` fills the whole grid with biome-like zone data before roads exist.
- Each cell stores `city_suitability` and `plains_score` in `PCGCell.data` for later phases.
- City anchors are sampled from local plains support and suitability, with random salt to avoid deterministic-looking placement.
- Initial city regions are painted as irregular blobs, bounded to the configured grid.
- `PCGContext` now carries `region_anchor`, `has_region_anchor`, and `urban_anchors` so road generation can respond to the preselected city field.
- `EvolvedSettlementGenerator` uses the primary region anchor as its core and adds smaller town grids for secondary anchors.
- Road path scoring now prefers urban/suburban regions and mildly resists wilderness, without forbidding wilderness roads.
- Urban road evolution now creates a narrow street skeleton first, then reinforces road width from network evidence: segment length, endpoint connectivity, city coverage, collinear continuity, and arterial role.
- 3-cell boulevards are the result of this hierarchy pass, not roads that are born wide. Trade and connector arterials are now guaranteed to become continuous main roads; local city streets only reach boulevard width if length, connectivity, and city support justify it. This prevents short interior streets from visually outranking the trunk network.
- Length has the highest base weight in hierarchy scoring. City-center density and core pull are deliberately secondary so urban proximity cannot make a short dead-end look more important than a long route.
- Wider roads also increase later branch probability, while nearby junctions suppress redundant branch creation.
- A follow-up correction moved road width from shared graph nodes to road edges. Wide boulevards no longer leak into connected cross-region roads through shared intersections.
- Wide boulevards are clipped against the prepainted urban field, so the 3-cell treatment belongs to the city interior rather than reading as a highway crossing multiple biomes.
- A later geometry hygiene pass was added after visual review. It snaps dangling road ends into nearby roads, adds intentional short orthogonal connectors for near-offset roads, and prunes tiny or fully overlapped dead-end stubs. This prevents roads that almost meet but miss by one or two cells, and removes one-off fragments beside trunk roads.
- `CivilizationZoneGrower` applies post-road settlement pressure so roads can organically convert nearby plains/wilderness into urban/suburban land.
- `PCGConfig.grid_size` now defaults to `360`, matching the selected preview scale.

## City Road Growth Philosophy

The selected model treats city roads as layered history:

- Trade routes and city anchors establish the reason for a city to exist.
- A market or crossing forms the first civic core.
- Wider boulevards emerge where traffic, commerce, and procession concentrate inside the urban district. In implementation terms, a road begins narrow and is upgraded only if the road graph gives it enough evidence of importance.
- Smaller streets subdivide land into blocks, because repeated access to parcels naturally encourages a loose grid.
- Streets sometimes stop, shift, widen, or extend beyond the core because real cities inherit terrain, ownership boundaries, older paths, and later expansion.

This is why the implementation uses a structured grid skeleton but lets spacing, omissions, branch extensions, and occasional wider local axes vary by seed.

## Visual Samples

The selected sample group was generated with seeds `13579`, `24680`, `35791`, and `46802`:

`/Users/dluck/Documents/GitHub/gol/.debug/pcg-prototypes/more-biome-salt-city-360-four-panel.png`

The later road-hierarchy correction sample is:

`/Users/dluck/Documents/GitHub/gol/.debug/pcg-prototypes/long-trunk-priority-360-four-panel.png`

The road-geometry hygiene correction sample is:

`/Users/dluck/Documents/GitHub/gol/.debug/pcg-prototypes/geometry-healed-roads-360-four-panel.png`

The rejected comparison group remains available for reference:

`/Users/dluck/Documents/GitHub/gol/.debug/pcg-prototypes/more-settlement-graph-360-four-panel.png`

## Follow-Up Watch Points

- Full tile resolution on a 360 grid is heavier than the old default; if runtime generation becomes too slow, optimize tile resolution rather than shrinking the map back.
- The selected algorithm intentionally removes road-distance zoning, so future tuning should adjust biome suitability, city-anchor sampling, road bias, and civilization pressure instead of reintroducing distance bands.
- Village naturalness from C was strong. If A later feels too city-heavy, borrow C-style village weighting without changing the biome-first phase order.
