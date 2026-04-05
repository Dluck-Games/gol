---
name: gol-test-integration
description: Write and validate SceneConfig integration tests for GOL Godot 4.6 project.
  Generates valid GDScript, selects correct systems, uses recipe-based entities,
  follows all project conventions. Triggers: "write integration test", "SceneConfig test",
  "new integration test", "integration test for [feature]", "test [system] integration"
allowed-tools: Read, Write, Bash, Glob, Grep
---

# gol-test-integration — SceneConfig Test Generation & Validation Skill

This skill writes **integration-tier SceneConfig tests only**.
It is for tests that load a real `GOLWorld`, register ECS systems, spawn recipe-based entities or use the default test scene, and assert multi-system behavior through `test_run(world)`.

Read these local assets before writing code:
- {file:reference/system-feature-map.md}
- {file:reference/assertion-patterns.md}
- {file:reference/test-catalog.md}
- {file:reference/validation-checklist.md}
- {file:templates/minimal.gd}
- {file:templates/combat-flow.gd}
- {file:templates/component-flow.gd}
- {file:templates/pcg-pipeline.gd}
- {file:templates/ui-interaction.gd}

Core contract:
1. confirm the tier
2. map feature → systems → entities → assertions
3. start from the closest template
4. pass pre-write and post-write validation
5. execute the test and require exit code `0`

---

## 1. Title & Overview

**Scope:** SceneConfig integration tier only.

Use this skill when the task is to create or update a test under `gol-project/tests/integration/` that:
- needs `World`, `GOLWorld`, or `ECS.world`
- verifies multiple systems or frame-based world behavior
- depends on recipe-based spawning, default scene setup, ECS queries, or service/world wiring

Do **not** use this skill for:
- gdUnit4 unit tests
- live-game AI Debug Bridge E2E scripts
- production gameplay implementation

Expected output:
- one complete `.gd` file under `tests/integration/`
- `extends SceneConfig`
- `class_name Test*Config`
- explicit `systems()` selection
- recipe-based entity setup or deliberate `entities() = null/[]`
- at least 3 descriptive assertions
- passes the standard SceneConfig runner

Bias rules:
- prefer the smallest valid systems list
- prefer the simplest template that can express the scenario
- prefer observable behavior over implementation trivia
- prefer explicit guards and early returns over clever chained access

If the requested work is not integration-tier, stop and switch skills.

---

## 2. Safety Rules

> **SAFETY: This skill operates from a MANAGEMENT REPO (gol/).**
> Game code lives in the `gol-project/` submodule.
> **ALL Godot operations MUST execute inside `gol-project/`.**
> **NEVER run git checkout, Godot, or create game files in the gol/ root directory.**
> **Test files go in `gol-project/tests/integration/` (via worktree if isolated).**

Hard rules:
- Skill assets live in `gol/.claude/skills/...`; test files do not.
- Run Godot from `/Users/dluckdu/Documents/Github/gol/gol-project`.
- Put integration tests in `/Users/dluckdu/Documents/Github/gol/gol-project/tests/integration/`.
- If isolation is needed, use a `gol-project` worktree under `gol/.worktrees/manual/...`.
- Never create game/test files in the management repo root.
- Never treat SceneConfig and gdUnit4 as interchangeable.

If the working directory or target path is wrong, fix that before writing code.

---

## 3. Decision Flow

Follow this sequence exactly.

### Step 1: Tier Confirmation

Use this decision matrix first.

| Question | Yes → | No → |
|----------|-------|------|
| Needs World/ECS.world? | Integration ✅ | Unit (wrong skill!) |
| Tests multiple systems? | Integration ✅ | Consider unit |
| Uses GOL.setup()/services? | Integration ✅ | Unit |

Stop conditions:
- If it can be tested without a real world, this skill is wrong.
- If it needs live rendering or AI Debug Bridge injection, it is probably E2E instead.
- If it is a pure function/class test, use the unit-test flow instead.

**STOP if this isn't an integration test.**

### Step 2: Feature → System Mapping

Primary source: {file:reference/system-feature-map.md}

Quick reference:

| Feature | Systems |
|---------|---------|
| Combat/HP | `s_hp`, `s_damage`, `s_dead` |
| Drop/pickup | `s_damage`, `s_pickup`, `s_life`, `s_dead` |
| Melee+elemental | `s_melee_attack`, `s_elemental_affliction`, `s_damage` |
| PCG map | `s_map_render` (`enable_pcg=true`) |
| Crafting | `s_pickup` |
| Console | `[]` (service layer) |
| UI | `s_ui`, `s_dialogue` |
| Penalties | `s_weight_penalty` + conflict systems as needed |

