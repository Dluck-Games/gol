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
