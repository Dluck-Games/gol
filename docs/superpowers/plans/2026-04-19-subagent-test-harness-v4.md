# Subagent-Driven Test Harness v4 — Implementation Plan

> Current usage note (2026-05-02): this historical plan predates the `gol` CLI wrapper becoming the supported AI surface. Current playtest flows use `gol run game`, `gol stop`, `gol debug ...`, and `gol debug input ...`; raw `node ai-debug.mjs boot/teardown` references below are superseded.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the test harness from three separate skills into two subagent-driven skills (gol-test-writer, gol-test-runner), add `boot`/`teardown` commands and `--path` support to ai-debug, migrate foreman off shell wrappers, and retire obsolete files.

**Architecture:** Two coordinator skills (SKILL.md) each dispatch subagents via prompt templates in `references/`. The ai-debug CLI becomes the single Godot lifecycle layer — boot, teardown, and all commands gain `--path` support. Foreman replaces shell scripts with direct `node ai-debug.mjs boot/teardown` calls.

**Tech Stack:** Node.js (ai-debug), Markdown (skills/prompts), Bash (foreman permissions)

---

## File Structure

### New files

```
# Skills (in gol-project/.claude/skills/ — but skills live at management repo level)
.claude/skills/gol-test-writer/
├── SKILL.md                              # Coordinator: routing + delegation
└── references/
    ├── unit-prompt.md                    # Subagent prompt: write gdUnit4 unit tests
    └── integration-prompt.md             # Subagent prompt: write SceneConfig integration tests

.claude/skills/gol-test-runner/
├── SKILL.md                              # Coordinator: routing + delegation (replaces old)
└── references/
    ├── runner-prompt.md                  # Subagent prompt: execute tests + parse + report
    └── playtest-prompt.md                # Subagent prompt: boot game + verify feature + report
```

### Modified files

```
gol-tools/ai-debug/ai-debug.mjs          # Add boot, teardown commands + --path flag
gol-tools/ai-debug/lib/godot-import.mjs   # No changes needed (ensureImportCache already exists)
gol-tools/foreman/foreman-daemon.mjs       # Replace tester script refs with ai-debug calls
gol-tools/foreman/prompts/tasks/tester/e2e-acceptance.md  # Replace shell script refs with ai-debug
AGENTS.md                                  # Update test harness section to v4
gol-project/tests/AGENTS.md               # Update test harness section to v4
```

### Deleted files

```
.claude/skills/gol-test-writer-unit/SKILL.md
.claude/skills/gol-test-writer-integration/SKILL.md
.claude/skills/gol-test-runner/SKILL.md          # Old version (replaced by new directory structure)
.claude/agents/console-playtester.md
gol-tools/foreman/bin/tester-start-godot.sh
gol-tools/foreman/bin/tester-cleanup.sh
```

---

## Task 1: Add `boot` command to ai-debug

**Files:**
- Modify: `gol-tools/ai-debug/ai-debug.mjs`

This task adds the `boot` subcommand that kills existing Godot, ensures import cache, launches Godot, and polls for readiness.

- [ ] **Step 1: Add `--path` flag parsing to `parseFlags()`**

In `ai-debug.mjs`, extend `parseFlags()` to recognize `--path`:

```javascript
// Inside parseFlags(), add this case before the else branch:
} else if (args[i] === '--path' || args[i] === '-p') {
    flags.path = args[++i];
    i++;
}
```

- [ ] **Step 2: Add `resolveProjectPath()` helper**

Add after the `resolveRuntimePaths()` function (around line 74):

```javascript
export function resolveProjectPath(explicitPath) {
    if (explicitPath) {
        const resolved = path.resolve(explicitPath);
        if (!fs.existsSync(path.join(resolved, 'project.godot'))) {
            throw new Error(`Not a Godot project: ${resolved}`);
        }
        return resolved;
    }
    return PROJECT_DIR;
}

export function resolveSignalDir(projectPath) {
    const projectName = 'God of Lego';
    const platform = os.platform();
    let base;
    switch (platform) {
        case 'darwin':
            base = path.join(os.homedir(), 'Library/Application Support/Godot/app_userdata', projectName);
            break;
        case 'win32':
            base = path.join(os.homedir(), 'AppData/Roaming/Godot/app_userdata', projectName);
            break;
        default:
            base = path.join(os.homedir(), '.local/share/godot/app_userdata', projectName);
    }
    return path.join(base, 'ai_signals');
}
```

Note: Godot's userdata path is derived from the `application/config/name` in `project.godot`, which is always "God of Lego" for this project. The signal directory is always the same regardless of `--path`. The `--path` flag controls which project directory Godot opens, not where signals go. This means the existing hardcoded `SIGNAL_DIR` remains correct for all commands. The `resolveProjectPath()` helper is used by `boot` and `teardown` to know which directory to pass to Godot.

- [ ] **Step 3: Add `boot` command handler**

Add after the `reimportAssets()` function (around line 373):

```javascript
async function bootGodot(projectDir) {
    const { execFileSync, spawn: spawnProcess } = await import('child_process');

    // Step 1: Kill existing Godot
    try { execFileSync('pkill', ['-f', 'Godot'], { stdio: 'ignore' }); } catch {}
    await new Promise(r => setTimeout(r, 2000));

    // Step 2: Resolve project path
    projectDir = resolveProjectPath(projectDir);

    // Step 3: Ensure import cache
    console.error(`Ensuring import cache for ${projectDir}...`);
    await ensureImportCache(projectDir);

    // Step 4: Launch Godot
    console.error(`Launching Godot with --path ${projectDir}...`);
    const godot = spawnProcess(GODOT_PATH, ['--path', projectDir], {
        stdio: ['ignore', 'ignore', 'ignore'],
        detached: true,
    });
    godot.unref();

    // Step 5: Poll for readiness
    const maxWaitMs = 90000;
    const pollIntervalMs = 3000;
    const startTime = Date.now();

    await ensureSignalDir();

    while (Date.now() - startTime < maxWaitMs) {
        await new Promise(r => setTimeout(r, pollIntervalMs));

        // Check if process died
        try {
            execFileSync('pgrep', ['-f', 'Godot'], { stdio: 'ignore' });
        } catch {
            // Process died — run headless to capture errors
            console.error('Godot process died during boot. Capturing errors...');
            let errors = '';
            try {
                const result = execFileSync(GODOT_PATH, [
                    '--headless', '--path', projectDir, '--quit'
                ], { timeout: 30000, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
                errors = result;
            } catch (e) {
                errors = e.stderr || e.stdout || e.message;
            }
            return `CRASH\n${errors}`;
        }

        // Check console responsiveness via signal file
        try {
            cleanupStaleFiles();
            fs.writeFileSync(COMMAND_FILE, JSON.stringify({ cmd: 'help', args: [] }));
            await new Promise(r => setTimeout(r, 2000));
            if (fs.existsSync(RESULT_FILE)) {
                fs.unlinkSync(RESULT_FILE);
                return 'READY';
            }
        } catch {
            // Not ready yet, continue polling
        }
    }

    return 'TIMEOUT';
}
```

