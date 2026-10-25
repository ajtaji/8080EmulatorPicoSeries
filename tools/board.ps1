param(
    [Parameter(Mandatory)][string]$Jobs,
    [string]$Port = 'COM7',
    [int]$Minutes = 5,
    [string]$Owner = '8080-core'
)
# Runs several uploads in a row on one board: each line of the jobs file is
# the arguments for tools/build.ps1 (with -Port). On a shared bench the
# board's lease ($env:BOARD_LEASE_SCRIPT, default
# C:\PMFBuild\board-leases\lease.ps1) is held across all of them.
$ErrorActionPreference = 'Stop'
$leaseScript = $(if ($env:BOARD_LEASE_SCRIPT) { $env:BOARD_LEASE_SCRIPT } else { 'C:\PMFBuild\board-leases\lease.ps1' })
$build = Join-Path $PSScriptRoot 'build.ps1'
$lines = Get-Content $Jobs | Where-Object { $_.Trim() -ne '' }
$lease = $null
if (Test-Path -LiteralPath $leaseScript) {
    . $leaseScript
    $lease = Get-BoardLease -Port $Port -Owner $Owner -Minutes $Minutes
}
try {
    foreach ($line in $lines) {
        Write-Host "=== JOB $line"
        Invoke-Expression "& '$build' -NoLease $line"
    }
} finally {
    if ($lease) { Release-BoardLease $lease }
}
