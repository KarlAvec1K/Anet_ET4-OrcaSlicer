Set-StrictMode -Version Latest

function ConvertTo-ProfileHashtable {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $map = @{}
        foreach ($key in $Value.Keys) {
            $map[[string]$key] = ConvertTo-ProfileHashtable $Value[$key]
        }
        return $map
    }

    if ($Value -is [pscustomobject]) {
        $map = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $map[$property.Name] = ConvertTo-ProfileHashtable $property.Value
        }
        return $map
    }

    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(ConvertTo-ProfileHashtable $item)
        }
        return ,$items
    }

    return $Value
}

function ConvertFrom-ProfileJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Json)

    $convertCommand = Get-Command ConvertFrom-Json
    if ($convertCommand.Parameters.ContainsKey('AsHashtable')) {
        return ConvertFrom-Json -InputObject $Json -AsHashtable
    }

    $value = ConvertFrom-Json -InputObject $Json
    return ConvertTo-ProfileHashtable $value
}

function Read-ProfileJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    $json = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, [Text.Encoding]::UTF8)
    $value = ConvertFrom-ProfileJson -Json $json
    if (-not ($value -is [System.Collections.IDictionary])) {
        throw "JSON root must be an object: $Path"
    }

    return $value
}

function Read-ProfileManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $manifest = Read-ProfileJson -Path $Path
    foreach ($key in @('package', 'orca', 'firmware', 'profile_limits', 'connection', 'printer', 'processes', 'filaments')) {
        if (-not $manifest.Contains($key)) {
            throw "Manifest is missing '$key': $Path"
        }
    }

    return $manifest
}

function Get-ProfileValues {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Profile.Contains($Name)) {
        return @()
    }

    $value = $Profile[$Name]
    if (($value -is [System.Collections.IEnumerable]) -and -not ($value -is [string])) {
        return @($value)
    }

    return @($value)
}

function ConvertTo-InvariantDouble {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    $text = ([string]$Value).Trim()
    if ($text.EndsWith('%', [StringComparison]::Ordinal)) {
        $text = $text.Substring(0, $text.Length - 1)
    }

    $number = 0.0
    $parsed = [double]::TryParse(
        $text,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )
    if (-not $parsed) {
        return $null
    }

    return $number
}

function Add-MissingKeyError {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][Collections.Generic.List[string]]$Errors
    )

    if (-not $Profile.Contains($Name)) {
        $Errors.Add("Missing required setting '$Name'.")
        return $true
    }

    return $false
}

function Test-NumericLimit {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][double]$Maximum,
        [Parameter(Mandatory)][Collections.Generic.List[string]]$Errors,
        [double]$Minimum = 0
    )

    if (Add-MissingKeyError -Profile $Profile -Name $Name -Errors $Errors) {
        return
    }

    foreach ($value in (Get-ProfileValues -Profile $Profile -Name $Name)) {
        $number = ConvertTo-InvariantDouble $value
        if ($null -eq $number) {
            $Errors.Add("Setting '$Name' is not numeric: '$value'.")
            continue
        }
        if ($number -lt $Minimum -or $number -gt $Maximum) {
            $Errors.Add("Setting '$Name' value '$value' is outside $Minimum..$Maximum.")
        }
    }
}

function Test-CompatiblePrinter {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest,
        [Parameter(Mandatory)][Collections.Generic.List[string]]$Errors
    )

    if (Add-MissingKeyError -Profile $Profile -Name 'compatible_printers' -Errors $Errors) {
        return
    }

    $compatible = @(Get-ProfileValues -Profile $Profile -Name 'compatible_printers')
    if ($compatible.Count -ne 1 -or [string]$compatible[0] -ne [string]$Manifest.printer.name) {
        $Errors.Add("Profile must target only '$($Manifest.printer.name)'.")
    }
}

