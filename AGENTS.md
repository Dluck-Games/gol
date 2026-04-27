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
│   ├── foreman/                   # AI daemon: GitHub issue → PR automation pipeline
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
| Run editor | `gol run editor` | `godot --editor --path .` |
| Stop game/editor | `gol stop` | `pkill godot` / manual kill |
| Run unit tests | `gol test unit` | `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd ...` |
| Run integration tests | `gol test integration` | `godot --headless --path . --scene scenes/tests/test_main.tscn ...` |
| Run all tests | `gol test` | Both unit + integration |
| Reimport assets | `gol reimport` | `godot --headless --import --path .` |
| Debug commands | `gol debug <cmd>` | `node ai-debug/ai-debug.mjs <cmd>` |
| Debug screenshot | `gol debug screenshot` | `node ai-debug/ai-debug.mjs screenshot` |
| Debug eval | `gol debug eval <expr>` | `node ai-debug/ai-debug.mjs eval <expr>` |
| Debug script | `gol debug script <file>` | `node ai-debug/ai-debug.mjs script <file>` |
| Error/parse check | `gol test` | `godot --headless --quit --path . 2>&1 \| grep ...` |

### Path Resolution

The `gol` CLI resolves paths automatically — no manual path construction needed:
- **Godot binary**: `GODOT_PATH` env → platform defaults → `godot` on PATH
- **Project path**: `--path` flag → `GOL_PROJECT_PATH` env → auto-detect from CWD

## Development

### Testing

Three-tier test architecture (unit / integration / playtest). See `gol-project/tests/AGENTS.md` for full tier definitions and decision matrix.

**v4 Test Harness — subagent-driven (two skills):**

Main agents NEVER write, run, or playtest directly. Always dispatch via skill:

1. Load the appropriate skill
2. Determine tier from decision matrix
3. Dispatch subagent with the matching prompt template
4. Receive report, decide next action

| Need | Skill | Tier → Prompt | Model |
|------|-------|---------------|-------|
| Write unit test | gol-test-writer | unit → unit-prompt.md | sonnet |
| Write integration test | gol-test-writer | integration → integration-prompt.md | sonnet |
| Run existing tests | gol-test-runner | runner → runner-prompt.md | haiku |
| Verify feature in game (playtest) | gol-test-runner | playtest → playtest-prompt.md | sonnet |

Shell hooks enforce tier isolation (wrong base class = blocked).

**Running all tests:** `gol test` (combined ASCII report, both phases).

### CI/CD

All CI/CD workflows are defined in `gol-project/.github/workflows/`.

- **tests.yml**: unit + integration 2-phase tests on push to main/develop + PRs
- **build.yml**: Build on version tags (`X.Y.Z`, no `v` prefix)

## Workflow

**VCS workflow**

1. Finish work in submodules (`gol-project/` for game code, `gol-tools/` for tooling, `gol-arts/` for art assets)
2. When isolation is needed, create the submodule worktree under `gol/.worktrees/<name>/` from inside the submodule repo (for example, run `git worktree add` in `gol-project/` and point it at `gol/.worktrees/<name>`)
3. Do all code edits, tests, and branch operations inside that submodule worktree, not in the management repo root
4. Push submodule changes first (`git push origin main` in submodule)
5. Update the main repo's submodule pointer (`git add gol-project/`), commit, and push main repo changes

**Worktree workflow**

- All worktree checkouts live under `gol/.worktrees/`, organized by source:
  - `gol/.worktrees/manual/` — interactive agent or manual work (e.g. `manual/issue-188`)
  - `gol/.worktrees/foreman/` — foreman daemon auto-created (e.g. `foreman/ws_20260328_abcd1234`)
- Create worktrees from the submodule repository you are changing (`gol-project/`, `gol-tools/`, or `gol-arts/`), never from the management repo root
- Treat each worktree as disposable local state: do not stage or commit any path under `gol/.worktrees/` in the management repo, and clean them up after the task is merged or abandoned
- If a worktree needs Godot import/cache state for local testing, keep that setup local and out of version control

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
  - **ALWAYS** Keep all worktree checkouts under `gol/.worktrees/` (subdirs: `manual/`, `foreman/`), ignored by the management repo
  - **ALWAYS** Write AI debug scripts to `.debug/scripts/` — never in `gol-project/scripts/` (Godot imports them) or `/tmp/` (not project-scoped)
  - **NEVER** create game files (scripts/, assets/, scenes/) at this root.
  - **NEVER** run Godot from this directory — always work inside `gol-project/`.
  - **NEVER** create branches in the main repo (`gol/`) — all development happens in `gol-project/` submodule.
  - **NEVER** create a worktree for the management repo itself inside `gol/.worktrees/`; that directory holds only submodule checkouts from `gol-project/`, `gol-tools/`, or `gol-arts/`.

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
├── foreman/              # Foreman daemon per-issue work logs (organized by issue number)
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
| `foreman/` | Foreman daemon | Foreman daemon (auto-commits after each task) |
| `arts/` | Any agent | Agent that created it (atomic commit with the work) |
| `reports/` | Any agent | Agent that created it (atomic commit with the work) |
| `handoff/` | Any agent | Agent that created it (atomic commit with the work) |

### Workspace hygiene

- **NEVER** leave uncommitted doc files in `docs/` after a task completes — always commit with the work.
- **NEVER** create files outside the five defined subdirectories.
- **NEVER** create temporary or scratch files in `docs/` — use the agent's own local scratch space (`.sisyphus/`, `.claude/`, etc.).
- **NEVER** modify handoff notes after creation — they are immutable snapshots.
- Clean up stale handoff notes older than 7 days during any docs-related task.
