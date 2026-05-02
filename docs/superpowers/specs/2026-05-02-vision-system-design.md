# Vision System Design (v0.3)

> Date: 2026-05-02
> Status: Draft
> Scope: Player & NPC field-of-view with building occlusion, map darkening, entity fade-out
> Reference: Project Zomboid vision model — perception logic drives visual presentation

## Overview

The vision system adds directional field-of-view (cone-shaped) to GOL. Players and NPCs share the same perception logic; the visual layer (map darkening, entity show/hide) is a rendering projection of that logic data, applied only to the player's screen.

Design philosophy (borrowed from Project Zomboid): **perception IS vision**. The visual effect on screen is a direct read of the perception system's output. NPC/enemies run identical perception logic but have no visual rendering. This means a single logic layer (SPerception) serves both AI decision-making and player viewport.

### Design Principles

- **Perception-driven**: All vision parameters live in the perception layer. The renderer has zero gameplay state.
- **Modality split**: Perception components split by sensory modality (CVision for sight, CHearing for sound in future). CPerception becomes a thin aggregator.
- **ECS-native**: Pure data components, system-driven logic, standard query patterns.
- **Performance by design**: Avoid O(N²) patterns; use per-frame caches, LOD throttling, AABB simplification.

## Architecture

```
SPerception (gameplay group) ─── Logic Layer
│
├── Queries: q.with_all([CPerception, CTransform])
├── Per-entity:
│   ├── Has CVision? → cone + AABB occlusion detection
│   ├── Has CHearing? → (future) circular audio detection
│   └── CPerception aggregates modality outputs → GOAP facts
├── Per-frame caches:
│   ├── _pos_cache (existing, all entities)
│   └── _building_cache (new, CBuilding + CTransform entities)
└── Player-only: compute _visible_polygon (ray-cast fan)

SVisionRenderer (render group) ─── Visual Layer
│
├── Queries: q.with_all([CVision, CPlayer, CTransform])
├── Reads player CVision._visible_polygon → shader uniform
├── Shader: darkens area outside polygon (soft edge, terrain visible)
├── Entity show/hide: reads CVision._visible_entity_set (O(1) lookup)
└── Fade-out timer management for entities leaving vision
```

## Component Design

### CVision (new — migrated from CPerception)

```gdscript
class_name CVision
extends Component

# --- Migrated from CPerception ---
@export var vision_range: float = 600.0
var base_vision_range: float = -1.0
@export var night_vision_multiplier: float = 1.25

# --- New: cone vision ---
## Field of view angle in degrees. 360 = omnidirectional (backward compat).
@export var fov_angle: float = 360.0
## Facing direction (unit vector). Updated by SPerception each scan.
var facing_direction: Vector2 = Vector2.RIGHT

# --- Visible entity storage (migrated from CPerception) ---
var _visible_entities: Array[Entity] = []
var _visible_entity_set: Dictionary = {}  # {Entity: true} for O(1) lookup
var _nearest_enemy: Entity = null
var _visible_friendlies: Array[Entity] = []

# --- Player-only rendering data ---
## Visible area polygon (computed only for player entity).
var _visible_polygon: PackedVector2Array = PackedVector2Array()

# --- Fade-out ---
## Duration before entity disappears after leaving vision (seconds).
@export var fade_out_duration: float = 1.5
## Entities currently fading out: {Entity: remaining_time_seconds}
var _fade_out_entities: Dictionary = {}

# --- Accessors (same API as old CPerception) ---
var visible_entities: Array[Entity]:
    get = get_visible_entities

var nearest_enemy: Entity:
    get:
        if not _is_valid(_nearest_enemy):
            _nearest_enemy = null
        return _nearest_enemy
    set(value):
        _nearest_enemy = value if _is_valid(value) else null

func get_visible_entities() -> Array[Entity]:
    var filtered: Array[Entity] = []
    filtered.assign(_visible_entities.filter(_is_valid))
    return filtered

func get_visible_friendlies() -> Array[Entity]:
    var filtered: Array[Entity] = []
    filtered.assign(_visible_friendlies.filter(_is_valid))
    return filtered

func is_in_vision(entity: Entity) -> bool:
    return _visible_entity_set.has(entity)

func _is_valid(entity) -> bool:
    return is_instance_valid(entity) and entity is Entity and not entity.is_queued_for_deletion()
```

### CPerception (slimmed — aggregator role)

```gdscript
class_name CPerception
extends Component

## Scan throttle interval (seconds).
@export var update_interval: float = 0.15
## Internal timer (staggered on init).
var _update_timer: float = 0.0
## Owner entity reference.
var owner_entity: Entity = null

func _init() -> void:
    _update_timer = update_interval
```

CPerception no longer stores visible entity lists, vision range, or enemy references. It retains scan timing and serves as a marker for "this entity has perception". All sensory data lives in modality components (CVision, future CHearing).

### Migration: explicit consumer updates

