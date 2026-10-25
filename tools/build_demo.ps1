param(
    # PureMetal Forge: -Compiler, else $env:PUREMETAL_FORGE, else PureMetalForge.exe on the PATH.
    [string]$Compiler = $(if ($env:PUREMETAL_FORGE) { $env:PUREMETAL_FORGE } else { 'PureMetalForge.exe' }),
    [int]$Frames = 1200
)
# Builds demo\demo.invaders for the Space Invaders board (the compiler writes
# demo\demo_roms\invaders.h/g/f/e) and runs it headless for $Frames frames
# with desktop\invaders_cli.exe, printing the counts and the frames it missed.
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $Compiler)) {
    $found = Get-Command $Compiler -ErrorAction SilentlyContinue
    if (!$found) { throw "PureMetal Forge not found ('$Compiler'): pass -Compiler or set PUREMETAL_FORGE." }
    $Compiler = $found.Source
}
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root 'demo\demo.invaders'
$hex = Join-Path $root 'demo\demo.hex'
$p = Start-Process -FilePath $Compiler -ArgumentList ('--compile "' + $src + '" -o "' + $hex + '"') -WindowStyle Hidden -Wait -PassThru `
    -RedirectStandardOutput "$hex.build.log" -RedirectStandardError "$hex.stderr.log"
Get-Content "$hex.build.log" | Select-String -Pattern 'ERROR|rror|too big|PM[0-9]{4}' | ForEach-Object Line
if ($p.ExitCode -ne 0) { throw "Compiler exit $($p.ExitCode): $hex.build.log" }
$roms = Join-Path $root 'demo\demo_roms'
$size = (Get-ChildItem $roms -File | Measure-Object Length -Sum).Sum
Write-Host "demo_roms: $size bytes"
& (Join-Path $root 'desktop\invaders_cli.exe') $roms $Frames --png (Join-Path $root 'demo\demo-screen.png')
