# Foreman Workflow Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a workflow engine to Foreman that orchestrates shell commands, agent tasks, and notifications in sequence with conditional execution, precondition gates, and structured data flow — then use it to run nightly automated tests.

**Architecture:** Workflow definitions are YAML files in `gol-tools/foreman/workflows/`. A new workflow runner executes steps sequentially, maintaining a context object with each step's output. The runner reuses existing Foreman session state, notifier, and cron infrastructure. A prerequisite change to `gol test playtest` adds `--all` support so the nightly workflow doesn't hardcode suite names.

**Tech Stack:** TypeScript (Node 18+, ES2022, node:test), YAML parsing (existing `yaml` dep), Go (gol CLI changes)

---

## File Structure

### New files (gol-tools/foreman/)

| File | Responsibility |
|------|---------------|
| `lib/workflow-loader.mts` | Load + validate workflow YAML, parse step definitions |
| `lib/workflow-runner.mts` | Execute workflow: gate checks, step dispatch, context management, failure propagation |
| `lib/shell-executor.mts` | Spawn shell commands, capture stdout/stderr, map exit codes to status/result |
| `lib/template-eval.mts` | Evaluate `{{...}}` template expressions against workflow context |
| `workflows/nightly-tests.yaml` | The nightly test workflow definition |
| `tests/workflow-loader.test.mts` | Tests for YAML loading and validation |
| `tests/template-eval.test.mts` | Tests for expression evaluation |
| `tests/shell-executor.test.mts` | Tests for shell step execution and exit code mapping |
| `tests/workflow-runner.test.mts` | Integration tests for the full runner loop |

### Modified files (gol-tools/foreman/)

| File | Change |
|------|--------|
| `bin/foreman.mts` | Add `run workflow`, `workflow list` commands |
| `lib/cron.mts` | Support `--workflow` in cron entries |

### Modified files (gol-tools/cli/)

| File | Change |
|------|--------|
| `cmd/test.go` | Allow `gol test playtest --all` (no `--suite` required for playtest tier) |
| `cmd/test_test.go` | Test for the new `--all` playtest behavior |

---

## Task 0: Enable `gol test playtest --all`

**Files:**
- Modify: `gol-tools/cli/cmd/test.go:66-99`
- Modify: `gol-tools/cli/cmd/test_test.go`

This is a prerequisite for the nightly workflow. Currently `gol test playtest` requires `--suite <names>`. We need it to accept `--all` to run every discovered playtest suite.

- [ ] **Step 1: Write the failing test**

In `gol-tools/cli/cmd/test_test.go`, add:

```go
func TestResolveTestSelection_PlaytestAll(t *testing.T) {
	tier, opts, err := resolveTestSelection([]string{"playtest"}, true, "", true, false)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if tier != testrunner.TierPlaytest {
		t.Errorf("expected TierPlaytest, got %v", tier)
	}
	if opts.Suite != nil {
		t.Errorf("expected nil suite (run all), got %v", opts.Suite)
	}
	if !opts.Record {
		t.Error("expected record=true")
	}
}

func TestResolveTestSelection_PlaytestRequiresSuiteOrAll(t *testing.T) {
	_, _, err := resolveTestSelection([]string{"playtest"}, false, "", false, false)
	if err == nil {
		t.Fatal("expected error when playtest has neither --suite nor --all")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd gol-tools/cli && go test ./cmd/ -run TestResolveTestSelection_Playtest -v`
Expected: `TestResolveTestSelection_PlaytestAll` FAIL (current code rejects `--all` combined with a tier arg, and rejects playtest without `--suite`)

- [ ] **Step 3: Modify resolveTestSelection to support playtest --all**

In `gol-tools/cli/cmd/test.go`, replace `resolveTestSelection`:

```go
func resolveTestSelection(args []string, all bool, suiteArg string, record bool, verbose bool) (testrunner.Tier, testrunner.RunOptions, error) {
	if all && len(args) > 0 && args[0] != "playtest" {
		return 0, testrunner.RunOptions{}, fmt.Errorf("--all cannot be combined with %s tier (only playtest supports --all)", args[0])
	}
	if !all && len(args) == 0 {
		return 0, testrunner.RunOptions{}, fmt.Errorf("running all tests requires explicit --all; targeted runs require 'unit --suite <names>', 'integration --suite <names>', or 'playtest --suite <names>'")
	}

	suites := parseSuiteList(suiteArg)

	tierArg := ""
	if len(args) > 0 {
		tierArg = args[0]
	}
	tier, err := testrunner.ParseTier(tierArg)
	if err != nil {
		return 0, testrunner.RunOptions{}, err
	}

	// For unit/integration, --suite is always required
	if (tier == testrunner.TierUnit || tier == testrunner.TierIntegration) && len(suites) == 0 {
		return 0, testrunner.RunOptions{}, fmt.Errorf("gol test %s requires --suite <names>; use --all only when intentionally running the full automated test set", args[0])
	}

	// For playtest, either --suite or --all is required
	if tier == testrunner.TierPlaytest && len(suites) == 0 && !all {
		return 0, testrunner.RunOptions{}, fmt.Errorf("gol test playtest requires --suite <names> or --all")
	}

	// --all without a tier arg means unit+integration (existing behavior)
	if all && len(args) == 0 {
		tier = testrunner.TierAll
	}
	// --all with playtest means run all playtest suites (suites stays nil = discover all)
	if all && tier == testrunner.TierPlaytest {
		suites = nil
	}

	if record && tier != testrunner.TierPlaytest {
		return 0, testrunner.RunOptions{}, fmt.Errorf("--record requires the playtest tier")
	}

	opts := testrunner.RunOptions{
		Record:  record,
		Verbose: verbose,
		Suite:   suites,
	}
	return tier, opts, nil
}
```

