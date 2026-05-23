---
name: gol-test-runner
description: "Run GOL test verification through the gol CLI. Use when asked to run unit, integration, automated playtest, targeted suite, all automated tests, or live playtest; unit/integration/playtest tiers require an explicit --suite, while full unit+integration runs require explicit --all."
---

# gol-test-runner

Coordinator skill for running GOL automated tests and playtesting. Runs explicit unit, integration, automated playtest, and all-test commands directly through the `gol` CLI; routes only interactive live playtesting to a subagent with the playtest prompt template.

Triggers: 'run test', 'run all tests', 'test runner', 'playtest', 'verify in game', 'do playtest', 'test in game'.

## You Are the Coordinator

You are the main agent. `gol test` already provides agent-friendly output for unit, integration, and automated playtest suites, so run those automated tests directly. You still never interact with live Godot gameplay yourself. Your job:

1. Determine whether the request is automated test execution or live playtest
2. For unit, integration, automated playtest, or all-test requests, run the matching `gol test ... --suite ...` or explicit `gol test --all` command directly
3. For interactive live playtest work, read `references/playtest-prompt.md`
4. Dispatch a live playtest subagent with the template + task-specific context
5. If FAIL: decide next action (fix code, fix test, re-run, escalate to user)

## Decision Matrix

| Need | Tier | Prompt Template | Dispatch |
|------|------|-----------------|----------|
| Run unit tests | Direct Unit | none | Main agent runs `gol test unit --suite <names>` directly |
| Run integration tests | Direct Integration | none | Main agent runs `gol test integration --suite <names>` directly |
| Run automated playtest | Direct Playtest | none | Main agent runs `gol test playtest --suite <names>` directly |
| Run unit + integration tests | Direct All | none | Main agent runs `gol test --all` directly |
| Verify a feature interactively in the running game | Live Playtest | `references/playtest-prompt.md` | Claude Code: haiku; OMO: `category="unspecified-low"`, `load_skills=[]` |

### Routing rules

- If the user says "run unit tests", "run quick unit tests", or asks for a unit suite via `--suite` -> **Direct Unit**, but choose or ask for a suite before running
- If the user says "run integration tests" or asks for an integration suite via `--suite` -> **Direct Integration**, but choose or ask for a suite before running
- If the user says "run automated playtest", asks for `gol test playtest`, or asks for a committed `tests/playtest/` suite -> **Direct Playtest**, but choose or ask for a suite before running
- If the user says "run all tests", "run unit and integration", or asks to run mixed automated tests -> **Direct All**
- If the user says "playtest", "verify in game", "test in game", "check if it works", or asks for live rendered/runtime verification without naming `gol test playtest` -> **Live Playtest**
- If the user says "run tests" without a tier, prefer **Direct Unit** for fast feedback unless the request clearly requires integration/all tests
- If the user says "run tests and playtest" -> run the direct automated test command first, then choose Direct Playtest for a named automated suite or dispatch Live Playtest for exploratory runtime QA

## Dispatch Protocol

### Direct automated execution

Run automated tests yourself from the project or worktree directory. Tier-specific commands are intentionally suite-gated to prevent accidental broad runs:

```bash
gol test unit --suite pcg
gol test integration --suite flow
gol test playtest --suite night_raid
gol test playtest --suite night_raid --record
gol test --all
```

For targeted suites, pass the suite filter directly:

```bash
gol test unit --suite pcg
gol test integration --suite pcg
gol test playtest --suite night_raid
gol test unit --suite ai,system
```

Use the command exit code and simplified output as the report. Do not spawn a subagent to run unit, integration, automated playtest, all-test, or suite-filtered automated test commands.

Never run bare `gol test`, `gol test unit`, `gol test integration`, or `gol test playtest`. Use `gol test --all` only when the task truly calls for the full unit+integration set.

### Live playtest dispatch

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

Run direct automated commands from your current working directory. If you're in a worktree, run them there. Pass the same current working directory to playtest subagents.

## Fix-Retest Loop

When a report says FAIL:

1. **Direct automated test FAIL**: Read the simplified failure output. If it's a test bug, fix the test. If it's a code bug, fix the code. Then run the same `gol test ...` command again.
2. **Automated playtest FAIL**: Read `logs/playtest/<suite>/report.txt` and the simplified CLI output. If it's a code bug, fix the code and rerun `gol test playtest --suite <name>`. If it's a tool/environment issue, report to user.
3. **Live playtest FAIL**: Read the issues. If it's a code bug, fix the code and re-dispatch playtest. If it's a tool/environment issue, report to user.
4. **Max retries**: 2 re-runs or re-dispatches per tier. After that, escalate to user with full report.

## What You Do NOT Do

- Spawn subagents for unit, integration, automated playtest, all-test, or automated suite-filtered test commands
- Run live/debug-bridge playtest commands directly
- Launch or kill Godot for live playtesting
- Write test files (use gol-test-writer for that)
- Read test framework documentation
