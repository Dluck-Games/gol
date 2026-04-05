# Assertion Patterns Reference

## Purpose
Idiomatic ways to write assertions in SceneConfig integration tests using TestResult API.
Based on patterns extracted from all 10 existing integration tests (1292 lines).

## TestResult API (Complete)

```gdscript
var result := TestResult.new()

# Only 2 assertion methods available:
result.assert_true(condition: bool, description: String = "")
result.assert_equal(actual: Variant, expected: Variant, description: String = "")

# Result methods:
result.passed() -> bool      # true if ALL assertions passed
result.exit_code() -> int    # 0=pass, 1=fail
result.print_report() -> void # stdout: [PASS]/[FAIL] per assertion
```

## Pattern Catalog

### Pattern 1: Entity Existence (10/10 tests — UNIVERSAL)
**When:** Every test must verify spawned entities exist before operating on them.
**Frequency:** 100% of tests use this as first assertion.

```gdscript
var entity: Entity = _find(world, "EntityName")
result.assert_true(entity != null, "Description of what entity should exist")

# ALWAYS follow with early return guard:
if entity == null:
    return result
```

**Rule:** NEVER access components on a null entity. Always null-guard.

### Pattern 2: Component Presence (8/10 tests)
**When:** Verifying an entity has (or doesn't have) a specific component after system execution.

```gdscript
# Positive case
result.assert_true(entity.has_component(CHP), "Entity has CHP after init")
# Negative case
result.assert_true(not entity.has_component(CWeapon), "Enemy lost CWeapon after death")
```

### Pattern 3: Component Property Value (7/10 tests)
**When:** Checking specific field values on attached components.

```gdscript
var hp: CHP = entity.get_component(CHP)
result.assert_true(hp.hp > 0.0, "Player is alive (HP > 0)")
result.assert_equal(weapon.attack_range, 42.0, "Weapon preserves attack_range")
result.assert_true(container.stored_components.size() > 0, "Box has stored items")
```

**Rule:** Always null-guard the get_component result before accessing properties.

### Pattern 4: Collection Size Checks (4/10 tests)
**When:** Verifying array/dictionary counts.

```gdscript
result.assert_equal(world.entities.size(), 0, "All entities cleaned up")
result.assert_true(map_entities.size() > 0, "Map entities exist")
```

### Pattern 5: Dictionary Key Existence (2/10 tests)
**When:** Working with enum-keyed dictionaries (e.g., elemental afflictions).

```gdscript
result.assert_true(
    affliction.entries.has(CElementalAttack.ElementType.FIRE),
    "Affliction contains fire entry"
)
```

### Pattern 6: ECS Query Results (1/10 tests)
**When:** Finding entities by component type rather than name.

```gdscript
var map_entities = ECS.world.query.with_all([CMapData]).execute()
result.assert_true(map_entities.size() > 0, "Map data entity exists")
```

### Pattern 7: Null-Safety Early Return Chain (8/10 tests — UNIVERSAL BEST PRACTICE)
**When:** Multiple dependent assertions where later ones require earlier ones to pass.

```gdscript
# Step 1: Find entity
var player: Entity = _find(world, "TestPlayer")
result.assert_true(player != null, "Player exists")
if player == null:
    return result  # ← EARLY RETURN prevents cascading null errors

# Step 2: Get component
var hp: CHP = player.get_component(CHP)
result.assert_true(hp != null, "Player has CHP")
if hp == null:
    return result

# Step 3: Check value (safe — hp is non-null here)
result.assert_true(hp.hp > 0.0, "Player is alive")
```

**Rule:** Each dependency level gets its own null-check + early return. Never chain more than 2 levels without a guard.

## Assertion Ordering Rules (MANDATORY)

1. **Existence first**: Always assert entity existence BEFORE component presence
2. **Presence before value**: Always assert component exists BEFORE checking its values
3. **Setup before action**: Assert initial state, then trigger action, then assert result state
4. **Cause before effect**: If A causes B, assert A happened, THEN assert B happened

## Anti-Patterns (NEVER do these)

1. ❌ **No null guard**: Accessing `.field` on potentially null get_component result
   ```gdscript
   # BAD
   result.assert_true(entity.get_component(CHP).hp > 0, "...")  # CRASH if null

   # GOOD
   var hp := entity.get_component(CHP)
   result.assert_true(hp != null, "has CHP")
   if hp == null: return result
   result.assert_true(hp.hp > 0.0, "alive")
   ```

2. ❌ **Exact float equality after physics**: Physics simulations produce floating point drift
   ```gdscript
   # BAD
   result.assert_equal(position.x, 100.0, "exact position")  # might fail

   # GOOD
   result.assert_true(abs(position.x - 100.0) < 0.01, "position near expected")
   ```

3. ❌ **Too few assertions**: Tests with < 3 assertions don't adequately verify behavior
   - Minimum: 3 meaningful assertions per test
   - Ideal: 5-12 assertions for flow tests

4. ❌ **Asserting implementation details**: Testing internal variable names rather than observable behavior
   ```gdscript
   # BAD — tests internal naming
   result.assert_true(entity.name == "_internal_helper", "...")

   # GOOD — tests observable outcome
   result.assert_true(entity.has_component(CTransform), "entity positioned")
   ```

5. ❌ **No description string**: Empty descriptions make failure reports useless
   ```gdscript
   # BAD
   result.assert_true(x > 0, "")

   # GOOD
   result.assert_true(x > 0, "Player HP is positive after healing")
   ```

## Description String Style Guide

- Describe WHAT is being verified, not HOW
- Include context: "Player {condition} after {action}"
- Use consistent phrasing:
  - Existence: "{EntityName} exists"
  - Presence: "{EntityName} has {Component}"
  - Absence: "{EntityName} lost {Component} after {event}"
  - Value: "{Component}.{field} is {expected} after {action}"
  - State: "{EntityName} is {state}" (alive/dead/armed/etc.)

## Common Assertion Sequences by Test Type

### Combat Test Sequence (~4-6 assertions):
1. Player exists → Enemy exists
2. Player has CHP → Enemy has CHP
3. Wait N frames for combat
4. Player HP > 0 (survived) OR Enemy HP reduced/took damage
5. (Optional) Specific damage value check

### Drop/Pickup Flow Sequence (~8-12 assertions):
1. Player exists → Enemy exists
2. Both have required components
3. Attach test-specific component (weapon to enemy, etc.)
4. Deal lethal damage
5. Enemy lost weapon component
6. Box/Chest entity spawned
7. Box has CContainer with items
8. Stored item preserved original values
9. Player can pick up
10. Player gained component from pickup

### PCG Pipeline Sequence (~3-4 assertions):
1. Wait for PCG completion (timer)
2. Map entity exists (via ECS query)
3. PCG result is non-null
4. PCG result is valid

## MUST NOT DO
- Do NOT invent assertion methods beyond assert_true and assert_equal (that's ALL TestResult has)
- Do NOT suggest gdUnit4 assertions (assert_int, assert_float, etc.) — those are UNIT tier ONLY
- Do NOT include hypothetical patterns not observed in existing tests
- Do NOT use placeholder text or TODO markers

<!-- OMO_INTERNAL_INITIATOR -->
