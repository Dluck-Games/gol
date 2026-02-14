class_name SDaynightCycle
extends System

func _ready() -> void:
	group = "gameplay"


func query() -> QueryBuilder:
	return q.with_all([CDayNightCycle])


func process(entity: Entity, delta: float) -> void:
	var c_daynight_cycle = entity.get_component(CDayNightCycle)
	
	if not c_daynight_cycle:
		return
		
	var current_time : float = c_daynight_cycle.current_time
	var speed_of_time : float = c_daynight_cycle.speed_of_time
	var duration : float = c_daynight_cycle.duration
	
	current_time += speed_of_time * delta
	
	if current_time >= duration:
		current_time -= duration
		
	c_daynight_cycle.current_time = current_time
