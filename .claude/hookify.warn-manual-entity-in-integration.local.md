---
name: warn-manual-entity-in-integration
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: .*/tests/integration/.*\.gd$
  - field: new_text
    operator: contains
    pattern: Entity\.new\(\)
---

⚠️ **Manual Entity construction in integration test!**

You're calling `Entity.new()` directly. **This violates integration test conventions.**

**The Rule:** Integration tests MUST use recipe-based entity spawning via the `entities()` method:
```gdscript
func entities() -> Variant:
    return [
        {
            "recipe": "player",
            "name": "TestPlayer",
            "components": { "CTransform": { "position": Vector2(100, 100) } },
        },
    ]
```

**Exception:** Dynamic entities created DURING `test_run()` (after initial spawn) via `ServiceContext.recipe().create_entity_by_id("recipe_id")` are acceptable — but not `Entity.new()`.

**Why it matters:**
- Recipe-based spawning ensures proper component initialization (GECS deep-copy)
- Manual `Entity.new()` skips `_initialize()` and may miss required components
- 8 of 10 existing tests use recipes exclusively

**Reference:** Check `reference/test-catalog.md` for how all 10 existing tests define entities.
