# GOL — Management Repo Knowledge Base

## Overview

God of Lego (GOL) — 2D survival game, Godot 4.6, GDScript.

- `gol/` — Management repo (this repo)
- `gol-project/` — Game code submodule (actual development happens here)
- `gol-tools/` — Tooling submodule (AI agents, LSP bridge, debug tools)
- `gol-arts/` — Art assets submodule (Aseprite sources, AI-generated artworks, prompts — Git LFS)

## AGENTS.md maps

AGENTS.md maps of overall project structure. Read them when you first enter each folder to start working on it.

```
gol/                               # Management repo (YOU ARE HERE)
├── AGENTS.md                      # Workflow, CI/CD, agent preferences
├── .debug/scripts/                # AI debug script sandbox (gitignored)
├── gol-project/                   # Game code submodule
│   ├── AGENTS.md                  # Code overview — read on first entry
│   ├── scripts/
│   │   ├── components/AGENTS.md   # Component catalog
│   │   ├── systems/AGENTS.md      # System catalog
│   │   ├── gameplay/AGENTS.md     # GOAP AI / ECS Authoring
│   │   ├── pcg/AGENTS.md          # Map generation pipeline
│   │   ├── services/AGENTS.md     # Service layer
│   │   └── ui/AGENTS.md           # UI / MVVM
│   └── tests/AGENTS.md            # Testing patterns and hierarchy
├── gol-tools/                     # Tooling submodule
│   ├── foreman/                   # AI task execution CLI: spawn coding agents with templated prompts
│   ├── gds-lsp/                   # GDScript LSP stdio-TCP bridge (npm: godot-lsp-stdio-bridge)
│   ├── ai-debug/                  # AI Debug Bridge: runtime screenshots, commands, script injection
│   └── pixel-art/                 # AI pixel art pipeline: Gemini/ComfyUI → render → evaluate
└── gol-arts/                      # Art assets submodule (Git LFS)
    ├── AGENTS.md                  # Path mapping convention
    ├── artworks/                  # AI-generated images + prompts
    │   └── <category>/            # Nested by game asset path
    └── assets/                    # Aseprite sources (mirrors gol-project/assets/)
        ├── sprites/
        ├── sprite_sheets/
        ├── tiles/
        └── ...
```

## Architectural principles

### GOL - God of Lego

- **ECS:** Data-driven design with GECS addon. Components are pure data, systems contain logic. Authoring via gameplay scripts that spawn entities with components.
- **MVVM UI:** Model-View-ViewModel pattern for UI, separating data, presentation, and logic.
- **GOAP AI:** Goal-Oriented Action Planning for NPC behavior, with a custom implementation in `gameplay/` scripts.
- **PCG Map Generation:** Procedural generation pipeline for maps, defined in `pcg/` scripts.

### GOL Tools -

- **Foreman:** AI agent that automates GitHub issue triage and PR creation based on task delegation.
- **GDS LSP Bridge:** Node.js tool that provides a TCP bridge for GDS Language Server Protocol, enabling AI agents to perform code analysis and refactoring.
- **AI Debug Bridge:** Runtime tool that allows AI agents to capture screenshots, execute commands, and inject scripts for debugging purposes.
- **Pixel Art Pipeline:** AI-driven asset creation tool that generates concept art (Gemini/ComfyUI), renders production pixel art with GOL's 10-color palette, and evaluates quality. See `gol-pixel-art` skill.

## GOL CLI Tool

All Godot and debug bridge interactions MUST go through the `gol` CLI binary. The CLI handles Godot binary discovery, project path resolution, PID management, and logging automatically.

**NEVER invoke the Godot binary (`godot`, `/Applications/Godot.app/...`) directly.**
**NEVER invoke `node ai-debug/ai-debug.mjs` directly.**
**Always use `gol` CLI commands.**

### Command Reference

| Intent | Command | Replaces |
|--------|---------|----------|
| Run game (headless) | `gol run game` | `godot --headless --path .` |
| Run game (windowed) | `gol run game --windowed` | `godot --path . --windowed` |
| Run game (skip menu) | `gol run game --windowed -- --skip-menu` | Direct to gameplay |
| Run game (detached) | `gol run game --detach` | `godot --headless --path . &` |
| Run game (detached, windowed) | `gol run game --detach --windowed` | `godot --path . --windowed &` |
| Run editor | `gol run editor` | `godot --editor --path .` |
| Stop game/editor | `gol stop` | `pkill godot` / manual kill |
| Run unit tests | `gol test unit` | `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd ...` |
| Run integration tests | `gol test integration` | `godot --headless --path . --scene scenes/tests/test_main.tscn ...` |
| Run all tests | `gol test --all` | Both unit + integration |
| Run specific suites | `gol test unit --suite pcg,ai` | Run only pcg + ai unit tests |
| Run tests with detail | `gol test unit --verbose` | Full suite table + raw gdunit4 output |
| Run suites verbosely | `gol test unit --suite system -v` | Detailed output for system tests only |
| Reimport assets | `gol reimport` | `godot --headless --import --path .` |
| Debug commands | `gol debug <cmd>` | `node ai-debug/ai-debug.mjs <cmd>` |
| Debug screenshot | `gol debug screenshot` | `node ai-debug/ai-debug.mjs screenshot` |
| Debug eval | `gol debug eval <expr>` | `node ai-debug/ai-debug.mjs eval <expr>` |
| Debug script | `gol debug script <file>` | `node ai-debug/ai-debug.mjs script <file>` |
| Debug input injection | `gol debug input <op> [action]` | Temporary debug scripts for basic player input |
| Error/parse check | `gol test unit` | `godot --headless --quit --path . 2>&1 \| grep ...` |

