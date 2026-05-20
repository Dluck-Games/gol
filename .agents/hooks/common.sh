#!/usr/bin/env bash

hook_require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq not installed" >&2
    exit 1
  }
}

hook_project_dir() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi

  if [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CODEX_PROJECT_DIR"
    return
  fi

  git rev-parse --show-toplevel 2>/dev/null || pwd
}

hook_json() {
  local input="$1"
  local filter="$2"
  jq -r "$filter" <<<"$input"
}

hook_tool_name() {
  hook_json "$1" '.tool_name // empty'
}

hook_tool_command() {
  hook_json "$1" '.tool_input.command // empty'
}

hook_file_path() {
  hook_json "$1" '.tool_input.file_path // .tool_input.filePath // empty'
}

hook_target_paths() {
  local input="$1"
  local file_path command

  file_path=$(hook_file_path "$input")
  command=$(hook_tool_command "$input")

  {
    [[ -n "$file_path" ]] && printf '%s\n' "$file_path"
    if [[ -n "$command" ]]; then
      printf '%s\n' "$command" | awk '
        /^\*\*\* (Add|Update|Delete) File: / {
          sub(/^\*\*\* (Add|Update|Delete) File: /, "")
          print
          next
        }
        /^\*\*\* Move to: / {
          sub(/^\*\*\* Move to: /, "")
          print
          next
        }
      '
    fi
  } | awk 'NF && !seen[$0]++'
}

hook_added_paths() {
  local input="$1"
  local file_path command

  file_path=$(hook_file_path "$input")
  command=$(hook_tool_command "$input")

  {
    [[ -n "$file_path" ]] && printf '%s\n' "$file_path"
    if [[ -n "$command" ]]; then
      printf '%s\n' "$command" | awk '
        /^\*\*\* Add File: / {
          sub(/^\*\*\* Add File: /, "")
          print
        }
      '
    fi
  } | awk 'NF && !seen[$0]++'
}

hook_patch_adds_text_in_path() {
  local input="$1"
  local path_fragment="$2"
  local text="$3"
  local command

  command=$(hook_tool_command "$input")
  [[ -z "$command" ]] && return 1

  printf '%s\n' "$command" | awk -v path_fragment="$path_fragment" -v text="$text" '
    /^\*\*\* (Add|Update) File: / {
      path = $0
      sub(/^\*\*\* (Add|Update) File: /, "", path)
      active = index(path, path_fragment) > 0
      next
    }
    /^\*\*\* / {
      active = 0
      next
    }
    active && /^\+/ && index(substr($0, 2), text) > 0 {
      found = 1
      exit
    }
    END {
      exit found ? 0 : 1
    }
  '
}