System rules:
- Always choose the **minimal complete set**.
- Preserve documented execution expectations: gameplay before cost, then render/UI.
- Add helper systems only when the behavior truly depends on them.
- **ALWAYS specify explicit `systems()`. NEVER return `null` for tests.**

Sanity checks:
- HP changing usually needs more than `s_damage` alone.
- Death/drop/pickup needs the full chain, not a partial subset.
- Penalty/conflict tests usually need both the producer and the modifier systems.
- UI tests may need default-scene setup rather than spawned entities.

### Step 3: Pattern Selection

Choose one template before writing.

- **minimal** — simplest valid test; default starting point for uncertain patterns
- **combat-flow** — HP, damage, survival, death-state over time
- **component-flow** — kill → drop → pickup loop
- **pcg-pipeline** — map generation, ECS query, `enable_pcg() = true`
- **ui-interaction** — node traversal, input simulation, signals, `entities() = null`

Templates:
- {file:templates/minimal.gd}
- {file:templates/combat-flow.gd}
- {file:templates/component-flow.gd}
- {file:templates/pcg-pipeline.gd}
- {file:templates/ui-interaction.gd}

Selection rules:
- Start with **minimal** unless you can prove a richer flow is required.
- Use **combat-flow** for timed combat assertions.
- Use **component-flow** for box/container/preserved-component verification.
- Use **pcg-pipeline** only when generated map output is the subject.
- Use **ui-interaction** only when the target is node/UI behavior rather than raw ECS state.

If unsure, match against a golden example in {file:reference/test-catalog.md}.

### Step 4: Entity Design

Entity rules are strict.

- **ALWAYS use recipe-based spawning. Never use `Entity.new()`.**
- Approved core recipes:
  - `player`
  - `enemy_basic`
  - `enemy_fire`
  - `enemy_wet`
  - `enemy_cold`
  - `enemy_electric`
  - `survivor`
  - `campfire`
  - `weapon_rifle`
  - `weapon_pistol`
- Additional approved recipes are documented in {file:reference/system-feature-map.md}.
- Entity names must be unique and descriptive.
- Use `Test*` names, e.g. `TestPlayer`, `TestEnemyFire`, `TestCampfire`.
- Default spacing:
  - `>= 80px` for non-collision tests
  - `<= 20px` for collision/proximity tests
- Default override: only `CTransform.position`.
- Any extra override or manual component attachment needs a test-specific reason.

Pre-write questions:
- Is each recipe documented and real?
- Is each entity name unique?
- Is spacing intentional for the behavior under test?
- Are you relying on default recipe data unless mutation is necessary?

### Step 5: Assertion Strategy

Primary source: {file:reference/assertion-patterns.md}

Rules:
- minimum **3 assertions** per test
- every assertion string must be descriptive and non-empty
- use **existence → presence → value** ordering
- assert cause before effect
- guard every nullable lookup before deeper access

Recommended progression:
1. expected entity/system/result exists
2. expected component/state is present
3. expected property/value changed as intended

Null-safety policy:
- Guard every `find`, `get_component`, query result, or optional node.
- On failure, assert the missing prerequisite, then early-return the same `TestResult`.
- Never do unsafe chains like `entity.get_component(CHP).hp` without a guard.

### Step 6: Code Generation Workflow

Use this exact workflow:
1. choose the closest template from `templates/`
2. fill in systems, entities, waits, and assertions
3. run Phase 1 of {file:reference/validation-checklist.md}
4. write the complete `.gd` file under `gol-project/tests/integration/`
5. run Phase 2 of {file:reference/validation-checklist.md}
6. execute the test and require exit code `0` (Phase 3)

When converting a template into a real test:
- rename the class from `Template` style to `Test*Config`
- rename the file to `test_*.gd` or `test_*_scene.gd`
- replace every placeholder
- delete unused commented extension blocks
- keep helpers focused and prefixed with `_`
- never return `null` from `test_run`

---

## 4. Pre-Write Validation

Apply this abbreviated Phase 1 summary from {file:reference/validation-checklist.md} before writing.

### Pre-write gate

- **Tier confirmed** ✓
  - needs `World`/`GOLWorld`/`ECS.world`
  - not a gdUnit4 unit test
- **Base class** ✓
  - `extends SceneConfig`
  - not `GdUnitTestSuite`
- **Location** ✓
  - file goes under `tests/integration/`, `tests/integration/flow/`, or `tests/integration/pcg/`
- **Naming** ✓
  - filename starts with `test_`
  - class is `Test*Config`
  - class name is unique, not template residue
- **Systems** ✓
  - explicit `systems()` array
  - not `null`
  - every path justified
- **Recipes** ✓
  - valid documented recipe IDs only
- **Spawning style** ✓
  - no manual `Entity.new()`
- **Scope clarity** ✓
  - one-sentence behavior goal
  - at least 3 planned assertions

