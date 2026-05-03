# Unified Worktree Directory Layout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Superseded by the current direct-child convention: all submodule worktrees now live directly under `gol/.worktrees/<name>/`; source buckets are no longer used.

**Goal:** Consolidate all worktree checkouts under `gol/.worktrees/` so manual and Foreman worktrees share a single discoverable root.

**Architecture:** Change foreman's `WorkspaceManager` to write worktrees to `.worktrees/` instead of `.foreman/workspaces/`. Update safety guards to match the new path. Update AGENTS.md docs to document the direct-child worktree convention. `.foreman/` retains all non-worktree runtime data (state, logs, plans, etc.).

**Tech Stack:** Node.js (foreman), Git worktrees, Markdown docs

---

### Task 1: Update WorkspaceManager to use `.worktrees/`

**Files:**
- Modify: `gol-tools/foreman/lib/workspace-manager.mjs:18` (wsDir path)
- Modify: `gol-tools/foreman/lib/workspace-manager.mjs:113` (destroy safety guard)

- [ ] **Step 1: Change `#wsDir` initialization**

In `workspace-manager.mjs` line 18, the wsDir is derived from `config.dataDir`:

```js
// Before
this.#wsDir = join(config.dataDir, 'workspaces');

// After
this.#wsDir = join(config.workDir, '.worktrees');
```

This switches from `.foreman/workspaces/` to `.worktrees/`. The `config.workDir` is already `/Users/dluckdu/Documents/Github/gol`.

- [ ] **Step 2: Verify destroy safety guard still works**

The `destroy()` method at line 113 checks `wsPath.startsWith(this.#wsDir)`. Since `#wsDir` is computed in the constructor, this guard automatically protects the new path — no code change needed, just verify by reading.

- [ ] **Step 3: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools
git add foreman/lib/workspace-manager.mjs
git commit -m "refactor(foreman): move worktrees from .foreman/workspaces/ to .worktrees"
```

---

### Task 2: Clean up old `.foreman/workspaces/` directory

**Files:**
- None (filesystem cleanup only)

- [ ] **Step 1: Check for any active foreman worktrees**

```bash
ls /Users/dluckdu/Documents/Github/gol/.foreman/workspaces/ 2>/dev/null
```

If worktrees exist, check whether foreman has active tasks via `.foreman/state.json`. Only proceed if no active tasks reference these paths.

- [ ] **Step 2: Prune and remove old workspaces directory**

```bash
git -C /Users/dluckdu/Documents/Github/gol/gol-project worktree prune
rm -rf /Users/dluckdu/Documents/Github/gol/.foreman/workspaces
```

This cleans git's worktree metadata for any stale entries, then removes the now-unused directory.

---

### Task 3: Update AGENTS.md worktree documentation

**Files:**
- Modify: `gol/AGENTS.md:80-85` (Worktree workflow section)
- Modify: `gol/AGENTS.md:101` (rule about worktrees)

- [ ] **Step 1: Update the Worktree workflow section**

Replace the current "Worktree workflow" block (lines 80–85) with:

```markdown
**Worktree workflow**

- All worktree checkouts live directly under `gol/.worktrees/<name>/`; do not create source buckets.
- Interactive agent and Foreman worktrees use the same direct-child namespace (for example, `.worktrees/issue-188` or `.worktrees/ws_20260328_abcd1234`).
- Create worktrees from the submodule repository you are changing (`gol-project/` or `gol-tools/`), never from the management repo root
- Treat each worktree as disposable local state: do not stage or commit any path under `gol/.worktrees/` in the management repo, and clean them up after the task is merged or abandoned
- If a worktree needs Godot import/cache state for local testing, keep that setup local and out of version control
```

- [ ] **Step 2: Update the monorepo rules section**

Line 101, update the ALWAYS rule:

```markdown
  - **ALWAYS** Keep all worktree checkouts directly under `gol/.worktrees/<name>/`, ignored by the management repo
```

Line 105, update the NEVER rule:

```markdown
  - **NEVER** create a worktree for the management repo itself inside `gol/.worktrees/`; that directory holds only submodule checkouts from `gol-project/` or `gol-tools/`.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol
git add AGENTS.md
git commit -m "docs: unify worktree directory layout under .worktrees/"
```

---

### Task 4: Update CLAUDE.md worktree references

**Files:**
- Modify: `gol/CLAUDE.md` (Worktree workflow section mirrors AGENTS.md)

- [ ] **Step 1: Sync CLAUDE.md worktree sections with AGENTS.md**

CLAUDE.md has the same Worktree workflow and Rules sections. Apply the same changes from Task 3 to keep them consistent.

- [ ] **Step 2: Commit**

```bash
cd /Users/dluckdu/Documents/Github/gol
git add CLAUDE.md
git commit -m "docs: sync CLAUDE.md with unified worktree layout"
```

---

### Task 5: Atomic push

**Files:** None (VCS operations only)

- [ ] **Step 1: Push gol-tools submodule** (Task 1 changes)

```bash
cd /Users/dluckdu/Documents/Github/gol/gol-tools
git push origin main
```

- [ ] **Step 2: Update and push parent repo** (Task 3–4 changes + submodule pointer)

```bash
cd /Users/dluckdu/Documents/Github/gol
git add gol-tools AGENTS.md CLAUDE.md
git commit -m "chore: unify worktree layout — .worktrees/{manual,foreman}"
git push origin main
```
