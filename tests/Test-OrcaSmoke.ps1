$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw "Smoke assertion failed: $Message"
    }
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Find-OrcaSlicerExecutable {
    $package = Get-AppxPackage -Name OrcaSlicer.OrcaSlicer -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($null -ne $package) {
        $candidate = Join-Path $package.InstallLocation 'orca-slicer.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-Command orca-slicer.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw 'OrcaSlicer executable was not found.'
}

function Get-ExecutableLines {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines)

    return @($Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and -not $_.StartsWith(';') })
}

function ConvertTo-NativeArgument {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value.Contains('"')) {
        throw "Native argument contains an unsupported quote: $Value"
    }
    return '"' + $Value + '"'
}

function New-OrcaCliProfileCopy {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $sourceText = [IO.File]::ReadAllText($SourcePath)
    $sourceProfile = Read-ProfileJson -Path $SourcePath
    Assert-True ($sourceProfile.from -eq 'User') "Production profile remains a User preset: $([IO.Path]::GetFileName($SourcePath))"

    $userMarker = '"from": "User"'
    $markerCount = [regex]::Matches($sourceText, [regex]::Escape($userMarker)).Count
    Assert-True ($markerCount -eq 1) "Production profile has one CLI source marker: $([IO.Path]::GetFileName($SourcePath))"

    # Orca's CLI derives compatibility from system inheritance for external JSON.
    # Change only this metadata field in an isolated copy used by the smoke test.
    $cliText = $sourceText.Replace($userMarker, '"from": "system"')
    [IO.File]::WriteAllText($DestinationPath, $cliText, [Text.UTF8Encoding]::new($false))

    $cliProfile = Read-ProfileJson -Path $DestinationPath
    Assert-True ($cliProfile.from -eq 'system') "CLI copy is treated as a system preset: $([IO.Path]::GetFileName($SourcePath))"

    $restoredText = $cliText.Replace('"from": "system"', $userMarker)
    Assert-True ($restoredText -ceq $sourceText) "CLI copy changes only the source metadata: $([IO.Path]::GetFileName($SourcePath))"

    return $DestinationPath
}

function Invoke-OrcaSlice {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$DataDirectory,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [Parameter(Mandatory)][string]$PrinterPath,
        [Parameter(Mandatory)][string]$ProcessPath,
        [Parameter(Mandatory)][string]$FilamentPath,
        [Parameter(Mandatory)][string]$FixturePath,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    $arguments = @(
        '--datadir', $DataDirectory,
        '--load-settings', "$PrinterPath;$ProcessPath",
        '--load-filaments', $FilamentPath,
        '--slice', '0',
        '--outputdir', $OutputDirectory,
        $FixturePath
    )
    $argumentLine = @($arguments | ForEach-Object { ConvertTo-NativeArgument -Value ([string]$_) }) -join ' '

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.Arguments = $argumentLine
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $orcaProcess = [Diagnostics.Process]::new()
    $orcaProcess.StartInfo = $startInfo
    try {
        if (-not $orcaProcess.Start()) {
            throw 'OrcaSlicer process did not start.'
        }
        $stdoutTask = $orcaProcess.StandardOutput.ReadToEndAsync()
        $stderrTask = $orcaProcess.StandardError.ReadToEndAsync()
        if (-not $orcaProcess.WaitForExit(120000)) {
            $orcaProcess.Kill()
            throw 'OrcaSlicer smoke test exceeded 120 seconds.'
        }
        $orcaProcess.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $orcaProcess.ExitCode
            Stdout = $stdoutTask.Result
            Stderr = $stderrTask.Result
        }
    }
    finally {
        $orcaProcess.Dispose()
    }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $projectRoot 'config\profile-manifest.json'
$modulePath = Join-Path $projectRoot 'scripts\ProfileTools.psm1'
$fixturePath = Join-Path $projectRoot 'tests\fixtures\20mm-cube.stl'