### Argument Pass-Through

`gol run game` supports passing arbitrary arguments to Godot via `--` separator:

    gol run game --windowed -- --skip-menu --custom-arg=value

Arguments after `--` are forwarded directly to Godot. The game reads them via `OS.get_cmdline_user_args()`.

| Game Argument  | Description                                |
|----------------|--------------------------------------------|
| `--skip-menu`  | Skip title screen, go directly to gameplay |

All test commands (`gol test unit`, `gol test integration`, `gol test`) automatically inject `--skip-menu`. No manual action needed.

### Detached Mode

`--detach` launches the game in the background, redirects all output to a log file, and returns immediately. This is designed for **AI agents** whose Bash tool blocks on streaming stdout.

    gol run game --detach
    gol run game --detach --windowed -- --skip-menu

When detached, the command prints the PID and log file path, then exits:

    Game started (PID 12345, detached)
    Log: /path/to/gol/logs/game/game-20260429-094727.log

**When to use `--detach`:**
- Calling `gol run game` from an AI agent's Bash tool (opencode, claude code, etc.)
- Any context where the caller needs the shell to return immediately

**When NOT to use `--detach`:**
- Interactive terminal sessions where you want to see live Godot output
- When you need Ctrl+C to stop the game (use `gol stop` instead)

**To check logs after detached launch:** `cat <log-path>` or `tail -f <log-path>`
**To stop a detached game:** `gol stop`

### Path Resolution

The `gol` CLI resolves paths automatically — no manual path construction needed:
- **Godot binary**: `GODOT_PATH` env → platform defaults → `godot` on PATH
- **Project path**: `--path` flag → `GOL_PROJECT_PATH` env → auto-detect from CWD

## Development

### Testing

Three-tier test architecture (unit / integration / playtest). See `gol-project/tests/AGENTS.md` for full tier definitions and decision matrix.

**v4 Test Harness — direct automated tests + delegated playtest (two skills):**

Main agents NEVER write tests or playtest directly. Automated test execution is direct through `gol test`; only live playtesting dispatches a subagent:

1. Load the appropriate skill
2. Determine tier from decision matrix
3. For unit, integration, or all-test execution, run the matching `gol test ...` command directly
4. For playtest, dispatch a subagent with the playtest prompt template
5. Receive report, decide next action

| Need | Skill | Tier → Prompt | Model |
|------|-------|---------------|-------|
| Write unit test | gol-test-writer | unit → unit-prompt.md | sonnet |
| Write integration test | gol-test-writer | integration → integration-prompt.md | sonnet |
| Run unit tests | gol-test-runner | direct `gol test unit` | main agent |
| Run integration/all tests | gol-test-runner | direct `gol test integration` / `gol test --all` | main agent |
| Verify feature in game (playtest) | gol-test-runner | playtest → playtest-prompt.md | haiku / OMO unspecified-low |

Shell hooks enforce tier isolation (wrong base class = blocked).

**Running tests:** `gol test` requires an explicit tier (`unit` or `integration`) or `--all`. Use `--verbose` for full suite table and slow-test warnings. Use `--suite pcg,ai` to run only specific test suites.

Examples:
- `gol test unit` — run unit tests only
- `gol test integration` — run integration tests only
- `gol test --all` — run both unit and integration
- `gol test unit --suite ai,system -v` — verbose, filtered to ai + system suites

### CI/CD

All CI/CD workflows are defined in `gol-project/.github/workflows/`.

- **tests.yml**: unit + integration 2-phase tests on push to main/develop + PRs
- **build.yml**: Build on version tags (`X.Y.Z`, no `v` prefix)

## Workflow

**VCS workflow**

1. Finish work in submodules (`gol-project/` for game code, `gol-tools/` for tooling, `gol-arts/` for art assets)
2. When isolation is needed, create a submodule worktree directly under `gol/.worktrees/<name>/` from inside the submodule repo (for example, run `git worktree add` in `gol-project/` and point it at `gol/.worktrees/<name>`)
3. Do all code edits, tests, and branch operations inside that submodule worktree, not in the management repo root
4. Push submodule changes first (`git push origin main` or the active feature branch in the submodule)
5. Update the main repo's submodule pointer (`git add gol-project/`, `git add gol-tools/`, or `git add gol-arts/`), commit, and push main repo changes

**Worktree workflow**

