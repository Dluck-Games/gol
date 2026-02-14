class_name CPerception
extends Component

## Perception component: stores visible entities within vision range
## Data-driven: logic handled by perception system and consumers

## Vision range - how far this entity can see
@export var vision_range: float = 600.0

## 夜间视野倍率 (仅对敌方生效)
@export var night_vision_multiplier: float = 1.25

## Internal storage for visible entities (updated by perception system)
var _visible_entities: Array[Entity] = []

## Reference to the owner entity (set by perception system)
var owner_entity: Entity = null

## Cached nearest enemy (updated by perception system)
var nearest_enemy: Entity = null

## Cached friendly entities (updated by perception system)
var _visible_friendlies: Array[Entity] = []

## Get all valid visible entities (auto-filters freed instances)
var visible_entities: Array[Entity]:
	get = get_visible_entities


func get_visible_entities() -> Array[Entity]:
	return _visible_entities.filter(_is_valid)


## Get all valid visible friendly entities
func get_visible_friendlies() -> Array[Entity]:
	return _visible_friendlies.filter(_is_valid)


## Check if a specific entity is a visible friendly
func is_visible_friendly(entity: Entity) -> bool:
	if not _is_valid(entity):
		return false
	return entity in _visible_friendlies


func _is_valid(entity: Entity) -> bool:
	return is_instance_valid(entity) and not entity.is_queued_for_deletion()
