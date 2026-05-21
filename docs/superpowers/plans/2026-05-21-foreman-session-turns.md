# Foreman Session Turns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add durable Foreman sessions and turn-based resume commands so Shiori can start a task once, then continue the same AI conversation by Foreman session ID only.

**Architecture:** Keep Foreman v2 additive and task-template based. `foreman run task brainstorming` creates a session and runs turn `001`; `foreman session resume fs_20260521_abcd` appends later turns. A new session state module owns canonical `logs/foreman/sessions/fs_20260521_abcd/session.json`; a new session runner owns turn lifecycle, client resume adapters, parsing native client session IDs, and notification.

**Tech Stack:** TypeScript ESM (`.mts`), Node `parseArgs`, `child_process.spawn`, atomic JSON file writes, existing Foreman YAML task templates, existing `openclaw` notifier, `tsx --test`.

---

## Scope Check

This plan implements one cohesive Foreman feature: session/turn execution. It touches CLI, state, runner, client argument building, parsing, notification, README, and the Shiori-facing harness instructions because those pieces must agree for the Telegram flow to work. It does not revive the old Foreman daemon, and it does not change GOL game code.

## File Structure

Implementation happens in `gol-tools/foreman/` on a feature branch or worktree. The parent repo gets only the final `gol-tools` submodule pointer update after the submodule work is pushed.

| File | Responsibility |
|---|---|
| `gol-tools/foreman/lib/session-state.mts` | Canonical session and turn records, ID generation, path resolution, atomic read/write, transition helpers |
| `gol-tools/foreman/lib/session-runner.mts` | Starts/resumes turns, spawns the correct client command, records native session IDs, updates session state, sends notifications |
| `gol-tools/foreman/lib/session-wrapper.mts` | Detached background process for a single turn, analogous to `detach-wrapper.mts` but session-aware |
| `gol-tools/foreman/lib/client-args.mts` | Builds first-turn and resume launch specs for Claude, Codex, and OpenCode families |
| `gol-tools/foreman/lib/opencode-session.mts` | Captures OpenCode native session IDs from JSON output or exact `opencode session list` title matches |
| `gol-tools/foreman/lib/log-parser.mts` | Extracts assistant summaries and native session IDs from JSONL logs |
| `gol-tools/foreman/lib/notifier.mts` | Adds optional `sessionId` and `turnId` to notification messages |
| `gol-tools/foreman/lib/task-loader.mts` | Adds `worktree?: boolean` to task templates |
| `gol-tools/foreman/bin/foreman.mts` | Parses strict prompt input, routes `run task` into session creation, adds `session` commands |
| `gol-tools/foreman/tasks/brainstorming.yaml` | New design discussion task with `worktree: false` and `superpowers:brainstorming` |
| `gol-tools/foreman/README.md` | Documents IM-style session flow and strict command shapes |
| Shiori Foreman instruction source | Teaches Shiori to start via `run task` and continue via `session resume` |

## Baseline Commands

Run these from `gol-tools/foreman/` unless stated otherwise:

```bash
npm test
```

Expected before changes: existing Foreman tests pass.

Use scoped commands during work:

```bash
npx tsx --test tests/session-state.test.mts
npx tsx --test tests/client-args.test.mts
npx tsx --test tests/log-parser.test.mts
npx tsx --test tests/notifier.test.mts
npx tsx --test tests/task-loader.test.mts
npx tsx --test tests/cli-session.test.mts
```

## Task 0: Isolated Submodule Workspace

**Files:**
- No code files modified in this task

- [ ] **Step 1: Check current state**

Run from parent repo:

```bash
git status --short
git -C gol-tools status --short
git -C gol-tools branch --show-current
```

Expected:

- Parent may show unrelated `gol-project` submodule changes; do not touch them.
- `gol-tools` must be clean before creating the worktree.

- [ ] **Step 2: Create a `gol-tools` worktree**

Run from parent repo:

```bash
git -C gol-tools worktree prune
git -C gol-tools worktree add -b feat/foreman-session-turns \
  /Users/dluck/Documents/GitHub/gol/.worktrees/foreman-session-turns \
  origin/main
```

Expected:

- Worktree created at `/Users/dluck/Documents/GitHub/gol/.worktrees/foreman-session-turns`.
- Branch is `feat/foreman-session-turns`.

- [ ] **Step 3: Install and run baseline tests**

Run:

```bash
cd /Users/dluck/Documents/GitHub/gol/.worktrees/foreman-session-turns/foreman
npm install
npm test
```

Expected: all existing tests pass.

## Task 1: Session State Module

**Files:**
- Create: `gol-tools/foreman/lib/session-state.mts`
- Create: `gol-tools/foreman/tests/session-state.test.mts`

- [ ] **Step 1: Write failing tests for session creation and turn allocation**

Create `tests/session-state.test.mts`:

```ts
import { describe, it, afterEach } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, rmSync, existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import {
  allocateTurn,
  closeSession,
  createSession,
  getLatestTurn,
  readSession,
  sessionDir,
  sessionLogFile,
  sessionPromptFile,
  sessionTurnId,
  updateTurn,
} from '../lib/session-state.mts'

const tempDirs: string[] = []

function makeRoot(): string {
  const dir = mkdtempSync(join(tmpdir(), 'foreman-session-state-'))
  tempDirs.push(dir)
  return dir
}

afterEach(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true })
  tempDirs.length = 0
})

describe('session-state', () => {
  it('creates a canonical session record under logs/foreman/sessions', () => {
    const root = makeRoot()
    const session = createSession(root, {
      taskName: 'brainstorming',
      client: 'cc-glm',
      clientFamily: 'claude',
      workspace: null,
      notify: true,
      title: 'Gameplay brainstorming',
    })

    assert.match(session.id, /^fs_\d{8}_[0-9a-f]{4}$/u)
    assert.equal(session.status, 'idle')
    assert.equal(session.nextTurn, 1)
    assert.equal(session.clientSessionId, null)
    assert.equal(existsSync(join(sessionDir(root, session.id), 'session.json')), true)

    const stored = readSession(root, session.id)
    assert.equal(stored.id, session.id)
    assert.equal(stored.taskName, 'brainstorming')
  })

  it('allocates fixed-width turn IDs and writes prompt text', () => {
    const root = makeRoot()
    const session = createSession(root, {
      taskName: 'brainstorming',
      client: 'cc-glm',
      clientFamily: 'claude',
      workspace: null,
      notify: false,
      title: null,
    })

    const turn = allocateTurn(root, session.id, 'Discuss night assaults')

    assert.equal(turn.id, '001')
    assert.equal(turn.status, 'running')
    assert.equal(readFileSync(sessionPromptFile(root, session.id, '001'), 'utf8'), 'Discuss night assaults')
    assert.equal(sessionLogFile(root, session.id, '001').endsWith('turns/001.log'), true)

    const updated = readSession(root, session.id)
    assert.equal(updated.status, 'running')
    assert.equal(updated.activeTurn, '001')
    assert.equal(updated.nextTurn, 2)
  })

  it('rejects allocating a new turn while running or closed', () => {
    const root = makeRoot()
    const session = createSession(root, {
      taskName: 'brainstorming',
      client: 'cc-glm',
      clientFamily: 'claude',
      workspace: null,
      notify: false,
      title: null,
    })

    allocateTurn(root, session.id, 'first')
    assert.throws(() => allocateTurn(root, session.id, 'second'), /running turn 001/u)

    updateTurn(root, session.id, '001', { status: 'done', exitCode: 0, pid: null, finishedAt: new Date().toISOString() })
    closeSession(root, session.id)
    assert.throws(() => allocateTurn(root, session.id, 'third'), /closed/u)
  })

  it('updates a finished turn and returns the latest turn', () => {
    const root = makeRoot()
    const session = createSession(root, {
      taskName: 'brainstorming',
      client: 'cc-glm',
      clientFamily: 'claude',
      workspace: null,
      notify: false,
      title: null,
    })

    allocateTurn(root, session.id, 'first')
    updateTurn(root, session.id, '001', {
      status: 'done',
      pid: null,
      exitCode: 0,
      nativeSessionId: 'native-1',
      finishedAt: '2026-05-21T00:00:01.000Z',
    })

    const stored = readSession(root, session.id)
    assert.equal(stored.status, 'idle')
    assert.equal(stored.activeTurn, null)
    assert.equal(stored.clientSessionId, 'native-1')
    assert.equal(getLatestTurn(stored)?.id, '001')
    assert.equal(sessionTurnId(12), '012')
  })
})
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
npx tsx --test tests/session-state.test.mts
```

