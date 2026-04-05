---
name: block-gdunit-in-integration
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: .*/tests/integration/.*\.gd$
  - field: new_text
    operator: contains
    pattern: extends GdUnitTestSuite
---

🚫 **Wrong base class for integration test directory!**

You're writing `extends GdUnitTestSuite` in `tests/integration/`. **This is forbidden.**

**The Rule:**
- `tests/integration/` → **MUST** use `extends SceneConfig`
- `tests/unit/` → **MUST** use `extends GdUnitTestSuite` (or `extends GdUnitTestSuite`)

**What to do:**
1. Change `extends GdUnitTestSuite` to `extends SceneConfig`
2. Add all 5 required methods: `scene_name()`, `systems()`, `enable_pcg()`, `entities()`, `test_run(world)`
3. Use `TestResult` for assertions (not gdUnit4's `assert_int`, `assert_float`, etc.)

**Reference:** See `.claude/skills/gol-test-integration/SKILL.md` for the correct integration test template.
