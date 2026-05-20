#!/usr/bin/env bash
# PreToolUse: Validate art asset placement in gol-project/assets/
# Warns (but does not block) when writing .png to non-standard directories
# Exit 0 = allow (always — this is advisory only)

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

INPUT=$(cat)

# Valid top-level asset directories
VALID_DIRS="sprites sprite_sheets tiles icons backgrounds artworks ui"

while IFS= read -r FILE_PATH; do
  [[ -z "$FILE_PATH" ]] && continue

  # Only check .png files going to gol-project/assets/
  [[ "$FILE_PATH" != *gol-project/assets/*.png ]] && continue

  # Extract the subdirectory after assets/
  SUBDIR=$(echo "$FILE_PATH" | sed -n 's|.*gol-project/assets/\([^/]*\)/.*|\1|p')

  FOUND=0
  for dir in $VALID_DIRS; do
    if [[ "$SUBDIR" == "$dir" ]]; then
      FOUND=1
      break
    fi
  done

  if [[ "$FOUND" -eq 0 ]] && [[ -n "$SUBDIR" ]]; then
    echo "WARNING: Writing .png to non-standard directory: gol-project/assets/$SUBDIR/" >&2
    echo "Standard directories: $VALID_DIRS" >&2
    echo "See docs/arts/asset-paths.md for placement guide." >&2
  fi
done < <(hook_target_paths "$INPUT")

# Always allow — this is advisory
exit 0
