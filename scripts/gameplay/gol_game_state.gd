# GOLGameState - Game State Management
# Handles gameplay logic: player respawn, campfire destruction, and game-over conditions
class_name GOLGameState
extends Object

var is_game_over := false

## Cached campfire world position from PCG VILLAGE POI
## Set by GOL.start_game() after PCG generation
var campfire_position := Vector2(500, 500)


## Handle player knocked down - triggers respawn logic
func handle_player_down() -> void:
	if is_game_over:
		return
	_respawn_player()


## Handle campfire destroyed - triggers game over
func handle_campfire_destroyed() -> void:
	if is_game_over:
		return
	is_game_over = true
	_lock_player_controls_on_game_over()
	_show_game_over_view()


## Reset game state for new game or restart
func reset() -> void:
	is_game_over = false


## Respawn player - create new player entity at campfire position
func _respawn_player() -> void:
	campfire_position = _find_campfire_position()
	
	# Create new player entity
	var new_player: Entity = ServiceContext.recipe().create_entity_by_id("player")
	if not new_player:
		push_error("[Respawn] Failed to create new player entity")
		return
	
	# Set position to campfire
	var transform: CTransform = new_player.get_component(CTransform)
	if transform:
		transform.position = campfire_position
	
	# Grant brief invincibility
	var hp: CHP = new_player.get_component(CHP)
	if hp:
		hp.invincible_time = 1.5
	
	# Add to world
	ECS.world.add_entity(new_player)
	print("[Respawn] New player spawned at campfire: ", campfire_position)


## Find campfire entity position for respawn
## Falls back to cached campfire_position if no live campfire entity exists
func _find_campfire_position() -> Vector2:
	const COMPONENT_CAMPFIRE := preload("res://scripts/components/c_campfire.gd")
	for entity in ECS.world.query.with_all([COMPONENT_CAMPFIRE, CTransform]).execute():
		var transform: CTransform = entity.get_component(CTransform)
		if transform:
			return transform.position
	return campfire_position


## Show game over UI view
func _show_game_over_view() -> void:
	var game_over_view: PackedScene = load("res://scenes/ui/menus/game_over.tscn")
	ServiceContext.ui().create_and_push_view(Service_UI.LayerType.HUD, game_over_view)


## Lock all player entity controls when game ends
func _lock_player_controls_on_game_over() -> void:
	if not ECS or not ECS.world:
		return
	
	for entity in ECS.world.query.with_all([CCamp, CPlayer]).execute():
		var pawn: CCamp = entity.get_component(CCamp)
		if not pawn or pawn.camp != CCamp.CampType.PLAYER:
			continue
		
		var player: CPlayer = entity.get_component(CPlayer)
		if player:
			player.is_enabled = false
		
		var movement: CMovement = entity.get_component(CMovement)
		if movement:
			movement.velocity = Vector2.ZERO
			movement.forbidden_move = true
