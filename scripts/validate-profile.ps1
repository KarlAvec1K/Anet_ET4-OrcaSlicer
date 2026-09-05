[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$BundlePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

Import-Module (Join-Path $PSScriptRoot 'ProfileTools.psm1') -Force

$manifest = Read-ProfileManifest -Path (Join-Path $ProjectRoot 'config\profile-manifest.json')
if ([string]::IsNullOrWhiteSpace($BundlePath)) {
    $BundlePath = Join-Path $ProjectRoot $manifest.package.output_file
}

$failureCount = 0
$sourceResult = Test-ProfileProject -ProjectRoot $ProjectRoot
foreach ($warning in $sourceResult.Warnings) {
    Write-Warning $warning
}
foreach ($message in $sourceResult.Errors) {
    $failureCount++
    Write-Host "ERROR: $message" -ForegroundColor Red
}

if (-not (Test-Path -LiteralPath $BundlePath -PathType Leaf)) {
    $failureCount++
    Write-Host "ERROR: Bundle not found: $BundlePath" -ForegroundColor Red
}
else {
    $bundleResult = Test-OrcaProfileBundle -Path $BundlePath -Manifest $manifest
    foreach ($warning in $bundleResult.Warnings) {
        Write-Warning $warning
    }
    foreach ($message in $bundleResult.Errors) {
        $failureCount++
        Write-Host "ERROR: $message" -ForegroundColor Red
    }
}

if ($failureCount -gt 0) {
    throw "Profile validation failed with $failureCount error(s)."
}

Write-Host 'Profile sources and import bundle are valid.' -ForegroundColor Green
