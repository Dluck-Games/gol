#!/usr/bin/env bash
# PreToolUse: Block .original.png files from being written to gol-project/
# These are AI concept images (1024×1024) that belong in .debug/art-workspace/
# Exit 0 = allow, exit 2 = deny

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

INPUT=$(cat)

while IFS= read -r FILE_PATH; do
  [[ -z "$FILE_PATH" ]] && continue
  if [[ "$FILE_PATH" == *gol-project/* ]] && [[ "$FILE_PATH" == *.original.png ]]; then
    echo "BLOCKED: .original.png files should not be written to gol-project/." >&2
    echo "Use .debug/art-workspace/ for AI concept images." >&2
    echo "Only commit the final production .png to gol-project/assets/." >&2
    exit 2
  fi
done < <(hook_target_paths "$INPUT")

exit 0
