# Subagent-Driven Test Harness v4 — Design Spec

**Date:** 2026-04-19
**Status:** Draft
**Scope:** Unified test skill architecture + ai-debug enhancements + playtest tier

> Current usage note (2026-05-02): this design predates the `gol` CLI wrapper becoming the supported AI surface. Use `gol run game`, `gol stop`, `gol debug ...`, and `gol debug input ...` in current prompts. Raw `node ai-debug.mjs boot/teardown` references below are historical design context.

## Problem

The current test harness (v3) has three issues:

1. **No playtest tier.** The decision matrix marks playtest as "Not yet available." The only playtest capability is a hardcoded `console-playtester.md` agent that tests 60 specific console commands — it can't verify arbitrary game features.

2. **Skills don't enforce delegation.** AGENTS.md says "main agents never write or run tests directly," but the skills themselves (`gol-test-writer-unit`, `gol-test-writer-integration`, `gol-test-runner`) are operational guides that the main agent executes in its own context. This pollutes the main agent's context window with test tool calls.

3. **Scattered Godot lifecycle management.** Booting, tearing down, and reimporting Godot is done three different ways: foreman's shell scripts (`tester-start-godot.sh`, `tester-cleanup.sh`), ai-debug's Node code, and the console-playtester's inline bash. Each handles PATH, env vars, and error cases differently.

## Solution

Two changes:

1. **Restructure test skills into two subagent-driven skills** (`gol-test-writer`, `gol-test-runner`) where the main agent is the coordinator and all test work is dispatched to subagents via prompt templates.

2. **Enhance ai-debug** with `boot` and `teardown` subcommands and consistent `--path` support, making it the single Godot interaction layer for all AI agents.

## Design

### 1. Skill Architecture

#### Two skills, four prompt templates

```
.claude/skills/
├── gol-test-writer/
│   ├── SKILL.md                        # Main agent: routing + delegation
│   └── references/
│       ├── unit-prompt.md              # Subagent: write gdUnit4 unit tests
│       └── integration-prompt.md       # Subagent: write SceneConfig integration tests
├── gol-test-runner/
│   ├── SKILL.md                        # Main agent: routing + delegation
│   └── references/
│       ├── runner-prompt.md            # Subagent: execute tests, parse output, report
│       └── playtest-prompt.md          # Subagent: boot game, verify feature, report
```

#### SKILL.md pattern (same for both skills)

Each SKILL.md contains:

- **Trigger keywords** for when the skill activates
- **Decision matrix** mapping the task to a tier and prompt template
- **Delegation rules**: "You are the coordinator. Never write/run tests yourself. Dispatch a subagent."
- **Dispatch instructions**: read the prompt template from `references/`, spawn a subagent with the template + task-specific input + CWD
- **Worktree guide**: pass your CWD to the subagent; if in a worktree, the subagent works there too
- **Fix-retest loop**: if the report says FAIL, you decide what's next (fix code, fix tools, re-run, escalate to user)
- **Model selection**: which model to use per tier

Zero operational knowledge about how to write tests, run tests, or interact with Godot. The main agent physically cannot do the work itself.

#### Prompt template pattern (references/*.md)

Each prompt template contains:

- **Identity**: who the subagent is and what it does
- **Tools**: what commands/APIs are available and how to use them
- **Workflow**: step-by-step operational procedure
- **Report format**: structured output the main agent can parse
- **Error handling**: what to do when things go wrong, what to escalate

### 2. gol-test-writer Skill

#### SKILL.md routing

| Need | Tier | Prompt template | Model |
|------|------|-----------------|-------|
| Test a pure function / single component / single class | Unit | `references/unit-prompt.md` | sonnet |
| Test multi-system ECS / needs World / recipe spawning | Integration | `references/integration-prompt.md` | sonnet |

**Trigger keywords:** "write test", "unit test", "integration test", "test component", "test system", "gdUnit4 test", "SceneConfig test"

