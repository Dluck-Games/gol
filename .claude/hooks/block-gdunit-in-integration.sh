#!/usr/bin/env bash
# PreToolUse hook: Block GdUnitTestSuite in tests/integration/
# Exit 0 = allow, exit 2 = deny
#
# Claude Code passes stdin as JSON:
#   {"tool_name":"Write","tool_input":{"file_path":"...","content":"..."}}

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

FILE_PATH=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
CONTENT=$(jq -r '.tool_input.content // ""' 2>/dev/null)

if [[ "$FILE_PATH" == *tests/integration/* ]] && echo "$CONTENT" | grep -q "extends GdUnitTestSuite"; then
  echo "BLOCKED: GdUnitTestSuite not allowed in tests/integration/ (use SceneConfig instead)" >&2
  exit 2
fi

exit 0
