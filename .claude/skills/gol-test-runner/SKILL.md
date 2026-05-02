# gol-test-runner

Coordinator skill for running GOL tests and playtesting. Runs quick unit tests directly; routes heavier test execution and playtesting to a subagent with the matching prompt template.

Triggers: 'run test', 'run all tests', 'test runner', 'playtest', 'verify in game', 'do playtest', 'test in game'.

## You Are the Coordinator

You are the main agent. You may run quick unit-test commands directly because `gol test unit` already provides agent-friendly output. You still never interact with live Godot yourself. Your job:

1. Determine the correct tier (runner vs playtest)
2. For quick unit tests, run the command directly and report the result
3. For integration/all/playtest work, read the matching prompt template from `references/`
4. Dispatch a subagent with the template + task-specific context
5. Receive the subagent's report
6. If FAIL: decide next action (fix code, fix test, re-run, escalate to user)

## Decision Matrix

| Need | Tier | Prompt Template | Dispatch |
|------|------|-----------------|----------|
| Run quick unit tests | Direct Unit | none | Main agent runs `gol test unit` directly |
| Run existing unit/integration tests | Runner | `references/runner-prompt.md` | Claude Code: haiku; OMO: `category="quick"`, `load_skills=[]` |
| Verify a feature in the running game | Playtest | `references/playtest-prompt.md` | Claude Code: haiku; OMO: `category="unspecified-low"`, `load_skills=[]` |

### Routing rules

- If the user says "run unit tests", "run quick unit tests", or asks for a unit suite via `--suite` → **Direct Unit**
- If the user says "run integration tests", "run all tests", or asks to run specific mixed/integration files → **Runner**
- If the user says "playtest", "verify in game", "test in game", "check if it works" → **Playtest**
- If the user says "run tests" without a tier, prefer **Direct Unit** for fast feedback unless the request clearly requires integration/all tests
- If the user says "run tests and playtest" → run Direct Unit or Runner first, then Playtest

## Dispatch Protocol

### Direct Unit execution

Run quick unit tests yourself from the project or worktree directory:

```bash
gol test unit
```

For targeted suites, pass the suite filter directly:

```bash
gol test unit --suite pcg
gol test unit --suite ai,system
```

Use the command exit code and simplified output as the report. Do not spawn a subagent just to run these quick unit commands.

### Runner dispatch

Use Runner only for integration tests, all tests, mixed file batches, or cases that require reading/parsing multiple test files. Spawn a leaf subagent. Do not load skills into it, and do not permit it to delegate to other subagents.

For OMO, use:

```typescript
task(category="quick", load_skills=[], run_in_background=false, prompt="...")
```

For Claude Code, use the cheapest available model class (haiku) with:

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

Spawn a leaf subagent. Do not use `unspecified-high`, GPT 5.5 Fast, Sonnet, or any other high-capability/default coding category for playtest. Playtest is runtime QA, not implementation.

For OMO, use:

```typescript
task(category="unspecified-low", load_skills=[], run_in_background=false, prompt="...")
```

For Claude Code, use the cheapest available model class (haiku) with:

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

1. **Direct Unit FAIL**: Read the simplified failure output. If it's a test bug, fix the test. If it's a code bug, fix the code. Then run the same unit command again.
2. **Runner FAIL**: Read the failure diagnosis. If it's a test bug, fix the test. If it's a code bug, fix the code. Then re-dispatch the runner.
3. **Playtest FAIL**: Read the issues. If it's a code bug, fix the code and re-dispatch playtest. If it's a tool/environment issue, report to user.
4. **Max retries**: 2 re-runs or re-dispatches per tier. After that, escalate to user with full report.

## What You Do NOT Do

- Run integration, all-test, or playtest commands directly
- Parse test output
- Launch or kill Godot
- Write test files (use gol-test-writer for that)
- Read test framework documentation
