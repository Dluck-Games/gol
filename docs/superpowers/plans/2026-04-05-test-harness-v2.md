# Test Harness v2 — Subagent-Driven Test Framework

Date: 2026-04-05
Status: Ready
Scope: Reorganize test generation/execution into subagent-driven architecture with zero-maintenance reference strategy.
Supersedes: 2026-04-05-integration-test-harness.md (v1)
Research: docs/reports/2026-04-05-test-harness-v2-research.md

## Problem Statement

v1 harness has structural issues:
1. **Thin agent + fat skill** — test-writer agent's first step is "invoke skill," doubling context cost without benefit
2. **Skill exposes knowledge to main agent** — main agent can bypass subagent and write tests directly
3. **Reference files require maintenance** — test-catalog already stale (10 listed vs 13 actual)
4. **Cross-platform model conflict** — `model: glm-5v-turbo-ioa` in agent frontmatter invalid for Claude Code
5. **Inconsistent test patterns** — 8 old tests have local `_find()` helpers instead of base class `_find_entity()`

## Design Decisions

### D1: Subagent over Skill for test writing
**Chosen:** Main agent delegates to subagent, never writes tests itself
**Why:** Test writing is a bounded task. Main agent should stay focused on feature/bug work. Skill injection pollutes main agent context with 400+ lines of test knowledge.

### D2: Writer split by tier, Runner unified
**Chosen:** `test-writer-integration`, `test-writer-unit` (separate), `test-runner` (unified)
**Why:** Writing requires tier-specific domain knowledge (different base class, API, patterns). Running is mechanical dispatch (execute command + parse output).

### D3: Zero-reference maintenance
**Chosen:** Delete all reference files and templates. Agent embeds core rules (~150 lines), discovers details from codebase at runtime.
**Why:** Existing passing tests are self-maintaining knowledge (CI guarantees correctness). AGENTS.md files document system/component catalogs. Reference files duplicate this and go stale.

### D4: Routing via dispatch skill
**Chosen:** `gol-test-dispatch` skill helps main agent select the right subagent
**Why:** Three-tier test framework needs external knowledge for routing, but this knowledge isn't needed every session. Skill is loaded on demand.

### D5: Platform-neutral agent definitions
**Chosen:** Agent `.md` files contain no `model` field. Claude Code inherits from global config (sonnet). OMO specifies model in `oh-my-opencode.jsonc`.
**Why:** `.claude/agents/*.md` is shared across platforms. Model selection is platform-specific.
**Verified:** R2 confirms tool names are identical across platforms (case auto-lowered by OMO).

### D6: Native shell hooks for hard rules
**Chosen:** Use shell-command PreToolUse hooks in `.claude/settings.local.json` for cross-platform enforcement. Delete hookify rules (CC-only, not bridged by OMO).
**Why:** R1 confirms OMO bridges shell-command hooks via `claude-code-hooks` module (exit code protocol: 0=allow, 2=deny). Hookify declarative rules are CC-only and cannot enforce across both clients.

## Target File Structure

```
.claude/
├── agents/
│   ├── test-writer-integration.md    # SceneConfig expert (~150 lines, self-contained)
│   ├── test-writer-unit.md           # gdUnit4 expert (~80 lines, self-contained)
│   └── test-runner.md                # Unified runner (~120 lines, all tiers)
│
├── skills/
│   └── gol-test-dispatch/
│       └── SKILL.md                  # Routing: tier decision + prompt templates + run commands
│
├── hooks/
│   ├── block-gdunit-in-integration.sh    # PreToolUse: block GdUnitTestSuite in tests/integration/
│   └── block-sceneconfig-in-unit.sh      # PreToolUse: block SceneConfig in tests/unit/
│
└── settings.local.json               # Hook configuration (PreToolUse shell hooks)

.opencode/
└── oh-my-opencode.jsonc              # OMO tuning (model, temp, permissions, hooks bridge)
```

