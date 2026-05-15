#!/usr/bin/env bash
# PreToolUse: Block git clone into submodule directories from parent repo
# Exit 0 = allow, exit 2 = deny (PreToolUse only)

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

INPUT=$(cat)

TOOL_NAME=$(hook_tool_name "$INPUT")
COMMAND=$(hook_tool_command "$INPUT")

[[ "$TOOL_NAME" != "Bash" ]] && exit 0

if echo "$COMMAND" | grep -qE 'git[[:space:]]+clone.*(gol-project|gol-tools)'; then
  echo "BLOCKED: Cannot git-clone into a submodule directory." >&2
  exit 2
fi

exit 0
