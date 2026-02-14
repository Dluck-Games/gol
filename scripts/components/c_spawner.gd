class_name CSpawner
extends Component

## 刷怪激活条件
enum ActiveCondition {
	ALWAYS,      ## 始终激活
	DAY_ONLY,    ## 仅白天
	NIGHT_ONLY   ## 仅夜晚
}

## Recipe ID for spawning
@export var spawn_recipe_id: String = ""

## 刷怪间隔 (秒)
@export var spawn_interval: float = 4.0
@export var spawn_interval_variance: float = 0.5

## 每次刷怪数量
@export var spawn_count: int = 1

## 刷怪半径 (距离刷怪器中心)
@export var spawn_radius: float = 0.0

## 最大存活数量限制 (0 = 不限制)
@export var max_spawn_count: int = 10

## 激活条件
@export var active_condition: ActiveCondition = ActiveCondition.ALWAYS

## 运行时状态
var spawn_timer: float = 0.0
var spawned: Array[Entity] = []

## 条件激活状态 (用于条件切换时立即刷一波)
var condition_activated: bool = false

## Enrage state (activated after damage, faster spawning)
var enraged: bool = false

## Spawn interval when enraged (seconds)
@export var enraged_spawn_interval: float = 2.0