Expected: FAIL because `lib/session-state.mts` does not exist.

- [ ] **Step 3: Implement `session-state.mts`**

Create `lib/session-state.mts` with these exported interfaces and functions:

```ts
import {
  closeSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  writeFileSync,
  fsyncSync,
} from 'node:fs'
import { randomBytes } from 'node:crypto'
import { dirname, join } from 'node:path'

export type SessionStatus = 'running' | 'idle' | 'failed' | 'cancelled' | 'closed'
export type TurnStatus = 'running' | 'done' | 'failed' | 'cancelled'

export interface TurnRecord {
  id: string
  status: TurnStatus
  pid: number | null
  promptFile: string
  logFile: string
  lastMessageFile: string
  startedAt: string
  finishedAt: string | null
  exitCode: number | null
  summarySource: string | null
  nativeSessionId: string | null
}

export interface SessionRecord {
  id: string
  taskName: string
  client: string
  clientFamily: string | undefined
  clientSessionId: string | null
  status: SessionStatus
  activeTurn: string | null
  nextTurn: number
  workspace: string | null
  notify: boolean
  createdAt: string
  updatedAt: string
  title: string | null
  turns: TurnRecord[]
}

export interface CreateSessionOptions {
  taskName: string
  client: string
  clientFamily: string | undefined
  workspace: string | null
  notify: boolean
  title: string | null
}

export function generateSessionId(date = new Date()): string {
  const stamp = date.toISOString().slice(0, 10).replace(/-/g, '')
  return `fs_${stamp}_${randomBytes(2).toString('hex')}`
}

export function sessionTurnId(value: number): string {
  return String(value).padStart(3, '0')
}

export function sessionsRoot(workDir: string): string {
  return join(workDir, 'logs', 'foreman', 'sessions')
}

export function sessionDir(workDir: string, sessionId: string): string {
  return join(sessionsRoot(workDir), sessionId)
}

export function sessionFile(workDir: string, sessionId: string): string {
  return join(sessionDir(workDir, sessionId), 'session.json')
}

export function sessionPromptFile(workDir: string, sessionId: string, turnId: string): string {
  return join(sessionDir(workDir, sessionId), 'turns', `${turnId}.prompt.txt`)
}

export function sessionLogFile(workDir: string, sessionId: string, turnId: string): string {
  return join(sessionDir(workDir, sessionId), 'turns', `${turnId}.log`)
}

export function sessionLastMessageFile(workDir: string, sessionId: string, turnId: string): string {
  return join(sessionDir(workDir, sessionId), 'turns', `${turnId}.last-message.txt`)
}

function atomicWriteJson(filePath: string, value: unknown): void {
  const dir = dirname(filePath)
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
  const tmp = `${filePath}.tmp`
  writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, 'utf8')
  const fd = openSync(tmp, 'r')
  try {
    fsyncSync(fd)
  } finally {
    closeSync(fd)
  }
  renameSync(tmp, filePath)
}

export function writeSession(workDir: string, session: SessionRecord): void {
  atomicWriteJson(sessionFile(workDir, session.id), session)
}

export function readSession(workDir: string, sessionId: string): SessionRecord {
  const filePath = sessionFile(workDir, sessionId)
  if (!existsSync(filePath)) throw new Error(`Session '${sessionId}' not found`)
  return JSON.parse(readFileSync(filePath, 'utf8')) as SessionRecord
}

export function createSession(workDir: string, opts: CreateSessionOptions): SessionRecord {
  let id = generateSessionId()
  while (existsSync(sessionFile(workDir, id))) id = generateSessionId()
  const now = new Date().toISOString()
  const session: SessionRecord = {
    id,
    taskName: opts.taskName,
    client: opts.client,
    clientFamily: opts.clientFamily,
    clientSessionId: null,
    status: 'idle',
    activeTurn: null,
    nextTurn: 1,
    workspace: opts.workspace,
    notify: opts.notify,
    createdAt: now,
    updatedAt: now,
    title: opts.title,
    turns: [],
  }
  writeSession(workDir, session)
  return session
}

export function allocateTurn(workDir: string, sessionId: string, prompt: string): TurnRecord {
  const session = readSession(workDir, sessionId)
  if (session.status === 'closed') throw new Error(`Session '${sessionId}' is closed`)
  if (session.activeTurn) throw new Error(`Session '${sessionId}' is running turn ${session.activeTurn}`)
  const turnId = sessionTurnId(session.nextTurn)
  const promptFile = sessionPromptFile(workDir, sessionId, turnId)
  const logFile = sessionLogFile(workDir, sessionId, turnId)
  const lastMessageFile = sessionLastMessageFile(workDir, sessionId, turnId)
  mkdirSync(dirname(promptFile), { recursive: true })
  writeFileSync(promptFile, prompt, 'utf8')
  const now = new Date().toISOString()
  const turn: TurnRecord = {
    id: turnId,
    status: 'running',
    pid: null,
    promptFile: `turns/${turnId}.prompt.txt`,
    logFile: `turns/${turnId}.log`,
    lastMessageFile: `turns/${turnId}.last-message.txt`,
    startedAt: now,
    finishedAt: null,
    exitCode: null,
    summarySource: null,
    nativeSessionId: null,
  }
  session.turns.push(turn)
  session.status = 'running'
  session.activeTurn = turnId
  session.nextTurn += 1
  session.updatedAt = now
  writeSession(workDir, session)
  return turn
}

export function getTurn(session: SessionRecord, turnId: string): TurnRecord {
  const turn = session.turns.find(item => item.id === turnId)
  if (!turn) throw new Error(`Turn '${turnId}' not found in session '${session.id}'`)
  return turn
}

export function getLatestTurn(session: SessionRecord): TurnRecord | null {
  return session.turns.at(-1) ?? null
}

export function updateTurn(workDir: string, sessionId: string, turnId: string, updates: Partial<TurnRecord>): SessionRecord {
  const session = readSession(workDir, sessionId)
  const turn = getTurn(session, turnId)
  Object.assign(turn, updates)
  const now = new Date().toISOString()
  session.updatedAt = now
  if (typeof updates.nativeSessionId === 'string' && updates.nativeSessionId) {
    session.clientSessionId = updates.nativeSessionId
  }
  if (turn.status !== 'running') {
    session.activeTurn = null
    session.status = turn.status === 'done' ? 'idle' : turn.status
  }
  writeSession(workDir, session)
  return session
}

export function updateTurnPid(workDir: string, sessionId: string, turnId: string, pid: number | null): void {
  updateTurn(workDir, sessionId, turnId, { pid })
}

export function closeSession(workDir: string, sessionId: string): SessionRecord {
  const session = readSession(workDir, sessionId)
  if (session.activeTurn) throw new Error(`Session '${sessionId}' is running turn ${session.activeTurn}`)
  session.status = 'closed'
  session.updatedAt = new Date().toISOString()
  writeSession(workDir, session)
  return session
}
```

- [ ] **Step 4: Run session-state tests**

Run:

```bash
npx tsx --test tests/session-state.test.mts
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add lib/session-state.mts tests/session-state.test.mts
git commit -m "feat(foreman): add session state model"
```

## Task 2: Client Resume Launch Specs and Native Session Parsers

**Files:**
- Modify: `gol-tools/foreman/lib/client-args.mts`
- Modify: `gol-tools/foreman/lib/log-parser.mts`
- Create: `gol-tools/foreman/lib/opencode-session.mts`
- Modify: `gol-tools/foreman/tests/client-args.test.mts`
- Modify: `gol-tools/foreman/tests/log-parser.test.mts`
- Create: `gol-tools/foreman/tests/opencode-session.test.mts`
- Add fixtures under `gol-tools/foreman/tests/fixtures/`

- [ ] **Step 1: Add failing client-args tests**

Append to `tests/client-args.test.mts`:

