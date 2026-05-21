# Foreman Session Turns Design

**Date:** 2026-05-21
**Status:** Approved design draft
**Scope:** Add durable session and turn support to Foreman v2. This is not a Foreman v3 rewrite.

## Goal

Foreman should support IM-style multi-turn AI sessions for design and gameplay discussion while preserving the existing task-template entry point.

The primary user flow is:

1. Shiori receives a Telegram request such as "use superpowers brainstorming to discuss gameplay".
2. Shiori runs one strict Foreman command to start a task.
3. Foreman creates a durable session and runs turn `001`.
4. When the model finishes, Foreman sends a Telegram notification containing the final summary and session ID.
5. The user replies in Telegram.
6. Shiori resumes the same Foreman session by Foreman session ID only.
7. Foreman runs the next turn and notifies again when it finishes.

The user should not need to poll status. A Telegram notification means that turn has ended and the session is ready for the next instruction unless the notification says it failed or was cancelled.

## Core Model

Foreman keeps three distinct concepts:

| Concept | Meaning |
|---|---|
| Task | A reusable prompt/template entry point, such as `brainstorming` or `generic` |
| Session | The durable conversation created by running a task |
| Turn | One non-interactive run inside a session, representing one user prompt and one assistant completion |

`foreman run task <name>` creates a session and immediately starts turn `001`.

After that, all meaningful interaction uses the Foreman session ID, not the task ID and not the client-native session ID.

## CLI

### Start a Session

```bash
foreman run task <task-name> --prompt-file - --client <client> --notify
```

Existing task-specific flags, such as `--issue` or `--plan`, remain valid only when declared by the task template. Unknown flags fail.

New strict prompt input behavior:

- `--prompt <text>` passes prompt text directly.
- `--prompt-file <path>` reads prompt text from a file.
- `--prompt-file -` reads prompt text from stdin.
- If both `--prompt` and `--prompt-file` are provided, Foreman fails.
- If neither is provided and the rendered task has no task-specific user content, Foreman fails.
- Empty prompt content fails.

Startup output should include the Foreman session ID:

```text
Session fs_20260521_abcd started: brainstorming (client: cc-glm)
Turn: 001
Log: /.../logs/foreman/sessions/fs_20260521_abcd/turns/001.log
```

### Resume a Session

```bash
foreman session resume <session-id> --prompt-file - --notify
```

Rules:

- `<session-id>` is the Foreman session ID, for example `fs_20260521_abcd`.
- Shiori does not provide a client name when resuming.
- Foreman reads the session record and chooses the correct client adapter.
- Resume never falls back to "latest", task name, title, or client-native session pickers.
- A running session cannot be resumed.
- A closed session cannot be resumed.

### Session Operations

```bash
foreman session list
foreman session show <session-id>
foreman session log <session-id> [--turn <turn-id>] [--lines N] [--no-follow]
foreman session stop <session-id>
foreman session close <session-id>
```

Meanings:

- `list` shows recent sessions with id, task, status, client, active turn, updated time, and short title if available.
- `show` prints the session record and recent turns.
- `log` tails a turn log. Without `--turn`, it uses the active turn, or the latest turn if idle.
- `stop` cancels the currently running turn, marks that turn `cancelled`, clears `activeTurn`, and marks the session `cancelled`.
- `close` marks the session closed. It is a lifecycle operation, not a deletion.

## State and Storage

Session data lives under a session-specific directory:

```text
logs/foreman/sessions/
  fs_20260521_abcd/
    session.json
    turns/
      001.prompt.txt
      001.log
      001.last-message.txt
      002.prompt.txt
      002.log
      002.last-message.txt
```

`logs/foreman/state.json` may keep a compact index for fast `status` and `session list`, but the canonical per-session record is `session.json`.

### Session Record