### Answer these before coding

| Planning question | Required answer |
|-------------------|-----------------|
| What feature is under test? | one sentence |
| Which systems are required? | explicit list |
| Which template is closest? | one template name |
| Which entities are needed? | recipe + name + position |
| What are the 3 minimum assertions? | existence, presence, value |
| Is `enable_pcg()` true or false? | explicit boolean |
| Should `entities()` be list, `[]`, or `null`? | one deliberate choice |

Do not start generating code until file path, class name, systems, entity setup, wait strategy, and assertion plan are all explicit.

---

## 5. Post-Write Validation

Apply this abbreviated Phase 2 + Phase 3 summary from {file:reference/validation-checklist.md} after writing.

### Must-pass checks

- **All 5 methods overridden** ✓
  - `scene_name()`
  - `systems()`
  - `enable_pcg()`
  - `entities()`
  - `test_run(world: GOLWorld)`
- **Static typing throughout** ✓
- **Async safety** ✓
  - `await` happens before entity access
- **Null guards + early returns** ✓
- **Returns `TestResult`** ✓
  - never `null`
- **Runs without crash** ✓
- **Exit code `0`** ✓

### Detailed post-write scan

| Check | Verify |
|------|--------|
| Base shape | exactly one `class_name`, one `extends SceneConfig` |
| Placeholder cleanup | no `{{PLACEHOLDER}}` remains |
| Method coverage | all 5 required overrides exist |
| Systems | explicit, minimal, non-null |
| Typing | typed locals/helpers/params or `:=` inference |
| Await discipline | first meaningful operation in `test_run()` is an `await` |
| Null safety | no unsafe component/property chain access |
| Assertions | 3+ assertions, all descriptive |
| Order | existence before presence before value |
| Cleanup | global mutations restored on all paths |
| Syntax | valid GDScript formatting, no trailing commas |
| Return | `TestResult` returned on success and early exit |

Reject the file if any of these are true:
- `systems()` returns `null`
- `test_run()` can fall through without returning `result`
- entity/component access happens before the initial `await`
- any assertion string is empty or vague
- helpers are unused template leftovers
- the file cannot be run with the standard SceneConfig command

---

## 6. Running Tests

Use these commands.

```bash
# Single test
cd /Users/dluckdu/Documents/Github/gol/gol-project
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --scene scenes/tests/test_main.tscn \
  -- --config=res://tests/integration/YOUR_TEST.gd

# All tests (from management repo)
./shortcuts/run-tests.command
```

Exit codes:
- `0` = PASS
- `1` = FAIL

Expected output:
```text
[RUN] path/to/test.gd
  ✓ Description
  ✗ Description — expected: X, got Y
=== N/M passed ===
```

Execution rules:
- run the single test first for new/edited files
- use the batch runner after the single test is clean
- if the test crashes before assertions, fix structure/timing first
- if assertions fail, re-check systems list, wait strategy, and entity setup before widening the test

Failure triage order:
1. wrong working directory/path
2. syntax or compile error
3. missing system dependency
4. async timing too early
5. bad entity setup or invalid recipe
6. wrong expected assertion

If the runner does not return `0`, the deliverable is not complete.

---

## 7. Common Mistakes

Condensed anti-patterns from {file:reference/validation-checklist.md}:

| # | Mistake | Fix |
|---|---------|-----|
| 1 | Wrong base class (`GdUnitTestSuite`) | Change to `extends SceneConfig` and implement all 5 overrides |
| 2 | `systems()` returning `null` | Return an explicit `Array[String]` |
| 3 | Missing `await` before entity access | Make the first operation in `test_run()` an `await` |
| 4 | Null-unsafe chained access | Guard each lookup and early-return `result` |
| 5 | Empty assertion descriptions | Write descriptive non-empty strings |
| 6 | Returning `null` from `test_run` | Always return a `TestResult` |
| 7 | Not restoring mutated global state | Save and restore on every path |
| 8 | Duplicate entity names | Use unique `Test*` names |
| 9 | Unknown recipe IDs | Use only documented recipes |
| 10 | Fewer than 3 assertions | Add existence, presence, and value assertions |

Extra reminders:
- do not assert exact float equality after movement/physics-style updates
- do not assert implementation details when observable behavior is available
- do not use `entities() = null` unless you deliberately want default-scene UI behavior
- do not set `enable_pcg() = true` unless the assertion depends on PCG output

---

## 8. Reference Index

Core references:
- Systems → Features: {file:reference/system-feature-map.md}
- Assertion patterns: {file:reference/assertion-patterns.md}
- Test catalog (10 golden examples): {file:reference/test-catalog.md}
- Validation checklist: {file:reference/validation-checklist.md}

