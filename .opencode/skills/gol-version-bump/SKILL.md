# gol-version-bump

A Skill for automated version updates in Godot projects (like god-of-lego).

## Standard Operating Procedure

Before executing a version update, you must strictly adhere to the following steps:

### 1. Environment Check and Cleanup
- **Branch restriction**: Must be executed on the `main` branch. If not currently on the `main` branch, switch and pull the latest code.
- **Status cleanup**: Before updating, you must forcibly clean the workspace to ensure there are no uncommitted changes.
  ```bash
  git checkout main
  git pull origin main
  git reset --hard HEAD
  git clean -fd
  ```

### 2. Version Number Identification and Modification
- **Target file**: `project.godot`
- **Operation logic**:
  1. Read `config/version="x.x.x"` from `project.godot`.
  2. Calculate the new version number based on the update requirement (patch/minor/major).
  3. Use `sed` or file read/write tools to update that line.

### 3. Commit and Archaeological Standards
- **Commit Message**: Must strictly follow the format `chore: bump version to x.x.x`.
- **Tag format**: Must use a pure numeric version number (e.g., `0.1.5`), do not use the `v` prefix.
- **Operational history reference**: Always confirm previous formats via `git log` and `git tag`.

### 4. Push
- After completing local commit and tag, automatically push to the remote:
  ```bash
  git push origin main
  git push origin --tags
  ```

## Automated Script Example

You can use the following logic for operations:

```bash
# Assuming current version is 0.1.4 and you want to update to 0.1.5
NEW_VERSION="0.1.5"

# Modify file
sed -i '' "s/config\/version=\".*\"/config\/version=\"$NEW_VERSION\"/" project.godot

# Commit and tag
git add project.godot
git commit -m "chore: bump version to $NEW_VERSION"
git tag $NEW_VERSION

# Push
git push origin main && git push origin --tags
```

## Notes
- After modifying `project.godot`, it is recommended to briefly check file integrity.
- Ensure you have push permissions.
