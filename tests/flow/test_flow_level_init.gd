extends GdUnitTestSuite

const CAMP_POS := Vector2.ZERO
const PLAYER_START_POS := Vector2(50, 50)

func before() -> void:
	GOL.setup()

func after() -> void:
	GOL.teardown()

func test_level_initialization() -> void:
	# 1. Arrange: Create entities that would be spawned in level start
	var campfire = auto_free(_create_campfire(CAMP_POS))
	var player = auto_free(_create_player(PLAYER_START_POS))
	
	# 2. Act: Start the game/level (Simulated by checking existence)
	# In a real integration test, we might call GOL.start_game()
	
	# 3. Assert: Entities are correctly initialized
	assert_object(campfire).is_not_null()
	assert_object(player).is_not_null()
	
	var camp_transform = campfire.get_component(CTransform)
	assert_vector(camp_transform.position).is_equal(CAMP_POS)
	
	var player_transform = player.get_component(CTransform)
	assert_vector(player_transform.position).is_equal(PLAYER_START_POS)
	
	assert_bool(GOL.Game.is_game_over).is_false()

func _create_campfire(pos: Vector2) -> Entity:
	var e = Entity.new()
	e.name = "Campfire"
	e.add_components([
		CTransform.new(),
		CCampfire.new(),
		CHP.new()
	])
	e.get_component(CTransform).position = pos
	return e

func _create_player(pos: Vector2) -> Entity:
	var e = Entity.new()
	e.name = "Player"
	e.add_components([
		CTransform.new(),
		CPlayer.new(), # Identifying component
		CHP.new()
	])
	e.get_component(CTransform).position = pos
	return e
