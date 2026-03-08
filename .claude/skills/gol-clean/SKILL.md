---
name: gol-clean
description: Reset the gol management repo and all submodules to a clean state. Use when AI tools have polluted the working directory with stale branches, leaked game files, or dirty submodules.
allowed-tools: Bash
---

# gol-clean — Management Repo Environment Recovery

> **PURPOSE:** Restore the gol management repo + all submodules to a pristine state,
> matching remote `main` exactly with zero local modifications.

## When to Use

- AI tools leaked game files (scripts/, assets/, scenes/, etc.) into gol/ root
- Stale local/remote branch references accumulated
- Submodules are on wrong branches or have dirty working trees
- `git status` shows unexpected modifications or untracked files
- General "something feels off" with the repo state

## Recovery Procedure

Execute all phases in order. Every phase is mandatory.

---

### Phase 1: Verify Starting Point

```bash
cd /Users/dluckdu/Documents/Github/gol
pwd  # MUST be the management repo root
git remote -v  # MUST show Dluck-Games/gol.git
```

If not at the correct path, stop and navigate there first.

---

### Phase 2: Clean Main Repo

#### 2.1 Switch to main and pull latest

```bash
git checkout main
git pull origin main
```

#### 2.2 Prune stale remote-tracking branches

```bash
git fetch --prune origin
```

#### 2.3 Delete ALL local branches except main

```bash
git branch | grep -v '^\* main$' | xargs git branch -D 2>/dev/null
```

#### 2.4 Verify only main remains

```bash
git branch -a
# Expected:
#   * main
#   remotes/origin/HEAD -> origin/main
#   remotes/origin/main
#   (plus any active remote branches that actually exist on GitHub)
```

---

### Phase 3: Clean Submodules

#### 3.1 gol-project

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-project

# Discard all local changes and untracked files
git restore . 2>/dev/null
git clean -fd

# Prune stale remote refs
git fetch --prune origin

# Delete all local branches except main
git checkout main 2>/dev/null
git branch | grep -v '^\* main$' | xargs git branch -D 2>/dev/null
```

#### 3.2 gol-tools

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools

# Discard all local changes and untracked files
git restore . 2>/dev/null
git clean -fd

# Prune stale remote refs
git fetch --prune origin

# Delete all local branches except main
git checkout main 2>/dev/null
git branch | grep -v '^\* main$' | xargs git branch -D 2>/dev/null
```

#### 3.3 Reset submodule pointers to match management repo

```bash
cd /Users/dluckdu/Documents/Github/gol
git submodule update --init --recursive
```

This checks out gol-project and gol-tools to the exact commits recorded by the management repo's main branch.

---

### Phase 4: Remove Leaked Files from Root

Game directories MUST NOT exist in the gol/ root (they belong in gol-project/).

```bash
cd /Users/dluckdu/Documents/Github/gol

# Remove known game directories that should never be here
rm -rf addons/ assets/ scenes/ scripts/ tests/ resources/ shaders/ external/ 2>/dev/null

# Remove common AI/editor junk files
rm -rf .codebuddy/ .foreman/ .sisyphus/ 2>/dev/null
rm -f .DS_Store "CLAUDE 2.md" ENDOFSCRIPT EOF godot_game_screenshot.png 2>/dev/null

# Remove any leftover temp test branches' artifacts
rm -f /tmp/e2e_*.gd 2>/dev/null
```

---

### Phase 5: Final Verification (MANDATORY)

```bash
cd /Users/dluckdu/Documents/Github/gol

# Must be completely clean
git status
# Expected output:
#   On branch main
#   Your branch is up to date with 'origin/main'.
#   nothing to commit, working tree clean

# Directory listing must only contain expected items
ls -la
# Expected:
#   .claude/
#   .git/
#   .gitignore
#   .gitmodules
#   .opencode/
#   AGENTS.md
#   CLAUDE.md -> AGENTS.md
#   gol-project/
#   gol-tools/
```

If `git status` is not clean after all phases, investigate what remains:

```bash
git status --porcelain
```

- `M gol-project` or `M gol-tools` → re-run `git submodule update --init`
- `?? some-file` → remove the untracked file manually
- ` M some-file` → `git restore some-file`

---

## Quick One-Liner (for experienced users)

If you're confident and just want to nuke everything back to clean:

```bash
cd /Users/dluckdu/Documents/Github/gol && \
git checkout main && git pull origin main && git fetch --prune origin && \
git branch | grep -v '^\* main$' | xargs git branch -D 2>/dev/null; \
cd gol-project && git restore . 2>/dev/null; git clean -fd; git fetch --prune origin; \
git checkout main 2>/dev/null; git branch | grep -v '^\* main$' | xargs git branch -D 2>/dev/null; \
cd ../gol-tools && git restore . 2>/dev/null; git clean -fd; git fetch --prune origin; \
git checkout main 2>/dev/null; git branch | grep -v '^\* main$' | xargs git branch -D 2>/dev/null; \
cd .. && git submodule update --init --recursive && \
rm -rf addons/ assets/ scenes/ scripts/ tests/ resources/ shaders/ external/ .codebuddy/ .foreman/ .sisyphus/ 2>/dev/null; \
rm -f .DS_Store "CLAUDE 2.md" ENDOFSCRIPT EOF godot_game_screenshot.png 2>/dev/null; \
git status
```

---

## What This Repo Should Look Like When Clean

```
gol/                        # Management repo
├── .claude/skills/         # AI skill definitions (git tracked)
├── .opencode/              # OpenCode config (git tracked)
├── .gitignore              # Blocks game dirs from being tracked
├── .gitmodules             # Defines gol-project + gol-tools submodules
├── AGENTS.md               # Project knowledge base
├── CLAUDE.md -> AGENTS.md  # Symlink for Claude Code
├── gol-project/            # Game code submodule (detached HEAD is normal)
└── gol-tools/              # Tooling submodule (on main branch)
```

Nothing else should exist at the root level. If it does, it's pollution from a previous AI session.
