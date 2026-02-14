class_name CBullet
extends Component

enum BulletType {
	NORMAL,
	SNOWBALL
}

@export var type: BulletType = BulletType.NORMAL

# Runtime property: set by SFireBullet to prevent self-hit
var owner_entity: Entity = null