Also update the `testRun` function to handle `TierPlaytest` when invoked via `--all`:

In `runner.go`, the `Run` function already handles `TierPlaytest` correctly — when `opts.Suite` is nil, `discoverPlaytests` returns all suites. No change needed there.

But `testRun` in `test.go` needs to handle the case where `--all` is passed with `playtest` arg. The current `testRun` calls `resolveTestSelection` which now returns `TierPlaytest` with nil suites — this flows correctly through `Run()` → `RunPlaytest()` → `discoverPlaytests()` with empty filter → returns all.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/cli && go test ./cmd/ -run TestResolveTestSelection -v`
Expected: PASS

- [ ] **Step 5: Update the command usage string**

In `test.go`, update the `Use` field:

```go
Use: "test (--all | unit --suite <names> | integration --suite <names> | playtest (--suite <names> | --all))",
```

- [ ] **Step 6: Build and verify CLI help**

Run: `cd gol-tools/cli && go build -o gol . && ./gol test --help`
Expected: Usage shows `playtest (--suite <names> | --all)`

- [ ] **Step 7: Commit**

```bash
cd gol-tools/cli
git add cmd/test.go cmd/test_test.go
git commit -m "feat(cli): support gol test playtest --all to run all suites"
```

---

## Task 1: Template Expression Evaluator

**Files:**
- Create: `gol-tools/foreman/lib/template-eval.mts`
- Create: `gol-tools/foreman/tests/template-eval.test.mts`

The evaluator resolves `{{...}}` expressions in strings against a context object. It supports property access, equality/inequality comparisons, boolean `&&`/`||`, and string literals.

- [ ] **Step 1: Write the failing tests**

Create `tests/template-eval.test.mts`:

```typescript
import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { evaluateTemplate, evaluateCondition } from '../lib/template-eval.mts'

describe('evaluateTemplate', () => {
  const ctx = {
    steps: {
      unit: { exit_code: 1, status: 'completed', result: 'fail', summary: '3 tests failed' },
      goap: { exit_code: 0, status: 'completed', result: 'pass', summary: 'all good' },
    },
    workflow: { has_failure: true, has_error: false, all_passed: false, errors_summary: '' },
    workspace_path: '/tmp/gol-project',
  }

  it('replaces simple variable references', () => {
    assert.equal(evaluateTemplate('path: {{workspace_path}}', ctx), 'path: /tmp/gol-project')
  })

  it('replaces nested property references', () => {
    assert.equal(evaluateTemplate('{{steps.unit.result}}', ctx), 'fail')
  })

  it('evaluates equality expressions to string', () => {
    assert.equal(evaluateTemplate('{{steps.unit.result == "fail" && steps.unit.summary}}', ctx), '3 tests failed')
  })

  it('evaluates false && to empty string', () => {
    assert.equal(evaluateTemplate('{{steps.goap.result == "fail" && steps.goap.summary}}', ctx), '')
  })

  it('leaves unknown references as empty string', () => {
    assert.equal(evaluateTemplate('{{steps.unknown.result}}', ctx), '')
  })
})

