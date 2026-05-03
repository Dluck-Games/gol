# Foreman v2 — Design Spec

> Refactor Foreman from a multi-agent daemon orchestrator to a simple, manual-trigger task execution CLI.

## Background

Foreman v1 is a daemon-based multi-agent orchestration system (TL → Planner → Coder → Reviewer → Tester) with document-based handoff, GitHub label-driven auto-pickup, and ~2,500 lines across 17 modules. It's overengineered and unreliable. V2 strips it down to a CLI that spawns a single coding agent per task, tracks state in a JSON file, and optionally notifies on completion.

### Core Philosophy Change

| | v1 | v2 |
|---|---|---|
| Architecture | Persistent daemon, multi-agent orchestration | CLI tool, single agent per task |
| Trigger | Auto-scan GitHub labels | Manual (`foreman run`) |
| Agent model | TL dispatches to Planner/Coder/Reviewer/Tester | One coding agent, one shot |
| Deliverable | Code + handoff documents | PR only |
| Prompt system | Nunjucks templates, role-based identity/task layers | YAML task templates with simple variable substitution |
| State | Complex (daemon recovery, pending ops, dead letter) | Minimal (active tasks + exit status) |

### Positioning

Foreman is a task runner for D.L.K — 栞 calls Foreman, Foreman calls a coding agent. It replaces manual `opencode` / `claude` invocations with templated, tracked, reproducible task execution. Clients are configured in `config.yaml` with env-file-driven model switching (e.g., `cc-glm`, `cc-kimi`, `cc-internal`).

## Approach

Clean rewrite (Approach B). New project structure from scratch, cherry-picking specific logic from v1:

- Atomic JSON write pattern (write → fsync → rename) from `state-manager.mjs`
- Process group kill (`kill(-pid)`) from `process-manager.mjs`
- Worktree cleanup edge cases (stale metadata pruning, force-remove fallback) from `workspace-manager.mjs`
- `gh` CLI error handling and rate-limit detection patterns from `github-sync.mjs` and `rate-limit-detector.mjs`

Everything else is new code.

### What Gets Deleted from v1

- `foreman-daemon.mjs`, `com.dluckdu.foreman-daemon.plist` — no daemon
- `lib/tl-dispatcher.mjs`, `lib/doc-manager.mjs`, `lib/prompt-builder.mjs` — no multi-agent orchestration
- `lib/progress-writer.mjs`, `lib/label-guard.mjs`, `lib/foreman-docs-commit.mjs` — no document handoff
- `lib/permission-utils.mjs`, `lib/daemon-runtime-utils.mjs`, `lib/tester-log-utils.mjs` — daemon-specific
- `lib/config-utils.mjs` — v1 migration logic
- Entire `prompts/` directory — replaced by task YAML templates
- `bin/foreman-ctl.mjs`, `bin/reset-label-utils.mjs` — replaced by unified CLI
- `bin/coder-run-tests.sh`, `bin/tester-ai-debug.sh` — agent-specific wrappers
- `tests/` — v1 tests for v1 modules

## Tech Stack

- **Language:** TypeScript (ESM, `.mts` files, strict mode)
- **Runtime:** `tsx` (no build step)
- **Dependencies:** `yaml` (YAML parsing), `tsx` (execution). No template engine, no framework.
- **Node APIs:** `node:child_process` (spawn), `node:fs` (state/config), `node:util` (parseArgs), `node:crypto` (task IDs)

## Project Structure

```
gol-tools/foreman/
├── bin/
│   └── foreman.mts              # CLI entry point (hashbang, arg parsing, command routing)
├── lib/
│   ├── runner.mts               # Spawns coding agent, manages fg/bg lifecycle, cancel
│   ├── state.mts                # Atomic JSON state file read/write
│   ├── worktree.mts             # Git worktree create/destroy/prune
│   ├── task-loader.mts          # YAML task template parse, validate, render
│   ├── notifier.mts             # Pluggable notification interface + backends
│   ├── github.mts               # Minimal gh CLI wrapper (issue read)
│   ├── cron.mts                 # Cron entry persistence + system crontab sync
│   └── detach-wrapper.mts       # Background mode: run agent, update state on exit, notify
├── tasks/                       # YAML task templates
│   ├── fix-issue.yaml
│   ├── implement-superpowers-plan.yaml
│   ├── scan-dead-code.yaml      # placeholder
│   ├── scan-god-system.yaml     # placeholder
│   ├── scan-god-component.yaml  # placeholder
│   ├── scan-dry.yaml            # placeholder
│   ├── scan-etc.yaml            # placeholder
│   ├── smoke-test.yaml          # placeholder
│   └── play-test.yaml           # placeholder
├── config.yaml                  # Project-specific foreman configuration
├── package.json
├── tsconfig.json
└── README.md
```