```ts
  it('builds claude resume args with explicit session id', () => {
    const spec = buildResumeLaunchSpec(
      { binary: 'claude', family: 'claude' },
      'native-claude-session',
      'continue discussion',
    )

    assert.deepStrictEqual(spec.args, [
      '--resume',
      'native-claude-session',
      '-p',
      'continue discussion',
      '--output-format',
      'stream-json',
      '--verbose',
    ])
  })

  it('builds codex exec resume args with last-message file', () => {
    const spec = buildResumeLaunchSpec(
      { binary: 'codex', family: 'codex', model: 'gpt-5.4-test' },
      '019df8ce-51a4-77a3-8715-f1a037b26050',
      'continue discussion',
      { lastMessageFile: '/tmp/turn.last-message.txt' },
    )

    assert.deepStrictEqual(spec.args, [
      'exec',
      'resume',
      '019df8ce-51a4-77a3-8715-f1a037b26050',
      '--ignore-user-config',
      '-c',
      'approval_policy="never"',
      '--model',
      'gpt-5.4-test',
      '--json',
      '--sandbox',
      'workspace-write',
      '--output-last-message',
      '/tmp/turn.last-message.txt',
      'continue discussion',
    ])
  })

  it('builds opencode resume args with explicit session id', () => {
    const spec = buildResumeLaunchSpec(
      { binary: 'opencode', family: 'opencode' },
      'ses_2029cea3fffe1J1Px5uRPuF79l',
      'continue discussion',
    )

    assert.deepStrictEqual(spec.args, [
      'run',
      '--session',
      'ses_2029cea3fffe1J1Px5uRPuF79l',
      'continue discussion',
      '--format',
      'json',
      '--dangerously-skip-permissions',
    ])
  })
```

Also update the import:

```ts
import { buildClientArgs, buildLaunchSpec, buildResumeLaunchSpec } from '../lib/client-args.mts'
```

- [ ] **Step 2: Add failing parser tests and fixtures**

Create `tests/fixtures/claude-session-init.log`:

```json
{"type":"system","subtype":"init","session_id":"11111111-2222-3333-4444-555555555555"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Ready."}]}}
```

Create `tests/fixtures/opencode-session.log`:

```json
{"type":"session","sessionID":"ses_2029cea3fffe1J1Px5uRPuF79l","title":"Discussion"}
{"type":"text","part":{"text":"Ready."}}
```

Append tests to `tests/log-parser.test.mts`:

```ts
import { parseClaudeSessionId, parseCodexThreadId, parseLastAssistantMessage, parseOpencodeSessionId } from '../lib/log-parser.mts'
```

```ts
  it('extracts claude session id from stream-json init event', () => {
    assert.equal(
      parseClaudeSessionId(fixturePath('claude-session-init.log')),
      '11111111-2222-3333-4444-555555555555',
    )
  })

  it('extracts opencode session id from json output', () => {
    assert.equal(
      parseOpencodeSessionId(fixturePath('opencode-session.log')),
      'ses_2029cea3fffe1J1Px5uRPuF79l',
    )
  })
```

- [ ] **Step 3: Add OpenCode session-list parser tests**

Create `tests/opencode-session.test.mts`:

```ts
import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { findOpencodeSessionByTitle, parseOpencodeSessionList } from '../lib/opencode-session.mts'

const sampleList = `Session ID                      Title                                                                                                 Updated
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
ses_aaa111                      Other discussion                                                                                      3:44 PM · 5/10/2026
ses_bbb222                      foreman:fs_20260521_abcd:001                                                                          3:45 PM · 5/10/2026
`

describe('opencode session list parsing', () => {
  it('parses session list rows', () => {
    const sessions = parseOpencodeSessionList(sampleList)
    assert.deepStrictEqual(sessions[1], {
      id: 'ses_bbb222',
      title: 'foreman:fs_20260521_abcd:001',
      updated: '3:45 PM · 5/10/2026',
    })
  })

  it('finds an exact title match', () => {
    assert.equal(findOpencodeSessionByTitle(sampleList, 'foreman:fs_20260521_abcd:001'), 'ses_bbb222')
  })

  it('rejects missing exact title matches', () => {
    assert.throws(
      () => findOpencodeSessionByTitle(sampleList, 'foreman:missing:001'),
      /Could not find OpenCode session title/u,
    )
  })
})
```

- [ ] **Step 4: Run failing tests**

Run:

```bash
npx tsx --test tests/client-args.test.mts tests/log-parser.test.mts tests/opencode-session.test.mts
```

Expected: FAIL because resume builder and parser functions do not exist.

- [ ] **Step 5: Implement `buildResumeLaunchSpec`**

Modify `lib/client-args.mts`:

```ts
export interface LaunchOptions {
  lastMessageFile?: string
  sessionTitle?: string
}
```

Update the OpenCode branch in `buildLaunchSpec`:

```ts
if (family === 'opencode') {
  const args = ['run', prompt, '--format', 'json', '--dangerously-skip-permissions']
  if (options.sessionTitle) args.push('--title', options.sessionTitle)
  return { binary: client.binary, args }
}
```

Then add the resume builder:

```ts
export function buildResumeLaunchSpec(
  client: ClientLaunchConfig,
  nativeSessionId: string,
  prompt: string,
  options: LaunchOptions = {},
): LaunchSpec {
  if (!nativeSessionId.trim()) throw new Error('Native session id is required')
  const family = client.family ?? inferFamily(client.binary)

  if (family === 'claude') {
    return {
      binary: client.binary,
      args: ['--resume', nativeSessionId, '-p', prompt, '--output-format', 'stream-json', '--verbose'],
    }
  }

  if (family === 'codex') {
    const lastMessageFile = options.lastMessageFile
    const args = [
      'exec',
      'resume',
      nativeSessionId,
      '--ignore-user-config',
      '-c',
      'approval_policy="never"',
      '--model',
      client.model ?? CODEX_DEFAULT_MODEL,
      '--json',
      '--sandbox',
      'workspace-write',
    ]
    if (lastMessageFile) args.push('--output-last-message', lastMessageFile)
    args.push(prompt)
    return { binary: client.binary, args, lastMessageFile }
  }

  if (family === 'opencode') {
    return {
      binary: client.binary,
      args: ['run', '--session', nativeSessionId, prompt, '--format', 'json', '--dangerously-skip-permissions'],
    }
  }

  throw new Error(`Client family '${family ?? 'unknown'}' does not support session resume`)
}
```

- [ ] **Step 6: Implement native session parsers**

Modify `lib/log-parser.mts`:

```ts
function parseNativeSessionId(logFilePath: string, keys: string[]): string | null {
  if (!existsSync(logFilePath)) return null
  let content = ''
  try {
    content = readFileSync(logFilePath, 'utf8')
  } catch {
    return null
  }
  const events = parseJsonLines(content)
  for (const event of events) {
    for (const key of keys) {
      const value = getStringProperty(event, key)
      if (value) return value
    }
  }
  return null
}

export function parseClaudeSessionId(logFilePath: string): string | null {
  return parseNativeSessionId(logFilePath, ['session_id', 'sessionId'])
}

export function parseOpencodeSessionId(logFilePath: string): string | null {
  return parseNativeSessionId(logFilePath, ['sessionID', 'session_id', 'sessionId'])
}
```

- [ ] **Step 7: Implement OpenCode session-list exact title fallback**

Create `lib/opencode-session.mts`:

```ts
import { execFileSync } from 'node:child_process'

export interface OpencodeListedSession {
  id: string
  title: string
  updated: string
}

export function opencodeTurnTitle(sessionId: string, turnId: string): string {
  return `foreman:${sessionId}:${turnId}`
}

export function parseOpencodeSessionList(output: string): OpencodeListedSession[] {
  const sessions: OpencodeListedSession[] = []
  for (const line of output.split(/\r?\n/u)) {
    const match = line.match(/^(ses_\S+)\s{2,}(.+?)\s{2,}(.+)$/u)
    if (!match) continue
    sessions.push({
      id: match[1],
      title: match[2].trim(),
      updated: match[3].trim(),
    })
  }
  return sessions
}

export function findOpencodeSessionByTitle(output: string, title: string): string {
  const matches = parseOpencodeSessionList(output).filter(session => session.title === title)
  if (matches.length === 1) return matches[0].id
  if (matches.length > 1) throw new Error(`Multiple OpenCode sessions matched title '${title}'`)
  throw new Error(`Could not find OpenCode session title '${title}'`)
}

export function captureOpencodeSessionByTitle(title: string): string {
  const output = execFileSync('opencode', ['session', 'list'], { encoding: 'utf8' })
  return findOpencodeSessionByTitle(output, title)
}
```

