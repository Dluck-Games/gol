# Unit Tests — gdUnit4

## What Belongs Here

- Component data tests (property defaults, typed arrays)
- Single-system logic with manually constructed entities (no World)
- Service method tests with mocked dependencies
- GOAP planner/action tests
- PCG single-phase tests

## What Does NOT Belong Here

- Anything that creates a `World` or sets `ECS.world`
- Anything that calls `GOL.setup()` / `GOL.teardown()`
- Multi-system interaction tests
- Full pipeline tests (PCG, combat flow, etc.)

## Template

```gdscript
class_name TestMyComponent
extends GdUnitTestSuite


func test_default_values() -> void:
	var comp: CMyComp = auto_free(CMyComp.new()) as CMyComp
	assert_float(comp.value).is_equal(0.0)


func test_array_field() -> void:
	var comp: CContainer = auto_free(CContainer.new()) as CContainer
	assert_array(comp.stored_components).is_empty()
```

## Assertion API (gdUnit4)

```gdscript
assert_object(obj).is_not_null()
assert_int(value).is_equal(42)
assert_float(value).is_greater_equal(0.0)
assert_str(text).contains("substring")
assert_bool(condition).is_true()
assert_array(arr).is_not_empty()
assert_vector(vec).is_equal(Vector2.ZERO)
```

## Conventions

- **File naming**: `test_*.gd`
- **Directory structure** mirrors `scripts/`: `ai/`, `system/`, `pcg/`, `service/`
- **Use `auto_free()`** for all entities/objects to prevent leaks
- **Static typing everywhere**: `: int`, `-> void`, `Array[Entity]`
- **One test suite per file**, focused on a single class/component

## Running

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project

# All unit tests
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/unit/ -c --ignoreHeadlessMode

# Specific file
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/unit/system/test_foo.gd -c --ignoreHeadlessMode

# Specific directory
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a res://tests/unit/ai/ -c --ignoreHeadlessMode
```

## Test Directories

| Directory | Content |
|-----------|---------|
| `tests/unit/ai/` | GOAP planner + action suites |
| `tests/unit/debug/` | AI Debug Bridge unit tests |
| `tests/unit/pcg/` | PCG single-phase tests |
| `tests/unit/service/` | Service-layer unit tests |
| `tests/unit/system/` | ECS system unit tests |
| `tests/unit/` (root) | Component tests, entity construction, scenario tests |