- [ ] **Step 4: Add `boot` route to `resolveCommand()`**

Add a new case in the `resolveCommand()` switch, before the `default` case:

```javascript
case 'boot':
    return { type: 'boot', projectDir: flags.path || positional[0] || null };

case 'teardown':
    return { type: 'teardown' };
```

- [ ] **Step 5: Add `boot` handler to `main()` switch**

In the `main()` function's switch on `route.type`, add:

```javascript
case 'boot':
    result = await bootGodot(route.projectDir);
    break;

case 'teardown':
    result = await teardownGodot();
    break;
```

- [ ] **Step 6: Update HELP_TEXT**

Add to the special commands section of `HELP_TEXT`:

```
  boot [--path <dir>]              Kill Godot, reimport if needed, launch, poll until ready
  teardown                         Clean kill of Godot
```

- [ ] **Step 7: Verify boot command works manually**

Run from the management repo root:
```bash
cd /Users/dluck/Documents/GitHub/gol
node gol-tools/ai-debug/ai-debug.mjs boot --path gol-project
```
Expected: `READY` after 15-30 seconds, or `TIMEOUT`/`CRASH` with diagnostics.

Then clean up:
```bash
node gol-tools/ai-debug/ai-debug.mjs teardown
```
Expected: `STOPPED`

- [ ] **Step 8: Commit**

```bash
git add gol-tools/ai-debug/ai-debug.mjs
git commit -m "feat(ai-debug): add boot and teardown commands"
```

---

## Task 2: Add `teardown` command to ai-debug

**Files:**
- Modify: `gol-tools/ai-debug/ai-debug.mjs`

- [ ] **Step 1: Add `teardownGodot()` function**

Add after the `bootGodot()` function:

```javascript
async function teardownGodot() {
    const { execFileSync } = await import('child_process');

    // Graceful kill
    try { execFileSync('pkill', ['-f', 'Godot'], { stdio: 'ignore' }); } catch {}

    // Wait and verify
    await new Promise(r => setTimeout(r, 2000));

    // Check if still alive
    try {
        execFileSync('pgrep', ['-f', 'Godot'], { stdio: 'ignore' });
        // Still alive — force kill
        try { execFileSync('pkill', ['-9', '-f', 'Godot'], { stdio: 'ignore' }); } catch {}
        await new Promise(r => setTimeout(r, 1000));
    } catch {
        // Already dead — good
    }

    return 'STOPPED';
}
```

Note: The `teardown` route and handler in `resolveCommand()` and `main()` were already added in Task 1, Steps 4 and 5.

- [ ] **Step 2: Verify teardown works**

```bash
node gol-tools/ai-debug/ai-debug.mjs teardown
```
Expected: `STOPPED`

- [ ] **Step 3: Commit**

```bash
git add gol-tools/ai-debug/ai-debug.mjs
git commit -m "feat(ai-debug): add teardown command for clean Godot shutdown"
```

---

## Task 3: Add `--path` support to existing ai-debug commands

**Files:**
- Modify: `gol-tools/ai-debug/ai-debug.mjs`

The `--path` flag was already parsed in Task 1. Now we need to make the signal directory resolution use it. However, as noted in Task 1 Step 2, the signal directory is always the same for "God of Lego" regardless of project path — Godot derives userdata from the project name in `project.godot`, not the filesystem path. So `--path` only affects `boot` (which directory to launch) and `reimport` (which directory to import). The signal directory for IPC is always `~/Library/Application Support/Godot/app_userdata/God of Lego/ai_signals/`.

This means existing commands (`console`, `get`, `set`, `screenshot`, `script`, `eval`, `spawn`, `recipes`) already work correctly regardless of `--path`. The `--path` flag is parsed but only consumed by `boot` and `reimport`.

- [ ] **Step 1: Update `reimport` route to accept `--path`**

In `resolveCommand()`, update the reimport case:

```javascript
case 'reimport':
    return { type: 'reimport', projectDir: flags.path || positional[0] || null };
```

This is already the current behavior for positional args, but now also accepts `--path`.

- [ ] **Step 2: Document `--path` in HELP_TEXT**

Update the help text to mention `--path` on relevant commands:

```
  boot [--path <dir>]              Kill Godot, reimport if needed, launch, poll until ready
  teardown                         Clean kill of Godot
  reimport [--path <dir>]          Stop game, clear import cache, reimport

Flags:
  --path, -p <dir>    Godot project directory (default: gol-project/ relative to CWD)
```

- [ ] **Step 3: Commit**

```bash
git add gol-tools/ai-debug/ai-debug.mjs
git commit -m "feat(ai-debug): add --path flag support for boot and reimport"
```

---

## Task 4: Create gol-test-writer skill — SKILL.md coordinator

**Files:**
- Create: `.claude/skills/gol-test-writer/SKILL.md`

- [ ] **Step 1: Create the directory structure**

```bash
mkdir -p .claude/skills/gol-test-writer/references
```

