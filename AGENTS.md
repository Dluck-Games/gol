# GOL — Management Repo Knowledge Base

> **THIS IS A MANAGEMENT REPO.** Game code lives in `gol-project/` submodule.
> **NEVER** create game files (scripts/, assets/, scenes/) at this root.
> **NEVER** run Godot from this directory — always work inside `gol-project/`.

## Project

God of Lego (GOL) — 2D survival game, Godot 4.6, GDScript.
Architecture: ECS ([GECS](addons/gecs)) + MVVM UI + GOAP AI + PCG map generation.

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
│   └── tests/AGENTS.md            # Testing patterns
└── gol-tools/                     # Tooling submodule
    ├── foreman/                   # AI daemon: GitHub issue → PR automation pipeline
    ├── gds-lsp/                   # GDScript LSP stdio-TCP bridge (npm: godot-lsp-stdio-bridge)
    └── ai-debug/                  # AI Debug Bridge: runtime screenshots, commands, script injection
```

## CI/CD

- **run-tests.yml**: gdUnit4 on push to main/develop + PRs
- **release.yml**: Build on version tags (`X.Y.Z`, no `v` prefix)
- Godot 4.6.1, Ubuntu (tests) / Windows (builds)

## Workflow

**Repository structure:**
- `gol/` — Management repo (this repo)
- `gol-project/` — Game code submodule (actual development happens here)

**Atomic push principle:** All code changes must be atomically pushed after completion.
- Always push the submodule first, then update the main repo reference
- Never run git checkout or Godot commands from the `gol/` root

**Agent workflow:**
- Delegate implementation tasks to subagents (via `task()`) rather than direct file editing
- Main agent focuses on acceptance, global decisions, and task coordination
- Execute independent tasks in parallel with multiple subagents for efficiency
- Unit tests required; functional changes also need E2E tests

**Issue feedback:** Report pain points encountered during work — repetitive tasks, time-consuming difficulties, inelegant code, hard-to-use tools — by creating issues on the `gol-project` repo (`gh issue create -R Dluck-Games/god-of-lego`).

**Chinese summary for acceptance:** When delivering user-facing changes, provide a concise Chinese summary from the user's perspective — what changed, how to verify, and whether any issues should be filed.
