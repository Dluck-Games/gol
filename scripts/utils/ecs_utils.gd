class_name ECSUtils


static func is_base_component(comp: Component) -> bool:
	return comp.get_script() in Config.BASE_COMPONENTS

static func remove_entity(entity: Entity) -> void:
	if ECS.world:
		ECS.world.remove_entity(entity)
	else:
		push_error("ECS World is not initialized.")


## 获取昼夜循环组件 (单例)
static func get_day_night_cycle() -> CDayNightCycle:
	var entities := ECS.world.query.with_all([CDayNightCycle]).execute()
	if entities.is_empty():
		return null
	return entities[0].get_component(CDayNightCycle)


## 判断当前是否为夜晚
static func is_night() -> bool:
	var tod := get_day_night_cycle()
	if not tod:
		return false
	var half_night := tod.night_weight / 2.0
	var night_end := half_night
	var night_start := tod.duration - half_night
	return tod.current_time < night_end or tod.current_time >= night_start


## 判断实体是否为敌方
static func is_enemy(entity: Entity) -> bool:
	var camp := entity.get_component(CCamp) as CCamp
	return camp and camp.camp == CCamp.CampType.ENEMY