Templates:
- {file:templates/minimal.gd} — Bare skeleton
- {file:templates/combat-flow.gd} — Combat/HP pattern
- {file:templates/component-flow.gd} — Drop/pickup cycle
- {file:templates/pcg-pipeline.gd} — PCG generation
- {file:templates/ui-interaction.gd} — UI/input simulation

Recommended lookup order:
1. use {file:reference/system-feature-map.md} to choose systems and entities
2. open the closest template and copy its structure
3. compare with a real example in {file:reference/test-catalog.md}
4. tighten assertion ordering and null-safety with {file:reference/assertion-patterns.md}
5. finish with {file:reference/validation-checklist.md}

---

## 9. Quick Reference Cards

### Card A — Common system paths

| System | Resource path | Typical use |
|--------|---------------|-------------|
| `s_hp` | `res://scripts/systems/s_hp.gd` | HP/invincibility handling |
| `s_damage` | `res://scripts/systems/s_damage.gd` | damage, hit processing, drop/death setup |
| `s_dead` | `res://scripts/systems/s_dead.gd` | death/removal/respawn sequence |
| `s_pickup` | `res://scripts/systems/s_pickup.gd` | pickup/container/blueprint flow |
| `s_life` | `res://scripts/systems/s_life.gd` | lifetime expiry → dead state |
| `s_melee_attack` | `res://scripts/systems/s_melee_attack.gd` | melee timing and overlap damage |
| `s_elemental_affliction` | `res://scripts/systems/s_elemental_affliction.gd` | elemental DoT/propagation |
| `s_collision` | `res://scripts/systems/s_collision.gd` | collision area lifecycle |
| `s_fire_bullet` | `res://scripts/systems/s_fire_bullet.gd` | weapon fire and bullet spawn |
| `s_move` | `res://scripts/systems/s_move.gd` | movement/input updates |
| `s_ai` | `res://scripts/systems/s_ai.gd` | GOAP AI loop |
| `s_perception` | `res://scripts/systems/s_perception.gd` | perception scan |
| `s_map_render` | `res://scripts/systems/s_map_render.gd` | PCG map render |
| `s_dialogue` | `res://scripts/systems/s_dialogue.gd` | dialogue proximity/view control |
| `s_weight_penalty` | `res://scripts/systems/s_weight_penalty.gd` | weight-based speed penalty |

### Card B — Recipe IDs

| Recipe ID | Description | Typical use |
|-----------|-------------|-------------|
| `player` | player character | most world-driven flows |
| `enemy_basic` | baseline enemy | basic combat/drop tests |
| `enemy_fire` | fire enemy | elemental tests |
| `enemy_wet` | wet enemy | elemental interaction tests |
| `enemy_cold` | cold enemy | freeze/cold-rate tests |
| `enemy_electric` | electric enemy | spread/conflict tests |
| `survivor` | ally/NPC | dialogue or interaction setup |
| `campfire` | structure/base object | proximity/base interactions |
| `weapon_rifle` | rifle item | pickup/inventory-like tests |
| `weapon_pistol` | pistol item | pickup/inventory-like tests |
| `enemy_raider` | advanced enemy recipe | verify component needs before use |
| `survivor_healer` | healer ally | healing/conflict scenarios |

### Card C — Common component types

| Component | Typical assertion target |
|-----------|--------------------------|
| `CTransform` | position, spacing, movement side effects |
| `CHP` | presence, HP value, invincibility timing |
| `CDamage` | pending damage state |
| `CDead` | death flag/state |
| `CContainer` | stored dropped components/loot boxes |
| `CPickup` | pickup eligibility/flow |
| `CLifeTime` | decay/expiry |
| `CMelee` | cooldown/readiness |
| `CElementalAffliction` | elemental status payload |
| `CMapData` | PCG query output |
| `CWeapon` | weapon attachment or preserved fields |
| `CMovement` | speed or penalty-modified values |
| `CCollision` | overlap/collision setup dependencies |
| `CPlayer` | player-specific detection/penalty logic |
| `CAreaEffect` | aura/radius behavior |

### Card D — SceneConfig API cheat sheet

| Method | Return | Purpose | Notes |
|--------|--------|---------|-------|
| `scene_name()` | `String` | choose test scene | usually `"test"` |
| `systems()` | `Variant` | register system resource paths | explicit array only; never `null` |
| `enable_pcg()` | `bool` | toggle PCG | `true` only for PCG-dependent tests |
| `entities()` | `Variant` | declare spawn set | list for most tests, `[]` for PCG, `null` only for default-scene UI pattern |
| `test_run(world: GOLWorld)` | `Variant` | execute assertions | must always return `TestResult` |

`test_run()` pattern: create `TestResult` → `await` → find prerequisites → assert existence → guard/early-return → assert presence/value → `return result`.