All consumers that previously read `CPerception.visible_entities`, `CPerception.nearest_enemy`, etc. must be updated to read from `CVision`. Affected files:

- `s_perception.gd` — writes to CVision instead of CPerception
- `s_presence_penalty.gd` — reads/writes `vision_range` from CVision
- All GOAP steps/templates that read `perception.nearest_enemy` or `perception.visible_entities`
- `s_goal_decision.gd` or equivalent GOAP fact mirroring

No transparent getters. Clean break.

### GOAP fact mirroring (post-refactor)

GOAP fact updates (`has_threat`, `is_safe`, `has_visible_food`, `has_food_stockpile`, `has_resource`) remain in SPerception but now read from CVision:

```gdscript
var vision := entity.get_component(CVision) as CVision
var agent := entity.get_component(CGoapAgent) as CGoapAgent
if agent == null or vision == null:
    return

var has_threat: bool = vision.nearest_enemy != null
agent.world_state.update_fact("has_threat", has_threat)
agent.world_state.update_fact("is_safe", not has_threat)
# ... food/resource facts likewise read from vision.visible_entities
```

No separate aggregation step needed. CPerception's role is scan timing only.

## Detection Logic (SPerception upgrades)

### Facing direction source

| Entity type | facing_direction source |
|---|---|
| Player | `CAim.direction` (mouse/crosshair aim) |
| Moving NPC/enemy | `CMove.velocity.normalized()` (falls back to last non-zero direction) |
| Idle NPC | Retains last facing direction |

SPerception updates `CVision.facing_direction` each scan cycle before running detection.

### Cone detection

For each candidate in `_pos_cache` that passes distance check:

```
offset = candidate_pos - scanner_pos
angle_diff = abs(facing_direction.angle_to(offset.normalized()))
if angle_diff <= deg_to_rad(fov_angle / 2.0):
    → candidate passes cone check
```

When `fov_angle >= 360.0`, skip cone check entirely (backward compatibility fast path).

### Building occlusion (AABB line-segment intersection)

**No physics engine dependency.** Pure math approach:

Per-frame `_building_cache` (rebuilt once like `_pos_cache`):

```gdscript
_building_cache: Array[Dictionary]
# entry = {pos: Vector2, half_size: Vector2}
# Built from: q.with_all([CBuilding, CTransform])
# half_size source: CBuilding.occlusion_half_size (new Vector2 field, configured per
# building type in EntityRecipe). Defaults to (32, 16) — one isometric tile.
# Not derived at runtime from sprites to avoid texture-size coupling.
```

For each candidate that passes distance + cone check, test if the line segment (scanner_pos → candidate_pos) intersects any building AABB:

```
for building in _building_cache:
    if line_segment_intersects_aabb(scanner_pos, candidate_pos, building.pos, building.half_size):
        → candidate is occluded, skip
        break
```

`line_segment_intersects_aabb` is a standard slab method: 4-6 float comparisons per building. With distance pre-filter (skip buildings far from line midpoint), actual tests are minimal.

**Pixel art fidelity note:** Buildings are simplified to axis-aligned bounding boxes matching approximate sprite size. No precise collision shapes needed — this is a pixel game, and approximate occlusion is sufficient.

### Candidate pipeline summary

```
_pos_cache (all entities, O(N) per frame)
    → Distance filter: dist_sq <= vision_range²
    → Cone filter: angle_diff <= fov_angle / 2
    → AABB occlusion filter: line-segment vs building AABBs
    → Survivors → CVision._visible_entities + _visible_entity_set
```

### Player visible polygon (ray-fan)

Computed only for the player entity, once per scan cycle:

1. Compute cone boundaries: `facing_direction ± fov_angle / 2`
2. Cast N rays (N ≈ 48) evenly spaced within the cone
3. Each ray: walk from player_pos outward to vision_range, test AABB intersection with each building
4. Hit → record intersection point. Miss → record vision_range endpoint.
5. All points + player_pos → `_visible_polygon` (PackedVector2Array)

48 rays × ~10-30 buildings = ~500-1500 AABB tests. Microsecond-level pure math.

## SVisionRenderer (new system)

### System setup

```gdscript
class_name SVisionRenderer
extends System

func _ready() -> void:
    group = "render"

func query() -> QueryBuilder:
    return q.with_all([CVision, CPlayer, CTransform])
```

### Map darkening shader

Follows SDaynightLighting architecture pattern: CanvasLayer + ColorRect + ShaderMaterial.

Shader uniforms:
- `polygon_vertices: vec2[]` — visible area polygon in **screen coordinates** (up to 64 vertices)
- `vertex_count: int` — actual vertex count
- `player_screen_pos: vec2` — player position in screen coords
- `edge_softness: float` — gradient width at vision boundary (in pixels)

**Coordinate conversion:** SVisionRenderer transforms `_visible_polygon` (world coords from SPerception) to screen coords using `viewport.get_canvas_transform()` before passing to shader — same pattern as SDaynightLighting's campfire light positions.