```json
{
  "id": "fs_20260521_abcd",
  "taskName": "brainstorming",
  "client": "cc-glm",
  "clientFamily": "claude",
  "clientSessionId": "native-client-session-id",
  "status": "idle",
  "activeTurn": null,
  "nextTurn": 2,
  "workspace": null,
  "notify": true,
  "createdAt": "2026-05-21T00:00:00.000Z",
  "updatedAt": "2026-05-21T00:10:00.000Z",
  "title": "Gameplay brainstorming"
}
```

Session status values:

- `running`: a turn is currently active.
- `idle`: last turn completed and session can be resumed.
- `failed`: last turn failed; session may still be resumed unless closed.
- `cancelled`: last turn was cancelled.
- `closed`: session is intentionally ended and cannot be resumed.

### Turn Record

Each turn is represented in `session.json` or a compact turn index:

```json
{
  "id": "001",
  "status": "done",
  "pid": null,
  "promptFile": "turns/001.prompt.txt",
  "logFile": "turns/001.log",
  "lastMessageFile": "turns/001.last-message.txt",
  "startedAt": "2026-05-21T00:00:00.000Z",
  "finishedAt": "2026-05-21T00:10:00.000Z",
  "exitCode": 0,
  "summarySource": "claude"
}
```

Turn IDs are fixed-width decimal strings starting at `001`.

## Client Adapters

Foreman should expose one session API while hiding client differences internally.

| Client family | First turn | Resume turn | Required capture |
|---|---|---|---|
| Claude family (`cc-glm`, `cc-kimi`) | `claude -p <prompt> --output-format stream-json --verbose` | `claude --resume <clientSessionId> -p <prompt> --output-format stream-json --verbose` | `session_id` from stream-json init event |
| Codex | `codex exec ... --json --output-last-message <file> <prompt>` | `codex exec resume <clientSessionId> ... --json --output-last-message <file> <prompt>` | `thread_id` from `thread.started` |
| OpenCode | `opencode run <prompt> --format json ...` | `opencode run --session <clientSessionId> <prompt> --format json ...` | session id from JSON events or command output, verified by implementation research |

Implementation must verify OpenCode's exact new-session ID capture path before relying on it. If OpenCode cannot expose a stable session ID in non-interactive JSON output, Foreman should fail OpenCode session start with a clear error until the adapter is completed. It should not silently use `--continue` or latest-session fallback.

## Notifications

The IM experience depends on notifications being turn-completion events.

Notification format:

```text
<status icon> <task-name> <status label> [duration]
Session: fs_20260521_abcd
Turn: 001

<last assistant message or parsed summary>
```

Rules:

- Send notification only after a turn exits.
- Include the Foreman session ID on every notification.
- Include the turn ID on every notification.
- Use the existing `openclaw` backend for Telegram.
- Preserve existing message truncation safeguards.
- On failure, include the best available failure summary or final output.

Shiori can treat a completion notification as "ready for the next user instruction".

## Strictness

Foreman should prefer explicit failure over guessing.

Strict rules:

- Unknown commands and unknown flags fail.
- Missing required prompt input fails.
- Empty prompt input fails.
- `session resume` requires a Foreman session ID.
- `session resume` never accepts a client-native session ID.
- `session resume` never uses latest-session fallback.
- Running sessions cannot receive another turn.
- Closed sessions cannot receive another turn.
- If a client adapter cannot capture or resume a native session ID, Foreman fails with a plain-text reason.
- Foreman does not rewrite malformed Shiori commands into corrected commands.

This strictness is intentional. The expected recovery path is that Shiori or another AI reads the plain-text error and retries with the correct command.

## Task Templates

Add a `brainstorming` task template for design discussions:

```yaml
name: brainstorming
description: "Run a multi-turn design discussion with superpowers brainstorming"
client: cc-glm
skills:
  - superpowers:brainstorming
args: []
summary_prompt: "在回复末尾用中文简要总结本轮讨论结论和下一步可继续追问的点。"
prompt: |
  You are working on the god-of-lego project.

  {{skills_instruction}}

  ## Task
  Discuss gameplay, system design, or implementation direction with the user.
  Follow the brainstorming skill exactly.

  {{extra_prompt}}
  {{summary_instruction}}
```

