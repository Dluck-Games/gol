# GOL.gd - Global Game Manager & Entry Point
# This autoload provides centralized access to game state and manages game initialization
extends Node

## Game state instance - manages gameplay data like respawn & fail conditions
## Implementation: GOLGameState class in scripts/gameplay/gol_game_state.gd
var Game: GOLGameState = null


# ============================================================================
# LIFECYCLE
# ============================================================================

func setup() -> void:
	ServiceContext.static_setup(get_tree().get_root())
	Game = GOLGameState.new()

func teardown() -> void:
	ServiceContext.static_teardown()
	Game.free()
	Game = null

func start_game() -> void:
	var config := PCGConfig.new()
	config.pcg_seed = randi()
	var result := ServiceContext.pcg().generate(config)
	if result == null or not result.is_valid():
		push_error("PCG generation failed - aborting game start")
		return

	# Cache campfire position from nearest VILLAGE POI to grid center
	Game.campfire_position = ServiceContext.pcg().find_nearest_village_poi()

	ServiceContext.scene().switch_scene("procedural")
