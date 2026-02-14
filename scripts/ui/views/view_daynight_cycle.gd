class_name View_Daynight_Cycle
extends ViewBase

## 昼夜循环视图 - 仅负责 UI 显示（如时钟）
## 光照效果已迁移到 SDaynightLighting 系统

# 昼夜循环组件
var day_night_cycle_comp: CDayNightCycle


func bind() -> void:
	var entities := ECS.world.query.with_all([CDayNightCycle]).execute()
	if entities.is_empty():
		return
	day_night_cycle_comp = entities[0].get_component(CDayNightCycle)


func teardown() -> void:
	day_night_cycle_comp = null