**9 modules, ~740 lines total.** Flat `lib/` directory, no nesting.

## CLI Design

### Commands

```
# Task execution
foreman run task <name> [--args...]        Run a task template
foreman run issue <issue-id> [--args...]   Shortcut: run fix-issue with --issue <id>
foreman cancel <task-id>                   Cancel a running task
foreman status                             Show active and recent tasks
foreman logs <task-id>                     Tail task log file

# Task template management
foreman task list                          List all available task templates
foreman task show <name>                   Show task template details + prompt preview

# Cron scheduling
foreman cron list                          List registered cron jobs
foreman cron add --task <name> --schedule '0 3 * * *' [--prompt "..."]
foreman cron remove <cron-id>              Remove a cron job

# Diagnostics
foreman doctor                             Validate setup, skills, clients, config
```

### Common Flags for `run`

| Flag | Description |
|---|---|
| `--prompt\|-p "..."` | Append extra instructions to the task prompt |
| `--client\|-c <name>` | Override client from task YAML (default: `opencode`) |
| `--notify` | Send notification on task completion |
| `--detach` | Fork agent as background process, exit immediately |

### Run Modes

| | Foreground (default) | Background (`--detach`) |
|---|---|---|
| Agent process | Child of foreman | Detached (survives foreman exit) |
| stdout | Streams to terminal + log file | Log file only |
| Exit code | Agent's exit code (0=success, 1=failure) | Always 0 (spawned OK) |
| State update | Foreman updates on agent exit | `detach-wrapper.mts` updates on agent exit |
| Notify | Foreman triggers on exit | `detach-wrapper.mts` triggers on exit |

### `foreman run issue` Expansion

`foreman run issue 188 -p "focus on the UI part"` is equivalent to `foreman run task fix-issue --issue 188 -p "focus on the UI part"`. Syntactic sugar, not a separate code path.

### Arg Parsing

`parseArgs` from `node:util` (built-in since Node 18.3). No external CLI framework.

## Task Template System

### YAML Schema

```yaml
name: fix-issue                              # unique task identifier
description: "Read GitHub issue, implement fix, run tests, submit PR"
client: opencode                             # default coding agent client
skills:                                      # skills to request the agent loads
  - gol-fix-issue
args:                                        # declared arguments this task accepts
  - name: issue
    required: true
    description: "GitHub issue number"
prompt: |                                    # prompt template with {{variables}}
  You are working on the god-of-lego project.
  
  {{skills_instruction}}
  
  ## Task
  Fix GitHub issue #{{issue}}.
  
  ## Issue Details
  {{issue_body}}
  
  {{worktree_instruction}}
  
  ## Instructions
  1. Read the issue carefully, understand the requirements
  2. Implement the fix following project conventions (read AGENTS.md)
  3. Run tests to verify
  4. Commit and push
  5. Create a PR linking the issue
  
  {{extra_prompt}}
  {{notify_instruction}}
```

Placeholder tasks omit the `prompt` field and include `status: placeholder`. Running a placeholder exits with an error.

### Template Variables

| Variable | Source | Description |
|---|---|---|
| `{{skills_instruction}}` | `skills` field in YAML | Auto-generated: "Use the Skill tool to invoke the following skills, then follow each exactly:\n- skill-a\n- skill-b" |
| `{{<arg_name>}}` | Task-specific args (from `args` field) | Dynamically injected per task. E.g. `{{issue}}` from `--issue`, `{{plan}}` from `--plan` |
| `{{issue_body}}` | `gh issue view` at runtime | Full issue body (only fetched when `{{issue}}` arg is present) |
| `{{extra_prompt}}` | `--prompt` flag | User's additional instructions |
| `{{notify_instruction}}` | `--notify` flag | Auto-appended notify command instruction |
| `{{worktree_instruction}}` | Runtime (if worktree created) | "A worktree has been created at {path} on branch {branch}. Do your coding work there. Do not modify the main working directory." |
| `{{workspace_path}}` | Runtime | Worktree absolute path |
| `{{branch_name}}` | Runtime | Worktree branch name |

**Rendering:** Simple string replacement (`{{var}}` → value). No template engine. Undefined variables render as empty string.

**Task-specific arg passing:** The CLI dynamically accepts `--<arg_name>` flags based on the task's `args` declaration. For example, if a task declares `args: [{name: issue, required: true}]`, then `foreman run task fix-issue --issue 188` is valid. Required args are validated before the agent spawns; missing required args cause an immediate error.

