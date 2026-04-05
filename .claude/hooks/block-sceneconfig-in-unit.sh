#!/usr/bin/env bash
# PreToolUse hook: Block SceneConfig in tests/unit/
# Exit 0 = allow, exit 2 = deny
#
# Claude Code passes stdin as JSON:
#   {"tool_name":"Write","tool_input":{"file_path":"...","content":"..."}}

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

FILE_PATH=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
CONTENT=$(jq -r '.tool_input.content // ""' 2>/dev/null)

if [[ "$FILE_PATH" == *tests/unit/* ]] && echo "$CONTENT" | grep -q "extends SceneConfig"; then
  echo "BLOCKED: SceneConfig not allowed in tests/unit/ (use GdUnitTestSuite instead)" >&2
  exit 2
fi

exit 0
