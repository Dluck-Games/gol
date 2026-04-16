#!/bin/bash
# Open GOL in Godot editor
cd "$(dirname "$0")/../gol-project"
/Applications/Godot.app/Contents/MacOS/Godot --editor --path . &
disown
