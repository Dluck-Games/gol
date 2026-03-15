# GOL — Management Repo Knowledge Base

> **THIS IS A MANAGEMENT REPO.** Game code lives in `gol-project/` submodule.
> **NEVER** create game files (scripts/, assets/, scenes/) at this root.
> **NEVER** run Godot from this directory — always work inside `gol-project/`.

## Project

God of Lego (GOL) — 2D survival game, Godot 4.6, GDScript.
Architecture: ECS ([GECS](addons/gecs)) + MVVM UI + GOAP AI + PCG map generation.

## AGENTS.md Map

渐进式披露 — 按需阅读：

```
gol/
└── AGENTS.md                    # YOU ARE HERE — 管理仓库知识（工作流程、CI/CD）
    
gol-project/
├── AGENTS.md                    # 代码总览 — 首次进入子模块时阅读
│                               #   • Repo Structure, Where to Look
│                               #   • Architecture, Naming Conventions
│                               #   • Code Style, Anti-Patterns
├── scripts/
│   ├── components/AGENTS.md     # 组件开发 → 查阅组件目录
│   ├── systems/AGENTS.md        # 系统开发 → 查阅系统目录
│   ├── gameplay/AGENTS.md       # GOAP AI / ECS Authoring → 查阅此处
│   ├── pcg/AGENTS.md            # 地图生成 → 查阅此处
│   ├── services/AGENTS.md       # 服务层 → 查阅此处
│   └── ui/AGENTS.md             # UI/MVVM → 查阅此处
└── tests/AGENTS.md              # 测试 → 查阅此处
```

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

**Agent workflow:**
- Delegate implementation tasks to subagents (via `task()`) rather than direct file editing
- Main agent focuses on acceptance, global decisions, and task coordination
- Execute independent tasks in parallel with multiple subagents for efficiency
