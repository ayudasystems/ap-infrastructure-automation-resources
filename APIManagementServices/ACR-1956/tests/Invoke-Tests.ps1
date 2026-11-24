#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the Pester suite after checking the Pester version (>= 5). Never touches Azure.
.PARAMETER MinimumPesterVersion
    Minimum Pester version required. Default 5.0.
.PARAMETER CheckOnly
    Only run the version pre-check, then exit (0 ok, 1 too old / missing).
#>
[CmdletBinding()]
param(
    [version]$MinimumPesterVersion = '5.0',
    [switch]$CheckOnly,
    [string]$Path = $PSScriptRoot
)

$best = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $best -or $best.Version -lt $MinimumPesterVersion) {
    $found = if ($best) { $best.Version } else { 'none' }
    Write-Error "Pester >= $MinimumPesterVersion is required (found: $found). Install/update Pester and retry."
    exit 1
}
if ($CheckOnly) { Write-Host "Pester $($best.Version) OK"; exit 0 }

Import-Module Pester -MinimumVersion $MinimumPesterVersion -Force
$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0 -or $result.Result -eq 'Failed') { exit 1 }
exit 0