- [ ] **Step 2: Write SKILL.md**

Create `.claude/skills/gol-test-writer/SKILL.md`:

```markdown
# gol-test-writer

Coordinator skill for writing GOL tests. Routes to the correct tier and dispatches a subagent with the matching prompt template.

Triggers: 'write test', 'unit test', 'integration test', 'test component', 'test system', 'gdUnit4 test', 'SceneConfig test'.

## You Are the Coordinator

You are the main agent. You **never** write test files yourself. Your job:

1. Determine the correct tier
2. Read the matching prompt template from `references/`
3. Dispatch a subagent with the template + task-specific context
4. Receive the subagent's report (test file path + content)
5. If the report indicates issues, decide next action (fix code, re-dispatch, escalate)

## Decision Matrix

| Need | Tier | Prompt Template | Model |
|------|------|-----------------|-------|
| Pure function / single component / single class | Unit | `references/unit-prompt.md` | sonnet |
| Multi-system ECS / needs World / recipe spawning | Integration | `references/integration-prompt.md` | sonnet |

### Routing rules

- If the scenario needs a `World`, `ECS.world`, `GOLWorld`, or recipe spawning → **Integration**
- If the scenario tests a single class, component, or pure function in isolation → **Unit**
- If unclear, ask the user before dispatching

## Dispatch Protocol

1. Read the prompt template: `references/<tier>-prompt.md`
2. Spawn a subagent (model: sonnet) with this prompt structure:

```
<prompt-template>
{contents of references/<tier>-prompt.md}
</prompt-template>

<task>
What to test: {description from user}
Class/file under test: {file path if known}
Specific behaviors to cover: {from user request}
Working directory: {your CWD}
Project directory: {path to gol-project/ or worktree}
</task>
```

3. The subagent returns: test file path + complete test file content
4. Verify the file was written to the correct directory (`tests/unit/` or `tests/integration/`)

## Worktree Support

Pass your current working directory to the subagent. If you're in a worktree, the subagent works there too. The subagent resolves all paths relative to the CWD it receives.

## After Dispatch

- If the subagent succeeds: report the test file path to the user
- If the subagent reports issues: decide whether to fix the code under test, adjust the test request, or escalate
- To run the test: use the `gol-test-runner` skill (separate dispatch)

## What You Do NOT Do

- Write test files
- Read test framework documentation
- Run test commands
- Interact with Godot
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/gol-test-writer/SKILL.md
git commit -m "feat(skills): add gol-test-writer coordinator SKILL.md"
```

---

## Task 5: Create gol-test-writer unit prompt template

**Files:**
- Create: `.claude/skills/gol-test-writer/references/unit-prompt.md`

This absorbs the content from the existing `gol-test-writer-unit/SKILL.md`.

- [ ] **Step 1: Write unit-prompt.md**

Create `.claude/skills/gol-test-writer/references/unit-prompt.md`:

```markdown
# Unit Test Writer — Subagent Prompt

You are a test writer subagent for God of Lego (Godot 4.6, GDScript). You write gdUnit4 unit tests.

## Identity

You write complete, runnable gdUnit4 unit test files. You receive a description of what to test and you deliver a finished test file. You do not run tests — that's the runner's job.

## Tools

You have access to: Read, Write, Glob, Grep, Bash (read-only commands only).

Use these to discover project details before writing:

1. **Target class first** — read the class under test and any direct dependencies
2. **Similar tests** — glob `tests/unit/**/*.gd`, read 1-2 nearby tests as scaffolds
3. **Assertion style** — copy real gdUnit4 assertion chains already used in this repo

Never guess method names, field names, or assertion APIs when the codebase can confirm them.

## Scope

- Location: `tests/unit/`
- Naming: `test_{feature}.gd`
- Base class: `extends GdUnitTestSuite`
- Test functions: `func test_NAME()`

### Valid unit targets

- Pure functions
- Single component behavior
- Single system `process()` logic with manual entity construction
- Single-class state transitions

### NOT unit tests (escalate back to coordinator)

- Multi-system interaction
- Any behavior that needs a `World`
- Rendering/UI flows
- Recipe spawning

If the scenario needs recipe entities or a realized ECS world, report back that this belongs in integration tier.

## gdUnit4 Basics

- Base class: `extends GdUnitTestSuite`
- Test functions: `func test_NAME()`
- Cleanup helper: `auto_free(obj)`
- Lifecycle hooks: `before()`, `after()`, `before_test()`, `after_test()`

## Assertion API Reference

- `assert_object(obj).is_not_null()`
- `assert_object(obj).is_same(other)`
- `assert_int(value).is_equal(expected)`
- `assert_float(value).is_equal(expected)`
- `assert_float(value).is_equal_approx(expected, tolerance)`
- `assert_str(value).is_equal(expected)`
- `assert_array(arr).is_not_empty()`
- `assert_array(arr).has_size(expected)`
- `assert_array(arr).contains(value)`
- `assert_bool(true).is_true()`
- `assert_bool(false).is_false()`
- `assert_dict(dict).is_equal(expected)`
- `assert_signal(obj).is_emitted("signal_name")`
- `assert_that(value)`
- `fail("message")`

## Testing Patterns

### Component

1. `new()` the component
2. Set properties
3. Assert resulting values

### System

1. Create `Entity.new()` manually
2. Add required components with `entity.add_component()`
3. Call the system method under test
4. Assert changed component state

### Pure function

1. Input
2. Output
3. Assert expected result
4. Include edge cases

## GOL Project Constraints

- No World access
- No ECS recipe spawning
- Import project classes directly, e.g. `var comp: CHP = CHP.new()`

## Quality Rules

- Prefer behavior assertions over implementation-detail assertions
- Include edge cases: zero, negative, empty, null-like inputs when applicable
- Keep each test focused on one behavior
- Use static typing where possible
- Use `auto_free()` when temporary objects need cleanup

## Execution Command (for self-verification)

```bash
$GODOT --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/$FILE --ignoreHeadlessMode
```

Results are written to `reports/results.xml`.

## Workflow

1. Read the `<task>` block to understand what to test
2. Discover: read the class under test, find similar tests, confirm assertion APIs
3. Write the complete test file to `tests/unit/test_{feature}.gd`
4. Self-verify by running the execution command above
5. Report results

## Report Format

```
FILE: tests/unit/test_{feature}.gd
STATUS: WRITTEN | ERROR
SELF_CHECK: PASS | FAIL | SKIPPED
NOTES: {any issues, assumptions, or escalations}
```

## Error Handling

- If the class under test doesn't exist at the given path, report back with the error
- If you discover the scenario needs a World (integration tier), report back: "ESCALATE: requires integration tier"
- If self-verification fails, include the failure output in your report but still deliver the test file
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/gol-test-writer/references/unit-prompt.md
git commit -m "feat(skills): add unit test writer prompt template"
```