describe('evaluateCondition', () => {
  const ctx = {
    steps: {
      unit: { exit_code: 1, status: 'completed', result: 'fail' },
    },
    workflow: { has_failure: true, has_error: false },
  }

  it('evaluates boolean property to true', () => {
    assert.equal(evaluateCondition('{{workflow.has_failure}}', ctx), true)
  })

  it('evaluates boolean property to false', () => {
    assert.equal(evaluateCondition('{{workflow.has_error}}', ctx), false)
  })

  it('evaluates comparison expression', () => {
    assert.equal(evaluateCondition('{{steps.unit.exit_code != 0}}', ctx), true)
  })

  it('evaluates equality with string literal', () => {
    assert.equal(evaluateCondition('{{steps.unit.result == "fail"}}', ctx), true)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && npx tsx --test tests/template-eval.test.mts`
Expected: FAIL (module not found)

- [ ] **Step 3: Implement template-eval.mts**

Create `lib/template-eval.mts`:

```typescript
export interface TemplateContext {
  steps: Record<string, Record<string, unknown>>
  workflow: Record<string, unknown>
  [key: string]: unknown
}

export function evaluateTemplate(template: string, ctx: TemplateContext): string {
  return template.replace(/\{\{(.+?)\}\}/g, (_match, expr: string) => {
    const result = evaluateExpression(expr.trim(), ctx)
    if (result === null || result === undefined || result === false) return ''
    if (result === true) return 'true'
    return String(result)
  })
}

export function evaluateCondition(template: string, ctx: TemplateContext): boolean {
  const inner = template.replace(/^\{\{/, '').replace(/\}\}$/, '').trim()
  const result = evaluateExpression(inner, ctx)
  return Boolean(result)
}

function evaluateExpression(expr: string, ctx: TemplateContext): unknown {
  // Handle && (short-circuit: left falsy → '', left truthy → right)
  const andParts = splitOnOperator(expr, '&&')
  if (andParts) {
    const left = evaluateExpression(andParts[0], ctx)
    if (!left) return ''
    return evaluateExpression(andParts[1], ctx)
  }

  // Handle || (short-circuit: left truthy → left, left falsy → right)
  const orParts = splitOnOperator(expr, '||')
  if (orParts) {
    const left = evaluateExpression(orParts[0], ctx)
    if (left) return left
    return evaluateExpression(orParts[1], ctx)
  }

  // Handle != comparison
  const neqParts = splitOnOperator(expr, '!=')
  if (neqParts) {
    const left = resolveValue(neqParts[0].trim(), ctx)
    const right = resolveValue(neqParts[1].trim(), ctx)
    return left != right
  }

  // Handle == comparison
  const eqParts = splitOnOperator(expr, '==')
  if (eqParts) {
    const left = resolveValue(eqParts[0].trim(), ctx)
    const right = resolveValue(eqParts[1].trim(), ctx)
    return left == right
  }

  // Plain property reference
  return resolveValue(expr, ctx)
}

function splitOnOperator(expr: string, op: string): [string, string] | null {
  let depth = 0
  let inString = false
  let stringChar = ''

  for (let i = 0; i <= expr.length - op.length; i++) {
    const ch = expr[i]
    if (inString) {
      if (ch === stringChar && expr[i - 1] !== '\\') inString = false
      continue
    }
    if (ch === '"' || ch === "'") {
      inString = true
      stringChar = ch
      continue
    }
    if (ch === '(') { depth++; continue }
    if (ch === ')') { depth--; continue }
    if (depth === 0 && expr.slice(i, i + op.length) === op) {
      return [expr.slice(0, i).trim(), expr.slice(i + op.length).trim()]
    }
  }
  return null
}

function resolveValue(token: string, ctx: TemplateContext): unknown {
  // String literal
  if ((token.startsWith('"') && token.endsWith('"')) || (token.startsWith("'") && token.endsWith("'"))) {
    return token.slice(1, -1)
  }

  // Numeric literal
  if (/^-?\d+(\.\d+)?$/.test(token)) {
    return Number(token)
  }

  // Boolean literal
  if (token === 'true') return true
  if (token === 'false') return false
  if (token === 'null') return null

  // Property path (e.g. steps.unit.exit_code)
  return resolvePath(token, ctx)
}

function resolvePath(path: string, obj: unknown): unknown {
  const parts = path.split('.')
  let current: unknown = obj
  for (const part of parts) {
    if (current === null || current === undefined) return undefined
    if (typeof current !== 'object') return undefined
    current = (current as Record<string, unknown>)[part]
  }
  return current
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/foreman && npx tsx --test tests/template-eval.test.mts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/template-eval.mts tests/template-eval.test.mts
git commit -m "feat(foreman): add template expression evaluator for workflows"
```

---

## Task 2: Shell Step Executor

**Files:**
- Create: `gol-tools/foreman/lib/shell-executor.mts`
- Create: `gol-tools/foreman/tests/shell-executor.test.mts`

Spawns a shell command, captures stdout/stderr, and maps exit codes to the two-dimensional status/result model.

- [ ] **Step 1: Write the failing tests**

Create `tests/shell-executor.test.mts`:

```typescript
import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { executeShell, mapExitCode, type ShellStepOutput } from '../lib/shell-executor.mts'

describe('mapExitCode', () => {
  it('maps 0 to completed/pass', () => {
    const result = mapExitCode(0)
    assert.equal(result.status, 'completed')
    assert.equal(result.result, 'pass')
  })

  it('maps 1 to completed/fail', () => {
    const result = mapExitCode(1)
    assert.equal(result.status, 'completed')
    assert.equal(result.result, 'fail')
  })

  it('maps 2+ to error/null', () => {
    const result = mapExitCode(2)
    assert.equal(result.status, 'error')
    assert.equal(result.result, null)
  })

  it('maps 127 to error/null', () => {
    const result = mapExitCode(127)
    assert.equal(result.status, 'error')
    assert.equal(result.result, null)
  })
})

describe('executeShell', () => {
  it('captures stdout from a passing command', async () => {
    const output = await executeShell('echo hello', '/tmp')
    assert.equal(output.status, 'completed')
    assert.equal(output.result, 'pass')
    assert.equal(output.exit_code, 0)
    assert.match(output.stdout, /hello/)
  })

  it('captures exit code 1 as completed/fail', async () => {
    const output = await executeShell('exit 1', '/tmp')
    assert.equal(output.status, 'completed')
    assert.equal(output.result, 'fail')
    assert.equal(output.exit_code, 1)
  })

  it('captures exit code 2 as error/null', async () => {
    const output = await executeShell('exit 2', '/tmp')
    assert.equal(output.status, 'error')
    assert.equal(output.result, null)
    assert.equal(output.exit_code, 2)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && npx tsx --test tests/shell-executor.test.mts`
Expected: FAIL (module not found)

- [ ] **Step 3: Implement shell-executor.mts**

Create `lib/shell-executor.mts`:

```typescript
import { spawn } from 'node:child_process'

export type StepStatus = 'completed' | 'error' | 'skipped' | 'gate_failed'
export type StepResult = 'pass' | 'fail' | null

export interface ShellStepOutput {
  status: StepStatus
  result: StepResult
  exit_code: number
  stdout: string
  summary: string
}

const MAX_STDOUT_BYTES = 32_000

export function mapExitCode(code: number): { status: StepStatus; result: StepResult } {
  if (code === 0) return { status: 'completed', result: 'pass' }
  if (code === 1) return { status: 'completed', result: 'fail' }
  return { status: 'error', result: null }
}

export function executeShell(command: string, cwd: string): Promise<ShellStepOutput> {
  return new Promise((resolve) => {
    const child = spawn('sh', ['-c', command], {
      cwd,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env },
    })

    let stdout = ''
    let stderr = ''

    child.stdout.on('data', (chunk: Buffer) => {
      const text = chunk.toString('utf8')
      if (Buffer.byteLength(stdout, 'utf8') < MAX_STDOUT_BYTES) {
        stdout += text
      }
    })

    child.stderr.on('data', (chunk: Buffer) => {
      const text = chunk.toString('utf8')
      if (Buffer.byteLength(stderr, 'utf8') < MAX_STDOUT_BYTES) {
        stderr += text
      }
    })

    child.on('error', (err) => {
      resolve({
        status: 'error',
        result: null,
        exit_code: 127,
        stdout: '',
        summary: `Failed to start: ${err.message}`,
      })
    })

    child.on('exit', (code) => {
      const exitCode = code ?? 1
      const { status, result } = mapExitCode(exitCode)
      const combined = (stdout + stderr).trim()
      const summaryLines = combined.split('\n').slice(-20)
      resolve({
        status,
        result,
        exit_code: exitCode,
        stdout: stdout.trim(),
        summary: summaryLines.join('\n'),
      })
    })
  })
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/foreman && npx tsx --test tests/shell-executor.test.mts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/shell-executor.mts tests/shell-executor.test.mts
git commit -m "feat(foreman): add shell step executor with exit code mapping"
```

---

## Task 3: Workflow Loader

**Files:**
- Create: `gol-tools/foreman/lib/workflow-loader.mts`
- Create: `gol-tools/foreman/tests/workflow-loader.test.mts`

Loads workflow YAML files, validates schema, and returns typed workflow definitions.

- [ ] **Step 1: Write the failing tests**

Create `tests/workflow-loader.test.mts`:

```typescript
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, it } from 'node:test'
import { loadWorkflow, loadAllWorkflows, type WorkflowDefinition } from '../lib/workflow-loader.mts'

function writeWorkflow(dir: string, name: string, content: string): string {
  const path = join(dir, `${name}.yaml`)
  writeFileSync(path, content, 'utf-8')
  return path
}

describe('loadWorkflow', () => {
  it('loads a valid workflow with shell steps', () => {
    const dir = mkdtempSync(join(tmpdir(), 'wf-'))
    writeWorkflow(dir, 'test', `
name: test
description: A test workflow
steps:
  - id: hello
    shell: echo hello
`)
    const wf = loadWorkflow(join(dir, 'test.yaml'))
    assert.equal(wf.name, 'test')
    assert.equal(wf.steps.length, 1)
    assert.equal(wf.steps[0].id, 'hello')
    assert.equal(wf.steps[0].type, 'shell')
  })

  it('parses requires at workflow level', () => {
    const dir = mkdtempSync(join(tmpdir(), 'wf-'))
    writeWorkflow(dir, 'gated', `
name: gated
description: Gated workflow
requires:
  - shell: "true"
    message: always passes
    on_fail: skip
steps:
  - id: run
    shell: echo ok
`)
    const wf = loadWorkflow(join(dir, 'gated.yaml'))
    assert.equal(wf.requires!.length, 1)
    assert.equal(wf.requires![0].on_fail, 'skip')
  })

  it('rejects workflow without steps', () => {
    const dir = mkdtempSync(join(tmpdir(), 'wf-'))
    writeWorkflow(dir, 'empty', `
name: empty
description: No steps
`)
    assert.throws(() => loadWorkflow(join(dir, 'empty.yaml')), /must have at least one step/)
  })

  it('rejects step without id', () => {
    const dir = mkdtempSync(join(tmpdir(), 'wf-'))
    writeWorkflow(dir, 'noid', `
name: noid
description: Missing id
steps:
  - shell: echo hi
`)
    assert.throws(() => loadWorkflow(join(dir, 'noid.yaml')), /must have an 'id'/)
  })

  it('rejects duplicate step ids', () => {
    const dir = mkdtempSync(join(tmpdir(), 'wf-'))
    writeWorkflow(dir, 'dup', `
name: dup
description: Duplicate ids
steps:
  - id: same
    shell: echo 1
  - id: same
    shell: echo 2
`)
    assert.throws(() => loadWorkflow(join(dir, 'dup.yaml')), /duplicate step id/)
  })
})

describe('loadAllWorkflows', () => {
  it('loads all yaml files from a directory', () => {
    const dir = mkdtempSync(join(tmpdir(), 'wf-'))
    writeWorkflow(dir, 'a', 'name: a\ndescription: A\nsteps:\n  - id: x\n    shell: echo a')
    writeWorkflow(dir, 'b', 'name: b\ndescription: B\nsteps:\n  - id: y\n    shell: echo b')
    const workflows = loadAllWorkflows(dir)
    assert.equal(workflows.size, 2)
    assert.ok(workflows.has('a'))
    assert.ok(workflows.has('b'))
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && npx tsx --test tests/workflow-loader.test.mts`
Expected: FAIL (module not found)

- [ ] **Step 3: Implement workflow-loader.mts**

Create `lib/workflow-loader.mts`:

```typescript
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { parse as parseYaml } from 'yaml'

export type GateOnFail = 'skip' | 'abort' | 'notify'

export interface GateDefinition {
  shell: string
  message: string
  on_fail: GateOnFail
}

export type StepType = 'shell' | 'agent' | 'notify'

export interface StepDefinition {
  id: string
  type: StepType
  shell?: string
  task?: string
  args?: Record<string, string>
  notify?: { message: string }
  when?: string
  continue_on_failure?: boolean
  requires?: GateDefinition[]
}

export interface WorkflowDefinition {
  name: string
  description: string
  requires?: GateDefinition[]
  steps: StepDefinition[]
}

export function loadWorkflow(filePath: string): WorkflowDefinition {
  const raw = readFileSync(filePath, 'utf-8')
  const data = parseYaml(raw) as Record<string, unknown>

  if (!data.name || typeof data.name !== 'string') {
    throw new Error(`Workflow at ${filePath} must have a 'name' field`)
  }
  if (!data.steps || !Array.isArray(data.steps) || data.steps.length === 0) {
    throw new Error(`Workflow '${data.name}' must have at least one step`)
  }

  const requires = parseGates(data.requires as unknown[] | undefined)
  const steps = parseSteps(data.steps as unknown[], data.name as string)

  return {
    name: data.name as string,
    description: (data.description as string) || '',
    requires: requires.length > 0 ? requires : undefined,
    steps,
  }
}

export function loadAllWorkflows(dir: string): Map<string, WorkflowDefinition> {
  const workflows = new Map<string, WorkflowDefinition>()
  if (!existsSync(dir)) return workflows

  for (const file of readdirSync(dir)) {
    if (!file.endsWith('.yaml') && !file.endsWith('.yml')) continue
    const wf = loadWorkflow(join(dir, file))
    workflows.set(wf.name, wf)
  }
  return workflows
}

function parseGates(raw: unknown[] | undefined): GateDefinition[] {
  if (!raw || !Array.isArray(raw)) return []
  return raw.map((item) => {
    const gate = item as Record<string, unknown>
    return {
      shell: String(gate.shell ?? ''),
      message: String(gate.message ?? ''),
      on_fail: (gate.on_fail as GateOnFail) || 'skip',
    }
  })
}

function parseSteps(raw: unknown[], workflowName: string): StepDefinition[] {
  const ids = new Set<string>()
  return raw.map((item, index) => {
    const step = item as Record<string, unknown>
    if (!step.id || typeof step.id !== 'string') {
      throw new Error(`Step ${index} in workflow '${workflowName}' must have an 'id' field`)
    }
    if (ids.has(step.id)) {
      throw new Error(`Workflow '${workflowName}' has duplicate step id '${step.id}'`)
    }
    ids.add(step.id)

    const type = resolveStepType(step)
    return {
      id: step.id as string,
      type,
      shell: step.shell as string | undefined,
      task: step.task as string | undefined,
      args: step.args as Record<string, string> | undefined,
      notify: step.notify as { message: string } | undefined,
      when: step.when as string | undefined,
      continue_on_failure: step.continue_on_failure as boolean | undefined,
      requires: parseGates(step.requires as unknown[] | undefined) || undefined,
    }
  })
}

function resolveStepType(step: Record<string, unknown>): StepType {
  if (step.shell) return 'shell'
  if (step.task) return 'agent'
  if (step.notify) return 'notify'
  throw new Error(`Step '${step.id}' must have one of: shell, task, notify`)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/foreman && npx tsx --test tests/workflow-loader.test.mts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/workflow-loader.mts tests/workflow-loader.test.mts
git commit -m "feat(foreman): add workflow YAML loader with validation"
```

---

## Task 4: Workflow Runner

**Files:**
- Create: `gol-tools/foreman/lib/workflow-runner.mts`
- Create: `gol-tools/foreman/tests/workflow-runner.test.mts`

The core execution loop: evaluates gates, dispatches steps by type, manages context, propagates failures.

- [ ] **Step 1: Write the failing tests**

Create `tests/workflow-runner.test.mts`:

```typescript
import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { runWorkflow, type WorkflowRunResult } from '../lib/workflow-runner.mts'
import type { WorkflowDefinition } from '../lib/workflow-loader.mts'

describe('runWorkflow', () => {
  it('runs shell steps in sequence and collects results', async () => {
    const wf: WorkflowDefinition = {
      name: 'test',
      description: '',
      steps: [
        { id: 'a', type: 'shell', shell: 'echo alpha' },
        { id: 'b', type: 'shell', shell: 'echo beta' },
      ],
    }
    const result = await runWorkflow(wf, { workspacePath: '/tmp', notify: false })
    assert.equal(result.status, 'passed')
    assert.equal(result.steps.a.result, 'pass')
    assert.equal(result.steps.b.result, 'pass')
    assert.match(result.steps.a.stdout, /alpha/)
  })

  it('stops on failure when continue_on_failure is false', async () => {
    const wf: WorkflowDefinition = {
      name: 'test',
      description: '',
      steps: [
        { id: 'fail', type: 'shell', shell: 'exit 1' },
        { id: 'skip', type: 'shell', shell: 'echo should-not-run' },
      ],
    }
    const result = await runWorkflow(wf, { workspacePath: '/tmp', notify: false })
    assert.equal(result.status, 'failed')
    assert.equal(result.steps.fail.result, 'fail')
    assert.equal(result.steps.skip.status, 'skipped')
  })

  it('continues on failure when continue_on_failure is true', async () => {
    const wf: WorkflowDefinition = {
      name: 'test',
      description: '',
      steps: [
        { id: 'fail', type: 'shell', shell: 'exit 1', continue_on_failure: true },
        { id: 'next', type: 'shell', shell: 'echo still-running' },
      ],
    }
    const result = await runWorkflow(wf, { workspacePath: '/tmp', notify: false })
    assert.equal(result.status, 'failed')
    assert.equal(result.steps.fail.result, 'fail')
    assert.equal(result.steps.next.result, 'pass')
  })

  it('skips steps whose when condition is false', async () => {
    const wf: WorkflowDefinition = {
      name: 'test',
      description: '',
      steps: [
        { id: 'pass', type: 'shell', shell: 'echo ok' },
        { id: 'conditional', type: 'shell', shell: 'echo nope', when: '{{workflow.has_failure}}' },
      ],
    }
    const result = await runWorkflow(wf, { workspacePath: '/tmp', notify: false })
    assert.equal(result.steps.conditional.status, 'skipped')
  })

  it('executes when-guarded steps even after a non-continue failure', async () => {
    const wf: WorkflowDefinition = {
      name: 'test',
      description: '',
      steps: [
        { id: 'fail', type: 'shell', shell: 'exit 1' },
        { id: 'alert', type: 'shell', shell: 'echo alerting', when: '{{workflow.has_failure}}' },
      ],
    }
    const result = await runWorkflow(wf, { workspacePath: '/tmp', notify: false })
    assert.equal(result.steps.fail.result, 'fail')
    assert.equal(result.steps.alert.result, 'pass')
  })

  it('skips entire workflow when gate fails with on_fail=skip', async () => {
    const wf: WorkflowDefinition = {
      name: 'test',
      description: '',
      requires: [{ shell: 'exit 1', message: 'gate failed', on_fail: 'skip' }],
      steps: [
        { id: 'run', type: 'shell', shell: 'echo should-not-run' },
      ],
    }
    const result = await runWorkflow(wf, { workspacePath: '/tmp', notify: false })
    assert.equal(result.status, 'skipped')
    assert.equal(Object.keys(result.steps).length, 0)
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd gol-tools/foreman && npx tsx --test tests/workflow-runner.test.mts`
Expected: FAIL (module not found)

- [ ] **Step 3: Implement workflow-runner.mts**

Create `lib/workflow-runner.mts`:

```typescript
import type { WorkflowDefinition, StepDefinition, GateDefinition } from './workflow-loader.mts'
import { executeShell, type ShellStepOutput, type StepStatus, type StepResult } from './shell-executor.mts'
import { evaluateTemplate, evaluateCondition, type TemplateContext } from './template-eval.mts'
import { createNotifier, type NotifyConfig } from './notifier.mts'

export interface StepOutput {
  status: StepStatus
  result: StepResult
  exit_code: number
  stdout: string
  summary: string
  artifacts_dir: string
}

export type WorkflowStatus = 'passed' | 'failed' | 'error' | 'skipped'

export interface WorkflowRunResult {
  status: WorkflowStatus
  steps: Record<string, StepOutput>
  gateMessage?: string
}

export interface WorkflowRunOptions {
  workspacePath: string
  notify: boolean
  notifyConfig?: NotifyConfig
  artifactsRoot?: string
  skipRequires?: boolean
}

export async function runWorkflow(wf: WorkflowDefinition, opts: WorkflowRunOptions): Promise<WorkflowRunResult> {
  const stepsOutput: Record<string, StepOutput> = {}
  let hasFailure = false
  let hasError = false
  let stopped = false

  // Evaluate workflow-level gates
  if (!opts.skipRequires && wf.requires) {
    const gateResult = await evaluateGates(wf.requires, opts.workspacePath)
    if (gateResult) {
      if (gateResult.on_fail === 'notify' && opts.notify && opts.notifyConfig) {
        const notifier = createNotifier(opts.notifyConfig)
        await notifier.notify({
          taskId: wf.name,
          taskName: wf.name,
          status: 'cancelled',
          prUrl: null,
          duration: '0s',
          summary: gateResult.message,
        })
      }
      return { status: 'skipped', steps: {}, gateMessage: gateResult.message }
    }
  }

  for (const step of wf.steps) {
    const ctx = buildContext(stepsOutput, hasFailure, hasError, opts.workspacePath)

    // If workflow is stopped (previous failure without continue_on_failure),
    // only execute steps that have a `when` condition that evaluates to true
    if (stopped) {
      if (!step.when || !evaluateCondition(step.when, ctx)) {
        stepsOutput[step.id] = skippedOutput()
        continue
      }
    }

    // Evaluate step-level gates
    if (step.requires) {
      const gateResult = await evaluateGates(step.requires, opts.workspacePath)
      if (gateResult) {
        stepsOutput[step.id] = gateFailedOutput()
        if (gateResult.on_fail === 'abort') {
          return { status: 'error', steps: stepsOutput, gateMessage: gateResult.message }
        }
        if (gateResult.on_fail === 'notify' && opts.notify && opts.notifyConfig) {
          const notifier = createNotifier(opts.notifyConfig)
          await notifier.notify({
            taskId: wf.name,
            taskName: wf.name,
            status: 'failed',
            prUrl: null,
            duration: '0s',
            summary: gateResult.message,
          })
        }
        continue
      }
    }

    // Evaluate when condition
    if (step.when && !evaluateCondition(step.when, ctx)) {
      stepsOutput[step.id] = skippedOutput()
      continue
    }

    // Execute step
    const output = await executeStep(step, ctx, opts)
    stepsOutput[step.id] = output

    if (output.result === 'fail') hasFailure = true
    if (output.status === 'error') hasError = true

    if (output.status !== 'completed' && output.status !== 'skipped') {
      if (!step.continue_on_failure) stopped = true
    }
    if (output.result === 'fail' && !step.continue_on_failure) {
      stopped = true
    }
  }

  const status: WorkflowStatus = hasError ? 'error' : hasFailure ? 'failed' : 'passed'
  return { status, steps: stepsOutput }
}

async function executeStep(step: StepDefinition, ctx: TemplateContext, opts: WorkflowRunOptions): Promise<StepOutput> {
  if (step.type === 'shell') {
    const command = evaluateTemplate(step.shell!, ctx)
    const result = await executeShell(command, opts.workspacePath)
    return { ...result, artifacts_dir: '' }
  }

  if (step.type === 'notify') {
    if (!opts.notify || !opts.notifyConfig) {
      return { status: 'completed', result: 'pass', exit_code: 0, stdout: '', summary: 'notify skipped (disabled)', artifacts_dir: '' }
    }
    const message = evaluateTemplate(step.notify!.message, ctx)
    try {
      const notifier = createNotifier(opts.notifyConfig)
      await notifier.notify({
        taskId: 'workflow',
        taskName: step.id,
        status: 'failed',
        prUrl: null,
        duration: '',
        summary: message,
      })
      return { status: 'completed', result: 'pass', exit_code: 0, stdout: '', summary: 'notification sent', artifacts_dir: '' }
    } catch (e) {
      return { status: 'error', result: null, exit_code: 1, stdout: '', summary: `notify failed: ${(e as Error).message}`, artifacts_dir: '' }
    }
  }

  if (step.type === 'agent') {
    // Agent steps will be implemented in a follow-up; for now return a placeholder error
    return { status: 'error', result: null, exit_code: 1, stdout: '', summary: 'agent steps not yet implemented', artifacts_dir: '' }
  }

  return { status: 'error', result: null, exit_code: 1, stdout: '', summary: `unknown step type`, artifacts_dir: '' }
}

async function evaluateGates(gates: GateDefinition[], cwd: string): Promise<GateDefinition | null> {
  for (const gate of gates) {
    const result = await executeShell(gate.shell, cwd)
    if (result.exit_code !== 0) {
      return gate
    }
  }
  return null
}

function buildContext(steps: Record<string, StepOutput>, hasFailure: boolean, hasError: boolean, workspacePath: string): TemplateContext {
  const errorSummaries = Object.values(steps)
    .filter(s => s.status === 'error')
    .map(s => s.summary)
    .join('\n')

  return {
    steps: steps as unknown as Record<string, Record<string, unknown>>,
    workflow: {
      has_failure: hasFailure,
      has_error: hasError,
      all_passed: !hasFailure && !hasError,
      errors_summary: errorSummaries,
    },
    workspace_path: workspacePath,
  }
}

function skippedOutput(): StepOutput {
  return { status: 'skipped', result: null, exit_code: 0, stdout: '', summary: '', artifacts_dir: '' }
}

function gateFailedOutput(): StepOutput {
  return { status: 'gate_failed', result: null, exit_code: 0, stdout: '', summary: '', artifacts_dir: '' }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd gol-tools/foreman && npx tsx --test tests/workflow-runner.test.mts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd gol-tools/foreman
git add lib/workflow-runner.mts tests/workflow-runner.test.mts
git commit -m "feat(foreman): add workflow runner with gates, conditions, and failure propagation"
```

---

## Task 5: CLI Integration

**Files:**
- Modify: `gol-tools/foreman/bin/foreman.mts`
- Modify: `gol-tools/foreman/lib/cron.mts`

Add `foreman run workflow <name>`, `foreman workflow list`, and cron support for `--workflow`.

- [ ] **Step 1: Add workflow CLI commands to foreman.mts**

In `bin/foreman.mts`, add imports at the top:

```typescript
import { loadWorkflow, loadAllWorkflows } from '../lib/workflow-loader.mts'
import { runWorkflow } from '../lib/workflow-runner.mts'
```

Add a `workflowsDir` constant after `tasksDir`:

```typescript
const workflowsDir = join(foremanDir, 'workflows')
```

Add handler functions:

```typescript
async function handleRunWorkflow(args: string[]): Promise<number> {
  try {
    const { values: flags, positionals } = parseArgs({
      args,
      options: {
        foreground: { type: 'boolean' },
        'skip-requires': { type: 'boolean' },
      },
      allowPositionals: true,
      strict: true,
    })

    const name = positionals[0]
    if (!name) {
      console.error('Usage: foreman run workflow <name> [--foreground] [--skip-requires]')
      return 1
    }

    const wfPath = join(workflowsDir, `${name}.yaml`)
    if (!existsSync(wfPath)) {
      console.error(`Workflow '${name}' not found at ${wfPath}`)
      return 1
    }

    const config = loadConfig()
    const workDir = resolveWorkDir()
    const repoDir = resolveRepoDir(workDir)
    const wf = loadWorkflow(wfPath)

    console.log(`Workflow '${wf.name}' starting (${wf.steps.length} steps)`)
    console.log(`Workspace: ${repoDir}`)

    const result = await runWorkflow(wf, {
      workspacePath: repoDir,
      notify: notificationsEnabled(config),
      notifyConfig: notificationsEnabled(config) ? config.notify : undefined,
      skipRequires: !!flags['skip-requires'],
    })

    console.log(`Workflow '${wf.name}' finished: ${result.status}`)
    if (result.gateMessage) {
      console.log(`Gate: ${result.gateMessage}`)
    }
    for (const [id, step] of Object.entries(result.steps)) {
      const icon = step.result === 'pass' ? '✓' : step.result === 'fail' ? '✗' : step.status === 'skipped' ? '○' : '!'
      console.log(`  ${icon} ${id}: ${step.status}${step.result ? ` (${step.result})` : ''}`)
    }

    return result.status === 'passed' || result.status === 'skipped' ? 0 : 1
  } catch (e) {
    console.error((e as Error).message)
    return 1
  }
}

function handleWorkflowList(): number {
  const workflows = loadAllWorkflows(workflowsDir)
  if (workflows.size === 0) {
    console.log('No workflows')
    return 0
  }
  console.log('Name                          Description                                    Steps')
  console.log('─'.repeat(90))
  for (const [, wf] of workflows) {
    console.log(`${wf.name.padEnd(30)}${wf.description.slice(0, 45).padEnd(47)}${wf.steps.length}`)
  }
  return 0
}
```

Add routing in the `main()` switch:

```typescript
case 'run':
  if (subcommand === 'task') return handleRunTask(args.slice(2))
  if (subcommand === 'workflow') return handleRunWorkflow(args.slice(2))
  console.error('Usage: foreman run <task|workflow> <name> [--args...]')
  return 1

// Add new top-level command:
case 'workflow':
  if (subcommand === 'list') return handleWorkflowList()
  console.error('Usage: foreman workflow <list>')
  return 1
```

Update the help text to include workflow commands.

- [ ] **Step 2: Add --workflow support to cron.mts**

In `lib/cron.mts`, modify `addCronEntry` to accept an optional `workflow` parameter:

```typescript
export function addCronEntry(
  dataDir: string,
  foremanBin: string,
  task: string,
  schedule: string,
  prompt?: string,
): CronEntry {
```

Change to:

```typescript
export interface CronEntryOptions {
  task?: string
  workflow?: string
  schedule: string
  prompt?: string
}

export function addCronEntry(
  dataDir: string,
  foremanBin: string,
  options: CronEntryOptions,
): CronEntry {
  const entries = readCronEntries(dataDir)
  const label = options.task ?? options.workflow ?? 'unknown'
  const id = `cron_${new Date().toISOString().slice(0, 10).replace(/-/g, '')}_${randomBytes(2).toString('hex')}`

  const entry: CronEntry = {
    id,
    task: label,
    schedule: options.schedule,
    prompt: options.prompt,
    createdAt: new Date().toISOString(),
  }
  entries.push(entry)
  writeCronEntries(dataDir, entries)

  let cmd: string
  if (options.workflow) {
    cmd = `${foremanBin} run workflow ${options.workflow}`
  } else {
    cmd = `${foremanBin} run task ${options.task}`
    if (options.prompt) cmd += ` --prompt ${JSON.stringify(options.prompt)}`
  }

  const crontab = getCurrentCrontab()
  const newLine = `${options.schedule} ${cmd} ${CRON_MARKER}${id}`
  setCrontab(crontab.trimEnd() + '\n' + newLine + '\n')

  return entry
}
```

Update `handleCronAdd` in `foreman.mts` to pass the new interface and accept `--workflow` flag.

- [ ] **Step 3: Verify CLI works**

Run: `cd gol-tools/foreman && npx tsx bin/foreman.mts workflow list`
Expected: "No workflows" (no workflow files yet)

Run: `cd gol-tools/foreman && npx tsx bin/foreman.mts run workflow nonexistent`
Expected: Error "Workflow 'nonexistent' not found"

- [ ] **Step 4: Commit**

```bash
cd gol-tools/foreman
git add bin/foreman.mts lib/cron.mts
git commit -m "feat(foreman): add workflow CLI commands and cron support"
```

---

## Task 6: Nightly Tests Workflow Definition

**Files:**
- Create: `gol-tools/foreman/workflows/nightly-tests.yaml`

- [ ] **Step 1: Create the workflows directory and definition**

```bash
mkdir -p gol-tools/foreman/workflows
```

Create `workflows/nightly-tests.yaml`:

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

- [ ] **Step 2: Verify it loads**

Run: `cd gol-tools/foreman && npx tsx bin/foreman.mts workflow list`
Expected: Shows `nightly-tests` with description and 5 steps

- [ ] **Step 3: Dry-run the workflow (with --skip-requires since workspace may be dirty)**

Run: `cd gol-tools/foreman && npx tsx bin/foreman.mts run workflow nightly-tests --foreground --skip-requires`
Expected: Workflow executes all test steps (may fail if tests fail, but the runner itself should work)

- [ ] **Step 4: Commit**

```bash
cd gol-tools/foreman
git add workflows/nightly-tests.yaml
git commit -m "feat(foreman): add nightly-tests workflow definition"
```

---

## Task 7: Schedule the Nightly Cron

- [ ] **Step 1: Register the cron job**

```bash
foreman cron add --workflow nightly-tests --schedule '0 3 * * *'
```

- [ ] **Step 2: Verify cron entry**

Run: `foreman cron list`
Expected: Shows `nightly-tests` with schedule `0 3 * * *` and active=yes

- [ ] **Step 3: Commit (no code change, just verify)**

No commit needed — cron state is in `logs/foreman/` which is gitignored.

---

## Summary

| Task | What it delivers | Estimated lines |
|------|-----------------|-----------------|
| 0 | `gol test playtest --all` | ~30 lines Go |
| 1 | Template expression evaluator | ~90 lines TS + tests |
| 2 | Shell step executor | ~60 lines TS + tests |
| 3 | Workflow YAML loader | ~100 lines TS + tests |
| 4 | Workflow runner | ~150 lines TS + tests |
| 5 | CLI integration | ~80 lines TS modified |
| 6 | Nightly workflow definition | ~40 lines YAML |
| 7 | Cron scheduling | 1 command |
