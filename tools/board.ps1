param(
    [Parameter(Mandatory)][string]$Jobs,
    [string]$Port = 'COM7',
    [int]$Minutes = 5,
    [string]$Owner = '8080-core'
)
# Holds the shared board's lease across several uploads: each line of the
# jobs file is the arguments for tools/build.ps1 (with -Port).
$ErrorActionPreference = 'Stop'
. 'C:\PMFBuild\board-leases\lease.ps1'
$build = Join-Path $PSScriptRoot 'build.ps1'
$lines = Get-Content $Jobs | Where-Object { $_.Trim() -ne '' }
$lease = Get-BoardLease -Port $Port -Owner $Owner -Minutes $Minutes
try {
    foreach ($line in $lines) {
        Write-Host "=== JOB $line"
        Invoke-Expression "& '$build' -NoLease $line"
    }
} finally {
    Release-BoardLease $lease
}
