# Run GOL game
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Join-Path $scriptDir "..\gol-project"
Set-Location $projectDir

# Find Godot
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

# Run game
& $GODOT --path .

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Godot exited with code: $LASTEXITCODE"
    pause
}