---

## Task 6: Create gol-test-writer integration prompt template

**Files:**
- Create: `.claude/skills/gol-test-writer/references/integration-prompt.md`

This absorbs the content from the existing `gol-test-writer-integration/SKILL.md`.

- [ ] **Step 1: Write integration-prompt.md**

Create `.claude/skills/gol-test-writer/references/integration-prompt.md`:

```markdown
# Integration Test Writer — Subagent Prompt

You are a test writer subagent for God of Lego (Godot 4.6, GDScript). You write SceneConfig integration tests.

## Identity

You write complete, runnable SceneConfig integration test files. You receive a description of what to test and you deliver a finished test file. You do not run tests — that's the runner's job.

## Tools

You have access to: Read, Write, Glob, Grep, Bash (read-only commands only).

Use these to discover project details before writing:

1. **Systems** — read `scripts/systems/AGENTS.md`, then read the needed `s_*.gd` files
2. **Similar tests** — glob `tests/integration/**/*.gd`, read 1-2 nearby tests as scaffolds
3. **Recipes** — glob `resources/recipes/*.tres`
4. **Components** — read the specific `c_*.gd` files used by the scenario

Never guess recipe contents, component fields, or system side effects when the codebase can confirm them.

## Scope

- Location: `tests/integration/`
- Naming: `test_{feature}.gd`
- Base class: `extends SceneConfig`
- Targets real ECS behavior in a realized `GOLWorld`

### Use This Tier When

- The scenario needs a real World
- Multiple systems interact
- The behavior depends on recipes, spawned entities, or ECS progression
- The test must verify runtime state changes instead of pure function output

### NOT integration tests (escalate back to coordinator)

- Isolated component checks or pure functions → unit tier
- Needs live game with rendering → playtest tier

## SceneConfig Architecture

`test_main.tscn` loads a config script that extends `SceneConfig`.

- `scene_name()` provides the scene name used by the default `scene_path()`
- `systems()` returns `Variant`: `null` for default loading or an explicit array of system script paths
- `enable_pcg()` controls whether PCG runs before the scene loads
- `pcg_config()` returns a cached `PCGConfig` instance
- `entities()` returns `Variant`: `null` or an array of entity dictionaries
- Each entity dictionary uses `{ "recipe": String, "name": String, "components": Dictionary }`
- The harness creates a realized `GOLWorld`, optionally runs PCG, and spawns those recipe entities
- `test_run(world)` executes the scenario and should return `TestResult`

## SceneConfig API

| Member | Signature / Type | Notes |
|---|---|---|
| `scene_name` | `func scene_name() -> String` | Override in tests; base pushes error and returns `""` |
| `scene_path` | `func scene_path() -> String` | Default: `res://scenes/maps/l_%s.tscn` % `scene_name()` |
| `systems` | `func systems() -> Variant` | Return `null` or array of system script paths |
| `enable_pcg` | `func enable_pcg() -> bool` | Default `true` |
| `pcg_config` | `func pcg_config() -> PCGConfig` | Returns cached `PCGConfig.new()` |
| `entities` | `func entities() -> Variant` | Return `null` or array of entity dictionaries |
| `test_run` | `func test_run(_world: GOLWorld) -> Variant` | Main test entry point |
| `_find_entity` | `func _find_entity(world: GOLWorld, entity_name: String) -> Entity` | Helper lookup by name |
| `_wait_frames` | `func _wait_frames(world: GOLWorld, count: int) -> void` | Helper for frame progression |
| `_find_by_component` | `func _find_by_component(world: GOLWorld, component_class: GDScript) -> Array[Entity]` | Helper lookup by component |

### Real tests override

| Override | Purpose | Rule |
|---|---|---|
| `func scene_name() -> String` | Scene name | Return `"test"` |
| `func systems() -> Variant` | Explicit system list | Return array of script paths |
| `func enable_pcg() -> bool` | PCG on/off | Gameplay tests usually return `false` |
| `func entities() -> Variant` | Recipe entities | Return array of dictionaries |
| `func test_run(world: GOLWorld) -> Variant` | Assertions | Return `TestResult` |

## Core Rules

1. **Always spawn via recipe entity dictionaries.** Never use `EntityConfig`; real tests use dictionaries.
2. **Write at least 3 assertions.** Minimum: existence → component presence → value/state change.
3. **Guard `_find_entity()` results.** Null guard and fail early.
4. **Advance frames explicitly.** Use `_wait_frames()` when systems need time to run.
5. **Use static typing everywhere.**

## Assertion Strategy

Strong tests verify all three layers:

1. **Existence** — expected entity was spawned
2. **Presence** — expected component exists
3. **Progression** — HP, status, drop state, or other value changes

## Common Mistakes

| Mistake | Fix |
|---|---|
| Using `Entity.new()` instead of recipe spawning | Use recipe entity dictionaries |
| Forgetting null guard after `_find_entity()` | Guard immediately |
| Not waiting enough frames for async systems | Add `_wait_frames()` |
| Only testing existence | Add progression/value assertions |
| Using implicit system loading | Return explicit system array |
| Documenting nonexistent `setup(world)` hook | Put setup in `test_run(world)` |
| Hardcoded entity indices | Lookup by stable entity name |

## Gotchas

- GECS uses deep-copy semantics; spawned mutations do not mutate templates
- `World.entities` is an `Array`; order follows spawn sequence, not a stable sort
- Recipe defaults may differ from expectations; verify before asserting
- Some enemy recipes do NOT include `CWeapon`; check before assuming combat
- SceneConfig runs headless; no rendering or organic input

## Execution Command (for self-verification)

```bash
$GODOT --headless --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/$FILE
```

## Workflow

1. Read the `<task>` block to understand what to test
2. Discover: read systems, similar tests, recipes, components
3. Map scenario: required systems, entities, setup actions, assertions
4. Write the complete test file to `tests/integration/test_{feature}.gd`
5. Self-verify by running the execution command above
6. Report results

## Report Format

```
FILE: tests/integration/test_{feature}.gd
STATUS: WRITTEN | ERROR
SELF_CHECK: PASS | FAIL | SKIPPED
SYSTEMS: [list of systems used]
ENTITIES: [list of recipe entities spawned]
ASSERTIONS: [summary of assertion plan]
NOTES: {any issues, assumptions, or escalations}
```

## Error Handling

- If required systems/recipes don't exist, report back with the error
- If you discover the scenario is pure isolation (unit tier), report: "ESCALATE: belongs in unit tier"
- If self-verification fails, include the failure output but still deliver the test file
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/gol-test-writer/references/integration-prompt.md
git commit -m "feat(skills): add integration test writer prompt template"
```

---

## Task 7: Create gol-test-runner skill — SKILL.md coordinator

**Files:**
- Create: `.claude/skills/gol-test-runner/SKILL.md` (new version, replaces old)
- Create: `.claude/skills/gol-test-runner/references/` directory

Since the old `gol-test-runner/SKILL.md` is a flat file (no subdirectories), we need to:
1. Delete the old SKILL.md
2. Create the new directory structure with SKILL.md + references/

- [ ] **Step 1: Back up and remove old SKILL.md**

```bash
rm .claude/skills/gol-test-runner/SKILL.md
mkdir -p .claude/skills/gol-test-runner/references
```

- [ ] **Step 2: Write new SKILL.md**

Create `.claude/skills/gol-test-runner/SKILL.md`:

```markdown
# gol-test-runner

Coordinator skill for running GOL tests and playtesting. Routes to the correct tier and dispatches a subagent with the matching prompt template.

Triggers: 'run test', 'run all tests', 'test runner', 'playtest', 'verify in game', 'do playtest', 'test in game'.

## You Are the Coordinator

You are the main agent. You **never** run tests or interact with Godot yourself. Your job:

1. Determine the correct tier (runner vs playtest)
2. Read the matching prompt template from `references/`
3. Dispatch a subagent with the template + task-specific context
4. Receive the subagent's report
5. If FAIL: decide next action (fix code, fix test, re-run, escalate to user)

## Decision Matrix

| Need | Tier | Prompt Template | Model |
|------|------|-----------------|-------|
| Run existing unit/integration tests | Runner | `references/runner-prompt.md` | haiku |
| Verify a feature in the running game | Playtest | `references/playtest-prompt.md` | sonnet |

### Routing rules

- If the user says "run tests", "run unit tests", "run integration tests", "run all tests" → **Runner**
- If the user says "playtest", "verify in game", "test in game", "check if it works" → **Playtest**
- If the user says "run tests and playtest" → dispatch **both** sequentially (runner first, then playtest)

## Dispatch Protocol

### Runner dispatch

Spawn a subagent (model: haiku) with:

```
<prompt-template>
{contents of references/runner-prompt.md}
</prompt-template>

<task>
What to run: {specific file, tier, or "all"}
Working directory: {your CWD}
Project directory: {path to gol-project/ or worktree}
</task>
```

### Playtest dispatch

Spawn a subagent (model: sonnet) with:

```
<prompt-template>
{contents of references/playtest-prompt.md}
</prompt-template>

<task>
What to verify: {feature-level description}
Working directory: {your CWD}
Project directory: {path to gol-project/ or worktree}
Context: {what changed, known issues, relevant systems}
</task>
```

## Worktree Support

Pass your current working directory to the subagent. If you're in a worktree, the subagent works there too.

## Fix-Retest Loop

When a report says FAIL:

1. **Runner FAIL**: Read the failure diagnosis. If it's a test bug, fix the test. If it's a code bug, fix the code. Then re-dispatch the runner.
2. **Playtest FAIL**: Read the issues. If it's a code bug, fix the code and re-dispatch playtest. If it's a tool/environment issue, report to user.
3. **Max retries**: 2 re-dispatches per tier. After that, escalate to user with full report.

## What You Do NOT Do

- Run test commands
- Parse test output
- Launch or kill Godot
- Write test files (use gol-test-writer for that)
- Read test framework documentation
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/gol-test-runner/SKILL.md
git commit -m "feat(skills): replace gol-test-runner with subagent-driven coordinator"
```

---

## Task 8: Create gol-test-runner runner prompt template

**Files:**
- Create: `.claude/skills/gol-test-runner/references/runner-prompt.md`

This absorbs the content from the old `gol-test-runner/SKILL.md`.

- [ ] **Step 1: Write runner-prompt.md**

Create `.claude/skills/gol-test-runner/references/runner-prompt.md`:

```markdown
# Test Runner — Subagent Prompt

You are a test runner subagent for God of Lego (Godot 4.6, GDScript). You execute tests, parse output, diagnose failures, and return a structured report.

## Identity

You run existing test files, parse their output, classify any failures, and report results. You never write or modify test files.

## Tools

You have access to: Bash, Read, Glob, Grep.

## Tier Identification

Read the test file and inspect the `extends` clause:

| Clause | Tier |
|---|---|
| `extends GdUnitTestSuite` | Unit |
| `extends SceneConfig` | Integration |

If neither matches, report the file as unsupported.

## Execution Commands

Run from the Godot project root (the `<project-directory>` from the task block).

```bash
# Unit (gdUnit4)
$GODOT --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/$FILE --ignoreHeadlessMode

# Integration (SceneConfig)
$GODOT --headless --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/$FILE
```

`$GODOT` resolves to the Godot binary on PATH.

## Modes

### Single test

1. Read the file
2. Detect tier from `extends`
3. Run the tier-appropriate command
4. Parse output
5. Report

### Batch

1. Discover tests under `tests/unit/**/*.gd` and `tests/integration/**/*.gd`
2. Detect each file's tier
3. Execute sequentially
4. Aggregate into one summary

For integration tests, trust the process exit code for final pass/fail.

## Output Parsers

### Unit — gdUnit4

Parse `reports/results.xml`:
- `/testsuite` counts
- `failures` attribute count
- `/testsuite/testcase` elements
- Failure message nodes

Extract: total, pass/fail/error counts, testcase names, failure messages.

### Integration — SceneConfig

Parse stdout and exit code:

```text
[test_main] Loaded config: res://tests/integration/test_XXX.gd (scene: test)
[PASS] Entity exists after initialization
[FAIL] Enemy took damage — expected: 80, got: 100
=== 1/2 passed ===
```

Also handle harness-level failures:
```text
[FAIL] Missing --config= argument
[FAIL] Config script not found: ...
[FAIL] Config script does not extend SceneConfig: ...
[FAIL] PCG generation failed
```

Extract: info line, [PASS]/[FAIL] lines, summary line, exit code (0=pass, 1=fail).

## Failure Diagnosis

Classify every non-pass result:

### Level 1 — Script error
Syntax/load/parse failure before test runs. Report error message and `file:line`.

### Level 2 — Runtime error
Null reference, type mismatch, traceback during execution. Report stderr and likely call site.

### Level 3 — Logic failure
Test completed but assertion failed. Report testcase name and expected vs actual.

### Level 4 — Hang
No output or timeout. Report timeout duration, last output, suggest reducing scope.

## Report Format

```
══ Test Run Summary ══════════════════════════════
  Tier         | Total | Pass | Fail | Error
