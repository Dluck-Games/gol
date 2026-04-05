---
name: check-integration-test-completeness
enabled: true
event: stop
action: warn
pattern: .*
---

📋 **Integration Test Completeness Checklist**

Before finishing, verify your SceneConfig test meets all requirements:

**Structure (all must be present):**
- [ ] `extends SceneConfig` (not GdUnitTestSuite)
- [ ] `class_name Test*Config` (PascalCase with Config suffix)
- [ ] All 5 methods overridden: `scene_name()`, `systems()`, `enable_pcg()`, `entities()`, `test_run(world)`
- [ ] `test_run()` returns `TestResult` (never null)

**Code Quality:**
- [ ] Static typing on all variables and return types
- [ ] `await world.get_tree().process_frame` before any entity/component access
- [ ] Null guard after EVERY `get_component()` or `_find_entity()` call
- [ ] Early return pattern: `if x == null: return result`
- [ ] Minimum 3 assertions in `test_run()`
- [ ] All assertion descriptions are non-empty strings

**Conventions:**
- [ ] Recipe-based entities only (no Entity.new())
- [ ] Valid recipe IDs from approved list
- [ ] Unique entity names
- [ ] Explicit systems() array (not null)
- [ ] Helper methods prefixed with `_`

**If any check fails, fix it before marking done.**

Run the test to verify:
```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/YOUR_TEST.gd
```