### Implemented Task Templates

**`fix-issue`:**
```yaml
name: fix-issue
description: "Read GitHub issue, implement fix, run tests, submit PR"
client: opencode
skills:
  - gol-fix-issue
args:
  - name: issue
    required: true
    description: "GitHub issue number"
prompt: |
  You are working on the god-of-lego project.
  
  {{skills_instruction}}
  
  ## Task
  Fix GitHub issue #{{issue}}.
  
  ## Issue Details
  {{issue_body}}
  
  {{worktree_instruction}}
  
  ## Instructions
  1. Read the issue carefully, understand the requirements
  2. Implement the fix following project conventions (read AGENTS.md)
  3. Run tests to verify
  4. Commit and push
  5. Create a PR linking the issue
  
  {{extra_prompt}}
  {{notify_instruction}}
```

**`implement-superpowers-plan`:**
```yaml
name: implement-superpowers-plan
description: "Execute a superpowers implementation plan document"
client: opencode
skills:
  - superpowers:subagent-driven-development
args:
  - name: plan
    required: false
    description: "Plan filename in docs/superpowers/plans/ (if omitted, agent will list available plans and ask)"
prompt: |
  You are working on the god-of-lego project.
  
  {{skills_instruction}}
  
  ## Task
  Execute an implementation plan from docs/superpowers/plans/.
  {{plan}}
  
  {{worktree_instruction}}
  
  ## Instructions
  If a plan name was provided above, read that plan document and execute it.
  If no plan name was provided, list available plans in docs/superpowers/plans/
  and ask which one to implement. Do not proceed without confirmation.
  
  1. Read the plan document carefully
  2. Follow the plan steps in order
  3. Run tests after each major step
  4. Commit progress incrementally
  5. Create a PR when complete
  
  {{extra_prompt}}
  {{notify_instruction}}
```

### Placeholder Tasks

```yaml
# scan-dead-code.yaml
name: scan-dead-code
description: "Scan for unused code across the project"
client: opencode
status: placeholder

# scan-god-system.yaml
name: scan-god-system
description: "Detect god systems (systems doing too much)"
client: opencode
status: placeholder

# scan-god-component.yaml
name: scan-god-component
description: "Detect god components (components with too many fields)"
client: opencode
status: placeholder

# scan-dry.yaml
name: scan-dry
description: "Scan for DRY violations (duplicated logic)"
client: opencode
status: placeholder

# scan-etc.yaml
name: scan-etc
description: "Check ECS orthogonality (systems touching wrong components)"
client: opencode
status: placeholder

# smoke-test.yaml
name: smoke-test
description: "Run smoke tests on the game"
client: opencode
status: placeholder

# play-test.yaml
name: play-test
description: "Run a single-feature playtest"
client: opencode
status: placeholder
```

## Runner (`lib/runner.mts`)

### Client Abstraction

```typescript
interface ClientSpec {
  binary: string
  envFile?: string               // path to .env file (relative to foreman dir)
  buildArgs(prompt: string, options: RunOptions): string[]
}
```

Clients are defined in `config.yaml`, not hardcoded. Each client variant can point to a different `.env` file for model/provider switching:

| Client | Binary | envFile | Use case |
|---|---|---|---|
| `opencode` | `opencode` | — | Default OpenCode client |
| `cc-glm` | `claude` | `.env.ccg` | Claude Code via GLM provider |
| `cc-kimi` | `claude` | `.env.cck` | Claude Code via Kimi provider |
| `cc-internal` | `claude` | `.env.cci` | Claude Code via internal provider |

### Env File Mechanism

Env files live in `gol-tools/foreman/`, gitignored (`.env.example` templates can be committed). Format is standard dotenv (`KEY=value`, one per line, `#` comments).

Runner spawn logic:
1. Look up client config from `config.yaml`
2. If `envFile` is set, parse the `.env` file into key-value pairs
3. Merge: `{ ...process.env, ...envFileVars }` (env file overrides current env)
4. `spawn(binary, args, { env: mergedEnv })`

This makes Foreman independent of shell functions, aliases, or device-specific shell profiles. The binary just needs to be on PATH.

Example `.env.ccg`:
```
Tencent_BASE_URL=https://open.bigmodel.cn/api/Tencent
Tencent_AUTH_TOKEN=xxx
Tencent_DEFAULT_SONNET_MODEL=glm-4.7
Tencent_DEFAULT_HAIKU_MODEL=glm-4.5-air
CLAUDE_CODE_DISABLE_1M_CONTEXT=1
```