──────────────┼───────┼──────┼──────┼──────
  Unit         | ...   | ...  | ...  | ...
  Integration  | ...   | ...  | ...  | ...
══════════════════════════════════════════════════

FAILURES:
- [file] [tier] [level] [diagnosis]

VERDICT: PASS | FAIL
```

## Error Handling

- If Godot binary not found, report: "ERROR: Godot binary not found on PATH"
- If test file doesn't exist, report: "ERROR: File not found: {path}"
- If command times out (>60s), kill the process and report Level 4 hang
- Never modify any files
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/gol-test-runner/references/runner-prompt.md
git commit -m "feat(skills): add test runner prompt template"
```

---

## Task 9: Create gol-test-runner playtest prompt template

**Files:**
- Create: `.claude/skills/gol-test-runner/references/playtest-prompt.md`

This is entirely new content — the playtest tier that was previously "Not yet available."

- [ ] **Step 1: Write playtest-prompt.md**

Create `.claude/skills/gol-test-runner/references/playtest-prompt.md`:

```markdown
# Playtester — Subagent Prompt

You are a playtester for God of Lego. You verify game features by running the game and interacting with it via the AI debug bridge.

## Identity

You boot the game, verify a feature works by running commands and checking state, then tear down and report. You are the only tier that interacts with a live, rendering game instance.

## Tools

You have access to: Bash, Read, Glob, Grep.

`ai-debug.mjs` is your only Godot interaction tool. Located relative to the working directory at `gol-tools/ai-debug/ai-debug.mjs` (from management repo root) or find it via the CWD provided in the task block.

### ai-debug subcommand reference

| Command | Purpose |
|---------|---------|
| `boot [--path <dir>]` | Kill existing Godot, reimport if needed, launch, poll until ready |
| `teardown` | Clean kill of Godot |
| `console <cmd>` | Run a debug console command |
| `get <key>` | Get game state (`player.pos`, `player.hp`, `time`, `entity_count`) |
| `set <key> <value>` | Set game state |
| `screenshot` | Capture screenshot, returns file path |
| `eval <expr>` | Evaluate GDScript expression |
| `script <file>` | Execute a GDScript file |
| `spawn <recipe> [count] [x] [y]` | Spawn entities |
| `recipes [filter]` | List available recipes |

All commands are run as:
```bash
node <path-to-ai-debug>/ai-debug.mjs <command> [args...]
```

## Workflow

### 1. Boot

```bash
node <ai-debug-path>/ai-debug.mjs boot --path <project-path>
```

Wait for `READY`. If `TIMEOUT` or `CRASH`, report FAIL immediately with the diagnostic output.

### 2. Verify

Use the commands above to verify the feature. You decide:
- Which commands to run
- What state to check before and after
- What screenshots to capture
- How many frames/seconds to wait between actions

Use your knowledge of game mechanics (ECS, components, systems) to design meaningful checks. Don't just check existence — verify behavior and state transitions.

### 3. Teardown

```bash
node <ai-debug-path>/ai-debug.mjs teardown
```

**Always run teardown**, even on failure. If teardown itself fails, note it but don't let it block your report.

## Verification Approach

You receive a feature-level description. You design the verification:

1. **Baseline**: capture initial state (entity count, player HP, positions)
2. **Action**: trigger the feature (spawn entities, deal damage, use commands)
3. **Observation**: check state changed as expected
4. **Evidence**: take screenshots at key moments

Think like a QA tester: what would convince you this feature works? What edge cases matter?

## Report Format

```
VERDICT: PASS | FAIL