### Deleted
- `.claude/skills/gol-test-integration/` — entire directory (knowledge absorbed into agents)
- `.claude/skills/gol-test/` — entire directory (routing absorbed into gol-test-dispatch, tier knowledge absorbed into agents)
- `.claude/agents/test-writer.md` — replaced by `test-writer-integration.md`
- `.claude/hookify.*.local.md` — 5 files (replaced by shell hooks)

### Knowledge Migration Map

| Source | Destination |
|--------|-------------|
| `gol-test/SKILL.md` tier decision matrix | `gol-test-dispatch/SKILL.md` |
| `gol-test/SKILL.md` run commands | `gol-test-dispatch/SKILL.md` |
| `gol-test/SKILL.md` system/recipe tables | `test-writer-integration.md` (embedded quick ref) |
| `gol-test/SKILL.md` gotchas | `test-writer-integration.md` (embedded) |
| `gol-test/reference/unit-tests.md` | `test-writer-unit.md` (embedded) |
| `gol-test/reference/integration-tests.md` | `test-writer-integration.md` (embedded) |
| `gol-test/reference/e2e-tests.md` | Deleted (e2e writer not in scope) |
| `gol-test-integration/SKILL.md` decision flow | `test-writer-integration.md` (embedded) |
| `gol-test-integration/SKILL.md` validation checklist | `test-writer-integration.md` (embedded, compact) |
| `gol-test-integration/SKILL.md` quick ref cards | `test-writer-integration.md` (embedded) |
| `gol-test-integration/reference/*.md` (4 files) | Deleted (runtime discovery replaces static docs) |
| `gol-test-integration/templates/*.gd` (5 files) | Deleted (existing tests serve as scaffolds) |
| hookify block rules (2) | `.claude/hooks/*.sh` + `settings.local.json` |
| hookify warn rules (3) | Dropped (advisory rules enforced via agent prompts) |

## Component Specifications

### gol-test-dispatch Skill (~60 lines)

Purpose: Help main agent route to the correct subagent.

Contents:
1. **Tier decision matrix**
   - Pure function/single component/single class → spawn test-writer-unit
   - Multi-system ECS behavior / needs World → spawn test-writer-integration
   - User-facing gameplay scenario / needs rendering → E2E (not yet available)
2. **Prompt templates** for each writer agent
   - What information main agent must provide (feature description, systems, expected behavior)
3. **Quick run commands** for manual testing

Does NOT contain: test writing knowledge, assertion patterns, validation rules, system/recipe tables.

### test-writer-integration Agent (~150 lines)

Purpose: Write complete, runnable SceneConfig integration tests.

Embedded knowledge (from gol-test-integration SKILL.md + gol-test reference/integration-tests.md):
- SceneConfig API (5 required overrides, signatures, return types)
- SceneConfig architecture (how test_main.tscn loads configs, spawns entities, runs test_run)
- Core rules (recipe spawning, 3+ assertions, null guards, existence→presence→value)
- Compact validation checklist (pre-write + post-write, ~20 lines)
- Quick reference tables (common systems, recipes, components)
- Common mistakes table (~10 lines)
- Gotchas (GECS deep-copy, World.entities, recipe component defaults)
- Execution command

Runtime discovery (per invocation):
- Relevant system details → Read `scripts/systems/AGENTS.md` + specific `s_*.gd`
- Most similar existing test → Glob `tests/integration/**/*.gd`, read 1-2 as scaffold
- Available recipes → Glob `resources/recipes/*.tres`
- Component details → Read specific `c_*.gd`

Frontmatter:
```yaml
---
name: test-writer-integration
description: Write SceneConfig integration tests for GOL Godot 4.6.
  Self-contained expert. Discovers system/recipe/component details from codebase.
tools: Read, Write, Glob, Grep, Bash
---
```

### test-writer-unit Agent (~80 lines)

Purpose: Write gdUnit4 unit tests.