**Dispatch input:** what to test (file/class under test), any specific behaviors to cover, CWD.

**Report:** subagent returns the complete test file content + file path where it was written.

#### unit-prompt.md

Absorbs the current `gol-test-writer-unit/SKILL.md` content:
- gdUnit4 API reference, assertion chains, base class (`extends GdUnitTestSuite`)
- File location convention (`tests/unit/test_{feature}.gd`)
- Discovery protocol (read class under test, then similar tests)
- Quality rules (behavior vs implementation, edge cases, `auto_free()`)
- Execution command for self-verification

#### integration-prompt.md

Absorbs the current `gol-test-writer-integration/SKILL.md` content:
- SceneConfig API reference, base class (`extends SceneConfig`)
- File location convention (`tests/integration/test_{feature}.gd`)
- Discovery order (systems, similar tests, recipes, components)
- Assertion strategy (existence / presence / progression)
- Common mistakes table
- Execution command for self-verification

### 3. gol-test-runner Skill

#### SKILL.md routing

| Need | Tier | Prompt template | Model |
|------|------|-----------------|-------|
| Run existing unit/integration tests | Runner | `references/runner-prompt.md` | haiku |
| Verify a feature in the running game | Playtest | `references/playtest-prompt.md` | sonnet |

**Trigger keywords:** "run test", "run all tests", "test runner", "playtest", "verify in game", "do playtest", "test in game"

**Dispatch input:**
- **Runner:** which tests to run (specific file, tier, or "all"), CWD
- **Playtest:** what to verify (feature-level description), CWD, optional context (what changed, known issues)

#### runner-prompt.md

Absorbs the current `gol-test-runner/SKILL.md` content:
- Tier detection via `extends` clause
- Two execution commands (gdUnit4 for unit, SceneConfig harness for integration)
- Two output parsers (XML for unit, stdout for integration)
- Failure diagnosis levels (script error / runtime error / logic failure / hang)
- Unified report format table

#### playtest-prompt.md

New content:

**Identity:** You are a playtester for God of Lego. You verify game features by running the game and interacting with it via the AI debug bridge.

**Tools:** `gol` is your only Godot interaction tool. Use `gol debug help` for the live debug command list. Core playtest commands:

| Command | Purpose |
|---------|---------|
| `gol run game --detach -- --skip-menu` | Launch game for agent-friendly playtest |
| `gol stop` | Clean kill of Godot |
| `gol debug console <cmd>` | Run a debug console command |
| `gol debug get <key>` | Get game state (player.pos, player.hp, time, entity_count) |
| `gol debug set <key> <value>` | Set game state |
| `gol debug screenshot` | Capture screenshot, returns file path |
| `gol debug eval <expr>` | Evaluate GDScript expression |
| `gol debug input <op> [action]` | Simulate player input (`actions`, `tap`, `press`, `release`, `hold`) |
| `gol debug script <file>` | Execute a GDScript file from `.debug/scripts/` |
| `gol debug spawn <recipe> [count] [x] [y]` | Spawn entities |
| `gol debug recipes [filter]` | List available recipes |

**Workflow:**
1. Boot: `gol run game --detach -- --skip-menu`
2. Verify: use commands above to verify the feature. You decide which commands, what state to check, what screenshots to take.
3. Teardown: `gol stop` — always, even on failure.

**Verification approach:** You receive a feature-level description. You design the verification — which commands to run, what state to check before and after, what screenshots to capture. Use your knowledge of game mechanics (ECS, components, systems) to design meaningful checks.

**Report format:**
```
VERDICT: PASS | FAIL

Checked:
- <what you verified and how>

Issues (if FAIL):
- <what failed, expected vs actual, hypothesis>

Screenshots: <list of paths if taken>
```

**Error handling:** If boot fails, report FAIL with the boot error. If a command times out, retry once, then report. If something is outside your scope (code bug, tool bug), report it clearly — the main agent decides what to do.

### 4. ai-debug Enhancements

#### New subcommand: `boot`

