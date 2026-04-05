# Validation Checklist — Quality Gates for Integration Tests

## Purpose
Two-phase checklist to catch mistakes BEFORE and AFTER generating a SceneConfig integration test.
Every generated test MUST pass ALL applicable checks.

---

## Phase 1: Pre-Write Validation (Before Writing Code)

Run these checks against your UNDERSTANDING of what test you're about to write.
If any check fails, STOP and resolve before writing code.

### 1.1 Tier Confirmation
- [ ] Does the test need a `World` / `GOLWorld` / `ECS.world`?
  - NO → Wrong tier! Write a **unit test** (gdUnit4) instead
  - YES → Continue ✓
- [ ] Does it test multiple systems interacting?
  - NO → Consider unit test instead
  - YES → Integration tier appropriate ✓

### 1.2 Base Class Lock
- [ ] Will the file use `extends SceneConfig`?
  - Using `extends GdUnitTestSuite` → **FORBIDDEN** in tests/integration/
  - Using `extends RefCounted` directly → Wrong base class
  - `extends SceneConfig` → Correct ✓

### 1.3 File Location
- [ ] File will be under `tests/integration/` or subdirectory?
  - Valid locations:
    - `tests/integration/test_*.gd` (root-level integration test)
    - `tests/integration/flow/test_*_scene.gd` (multi-system gameplay flow)
    - `tests/integration/pcg/test_*.gd` (PCG pipeline test)
  - Invalid: `tests/unit/` (wrong tier), `tests/` root (ambiguous)

### 1.4 Naming Convention
- [ ] Filename follows `test_*.gd` or `test_*_scene.gd` format?
- [ ] class_name follows `Test*Config` PascalCase pattern?
- [ ] class_name is UNIQUE across all integration tests (no collisions)?

### 1.5 System Selection
- [ ] `systems()` returns explicit `Array[String]` (NOT `null`)?
  - Tests should ALWAYS specify exact systems needed
  - `null` means "auto-discover all" — too slow, unpredictable for tests
- [ ] All specified system paths exist and extend `GOLSystem`?
- [ ] No orphan systems included (every system has a reason)?
- [ ] Minimum viable system set for the feature under test?
  - Reference system-feature-map.md for correct combinations

### 1.6 Entity Design
- [ ] All entities use recipe-based spawning (`"recipe": "recipe_id"`)?
  - NO manual `Entity.new()` or `Entity.create()` in entities()
- [ ] All recipe IDs from approved list?
  - Approved: player, enemy_basic, enemy_fire, enemy_wet, enemy_cold, enemy_electric, survivor, campfire, weapon_rifle, weapon_pistol
- [ ] Entities have unique `"name"` values (no duplicates)?
- [ ] Entity positions are spaced appropriately (not overlapping unless intentional)?
  - Recommendation: ≥ 80px apart for non-collision tests, ≤ 20px for collision tests
- [ ] Custom component overrides (if any) use correct GDScript property names?

### 1.7 PCG Setting
- [ ] `enable_pcg()` returns correct value?
  - `true` ONLY if test verifies PCG-generated content
  - `false` for all other tests (faster, deterministic)

### 1.8 Test Scope Clarity
- [ ] Can you describe WHAT the test verifies in ONE sentence?
- [ ] Can you list the minimum assertions needed (≥ 3)?
- [ ] Is there an existing test that already covers this exact scenario?
  - YES → Don't duplicate. Extend existing test or test a DIFFERENT aspect.

---

## Phase 2: Post-Write Validation (After Writing Code)

Run these checks against the GENERATED CODE. Fix any failures before committing.

### 2.1 Structural Completeness
- [ ] File has exactly ONE `class_name Test*Config`?
- [ ] File has `extends SceneConfig`?
- [ ] All 5 methods overridden (NOT inherited defaults)?
  - [ ] `scene_name() -> String` (returns "test")
  - [ ] `systems() -> Variant` (returns Array[String])
  - [ ] `enable_pcg() -> bool` (returns true or false)
  - [ ] `entities() -> Variant` (returns Array[Dictionary] or [])
  - [ ] `test_run(world: GOLWorld) -> Variant` (returns TestResult)
- [ ] No extra public methods that shouldn't be there?
- [ ] Helper methods (if any) are prefixed with `_`?

### 2.2 Import Correctness
- [ ] No stray `extends` statements besides the class declaration?
- [ ] No `preload()` or `load()` calls for built-in types (Entity, Vector2, etc.)?
- [ ] Non-built-in types referenced correctly (CHP, CWeapon, etc. are available globally)?

### 2.3 Static Typing
- [ ] All variables have explicit type annotations?
  - `var result := TestResult.new()` ✓ (inferred from `:=`)
  - `var entity: Entity` ✓ (explicit)
  - `func test_run(world: GOLWorld) -> Variant:` ✓ (return typed)
