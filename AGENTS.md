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

## AI Agent Workflow Preferences

### 代理分工原则

- **具体工作委托**: 尽可能使用 sub agent（如 task() 调用）完成具体实现工作，而非主代理直接编辑文件
- **主代理职责**: 主代理专注于验收、决策全局、协调任务，避免陷入细节实现
- **并行执行**: 对于独立的多个任务，使用并行 sub agent 同时执行，提高效率

### 推送规则

**原子化推送原则**: 所有代码变更完成后必须原子化推送到仓库

**子模块 vs 主模块区分**:
- `gol-project/` 是**子模块**（游戏代码仓库）
- `gol/` 是**主模块**（管理仓库）

**正确推送流程**:
```bash
# 1. 先在子模块提交
cd gol-project
git add .
git commit -m "feat: your changes"

# 2. 先推送子模块
git push

# 3. 回到主模块更新子模块引用
cd ..
git add gol-project
git commit -m "chore: update submodule"
git push
```

**关键提醒**:
- 永远先推送子模块，再更新主模块的引用
- 禁止直接从 gol/ 根目录运行 git checkout 或 Godot 命令
- 所有游戏代码变更必须在 gol-project/ 目录内进行
