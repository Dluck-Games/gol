# Foreman Workflow Engine Design

## Overview

Extend Foreman with a workflow engine that orchestrates multiple steps (shell commands, agent tasks, notifications) in sequence, with conditional execution, precondition gates, structured data flow between steps, and configurable failure semantics. The primary use case is nightly automated test execution across all tiers.

## Motivation

- All automated tests (unit, integration, playtest, GOAP benchmark) need to run nightly with failure-only notification
- Current Foreman only supports single-task sessions — no multi-step orchestration
- Notification is currently all-or-nothing (per session), with no conditional logic
- Test execution doesn't need AI, but we want to reuse Foreman's cron scheduling, session state, logging, and notification infrastructure

## Core Concepts

```
Workflow = requires (gates) + ordered steps + global context
Step     = shell | agent | notify (three types, unified output interface)
Data     = template variables (lightweight) + artifact files (complex)
```

## Workflow Definition

Workflows are YAML files in `gol-tools/foreman/workflows/`.

```yaml
name: nightly-tests
description: "Nightly full test suite — unit, integration, playtest, GOAP benchmark"

requires:
  - shell: git -C {{workspace_path}} diff --quiet && git -C {{workspace_path}} diff --cached --quiet
    message: "工作区有未提交的修改，跳过本次执行"
    on_fail: skip

steps:
  - id: unit
    shell: gol test --all --verbose
    continue_on_failure: true

  - id: playtest
    shell: gol test playtest --all --verbose
    continue_on_failure: true

  - id: goap
    shell: gol test goap --json
    continue_on_failure: true

  - id: alert
    notify:
      message: |
        🔴 夜间测试有失败

        Unit+Integration: {{steps.unit.result}}
        Playtest: {{steps.playtest.result}}
        GOAP Bench: {{steps.goap.result}}

        {{steps.unit.result == "fail" && steps.unit.summary}}
        {{steps.playtest.result == "fail" && steps.playtest.summary}}
        {{steps.goap.result == "fail" && steps.goap.summary}}
    when: "{{workflow.has_failure}}"

  - id: infra-alert
    notify:
      message: |
        ⚠️ 夜间测试执行异常

        {{workflow.errors_summary}}
    when: "{{workflow.has_error}}"
```

## Step Types

### Shell Step

Executes a shell command directly. No AI agent involved.

```yaml
- id: <unique-id>
  shell: <command>
  continue_on_failure: bool   # default: false
  requires: [...]             # optional step-level gates
```

### Agent Step

Starts a Foreman session using an existing task template.

```yaml
- id: <unique-id>
  task: <task-template-name>  # references tasks/<name>.yaml
  args:
    prompt: "..."             # passed as --prompt to the task
    <arg>: <value>            # task-specific args
  continue_on_failure: bool
  when: "<expression>"
  requires: [...]
```

### Notify Step

Sends a notification through the existing Foreman notifier (OpenClaw/Telegram).

```yaml
- id: <unique-id>
  notify:
    message: "<template string>"
  when: "<expression>"
```

