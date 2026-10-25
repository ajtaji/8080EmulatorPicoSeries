param(
    # PureMetal Forge: -Compiler, else $env:PUREMETAL_FORGE, else PureMetalForge.exe on the PATH.
    [string]$Compiler = $(if ($env:PUREMETAL_FORGE) { $env:PUREMETAL_FORGE } else { 'PureMetalForge.exe' }),
    [string]$Source = 'src/demo.picow',
    [string]$Output = 'firmware/8080-picow.uf2',
    [string]$Port = '',
    [int]$Seconds = 12,
    [string]$Verify = '',
    [string]$LeaseOwner = '8080-core',
    [switch]$NoLease
)
# Compiles; with -Port also uploads and captures the board's serial output.
# On a bench where several people share boards, a lease script
# ($env:BOARD_LEASE_SCRIPT, default C:\PMFBuild\board-leases\lease.ps1) is
# used for exactly the upload and capture when it exists; without one the
# board is simply used.
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $Compiler)) {
    $found = Get-Command $Compiler -ErrorAction SilentlyContinue
    if (!$found) { throw "PureMetal Forge not found ('$Compiler'): pass -Compiler or set PUREMETAL_FORGE." }
    $Compiler = $found.Source
}
$leaseScript = $(if ($env:BOARD_LEASE_SCRIPT) { $env:BOARD_LEASE_SCRIPT } else { 'C:\PMFBuild\board-leases\lease.ps1' })
$projectRoot = Split-Path $PSScriptRoot -Parent
# Relative paths are from the repository; absolute ones (a private wrapper
# outside git, and its image) are taken as they are.
if ([IO.Path]::IsPathRooted($Source)) { $sourcePath = $Source } else { $sourcePath = [IO.Path]::GetFullPath((Join-Path $projectRoot $Source)) }
if ([IO.Path]::IsPathRooted($Output)) { $outputPath = $Output } else { $outputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $Output)) }
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

# Keep the image below flash $10050000: the bench's boards keep other data
# (an NES ROM store) from there up, and these images need far less.
$uf2 = [IO.File]::ReadAllBytes($outputPath); $imageEnd = 0
for ($o = 0; $o -lt $uf2.Length; $o += 512) {
    $blockEnd = [BitConverter]::ToUInt32($uf2, $o + 12) + [BitConverter]::ToUInt32($uf2, $o + 16)
    if ($blockEnd -gt $imageEnd) { $imageEnd = $blockEnd }
}
if ($imageEnd -gt 0x10050000) { throw ('Image reaches 0x{0:X8}, past the NES ROM store at 0x10050000; refusing to upload.' -f $imageEnd) }

if ($Port -and ($NoLease -or !(Test-Path -LiteralPath $leaseScript))) {
    # The caller (tools/board.ps1) holds the board's lease, or there is no lease to take.
    Invoke-Forge ('--compile "' + $sourcePath + '" -S -o "' + $outputPath + '" --port ' + $Port + ' --seconds ' + $Seconds)
} elseif ($Port) {
    # The shared bench's one lease procedure.
    . $leaseScript
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
