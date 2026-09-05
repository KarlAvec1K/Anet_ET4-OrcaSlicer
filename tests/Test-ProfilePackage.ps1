$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:FailureCount = 0

function Write-Pass {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Write-Failure {
    param([Parameter(Mandatory)][string]$Message)

    $script:FailureCount++
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)][string]$Message
    )

    if ([object]::Equals($Expected, $Actual)) {
        Write-Pass $Message
        return
    }

    Write-Failure "$Message (expected '$Expected', got '$Actual')"
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Condition) {
        Write-Pass $Message
        return
    }

    Write-Failure $Message
}

function Assert-HasErrors {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Message
    )

    Assert-True ($Result.Errors.Count -gt 0) $Message
}

function Copy-Data {
    param([Parameter(Mandatory)]$InputObject)

    $json = $InputObject | ConvertTo-Json -Depth 100
    return ConvertFrom-ProfileJson -Json $json
}

function New-TraversalArchive {
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create)
    try {
        $archive = [IO.Compression.ZipArchive]::new(
            $stream,
            [IO.Compression.ZipArchiveMode]::Create,
            $false
        )
        try {
            $entry = $archive.CreateEntry('../outside.json')
            $writer = [IO.StreamWriter]::new($entry.Open())
            try {
                $writer.Write('{}')
            }
            finally {
                $writer.Dispose()
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $projectRoot 'scripts\ProfileTools.psm1'
$manifestPath = Join-Path $projectRoot 'config\profile-manifest.json'
$sourceArchive = Join-Path $projectRoot 'source\Anet ET4.original.orca_printer'
$expectedSourceHash = 'F06CAB65E3640F3205B555D5F4452E23E890337D49AE0546AF8D00E0F113245A'

Import-Module $modulePath -Force

$sourceHash = (Get-FileHash -LiteralPath $sourceArchive -Algorithm SHA256).Hash
Assert-Equal $expectedSourceHash $sourceHash 'Original user export is preserved byte-for-byte'

$manifest = Read-ProfileManifest -Path $manifestPath
Assert-Equal 220 ([int]$manifest.firmware.max_printable_x) 'X printable limit'
Assert-Equal 220 ([int]$manifest.firmware.max_printable_y) 'Y printable limit'
Assert-Equal 250 ([int]$manifest.firmware.max_printable_z) 'Z printable limit'
Assert-Equal 250 ([int]$manifest.firmware.max_velocity) 'Firmware velocity limit'
Assert-Equal 800 ([int]$manifest.firmware.max_acceleration) 'Firmware acceleration limit'
Assert-Equal 250 ([int]$manifest.profile_limits.max_hotend_temperature) 'Preset hotend limit'
Assert-Equal 100 ([int]$manifest.profile_limits.max_bed_temperature) 'Preset bed limit'

$result = Test-ProfileProject -ProjectRoot $projectRoot
foreach ($errorMessage in $result.Errors) {
    Write-Host "VALIDATION: $errorMessage" -ForegroundColor Red
}
Assert-Equal 0 $result.Errors.Count 'Valid source profiles'
Assert-Equal 1 $result.PrinterCount 'Printer preset count'
Assert-Equal 3 $result.ProcessCount 'Process preset count'
Assert-Equal 7 $result.FilamentCount 'Filament preset count'

$printerPath = Join-Path $projectRoot $manifest.printer.path
$printer = Read-ProfileJson -Path $printerPath
Assert-Equal 'Anet ET4 Klipper 0.4' $printer.name 'Portable printer preset name'
Assert-True (-not $printer.ContainsKey('inherits')) 'Printer has no user-profile dependency'
Assert-Equal '0' $printer.emit_machine_limits_to_gcode 'Slicer does not emit firmware limits'
Assert-Equal '0' $printer.use_firmware_retraction 'Slicer-managed retraction is enabled'
Assert-Equal '2' $printer.retraction_length[0] 'Bowden retraction length'
Assert-Equal '20' $printer.retraction_speed[0] 'Bowden retraction speed'
Assert-Equal '0.4' $printer.z_hop[0] 'Travel Z hop'

$startPhases = @(
    'M190 S0',
    'M109 S0',
    '_PRINT_START_PHASE_INIT',
    '_PRINT_START_PHASE_PREHEAT',
    '_PRINT_START_PHASE_PROBING',
    '_PRINT_START_PHASE_EXTRUDER',
    '_PRINT_START_PHASE_PURGE'
)
$lastPhaseIndex = -1
foreach ($phase in $startPhases) {
    $phaseIndex = $printer.machine_start_gcode.IndexOf($phase, $lastPhaseIndex + 1, [StringComparison]::Ordinal)
    Assert-True ($phaseIndex -gt $lastPhaseIndex) "Start G-code phase is ordered: $phase"
    $lastPhaseIndex = $phaseIndex
}
Assert-Equal 'PRINT_END' $printer.machine_end_gcode.Trim() 'End G-code delegates to PRINT_END'

$processExpectations = @{
    'ET4 0.16 Quality' = @{ layer = '0.16'; outer = '30'; inner = '45'; infill = '55'; travel = '150'; accel = '600' }
    'ET4 0.20 Production' = @{ layer = '0.2'; outer = '35'; inner = '50'; infill = '60'; travel = '160'; accel = '700' }
    'ET4 0.28 Draft' = @{ layer = '0.28'; outer = '40'; inner = '60'; infill = '70'; travel = '180'; accel = '750' }
}
foreach ($processEntry in $manifest.processes) {
    $process = Read-ProfileJson -Path (Join-Path $projectRoot $processEntry.path)
    $expected = $processExpectations[$process.name]
    Assert-True ($null -ne $expected) "Known process preset: $($process.name)"
    Assert-True (-not $process.ContainsKey('inherits')) "Process is flattened: $($process.name)"
    Assert-Equal $expected.layer $process.layer_height "Layer height: $($process.name)"
    Assert-Equal '0.24' $process.initial_layer_print_height "First layer height: $($process.name)"
    Assert-Equal '0.5' $process.initial_layer_line_width "First layer width: $($process.name)"
    Assert-Equal '20' $process.initial_layer_speed "First layer speed: $($process.name)"
    Assert-Equal $expected.outer $process.outer_wall_speed "Outer wall speed: $($process.name)"
    Assert-Equal $expected.inner $process.inner_wall_speed "Inner wall speed: $($process.name)"
    Assert-Equal $expected.infill $process.sparse_infill_speed "Infill speed: $($process.name)"
    Assert-Equal $expected.travel $process.travel_speed "Travel speed: $($process.name)"
    Assert-Equal $expected.accel $process.default_acceleration "Acceleration: $($process.name)"
    Assert-Equal '3' $process.wall_loops "Wall count: $($process.name)"
    Assert-Equal '15%' $process.sparse_infill_density "Infill density: $($process.name)"
    Assert-Equal 'gyroid' $process.sparse_infill_pattern "Infill pattern: $($process.name)"
}

$filamentExpectations = @{
    'ET4 Generic PLA' = @{ nozzle = '210'; firstNozzle = '215'; bed = '55'; firstBed = '60'; mvs = '8'; type = 'PLA' }
    'ET4 Generic PLA+' = @{ nozzle = '215'; firstNozzle = '220'; bed = '55'; firstBed = '60'; mvs = '7'; type = 'PLA' }
    'ET4 Silk PLA' = @{ nozzle = '210'; firstNozzle = '215'; bed = '55'; firstBed = '60'; mvs = '5.5'; type = 'PLA' }
    'ET4 Generic PETG' = @{ nozzle = '235'; firstNozzle = '240'; bed = '75'; firstBed = '80'; mvs = '6'; type = 'PETG' }
    'ET4 Generic TPU 95A' = @{ nozzle = '215'; firstNozzle = '220'; bed = '45'; firstBed = '50'; mvs = '2.5'; type = 'TPU' }
    'ET4 Generic ABS' = @{ nozzle = '240'; firstNozzle = '245'; bed = '95'; firstBed = '100'; mvs = '6'; type = 'ABS' }
    'ET4 Generic ASA' = @{ nozzle = '245'; firstNozzle = '250'; bed = '95'; firstBed = '100'; mvs = '5.5'; type = 'ASA' }
}
foreach ($filamentEntry in $manifest.filaments) {
    $filament = Read-ProfileJson -Path (Join-Path $projectRoot $filamentEntry.path)
    $expected = $filamentExpectations[$filament.name]
    Assert-True ($null -ne $expected) "Known filament preset: $($filament.name)"
    Assert-True (-not $filament.ContainsKey('inherits')) "Filament is flattened: $($filament.name)"
    Assert-True (([string]$filament.filament_notes).IndexOf(';') -lt 0) "Filament notes survive Orca import: $($filament.name)"
    Assert-Equal $expected.type $filament.filament_type[0] "Material type: $($filament.name)"
    Assert-Equal $expected.nozzle $filament.nozzle_temperature[0] "Nozzle temperature: $($filament.name)"
    Assert-Equal $expected.firstNozzle $filament.nozzle_temperature_initial_layer[0] "First-layer nozzle temperature: $($filament.name)"
    Assert-Equal $expected.bed $filament.hot_plate_temp[0] "Bed temperature: $($filament.name)"
    Assert-Equal $expected.firstBed $filament.hot_plate_temp_initial_layer[0] "First-layer bed temperature: $($filament.name)"
    Assert-Equal $expected.mvs $filament.filament_max_volumetric_speed[0] "Volumetric speed: $($filament.name)"
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("anet-et4-profile-tests-{0}" -f [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
try {
    $firstArchive = Join-Path $tempRoot 'first.orca_printer'
    $secondArchive = Join-Path $tempRoot 'second.orca_printer'
    New-OrcaProfileBundle -ProjectRoot $projectRoot -OutputPath $firstArchive | Out-Null
    New-OrcaProfileBundle -ProjectRoot $projectRoot -OutputPath $secondArchive | Out-Null

    $firstHash = (Get-FileHash -LiteralPath $firstArchive -Algorithm SHA256).Hash
    $secondHash = (Get-FileHash -LiteralPath $secondArchive -Algorithm SHA256).Hash
    Assert-Equal $firstHash $secondHash 'Deterministic archive output'

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($firstArchive)
    try {
        $nonStoredEntries = @($archive.Entries | Where-Object { $_.CompressedLength -ne $_.Length })
        Assert-Equal 0 $nonStoredEntries.Count 'Archive uses runtime-independent stored entries'
    }
    finally {
        $archive.Dispose()
    }

    $bundleResult = Test-OrcaProfileBundle -Path $firstArchive -Manifest $manifest
    foreach ($errorMessage in $bundleResult.Errors) {
        Write-Host "BUNDLE: $errorMessage" -ForegroundColor Red
    }
    Assert-Equal 0 $bundleResult.Errors.Count 'Built archive contract'

    $badFilament = Copy-Data (Read-ProfileJson -Path (Join-Path $projectRoot $manifest.filaments[0].path))
    $badFilament.nozzle_temperature = @('251')
    Assert-HasErrors (Test-ProfileData -Kind Filament -Profile $badFilament -Manifest $manifest) 'Reject nozzle temperature above profile limit'

    $badProcess = Copy-Data (Read-ProfileJson -Path (Join-Path $projectRoot $manifest.processes[0].path))
    $badProcess.default_acceleration = '801'
    Assert-HasErrors (Test-ProfileData -Kind Process -Profile $badProcess -Manifest $manifest) 'Reject acceleration above firmware limit'

    $badRetraction = Copy-Data $printer
    $badRetraction.use_firmware_retraction = '1'
    Assert-HasErrors (Test-ProfileData -Kind Printer -Profile $badRetraction -Manifest $manifest) 'Reject firmware retraction for production preset'

    $badStart = Copy-Data $printer
    $badStart.machine_start_gcode = 'PRINT_START EXTRUDER=210 BED=60'
    Assert-HasErrors (Test-ProfileData -Kind Printer -Profile $badStart -Manifest $manifest) 'Reject missing phased start macros'

    $badInheritance = Copy-Data $printer
    $badInheritance.inherits = 'MyKlipper 0.4 nozzle'
    Assert-HasErrors (Test-ProfileData -Kind Printer -Profile $badInheritance -Manifest $manifest) 'Reject MyKlipper dependency'

    $traversalArchive = Join-Path $tempRoot 'traversal.orca_printer'
    New-TraversalArchive -Path $traversalArchive
    Assert-HasErrors (Test-OrcaProfileBundle -Path $traversalArchive -Manifest $manifest) 'Reject path traversal ZIP entry'
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith('anet-et4-profile-tests-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:FailureCount -gt 0) {
    throw "$script:FailureCount profile package assertion(s) failed."
}

Write-Host 'All profile package tests passed.' -ForegroundColor Green
