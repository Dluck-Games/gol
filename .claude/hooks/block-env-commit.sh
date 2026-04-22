#!/usr/bin/env bash
# PreToolUse: Block .env files from being committed or written
# .env contains API keys — use .env.example for the template
# Exit 0 = allow, exit 2 = deny

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# For Write/Edit: check file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

if [[ -n "$FILE_PATH" ]]; then
  BASENAME=$(basename "$FILE_PATH")
  if [[ "$BASENAME" == ".env" ]]; then
    echo "BLOCKED: Cannot write .env files (contains secrets)." >&2
    echo "Edit .env.example instead, then copy to .env manually." >&2
    exit 2
  fi
fi

# For Bash: check if git add includes .env
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  if echo "$COMMAND" | grep -qE 'git[[:space:]]+add.*\.env([[:space:]]|$)'; then
    echo "BLOCKED: Cannot stage .env files (contains secrets)." >&2
    echo "The .env file is gitignored. Use .env.example for the template." >&2
    exit 2
  fi
fi

exit 0