- [ ] Method parameters typed? Return types typed?
- [ ] No untyped `var x` without `:=` inference or `: Type`?

### 2.4 Async Safety
- [ ] First operation in `test_run()` is an `await`?
  - Minimum: `await world.get_tree().process_frame` (at least 1 frame for entity init)
  - Some tests need 2 frames for full initialization
- [ ] Frame waits use correct pattern?
  ```
  # Correct
  for i: int in range(count):
      await world.get_tree().process_frame

  # Also correct (for timed waits)
  await world.get_tree().create_timer(seconds).timeout
  ```

### 2.5 Null Safety
- [ ] EVERY `get_component()` result is null-checked before property access?
- [ ] EVERY `_find()` / `_find_entity()` result is null-checked?
- [ ] Early return pattern used after null checks? (`if x == null: return result`)
- [ ] No chained null-unsafe access like `a.b.c.d` without intermediate guards?

### 2.6 Assertion Quality
- [ ] Minimum 3 assertions in `test_run()`?
- [ ] All assertion `description` strings are non-empty and descriptive?
- [ ] Assertions ordered: existence → presence → value (cause before effect)?
- [ ] No meaningless assertions like `assert_true(true, "placeholder")`?
- [ ] Uses `assert_true()` for booleans/null-checks, `assert_equal()` for values?

### 2.7 Return Value
- [ ] `test_run()` ALWAYS returns a `TestResult` instance?
  - No early `return null` — always `return result`
  - Even on early-exit paths: `if entity == null: return result`

### 2.8 Helper Methods
- [ ] Helper methods are `func _name(...) -> ReturnType:` (underscore prefix)?
- [ ] Helpers don't duplicate base class methods (SceneConfig._find_entity etc.)?
- [ ] Helpers are focused (single responsibility)?

### 2.9 Resource Cleanup
- [ ] If test mutates global state (config values, GOL.Player, etc.), is it restored?
  - Must restore on ALL code paths (including early returns)
  - Save/restore pattern recommended
- [ ] If test creates dynamic entities (via ServiceContext.recipe()), are they accounted for?

### 2.10 GDScript Syntax
- [ ] File uses tabs for indentation (Godot convention)?
- [ ] No trailing commas in function calls (GDScript doesn't support them)?
- [ ] Dictionary keys are strings ("key": value)?
- [ ] `pass` statements not needed (GDScript allows empty functions)?
- [ ] Comments use `##` for doc comments, `#` for inline?

---

## Phase 3: Execution Validation (After Running the Test)

### 3.1 Compilation
- [ ] Godot loads the file without parse errors?
- [ ] No "invalid 'class_name' in script" errors?
- [ ] No "unrecognized identifier" errors for types?

### 3.2 Execution
- [ ] Test runs without crashing (exit code 0 or 1, not segfault)?
- [ ] Test completes (doesn't hang indefinitely)?
  - If it hangs: add more frame awaits or check for infinite loops
- [ ] TestResult report prints to stdout?

### 3.3 Assertion Results
- [ ] At least some assertions pass (test is wired correctly)?
- [ ] Failure messages (if any) are informative enough to debug?
- [ ] No false positives (assertions passing that shouldn't)?

---

## Common Mistakes Quick Reference

These are the TOP mistakes caught by this checklist, ranked by frequency:

| # | Mistake | Which Check Catches It | Fix |
|---|---------|------------------------|-----|
| 1 | Using `extends GdUnitTestSuite` in integration dir | 1.2 Base Class Lock | Change to `extends SceneConfig` |
| 2 | `systems()` returning `null` | 1.5 System Selection | Return explicit Array[String] |
| 3 | No `await` before entity access | 2.4 Async Safety | Add `await world.get_tree().process_frame` |
| 4 | Chained null-unsafe access | 2.5 Null Safety | Add null guards + early returns |
| 5 | Empty assertion descriptions | 2.6 Assertion Quality | Write descriptive strings |
| 6 | Returning `null` from test_run | 2.7 Return Value | Always `return result` |
| 7 | Not restoring mutated global state | 2.9 Resource Cleanup | Add save/restore pattern |
| 8 | Duplicate entity names in entities() | 1.6 Entity Design | Ensure unique names |
| 9 | Using unknown recipe ID | 1.6 Entity Design | Use approved recipe list |
| 10 | < 3 assertions | 2.6 Assertion Quality | Add more meaningful asserts |
| 11 | Wrong tier (should be unit test) | 1.1 Tier Confirmation | Move to tests/unit/ or redesign |
| 12 | Missing `class_name` | 2.1 Structural | Add `class_name Test*Config` |

## MUST NOT DO
- Do NOT skip checks — they all exist because real mistakes were made
- Do NOT add checks for things that never go wrong (don't pad the list)
- Do NOT use vague language — each check must be specific and actionable
- Do NOT reference external tools or processes not relevant to GDScript/Godot

<!-- OMO_INTERNAL_INITIATOR -->
