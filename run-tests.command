#!/bin/bash
# Run all GOL tests: gdUnit4 (unit + integration) + SceneConfig integration
cd "$(dirname "$0")/gol-project"

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

# Clean stale reports
rm -rf reports/

echo ""
echo "  ┌──────────────────────────────────────────┐"
echo "  │           GOL Test Runner  v1.0           │"
echo "  │      Unit + Integration + SceneConfig     │"
echo "  └──────────────────────────────────────────┘"
echo ""

# ═══════════════════════════════════════════════════
# Phase 1: gdUnit4 (unit + gdUnit4 integration)
# ═══════════════════════════════════════════════════
echo "▶ [1/2] gdUnit4 tests (unit + integration)..."
echo ""

"$GODOT" --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add res://tests/ \
  --ignoreHeadlessMode \
  --verbose

GDUNIT_EXIT=$?

# ═══════════════════════════════════════════════════
# Phase 2: SceneConfig integration tests
# ═══════════════════════════════════════════════════
echo ""
echo "▶ [2/2] SceneConfig integration tests..."
echo ""

SCENE_PASS=0
SCENE_FAIL=0
SCENE_LINES=""

for config in $(grep -rl "extends SceneConfig" tests/integration/*.gd 2>/dev/null); do
  name=$(basename "$config" .gd)
  echo -n "  $name ... "

  "$GODOT" --headless --path . "res://scenes/tests/test_main.tscn" \
    -- --config="res://$config" >/dev/null 2>&1

  if [ $? -eq 0 ]; then
    echo "PASS"
    SCENE_PASS=$((SCENE_PASS + 1))
    SCENE_LINES="${SCENE_LINES}  [PASS] ${name}\n"
  else
    echo "FAIL"
    SCENE_FAIL=$((SCENE_FAIL + 1))
    SCENE_LINES="${SCENE_LINES}  [FAIL] ${name}\n"
  fi
done

SCENE_TOTAL=$((SCENE_PASS + SCENE_FAIL))

# ═══════════════════════════════════════════════════
# Parse JUnit XML report
# ═══════════════════════════════════════════════════
REPORT_XML=$(find reports -name "results.xml" -not -path "*/unittest-*" 2>/dev/null | sort -V | tail -1)

GD_TESTS=0; GD_FAIL=0; GD_SKIP=0; GD_PASS=0
SUITE_LINES=""
FAIL_LINES=""
TOTAL_TIME=0

if [ -n "$REPORT_XML" ]; then
  GD_TESTS=$(xmllint --xpath 'string(/testsuites/@tests)' "$REPORT_XML" 2>/dev/null)
  GD_FAIL=$(xmllint --xpath 'string(/testsuites/@failures)' "$REPORT_XML" 2>/dev/null)
  GD_SKIP=$(xmllint --xpath 'string(/testsuites/@skipped)' "$REPORT_XML" 2>/dev/null)
  GD_TESTS=${GD_TESTS:-0}; GD_FAIL=${GD_FAIL:-0}; GD_SKIP=${GD_SKIP:-0}
  GD_PASS=$((GD_TESTS - GD_FAIL - GD_SKIP))

  count=$(xmllint --xpath 'count(/testsuites/testsuite)' "$REPORT_XML" 2>/dev/null)
  count=${count:-0}

  for ((i=1; i<=count; i++)); do
    s_name=$(xmllint --xpath "string(/testsuites/testsuite[$i]/@name)" "$REPORT_XML" 2>/dev/null)
    s_tests=$(xmllint --xpath "string(/testsuites/testsuite[$i]/@tests)" "$REPORT_XML" 2>/dev/null)
    s_fails=$(xmllint --xpath "string(/testsuites/testsuite[$i]/@failures)" "$REPORT_XML" 2>/dev/null)
    s_time=$(xmllint --xpath "string(/testsuites/testsuite[$i]/@time)" "$REPORT_XML" 2>/dev/null)
    s_pass=$((s_tests - s_fails))
    t_fmt=$(printf "%.1fs" "$s_time" 2>/dev/null || echo "${s_time}s")

    if [ "${s_fails:-0}" -gt 0 ] 2>/dev/null; then
      mark="<<"
    else
      mark="  "
    fi
    SUITE_LINES="${SUITE_LINES}$(printf '  %-38s %5s %5s %5s %7s %s' "${s_name:0:38}" "$s_tests" "$s_pass" "$s_fails" "$t_fmt" "$mark")\n"
    TOTAL_TIME=$(echo "$TOTAL_TIME + ${s_time:-0}" | bc 2>/dev/null || echo "$TOTAL_TIME")

    # Collect individual failures
    if [ "${s_fails:-0}" -gt 0 ] 2>/dev/null; then
      tc_count=$(xmllint --xpath "count(/testsuites/testsuite[$i]/testcase)" "$REPORT_XML" 2>/dev/null)
      tc_count=${tc_count:-0}
      for ((j=1; j<=tc_count; j++)); do
        has_f=$(xmllint --xpath "count(/testsuites/testsuite[$i]/testcase[$j]/failure)" "$REPORT_XML" 2>/dev/null)
        if [ "${has_f:-0}" -gt 0 ]; then
          tc_name=$(xmllint --xpath "string(/testsuites/testsuite[$i]/testcase[$j]/@name)" "$REPORT_XML" 2>/dev/null)
          FAIL_LINES="${FAIL_LINES}    x ${s_name}.${tc_name}\n"
        fi
      done
    fi
  done
fi

TOTAL_TIME_FMT=$(printf "%.1f" "$TOTAL_TIME" 2>/dev/null || echo "0.0")

# Grand totals
ALL_TESTS=$((GD_TESTS + SCENE_TOTAL))
ALL_PASS=$((GD_PASS + SCENE_PASS))
ALL_FAIL=$((GD_FAIL + SCENE_FAIL))

# ═══════════════════════════════════════════════════
# Render ASCII Report
# ═══════════════════════════════════════════════════
BAR="================================================================"

echo ""
echo ""
echo "$BAR"
echo "                       GOL TEST REPORT"
echo "$BAR"
echo ""
echo "  gdUnit4 (Unit + Integration)"
echo "  ────────────────────────────"
echo ""
printf '  %-38s %5s %5s %5s %7s\n' "Suite" "Tests" "Pass" "Fail" "Time"
printf '  %-38s %5s %5s %5s %7s\n' "──────────────────────────────────────" "─────" "─────" "─────" "───────"
echo -e "$SUITE_LINES"
printf '  Subtotal: %-5s Passed: %-5s Failed: %-5s Skipped: %-5s\n' "$GD_TESTS" "$GD_PASS" "$GD_FAIL" "$GD_SKIP"
echo "  Duration: ${TOTAL_TIME_FMT}s"

if [ -n "$FAIL_LINES" ]; then
  echo ""
  echo "  Failures:"
  echo -e "$FAIL_LINES"
fi

echo ""
echo "  SceneConfig Integration"
echo "  ────────────────────────────"
echo ""
if [ $SCENE_TOTAL -gt 0 ]; then
  echo -e "$SCENE_LINES"
else
  echo "  (no SceneConfig tests found)"
  echo ""
fi

echo "$BAR"
echo ""
printf '  Total: %-5s  Passed: %-5s  Failed: %-5s  Skipped: %-5s\n' "$ALL_TESTS" "$ALL_PASS" "$ALL_FAIL" "$GD_SKIP"
echo ""

if [ $ALL_FAIL -eq 0 ] && [ $GDUNIT_EXIT -eq 0 ]; then
  echo "  RESULT: ALL TESTS PASSED"
else
  echo "  RESULT: SOME TESTS FAILED"
fi

echo ""
echo "$BAR"

echo ""
echo "按回车键关闭窗口..."
read
