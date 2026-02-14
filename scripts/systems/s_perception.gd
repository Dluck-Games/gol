class_name SPerception
extends System

## Perception System: pure visual sensing, no decision making
## Populates each entity's visible_entities, nearest_enemy, and visible_friendlies

func _ready() -> void:
	group = "gameplay"

func query() -> QueryBuilder:
	return q.with_all([CPerception, CTransform])

func process(entity: Entity, _delta: float) -> void:
	var perception := entity.get_component(CPerception) as CPerception
	var transform := entity.get_component(CTransform) as CTransform
	
	perception.owner_entity = entity
	perception._visible_entities.clear()
	perception._visible_friendlies.clear()
	perception.nearest_enemy = null
	
	# 计算有效视野 (敌方夜间增强)
	var effective_vision := perception.vision_range
	if ECSUtils.is_enemy(entity) and ECSUtils.is_night():
		effective_vision *= perception.night_vision_multiplier
	
	var vision_range_sq: float = effective_vision * effective_vision
	var my_camp := entity.get_component(CCamp) as CCamp
	var my_camp_type: CCamp.CampType = my_camp.camp if my_camp else CCamp.CampType.PLAYER
	var enemy_camp: CCamp.CampType = _get_enemy_camp(my_camp)
	
	var closest_enemy_dist_sq := INF
	
	var candidates := ECS.world.query.with_all([CTransform]).execute()
	for candidate in candidates:
		if candidate == entity:
			continue
		
		var candidate_transform := candidate.get_component(CTransform) as CTransform
		if candidate_transform == null:
			continue
		
		var offset: Vector2 = candidate_transform.position - transform.position
		var dist_sq := offset.length_squared()
		if dist_sq > vision_range_sq:
			continue
		
		perception._visible_entities.append(candidate)
		
		# Track friendlies (same camp, not dead)
		if _is_friendly(candidate, my_camp_type):
			perception._visible_friendlies.append(candidate)
		
		# Track nearest enemy
		if _is_enemy(candidate, enemy_camp) and dist_sq < closest_enemy_dist_sq:
			closest_enemy_dist_sq = dist_sq
			perception.nearest_enemy = candidate


func _get_enemy_camp(my_camp: CCamp) -> CCamp.CampType:
	if my_camp and my_camp.camp == CCamp.CampType.ENEMY:
		return CCamp.CampType.PLAYER
	return CCamp.CampType.ENEMY


func _is_enemy(candidate: Entity, enemy_camp: CCamp.CampType) -> bool:
	var camp := candidate.get_component(CCamp) as CCamp
	if not camp or camp.camp != enemy_camp:
		return false
	return not candidate.has_component(CDead)


func _is_friendly(candidate: Entity, my_camp_type: CCamp.CampType) -> bool:
	var camp := candidate.get_component(CCamp) as CCamp
	if not camp or camp.camp != my_camp_type:
		return false
	return not candidate.has_component(CDead)