Notify steps have no `continue_on_failure` (they don't produce business results) and no `requires` (they are lightweight actions).

## Step Output Interface

Every step produces a unified output after execution:

| Field | Type | Description |
|-------|------|-------------|
| `status` | `completed` \| `error` | Infrastructure level: did the step finish normally? |
| `result` | `pass` \| `fail` \| `null` | Business level: was the outcome positive? (null when status=error) |
| `exit_code` | int | Raw exit code (for debugging) |
| `stdout` | string | Standard output (truncated to reasonable length) |
| `summary` | string | Structured summary (agent: model output; shell: stdout tail) |
| `artifacts_dir` | string | Path to file output directory |

### Exit Code Mapping (Shell Steps)

| Exit Code | status | result | Meaning |
|-----------|--------|--------|---------|
| 0 | `completed` | `pass` | All passed |
| 1 | `completed` | `fail` | Normal execution, business result negative (e.g. test cases failed) |
| 2+ | `error` | `null` | Unexpected exit (infra problem: binary not found, crash, timeout) |
| timeout/crash | `error` | `null` | Process killed or crashed |

### Exit Code Mapping (Agent Steps)

| Condition | status | result |
|-----------|--------|--------|
| Session ends normally, exit 0 | `completed` | `pass` |
| Session ends normally, exit 1 | `completed` | `fail` |
| Session fails to start / timeout | `error` | `null` |

## Data Flow Between Steps

### Template Variables

Downstream steps reference upstream outputs via template expressions:

- `{{steps.<id>.exit_code}}` — raw exit code
- `{{steps.<id>.status}}` — completed / error
- `{{steps.<id>.result}}` — pass / fail / null
- `{{steps.<id>.summary}}` — text summary
- `{{steps.<id>.artifacts_dir}}` — path to artifacts directory

### Workflow-Level Variables

- `{{workflow.has_failure}}` — any step has result == fail
- `{{workflow.has_error}}` — any step has status == error
- `{{workflow.all_passed}}` — all steps: status == completed && result == pass
- `{{workflow.errors_summary}}` — aggregated error messages from all error steps
- `{{workspace_path}}` — resolved gol-project path

### Complex Data

For large or structured data, steps write to their `artifacts_dir`. Downstream steps read via file path: `{{steps.<id>.artifacts_dir}}/output.json`.

## Conditional Execution: `when`

Template expression evaluated before step execution:

```yaml
when: "{{steps.unit.exit_code != 0}}"
when: "{{workflow.has_failure}}"
when: "{{steps.decide.result == 'fail'}}"
```

If `when` evaluates to false, the step is skipped (status = `skipped`, result = `null`). Workflow continues normally.

## Precondition Gates: `requires`

Hard checks that must pass before execution proceeds. Unlike `when`, gate failure is not a normal skip — it means the environment is unsuitable.

### Syntax

```yaml
requires:
  - shell: <check-command>
    message: "<human-readable explanation>"
    on_fail: skip | abort | notify   # default: skip
```

### Gate Levels

**Workflow-level requires:** checked before any step runs.

**Step-level requires:** checked before that specific step runs.

### `on_fail` Behavior

| `on_fail` | Workflow-level | Step-level |
|-----------|---------------|------------|
| `skip` (default) | Entire workflow marked `skipped`, silent exit | Current step marked `gate_failed`, subsequent steps continue |
| `abort` | Same as skip at workflow level | Abort entire workflow immediately |
| `notify` | Same as skip + send notification with message | Same as skip + send notification with message |

### Gate vs When

| | `when` | `requires` |
|--|--------|-----------|
| Semantics | Conditional execution | Precondition check |
| On false/fail | Step skipped, workflow continues | Step/workflow aborted |
| Status | `skipped` (normal) | `gate_failed` (environment unsuitable) |
| Typical use | "Only notify on failure" | "Don't run if workspace is dirty" |
| Check method | References upstream step outputs | Independent shell command |

## Failure Propagation: `continue_on_failure`

- `false` (default): step failure stops subsequent steps (except those with a `when` that evaluates to true)
- `true`: step failure is recorded but workflow continues to next step

In both cases, `workflow.has_failure` / `workflow.has_error` are updated for downstream `when` expressions.

## Workflow Runner Execution Flow

```
1. Load workflow YAML from workflows/<name>.yaml
2. Resolve workspace_path
3. Evaluate workflow-level requires:
   - All pass → continue
   - Any fail → apply on_fail (skip/abort/notify), exit
4. Initialize context: { steps: {}, workflow: { has_failure: false, has_error: false } }
5. For each step:
   a. Evaluate step-level requires → gate_failed? apply on_fail, continue/abort
   b. Evaluate `when` → false? mark skipped, continue
   c. Execute step by type:
      - shell: spawn subprocess, capture stdout/stderr/exit_code
      - agent: call existing session-runner (reuse full Foreman session machinery)
      - notify: call existing notifier (reuse OpenClaw/Telegram pipeline)
   d. Map exit code to status/result
   e. Record output to context.steps[id]
   f. Update workflow.has_failure / workflow.has_error
   g. If status != completed && !continue_on_failure → skip remaining (but still eval `when` steps)
6. Record workflow final state (passed / failed / error / skipped)
```

## CLI Interface

### Run a workflow

```bash
foreman run workflow <name>              # background (default, same as task runs)
foreman run workflow <name> --foreground # stream output to terminal
```

### Schedule a workflow

```bash
foreman cron add --workflow nightly-tests --schedule '0 3 * * *'
```

### List workflows

```bash
foreman workflow list
```

### Manual trigger with overrides

```bash
foreman run workflow nightly-tests --skip-requires   # bypass gates (for debugging)
```

## Logging and State

Reuse existing Foreman session infrastructure:

- Each workflow run creates a session (with metadata `type: workflow`)
- Each step maps to a turn within the session
- Logs written to `logs/foreman/sessions/<session-id>/`
- Step artifacts stored in `logs/foreman/sessions/<session-id>/artifacts/<step-id>/`

## Implementation Scope

| Change | File | Estimate |
|--------|------|----------|
| Workflow YAML loader + schema validation | new `lib/workflow-loader.mts` | ~80 lines |
| Workflow runner (execution loop, context management) | new `lib/workflow-runner.mts` | ~150 lines |
| Shell step executor | new `lib/shell-executor.mts` | ~40 lines |
| Template expression evaluator | new `lib/template-eval.mts` | ~60 lines |
| CLI entry points (`run workflow`, `workflow list`) | modify `bin/foreman.mts` | ~30 lines |
| Cron support for workflows | modify `lib/cron.mts` | ~10 lines |
| **Total** | | **~370 lines new + ~40 lines modified** |

No changes to existing task templates, session-runner, or notifier — all reused as-is.

## Nightly Test Workflow (Target Use Case)

```yaml
# workflows/nightly-tests.yaml
name: nightly-tests
description: "Nightly full test suite — unit, integration, playtest, GOAP benchmark"

requires:
  - shell: git -C {{workspace_path}} diff --quiet && git -C {{workspace_path}} diff --cached --quiet
    message: "工作区有未提交的修改，跳过本次执行"
    on_fail: skip

steps:
  - id: unit
    shell: gol test --all --verbose
    continue_on_failure: true

  - id: playtest
    shell: gol test playtest --all --verbose
    continue_on_failure: true

  - id: goap
    shell: gol test goap --json
    continue_on_failure: true

  - id: alert
    notify:
      message: |
        🔴 夜间测试有失败

        Unit+Integration: {{steps.unit.result}}
        Playtest: {{steps.playtest.result}}
        GOAP Bench: {{steps.goap.result}}

        {{steps.unit.result == "fail" && steps.unit.summary}}
        {{steps.playtest.result == "fail" && steps.playtest.summary}}
        {{steps.goap.result == "fail" && steps.goap.summary}}
    when: "{{workflow.has_failure}}"

  - id: infra-alert
    notify:
      message: |
        ⚠️ 夜间测试执行异常

        {{workflow.errors_summary}}
    when: "{{workflow.has_error}}"
```

Triggered via:
```bash
foreman cron add --workflow nightly-tests --schedule '0 3 * * *'
```

## Future Extensions (Out of Scope)

- Parallel step execution (fan-out / fan-in)
- Step retry with backoff
- Workflow composition (workflow calling sub-workflow)
- Web dashboard for workflow run history
- Workflow-level timeout
