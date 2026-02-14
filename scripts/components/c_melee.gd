class_name CMelee
extends Component

## Melee attack configuration component

## Attack detection radius
@export var attack_range: float = 24.0

## Distance at which AI considers melee ready
@export var ready_range: float = 20.0

## Damage per hit
@export var damage: float = 20.0

## Swing animation angle in degrees
@export var swing_angle: float = 20.0

## Swing animation duration in seconds
@export var swing_duration: float = 0.15

## Attack interval (cooldown between attacks)
@export var attack_interval: float = 1.0

## 夜间攻击速度倍率 (仅对敌方生效，倍率越高间隔越短)
@export var night_attack_speed_multiplier: float = 1.1

## Current cooldown remaining (managed by SMeleeAttack system)
var cooldown_remaining: float = 0.0

## Whether an attack is pending (prevents duplicate triggers)
var attack_pending: bool = false

## Attack direction for next attack (consumed by SMeleeAttack system)
var attack_direction: Vector2 = Vector2.ZERO