### Foreground Flow

1. Task loader resolves template, renders prompt with all `{{variables}}`
2. Pre-run check: validate task's skills exist + client binary on PATH
3. Runner spawns client binary as child process (`child_process.spawn`)
4. CWD = **project root** (not worktree — agent needs access to `.claude/skills/`, `.opencode/`, etc.)
5. stdout/stderr piped to both terminal AND log file (tee pattern)
6. Foreman blocks until child exits
7. On exit: update state file, trigger notifier if `--notify`, destroy worktree
8. Exit with child's exit code

### Background Flow (`--detach`)

1. Same template resolution and prompt rendering
2. Spawn `detach-wrapper.mts` as detached process (`detached: true`, `stdio` to log file)
3. Record PID in state file
4. `child.unref()` — foreman exits immediately with code 0
5. `detach-wrapper.mts` runs the actual agent binary, waits for exit, updates state, notifies, cleans up worktree

### Process Management (cherry-picked from v1)

- **PID tracking:** Store real PID in state file
- **Process group kill:** `process.kill(-pid, 'SIGTERM')` — kills entire process tree
- **Graceful cancel:** SIGTERM → wait 5s → SIGKILL if still alive
- **Log files:** `{workDir}/.foreman/logs/{task-id}.log`

## State File (`lib/state.mts`)

### Location

`{workDir}/.foreman/state.json`

### Schema

```typescript
interface ForemanState {
  version: 1
  tasks: Record<string, Task>
}

interface Task {
  id: string                     // "task_20260426_a1b2"
  taskName: string               // "fix-issue"
  status: 'running' | 'done' | 'failed' | 'cancelled'
  pid: number | null
  issueNumber: number | null
  prUrl: string | null
  workspace: string | null       // worktree path
  client: string                 // "opencode" | "cc-glm" | "cc-kimi" | "cc-internal"
  logFile: string
  startedAt: string              // ISO timestamp
  finishedAt: string | null
  exitCode: number | null
  notify: boolean                // --notify was requested
  notified: boolean              // notification was sent
}
```

### Atomic Write

```
write to state.json.tmp → fsync → rename to state.json
```

### State Transitions

```
running → done       (exit code 0)
running → failed     (exit code non-0)
running → cancelled  (foreman cancel)
```

No queued, no intermediate states. One agent, running or not.

## Worktree Management (`lib/worktree.mts`)

### Location

`{workDir}/.worktrees/{name}/` (gitignored). Foreman creates direct children under `.worktrees/`; it must not create source-bucket subdirectories or any management-repo worktree.

### Naming

- Directory: `ws_{YYYYMMDD}T{HHMMSS}_{4-hex}`
- Branch: `foreman/issue-{N}` for fix-issue, `foreman/{task-name}-{timestamp}` for others

### CWD Convention

**Agent CWD = project root, NOT the worktree.** The coding agent needs access to harness files (`.claude/skills/`, `.opencode/`, `CLAUDE.md`, etc.) which live at the project root. The worktree path is injected into the prompt via `{{worktree_instruction}}`:

> A worktree has been created at {workspace_path} on branch {branch_name}. Do your coding work there. Do not modify the main working directory.

The agent navigates to the worktree for code edits based on this instruction and existing AGENTS.md worktree conventions.

### Lifecycle

| Step | Owner |
|---|---|
| Create worktree | Foreman (before spawning agent) |
| Spawn agent with CWD = project root | Foreman |
| Inject worktree path in prompt | Foreman |
| Navigate to worktree for code work | Coding agent |
| Push branch, create PR | Coding agent |
| Destroy worktree | Foreman (after agent exits) |

### Create

1. `git fetch origin main`
2. `git worktree prune` (clean stale metadata)
3. `git worktree add -b {branch} {path} origin/main`
4. Return worktree absolute path

### Destroy

1. `git worktree remove --force {path}`
2. Fallback: `rm -rf` if git command fails
3. `git worktree prune`
4. Branch is NOT deleted (stays for PR reference)

### Stale Worktree Handling

No background cleanup loop (no daemon). On each `foreman run`, prune stale git worktree metadata before creating a new one. Stale directories from crashed runs accumulate until next run.

## Notifier (`lib/notifier.mts`)

### Interface

```typescript
interface Notifier {
  name: string
  notify(result: TaskResult): Promise<void>
}

interface TaskResult {
  taskId: string
  taskName: string
  status: 'done' | 'failed' | 'cancelled'
  issueNumber: number | null
  prUrl: string | null
  duration: string
  summary: string
}
```

