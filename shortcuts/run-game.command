#!/bin/bash
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs/game"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/game-$TIMESTAMP.log"

cd "$REPO_ROOT/gol-project" || exit 1
/Applications/Godot.app/Contents/MacOS/Godot --path . 2>&1 | tee "$LOG_FILE"