Import-Module $modulePath -Force
$manifest = Read-ProfileManifest -Path $manifestPath
$bundlePath = Join-Path $projectRoot $manifest.package.output_file
Assert-True (Test-Path -LiteralPath $bundlePath -PathType Leaf) 'Import bundle exists before slicing'

$bundleResult = Test-OrcaProfileBundle -Path $bundlePath -Manifest $manifest
Assert-True ($bundleResult.Errors.Count -eq 0) 'Import bundle passes structural validation'

$vertices = @(
    Select-String -LiteralPath $fixturePath -Pattern '^\s*vertex\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*$' |
        ForEach-Object {
            [pscustomobject]@{
                X = [double]$_.Matches[0].Groups[1].Value
                Y = [double]$_.Matches[0].Groups[2].Value
                Z = [double]$_.Matches[0].Groups[3].Value
            }
        }
)
Assert-True ($vertices.Count -eq 36) 'Cube fixture contains 12 triangles'
foreach ($axis in @('X', 'Y', 'Z')) {
    $measure = $vertices | Measure-Object -Property $axis -Minimum -Maximum
    Assert-True ($measure.Minimum -eq 0 -and $measure.Maximum -eq 20) "Cube fixture spans 20 mm on $axis"
}

$orcaExecutable = Find-OrcaSlicerExecutable
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("anet-et4-orca-smoke-{0}" -f [guid]::NewGuid().ToString('N'))
$dataDirectory = Join-Path $tempRoot 'data'
$outputDirectory = Join-Path $tempRoot 'output'
$cliProfileDirectory = Join-Path $tempRoot 'profiles'
[IO.Directory]::CreateDirectory($dataDirectory) | Out-Null
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
[IO.Directory]::CreateDirectory($cliProfileDirectory) | Out-Null