Checked:
- <what you verified and how>

Issues (if FAIL):
- <what failed, expected vs actual, hypothesis>

Screenshots: <list of paths if taken>
```

## Error Handling

- If boot fails → report FAIL with the boot error, skip verification, still run teardown
- If a command times out → retry once after 5 seconds, then report the timeout
- If something is outside your scope (code bug, tool bug) → report it clearly, the coordinator decides what to do
- If the game crashes mid-verification → capture any available diagnostics, report FAIL, run teardown

## What You Do NOT Do

- Modify game code or test files
- Write persistent test scripts (use ephemeral commands only)
- Skip teardown for any reason
- Claim PASS without evidence (state checks or screenshots)
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/gol-test-runner/references/playtest-prompt.md
git commit -m "feat(skills): add playtest prompt template for live game verification"
```

---

## Task 10: Migrate foreman from shell scripts to ai-debug

**Files:**
- Modify: `gol-tools/foreman/foreman-daemon.mjs:397-408` (bash allow list)
- Modify: `gol-tools/foreman/foreman-daemon.mjs:1546-1558` (cleanup method)
- Modify: `gol-tools/foreman/prompts/tasks/tester/e2e-acceptance.md`

- [ ] **Step 1: Update `#getTesterBashAllow()` in foreman-daemon.mjs**

