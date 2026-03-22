#!/bin/bash
# 在 Godot 编辑器中打开 GOL 项目
cd "$(dirname "$0")/gol-project"
/Applications/Godot.app/Contents/MacOS/Godot --editor --path . &
disown
