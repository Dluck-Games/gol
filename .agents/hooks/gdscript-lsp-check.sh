#!/bin/bash
# PostToolUse hook launcher for the GDScript LSP check.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Codex desktop hooks can inherit a GUI-style PATH that omits Homebrew.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

NODE_BIN="$(command -v node 2>/dev/null || true)"

if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  for candidate in /opt/homebrew/bin/node /usr/local/bin/node; do
    if [[ -x "$candidate" ]]; then
      NODE_BIN="$candidate"
      break
    fi
  done
fi

if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]] && [[ -x /bin/zsh ]]; then
  NODE_BIN="$(/bin/zsh -lc 'command -v node' 2>/dev/null || true)"
fi

if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"GDScript LSP check skipped because Node.js was not found in the hook environment. Install Node.js or make it available from /opt/homebrew/bin or /usr/local/bin."}}'
  exit 0
fi

exec "$NODE_BIN" "$SCRIPT_DIR/gdscript-lsp-check.mjs"
