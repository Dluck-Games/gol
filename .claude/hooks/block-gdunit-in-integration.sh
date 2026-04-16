#!/usr/bin/env bash
# PreToolUse hook: Block GdUnitTestSuite in tests/integration/
# Exit 0 = allow, exit 2 = deny
#
# Claude Code passes stdin as JSON:
#   {"tool_name":"Write","tool_input":{"file_path":"...","content":"..."}}

# Ensure we're in the project root (CWD may differ in some runtimes)
[[ -n "$CLAUDE_PROJECT_DIR" ]] && cd "$CLAUDE_PROJECT_DIR" 2>/dev/null

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

# Read stdin ONLY ONCE — stdin is single-use pipe
INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""')

if [[ "$FILE_PATH" == *tests/integration/* ]] && echo "$CONTENT" | grep -q "extends GdUnitTestSuite"; then
  echo "BLOCKED: GdUnitTestSuite not allowed in tests/integration/ (use SceneConfig instead)" >&2
  exit 2
fi

exit 0
