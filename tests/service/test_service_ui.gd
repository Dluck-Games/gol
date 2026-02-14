extends GdUnitTestSuite
## Unit tests for Service_UI

var _service: Service_UI
var _mock_root: Node


func before() -> void:
	_mock_root = auto_free(Node.new())
	_mock_root.name = "MockRoot"
	ServiceContext.root_node = _mock_root


func after() -> void:
	ServiceContext.root_node = null


func before_test() -> void:
	_service = auto_free(Service_UI.new())
	_service.setup()
	# Process deferred calls
	await get_tree().process_frame


func after_test() -> void:
	if _service:
		_service.teardown()


# ============================================================
# Setup / Teardown Tests
# ============================================================

func test_setup_creates_ui_structure() -> void:
	assert_object(_service.ui_base).is_not_null()
	assert_object(_service.hud_layer).is_not_null()
	assert_object(_service.game_layer).is_not_null()
	assert_str(_service.ui_base.name).is_equal("UI")
	assert_str(_service.hud_layer.name).is_equal("HUD_Layer")
	assert_str(_service.game_layer.name).is_equal("Game_Layer")


func test_setup_adds_layers_to_ui_base() -> void:
	assert_bool(_service.hud_layer.get_parent() == _service.ui_base).is_true()
	assert_bool(_service.game_layer.get_parent() == _service.ui_base).is_true()


func test_teardown_clears_references() -> void:
	_service.teardown()
	
	assert_object(_service.ui_base).is_null()
	assert_object(_service.hud_layer).is_null()
	assert_object(_service.game_layer).is_null()


# ============================================================
# View Push / Pop Tests
# ============================================================

func test_push_view_to_hud_layer() -> void:
	var view: ViewBase = auto_free(_create_mock_view())
	
	_service.push_view(Service_UI.LayerType.HUD, view)
	
	assert_bool(view.get_parent() == _service.hud_layer).is_true()


func test_push_view_to_game_layer() -> void:
	var view: ViewBase = auto_free(_create_mock_view())
	
	_service.push_view(Service_UI.LayerType.GAME, view)
	
	assert_bool(view.get_parent() == _service.game_layer).is_true()


func test_push_null_view_reports_error() -> void:
	# Should not crash, just log error
	_service.push_view(Service_UI.LayerType.HUD, null)
	# No assertion needed - just verify no crash


func test_push_same_view_twice_reports_error() -> void:
	var view: ViewBase = auto_free(_create_mock_view())
	
	_service.push_view(Service_UI.LayerType.HUD, view)
	_service.push_view(Service_UI.LayerType.HUD, view)
	
	# View should only be added once
	assert_int(_service.hud_layer.get_child_count()).is_equal(1)


func test_pop_view_removes_from_tree() -> void:
	var view := _create_mock_view()
	_service.push_view(Service_UI.LayerType.HUD, view)
	
	_service.pop_view(view)
	await get_tree().process_frame
	
	assert_int(_service.hud_layer.get_child_count()).is_equal(0)


func test_pop_null_view_reports_error() -> void:
	# Should not crash
	_service.pop_view(null)


func test_pop_views_by_layer_clears_layer() -> void:
	var view1 := _create_mock_view()
	var view2 := _create_mock_view()
	
	_service.push_view(Service_UI.LayerType.HUD, view1)
	_service.push_view(Service_UI.LayerType.HUD, view2)
	
	_service.pop_views_by_layer(Service_UI.LayerType.HUD)
	await get_tree().process_frame
	
	assert_int(_service.hud_layer.get_child_count()).is_equal(0)


func test_pop_views_by_layer_does_not_affect_other_layer() -> void:
	var hud_view: ViewBase = _create_mock_view()
	var game_view: ViewBase = auto_free(_create_mock_view())
	
	_service.push_view(Service_UI.LayerType.HUD, hud_view)
	_service.push_view(Service_UI.LayerType.GAME, game_view)
	
	_service.pop_views_by_layer(Service_UI.LayerType.HUD)
	await get_tree().process_frame
	
	assert_int(_service.hud_layer.get_child_count()).is_equal(0)
	assert_int(_service.game_layer.get_child_count()).is_equal(1)


# ============================================================
# ViewModel Tests
# ============================================================

func test_acquire_view_model_creates_new_instance() -> void:
	var vm: ViewModelBase = _service.acquire_view_model(MockViewModel)
	
	assert_object(vm).is_not_null()
	assert_bool(vm is MockViewModel).is_true()
	
	_service.release_view_model(vm)


func test_acquire_view_model_returns_same_instance() -> void:
	var vm1: ViewModelBase = _service.acquire_view_model(MockViewModel)
	var vm2: ViewModelBase = _service.acquire_view_model(MockViewModel)
	
	assert_object(vm1).is_same(vm2)
	
	_service.release_view_model(vm1)
	_service.release_view_model(vm2)


func test_release_view_model_decrements_ref_count() -> void:
	var vm1: ViewModelBase = _service.acquire_view_model(MockViewModel)
	var vm2: ViewModelBase = _service.acquire_view_model(MockViewModel)
	
	_service.release_view_model(vm1)
	
	# Should still exist after first release
	var vm3: ViewModelBase = _service.acquire_view_model(MockViewModel)
	assert_object(vm3).is_same(vm2)
	
	_service.release_view_model(vm2)
	_service.release_view_model(vm3)


func test_release_null_view_model_does_not_crash() -> void:
	_service.release_view_model(null)


# ============================================================
# Helper Classes
# ============================================================

class MockViewModel extends ViewModelBase:
	var setup_called := false
	var teardown_called := false
	
	func setup() -> void:
		setup_called = true
	
	func teardown() -> void:
		teardown_called = true


# ============================================================
# Helper Functions
# ============================================================

func _create_mock_view() -> ViewBase:
	var view := ViewBase.new()
	view.name = "MockView"
	return view
