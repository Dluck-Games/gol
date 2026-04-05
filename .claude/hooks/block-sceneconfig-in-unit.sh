#!/usr/bin/env bash
# PreToolUse hook: Block SceneConfig in tests/unit/
# Exit 0 = allow, exit 2 = deny

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

FILE_PATH=$(jq -r '.input.file_path // empty' 2>/dev/null)
CONTENT=$(jq -r '.input.content // ""' 2>/dev/null)

if [[ "$FILE_PATH" == *tests/unit/* ]] && echo "$CONTENT" | grep -q "extends SceneConfig"; then
  exit 2
fi

exit 0
