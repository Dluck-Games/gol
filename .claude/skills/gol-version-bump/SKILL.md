---
name: gol-version-bump
description: Automated version updates for Godot projects (god-of-lego). Triggers - 'bump version', 'update version', 'new version'
allowed-tools: Bash, Read, Edit
---

## ⚠️ CRITICAL: Submodule-Only Operation

**gol** is a parent repo that aggregates submodules. The actual Godot project with `project.godot` is in the **`gol-project/` submodule**.

### Common Mistake to Avoid
- ❌ DO NOT look for `project.godot` in `gol/` root
- ❌ DO NOT commit version changes to `gol/` parent repo
- ✅ ALWAYS operate inside `gol-project/` submodule

### Directory Structure Awareness
```
gol/                      ← Parent repo (NO project.godot here)
├── .claude/
├── gol-project/          ← SUBMODULE: Actual Godot project
│   ├── project.godot     ← TARGET FILE IS HERE
│   └── ...
└── gol-tools/            ← Another submodule
```

## Standard Operating Procedure

### 1. Location Verification (MANDATORY FIRST STEP)
Before anything else, verify your location:
```bash
pwd                              # Check current directory
ls project.godot 2>/dev/null     # Should FAIL if in gol/ root
ls gol-project/project.godot     # Should SUCCEED if in gol/ root
```

**If you are in `gol/` root (not in `gol-project/`):**
- Change into the submodule: `cd gol-project`
- All subsequent operations happen INSIDE `gol-project/`

### 2. Environment Check and Cleanup
- **Branch restriction**: Must be executed on the `main` branch of the **submodule**.
- **Status cleanup**: Clean the submodule workspace before updating.
  ```bash
  cd gol-project  # Ensure you're in the submodule
  git checkout main
  git pull origin main
  git reset --hard HEAD
  git clean -fd
  ```

### 3. Version Number Identification and Modification
- **Target file**: `gol-project/project.godot` (inside the submodule)
- **Operation logic**:
  1. Read `config/version="x.x.x"` from `project.godot`.
  2. Calculate the new version number based on the update requirement (patch/minor/major).
  3. Use `sed` or file read/write tools to update that line.

### 4. Commit, Tag, and Push (Submodule)
- **Commit Message**: Must strictly follow the format `chore: bump version to x.x.x`.
- **Tag format**: Must use a pure numeric version number (e.g., `0.1.5`), do not use the `v` prefix.
  ```bash
  # Inside gol-project/ submodule
  git add project.godot
  git commit -m "chore: bump version to $NEW_VERSION"
  git tag $NEW_VERSION
  git push origin main
  git push origin --tags
  ```

### 5. CRITICAL: Update Parent Repo Submodule Pointer
**After pushing the submodule, you MUST update the parent repo:**

```bash
cd ..  # Go back to gol/ parent directory
git add gol-project
git commit -m "chore: update gol-project submodule (bump version to $NEW_VERSION)"
git push origin main
```

**⚠️ DO NOT SKIP THIS STEP.** The parent repo tracks a specific submodule commit. Without this step, other developers will not see the version bump.

## Automated Script Example

Complete workflow including submodule and parent repo updates:

```bash
# ============ PHASE 1: Submodule (gol-project) ============
cd gol-project  # CRITICAL: Must operate in submodule

NEW_VERSION="0.1.5"

# Verify location
current_dir=$(pwd)
if [[ "$current_dir" != *"gol-project"* ]]; then
    echo "ERROR: Must run inside gol-project submodule!"
    exit 1
fi

# Modify file
sed -i '' "s/config\/version=\".*\"/config\/version=\"$NEW_VERSION\"/" project.godot

# Commit and tag in submodule
git add project.godot
git commit -m "chore: bump version to $NEW_VERSION"
git tag $NEW_VERSION
git push origin main
git push origin --tags

# ============ PHASE 2: Parent Repo (gol) ============
cd ..  # Back to parent repo
git add gol-project
git commit -m "chore: update gol-project submodule (bump version to $NEW_VERSION)"
git push origin main
```

## Verification Checklist

Before declaring success, verify:
- [ ] `pwd` shows you're in `gol-project/` when modifying files
- [ ] `project.godot` was found and modified inside `gol-project/`
- [ ] Commit and tag were pushed from `gol-project/` submodule
- [ ] Parent repo `gol/` has an updated submodule pointer commit
- [ ] Parent repo push includes `gol-project @ <new-commit-hash>`

## Error Prevention

### If you get "project.godot not found":
```bash
# You're probably in wrong directory
cd gol-project  # Fix it
```

### If parent repo shows "modified: gol-project (new commits)":
```bash
# You forgot Phase 2 - update parent repo
cd ..  # Go to gol/ root
git add gol-project
git commit -m "chore: update gol-project submodule (bump version to X.X.X)"
git push origin main
```

## Notes
- After modifying `project.godot`, verify the version line is correct.
- Ensure you have push permissions to both `gol-project` and `gol` repos.
- The submodule (`gol-project`) and parent repo (`gol`) are **separate git repositories** with separate remotes.
