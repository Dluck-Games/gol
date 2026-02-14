class_name CPlayer
extends Component

## 玩家标记组件
## 
## 用于标识一个实体是玩家控制的实体。
## 可用于：
## - 区分玩家实体与 AI 实体
## - 控制是否接受玩家输入
## - 查找玩家实体
## 
## 使用方式:
##   # 检查实体是否是玩家
##   if entity.has_component(CPlayer):
##       # 是玩家实体
##       pass
##   
##   # 检查玩家输入是否启用
##   var player: CPlayer = entity.get_component(CPlayer)
##   if player and player.is_enabled:
##       var move_dir := ServiceContext.input().get_move_direction()

## 输入是否启用 (可用于暂停、死亡、过场动画等状态)
var is_enabled: bool = true
