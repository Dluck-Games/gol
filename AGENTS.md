# GOL — Management Repo Knowledge Base

> **THIS IS A MANAGEMENT REPO.** Game code lives in `gol-project/` submodule.
> **NEVER** create game files (scripts/, assets/, scenes/) at this root.
> **NEVER** run Godot from this directory — always work inside `gol-project/`.

## Project

God of Lego (GOL) — 2D survival game, Godot 4.6, GDScript.
Architecture: ECS ([GECS](addons/gecs)) + MVVM UI + GOAP AI + PCG map generation.

## Repo Structure

```
gol/                           # Management repo (YOU ARE HERE)
├── AGENTS.md / CLAUDE.md      # This file (CLAUDE.md is symlink)
├── gol-project/               # Game code submodule (god-of-lego repo)
│   ├── scripts/               # ~180 GDScript files
│   │   ├── components/        # ECS Components (c_*.gd)
│   │   ├── systems/           # ECS Systems (s_*.gd, auto-discovered)
│   │   ├── gameplay/          # GOAP AI + ECS authoring + game state
│   │   ├── pcg/               # PCG pipeline + WFC
│   │   ├── services/          # ServiceContext + 7 service impls
│   │   ├── ui/                # MVVM: ViewModels + Views
│   │   ├── debug/             # ImGui debuggers
│   │   └── configs/           # Config.gd — game constants
│   ├── scenes/                # .tscn files
│   ├── resources/             # .tres (recipes, goals, sprite_frames)
│   ├── tests/                 # gdUnit4 tests (ai/, flow/, pcg/, system/, unit/)
│   └── addons/                # gecs, gdUnit4, imgui-godot
└── gol-tools/                 # Tooling submodule (foreman, gds-lsp)
```

## Where to Look

| Task | Location (inside gol-project/) | Notes |
|------|-------------------------------|-------|
| New entity type | `scripts/gameplay/ecs/authoring/` + `resources/recipes/` | Authoring + recipe .tres |
| ECS component | `scripts/components/c_*.gd` | Data only, extend Component |
| ECS system | `scripts/systems/s_*.gd` | Extend System, set group in `_ready()` |
| GOAP action | `scripts/gameplay/goap/actions/` | Extend GoapAction |
| GOAP goal | `resources/goals/*.tres` | GoapGoal resource |
| UI element | `scripts/ui/viewmodels/` + `views/` + `scenes/ui/` | ViewModel + View + .tscn |
| Service | `scripts/services/impl/service_*.gd` | Extend ServiceBase |
| PCG phase | `scripts/pcg/phases/` | Extend PCGPhase |
| Tests | `tests/{category}/test_*.gd` | gdUnit4, use skill `gol-unittest` |
| Game constants | `scripts/configs/config.gd` | Speeds, distances, base components |

## Architecture

**Data flow (one-way):** `System → Component → ViewModel → View`

**System groups (GOLWorld processing order):**

| Order | Group | Frame | Purpose |
|-------|-------|-------|---------|
| 1 | `gameplay` | `_process` | Movement, combat, AI, spawning, day/night |
| 2 | `ui` | `_process` | HUD, HP bars |
| 3 | `render` | `_process` | Sprite sync, map render, lighting |
| 4 | `physics` | `_physics_process` | Collision detection |

**Autoloads:** `ECS` (framework), `GOL` (game manager, `GOL.Game` for state), `DebugPanel`, `ImGuiRoot`

**Boot:** `main.tscn → GOL.setup() → ServiceContext.static_setup() → GOL.start_game() → PCG generate → GOLWorld.initialize() → auto-discover systems → bake entities → spawn`

## Naming Conventions (STRICT)

| Type | Class | File | Example |
|------|-------|------|---------|
| Component | `CThing` | `c_thing.gd` | `CTransform` / `c_transform.gd` |
| System | `SThing` | `s_thing.gd` | `SMove` / `s_move.gd` |
| Service | `Service_Thing` | `service_thing.gd` | `Service_PCG` / `service_pcg.gd` |
| ViewModel | `ViewModelThing` | `viewmodel_thing.gd` | `ViewModelHud` / `viewmodel_hud.gd` |
| View | `View_Thing` | `view_thing.gd` | `View_HPBar` / `view_hp_bar.gd` |
| GOAP Action | `GoapAction_Thing` | `thing.gd` | `GoapAction_ChaseTarget` / `chase_target.gd` |

## Code Style

```gdscript
class_name MyClass          # ALWAYS declare class_name
extends ParentClass

# Order: Constants → Signals → Enums → @export → Public vars → Private vars
# Then:  Lifecycle → Public funcs → Private funcs
```

- **Tabs** for indentation
- **Static typing everywhere**: `: int`, `-> void`, `Array[Entity]`
- **Short functions**, early returns
- **Entity creation**: `ServiceContext.recipe().create_entity_by_id("id")`
- **Service access**: `ServiceContext.thing()` — never direct

## Anti-Patterns

- Components with logic — they are **pure data**
- New singletons — only `ServiceContext` and `ECS` exist
- Direct service access — always `ServiceContext.thing()`
- Manual system instantiation — `GOLWorld._load_all_systems()` auto-discovers
- Using `GoapAction_MoveTo` directly — it's abstract, extend it
- Omitting `class_name` — every `.gd` file must have one

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
