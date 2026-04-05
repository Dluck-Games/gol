# Integration Test Harness Engineering System

Date: 2026-04-05
Status: Implemented
Scope: Skills, agents, templates, hooks, and base class enhancements for AI-driven SceneConfig integration test generation and execution.

## Problem Statement

GOL has 10 integration tests (1292 lines of GDScript) using the SceneConfig framework. Writing new tests requires deep knowledge of:
- Which systems to register for which features
- How to design recipe-based entities with proper component overrides
- Idiomatic assertion patterns using the limited TestResult API
- Async safety conventions (frame awaits, null guards, early returns)
- Cross-client compatibility (Claude Code + OpenCode/OMO)

Without tooling, AI agents consistently generate broken tests: wrong base class, missing systems, null-unsafe chains, insufficient assertions.

## Solution Overview

A layered harness system:

```
gol/
├── .claude/
│   ├── skills/
│   │   └── gol-test-integration/          # Active generation skill
│   │       ├── SKILL.md                   # Master prompt
│   │       └── reference/
│   │           ├── system-feature-map.md   # Feature → system mapping
│   │           ├── assertion-patterns.md   # Idiomatic TestResult usage
│   │           ├── test-catalog.md         # All 10 existing tests cataloged
│   │           └── validation-checklist.md # Pre/post-write quality gates
│   └── agents/
│       ├── test-writer.md                 # Writes SceneConfig tests
│       └── test-runner.md                 # Executes + diagnoses tests
├── .opencode/
│   └── oh-my-opencode.jsonc              # OMO enhancement layer
└── docs/superpowers/plans/
    └── 2026-04-05-integration-test-harness.md  # This document
```

Plus a submodule enhancement: helper methods added to SceneConfig base class.

## Architecture Decisions

### Decision 1: Dual-Layer Skill Design
**Chosen:** Separate active-generation skill (`gol-test-integration`) from read-only reference (`gol-test`)
**Reasoning:** Existing `gol-test` is a reference reader (how to RUN tests). New skill is a generator (how to WRITE tests). Different concerns, different prompts.

### Decision 2: Template-Based Generation
**Chosen:** 5 templates covering all observed pattern clusters
- minimal.gd — Bare skeleton (starting point)
- combat-flow.gd — Damage/HP/survival patterns
- component-flow.gd — Kill→drop→pickup cycles
- pcg-pipeline.gd — PCG map generation
- ui-interaction.gd — UI/node-tree/input simulation
**Reasoning:** Templates reduce hallucination risk by providing working code scaffolds.

### Decision 3: Cross-Client Agent Definitions
**Chosen:** `.claude/agents/*.md` for shared identity + `.opencode/oh-my-opencode.jsonc` for OMO tuning
**Reasoning:** Per the opencode-subagent-config-strategy report, this dual-layer approach ensures compatibility with both Claude Code (reads .claude/agents/) and OpenCode+OMO (same loader + enhancement layer).

### Decision 4: Model Assignment
**Chosen:** glm-5v-turbo-ioa (default model) for both agents
**Reasoning:** Code generation quality benefits from larger context window and stronger reasoning.

### Decision 5: Base Class Enhancement
**Chosen:** Add _find_entity(), _wait_frames(), _find_by_component() to SceneConfig
**Reasoning:** 8/10 tests copy-paste identical _find(). Extracting to base class reduces boilerplate and ensures consistency. Backward compatible (existing local helpers shadow base method via GDScript MRO).

### Decision 6: Hookify Rules
**Chosen:** Both skill-embedded checklist + Hookify hard-block rules
**Reasoning:** Belt-and-suspenders. Checklist guides agents, hookify rules catch mistakes that slip through.

## Deliverables

### Wave 1: Foundation References (4 files)
1. **system-feature-map.md** — 20 systems mapped to features, components, dependencies
2. **assertion-patterns.md** — 7 patterns from 10 tests + anti-patterns
3. **test-catalog.md** — Full catalog of all 10 tests with detailed analysis
4. **validation-checklist.md** — 30+ checks across pre-write, post-write, execution phases

### Wave 2: Templates + Skill (6 files)
5. **templates/minimal.gd** — 35-line bare skeleton
6. **templates/combat-flow.gd** — 75-line combat pattern
7. **templates/component-flow.gd** — 100-line drop/pickup cycle
8. **templates/pcg-pipeline.gd** — 45-line PCG pattern
9. **templates/ui-interaction.gd** — 120-line UI pattern
10. **SKILL.md** — Master generation skill importing all references

### Wave 3: Agent Definitions (3 files)
11. **test-writer.md** — Subagent: writes tests from feature descriptions
12. **test-runner.md** — Subagent: executes tests, parses output, diagnoses failures
13. **oh-my-opencode.jsonc** — OMO enhancement: variant, permissions, thinking budget

### Wave 3c: Hookify Rules
14. Hookify rules blocking anti-patterns in tests/integration/

### Wave 4: Base Class Enhancement (submodule)
15. SceneConfig._find_entity() — Name-based entity lookup
16. SceneConfig._wait_frames() — Frame delay helper
17. SceneConfig._find_by_component() — Component-type entity search
18. Verification test using new helpers

## Usage

### Writing a New Integration Test

**Via Agent (recommended):**
```
Delegate to test-writer agent with:
- Feature description: "SFireBullet system creates projectiles that deal damage on impact"
- Context: "New system, no existing tests yet"
Agent produces: tests/integration/test_fire_bullet.gd
```

**Via Skill (manual):**
```
Invoke gol-test-integration skill, follow decision flow:
1. Confirm integration tier (needs World? yes)
2. Map feature → systems (s_fire_bullet, s_damage, s_hp, s_dead)
3. Select pattern (combat-flow variant)
4. Design entities (player + enemy_in_range)
5. Write assertions (projectile spawned, damage dealt, enemy HP reduced)
6. Validate against checklist
7. Run test, verify exit code 0
```

### Running Tests

**Single test:**
```bash
cd gol-project
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --scene scenes/tests/test_main.tscn \
  -- --config=res://tests/integration/MY_TEST.gd
```

**All tests:**
```bash
cd gol  # management repo
./shortcuts/run-tests.command
```

**Via test-runner agent:**
Delegate to test-runner agent with file path or "run all".

## Compatibility Matrix

| Client | Agent Loading | Skill Injection | Permission Control |
|--------|--------------|-----------------|-------------------|
| Claude Code | ✅ .claude/agents/*.md | ✅ Via tools/allowed-tools | ✅ YAML frontmatter |
| OpenCode+OMO | ✅ Same .claude/agents/*.md (OMO auto-loader) | ✅ OMO skills injection | ✅ oh-my-opencode.jsonc |
| Plain OpenCode | ✅ .opencode/agents/*.md (native) | ❌ Not supported | ✅ Native agent schema |

## Future Work

- [ ] TDD template generation (write failing test → implement feature → test passes)
- [ ] Coverage analysis (which systems/features have no integration tests)
- [ ] Regression test generation from git blame (when was this last tested?)
- [ ] Visual diff integration (compare game states before/after test)
- [ ] E2E test harness extension (ephemeral AI Debug Bridge scripts)

<!-- OMO_INTERNAL_INITIATOR -->
