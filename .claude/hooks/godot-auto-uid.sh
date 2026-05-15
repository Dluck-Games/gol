#!/usr/bin/env bash
# PostToolUse hook: Auto-generate .uid files for new .gd files
# Runs after Write tool completes on .gd files
#
# Claude Code passes stdin as JSON:
#   {"tool_name":"Write","tool_input":{"file_path":"...","content":"..."}}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 0; }

PROJECT_DIR=$(hook_project_dir)
cd "$PROJECT_DIR" 2>/dev/null || true

# Read stdin ONLY ONCE — stdin is single-use pipe
INPUT=$(cat)

GD_PATH=""
while IFS= read -r FILE_PATH; do
  if [[ "$FILE_PATH" == *.gd ]]; then
    GD_PATH="$FILE_PATH"
    break
  fi
done < <(hook_added_paths "$INPUT")

[[ -z "$GD_PATH" ]] && exit 0

echo "[godot-hook] Generating UID for: $GD_PATH" >&2

GODOT_IMPORT="$PROJECT_DIR/gol-tools/ai-debug/lib/godot-import.mjs"
GOL_PROJECT="$PROJECT_DIR/gol-project"

if [[ ! -f "$GODOT_IMPORT" ]]; then
  echo "[godot-hook] WARNING: godot-import.mjs not found, skipping" >&2

  exit 0
fi

if command -v gol &>/dev/null; then
  gol reimport 2>&1 | while IFS= read -r line; do
    echo "[gol-reimport] $line" >&2
  done
else
  echo "[godot-hook] WARNING: gol CLI not found. Run 'gol install' to set up." >&2
fi