Replace the tester script paths with ai-debug.mjs:

```javascript
#getTesterBashAllow() {
    return this.#expandBashAllow([
        'sleep',
        'tail',
        'ls',
        'pkill',
        'pgrep',
        'ps',
        'node ' + join(this.#config.workDir, 'gol-tools', 'ai-debug', 'ai-debug.mjs'),
    ]);
}
```

- [ ] **Step 2: Update `#cleanupTesterRuntime()` in foreman-daemon.mjs**

Replace the shell script call with a direct ai-debug teardown:

```javascript
#cleanupTesterRuntime(issueNumber) {
    const aiDebug = join(this.#config.workDir, 'gol-tools', 'ai-debug', 'ai-debug.mjs');

    try {
        execFileSync('node', [aiDebug, 'teardown'], { stdio: 'ignore', timeout: 15000 });
        info(COMPONENT, `#${issueNumber}: tester runtime cleanup completed`);
        return '';
    } catch (e) {
        const message = `tester cleanup failed: ${e.message}`;
        warn(COMPONENT, `#${issueNumber}: ${message}`);
        return message;
    }
}
```

- [ ] **Step 3: Update e2e-acceptance.md prompt template**

Replace all shell script references in `gol-tools/foreman/prompts/tasks/tester/e2e-acceptance.md`:

Replace:
```
{{ repoRoot }}/gol-tools/foreman/bin/tester-start-godot.sh {{ wsPath }} <场景路径> > /tmp/godot_e2e.log 2>&1 &
```
With:
```
node {{ repoRoot }}/gol-tools/ai-debug/ai-debug.mjs boot --path {{ wsPath }}
```

Replace:
```
{{ repoRoot }}/gol-tools/foreman/bin/tester-ai-debug.sh get entity_count
```
With:
```
node {{ repoRoot }}/gol-tools/ai-debug/ai-debug.mjs get entity_count
```

Replace:
```
{{ repoRoot }}/gol-tools/foreman/bin/tester-ai-debug.sh script /tmp/e2e_check_*.gd
```
With:
```
node {{ repoRoot }}/gol-tools/ai-debug/ai-debug.mjs script /tmp/e2e_check_*.gd
```

Replace:
```
{{ repoRoot }}/gol-tools/foreman/bin/tester-ai-debug.sh screenshot
```
With:
```
node {{ repoRoot }}/gol-tools/ai-debug/ai-debug.mjs screenshot
```

Replace:
```
{{ repoRoot }}/gol-tools/foreman/bin/tester-cleanup.sh
```
With:
```
node {{ repoRoot }}/gol-tools/ai-debug/ai-debug.mjs teardown
```

Also update the troubleshooting line that references `tester-cleanup.sh`:
Replace `清理时使用 tester-cleanup.sh 或 pkill` with `清理时使用 ai-debug.mjs teardown 或 pkill`.

- [ ] **Step 4: Commit**

```bash
git add gol-tools/foreman/foreman-daemon.mjs gol-tools/foreman/prompts/tasks/tester/e2e-acceptance.md
git commit -m "refactor(foreman): replace tester shell scripts with ai-debug boot/teardown"
```

---

## Task 11: Delete retired files

**Files:**
- Delete: `.claude/skills/gol-test-writer-unit/SKILL.md`
- Delete: `.claude/skills/gol-test-writer-integration/SKILL.md`
- Delete: `.claude/agents/console-playtester.md`
- Delete: `gol-tools/foreman/bin/tester-start-godot.sh`
- Delete: `gol-tools/foreman/bin/tester-cleanup.sh`

Note: `tester-ai-debug.sh` is NOT deleted — it's a thin wrapper that delegates to ai-debug.mjs and may still be used by other scripts or manual workflows. The spec only lists `tester-start-godot.sh` and `tester-cleanup.sh` for deletion.

- [ ] **Step 1: Delete old test writer skills**

```bash
rm .claude/skills/gol-test-writer-unit/SKILL.md
rmdir .claude/skills/gol-test-writer-unit
rm .claude/skills/gol-test-writer-integration/SKILL.md
rmdir .claude/skills/gol-test-writer-integration
```

- [ ] **Step 2: Delete console-playtester agent**

```bash
rm .claude/agents/console-playtester.md
```

- [ ] **Step 3: Delete foreman tester shell scripts**

```bash
rm gol-tools/foreman/bin/tester-start-godot.sh
rm gol-tools/foreman/bin/tester-cleanup.sh
```

- [ ] **Step 4: Commit**

```bash
git add -A .claude/skills/gol-test-writer-unit .claude/skills/gol-test-writer-integration .claude/agents/console-playtester.md gol-tools/foreman/bin/tester-start-godot.sh gol-tools/foreman/bin/tester-cleanup.sh
git commit -m "chore: retire v3 test skills, console-playtester agent, and foreman tester scripts"
```

---

## Task 12: Update AGENTS.md files

**Files:**
- Modify: `AGENTS.md` (management repo root)
- Modify: `gol-project/tests/AGENTS.md`

- [ ] **Step 1: Update management repo AGENTS.md**

In `AGENTS.md`, replace the v3 test harness section with:

```markdown
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

Also rename any "E2E" references to "playtest" in the test-related sections.

