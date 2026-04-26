#!/usr/bin/env bash
# PostToolUse hook: Auto-generate .uid files for new .gd files
# Runs after Write tool completes on .gd files
#
# Claude Code passes stdin as JSON:
#   {"tool_name":"Write","tool_input":{"file_path":"...","content":"..."}}

[[ -n "$CLAUDE_PROJECT_DIR" ]] && cd "$CLAUDE_PROJECT_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 0; }

# Read stdin ONLY ONCE — stdin is single-use pipe
INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only process .gd files
if [[ "$FILE_PATH" != *.gd ]]; then
  exit 0
fi

echo "[godot-hook] Generating UID for: $FILE_PATH" >&2

GODOT_IMPORT="$CLAUDE_PROJECT_DIR/gol-tools/ai-debug/lib/godot-import.mjs"
GOL_PROJECT="$CLAUDE_PROJECT_DIR/gol-project"

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
