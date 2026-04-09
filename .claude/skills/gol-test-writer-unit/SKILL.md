# gol-test-writer-unit

Use this skill when writing gdUnit4 unit tests for GOL Godot 4.6.
Covers component tests, pure functions, and single-class behavior.
Triggers: 'write unit test', 'unit test', 'test component', 'test pure function', 'gdUnit4 test'.

## Scope

- Location: `tests/unit/`
- Naming: `test_{feature}.gd`
- Base class: `extends GdUnitTestSuite`
- Test functions: `func test_NAME()`

### Valid unit targets

- Pure functions
- Single component behavior
- Single system `process()` logic with manual entity construction
- Single-class state transitions

### NOT unit tests (route to integration)

- Multi-system interaction
- Any behavior that needs a `World`
- Rendering/UI flows
- Recipe spawning

If the scenario needs recipe entities or a realized ECS world, it belongs in integration — use `gol-test-writer-integration` instead.

## Runtime Discovery Rules

Before writing, discover concrete project details from code:

1. **Target class first** → read the class under test and any direct dependencies.
2. **Similar tests** → glob `tests/unit/**/*.gd`, then read 1-2 nearby tests as scaffolds.
3. **Assertion style** → copy real gdUnit4 assertion chains already used in this repo.

Never guess method names, field names, or assertion APIs when the codebase can confirm them.

## gdUnit4 Basics

- Base class: `extends GdUnitTestSuite`
- Test functions: `func test_NAME()`
- Cleanup helper: `auto_free(obj)`
- Lifecycle hooks: `before()`, `after()`, `before_test()`, and `after_test()`

## Assertion API Reference

- `assert_object(obj).is_not_null()`
- `assert_object(obj).is_same(other)`
- `assert_int(value).is_equal(expected)`
- `assert_float(value).is_equal(expected)`
- `assert_float(value).is_equal_approx(expected, tolerance)`
- `assert_str(value).is_equal(expected)`
- `assert_array(arr).is_not_empty()`
- `assert_array(arr).has_size(expected)`
- `assert_array(arr).contains(value)`
- `assert_bool(true).is_true()`
- `assert_bool(false).is_false()`
- `assert_dict(dict).is_equal(expected)`
- `assert_signal(obj).is_emitted("signal_name")`
- `assert_that(value)`
- `fail("message")`

## GOL Project Constraints

- Location: `tests/unit/`
- Naming: `test_{feature}.gd`
- No World access
- No ECS recipe spawning
- Import project classes directly, e.g. `var comp: CHP = CHP.new()`

## Testing Patterns

### Component

1. `new()` the component
2. set properties
3. assert resulting values

### System

1. create `Entity.new()` manually
2. add required components with `entity.add_component()`
3. call the system method under test
4. assert changed component state

### Pure function

1. input
2. output
3. assert expected result
4. include edge cases

## Execution Command

```bash
$GODOT --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/$FILE --ignoreHeadlessMode
```

Results are written to `reports/results.xml`.

## Quality Rules

- Prefer behavior assertions over implementation-detail assertions
- Include edge cases: zero, negative, empty, null-like inputs when applicable
- Keep each test focused on one behavior
- Use static typing where possible
- Use `auto_free()` when temporary objects need cleanup

## Common Mistakes

- Testing implementation details instead of behavior
- Missing edge cases such as zero, negative, or null inputs
- Over-mocking in a language without a built-in mock framework

## Output Contract

Deliver one complete gdUnit4 file that:

- extends `GdUnitTestSuite`
- uses clear `test_*` functions
- stays inside unit-test scope
- can be executed directly with the command above
