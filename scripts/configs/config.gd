class_name Config

# Player and Enemy default speeds - used for initialization only
const INIT_PLAYER_SPEED: float = 140.0
const INIT_ENEMY_SPEED: float = INIT_PLAYER_SPEED - 40.0

# ========================================
# GOAP Actions Configuration
# ========================================

## Time Intervals
const GOAP_PATROL_INTERVAL: float = 3.0
const GOAP_WANDER_INTERVAL: float = 5.0

## Distance Thresholds - Patrol & Wander
const GOAP_PATROL_RADIUS: float = 128.0
const GOAP_WANDER_RADIUS: float = 64.0
const GOAP_MAX_DISTANCE_FROM_CAMP: float = 200.0

## 基础组件列表 - 实体的核心组件
static var BASE_COMPONENTS: Array = [
	CTransform, CSprite, CCollision, CPlayer,
	CCamp, CHP, CLifeTime,
	CMovement, CPickup, CCamera,
	CGoapAgent, CAnimation,
	CGuard, CPerception, CSemanticTranslation,
	CMelee, CAim, CDamage
]

## 死亡时移除的干扰组件 - 这些组件会干扰死亡动画流程
static var DEATH_REMOVE_COMPONENTS: Array = [
	CAnimation,
	CCollision,
	CGoapAgent,
	CPerception,
	CWeapon,
	CHP,
	CMelee,
	CTracker,
	CAim,
]