- All worktree checkouts live directly under `gol/.worktrees/<name>/`; do not add source buckets such as `manual/` or `foreman/`
- Create worktrees only from the submodule repository you are changing (`gol-project/`, `gol-tools/`, rarely `gol-arts/`), never from the management repo root
- Prefer worktrees for `gol-project` feature/issue work and `gol-tools` tooling work. `gol-arts` usually does not need worktrees unless an art task explicitly needs isolation.
- Treat each worktree as disposable local state: do not stage or commit any path under `gol/.worktrees/` in the management repo, and clean them up after the task is merged or abandoned
- If a worktree needs Godot import/cache state for local testing, keep that setup local and out of version control

**Branch workflow**

- `gol-project/`: branch-driven development for features, fixes, and Foreman issue work (`feat/...`, `fix/...`, `foreman/...`), followed by PR/merge before updating the parent submodule pointer
- `gol-tools/`: create branches/worktrees for larger tooling features; small maintenance changes may commit directly to `main`
- `gol/` management repo and `gol-arts/`: normally commit directly to `main`; do not create management-repo branches or worktrees unless the user explicitly requests an exception

**Agent workflow:**

- Delegate implementation tasks to subagents (via `task()`) rather than direct file editing
- Main agent focuses on acceptance, global decisions, and task coordination
- Execute independent tasks in parallel with multiple subagents for efficiency
- **Test work ALWAYS delegates** via category+skill delegation. Never write tests directly.
- Functional changes should include test coverage (delegate to appropriate writer tier)

**Issue feedback:** Report pain points encountered during work — repetitive tasks, time-consuming difficulties, inelegant code, hard-to-use tools — by creating issues on the `gol-project` repo (`gh issue create -R Dluck-Games/god-of-lego`).

## Rules

- **MONOREPO RULES**: This root (`gol/`) is strictly for management and coordination.
  - **ALWAYS** Push the submodule first, then update the main repo reference
  - **ALWAYS** Atomic push changes must be atomically pushed after completion without asking.
  - **ALWAYS** Keep all worktree checkouts directly under `gol/.worktrees/<name>/`, ignored by the management repo
  - **ALWAYS** Write AI debug scripts to `.debug/scripts/` — never in `gol-project/scripts/` (Godot imports them) or `/tmp/` (not project-scoped)
  - **NEVER** create game files (scripts/, assets/, scenes/) at this root.
  - **NEVER** run Godot from this directory — always work inside `gol-project/`.
  - **NEVER** create branches in the main repo (`gol/`) for normal development — branch-driven work belongs in submodules, especially `gol-project/`.
  - **NEVER** create a worktree for the management repo itself inside `gol/.worktrees/`; that directory holds only direct child worktrees from `gol-project/`, `gol-tools/`, or rare `gol-arts/` isolation work.

## Reference

- **SSOT Notes:** Obsidian vault "Notes" has original game design and tech notes of GOL project.
  - Use notesmd-cli to read.
  - Never modify notes or add any extra files in obsidian vault.
  - The original notes are the golden standard for all design and implementation decisions.
- **Project Documentation:** The `docs/` folder in mono repo contains working plans, design docs, and technical documentation of the project.
  - The `superpowers/` folder logged the plans and key decisions, read them for understanding the history of features and design choices for the project.
  - The `handoff/` folder contains handoff notes of working tasks between agents, this is pieces of working notes.

## Docs — Structure & Rules

```
docs/
├── superpowers/          # Feature specs, plans, and key design decisions
│   ├── plans/            # Implementation plans (date-prefixed: YYYY-MM-DD-topic.md)
│   └── specs/            # Design specs and technical blueprints (date-prefixed)
├── foreman/              # Foreman per-issue work logs (organized by issue number)
├── arts/                 # Art standards SSOT (style guide, asset paths, prompt templates)
│   ├── style-guide.md   # Palette, aesthetic rules, animation conventions
│   ├── asset-paths.md   # Where each asset type goes in gol-project/
│   ├── commit-convention.md  # art(category): description format
│   └── prompts/          # Per-category prompt templates (character, enemy, box, etc.)
├── reports/              # Analysis and verification reports (date-prefixed)
└── handoff/              # Session handoff notes between agents (date-prefixed)
```

### File naming

- **All docs** use `YYYY-MM-DD-topic.md` format (except `foreman/` which uses `issue-number/` dirs)
- No spaces, no CamelCase, lowercase with hyphens

### Ownership & commits

| Folder | Created by | Committed by |
|---|---|---|
| `superpowers/` | Planning agents | Planning agent (with the plan commit) |
| `foreman/` | Foreman | Foreman (auto-commits after each task) |
| `arts/` | Any agent | Agent that created it (atomic commit with the work) |
| `reports/` | Any agent | Agent that created it (atomic commit with the work) |
| `handoff/` | Any agent | Agent that created it (atomic commit with the work) |

### Workspace hygiene

- **NEVER** leave uncommitted doc files in `docs/` after a task completes — always commit with the work.
- **NEVER** create files outside the five defined subdirectories.
- **NEVER** create temporary or scratch files in `docs/` — use the agent's own local scratch space (`.sisyphus/`, `.claude/`, etc.).
- **NEVER** modify handoff notes after creation — they are immutable snapshots.
- Clean up stale handoff notes older than 7 days during any docs-related task.
