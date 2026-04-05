---
name: block-sceneconfig-in-unit
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: .*/tests/unit/.*\.gd$
  - field: new_text
    operator: contains
    pattern: extends SceneConfig
---

🚫 **Wrong base class for unit test directory!**

You're writing `extends SceneConfig` in `tests/unit/`. **This is forbidden.**

**The Rule:**
- `tests/unit/` → **MUST** use `extends GdUnitTestSuite`
- `tests/integration/` → **MUST** use `extends SceneConfig`

**What to do:**
1. If testing a single class/component in isolation → use `extends GdUnitTestSuite`, move to `tests/unit/`
2. If you need a World with multiple systems → move to `tests/integration/` and keep `extends SceneConfig`

SceneConfig tests need a real GOLWorld (ECS). Unit tests must NOT create Worlds.
