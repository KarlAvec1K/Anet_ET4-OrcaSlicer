[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

Import-Module (Join-Path $PSScriptRoot 'ProfileTools.psm1') -Force

$manifest = Read-ProfileManifest -Path (Join-Path $ProjectRoot 'config\profile-manifest.json')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $ProjectRoot $manifest.package.output_file
}

$sourceResult = Test-ProfileProject -ProjectRoot $ProjectRoot
if ($sourceResult.Errors.Count -gt 0) {
    foreach ($message in $sourceResult.Errors) {
        Write-Error $message
    }
    throw "Source validation failed with $($sourceResult.Errors.Count) error(s)."
}

$archivePath = New-OrcaProfileBundle -ProjectRoot $ProjectRoot -OutputPath $OutputPath
$bundleResult = Test-OrcaProfileBundle -Path $archivePath -Manifest $manifest
if ($bundleResult.Errors.Count -gt 0) {
    foreach ($message in $bundleResult.Errors) {
        Write-Error $message
    }
    throw "Bundle validation failed with $($bundleResult.Errors.Count) error(s)."
}

$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
Write-Host "Built: $archivePath"
Write-Host "SHA256: $hash"
