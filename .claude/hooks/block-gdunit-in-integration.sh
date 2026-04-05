#!/usr/bin/env bash
# PreToolUse hook: Block GdUnitTestSuite in tests/integration/
# Exit 0 = allow, exit 2 = deny

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

# Read tool input from stdin (JSON with .input.file_path and .input.content)
# For Write/Edit tools, check if content would add GdUnitTestSuite to integration dir

# Parse the file path and content from the hook input
# Claude Code passes hook stdin as JSON: {"tool_name":"Write","input":{"file_path":"...","content":"..."}}

FILE_PATH=$(jq -r '.input.file_path // empty' 2>/dev/null)
CONTENT=$(jq -r '.input.content // ""' 2>/dev/null)

if [[ "$FILE_PATH" == *tests/integration/* ]] && echo "$CONTENT" | grep -q "extends GdUnitTestSuite"; then
  exit 2
fi

exit 0