try {
    $printerPath = Join-Path $projectRoot $manifest.printer.path
    $cliPrinterPath = New-OrcaCliProfileCopy -SourcePath $printerPath -DestinationPath (Join-Path $cliProfileDirectory 'printer.json')

    $cliProcessPaths = @()
    for ($index = 0; $index -lt $manifest.processes.Count; $index++) {
        $processPath = Join-Path $projectRoot $manifest.processes[$index].path
        $destination = Join-Path $cliProfileDirectory ("process-{0:D2}.json" -f $index)
        $cliProcessPaths += New-OrcaCliProfileCopy -SourcePath $processPath -DestinationPath $destination
    }

    $cliFilamentPaths = @()
    for ($index = 0; $index -lt $manifest.filaments.Count; $index++) {
        $filamentPath = Join-Path $projectRoot $manifest.filaments[$index].path
        $destination = Join-Path $cliProfileDirectory ("filament-{0:D2}.json" -f $index)
        $cliFilamentPaths += New-OrcaCliProfileCopy -SourcePath $filamentPath -DestinationPath $destination
    }

    $sliceCases = @(
        [pscustomobject]@{ Name = 'production-pla'; ProcessIndex = 1; FilamentIndex = 0; Primary = $true }
    )
    for ($index = 0; $index -lt $manifest.filaments.Count; $index++) {
        $sliceCases += [pscustomobject]@{
            Name = "material-{0:D2}" -f $index
            ProcessIndex = $index % $manifest.processes.Count
            FilamentIndex = $index
            Primary = $false
        }
    }

    $primaryGcodeFile = $null
    foreach ($case in $sliceCases) {
        $caseOutputDirectory = Join-Path $outputDirectory $case.Name
        $result = Invoke-OrcaSlice `
            -Executable $orcaExecutable `
            -DataDirectory $dataDirectory `
            -OutputDirectory $caseOutputDirectory `
            -PrinterPath $cliPrinterPath `
            -ProcessPath $cliProcessPaths[$case.ProcessIndex] `
            -FilamentPath $cliFilamentPaths[$case.FilamentIndex] `
            -FixturePath $fixturePath `
            -WorkingDirectory $tempRoot
        if ($result.ExitCode -ne 0) {
            throw "OrcaSlicer case '$($case.Name)' exited with code $($result.ExitCode).`nSTDOUT:`n$($result.Stdout)`nSTDERR:`n$($result.Stderr)"
        }

        $gcodeFiles = @(Get-ChildItem -LiteralPath $caseOutputDirectory -File -Filter '*.gcode')
        Assert-True ($gcodeFiles.Count -eq 1) "OrcaSlicer slices case '$($case.Name)'"
        if ($case.Primary) {
            $primaryGcodeFile = $gcodeFiles[0]
        }
    }
    Assert-True ($null -ne $primaryGcodeFile) 'Production PLA reference G-code exists'

    $gcodeLines = [IO.File]::ReadAllLines($primaryGcodeFile.FullName)
    $executableLines = Get-ExecutableLines -Lines $gcodeLines
    $phasePatterns = @(
        '^M190 S0$',
        '^M109 S0$',
        '^_PRINT_START_PHASE_INIT\s+',
        '^_PRINT_START_PHASE_PREHEAT$',
        '^_PRINT_START_PHASE_PROBING$',
        '^_PRINT_START_PHASE_EXTRUDER$',
        '^_PRINT_START_PHASE_PURGE$'
    )
    $lastIndex = -1
    foreach ($pattern in $phasePatterns) {
        $matches = @($executableLines | Where-Object { $_ -match $pattern })
        Assert-True ($matches.Count -eq 1) "Generated G-code contains one '$pattern' command"
        $index = [array]::IndexOf($executableLines, $matches[0])
        Assert-True ($index -gt $lastIndex) "Generated start command is ordered: $pattern"
        $lastIndex = $index
    }

    $endCommands = @($executableLines | Where-Object { $_ -eq 'PRINT_END' })
    Assert-True ($endCommands.Count -eq 1) 'Generated G-code contains one PRINT_END command'

    $gcodeText = $gcodeLines -join "`n"
    Assert-True ($gcodeText -match '(?m)^;\s*nozzle_diameter\s*=\s*0\.4(?:\D|$)') 'Generated G-code records a 0.4 mm nozzle'

    for ($lineIndex = 0; $lineIndex -lt $executableLines.Count; $lineIndex++) {
        $line = $executableLines[$lineIndex]
        if ($line -match '^M10[49]\s+S(\d+(?:\.\d+)?)') {
            $temperature = [double]$Matches[1]
            Assert-True ($temperature -le [double]$manifest.profile_limits.max_hotend_temperature) "Hotend command stays within profile limit: $line"
            if ($temperature -gt 0) {
                Assert-True ($lineIndex -gt $lastIndex) "Non-zero hotend command follows phased startup: $line"
            }
        }
        if ($line -match '^M1(?:40|90)\s+S(\d+(?:\.\d+)?)') {
            $temperature = [double]$Matches[1]
            Assert-True ($temperature -le [double]$manifest.profile_limits.max_bed_temperature) "Bed command stays within profile limit: $line"
            if ($temperature -gt 0) {
                Assert-True ($lineIndex -gt $lastIndex) "Non-zero bed command follows phased startup: $line"
            }
        }
        if ($line -match '^M204(?:\s+[SPRT]\d+(?:\.\d+)?)+') {
            foreach ($match in [regex]::Matches($line, '[SPRT](\d+(?:\.\d+)?)')) {
                Assert-True ([double]$match.Groups[1].Value -le [double]$manifest.firmware.max_acceleration) "Acceleration stays within firmware limit: $line"
            }
        }
    }

    $executableText = $executableLines -join "`n"
    Assert-True ($executableText.IndexOf('192.168.18.152', [StringComparison]::Ordinal) -lt 0) 'Executable G-code contains no Moonraker endpoint'
    Write-Host "Orca smoke reference output: $($primaryGcodeFile.FullName)"
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith('anet-et4-orca-smoke-', [StringComparison]::Ordinal)) {
        [IO.Directory]::Delete($resolvedTemp, $true)
    }
}

Write-Host 'OrcaSlicer smoke test passed.' -ForegroundColor Green
