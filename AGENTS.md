# GOL — Management Repo Knowledge Base

## Overview

God of Lego (GOL) — 2D survival game, Godot 4.6, GDScript.

- `gol/` — Management repo (this repo)
- `gol-project/` — Game code submodule (actual development happens here)
- `gol-tools/` — Tooling submodule (AI agents, LSP bridge, debug tools)

## AGENTS.md maps

AGENTS.md maps of overall project structure. Read them when you first enter each folder to start working on it.

```
gol/                               # Management repo (YOU ARE HERE)
├── AGENTS.md                      # Workflow, CI/CD, agent preferences
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
└── gol-tools/                     # Tooling submodule
    ├── foreman/                   # AI daemon: GitHub issue → PR automation pipeline
    ├── gds-lsp/                   # GDScript LSP stdio-TCP bridge (npm: godot-lsp-stdio-bridge)
    └── ai-debug/                  # AI Debug Bridge: runtime screenshots, commands, script injection
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

## Development

### Testing

- **Unit tests:** gdUnit4 test suites for components, systems, and gameplay logic.
- **Integration tests:** SceneConfig-based tests that load real GOLWorlds for end-to-end verification.
- **E2E tests:** User-facing scenarios that validate complete features from input to output, also using SceneConfig for realistic environments.

**Test runners (two phases, both automated):**

- **Phase 1 — gdUnit4:** Discovers all `extends GdUnitTestSuite` suites (unit + integration).
- **Phase 2 — SceneConfig:** Each `extends SceneConfig` under `tests/integration/` loads a real GOLWorld for scene-level verification.
- Both phases run headless. `run-tests.command` in repo root runs everything with a combined ASCII report.

### CI/CD

All CI/CD workflows are defined in `gol-project/.github/workflows/`.

- **tests.yml**: unit + integration 2-phase tests on push to main/develop + PRs
- **build.yml**: Build on version tags (`X.Y.Z`, no `v` prefix)

## Workflow

**VCS workflow**

1. Finish work in submodules (`gol-project/` for game code, `gol-tools/` for tooling)
2. Push submodule changes first (`git push origin main` in submodule)
3. Update main repo reference (`git add gol-project/`), commit, and push main repo changes

**Agent workflow:**

- Delegate implementation tasks to subagents (via `task()`) rather than direct file editing
- Main agent focuses on acceptance, global decisions, and task coordination
- Execute independent tasks in parallel with multiple subagents for efficiency
- Functional changes also need E2E tests

**Issue feedback:** Report pain points encountered during work — repetitive tasks, time-consuming difficulties, inelegant code, hard-to-use tools — by creating issues on the `gol-project` repo (`gh issue create -R Dluck-Games/god-of-lego`).

## Rules

- **MONOREPO RULES**: This root (`gol/`) is strictly for management and coordination.
  - **ALWAYS** Push the submodule first, then update the main repo reference
  - **ALWAYS** Atomic push changes must be atomically pushed after completion without asking.
  - **NEVER** create game files (scripts/, assets/, scenes/) at this root.
  - **NEVER** run Godot from this directory — always work inside `gol-project/`.
  - **NEVER** create branches in the main repo (`gol/`) — all development happens in `gol-project/` submodule.

## Reference

- **SSOT Notes:** Obsidian vault "Notes" has original game design and tech notes of GOL project.
  - Use notesmd-cli to read.
  - Never modify notes or add any extra files in obsidian vault.
  - The original notes are the golden standard for all design and implementation decisions.
- **Project Documentation:** The `docs/` folder in mono repo contains working plans, design docs, and technical documentation of the project.
  - The `superpowers/` folder logged the plans and key decisions, read them for understanding the history of features and design choices for the project.
  - The `plans/` folder contains some working plans for single tasks used to be shared between agents, this is pieces of working notes.
  - The `handoff/` folder contains handoff notes of working tasks between agents, this is pieces of working notes.
