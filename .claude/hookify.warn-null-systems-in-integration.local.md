---
name: warn-null-systems-in-integration
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: .*/tests/integration/.*\.gd$
  - field: new_text
    operator: contains
    pattern: func systems\(\) -> Variant:\s*\n\s*return null
---

⚠️ **systems() returning null in integration test!**

You're returning `null` from `systems()`. **This is bad practice for tests.**

**The Rule:** Integration tests should ALWAYS specify explicit system paths:
```gdscript
func systems() -> Variant:
    return [
        "res://scripts/systems/s_hp.gd",
        "res://scripts/systems/s_damage.gd",
    ]
```

**Why returning `null` is problematic for tests:**
- `null` means "auto-discover ALL systems" — slow, unpredictable ordering
- Makes test behavior dependent on unrelated system changes
- CI runs may break when new systems are added (they auto-register)
- Harder to reason about which systems are actually under test

**Exception:** The base SceneConfig class defaults to `null`. Tests must override this explicitly.

**Reference:** See `reference/system-feature-map.md` for the correct systems to register for your feature.
