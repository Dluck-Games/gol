class_name SEnemySpawn
extends System

## 多怪物同时刷新时的最小间距
const MIN_SPAWN_SPACING: float = 32.0

var _cached_tod: CDayNightCycle = null


func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CSpawner, CTransform])


func process(entity: Entity, delta: float) -> void:
	var spawner := entity.get_component(CSpawner) as CSpawner
	var transform := entity.get_component(CTransform) as CTransform
	
	_cleanup_invalid_entities(spawner)
	
	# 检查激活条件
	if not _check_active_condition(spawner):
		spawner.condition_activated = false
		spawner.spawn_timer = 0.0
		return
	
	# 条件刚满足时立即刷一波
	if not spawner.condition_activated:
		spawner.condition_activated = true
		_spawn_wave(spawner, transform)
		_reset_timer(spawner)
		return
	
	# 计时刷怪
	spawner.spawn_timer -= delta
	if spawner.spawn_timer > 0:
		return
	
	# 检查数量限制
	if spawner.max_spawn_count > 0 and spawner.spawned.size() >= spawner.max_spawn_count:
		return
	
	_spawn_wave(spawner, transform)
	_reset_timer(spawner)


func _spawn_wave(spawner: CSpawner, transform: CTransform) -> void:
	if spawner.spawn_recipe_id.is_empty():
		push_error("SEnemySpawn: No spawn recipe specified")
		return
	
	# 检查数量限制，计算本次可刷数量
	var count_to_spawn := spawner.spawn_count
	if spawner.max_spawn_count > 0:
		var remaining := spawner.max_spawn_count - spawner.spawned.size()
		count_to_spawn = mini(count_to_spawn, remaining)
	
	if count_to_spawn <= 0:
		return
	
	var center := transform.position
	
	for i in range(count_to_spawn):
		var new_entity := ServiceContext.recipe().create_entity_by_id(spawner.spawn_recipe_id)
		if not new_entity:
			push_error("SEnemySpawn: Failed to create entity")
			continue
		
		# 计算刷新位置
		var spawn_pos := _calculate_spawn_position(center, spawner.spawn_radius, i, count_to_spawn)
		
		var new_transform := new_entity.get_component(CTransform) as CTransform
		if new_transform:
			new_transform.position = spawn_pos
		
		spawner.spawned.append(new_entity)


## 计算刷新位置，多个怪物时均匀分布在圆周上
func _calculate_spawn_position(center: Vector2, radius: float, index: int, total: int) -> Vector2:
	if total <= 1:
		# 单个怪物，使用指定半径内随机位置
		if radius > 0:
			var angle := randf() * TAU
			var distance := randf_range(0, radius)
			return center + Vector2(cos(angle), sin(angle)) * distance
		return center
	
	# 多个怪物，均匀分布在圆周上
	var effective_radius := maxf(radius, MIN_SPAWN_SPACING)
	var angle := (float(index) / total) * TAU + randf_range(-0.2, 0.2)  # 添加少许随机偏移
	return center + Vector2(cos(angle), sin(angle)) * effective_radius


func _reset_timer(spawner: CSpawner) -> void:
	var variance := randf_range(-spawner.spawn_interval_variance, spawner.spawn_interval_variance)
	spawner.spawn_timer = spawner.spawn_interval + variance


func _check_active_condition(spawner: CSpawner) -> bool:
	match spawner.active_condition:
		CSpawner.ActiveCondition.ALWAYS:
			return true
		CSpawner.ActiveCondition.DAY_ONLY:
			return not _is_night()
		CSpawner.ActiveCondition.NIGHT_ONLY:
			return _is_night()
	return true


func _is_night() -> bool:
	var tod := _get_day_night_cycle()
	if not tod:
		return false
	var half_night := tod.night_weight / 2.0
	var night_end := half_night
	var night_start := tod.duration - half_night
	return tod.current_time < night_end or tod.current_time >= night_start


func _cleanup_invalid_entities(spawner: CSpawner) -> void:
	for i in range(spawner.spawned.size() - 1, -1, -1):
		var spawned_entity = spawner.spawned[i]
		if not is_instance_valid(spawned_entity):
			spawner.spawned.remove_at(i)


func _get_day_night_cycle() -> CDayNightCycle:
	if _cached_tod and is_instance_valid(_cached_tod):
		return _cached_tod
	
	var entities := ECS.world.query.with_all([CDayNightCycle]).execute()
	if entities.is_empty():
		return null
	_cached_tod = entities[0].get_component(CDayNightCycle)
	return _cached_tod