function Test-ProfileData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Printer', 'Process', 'Filament')][string]$Kind,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Profile,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest
    )

    $errors = [Collections.Generic.List[string]]::new()
    $warnings = [Collections.Generic.List[string]]::new()
    $typeByKind = @{ Printer = 'machine'; Process = 'process'; Filament = 'filament' }

    foreach ($key in @('type', 'name', 'from', 'instantiation', 'version')) {
        Add-MissingKeyError -Profile $Profile -Name $key -Errors $errors | Out-Null
    }

    if ($Profile.Contains('type') -and [string]$Profile.type -ne $typeByKind[$Kind]) {
        $errors.Add("Profile type '$($Profile.type)' does not match $Kind.")
    }
    if ($Profile.Contains('from') -and [string]$Profile.from -ne 'User') {
        $errors.Add("Profile '$($Profile.name)' must use from='User'.")
    }
    if ($Profile.Contains('instantiation') -and [string]$Profile.instantiation -ne 'true') {
        $errors.Add("Profile '$($Profile.name)' must be instantiable.")
    }
    if ($Profile.Contains('version') -and [string]$Profile.version -ne [string]$Manifest.orca.profile_version) {
        $errors.Add("Profile '$($Profile.name)' has unsupported version '$($Profile.version)'.")
    }
    if ($Profile.Contains('inherits') -and -not [string]::IsNullOrWhiteSpace([string]$Profile.inherits)) {
        $errors.Add("Profile '$($Profile.name)' must be flattened and cannot inherit '$($Profile.inherits)'.")
    }

    $serialized = $Profile | ConvertTo-Json -Depth 100 -Compress
    if ($serialized.IndexOf('MyKlipper', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $errors.Add("Profile '$($Profile.name)' depends on MyKlipper.")
    }

    if ($Kind -eq 'Printer') {
        if ($Profile.Contains('name') -and [string]$Profile.name -ne [string]$Manifest.printer.name) {
            $errors.Add("Unexpected printer name '$($Profile.name)'.")
        }
        if ($Profile.Contains('gcode_flavor') -and [string]$Profile.gcode_flavor -ne 'klipper') {
            $errors.Add('Printer G-code flavor must be klipper.')
        }
        if ($Profile.Contains('host_type') -and [string]$Profile.host_type -ne [string]$Manifest.connection.host_type) {
            $errors.Add('Printer host type must be moonraker.')
        }
        if ($Profile.Contains('print_host') -and [string]$Profile.print_host -ne [string]$Manifest.connection.url) {
            $errors.Add("Printer host must be '$($Manifest.connection.url)'.")
        }

        foreach ($key in @('gcode_flavor', 'host_type', 'print_host', 'printable_area', 'printable_height', 'nozzle_diameter', 'emit_machine_limits_to_gcode', 'use_firmware_retraction', 'machine_start_gcode', 'machine_end_gcode')) {
            Add-MissingKeyError -Profile $Profile -Name $key -Errors $errors | Out-Null
        }

        if ($Profile.Contains('printable_area')) {
            $expectedArea = '0x0|220x0|220x220|0x220'
            $actualArea = (@(Get-ProfileValues -Profile $Profile -Name 'printable_area') -join '|')
            if ($actualArea -ne $expectedArea) {
                $errors.Add("Printable area must be '$expectedArea'.")
            }
        }
        if ($Profile.Contains('printable_height') -and [double]$Profile.printable_height -ne [double]$Manifest.firmware.max_printable_z) {
            $errors.Add('Printable height does not match firmware.')
        }
        if ($Profile.Contains('nozzle_diameter') -and [string](Get-ProfileValues -Profile $Profile -Name 'nozzle_diameter')[0] -ne '0.4') {
            $errors.Add('Printer profile must use a 0.4 mm nozzle.')
        }
        if ($Profile.Contains('emit_machine_limits_to_gcode') -and [string]$Profile.emit_machine_limits_to_gcode -ne '0') {
            $errors.Add('Machine-limit G-code emission must stay disabled.')
        }
        if ($Profile.Contains('use_firmware_retraction') -and [string]$Profile.use_firmware_retraction -ne '0') {
            $errors.Add('Firmware retraction must stay disabled for this profile.')
        }
        if ($Profile.Contains('use_relative_e_distances') -and [string]$Profile.use_relative_e_distances -ne '1') {
            $errors.Add('Relative extrusion must stay enabled.')
        }

        foreach ($key in @('machine_max_speed_x', 'machine_max_speed_y', 'machine_max_speed_e')) {
            Test-NumericLimit -Profile $Profile -Name $key -Maximum ([double]$Manifest.firmware.max_velocity) -Errors $errors
        }
        Test-NumericLimit -Profile $Profile -Name 'machine_max_speed_z' -Maximum ([double]$Manifest.firmware.max_z_velocity) -Errors $errors
        foreach ($key in @('machine_max_acceleration_x', 'machine_max_acceleration_y', 'machine_max_acceleration_e', 'machine_max_acceleration_extruding', 'machine_max_acceleration_retracting', 'machine_max_acceleration_travel')) {
            Test-NumericLimit -Profile $Profile -Name $key -Maximum ([double]$Manifest.firmware.max_acceleration) -Errors $errors
        }
        Test-NumericLimit -Profile $Profile -Name 'machine_max_acceleration_z' -Maximum ([double]$Manifest.firmware.max_z_acceleration) -Errors $errors

        if ($Profile.Contains('machine_start_gcode')) {
            $startGcode = [string]$Profile.machine_start_gcode
            $phases = @(
                'M190 S0',
                'M109 S0',
                '_PRINT_START_PHASE_INIT',
                '_PRINT_START_PHASE_PREHEAT',
                '_PRINT_START_PHASE_PROBING',
                '_PRINT_START_PHASE_EXTRUDER',
                '_PRINT_START_PHASE_PURGE'
            )
            $lastIndex = -1
            foreach ($phase in $phases) {
                $index = $startGcode.IndexOf($phase, $lastIndex + 1, [StringComparison]::Ordinal)
                if ($index -lt 0) {
                    $errors.Add("Start G-code is missing or misorders '$phase'.")
                }
                else {
                    $lastIndex = $index
                }
            }
            foreach ($token in @('EXTRUDER={first_layer_temperature[initial_tool]}', 'BED=[first_layer_bed_temperature]', 'MESH_MIN={first_layer_print_min[0]},{first_layer_print_min[1]}', 'MESH_MAX={first_layer_print_max[0]},{first_layer_print_max[1]}', 'LAYERS={total_layer_count}', 'NOZZLE_SIZE={nozzle_diameter[0]}')) {
                if ($startGcode.IndexOf($token, [StringComparison]::Ordinal) -lt 0) {
                    $errors.Add("Start G-code is missing '$token'.")
                }
            }
        }
        if ($Profile.Contains('machine_end_gcode') -and [string]$Profile.machine_end_gcode.Trim() -ne 'PRINT_END') {
            $errors.Add('Machine end G-code must contain only PRINT_END.')
        }
    }

    if ($Kind -eq 'Process') {
        Test-CompatiblePrinter -Profile $Profile -Manifest $Manifest -Errors $errors
        foreach ($key in @('outer_wall_speed', 'inner_wall_speed', 'sparse_infill_speed', 'internal_solid_infill_speed', 'top_surface_speed', 'gap_infill_speed', 'bridge_speed', 'support_speed', 'support_interface_speed', 'travel_speed', 'initial_layer_speed', 'initial_layer_infill_speed')) {
            Test-NumericLimit -Profile $Profile -Name $key -Maximum ([double]$Manifest.firmware.max_velocity) -Errors $errors
        }
        foreach ($key in @('default_acceleration', 'initial_layer_acceleration', 'top_surface_acceleration', 'travel_acceleration', 'inner_wall_acceleration', 'outer_wall_acceleration')) {
            Test-NumericLimit -Profile $Profile -Name $key -Maximum ([double]$Manifest.firmware.max_acceleration) -Errors $errors
        }
        foreach ($key in @('layer_height', 'initial_layer_print_height', 'initial_layer_line_width', 'wall_loops', 'sparse_infill_density', 'sparse_infill_pattern')) {
            Add-MissingKeyError -Profile $Profile -Name $key -Errors $errors | Out-Null
        }
    }

    if ($Kind -eq 'Filament') {
        Test-CompatiblePrinter -Profile $Profile -Manifest $Manifest -Errors $errors
        foreach ($key in @('nozzle_temperature', 'nozzle_temperature_initial_layer', 'nozzle_temperature_range_high')) {
            Test-NumericLimit -Profile $Profile -Name $key -Maximum ([double]$Manifest.profile_limits.max_hotend_temperature) -Errors $errors
        }
        foreach ($key in @('cool_plate_temp', 'cool_plate_temp_initial_layer', 'eng_plate_temp', 'eng_plate_temp_initial_layer', 'hot_plate_temp', 'hot_plate_temp_initial_layer', 'textured_plate_temp', 'textured_plate_temp_initial_layer', 'supertack_plate_temp', 'supertack_plate_temp_initial_layer')) {
            Test-NumericLimit -Profile $Profile -Name $key -Maximum ([double]$Manifest.profile_limits.max_bed_temperature) -Errors $errors
        }
        Test-NumericLimit -Profile $Profile -Name 'filament_max_volumetric_speed' -Maximum 30 -Minimum 0.1 -Errors $errors
        foreach ($key in @('filament_type', 'filament_diameter', 'filament_flow_ratio', 'fan_min_speed', 'fan_max_speed', 'close_fan_the_first_x_layers')) {
            Add-MissingKeyError -Profile $Profile -Name $key -Errors $errors | Out-Null
        }

        if ($Profile.Contains('filament_type')) {
            $materialType = [string](Get-ProfileValues -Profile $Profile -Name 'filament_type')[0]
            if ($materialType -in @('ABS', 'ASA')) {
                if (-not $Profile.Contains('filament_notes') -or
                    ([string]$Profile.filament_notes).IndexOf('enclosure', [StringComparison]::OrdinalIgnoreCase) -lt 0 -or
                    ([string]$Profile.filament_notes).IndexOf('ventilation', [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    $errors.Add("$materialType profile must document enclosure and room ventilation.")
                }
            }
            if ($materialType -eq 'TPU') {
                if (-not $Profile.Contains('filament_retraction_length') -or [string](Get-ProfileValues -Profile $Profile -Name 'filament_retraction_length')[0] -ne '1') {
                    $errors.Add('TPU retraction length must be 1 mm.')
                }
                if (-not $Profile.Contains('filament_retraction_speed') -or [string](Get-ProfileValues -Profile $Profile -Name 'filament_retraction_speed')[0] -ne '15') {
                    $errors.Add('TPU retraction speed must be 15 mm/s.')
                }
            }
        }
    }

    return [pscustomobject]@{
        Errors = @($errors)
        Warnings = @($warnings)
    }
}

function Resolve-ProfileProjectPath {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $nativeRelativePath = $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    return [IO.Path]::GetFullPath((Join-Path $ProjectRoot $nativeRelativePath))
}

function Test-ProfileProject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $errors = [Collections.Generic.List[string]]::new()
    $warnings = [Collections.Generic.List[string]]::new()
    $printerCount = 0
    $processCount = 0
    $filamentCount = 0
    $manifestPath = Join-Path $ProjectRoot 'config\profile-manifest.json'

    try {
        $manifest = Read-ProfileManifest -Path $manifestPath
    }
    catch {
        $errors.Add($_.Exception.Message)
        return [pscustomobject]@{ Errors = @($errors); Warnings = @($warnings); PrinterCount = 0; ProcessCount = 0; FilamentCount = 0 }
    }

    $entries = @(
        [pscustomobject]@{ Kind = 'Printer'; Name = $manifest.printer.name; Path = $manifest.printer.path }
    )
    foreach ($entry in $manifest.processes) {
        $entries += [pscustomobject]@{ Kind = 'Process'; Name = $entry.name; Path = $entry.path }
    }
    foreach ($entry in $manifest.filaments) {
        $entries += [pscustomobject]@{ Kind = 'Filament'; Name = $entry.name; Path = $entry.path }
    }

    $seenNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $expectedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) {
        if (-not $seenNames.Add([string]$entry.Name)) {
            $errors.Add("Duplicate preset name '$($entry.Name)'.")
        }

        $profilePath = Resolve-ProfileProjectPath -ProjectRoot $ProjectRoot -RelativePath ([string]$entry.Path)
        $expectedPaths.Add($profilePath) | Out-Null
        if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
            $errors.Add("Missing $($entry.Kind.ToLowerInvariant()) profile: $($entry.Path)")
            continue
        }

        try {
            $profile = Read-ProfileJson -Path $profilePath
            if (-not $profile.Contains('name') -or [string]$profile.name -ne [string]$entry.Name) {
                $errors.Add("Manifest name '$($entry.Name)' does not match '$($profile.name)'.")
            }
            $profileResult = Test-ProfileData -Kind $entry.Kind -Profile $profile -Manifest $manifest
            foreach ($message in $profileResult.Errors) {
                $errors.Add("$($entry.Name): $message")
            }
            foreach ($message in $profileResult.Warnings) {
                $warnings.Add("$($entry.Name): $message")
            }
            switch ($entry.Kind) {
                'Printer' { $printerCount++ }
                'Process' { $processCount++ }
                'Filament' { $filamentCount++ }
            }
        }
        catch {
            $errors.Add("Cannot read '$($entry.Path)': $($_.Exception.Message)")
        }
    }

    $profilesRoot = Join-Path $ProjectRoot 'profiles'
    if (Test-Path -LiteralPath $profilesRoot -PathType Container) {
        foreach ($file in (Get-ChildItem -LiteralPath $profilesRoot -Recurse -File -Filter '*.json')) {
            if (-not $expectedPaths.Contains($file.FullName)) {
                $errors.Add("Unlisted profile file: $($file.FullName)")
            }
        }
    }

    return [pscustomobject]@{
        Errors = @($errors)
        Warnings = @($warnings)
        PrinterCount = $printerCount
        ProcessCount = $processCount
        FilamentCount = $filamentCount
    }
}

