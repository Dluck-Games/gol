# Run all GOL tests: gdUnit4 (unit) + SceneConfig (integration)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Join-Path $scriptDir "..\gol-project"
Set-Location $projectDir

# Godot paths (Steam version priority, also check Scoop shim)
$GodotPaths = @(
    "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.exe",
    "$env:USERPROFILE\.local\bin\godot.bat",
    "C:\Program Files\Godot\Godot.exe",
    "C:\Program Files (x86)\Godot\Godot.exe",
    "godot"
)

$GODOT = $null
foreach ($path in $GodotPaths) {
    if (Test-Path $path -ErrorAction SilentlyContinue) {
        $GODOT = $path
        break
    }
}

if (-not $GODOT) {
    Write-Error "Godot not found. Please install Godot or add it to PATH."
    pause
    exit 1
}

# Clean old reports
Remove-Item -Recurse -Force "reports" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  ┌──────────────────────────────────────────┐"
Write-Host "  │           GOL Test Runner  v1.0           │"
Write-Host "  │     Unit (gdUnit4) + Integration (Scene)   │"
Write-Host "  └──────────────────────────────────────────┘"
Write-Host ""

# ═══════════════════════════════════════════════════
# Phase 1: gdUnit4 (unit tests ONLY)
# ═══════════════════════════════════════════════════
Write-Host "▶ [1/2] gdUnit4 unit tests..."
Write-Host ""

& $GODOT --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd `
    --add res://tests/unit/ `
    --ignoreHeadlessMode `
    --verbose

$GDUNIT_EXIT = $LASTEXITCODE

# ═══════════════════════════════════════════════════
# Phase 2: SceneConfig integration tests
# ═══════════════════════════════════════════════════
Write-Host ""
Write-Host "> [2/2] SceneConfig integration tests..."
Write-Host ""

$SCENE_PASS = 0
$SCENE_FAIL = 0
$SCENE_LINES = @()

# Find all SceneConfig test files
$testFiles = Get-ChildItem -Path "tests/integration" -Filter "*.gd" -Recurse -ErrorAction SilentlyContinue | 
    Where-Object { Select-String -Path $_.FullName -Pattern "extends SceneConfig" -Quiet }

foreach ($file in $testFiles) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    Write-Host -NoNewline "  $name ... "

    $configPath = "res://tests/integration/$($file.Name)"
    & $GODOT --headless --path . "res://scenes/tests/test_main.tscn" `
        -- "--config=$configPath" 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "PASS" -ForegroundColor Green
        $SCENE_PASS++
        $SCENE_LINES += "  [PASS] $name"
    } else {
        Write-Host "FAIL" -ForegroundColor Red
        $SCENE_FAIL++
        $SCENE_LINES += "  [FAIL] $name"
    }
}

$SCENE_TOTAL = $SCENE_PASS + $SCENE_FAIL

# ═══════════════════════════════════════════════════
# Parse JUnit XML report
# ═══════════════════════════════════════════════════
$REPORT_XML = Get-ChildItem -Path "reports" -Filter "results.xml" -Recurse -ErrorAction SilentlyContinue | 
    Where-Object { $_.FullName -notmatch 'unittest-' } |
    Sort-Object Name | Select-Object -Last 1

$GD_TESTS = 0
$GD_FAIL = 0
$GD_SKIP = 0
$GD_PASS = 0
$SUITE_LINES = @()
$FAIL_LINES = @()
$TOTAL_TIME = 0.0

if ($REPORT_XML) {
    [xml]$xml = Get-Content $REPORT_XML.FullName
    
    $testsuites = $xml.testsuites
    $GD_TESTS = if ($testsuites.tests) { [int]$testsuites.tests } else { 0 }
    $GD_FAIL = if ($testsuites.failures) { [int]$testsuites.failures } else { 0 }
    $GD_SKIP = if ($testsuites.skipped) { [int]$testsuites.skipped } else { 0 }
    $GD_PASS = $GD_TESTS - $GD_FAIL - $GD_SKIP
    
    foreach ($suite in $testsuites.testsuite) {
        $s_name = $suite.name
        $s_tests = if ($suite.tests) { [int]$suite.tests } else { 0 }
        $s_fails = if ($suite.failures) { [int]$suite.failures } else { 0 }
        $s_time = if ($suite.time) { [double]$suite.time } else { 0.0 }
        $s_pass = $s_tests - $s_fails
        $t_fmt = "{0:F1}s" -f $s_time
        
        $mark = if ($s_fails -gt 0) { "<<" } else { "  " }
        $SUITE_LINES += "  {0,-38} {1,5} {2,5} {3,5} {4,7} {5}" -f 
            $s_name.Substring(0, [Math]::Min(38, $s_name.Length)), $s_tests, $s_pass, $s_fails, $t_fmt, $mark
        
        $TOTAL_TIME += $s_time
        
        # Collect failed test cases
        if ($s_fails -gt 0) {
            foreach ($tc in $suite.testcase) {
                if ($tc.failure) {
                    $FAIL_LINES += "    x $($s_name).$($tc.name)"
                }
            }
        }
    }
}

$TOTAL_TIME_FMT = "{0:F1}" -f $TOTAL_TIME

# Grand totals
$ALL_TESTS = $GD_TESTS + $SCENE_TOTAL
$ALL_PASS = $GD_PASS + $SCENE_PASS
$ALL_FAIL = $GD_FAIL + $SCENE_FAIL

# ═══════════════════════════════════════════════════
# Render ASCII Report
# ═══════════════════════════════════════════════════
$BAR = "================================================================"

Write-Host ""
Write-Host ""
Write-Host $BAR
Write-Host "                       GOL TEST REPORT"
Write-Host $BAR
Write-Host ""
Write-Host "  gdUnit4 (Unit)"
Write-Host "  ────────────────────────────"
Write-Host ""
Write-Host "  {0,-38} {1,5} {2,5} {3,5} {4,7}" -f "Suite", "Tests", "Pass", "Fail", "Time"
Write-Host "  {0,-38} {1,5} {2,5} {3,5} {4,7}" -f "──────────────────────────────────────", "─────", "─────", "─────", "───────"
$SUITE_LINES | ForEach-Object { Write-Host $_ }
Write-Host "  Subtotal: $GD_TESTS  Passed: $GD_PASS  Failed: $GD_FAIL  Skipped: $GD_SKIP"
Write-Host "  Duration: ${TOTAL_TIME_FMT}s"

if ($FAIL_LINES.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:"
    $FAIL_LINES | ForEach-Object { Write-Host $_ }
}

Write-Host ""
Write-Host "  SceneConfig Integration"
Write-Host "  ────────────────────────────"
Write-Host ""
if ($SCENE_TOTAL -gt 0) {
    $SCENE_LINES | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "  (no SceneConfig tests found)"
    Write-Host ""
}

Write-Host $BAR
Write-Host ""
Write-Host "  Total: $ALL_TESTS   Passed: $ALL_PASS   Failed: $ALL_FAIL   Skipped: $GD_SKIP"
Write-Host ""

if ($ALL_FAIL -eq 0 -and $GDUNIT_EXIT -eq 0) {
    Write-Host "  RESULT: ALL TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "  RESULT: SOME TESTS FAILED" -ForegroundColor Red
}

Write-Host ""
Write-Host $BAR

Write-Host ""
Write-Host "Press any key to close..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
