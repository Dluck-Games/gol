# gol-test-dispatch

Use this skill when the main agent needs to route a test task to the correct writer subagent.

## Purpose

Dispatch only.

This skill decides which tier owns the task and what context the main agent must pass.

It does **not** include test writing knowledge, assertion patterns, validation rules, or system/recipe tables.

## Tier decision matrix

Route as a pure function:

| Situation | Route |
|---|---|
| Pure function / single component / single class | `test-writer-unit` |
| Multi-system ECS behavior / needs World | `test-writer-integration` |
| User-facing gameplay scenario / needs rendering / needs AI Debug Bridge | E2E (not yet available) |

## Prompt template: `test-writer-unit`

Main agent must provide:

- feature description
- class/component to test
- key methods
- expected behaviors

```text
Write a unit test for this feature.

Feature description: <what changed>
Class/component to test: <name>
Key methods: <method list>
Expected behaviors:
- <behavior 1>
- <behavior 2>
```

## Prompt template: `test-writer-integration`

Main agent must provide:

- feature description
- systems involved
- entities/recipes needed
- expected gameplay behavior
- assertion plan

```text
Write an integration test for this feature.

Feature description: <what changed>
Systems involved: <system list>
Entities/recipes needed: <setup list>
Expected gameplay behavior:
- <behavior 1>
- <behavior 2>
Assertion plan:
- <assertion 1>
- <assertion 2>
```

## Quick run commands

Unit:

```bash
$GODOT --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/unit/$FILE --ignoreHeadlessMode
```

Integration:

```bash
$GODOT --headless --path . --scene scenes/tests/test_main.tscn -- --config=res://tests/integration/$FILE
```