- [ ] **Step 8: Verify OpenCode capture**

Run a tiny local OpenCode session from the worktree:

```bash
opencode run --title foreman:fs_20260521_smok:001 "Return exactly: session smoke" --format json --dangerously-skip-permissions 2>&1 | tee /tmp/foreman-opencode-session-smoke.log | head -c 4000
```

Then inspect:

```bash
rg -n "session|sessionID|ses_" /tmp/foreman-opencode-session-smoke.log
opencode session list | rg "foreman:fs_20260521_smok:001"
```

Expected: either the JSON output includes a session ID parsed by `parseOpencodeSessionId`, or `opencode session list` includes exactly one row titled `foreman:fs_20260521_smok:001`. Session runner must use JSON parsing first, then `captureOpencodeSessionByTitle(opencodeTurnTitle(sessionId, turnId))`.

- [ ] **Step 9: Run tests**

Run:

```bash
npx tsx --test tests/client-args.test.mts tests/log-parser.test.mts tests/opencode-session.test.mts
```

Expected: PASS.

- [ ] **Step 10: Commit**

Run:

```bash
git add lib/client-args.mts lib/log-parser.mts lib/opencode-session.mts tests/client-args.test.mts tests/log-parser.test.mts tests/opencode-session.test.mts tests/fixtures/claude-session-init.log tests/fixtures/opencode-session.log
git commit -m "feat(foreman): add session resume launch specs"
```

## Task 3: Task Template Prompt Input and `worktree: false`

**Files:**
- Modify: `gol-tools/foreman/lib/task-loader.mts`
- Modify: `gol-tools/foreman/bin/foreman.mts`
- Create: `gol-tools/foreman/tasks/brainstorming.yaml`
- Create: `gol-tools/foreman/tests/task-loader.test.mts`

- [ ] **Step 1: Add task-loader tests**

Create `tests/task-loader.test.mts`:

```ts
import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { loadTasks } from '../lib/task-loader.mts'

describe('task-loader', () => {
  it('loads worktree false from task yaml', () => {
    const dir = mkdtempSync(join(tmpdir(), 'foreman-task-loader-'))
    try {
      writeFileSync(join(dir, 'brainstorming.yaml'), `
name: brainstorming
description: "Brainstorm"
client: cc-glm
worktree: false
args: []
prompt: |
  {{extra_prompt}}
`, 'utf8')

      const task = loadTasks(dir).get('brainstorming')
      assert.equal(task?.worktree, false)
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})
```

- [ ] **Step 2: Run failing test**

Run:

```bash
npx tsx --test tests/task-loader.test.mts
```

Expected: FAIL because `TaskTemplate` does not expose `worktree`.

- [ ] **Step 3: Extend task template type**

Modify `lib/task-loader.mts`:

```ts
export interface TaskTemplate {
  name: string
  description: string
  client: string
  skills?: string[]
  args?: TaskArg[]
  prompt?: string
  summary_prompt?: string
  status?: 'placeholder'
  worktree?: boolean
}
```

- [ ] **Step 4: Add `brainstorming.yaml`**

Create `tasks/brainstorming.yaml`:

```yaml
name: brainstorming
description: "Run a multi-turn design discussion with superpowers brainstorming"
client: cc-glm
worktree: false
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

- [ ] **Step 5: Add strict prompt reader helpers in CLI**

Modify `bin/foreman.mts` imports:

```ts
import { readFileSync, existsSync } from 'node:fs'
```

Replace with:

```ts
import { readFileSync, existsSync } from 'node:fs'
```

No import change is needed if `readFileSync` already exists. Add helper functions near `sleep`:

```ts
function readStdin(): string {
  return readFileSync(0, 'utf8')
}

function readPromptInput(flags: { prompt?: unknown; ['prompt-file']?: unknown }, usage: string): string {
  const prompt = typeof flags.prompt === 'string' ? flags.prompt : undefined
  const promptFile = typeof flags['prompt-file'] === 'string' ? flags['prompt-file'] : undefined
  if (prompt !== undefined && promptFile !== undefined) {
    throw new Error(`${usage}\nUse either --prompt or --prompt-file, not both.`)
  }
  const value = promptFile === '-'
    ? readStdin()
    : promptFile !== undefined
      ? readFileSync(promptFile, 'utf8')
      : prompt
  if (value !== undefined && value.trim().length === 0) {
    throw new Error(`${usage}\nPrompt content is empty.`)
  }
  return value ?? ''
}
```

In `handleRunTask`, add the option:

```ts
'prompt-file': { type: 'string' },
```

Change `strict: false` to:

```ts
strict: true,
allowPositionals: false,
```

Replace:

```ts
const extraPrompt = (flags.prompt as string) || ''
```

with:

```ts
const extraPrompt = readPromptInput(flags, `Usage: foreman run task ${taskName} [--args...]`)
```

Replace:

```ts
const noWorktree = !!flags['no-worktree']
```

with:

```ts
const noWorktree = !!flags['no-worktree'] || template.worktree === false
```

- [ ] **Step 6: Run scoped tests**

Run:

```bash
npx tsx --test tests/task-loader.test.mts
npm test
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add lib/task-loader.mts bin/foreman.mts tasks/brainstorming.yaml tests/task-loader.test.mts
git commit -m "feat(foreman): add brainstorming task prompt input"
```

## Task 4: Session Runner and Detached Session Wrapper

**Files:**
- Create: `gol-tools/foreman/lib/session-runner.mts`
- Create: `gol-tools/foreman/lib/session-wrapper.mts`
- Create: `gol-tools/foreman/tests/session-runner.test.mts`

- [ ] **Step 1: Write focused session-runner tests for pure helpers**

Create `tests/session-runner.test.mts`:

```ts
import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { resolveNativeSessionId, resolveTurnStatus } from '../lib/session-runner.mts'

