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