### Backends

| Backend | Config key | Implementation |
|---|---|---|
| `openclaw` | `notify.openclaw` | `openclaw message send --target X --channel Y --message "..."` |
| `system` | `notify.system` | macOS `osascript -e 'display notification "..."'` |

### Config

```yaml
# in config.yaml
notify:
  default: openclaw
  openclaw:
    target: "栞"
    channel: "foreman"
  system: {}
```

### Two-Layer Notification

1. **Prompt injection (best-effort):** Foreman appends `{{notify_instruction}}` to the agent's prompt, instructing it to call `foreman notify --task-id {id} --status <done|failed> --summary "..."` when finished. The agent may or may not execute this.

2. **State file fallback (guaranteed):** After the agent exits, Foreman (or `detach-wrapper.mts`) checks the task's `notified` field. If `--notify` was requested and `notified` is still `false`, Foreman sends a generic notification based on exit code.

### `foreman notify` (internal subcommand)

```
foreman notify --task-id <id> --status <done|failed> --summary "..."
```

Called by the coding agent. Updates state (`notified: true`, stores summary), then calls the configured notifier backend. Not listed in user-facing help.

## Cron Scheduling (`lib/cron.mts`)

### Persistence

`{workDir}/.foreman/cron-entries.json`:

```json
[
  {
    "id": "cron_20260426_a1b2",
    "task": "scan-dead-code",
    "schedule": "0 3 * * *",
    "prompt": "focus on scripts/systems/",
    "createdAt": "2026-04-26T17:00:00Z"
  }
]
```

### Implementation

- `foreman cron add` writes entry to `cron-entries.json` + installs system crontab line calling `foreman run task <name> --detach [--prompt "..."]`
- `foreman cron remove` deletes from both `cron-entries.json` and system crontab
- `foreman cron list` reads `cron-entries.json`, cross-references actual crontab for status (active/orphaned)

## Doctor (`foreman doctor`)

Validates setup and task templates:

1. **Client binaries:** All binaries referenced in `config.yaml` clients are on PATH
2. **Env files:** For each client with `envFile`, check the file exists in `gol-tools/foreman/` and is parseable (valid dotenv format, no syntax errors)
3. **Skill existence:** For each task's `skills` list — check `.claude/skills/{name}/SKILL.md` exists (Claude Code skills) or note plugin skills (`superpowers:*`)
4. **Task template validity:** All YAML files parse, required fields present
5. **Config validity:** `config.yaml` parses, required fields present
6. **State directory:** `.foreman/` exists and writable
7. **Git repo:** `gol-project/` is a valid git repo
8. **gh CLI:** `gh auth status` passes

**Pre-run check:** `foreman run` runs a fast subset — only the specific task's skills, selected client binary, and its env file (if any). Fails fast on missing dependencies.

## Config (`config.yaml`)

Lives in repo at `gol-tools/foreman/config.yaml`. `workDir` and `localRepo` are auto-detected at runtime by walking up from the foreman directory to find the management repo root and the `gol-project/` submodule — not hardcoded in config.

```yaml
repo: Dluck-Games/god-of-lego

clients:
  opencode:
    binary: opencode
  cc-glm:
    binary: claude
    envFile: .env.ccg
  cc-kimi:
    binary: claude
    envFile: .env.cck
  cc-internal:
    binary: claude
    envFile: .env.cci

notify:
  default: openclaw
  openclaw:
    target: "栞"
    channel: "foreman"
  system: {}
```

Env files (`.env.ccg`, `.env.cck`, `.env.cci`) live in `gol-tools/foreman/`, gitignored. Commit `.env.example` templates with placeholder values for documentation.

## Summary

| Module | Responsibility | ~Lines |
|---|---|---|
| `bin/foreman.mts` | CLI parsing, command routing | ~150 |
| `lib/runner.mts` | Agent spawn, fg/bg lifecycle, cancel | ~120 |
| `lib/state.mts` | Atomic JSON state read/write | ~60 |
| `lib/worktree.mts` | Git worktree create/destroy/prune | ~80 |
| `lib/task-loader.mts` | YAML parse, validate, template render | ~100 |
| `lib/notifier.mts` | Pluggable notify interface + backends | ~70 |
| `lib/github.mts` | gh CLI wrapper (issue read) | ~50 |
| `lib/cron.mts` | Cron entry persistence + crontab sync | ~80 |
| `lib/detach-wrapper.mts` | Background mode cleanup script | ~30 |
| **Total** | | **~740** |
