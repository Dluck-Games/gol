class_name CCampfire
extends Component
## 营火组件 - 存储营火的配置数据
##
## 此组件仅存储数据，实际渲染由 SCampfireRender 系统处理


## 火焰强度 (影响光照亮度和粒子效果)
var fire_intensity: float = 1.5

## 火焰高度 (预留参数)
var flame_height: float = 50.0

## 是否启用闪烁效果
var enable_flicker: bool = true

## 闪烁速度
var flicker_speed: float = 12.0
