#!/bin/bash
# 运行 GOL 单元测试 + 集成测试 (gdUnit4)
cd "$(dirname "$0")/gol-project"

echo "========================================="
echo "  GOL 测试运行器 (gdUnit4)"
echo "========================================="
echo ""

/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add res://tests/ \
  --ignoreHeadlessMode \
  --verbose

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ 所有测试通过!"
else
  echo "❌ 测试失败 (exit code: $EXIT_CODE)"
fi

echo ""
echo "按回车键关闭窗口..."
read
