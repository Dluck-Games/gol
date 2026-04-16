#!/usr/bin/env bash
# PreToolUse hook: Block SceneConfig in tests/unit/
# Exit 0 = allow, exit 2 = deny
#
# Claude Code passes stdin as JSON:
#   {"tool_name":"Write","tool_input":{"file_path":"...","content":"..."}}

[[ -n "$CLAUDE_PROJECT_DIR" ]] && cd "$CLAUDE_PROJECT_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

# Use temp file to avoid stdin/newline issues with $() subshells
TMP=$(mktemp)
cat > "$TMP"
FILE_PATH=$(jq -r '.tool_input.file_path // empty' < "$TMP")
CONTENT=$(jq -r '.tool_input.content // ""' < "$TMP")
rm -f "$TMP"

if [[ "$FILE_PATH" == *tests/unit/* ]] && echo "$CONTENT" | grep -q "extends SceneConfig"; then
  echo "BLOCKED: SceneConfig not allowed in tests/unit/ (use GdUnitTestSuite instead)" >&2
  exit 2
fi

exit 0