Shader logic per pixel:
1. Point-in-polygon test (ray crossing / winding number)
2. Inside polygon → fully visible (alpha = 0)
3. Within edge_softness distance of polygon boundary → gradient
4. Outside polygon → darkened (alpha ≈ 0.6-0.7, terrain silhouette visible)

CanvasLayer ordering: above game content, separate from SDaynightLighting layer. Both layers composite naturally — night makes everything darker, vision cone carves a bright area within that.

### Entity visibility control

Each frame, SVisionRenderer processes all entities with CSprite + CTransform:

```
player_vision = player.get_component(CVision)

for entity in all_sprite_entities:
    if entity is player → skip (always visible)

    if player_vision.is_in_vision(entity):  # O(1) Dictionary lookup
        entity.sprite.visible = true
        entity.sprite.modulate.a = 1.0
        # Remove from fade-out if re-entered vision
        player_vision._fade_out_entities.erase(entity)

    elif player_vision._fade_out_entities.has(entity):
        remaining = player_vision._fade_out_entities[entity]
        remaining -= delta
        if remaining <= 0:
            entity.sprite.visible = false
            player_vision._fade_out_entities.erase(entity)
        else:
            entity.sprite.modulate.a = remaining / player_vision.fade_out_duration
            player_vision._fade_out_entities[entity] = remaining

    else:
        # Just left vision this frame — start fade-out
        if entity.sprite.visible:
            player_vision._fade_out_entities[entity] = player_vision.fade_out_duration
        else:
            entity.sprite.visible = false
```

### Exclusions

- Player entity: always visible
- UI elements: on separate CanvasLayer, unaffected
- Particle effects / VFX: follow parent entity visibility

## Performance Design

### Identified risks and mitigations

| Concern | Worst case | Mitigation | Final cost |
|---|---|---|---|
| Cone angle computation | 200 candidates × atan2 | Only after distance filter; skip if fov=360 | ~50-100 atan2/frame |
| Building occlusion | 400 candidates × 30 buildings | AABB slab method (4-6 floats each); distance pre-filter on buildings | ~2000-5000 float ops/frame |
| Visible polygon rays | 48 rays × 30 buildings | Player only, once per scan; same AABB method | ~1500 float ops/frame |
| Entity visibility lookup | 200 sprite entities × set lookup | `_visible_entity_set` Dictionary: O(1) per lookup | 200 hash lookups/frame |
| Shader polygon test | 2M pixels × 48 vertices | GPU fragment shader; trivially parallel | Negligible |
| Cache rebuilds | _pos_cache + _building_cache | Once per frame, O(N entities + M buildings) | Same as current |

### LOD integration

Existing SPerception LOD tiers (near/mid/far update intervals) apply to cone + occlusion detection identically. Far entities scan less frequently, reducing all per-entity costs proportionally.

### Backward compatibility

Entities with `CVision.fov_angle = 360.0` (default) skip cone check entirely. AABB occlusion still applies (buildings block omnidirectional vision too). This means existing NPC configurations work without changes — they just gain building occlusion awareness.

## Configuration

### Player defaults

| Parameter | Value | Rationale |
|---|---|---|
| fov_angle | 120° | PZ-style forward cone |
| vision_range | 600.0 | Existing default |
| fade_out_duration | 1.5s | Smooth but not lingering |
| Shader edge_softness | ~30-50px | Soft gradient at vision boundary |
| Shader darkness_alpha | 0.65 | Dark but terrain silhouette visible |
| Polygon ray count | 48 | Balance between shape fidelity and cost |

### Enemy defaults

| Parameter | Value | Rationale |
|---|---|---|
| fov_angle | 360° | Backward compat; reconfigure per enemy type later |
| vision_range | 600.0 (+ presence penalty scaling) | Existing behavior preserved |

## Scope boundaries (v0.3)

### In scope
- CVision component + CPerception slim-down + explicit consumer migration
- SPerception upgrade: cone detection + AABB building occlusion
- Player visible polygon computation
- SVisionRenderer: map darkening shader + entity show/hide + fade-out
- Building collision layer setup for occlusion

### Out of scope (future versions)
- Explored / unexplored tile memory (persistent FoW map)
- CHearing (auditory perception modality)
- Non-building occluders (trees, vehicles, terrain features)
- Minimap fog synchronization
- Multiplayer vision sharing

## Implementation: single PR

All changes ship as one PR. Internal ordering:

1. Create CVision component with all fields
2. Slim CPerception to aggregator
3. Migrate all consumers (GOAP steps, behavior templates, SPresencePenalty) from CPerception → CVision
4. Add fov_angle + facing_direction fields to CVision; SPerception cone logic
5. Add _building_cache + AABB occlusion to SPerception
6. Add _visible_polygon computation (player only)
7. Create SVisionRenderer system (shader + entity visibility)
8. EntityRecipe updates: add CVision to all entities that had CPerception
9. Building collision layer configuration
10. Config defaults and tuning
