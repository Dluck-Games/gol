class_name GoapAction_MarchToCampfire
extends GoapAction

## 朝营火行军: 替代 Wander，让僵尸在没有威胁时朝营火方向移动

func _init() -> void:
	action_name = "MarchToCampfire"
	cost = 10.0
	preconditions = {}
	effects = {
		"reached_campfire": true
	}


func perform(agent_entity: Entity, agent_component: CGoapAgent, _delta: float, _context: Dictionary) -> bool:
	var transform := agent_entity.get_component(CTransform)
	var movement := agent_entity.get_component(CMovement)
	if transform == null or movement == null:
		return true
	
	# 如果发现敌人，停止行军，让 ClearThreat 接管
	var perception := agent_entity.get_component(CPerception)
	var target_entity: Entity = perception.nearest_enemy if perception else null
	
	if target_entity != null:
		_store_target(agent_component, target_entity)
		movement.velocity = Vector2.ZERO
		return true
	
	_clear_target(agent_component)
	
	# 寻找营火并朝它移动
	var campfire := _find_campfire()
	if campfire == null:
		movement.velocity = Vector2.ZERO
		return false
	
	var campfire_transform := campfire.get_component(CTransform) as CTransform
	if campfire_transform == null:
		movement.velocity = Vector2.ZERO
		return false
	
	var direction: Vector2 = campfire_transform.position - transform.position
	if direction.length() < 32.0:
		# 到达营火附近，停下
		movement.velocity = Vector2.ZERO
		return false
	
	# 以游荡速度朝营火移动
	movement.velocity = direction.normalized() * movement.get_wander_speed()
	return false


func _find_campfire() -> Entity:
	var campfires := ECS.world.query.with_all([CCampfire, CTransform]).execute()
	for campfire in campfires:
		if not campfire.has_component(CDead):
			return campfire
	return null


func _store_target(agent_component: CGoapAgent, target_entity: Entity) -> void:
	agent_component.blackboard["threat_entity"] = weakref(target_entity)


func _clear_target(agent_component: CGoapAgent) -> void:
	agent_component.blackboard.erase("threat_entity")
