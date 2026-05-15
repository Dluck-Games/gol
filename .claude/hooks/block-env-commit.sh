#!/usr/bin/env bash
# PreToolUse: Block .env files from being committed or written
# .env contains API keys — use .env.example for the template
# Exit 0 = allow, exit 2 = deny

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

INPUT=$(cat)

TOOL_NAME=$(hook_tool_name "$INPUT")

while IFS= read -r FILE_PATH; do
  [[ -z "$FILE_PATH" ]] && continue
  BASENAME=$(basename "$FILE_PATH")
  if [[ "$BASENAME" == ".env" ]]; then
    echo "BLOCKED: Cannot write .env files (contains secrets)." >&2
    echo "Edit .env.example instead, then copy to .env manually." >&2
    exit 2
  fi
done < <(hook_target_paths "$INPUT")

# For Bash: check if git add includes .env
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(hook_tool_command "$INPUT")
  if echo "$COMMAND" | grep -qE 'git[[:space:]]+add.*\.env([[:space:]]|$)'; then
    echo "BLOCKED: Cannot stage .env files (contains secrets)." >&2
    echo "The .env file is gitignored. Use .env.example for the template." >&2
    exit 2
  fi
fi

exit 0