function Get-BundleEntryName {
    param(
        [Parameter(Mandatory)][ValidateSet('printer', 'process', 'filament')][string]$Kind,
        [Parameter(Mandatory)][string]$ProfilePath
    )

    return "$Kind/$([IO.Path]::GetFileName($ProfilePath))"
}

function Get-NormalizedJsonText {
    param([Parameter(Mandatory)][string]$Path)

    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd()
    return "$text`n"
}

function New-OrcaProfileBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $projectResult = Test-ProfileProject -ProjectRoot $ProjectRoot
    if ($projectResult.Errors.Count -gt 0) {
        throw "Cannot build invalid profile project: $($projectResult.Errors -join ' | ')"
    }

    $manifest = Read-ProfileManifest -Path (Join-Path $ProjectRoot 'config\profile-manifest.json')
    $printerEntry = Get-BundleEntryName -Kind printer -ProfilePath ([string]$manifest.printer.path)
    $processEntries = @($manifest.processes | ForEach-Object { Get-BundleEntryName -Kind process -ProfilePath ([string]$_.path) })
    $filamentEntries = @($manifest.filaments | ForEach-Object { Get-BundleEntryName -Kind filament -ProfilePath ([string]$_.path) })

    [array]::Sort($processEntries, [StringComparer]::Ordinal)
    [array]::Sort($filamentEntries, [StringComparer]::Ordinal)

    $bundleManifest = [ordered]@{
        bundle_id = [string]$manifest.package.bundle_id
        bundle_type = 'printer config bundle'
        filament_config = @($filamentEntries)
        printer_config = @($printerEntry)
        printer_preset_name = [string]$manifest.printer.name
        process_config = @($processEntries)
        version = [string]$manifest.package.bundle_version
    }

    $contents = @{}
    $bundleJson = $bundleManifest | ConvertTo-Json -Depth 20
    $contents['bundle_structure.json'] = $bundleJson.Replace("`r`n", "`n").TrimEnd() + "`n"
    $contents[$printerEntry] = Get-NormalizedJsonText -Path (Resolve-ProfileProjectPath -ProjectRoot $ProjectRoot -RelativePath ([string]$manifest.printer.path))
    foreach ($entry in $manifest.processes) {
        $entryName = Get-BundleEntryName -Kind process -ProfilePath ([string]$entry.path)
        $contents[$entryName] = Get-NormalizedJsonText -Path (Resolve-ProfileProjectPath -ProjectRoot $ProjectRoot -RelativePath ([string]$entry.path))
    }
    foreach ($entry in $manifest.filaments) {
        $entryName = Get-BundleEntryName -Kind filament -ProfilePath ([string]$entry.path)
        $contents[$entryName] = Get-NormalizedJsonText -Path (Resolve-ProfileProjectPath -ProjectRoot $ProjectRoot -RelativePath ([string]$entry.path))
    }

    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $resolvedOutput)) | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $fileStream = [IO.File]::Open($resolvedOutput, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($fileStream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $entryNames = @($contents.Keys)
            [array]::Sort($entryNames, [StringComparer]::Ordinal)
            $fixedTimestamp = [DateTimeOffset]::new(2026, 9, 5, 0, 0, 0, [TimeSpan]::Zero)
            $utf8NoBom = [Text.UTF8Encoding]::new($false)
            foreach ($entryName in $entryNames) {
                $zipEntry = $archive.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
                $zipEntry.LastWriteTime = $fixedTimestamp
                $writer = [IO.StreamWriter]::new($zipEntry.Open(), $utf8NoBom)
                try {
                    $writer.Write([string]$contents[$entryName])
                }
                finally {
                    $writer.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $fileStream.Dispose()
    }

    return $resolvedOutput
}

function Compare-StringArray {
    param(
        [Parameter(Mandatory)][object[]]$Expected,
        [Parameter(Mandatory)][object[]]$Actual
    )

    if ($Expected.Count -ne $Actual.Count) {
        return $false
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ([string]$Expected[$index] -cne [string]$Actual[$index]) {
            return $false
        }
    }
    return $true
}

function Read-ZipEntryText {
    param([Parameter(Mandatory)][IO.Compression.ZipArchiveEntry]$Entry)

    $reader = [IO.StreamReader]::new($Entry.Open(), [Text.Encoding]::UTF8, $true)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Test-OrcaProfileBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest
    )

    $errors = [Collections.Generic.List[string]]::new()
    $warnings = [Collections.Generic.List[string]]::new()
    $printerCount = 0
    $processCount = 0
    $filamentCount = 0

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $errors.Add("Bundle not found: $Path")
        return [pscustomobject]@{ Errors = @($errors); Warnings = @($warnings); PrinterCount = 0; ProcessCount = 0; FilamentCount = 0 }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    }
    catch {
        $errors.Add("Cannot open bundle: $($_.Exception.Message)")
        return [pscustomobject]@{ Errors = @($errors); Warnings = @($warnings); PrinterCount = 0; ProcessCount = 0; FilamentCount = 0 }
    }

    try {
        $entryByName = @{}
        $seenNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($entry in $archive.Entries) {
            $name = [string]$entry.FullName
            $segments = @($name.Split('/'))
            if ([string]::IsNullOrWhiteSpace($name) -or
                $name.StartsWith('/', [StringComparison]::Ordinal) -or
                $name.Contains('\') -or
                $segments -contains '..' -or
                $segments -contains '.' -or
                [IO.Path]::IsPathRooted($name)) {
                $errors.Add("Unsafe ZIP entry path: '$name'.")
            }
            if (-not $seenNames.Add($name)) {
                $errors.Add("Duplicate ZIP entry: '$name'.")
            }
            $entryByName[$name] = $entry
        }

        $printerEntry = Get-BundleEntryName -Kind printer -ProfilePath ([string]$Manifest.printer.path)
        $processEntries = @($Manifest.processes | ForEach-Object { Get-BundleEntryName -Kind process -ProfilePath ([string]$_.path) })
        $filamentEntries = @($Manifest.filaments | ForEach-Object { Get-BundleEntryName -Kind filament -ProfilePath ([string]$_.path) })
        [array]::Sort($processEntries, [StringComparer]::Ordinal)
        [array]::Sort($filamentEntries, [StringComparer]::Ordinal)
        $expectedEntries = @('bundle_structure.json', $printerEntry) + $processEntries + $filamentEntries
        [array]::Sort($expectedEntries, [StringComparer]::Ordinal)
        $actualEntries = @($entryByName.Keys)
        [array]::Sort($actualEntries, [StringComparer]::Ordinal)
        if (-not (Compare-StringArray -Expected $expectedEntries -Actual $actualEntries)) {
            $errors.Add("Bundle entries differ. Expected [$($expectedEntries -join ', ')], got [$($actualEntries -join ', ')].")
        }

        if ($entryByName.Contains('bundle_structure.json')) {
            try {
                $bundleManifest = ConvertFrom-ProfileJson -Json (Read-ZipEntryText -Entry $entryByName['bundle_structure.json'])
                if ([string]$bundleManifest.bundle_type -ne 'printer config bundle') {
                    $errors.Add('Invalid bundle_type.')
                }
                if ([string]$bundleManifest.bundle_id -ne [string]$Manifest.package.bundle_id) {
                    $errors.Add('Invalid bundle_id.')
                }
                if ([string]$bundleManifest.printer_preset_name -ne [string]$Manifest.printer.name) {
                    $errors.Add('Invalid printer_preset_name.')
                }
                if ([string]$bundleManifest.version -ne [string]$Manifest.package.bundle_version) {
                    $errors.Add('Invalid bundle version.')
                }
                if (-not (Compare-StringArray -Expected @($printerEntry) -Actual @(Get-ProfileValues -Profile $bundleManifest -Name 'printer_config'))) {
                    $errors.Add('Printer manifest entries differ.')
                }
                if (-not (Compare-StringArray -Expected $processEntries -Actual @(Get-ProfileValues -Profile $bundleManifest -Name 'process_config'))) {
                    $errors.Add('Process manifest entries differ.')
                }
                if (-not (Compare-StringArray -Expected $filamentEntries -Actual @(Get-ProfileValues -Profile $bundleManifest -Name 'filament_config'))) {
                    $errors.Add('Filament manifest entries differ.')
                }
            }
            catch {
                $errors.Add("Cannot parse bundle_structure.json: $($_.Exception.Message)")
            }
        }
        else {
            $errors.Add('Missing bundle_structure.json.')
        }

        $profileGroups = @(
            [pscustomobject]@{ Kind = 'Printer'; Entries = @($printerEntry) },
            [pscustomobject]@{ Kind = 'Process'; Entries = @($processEntries) },
            [pscustomobject]@{ Kind = 'Filament'; Entries = @($filamentEntries) }
        )
        foreach ($group in $profileGroups) {
            foreach ($entryName in $group.Entries) {
                if (-not $entryByName.Contains([string]$entryName)) {
                    continue
                }
                try {
                    $profile = ConvertFrom-ProfileJson -Json (Read-ZipEntryText -Entry $entryByName[[string]$entryName])
                    $profileResult = Test-ProfileData -Kind $group.Kind -Profile $profile -Manifest $Manifest
                    foreach ($message in $profileResult.Errors) {
                        $errors.Add("${entryName}: $message")
                    }
                    switch ($group.Kind) {
                        'Printer' { $printerCount++ }
                        'Process' { $processCount++ }
                        'Filament' { $filamentCount++ }
                    }
                }
                catch {
                    $errors.Add("Cannot validate '$entryName': $($_.Exception.Message)")
                }
            }
        }
    }
    finally {
        $archive.Dispose()
    }

    return [pscustomobject]@{
        Errors = @($errors)
        Warnings = @($warnings)
        PrinterCount = $printerCount
        ProcessCount = $processCount
        FilamentCount = $filamentCount
    }
}

Export-ModuleMember -Function @(
    'ConvertFrom-ProfileJson',
    'Read-ProfileJson',
    'Read-ProfileManifest',
    'Test-ProfileData',
    'Test-ProfileProject',
    'New-OrcaProfileBundle',
    'Test-OrcaProfileBundle'
)
