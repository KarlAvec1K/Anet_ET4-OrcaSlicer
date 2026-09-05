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
    $processPath = Join-Path $projectRoot $manifest.processes[1].path
    $filamentPath = Join-Path $projectRoot $manifest.filaments[0].path
    $cliPrinterPath = New-OrcaCliProfileCopy -SourcePath $printerPath -DestinationPath (Join-Path $cliProfileDirectory 'printer.json')
    $cliProcessPath = New-OrcaCliProfileCopy -SourcePath $processPath -DestinationPath (Join-Path $cliProfileDirectory 'process.json')
    $cliFilamentPath = New-OrcaCliProfileCopy -SourcePath $filamentPath -DestinationPath (Join-Path $cliProfileDirectory 'filament.json')
    $stdoutPath = Join-Path $tempRoot 'orca.stdout.log'
    $stderrPath = Join-Path $tempRoot 'orca.stderr.log'
    $arguments = @(
        '--datadir', $dataDirectory,
        '--load-settings', "$cliPrinterPath;$cliProcessPath",
        '--load-filaments', $cliFilamentPath,
        '--slice', '0',
        '--outputdir', $outputDirectory,
        $fixturePath
    )

    $argumentLine = @($arguments | ForEach-Object { ConvertTo-NativeArgument -Value ([string]$_) }) -join ' '
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $orcaExecutable
    $startInfo.Arguments = $argumentLine
    $startInfo.WorkingDirectory = $tempRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $orcaProcess = [Diagnostics.Process]::new()
    $orcaProcess.StartInfo = $startInfo
    try {
        Assert-True $orcaProcess.Start() 'OrcaSlicer process starts'
        $stdoutTask = $orcaProcess.StandardOutput.ReadToEndAsync()
        $stderrTask = $orcaProcess.StandardError.ReadToEndAsync()
        if (-not $orcaProcess.WaitForExit(120000)) {
            $orcaProcess.Kill()
            throw 'OrcaSlicer smoke test exceeded 120 seconds.'
        }
        $orcaProcess.WaitForExit()
        $stdoutText = $stdoutTask.Result
        $stderrText = $stderrTask.Result
        [IO.File]::WriteAllText($stdoutPath, $stdoutText, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($stderrPath, $stderrText, [Text.UTF8Encoding]::new($false))
        $orcaExitCode = $orcaProcess.ExitCode
    }
    finally {
        $orcaProcess.Dispose()
    }
    if ($orcaExitCode -ne 0) {
        throw "OrcaSlicer exited with code $orcaExitCode.`nSTDOUT:`n$stdoutText`nSTDERR:`n$stderrText"
    }
    Assert-True $true "OrcaSlicer exits successfully (code $orcaExitCode)"

    $gcodeFiles = @(Get-ChildItem -LiteralPath $outputDirectory -File -Filter '*.gcode')
    if ($gcodeFiles.Count -ne 1) {
        $stderr = if (Test-Path -LiteralPath $stderrPath) { [IO.File]::ReadAllText($stderrPath) } else { '' }
        throw "Expected one G-code file, found $($gcodeFiles.Count). Orca stderr: $stderr"
    }

    $gcodeLines = [IO.File]::ReadAllLines($gcodeFiles[0].FullName)
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

    foreach ($line in $executableLines) {
        if ($line -match '^M10[49]\s+S(\d+(?:\.\d+)?)') {
            Assert-True ([double]$Matches[1] -le [double]$manifest.profile_limits.max_hotend_temperature) "Hotend command stays within profile limit: $line"
        }
        if ($line -match '^M1(?:40|90)\s+S(\d+(?:\.\d+)?)') {
            Assert-True ([double]$Matches[1] -le [double]$manifest.profile_limits.max_bed_temperature) "Bed command stays within profile limit: $line"
        }
        if ($line -match '^M204(?:\s+[SPRT]\d+(?:\.\d+)?)+') {
            foreach ($match in [regex]::Matches($line, '[SPRT](\d+(?:\.\d+)?)')) {
                Assert-True ([double]$match.Groups[1].Value -le [double]$manifest.firmware.max_acceleration) "Acceleration stays within firmware limit: $line"
            }
        }
    }

    $executableText = $executableLines -join "`n"
    Assert-True ($executableText.IndexOf('192.168.18.152', [StringComparison]::Ordinal) -lt 0) 'Executable G-code contains no Moonraker endpoint'
    Write-Host "Orca smoke output: $($gcodeFiles[0].FullName)"
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
