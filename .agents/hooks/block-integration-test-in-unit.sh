#!/usr/bin/env bash
# PreToolUse hook: Block integration test suites in tests/unit/
# Exit 0 = allow, exit 2 = deny
#
# Claude Code passes stdin as JSON:
#   {"tool_name":"Write","tool_input":{"file_path":"...","content":"..."}}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

hook_require_jq

PROJECT_DIR=$(hook_project_dir)
cd "$PROJECT_DIR" 2>/dev/null || true

# Use temp file to avoid stdin/newline issues with $() subshells
TMP=$(mktemp)
cat > "$TMP"
INPUT=$(cat "$TMP")
rm -f "$TMP"

FILE_PATH=$(hook_file_path "$INPUT")
CONTENT=$(hook_json "$INPUT" '.tool_input.content // ""')

if [[ "$FILE_PATH" == *tests/unit/* ]] && echo "$CONTENT" | grep -Eq "extends (IntegrationTestSuite|AutomationPlayTestSuite)"; then
  echo "BLOCKED: IntegrationTestSuite/AutomationPlayTestSuite not allowed in tests/unit/ (use GdUnitTestSuite instead)" >&2
  exit 2
fi

if hook_patch_adds_text_in_path "$INPUT" "tests/unit/" "extends IntegrationTestSuite"; then
  echo "BLOCKED: IntegrationTestSuite not allowed in tests/unit/ (use GdUnitTestSuite instead)" >&2
  exit 2
fi

if hook_patch_adds_text_in_path "$INPUT" "tests/unit/" "extends AutomationPlayTestSuite"; then
  echo "BLOCKED: AutomationPlayTestSuite not allowed in tests/unit/ (use GdUnitTestSuite instead)" >&2
  exit 2
fi

exit 0