describe('session-runner helpers', () => {
  it('maps exit code to turn status', () => {
    assert.equal(resolveTurnStatus(0), 'done')
    assert.equal(resolveTurnStatus(1), 'failed')
  })

  it('resolves native session id by family', () => {
    assert.equal(resolveNativeSessionId('claude', 'claude-native', null, null), 'claude-native')
    assert.equal(resolveNativeSessionId('codex', null, 'codex-thread', null), 'codex-thread')
    assert.equal(resolveNativeSessionId('opencode', null, null, 'opencode-session'), 'opencode-session')
  })

  it('fails when native session id cannot be captured', () => {
    assert.throws(
      () => resolveNativeSessionId('opencode', null, null, null),
      /Could not capture native opencode session id/u,
    )
  })
})
```

- [ ] **Step 2: Run failing test**

Run:

```bash
npx tsx --test tests/session-runner.test.mts
```

Expected: FAIL because `session-runner.mts` does not exist.

- [ ] **Step 3: Implement `session-runner.mts` exported helper surface**

Create `lib/session-runner.mts` with helper exports first:

```ts
import { spawn, execFileSync } from 'node:child_process'
import { closeSync, createWriteStream, existsSync, mkdirSync, openSync, readFileSync, statSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { buildLaunchSpec, buildResumeLaunchSpec, type ClientFamily } from './client-args.mts'
import { createNotifier, type NotifyConfig, type TaskResult } from './notifier.mts'
import { parseClaudeSessionId, parseCodexThreadId, parseLastAssistantMessage, parseOpencodeSessionId } from './log-parser.mts'
import { captureOpencodeSessionByTitle, opencodeTurnTitle } from './opencode-session.mts'
import { DEFAULT_MAX_RETRIES, isRetryableApiError, retryDelayMs } from './retry-policy.mts'
import {
  allocateTurn,
  readSession,
  sessionLastMessageFile,
  sessionLogFile,
  updateTurn,
  updateTurnPid,
  type TurnStatus,
} from './session-state.mts'

export interface SessionRunOptions {
  sessionId: string
  client: string
  binary: string
  family?: ClientFamily
  model?: string
  prompt: string
  notify: boolean
  notifyConfig?: NotifyConfig
  workDir: string
  workspace: string | null
  detach: boolean
  maxRetries?: number
  resume: boolean
}

export function resolveTurnStatus(exitCode: number): TurnStatus {
  return exitCode === 0 ? 'done' : 'failed'
}

export function resolveNativeSessionId(
  family: ClientFamily | undefined,
  claudeSessionId: string | null,
  codexThreadId: string | null,
  opencodeSessionId: string | null,
): string {
  if (family === 'claude' && claudeSessionId) return claudeSessionId
  if (family === 'codex' && codexThreadId) return codexThreadId
  if (family === 'opencode' && opencodeSessionId) return opencodeSessionId
  throw new Error(`Could not capture native ${family ?? 'unknown'} session id`)
}
```

- [ ] **Step 4: Add synchronous utility functions**

Append:

```ts
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

function getFileSize(filePath: string): number {
  try {
    return statSync(filePath).size
  } catch {
    return 0
  }
}

function readFileFrom(filePath: string, offset: number): string {
  try {
    return readFileSync(filePath, 'utf8').slice(offset)
  } catch {
    return ''
  }
}

function computeDuration(startedAt: string): string {
  const ms = Date.now() - new Date(startedAt).getTime()
  const secs = Math.floor(ms / 1000)
  if (secs < 60) return `${secs}s`
  const mins = Math.floor(secs / 60)
  const remSecs = secs % 60
  if (mins < 60) return `${mins}m ${remSecs}s`
  const hrs = Math.floor(mins / 60)
  return `${hrs}h ${mins % 60}m`
}

function parseNativeId(family: ClientFamily | undefined, logFile: string): string {
  const directOpencodeId = parseOpencodeSessionId(logFile)
  if (family === 'opencode' && directOpencodeId) return directOpencodeId
  return resolveNativeSessionId(
    family,
    parseClaudeSessionId(logFile),
    parseCodexThreadId(logFile),
    directOpencodeId,
  )
}
```

- [ ] **Step 5: Add foreground turn execution**

Append:

```ts
export async function runSessionForeground(opts: SessionRunOptions): Promise<number> {
  const session = readSession(opts.workDir, opts.sessionId)
  const nativeSessionId = session.clientSessionId
  if (opts.resume && !nativeSessionId) {
    throw new Error(`Session '${opts.sessionId}' has no native client session id`)
  }

  const turn = allocateTurn(opts.workDir, opts.sessionId, opts.prompt)
  const logFile = sessionLogFile(opts.workDir, opts.sessionId, turn.id)
  const lastMessageFile = sessionLastMessageFile(opts.workDir, opts.sessionId, turn.id)
  const sessionTitle = opts.family === 'opencode' ? opencodeTurnTitle(opts.sessionId, turn.id) : undefined
  const launch = opts.resume
    ? buildResumeLaunchSpec(opts, nativeSessionId!, opts.prompt, { lastMessageFile })
    : buildLaunchSpec(opts, opts.prompt, { lastMessageFile, sessionTitle })

  mkdirSync(dirname(logFile), { recursive: true })
  closeSync(openSync(logFile, 'a'))
  const logStream = createWriteStream(logFile, { flags: 'a' })
  const maxRetries = opts.maxRetries ?? DEFAULT_MAX_RETRIES
  const env = { ...process.env }
  let exitCode = 1

  for (let attempt = 1; attempt <= maxRetries + 1; attempt += 1) {
    const logOffset = getFileSize(logFile)
    const child = spawn(launch.binary, launch.args, {
      cwd: opts.workDir,
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    updateTurnPid(opts.workDir, opts.sessionId, turn.id, child.pid ?? null)

    child.stdout?.on('data', chunk => {
      process.stdout.write(chunk)
      logStream.write(chunk)
    })
    child.stderr?.on('data', chunk => {
      process.stderr.write(chunk)
      logStream.write(chunk)
    })

    const result = await new Promise<{ exitCode: number; retryable: boolean }>(resolve => {
      child.on('error', error => {
        logStream.write(`[foreman] Failed to start client '${launch.binary}': ${error.message}\n`)
        resolve({ exitCode: 1, retryable: false })
      })
      child.on('exit', code => {
        const codeValue = code ?? 1
        const attemptOutput = readFileFrom(logFile, logOffset)
        resolve({ exitCode: codeValue, retryable: codeValue !== 0 && isRetryableApiError(attemptOutput) })
      })
    })

    exitCode = result.exitCode
    if (exitCode === 0 || !result.retryable || attempt > maxRetries) break
    const delay = retryDelayMs(attempt)
    logStream.write(`[foreman] Retryable API error detected; retrying in ${Math.round(delay / 1000)}s (${attempt}/${maxRetries})\n`)
    await sleep(delay)
  }

  logStream.end()
  await finishSessionTurn(opts, turn.id, exitCode)
  return exitCode
}
```

- [ ] **Step 6: Add detached turn start and finish helper**

Append:

```ts
export function runSessionDetached(opts: SessionRunOptions): { wrapperPid: number | null; wrapperLogFile: string; turnId: string } {
  const session = readSession(opts.workDir, opts.sessionId)
  if (opts.resume && !session.clientSessionId) {
    throw new Error(`Session '${opts.sessionId}' has no native client session id`)
  }
  const turn = allocateTurn(opts.workDir, opts.sessionId, opts.prompt)
  const foremanDir = dirname(dirname(fileURLToPath(import.meta.url)))
  const wrapperPath = join(foremanDir, 'lib', 'session-wrapper.mts')
  const logFile = sessionLogFile(opts.workDir, opts.sessionId, turn.id)
  const wrapperLogFile = `${logFile}.wrapper.log`
  mkdirSync(dirname(logFile), { recursive: true })
  const tsxBin = join(foremanDir, 'node_modules', '.bin', process.platform === 'win32' ? 'tsx.cmd' : 'tsx')
  const fd = openSync(wrapperLogFile, 'a')
  const args = [
    wrapperPath,
    '--session-id', opts.sessionId,
    '--turn-id', turn.id,
    '--binary', opts.binary,
    '--client', opts.client,
    '--work-dir', opts.workDir,
    '--resume', String(opts.resume),
    '--max-retries', String(opts.maxRetries ?? DEFAULT_MAX_RETRIES),
  ]
  if (opts.family) args.push('--family', opts.family)
  if (opts.model) args.push('--model', opts.model)
  if (opts.notify) args.push('--notify')
  if (opts.notifyConfig) args.push('--notify-config', JSON.stringify(opts.notifyConfig))
  args.push('--', opts.prompt)

  const child = spawn(tsxBin, args, {
    cwd: opts.workDir,
    stdio: ['ignore', fd, fd],
    detached: true,
  })
  closeSync(fd)
  child.unref()
  return { wrapperPid: child.pid ?? null, wrapperLogFile, turnId: turn.id }
}

export async function finishSessionTurn(opts: SessionRunOptions, turnId: string, exitCode: number): Promise<void> {
  const logFile = sessionLogFile(opts.workDir, opts.sessionId, turnId)
  const lastMessageFile = sessionLastMessageFile(opts.workDir, opts.sessionId, turnId)
  const nativeSessionId = opts.family === 'opencode'
    ? (parseOpencodeSessionId(logFile) ?? captureOpencodeSessionByTitle(opencodeTurnTitle(opts.sessionId, turnId)))
    : parseNativeId(opts.family, logFile)
  const parsed = parseLastAssistantMessage(logFile, opts.client, lastMessageFile)
  const status = resolveTurnStatus(exitCode)
  const session = updateTurn(opts.workDir, opts.sessionId, turnId, {
    status,
    pid: null,
    exitCode,
    finishedAt: new Date().toISOString(),
    summarySource: parsed.source,
    nativeSessionId,
  })

  if (opts.notify && opts.notifyConfig) {
    const notifier = createNotifier(opts.notifyConfig)
    const result: TaskResult = {
      taskId: opts.sessionId,
      sessionId: opts.sessionId,
      turnId,
      taskName: session.taskName,
      status,
      issueNumber: null,
      prUrl: null,
      duration: computeDuration(getLatestStartedAt(session, turnId)),
      summary: parsed.summary || `退出码: ${exitCode}`,
    }
    await notifier.notify(result)
  }
}

function getLatestStartedAt(session: { turns: Array<{ id: string; startedAt: string }> }, turnId: string): string {
  return session.turns.find(turn => turn.id === turnId)?.startedAt ?? new Date().toISOString()
}
```

- [ ] **Step 7: Implement `session-wrapper.mts`**

Create `lib/session-wrapper.mts` by mirroring `detach-wrapper.mts` but using session state:

```ts
#!/usr/bin/env tsx
import { parseArgs } from 'node:util'
import { spawn } from 'node:child_process'
import { closeSync, createWriteStream, existsSync, mkdirSync, openSync, readFileSync, statSync } from 'node:fs'
import { dirname } from 'node:path'
import { buildLaunchSpec, buildResumeLaunchSpec, type ClientFamily } from './client-args.mts'
import { DEFAULT_MAX_RETRIES, isRetryableApiError, retryDelayMs } from './retry-policy.mts'
import { opencodeTurnTitle } from './opencode-session.mts'
import { readSession, sessionLastMessageFile, sessionLogFile, updateTurnPid } from './session-state.mts'
import { finishSessionTurn } from './session-runner.mts'
import type { NotifyConfig } from './notifier.mts'

const { values, positionals } = parseArgs({
  options: {
    'session-id': { type: 'string' },
    'turn-id': { type: 'string' },
    binary: { type: 'string' },
    family: { type: 'string' },
    model: { type: 'string' },
    client: { type: 'string' },
    'work-dir': { type: 'string' },
    resume: { type: 'string' },
    notify: { type: 'boolean', default: false },
    'notify-config': { type: 'string' },
    'max-retries': { type: 'string' },
  },
  allowPositionals: true,
  strict: true,
})

const sessionId = values['session-id']!
const turnId = values['turn-id']!
const binary = values.binary!
const family = values.family as ClientFamily | undefined
const model = values.model
const client = values.client!
const workDir = values['work-dir']!
const isResume = values.resume === 'true'
const shouldNotify = values.notify ?? false
const notifyConfig: NotifyConfig | undefined = values['notify-config'] ? JSON.parse(values['notify-config']) : undefined
const maxRetries = values['max-retries'] ? parseInt(values['max-retries'], 10) : DEFAULT_MAX_RETRIES
const prompt = positionals[0]

if (!prompt) {
  console.error('No prompt provided')
  process.exit(1)
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

function getFileSize(filePath: string): number {
  try { return statSync(filePath).size } catch { return 0 }
}

function readFileFrom(filePath: string, offset: number): string {
  try { return readFileSync(filePath, 'utf8').slice(offset) } catch { return '' }
}

const session = readSession(workDir, sessionId)
const nativeSessionId = session.clientSessionId
const logFile = sessionLogFile(workDir, sessionId, turnId)
const lastMessageFile = sessionLastMessageFile(workDir, sessionId, turnId)
const sessionTitle = family === 'opencode' ? opencodeTurnTitle(sessionId, turnId) : undefined
const launch = isResume
  ? buildResumeLaunchSpec({ binary, family, model }, nativeSessionId!, prompt, { lastMessageFile })
  : buildLaunchSpec({ binary, family, model }, prompt, { lastMessageFile, sessionTitle })

mkdirSync(dirname(logFile), { recursive: true })
closeSync(openSync(logFile, 'a'))
const logStream = createWriteStream(logFile, { flags: 'a' })
const env = { ...process.env }

;(async () => {
  let exitCode = 1
  for (let attempt = 1; attempt <= maxRetries + 1; attempt += 1) {
    const logOffset = getFileSize(logFile)
    const child = spawn(launch.binary, launch.args, {
      cwd: workDir,
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    updateTurnPid(workDir, sessionId, turnId, child.pid ?? null)

    child.stdout?.on('data', chunk => logStream.write(chunk))
    child.stderr?.on('data', chunk => logStream.write(chunk))

    const result = await new Promise<{ exitCode: number; retryable: boolean }>(resolve => {
      child.on('error', error => {
        logStream.write(`[foreman] Failed to start client '${launch.binary}': ${error.message}\n`)
        resolve({ exitCode: 1, retryable: false })
      })
      child.on('exit', code => {
        const codeValue = code ?? 1
        resolve({
          exitCode: codeValue,
          retryable: codeValue !== 0 && isRetryableApiError(readFileFrom(logFile, logOffset)),
        })
      })
    })

    exitCode = result.exitCode
    if (exitCode === 0 || !result.retryable || attempt > maxRetries) break
    const delay = retryDelayMs(attempt)
    logStream.write(`[foreman] Retryable API error detected; retrying in ${Math.round(delay / 1000)}s (${attempt}/${maxRetries})\n`)
    await sleep(delay)
  }

  logStream.end()
  await finishSessionTurn({
    sessionId,
    client,
    binary,
    family,
    model,
    prompt,
    notify: shouldNotify,
    notifyConfig,
    workDir,
    workspace: session.workspace,
    detach: true,
    maxRetries,
    resume: isResume,
  }, turnId, exitCode)
  process.exit(exitCode)
})().catch(async error => {
  logStream.write(`[foreman] Session wrapper failed: ${(error as Error).message}\n`)
  logStream.end()
  await finishSessionTurn({
    sessionId,
    client,
    binary,
    family,
    model,
    prompt,
    notify: shouldNotify,
    notifyConfig,
    workDir,
    workspace: session.workspace,
    detach: true,
    maxRetries,
    resume: isResume,
  }, turnId, 1)
  process.exit(1)
})
```

- [ ] **Step 8: Run tests**

Run:

```bash
npx tsx --test tests/session-runner.test.mts
npm test
```

Expected: PASS.

- [ ] **Step 9: Commit**

Run:

```bash
git add lib/session-runner.mts lib/session-wrapper.mts tests/session-runner.test.mts
git commit -m "feat(foreman): run session turns"
```

## Task 5: CLI Session Commands and `run task` Entry

**Files:**
- Modify: `gol-tools/foreman/bin/foreman.mts`
- Create: `gol-tools/foreman/tests/cli-session.test.mts`

- [ ] **Step 1: Add CLI parser tests for prompt strictness using helper exports**

Create `tests/cli-session.test.mts`:

```ts
import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { parsePromptFlags, resolveSessionLogTurn } from '../lib/cli-helpers.mts'

describe('foreman session CLI helpers', () => {
  it('rejects prompt and prompt-file together', () => {
    assert.throws(
      () => parsePromptFlags({ prompt: 'a', 'prompt-file': 'b' }),
      /Use either --prompt or --prompt-file/u,
    )
  })

  it('rejects empty prompt content', () => {
    assert.throws(
      () => parsePromptFlags({ prompt: '   ' }),
      /Prompt content is empty/u,
    )
  })

  it('resolves explicit log turn over active/latest', () => {
    assert.equal(resolveSessionLogTurn({ activeTurn: '002', turns: [{ id: '001' }, { id: '002' }] }, '001'), '001')
  })
})
```

- [ ] **Step 2: Add CLI helper implementation**

Create `lib/cli-helpers.mts`:

```ts
import { readFileSync } from 'node:fs'

export function parsePromptFlags(flags: { prompt?: unknown; ['prompt-file']?: unknown }): string {
  const prompt = typeof flags.prompt === 'string' ? flags.prompt : undefined
  const promptFile = typeof flags['prompt-file'] === 'string' ? flags['prompt-file'] : undefined
  if (prompt !== undefined && promptFile !== undefined) throw new Error('Use either --prompt or --prompt-file, not both.')
  const value = promptFile === '-' ? readFileSync(0, 'utf8') : promptFile ? readFileSync(promptFile, 'utf8') : prompt
  if (value !== undefined && value.trim().length === 0) throw new Error('Prompt content is empty.')
  return value ?? ''
}

export function resolveSessionLogTurn(
  session: { activeTurn: string | null; turns: Array<{ id: string }> },
  explicitTurn?: string,
): string {
  if (explicitTurn) {
    if (!session.turns.some(turn => turn.id === explicitTurn)) throw new Error(`Turn '${explicitTurn}' not found`)
    return explicitTurn
  }
  if (session.activeTurn) return session.activeTurn
  const latest = session.turns.at(-1)
  if (!latest) throw new Error('Session has no turns')
  return latest.id
}
```

Update `bin/foreman.mts` to use these helpers instead of duplicating prompt parsing.

- [ ] **Step 3: Route `handleRunTask` through session creation**

Modify `bin/foreman.mts`:

- Import `createSession` from `../lib/session-state.mts`.
- Import `runSessionDetached` and `runSessionForeground` from `../lib/session-runner.mts`.
- Do not call `createTask`, `runDetached`, or `runForeground` in the new `handleRunTask` path; `run task` creates a session and runs a session turn.
- After rendering the prompt, call:

```ts
const session = createSession(workDir, {
  taskName,
  client: clientName,
  clientFamily: inferClientFamily(clientName, clientConfig.binary, clientConfig.family),
  workspace: noWorktree ? null : workspace,
  notify: shouldNotify,
  title: extraPrompt.slice(0, 80) || taskName,
})
```

For detached mode:

```ts
const detached = runSessionDetached({
  sessionId: session.id,
  client: clientName,
  binary: clientConfig.binary,
  family: inferClientFamily(clientName, clientConfig.binary, clientConfig.family),
  model: clientConfig.model,
  prompt,
  notify: shouldNotify,
  notifyConfig: shouldNotify ? config.notify : undefined,
  workDir,
  workspace: noWorktree ? null : workspace,
  detach: true,
  maxRetries,
  resume: false,
})

console.log(`Session ${session.id} started: ${taskName} (client: ${clientName})`)
console.log(`Turn: ${detached.turnId}`)
console.log(`Log: ${sessionLogFile(workDir, session.id, detached.turnId)}`)
console.log(`Detached: yes${detached.wrapperPid ? ` (wrapper PID ${detached.wrapperPid})` : ''}`)
console.log(`Tail: foreman session log ${session.id}`)
return 0
```

For foreground mode, call `runSessionForeground` with `resume: false`.

- [ ] **Step 4: Add `session` subcommands**

Add handlers:

```ts
async function handleSessionResume(args: string[]): Promise<number> {
  const sessionId = args[0]
  if (!sessionId) {
    console.error('Usage: foreman session resume <session-id> (--prompt "..." | --prompt-file <path>) [--notify]')
    return 1
  }
  const config = loadConfig()
  const workDir = resolveWorkDir()
  const session = readSession(workDir, sessionId)
  if (session.status === 'closed') throw new Error(`Session '${sessionId}' is closed`)
  if (session.activeTurn) throw new Error(`Session '${sessionId}' is running turn ${session.activeTurn}`)
  if (!session.clientSessionId) throw new Error(`Session '${sessionId}' has no native client session id`)
  const { values: flags } = parseArgs({
    args: args.slice(1),
    options: {
      prompt: { type: 'string', short: 'p' },
      'prompt-file': { type: 'string' },
      notify: { type: 'boolean' },
      foreground: { type: 'boolean' },
      retries: { type: 'string' },
    },
    strict: true,
  })
  const prompt = parsePromptFlags(flags)
  if (!prompt) throw new Error('Prompt content is required.')
  const clientConfig = config.clients[session.client]
  if (!clientConfig) throw new Error(`Unknown client '${session.client}' in session '${sessionId}'`)
  const shouldNotify = !!flags.notify || session.notify
  const runOpts = {
    sessionId,
    client: session.client,
    binary: clientConfig.binary,
    family: inferClientFamily(session.client, clientConfig.binary, clientConfig.family),
    model: clientConfig.model,
    prompt,
    notify: shouldNotify,
    notifyConfig: shouldNotify ? config.notify : undefined,
    workDir,
    workspace: session.workspace,
    detach: !flags.foreground,
    maxRetries: flags.retries ? parseInt(flags.retries as string, 10) : undefined,
    resume: true,
  }
  if (flags.foreground) return runSessionForeground(runOpts)
  const detached = runSessionDetached(runOpts)
  console.log(`Session ${sessionId} resumed (client: ${session.client})`)
  console.log(`Turn: ${detached.turnId}`)
  console.log(`Log: ${sessionLogFile(workDir, sessionId, detached.turnId)}`)
  console.log(`Tail: foreman session log ${sessionId}`)
  return 0
}
```

Add `list`, `show`, `log`, `stop`, and `close` handlers using `readSession`, directory listing under `sessionsRoot(workDir)`, `resolveSessionLogTurn`, `execSync` tail logic from `handleLogs`, `process.kill(-pid)`, `updateTurn(... status: 'cancelled' ...)`, and `closeSession`.

- [ ] **Step 5: Wire routing and help text**

In `main()` add:

```ts
case 'session':
  if (subcommand === 'resume') return handleSessionResume(args.slice(2))
  if (subcommand === 'list') return handleSessionList()
  if (subcommand === 'show') return handleSessionShow(args.slice(2))
  if (subcommand === 'log') return handleSessionLog(args.slice(2))
  if (subcommand === 'stop') return handleSessionStop(args.slice(2))
  if (subcommand === 'close') return handleSessionClose(args.slice(2))
  console.error('Usage: foreman session <list|show|resume|log|stop|close> ...')
  return 1
```

Update help text with:

```text
foreman session list
foreman session show <session-id>
foreman session resume <session-id> (--prompt "..." | --prompt-file <path>) [--notify]
foreman session log <session-id> [--turn 001]
foreman session stop <session-id>
foreman session close <session-id>
```

- [ ] **Step 6: Run CLI tests and full tests**

Run:

```bash
npx tsx --test tests/cli-session.test.mts
npm test
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add bin/foreman.mts lib/cli-helpers.mts tests/cli-session.test.mts
git commit -m "feat(foreman): add session CLI commands"
```

## Task 6: Notification Format With Session and Turn IDs

**Files:**
- Modify: `gol-tools/foreman/lib/notifier.mts`
- Create: `gol-tools/foreman/tests/notifier.test.mts`

- [ ] **Step 1: Export message formatter and add failing test**

Create `tests/notifier.test.mts`:

```ts
import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { formatNotificationMessage } from '../lib/notifier.mts'

describe('formatNotificationMessage', () => {
  it('includes session and turn ids when present', () => {
    const message = formatNotificationMessage({
      taskId: 'fs_20260521_abcd',
      sessionId: 'fs_20260521_abcd',
      turnId: '001',
      taskName: 'brainstorming',
      status: 'done',
      issueNumber: null,
      prUrl: null,
      duration: '8m 12s',
      summary: '本轮确认了夜袭节奏。',
    })

    assert.match(message, /^✅ brainstorming 完成 \[8m 12s\]/u)
    assert.match(message, /Session: fs_20260521_abcd/u)
    assert.match(message, /Turn: 001/u)
    assert.match(message, /本轮确认了夜袭节奏/u)
  })
})
```

- [ ] **Step 2: Run failing test**

Run:

```bash
npx tsx --test tests/notifier.test.mts
```

Expected: FAIL because `formatNotificationMessage` is not exported and `TaskResult` lacks session fields.

- [ ] **Step 3: Update notifier types and formatter**

Modify `lib/notifier.mts`:

```ts
export interface TaskResult {
  taskId: string
  sessionId?: string
  turnId?: string
  taskName: string
  status: 'done' | 'failed' | 'cancelled'
  issueNumber: number | null
  prUrl: string | null
  duration: string
  summary: string
}
```

Rename `formatMessage` to exported `formatNotificationMessage` and add session lines:

```ts
export function formatNotificationMessage(result: TaskResult): string {
  const icon = result.status === 'done' ? '✅' : result.status === 'failed' ? '❌' : '⚪'
  const statusLabel = STATUS_LABELS[result.status] || result.status
  let msg = `${icon} ${result.taskName} ${statusLabel}`
  if (result.issueNumber) msg += ` (#${result.issueNumber})`
  msg += ` [${result.duration}]`
  if (result.sessionId) msg += `\nSession: ${result.sessionId}`
  if (result.turnId) msg += `\nTurn: ${result.turnId}`
  if (result.summary) msg += `\n\n${result.summary}`
  if (result.prUrl) msg += `\nPR: ${result.prUrl}`
  return truncateForDelivery(msg)
}
```

Update notifier callers:

```ts
const message = formatNotificationMessage(result)
```

- [ ] **Step 4: Run tests**

Run:

```bash
npx tsx --test tests/notifier.test.mts
npm test
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add lib/notifier.mts tests/notifier.test.mts
git commit -m "feat(foreman): include session ids in notifications"
```

## Task 7: README and Shiori-Facing Harness Instructions

**Files:**
- Modify: `gol-tools/foreman/README.md`
- Modify: Shiori Foreman instruction source found by search

- [ ] **Step 1: Locate Shiori instruction source**

Run from parent repo:

```bash
rg -n "Shiori|foreman run task|foreman session|openclaw|Telegram|telegram" \
  /Users/dluck/Documents/GitHub/gol \
  /Users/dluck/Documents/GitHub/ai-config \
  ~/.codex/skills \
  ~/.claude/skills 2>/dev/null | head -c 12000
```

Expected: identify the canonical file that teaches Shiori or assistant harnesses how to call Foreman. Edit the canonical source reported by this command; do not edit synced copies under `~/.codex/skills` or `~/.claude/skills`.

- [ ] **Step 2: Update README commands**

In `gol-tools/foreman/README.md`, add:

```md
## Sessions

`foreman run task brainstorming` creates a durable Foreman session and starts turn `001`.
Follow-up messages use the Foreman session ID only.

```bash
foreman run task brainstorming --client cc-glm --prompt-file - --notify
foreman session resume fs_20260521_abcd --prompt-file - --notify
foreman session list
foreman session show fs_20260521_abcd
foreman session log fs_20260521_abcd --turn 001
foreman session stop fs_20260521_abcd
foreman session close fs_20260521_abcd
```

When `--notify` is used, each notification is a turn-completion event and includes:

```text
✅ brainstorming 完成 [8m 12s]
Session: fs_20260521_abcd
Turn: 001

本轮确认了夜袭导演的节奏目标与下一步讨论点。
```
```

- [ ] **Step 3: Update Shiori instructions**

Add this exact guidance to the canonical Shiori-facing source:

```md
### Foreman Session Flow

- Start a new design discussion with `foreman run task brainstorming --client cc-glm --prompt-file - --notify`.
- Treat the returned `fs_...` value as the only session ID users and Shiori need.
- Continue a discussion with `foreman session resume fs_20260521_abcd --prompt-file - --notify`, replacing `fs_20260521_abcd` with the Foreman session ID from the prior notification.
- Do not pass `--client` on resume.
- Do not use native Claude, Codex, or OpenCode session IDs.
- Do not use latest-session or continue fallback commands.
- On Foreman usage errors, surface the plain-text error or retry with the exact corrected Foreman command.
```

- [ ] **Step 4: Run docs check**

Run:

```bash
rg -n "foreman session resume|foreman run task brainstorming|--prompt-file" gol-tools/foreman/README.md
```

Expected: all new command forms are present.

- [ ] **Step 5: Commit**

Commit the `gol-tools` README change:

```bash
git add README.md
git commit -m "docs(foreman): document session turns"
```

When the canonical Shiori source is in `ai-config`, commit that repo separately. Set `SHIORI_FILE` to the path found in Step 1:

```bash
SHIORI_FILE=data/skills/shared/foreman/SKILL.md
git -C /Users/dluck/Documents/GitHub/ai-config add "$SHIORI_FILE"
git -C /Users/dluck/Documents/GitHub/ai-config commit -m "docs: teach shiori foreman session flow"
```

## Task 8: Manual Verification

**Files:**
- Modify only if fixes are needed

- [ ] **Step 1: Run full automated tests**

Run:

```bash
cd /Users/dluck/Documents/GitHub/gol/.worktrees/foreman-session-turns/foreman
npm test
```

Expected: PASS.

- [ ] **Step 2: Verify `brainstorming` starts a session without worktree**

Run:

```bash
printf '讨论夜袭导演的第一阶段玩法，不要写代码。' | npx tsx bin/foreman.mts run task brainstorming --client cc-glm --prompt-file - --notify | tee /tmp/foreman-brainstorming-session.out
SESSION_ID=$(awk '/^Session fs_/ { print $2 }' /tmp/foreman-brainstorming-session.out)
test -n "$SESSION_ID"
```

Expected output includes:

```text
Session fs_
Turn: 001
Tail: foreman session log fs_
```

Also verify no new `.worktrees/brainstorming-*` directory was created.

- [ ] **Step 3: Wait for notification and capture session ID**

Expected Telegram notification includes:

```text
Session: fs_
Turn: 001
```

- [ ] **Step 4: Resume by Foreman session ID**

Run:

```bash
printf '基于上一轮，继续比较两种节奏方案。' | npx tsx bin/foreman.mts session resume "$SESSION_ID" --prompt-file - --notify
```

Expected:

```text
Session fs_... resumed
Turn: 002
```

Notification later includes `Turn: 002`.

- [ ] **Step 5: Verify strict failures**

Run:

```bash
npx tsx bin/foreman.mts session resume
npx tsx bin/foreman.mts session resume "$SESSION_ID" --client cc-glm --prompt "bad"
npx tsx bin/foreman.mts session resume "$SESSION_ID" --prompt ""
```

Expected:

- Missing ID prints usage and exits non-zero.
- Unknown `--client` flag exits non-zero.
- Empty prompt exits non-zero.

- [ ] **Step 6: Verify Codex session start and resume**

Run:

```bash
npx tsx bin/foreman.mts run task generic --client codex --prompt "Say exactly: codex session start" --foreground --no-worktree | tee /tmp/foreman-codex-session.out
npx tsx bin/foreman.mts session list
CODEX_SESSION_ID=$(awk '/^Session fs_/ { print $2 }' /tmp/foreman-codex-session.out)
test -n "$CODEX_SESSION_ID"
npx tsx bin/foreman.mts session resume "$CODEX_SESSION_ID" --prompt "Say exactly: codex session resume" --foreground
```

Expected: first and second turns complete and `session.json` stores a Codex `clientSessionId`.

- [ ] **Step 7: Verify OpenCode session start and resume**

```bash
npx tsx bin/foreman.mts run task generic --client opencode --prompt "Say exactly: opencode session start" --foreground --no-worktree | tee /tmp/foreman-opencode-session.out
OPENCODE_SESSION_ID=$(awk '/^Session fs_/ { print $2 }' /tmp/foreman-opencode-session.out)
test -n "$OPENCODE_SESSION_ID"
npx tsx bin/foreman.mts session resume "$OPENCODE_SESSION_ID" --prompt "Say exactly: opencode session resume" --foreground
```

Expected: both turns complete, and `session.json` stores an OpenCode `clientSessionId` beginning with `ses_`.

- [ ] **Step 8: Commit any verification fixes**

When verification requires code fixes, commit them:

```bash
git status --short
git add lib/session-runner.mts lib/session-wrapper.mts lib/client-args.mts lib/log-parser.mts lib/opencode-session.mts bin/foreman.mts
git commit -m "fix(foreman): stabilize session turn verification"
```

## Task 9: Push Submodule and Parent Pointer

**Files:**
- Modify: parent repo `gol-tools` submodule pointer

- [ ] **Step 1: Push `gol-tools` branch**

Run:

```bash
cd /Users/dluck/Documents/GitHub/gol/.worktrees/foreman-session-turns
git status --short
git push -u origin feat/foreman-session-turns
```

Expected: branch is pushed.

- [ ] **Step 2: Create PR for `gol-tools`**

Run:

```bash
gh pr create -R Dluck-Games/gol-tools \
  --base main \
  --head feat/foreman-session-turns \
  --title "feat: add Foreman session turns" \
  --body "Adds Foreman session/turn lifecycle, strict resume commands, brainstorming task, and notification session IDs."
```

Expected: PR is created for the `gol-tools` submodule branch. Keep main history linear when merging.

- [ ] **Step 3: After merge, update parent submodule pointer**

Run from parent repo:

```bash
cd /Users/dluck/Documents/GitHub/gol
git submodule update --remote gol-tools
git add gol-tools
git commit -m "chore(foreman): update gol-tools session turns"
git push
```

Expected: parent repo points at the merged `gol-tools` commit. Do not stage or modify the existing unrelated `gol-project` dirty state.
