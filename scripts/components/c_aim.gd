class_name CAim
extends Component

## 瞄准方向组件 - 标记角色的瞄准目标位置
##
## 该组件用于标识实体当前的瞄准位置（屏幕坐标）。
## 玩家：由 SCrosshair 系统根据鼠标位置更新
## AI：由 STrackLocation 系统根据追踪目标更新

## 瞄准位置（屏幕坐标）
var aim_position: Vector2 = Vector2.ZERO:
	set(v):
		aim_position = v
		aim_position_observable.set_value(v)
var aim_position_observable: ObservableProperty = ObservableProperty.new(aim_position)
