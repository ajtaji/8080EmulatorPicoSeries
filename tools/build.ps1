param(
    [string]$Compiler = 'C:\Users\ajtaj\Desktop\Github\PureBasicCode\OpenGl Work\ArduinoBasic\PureMetalForge.exe',
    [string]$Source = 'src/demo.picow',
    [string]$Output = 'firmware/8080-picow.uf2',
    [string]$Port = '',
    [int]$Seconds = 12,
    [string]$Verify = '',
    [string]$LeaseOwner = '8080-core',
    [switch]$NoLease
)
# Compiles; with -Port also uploads and captures the board's serial output.
# A board shared between several workers is taken with the bench's lease
# (C:\PMFBuild\board-leases\lease.ps1) for exactly the upload and capture.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = [IO.Path]::GetFullPath((Join-Path $projectRoot $Source))
$outputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $Output))
[IO.Directory]::CreateDirectory((Split-Path $outputPath -Parent)) | Out-Null
$stdoutPath = $outputPath + '.build.log'
$stderrPath = $outputPath + '.stderr.log'

function Invoke-Forge([string]$arguments) {
    $p = Start-Process -FilePath $Compiler -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    Get-Content $stdoutPath
    Get-Content $stderrPath
    if ($p.ExitCode -ne 0) { throw "Compiler exit $($p.ExitCode): $stdoutPath" }
}

# Compile alone first: a source that does not build never takes the board.
Invoke-Forge ('--compile "' + $sourcePath + '" -S -o "' + $outputPath + '"')

# The NES ROM store starts at flash $10050000 on the shared Pico W.
$uf2 = [IO.File]::ReadAllBytes($outputPath); $imageEnd = 0
for ($o = 0; $o -lt $uf2.Length; $o += 512) {
    $blockEnd = [BitConverter]::ToUInt32($uf2, $o + 12) + [BitConverter]::ToUInt32($uf2, $o + 16)
    if ($blockEnd -gt $imageEnd) { $imageEnd = $blockEnd }
}
if ($imageEnd -gt 0x10050000) { throw ('Image reaches 0x{0:X8}, past the NES ROM store at 0x10050000; refusing to upload.' -f $imageEnd) }

if ($Port -and $NoLease) {
    # The caller (tools/board.ps1) holds the board's lease.
    Invoke-Forge ('--compile "' + $sourcePath + '" -S -o "' + $outputPath + '" --port ' + $Port + ' --seconds ' + $Seconds)
} elseif ($Port) {
    # The shared bench's one lease procedure.
    . 'C:\PMFBuild\board-leases\lease.ps1'
    $lease = Get-BoardLease -Port $Port -Owner $LeaseOwner -Minutes ([Math]::Ceiling(($Seconds + 90) / 60))
    try {
        Invoke-Forge ('--compile "' + $sourcePath + '" -S -o "' + $outputPath + '" --port ' + $Port + ' --seconds ' + $Seconds)
    } finally {
        Release-BoardLease $lease
    }
}
if ($Verify) {
    if (!$Port) { throw '-Verify requires -Port; compilation alone cannot pass verification.' }
    $transcript = Get-Content -Raw $stdoutPath
    foreach ($required in ($Verify -split '\|')) {
        if (!$transcript.Contains($required)) { throw "Missing board verdict: $required" }
    }
    if ($transcript -cmatch '\bFAIL\b') { throw "Board reported FAIL: $stdoutPath" }
    Write-Host 'Board verdicts present.'
}
Get-FileHash -Algorithm SHA256 -LiteralPath $Compiler,$sourcePath,$outputPath | Format-Table -AutoSize