- [ ] **Step 2: Update gol-project/tests/AGENTS.md**

Replace the entire content with updated v4 terminology:

In the three-tier table, rename "E2E" to "Playtest":

```markdown
| Tier | Framework | Directory | `extends` | Runner |
|------|-----------|-----------|-----------|--------|
| **Unit** | gdUnit4 | `tests/unit/` | `GdUnitTestSuite` | gdUnit4 CLI |
| **Integration** | SceneConfig | `tests/integration/` | `SceneConfig` | `test_main.tscn` |
| **Playtest** | AI Debug Bridge | not committed | none (ephemeral) | live game + `ai-debug.mjs` |
```

Replace the v2 delegation protocol section with:

```markdown
## v4 Test Harness: Subagent-Driven Delegation

Main agents **NEVER** write, run, or playtest directly. Use the subagent-driven harness:

1. **Write**: Load `gol-test-writer` skill → determines tier (unit vs integration) → dispatches writer subagent
2. **Run**: Load `gol-test-runner` skill → determines tier (runner vs playtest) → dispatches runner subagent
3. Receive report, decide next action (fix, re-run, escalate)

| Need | Skill | Tier → Prompt | Model |
|------|-------|---------------|-------|
| Write unit test | gol-test-writer | unit → unit-prompt.md | sonnet |
| Write integration test | gol-test-writer | integration → integration-prompt.md | sonnet |
| Run existing tests | gol-test-runner | runner → runner-prompt.md | haiku |
| Verify feature in game (playtest) | gol-test-runner | playtest → playtest-prompt.md | sonnet |

**Detailed knowledge** lives inside each prompt template (`references/*.md`). This file is for architecture understanding only.
```

Update the decision rule table to rename E2E:

```markdown
| Does it need a live game with rendering? | Playtest | Integration |
| Does it need AI Debug Bridge injection? | Playtest | Integration |
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md gol-project/tests/AGENTS.md
git commit -m "docs: update AGENTS.md files to v4 test harness with playtest terminology"
```

---

## Task 13: Update CLAUDE.md test harness section

**Files:**
- Modify: `CLAUDE.md` (management repo root)

- [ ] **Step 1: Update the Testing section in CLAUDE.md**

Replace the v3 test harness table and delegation protocol with:

```markdown
**v4 Test Harness — subagent-driven workflow (two skills):**

Main agents **NEVER** write or run tests directly. Delegate via skills:

1. **Determine tier** from the decision matrix
2. **Load skill** (`gol-test-writer` or `gol-test-runner`)
3. Skill dispatches subagent with the matching prompt template
4. Receive report, decide next action

| Need | Skill | Tier → Prompt | Model |
|------|-------|---------------|-------|
| Write unit test | gol-test-writer | unit → unit-prompt.md | sonnet |
| Write integration test | gol-test-writer | integration → integration-prompt.md | sonnet |
| Run existing tests | gol-test-runner | runner → runner-prompt.md | haiku |
| Verify feature in game (playtest) | gol-test-runner | playtest → playtest-prompt.md | sonnet |
```

Remove the old "E2E (needs rendering / AI Debug Bridge) | — | — | Not yet available" row.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md to v4 test harness"
```

---

## Task 14: Update superpowers skill list for new skill names

**Files:**
- Check and update any skill registration files that reference the old skill names

- [ ] **Step 1: Search for old skill name references**

```bash
grep -r "gol-test-writer-unit\|gol-test-writer-integration" .claude/ --include="*.md" --include="*.json" --include="*.yaml"
```

Update any references found to point to the new `gol-test-writer` skill.

- [ ] **Step 2: Search for old gol-test-runner references in skill configs**

```bash
grep -r "gol-test-runner" .claude/ --include="*.json" --include="*.yaml"
```

Verify the new `gol-test-runner/SKILL.md` is picked up automatically (skills are discovered by directory name).

- [ ] **Step 3: Commit if changes were needed**

```bash
git add .claude/
git commit -m "chore: update skill references to v4 test harness names"
```

---

## Task 15: Verify end-to-end

- [ ] **Step 1: Verify ai-debug boot/teardown**

```bash
cd /Users/dluck/Documents/GitHub/gol
node gol-tools/ai-debug/ai-debug.mjs boot --path gol-project
# Expected: READY (after 15-30s)
node gol-tools/ai-debug/ai-debug.mjs teardown
# Expected: STOPPED
```

- [ ] **Step 2: Verify skill files exist and are well-formed**

```bash
ls -la .claude/skills/gol-test-writer/SKILL.md
ls -la .claude/skills/gol-test-writer/references/unit-prompt.md
ls -la .claude/skills/gol-test-writer/references/integration-prompt.md
ls -la .claude/skills/gol-test-runner/SKILL.md
ls -la .claude/skills/gol-test-runner/references/runner-prompt.md
ls -la .claude/skills/gol-test-runner/references/playtest-prompt.md
```

- [ ] **Step 3: Verify old files are deleted**

```bash
# These should all fail (file not found):
ls .claude/skills/gol-test-writer-unit/SKILL.md 2>&1
ls .claude/skills/gol-test-writer-integration/SKILL.md 2>&1
ls .claude/agents/console-playtester.md 2>&1
ls gol-tools/foreman/bin/tester-start-godot.sh 2>&1
ls gol-tools/foreman/bin/tester-cleanup.sh 2>&1
```

- [ ] **Step 4: Verify foreman references are updated**

```bash
grep -c "tester-start-godot\|tester-cleanup" gol-tools/foreman/foreman-daemon.mjs
# Expected: 0

grep -c "ai-debug.mjs" gol-tools/foreman/foreman-daemon.mjs
# Expected: >= 1

grep -c "tester-start-godot\|tester-cleanup" gol-tools/foreman/prompts/tasks/tester/e2e-acceptance.md
# Expected: 0
```

- [ ] **Step 5: Final commit if any fixes needed**

```bash
git status
# Fix anything that's off, then:
git add -A && git commit -m "fix: address verification issues from v4 harness migration"
```
