#!/usr/bin/env bash
# PreToolUse hook: Block GdUnitTestSuite in tests/integration/
# Exit 0 = allow, exit 2 = deny
#
# Claude Code passes stdin as JSON:
#   {"tool_name":"Write","tool_input":{"file_path":"...","content":"..."}}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

hook_require_jq

PROJECT_DIR=$(hook_project_dir)
cd "$PROJECT_DIR" 2>/dev/null || true

# Read stdin ONLY ONCE — stdin is single-use pipe
INPUT=$(cat)

FILE_PATH=$(hook_file_path "$INPUT")
CONTENT=$(hook_json "$INPUT" '.tool_input.content // ""')

if [[ "$FILE_PATH" == *tests/integration/* ]] && echo "$CONTENT" | grep -q "extends GdUnitTestSuite"; then
  echo "BLOCKED: GdUnitTestSuite not allowed in tests/integration/ (use SceneConfig instead)" >&2
  exit 2
fi

if hook_patch_adds_text_in_path "$INPUT" "tests/integration/" "extends GdUnitTestSuite"; then
  echo "BLOCKED: GdUnitTestSuite not allowed in tests/integration/ (use SceneConfig instead)" >&2
  exit 2
fi

exit 0
