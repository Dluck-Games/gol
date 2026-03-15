# GOL — Management Repo Knowledge Base

> **THIS IS A MANAGEMENT REPO.** Game code lives in `gol-project/` submodule.
> **NEVER** create game files (scripts/, assets/, scenes/) at this root.
> **NEVER** run Godot from this directory — always work inside `gol-project/`.

## Project

God of Lego (GOL) — 2D survival game, Godot 4.6, GDScript.
Architecture: ECS ([GECS](addons/gecs)) + MVVM UI + GOAP AI + PCG map generation.

## Code Reference

See `gol-project/AGENTS.md` for detailed:
- Repo Structure
- Where to Look (task → location mapping)
- Architecture (data flow, system groups, boot sequence)
- Naming Conventions (STRICT)
- Code Style
- Anti-Patterns

## Submodule Workflow (CRITICAL)

All code changes happen inside `gol-project/`. Push order matters:

```bash
# 1. Commit in submodule
cd gol-project && git add . && git commit -m "feat: ..."
# 2. Push submodule FIRST
git push
# 3. Update management repo reference
cd .. && git add gol-project && git commit -m "chore: update submodule" && git push
```

**NEVER** run `git checkout` / Godot commands from the `gol/` root.

## Gotchas

- Chinese comments in some files (Config.gd, SMove, ECSUtils) — normal
- `GoapGoal` uses untyped Dictionary — Godot 4.x StringName leak bug workaround
- `Config.BASE_COMPONENTS` — components that survive death
- PCG uses seeded RNG — same seed = same map
- Entity recipes support inheritance via `base_recipe`

## Domain Knowledge (subdirectory AGENTS.md)

Detailed domain docs live alongside the code:
- `scripts/components/AGENTS.md` — Component catalog
- `scripts/systems/AGENTS.md` — System catalog & groups
- `scripts/gameplay/AGENTS.md` — GOAP AI + ECS authoring + recipes
- `scripts/pcg/AGENTS.md` — PCG pipeline & WFC
- `scripts/services/AGENTS.md` — Service layer
- `scripts/ui/AGENTS.md` — MVVM bindings
- `tests/AGENTS.md` — Test patterns & gdUnit4

## CI/CD

- **run-tests.yml**: gdUnit4 on push to main/develop + PRs
- **release.yml**: Build on version tags (`X.Y.Z`, no `v` prefix)
- Godot 4.5.1, Ubuntu (tests) / Windows (builds)

## Workflow

**Repository structure:**
- `gol/` — Management repo (this repo)
- `gol-project/` — Game code submodule (actual development happens here)

**Atomic push principle:** All code changes must be atomically pushed after completion.
- Always push the submodule first, then update the main repo reference
- Never run git checkout or Godot commands from the `gol/` root