The task must run without a worktree because brainstorming and design discussion should not modify code. Add task-template support for `worktree: false`, set it on `brainstorming.yaml`, and have `foreman run task brainstorming ...` honor it without requiring Shiori to pass `--no-worktree`.

## Shiori and Harness Updates

The Shiori-facing Foreman skill or command instructions must be updated to teach the new session flow. Implementation must first locate the canonical Shiori instruction source. For GOL project-local skill changes, the canonical source is `.agents/skills/`; do not edit `.claude/skills` or `.codex/skills` directly.

Required behavior:

- For a new discussion, call `foreman run task brainstorming --client cc-glm --prompt-file - --notify`.
- Store the Foreman session ID returned by the command or received in the notification.
- For follow-up discussion, call `foreman session resume <session-id> --prompt-file - --notify`.
- Do not pass a client on resume.
- Do not use client-native session IDs.
- Do not use latest-session commands.
- If Foreman returns a usage error, send that plain text back or retry only with an explicitly corrected command.

If the active Shiori Foreman skill lives outside this repository, update that canonical source in the same change and record the path in the verification notes.

## Compatibility With Existing Foreman Commands

Existing commands can remain during migration:

- `foreman status` can show active and recent sessions instead of only old task records, or show both with a clear label.
- `foreman log tail <id>` may accept old task IDs for compatibility and session IDs for new runs.
- `foreman cancel <id>` may route to session stop when given a session ID.

New Shiori behavior should use only the session commands after the initial `run task`.

## Implementation Scope

Expected files:

| File | Change |
|---|---|
| `gol-tools/foreman/lib/session-state.mts` | New session read/write, id generation, turn allocation |
| `gol-tools/foreman/lib/session-runner.mts` | New turn lifecycle, notification, cancellation |
| `gol-tools/foreman/lib/client-args.mts` | Add launch specs for resume per family |
| `gol-tools/foreman/lib/log-parser.mts` | Add or verify native session ID extraction for each family |
| `gol-tools/foreman/bin/foreman.mts` | Add `session` commands and route `run task` through session creation |
| `gol-tools/foreman/lib/notifier.mts` | Include session and turn fields in notifications |
| `gol-tools/foreman/tasks/brainstorming.yaml` | New brainstorming task template |
| `gol-tools/foreman/README.md` | Document session commands and IM flow |
| Shiori Foreman skill source | Update Shiori/Foreman-facing session command instructions |

Keep the change additive and local to Foreman v2. Do not revive the old daemon architecture.

## Tests

Add focused tests before implementation code:

- `session-state` creates session IDs, allocates turn IDs, rejects invalid transitions, and writes atomically.
- `client-args` builds start and resume commands for Claude, Codex, and OpenCode families.
- `log-parser` extracts native session IDs from fixture logs for supported clients.
- `notifier` formats session and turn IDs in messages.
- CLI parser rejects missing prompt, empty prompt, unknown flags, missing session ID, running session resume, and closed session resume.
- README examples match actual command syntax.

Manual verification:

- Start a `brainstorming` session with `cc-glm` and `--notify`.
- Resume the returned Foreman session ID with `cc-glm`.
- Start and resume a Codex-backed session.
- Start and resume an OpenCode-backed session, after confirming stable native session ID capture.
- Confirm Telegram notification arrives only after each turn completes and contains the Foreman session ID.

## Open Questions Resolved

- This is not Foreman v3. It is an additive Foreman v2 feature.
- `run task` remains the entry point.
- Session is the real execution object.
- Turn is the unit of IM interaction.
- Shiori resumes by Foreman session ID only.
- The user should wait for Telegram notifications instead of polling status.