```
node ai-debug.mjs boot [--path <project-dir>]
```

Sequence:
1. Kill any existing Godot processes (`pkill -f Godot`)
2. Resolve project path: explicit `--path` or `gol-project/` relative to CWD
3. Run `ensureImportCache()` from `godot-import.mjs` (handles reimport if `.godot/` stale)
4. Launch Godot with `--path <resolved>`
5. Poll game readiness every 3s (internally uses the signal directory to check console responsiveness), up to 90s timeout
6. Output: `READY` on success, `TIMEOUT` or `CRASH` with diagnostic on failure

If crash detected (process dies during poll), run headless to capture script errors and include them in the `CRASH` output. The boot command resolves the signal directory internally from the project path — callers don't need to know the userdata convention.

#### New subcommand: `teardown`

```
node ai-debug.mjs teardown
```

Sequence:
1. Graceful kill (`pkill -f Godot`)
2. Wait 2s, verify process gone
3. Force kill if still alive (`pkill -9`)
4. Output: `STOPPED`

#### `--path` flag on existing commands

All commands that resolve the signal directory gain `--path <dir>`:
- `console`, `get`, `set`, `screenshot`, `script`, `reimport`, `eval`, `spawn`, `recipes`

Default: `gol-project/` relative to CWD. The signal directory is derived from the project path via Godot's userdata convention.

### 5. Foreman Migration

Replace shell wrappers with ai-debug calls:

| Old | New |
|-----|-----|
| `bin/tester-start-godot.sh <ws> <scene>` | `node ai-debug.mjs boot --path <ws>` |
| `bin/tester-cleanup.sh` | `node ai-debug.mjs teardown` |
| `bin/tester-ai-debug.sh` | No change (already delegates to ai-debug) |

Update call sites in `foreman-daemon.mjs` and `workspace-manager.mjs`.

Delete `tester-start-godot.sh` and `tester-cleanup.sh` after migration.

### 6. Retirement

| File | Action |
|------|--------|
| `.claude/agents/console-playtester.md` | Delete |
| `.claude/skills/gol-test-writer-unit/` | Delete (absorbed into `gol-test-writer/references/unit-prompt.md`) |
| `.claude/skills/gol-test-writer-integration/` | Delete (absorbed into `gol-test-writer/references/integration-prompt.md`) |
| `.claude/skills/gol-test-runner/` (old) | Replace with new subagent-driven version |
| `gol-tools/foreman/bin/tester-start-godot.sh` | Delete |
| `gol-tools/foreman/bin/tester-cleanup.sh` | Delete |

### 7. AGENTS.md Updates

Update the test harness section in both `gol/AGENTS.md` and `gol-project/tests/AGENTS.md`:

```
**v4 Test Harness — subagent-driven (two skills):**

Main agents NEVER write, run, or playtest directly. Always dispatch via skill:

1. Load the appropriate skill
2. Determine tier from decision matrix
3. Dispatch subagent with the matching prompt template
4. Receive report, decide next action

| Need | Skill | Tier → Prompt | Model |
|------|-------|---------------|-------|
| Write unit test | gol-test-writer | unit → unit-prompt.md | sonnet |
| Write integration test | gol-test-writer | integration → integration-prompt.md | sonnet |
| Run existing tests | gol-test-runner | runner → runner-prompt.md | haiku |
| Verify feature in game (playtest) | gol-test-runner | playtest → playtest-prompt.md | sonnet |
```

Rename all "E2E" references to "playtest" across AGENTS.md files.

## Terminology

- **Playtest** (not E2E): verifying game features by running the game and interacting with it
- **Runner**: executing existing unit/integration test files and parsing results
- **Writer**: authoring new test files

## Out of Scope

- Visual regression testing (screenshot diffing)
- Automated playtest scenario libraries (may add later as more `references/scenarios/` files)
- Changes to gdUnit4 or SceneConfig test frameworks themselves
- Changes to the writer prompt content beyond restructuring (the authoring guides stay the same)