Embedded knowledge (from gol-test reference/unit-tests.md):
- gdUnit4 basics (extends GdUnitTestSuite, auto_free, assert_* API)
- Scope rules (what belongs in unit, what doesn't)
- GOL project constraints (file location under tests/unit/, naming, no World/ECS)
- Component testing pattern (direct new() + property verification)
- System testing pattern (manual entity construction + process call)
- Pure function testing pattern (input→output)
- Assertion API reference (assert_object, assert_int, assert_float, assert_str, assert_array)
- Execution command

Frontmatter:
```yaml
---
name: test-writer-unit
description: Write gdUnit4 unit tests for GOL Godot 4.6.
  Covers component tests, pure functions, and single-class behavior.
tools: Read, Write, Glob, Grep, Bash
---
```

### test-runner Agent (~120 lines)

Purpose: Execute tests across all tiers, parse output, diagnose failures.

Embedded knowledge:
- Tier identification (read file → check `extends` → route)
- Two execution commands:
  - gdUnit4: `$GODOT --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/$FILE --ignoreHeadlessMode`
  - SceneConfig: `$GODOT --headless --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/$FILE`
- Two output parsers:
  - gdUnit4: JUnit XML in `reports/results.xml`
  - SceneConfig: TestResult stdout (`[RUN]`, `✓`/`✗`, `=== N/M passed ===`)
- Unified report format
- Failure diagnosis protocol (4 levels: script error, runtime error, logic failure, hang)
- Batch mode: discover all tests via Glob + grep for `extends` pattern

Frontmatter:
```yaml
---
name: test-runner
description: Execute GOL tests (unit + integration), parse output, diagnose failures.
  Supports single-test and batch modes across all tiers.
tools: Read, Bash, Glob, Grep
---
```

Read-only agent. No Write tool.

### Shell Hook Scripts

#### block-gdunit-in-integration.sh
PreToolUse hook on Write/Edit tools. Checks if target path is under `tests/integration/` and file content contains `extends GdUnitTestSuite`. Exit 2 (deny) on match.

#### block-sceneconfig-in-unit.sh
PreToolUse hook on Write/Edit tools. Checks if target path is under `tests/unit/` and file content contains `extends SceneConfig`. Exit 2 (deny) on match.

#### settings.local.json
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{
          "type": "command",
          "command": ".claude/hooks/block-gdunit-in-integration.sh"
        }]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [{
          "type": "command",
          "command": ".claude/hooks/block-sceneconfig-in-unit.sh"
        }]
      }
    ]
  }
}
```

### oh-my-opencode.jsonc

```jsonc
{
  "agents": {
    "test-writer-integration": {
      "variant": "high",
      "temperature": 0.05,
      "thinking": { "type": "enabled", "budgetTokens": 15000 },
      "permission": {
        "edit": "allow",
        "write": "allow",
        "bash": {
          "godot* *--headless*": "allow",
          "*": "ask"
        },
        "task": "deny"
      }
    },
    "test-writer-unit": {
      "variant": "medium",
      "temperature": 0.05,
      "thinking": { "type": "enabled", "budgetTokens": 10000 },
      "permission": {
        "edit": "allow",
        "write": "allow",
        "bash": {
          "godot* *--headless*": "allow",
          "*": "ask"
        },
        "task": "deny"
      }
    },
    "test-runner": {
      "variant": "medium",
      "temperature": 0.0,
      "thinking": { "type": "enabled", "budgetTokens": 8000 },
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": {
          "godot* *--headless*": "allow",
          "*": "deny"
        },
        "task": "deny"
      }
    }
  },
  "claude_code": {
    "agents": true,
    "hooks": true
  }
}
```

## Implementation Plan

### Step 1: Normalize existing tests (submodule)
Standardize all integration tests to use base class helpers.

- [ ] Migrate `_find()` → `_find_entity()` in 5 tests:
  - `test_flow_console_spawn_scene.gd`
  - `test_flow_composer_scene.gd`
  - `test_flow_composition_cost_scene.gd`
  - `test_flow_elemental_status_scene.gd`
  - `test_flow_composer_interaction_scene.gd`
- [ ] Remove redundant local `_find_entity()` in 3 tests (already matches base class):
  - `test_bullet_flight.gd`
  - `test_flow_component_drop_scene.gd`
  - `test_flow_blueprint_drop_scene.gd`
- [ ] Fix `test_base_helpers.gd`: replace `call("_find_entity", ...)` with direct `_find_entity(...)`, same for `_wait_frames` and `_find_by_component`
- [ ] Fix `test_flow_player_respawn.gd`: remove local `_find_entity()`, use base class
- [ ] Run all integration tests to verify no regressions
- [ ] Commit + push submodule

### Step 2: Write new agents (management repo)
Create self-contained agent definitions with embedded knowledge.

- [ ] Create `test-writer-integration.md` (~150 lines)
  - Absorb from: `gol-test-integration/SKILL.md` (decision flow, validation, quick ref, mistakes, gotchas)
  - Absorb from: `gol-test/reference/integration-tests.md` (SceneConfig architecture, API)
  - Absorb from: `gol-test/SKILL.md` (system/recipe tables)
  - Add runtime discovery instructions
- [ ] Create `test-writer-unit.md` (~80 lines)
  - Absorb from: `gol-test/reference/unit-tests.md` (template, assertion API, scope rules)
  - Add GOL-specific constraints
- [ ] Rewrite `test-runner.md` (~120 lines)
  - Expand to unified multi-tier dispatch
  - Add gdUnit4 XML parsing + command
  - Keep SceneConfig parsing from v1
- [ ] Delete old `test-writer.md`

### Step 3: Create dispatch skill + hooks (management repo)
Replace routing skill and convert enforcement to native hooks.

- [ ] Create `gol-test-dispatch/SKILL.md` (~60 lines)
  - Absorb from: `gol-test/SKILL.md` (tier decision matrix, run commands, directory structure)
  - Strip: system/recipe tables, gotchas, reference links
  - Add: prompt templates for each writer agent
- [ ] Delete `gol-test/` directory entirely
- [ ] Delete `gol-test-integration/` directory entirely
- [ ] Create `.claude/hooks/block-gdunit-in-integration.sh`
- [ ] Create `.claude/hooks/block-sceneconfig-in-unit.sh`
- [ ] Create `.claude/settings.local.json` with PreToolUse hooks
- [ ] Delete 5 hookify files:
  - `hookify.block-gdunit-in-integration.local.md`
  - `hookify.block-sceneconfig-in-unit.local.md`
  - `hookify.warn-manual-entity-in-integration.local.md`
  - `hookify.warn-null-systems-in-integration.local.md`
  - `hookify.check-integration-test-completeness.local.md`

### Step 4: Update OMO config (management repo)
- [ ] Rewrite `oh-my-opencode.jsonc` with new agent names + `claude_code.hooks: true`
- [ ] Remove platform-specific fields from all agent frontmatter (model, mode)

### Step 5: Verify
- [ ] Spawn test-writer-integration: sample feature → generates valid test → passes
- [ ] Spawn test-writer-unit: sample function → generates valid test → passes
- [ ] Spawn test-runner: "run all" → multi-tier dispatch works
- [ ] Invoke gol-test-dispatch: routes to correct agent
- [ ] Shell hooks: attempt wrong base class in wrong directory → blocked
- [ ] Cross-platform: verify agents load in OpenCode+OMO (if available)

### Step 6: Cleanup + commit
- [ ] Update management repo submodule pointer
- [ ] Commit all management repo changes
- [ ] Push submodule first, then management repo

## Information Flow

```
Main Agent (feature dev / bug fix)
  │
  ├─ invoke gol-test-dispatch skill
  │   → "Multi-system? → Yes → spawn test-writer-integration"
  │   → prompt template filled with feature context
  │
  ├─ spawn test-writer-integration
  │   │ (self-contained, reads codebase on demand)
  │   └─ returns: file path of new test
  │
  ├─ spawn test-runner
  │   │ (identifies tier from file, executes, parses)
  │   └─ returns: PASS/FAIL + structured report
  │
  └─ continues feature work
```
