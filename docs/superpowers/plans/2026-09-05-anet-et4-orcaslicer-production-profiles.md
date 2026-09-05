# Anet ET4 OrcaSlicer Production Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a portable OrcaSlicer 2.4.3 import bundle for the Klipper-driven Anet ET4, including one printer preset, three process presets, and seven filament presets.

**Architecture:** Store reviewable JSON sources under `profiles`, describe bundle membership and firmware limits in one manifest, and build the `.orca_printer` artifact with a PowerShell module. A dependency-free PowerShell test runner will exercise the real builder and validator, while an OrcaSlicer CLI smoke test will slice an ASCII STL without contacting the printer.

**Tech Stack:** PowerShell 7 or Windows PowerShell 5.1, JSON, ZIP/Orca `.orca_printer`, OrcaSlicer 2.4.3, Klipper phased start macros.

**Spec:** `docs/superpowers/specs/2026-09-05-anet-et4-orcaslicer-production-profiles-design.md`

## Global Constraints

- Store the project under `C:\Users\Karl\OneDrive\Dev\Anet_ET4-OrcaSlicer`.
- Support OrcaSlicer 2.4.3 or later and a 0.4 mm nozzle.
- Use a 220 by 220 by 250 mm printable volume.
- Do not exceed 250 mm/s, 800 mm/s2, 260 C hotend, or 125 C bed firmware limits.
- Presets must stay at or below 250 C hotend and 100 C bed.
- Use slicer-managed retraction, 2.0 mm at 20 mm/s, with 0.4 mm Z hop.
- Use Klipper phased start macros and one `PRINT_END` command.
- Validation must not connect to Moonraker or command the physical printer.
- Preserve the supplied Orca export byte-for-byte under `source`.

---

### Task 1: Establish the test harness and immutable source fixture

**Files:**
- Create: `tests/Test-ProfilePackage.ps1`
- Create: `tests/fixtures/20mm-cube.stl`
- Copy: `source/Anet ET4.original.orca_printer`

**Interfaces:**
- Consumes: `scripts/ProfileTools.psm1` once Task 2 creates it.
- Produces: A dependency-free test command that returns exit code 0 only when every assertion passes.

- [ ] **Step 1: Preserve the user export**

Copy `C:\Users\Karl\Downloads\Anet ET4.orca_printer` to
`source/Anet ET4.original.orca_printer` with `System.IO.File.Copy`. Record both
SHA-256 values and require equality.

- [ ] **Step 2: Write the failing package tests**

Create a PowerShell test runner with literal expectations for these behaviors:

```powershell
$manifest = Read-ProfileManifest -Path $manifestPath
Assert-Equal 220 $manifest.firmware.max_printable_x 'X printable limit'
Assert-Equal 800 $manifest.firmware.max_acceleration 'Firmware acceleration limit'

$result = Test-ProfileProject -ProjectRoot $projectRoot
Assert-Equal 0 $result.Errors.Count 'Valid source profiles'
Assert-Equal 1 $result.PrinterCount 'Printer preset count'
Assert-Equal 3 $result.ProcessCount 'Process preset count'
Assert-Equal 7 $result.FilamentCount 'Filament preset count'

$firstHash = (Get-FileHash $firstArchive -Algorithm SHA256).Hash
$secondHash = (Get-FileHash $secondArchive -Algorithm SHA256).Hash
Assert-Equal $firstHash $secondHash 'Deterministic archive output'
```

Add negative cases that pass cloned hashtables to the real validator and expect
errors for 251 C, 801 mm/s2, firmware retraction, missing phased macros, a
`MyKlipper` dependency, and a path traversal ZIP entry.

- [ ] **Step 3: Run the test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-ProfilePackage.ps1
```

Expected result: non-zero exit because `ProfileTools.psm1`, the manifest, and
the production profiles do not exist.

- [ ] **Step 4: Add a deterministic 20 mm cube fixture**

Create an ASCII STL with 12 triangles spanning coordinates 0 through 20 on X,
Y, and Z. The test runner will verify its bounding box before Orca uses it.

- [ ] **Step 5: Commit the failing tests and source fixture**

```powershell
git add -- Anet_ET4-OrcaSlicer/tests Anet_ET4-OrcaSlicer/source
git commit -m "test: define ET4 profile package contract"
```

### Task 2: Implement deterministic build and contract validation

**Files:**
- Create: `scripts/ProfileTools.psm1`
- Create: `scripts/build-profile.ps1`
- Create: `scripts/validate-profile.ps1`
- Create: `config/profile-manifest.json`

**Interfaces:**
- Produces: `Read-ProfileManifest -Path <string>` returning a hashtable.
- Produces: `Test-ProfileProject -ProjectRoot <string>` returning counts, errors, and warnings.
- Produces: `New-OrcaProfileBundle -ProjectRoot <string> -OutputPath <string>` returning the archive path.
- Consumes: JSON sources listed by `config/profile-manifest.json`.

- [ ] **Step 1: Create the manifest**

Record the Orca version, firmware limits, local Moonraker host, expected preset
names, source paths, and output filename. Use numeric JSON values for limits and
strings for Orca profile values.

- [ ] **Step 2: Implement JSON and project validation**

Parse JSON with `ConvertFrom-Json -AsHashtable` under PowerShell 7 and a
recursive PSCustomObject-to-hashtable fallback under Windows PowerShell 5.1.
Validate file membership, preset types, unique names, firmware limits,
temperature limits, retraction mode, start phases, end G-code, and user-only
inheritance.

- [ ] **Step 3: Implement deterministic bundle construction**

Use `System.IO.Compression.ZipArchive`. Sort entries with ordinal comparison,
encode JSON as UTF-8 without BOM, use `/` path separators, and assign every ZIP
entry the timestamp `2026-09-05T00:00:00Z`. Generate this manifest inside the
archive:

```json
{
  "bundle_type": "printer config bundle",
  "filament_config": ["filament/<name>.json"],
  "printer_config": ["printer/Anet ET4 Klipper 0.4 By Codex.json"],
  "process_config": ["process/<name>.json"],
  "printer_preset_name": "Anet ET4 Klipper 0.4 By Codex",
  "version": "02.04.03.00"
}
```

- [ ] **Step 4: Add wrapper scripts**

`build-profile.ps1` imports the module, validates the sources, removes no user
files, and writes the archive to `dist`. `validate-profile.ps1` validates both
the source tree and the built archive, prints each error, and returns non-zero
on failure.

- [ ] **Step 5: Run the tests and confirm expected partial failures**

Run the test runner. The module behavior and negative cases must pass. Profile
count assertions must still fail because Tasks 3 through 5 have not created the
JSON presets.

- [ ] **Step 6: Commit the tooling**

```powershell
git add -- Anet_ET4-OrcaSlicer/config Anet_ET4-OrcaSlicer/scripts
git commit -m "feat: add deterministic Orca profile builder"
```

### Task 3: Build the firmware-compatible printer preset

**Files:**
- Create: `profiles/printer/Anet ET4 Klipper 0.4 By Codex.json`

**Interfaces:**
- Produces: Printer preset named `Anet ET4 Klipper 0.4 By Codex`.
- Consumes: Live Klipper limits captured in the design spec.

- [ ] **Step 1: Keep the printer test RED**

Run the test runner and confirm the missing printer preset causes the expected
count or missing-file failure.

- [ ] **Step 2: Create a flattened printer profile**

Start from the supplied flattened Orca export. Remove the `MyKlipper`
inheritance and unsupported hardware flags. Set the verified geometry, Klipper
flavor, Moonraker host, speed metadata, 2 mm retraction, 20 mm/s retract and
deretract speed, 0.4 mm Z hop, wipe, and machine-limit emission disabled.

Use this start sequence exactly:

```gcode
M190 S0
M109 S0
_PRINT_START_PHASE_INIT EXTRUDER={first_layer_temperature[initial_tool]} BED=[first_layer_bed_temperature] MESH_MIN={first_layer_print_min[0]},{first_layer_print_min[1]} MESH_MAX={first_layer_print_max[0]},{first_layer_print_max[1]} LAYERS={total_layer_count} NOZZLE_SIZE={nozzle_diameter[0]}
_PRINT_START_PHASE_PREHEAT
_PRINT_START_PHASE_PROBING
_PRINT_START_PHASE_EXTRUDER
_PRINT_START_PHASE_PURGE
```

Use `PRINT_END` as the complete end G-code.

- [ ] **Step 3: Run the tests and verify printer GREEN**

Expected result: printer checks pass, process and filament counts remain
failing.

- [ ] **Step 4: Commit the printer preset**

```powershell
git add -- Anet_ET4-OrcaSlicer/profiles/printer
git commit -m "feat: add Klipper-compatible ET4 printer preset"
```

### Task 4: Add three conservative process presets

**Files:**
- Create: `profiles/process/ET4 0.16 Quality By Codex.json`
- Create: `profiles/process/ET4 0.20 Production By Codex.json`
- Create: `profiles/process/ET4 0.28 Draft By Codex.json`

**Interfaces:**
- Produces: Three process presets compatible with `Anet ET4 Klipper 0.4 By Codex`.
- Consumes: Machine geometry, nozzle size, and acceleration caps from the manifest.

- [ ] **Step 1: Keep the process tests RED**

Run the test runner and confirm it reports three missing process files.

- [ ] **Step 2: Create complete process presets**

Flatten Orca's FFF process defaults into each file. Apply the exact layer,
speed, travel, and acceleration values from the design spec. Set a 0.24 mm
first layer, 0.50 mm first-layer width, 20 mm/s first-layer speed, three walls,
15 percent gyroid infill, wall-avoidance travel, and no machine-limit override.

- [ ] **Step 3: Run the tests and verify process GREEN**

Expected result: all printer and process assertions pass. Filament count remains
failing.

- [ ] **Step 4: Commit the process presets**

```powershell
git add -- Anet_ET4-OrcaSlicer/profiles/process
git commit -m "feat: add ET4 quality production and draft presets"
```

### Task 5: Add seven material presets

**Files:**
- Create: `profiles/filament/ET4 Generic PLA By Codex.json`
- Create: `profiles/filament/ET4 Generic PLA+ By Codex.json`
- Create: `profiles/filament/ET4 Silk PLA By Codex.json`
- Create: `profiles/filament/ET4 Generic PETG By Codex.json`
- Create: `profiles/filament/ET4 Generic TPU 95A By Codex.json`
- Create: `profiles/filament/ET4 Generic ABS By Codex.json`
- Create: `profiles/filament/ET4 Generic ASA By Codex.json`

**Interfaces:**
- Produces: Seven filament presets compatible with `Anet ET4 Klipper 0.4 By Codex`.
- Consumes: Material temperature, cooling, flow, and operating notes from the design spec.

- [ ] **Step 1: Keep the filament tests RED**

Run the test runner and confirm it reports seven missing filament files.

- [ ] **Step 2: Create flattened material profiles**

Use the temperature, maximum volumetric flow, cooling, and safety notes from the
design. Bind each profile to `Anet ET4 Klipper 0.4 By Codex`. Override TPU retraction to
1.0 mm at 15 mm/s. Keep the printer's 2.0 mm at 20 mm/s for the other six
materials.

- [ ] **Step 3: Run the complete source test suite GREEN**

Run the test runner. Expected result: every source, limit, negative-case, and
preset-count assertion passes.

- [ ] **Step 4: Commit the filament presets**

```powershell
git add -- Anet_ET4-OrcaSlicer/profiles/filament
git commit -m "feat: add ET4 production filament presets"
```

### Task 6: Build, inspect, and smoke-test the import archive

**Files:**
- Create: `dist/Anet_ET4_Klipper_Production.orca_printer`
- Create: `tests/Test-OrcaSmoke.ps1`

**Interfaces:**
- Produces: The user-importable Orca profile bundle.
- Consumes: OrcaSlicer 2.4.3 and all source profiles.

- [ ] **Step 1: Write the failing Orca smoke test**

Create a test that resolves the installed Orca executable, creates an isolated
temporary data directory, invokes Orca against the 20 mm cube with the printer,
process, and PLA profiles, and asserts that a G-code file appears. It must then
assert one ordered phased-start sequence, one `PRINT_END`, a 0.4 mm nozzle, and
temperature and acceleration values below manifest caps.

- [ ] **Step 2: Run the smoke test and verify RED**

Expected result: non-zero exit because the archive and built profile staging do
not exist.

- [ ] **Step 3: Build the archive twice**

Run `scripts\build-profile.ps1` twice to separate paths. Verify matching SHA-256
hashes, then retain the canonical artifact in `dist`.

- [ ] **Step 4: Validate the archive structure**

Run `scripts\validate-profile.ps1`. Confirm one printer, three process files,
seven filament files, no unlisted archive entries, no traversal paths, and no
contract errors.

- [ ] **Step 5: Run the Orca smoke test GREEN**

Invoke the Store executable in a separate instance with Orca's source-defined
CLI flags:

```powershell
orca-slicer.exe --load-settings "profiles/printer/Anet ET4 Klipper 0.4 By Codex.json;profiles/process/ET4 0.20 Production By Codex.json" `
  --load-filaments "profiles/filament/ET4 Generic PLA By Codex.json" `
  --slice 0 --outputdir tests/out tests/fixtures/20mm-cube.stl
```

Do not open Moonraker or upload G-code. Expected result: one valid local G-code
file with every asserted macro and limit.

- [ ] **Step 6: Commit the archive and smoke test**

```powershell
git add -- Anet_ET4-OrcaSlicer/dist Anet_ET4-OrcaSlicer/tests/Test-OrcaSmoke.ps1
git commit -m "build: publish validated ET4 Orca import bundle"
```

### Task 7: Document import, calibration, and recovery

**Files:**
- Create: `README.md`
- Create: `CHANGELOG.md`
- Create: `docs/COMPATIBILITY.md`
- Create: `docs/CALIBRATION.md`
- Create: `docs/IMPORT.md`

**Interfaces:**
- Produces: A third-party runbook for import, profile selection, calibration, backup, and recovery.
- Consumes: Final preset names and archive path.

- [ ] **Step 1: Document the production workflow**

Explain how to import the archive, choose printer/process/material presets,
connect Moonraker, slice locally, inspect the preview, and upload only after
review. Identify the 0.20 Production and matching material preset as defaults.

- [ ] **Step 2: Document calibration boundaries**

Record the current machine contract and distinguish firmware calibration from
spool calibration. Include temperature tower, flow ratio, pressure advance,
retraction, first-layer inspection, and dimensional checks. State that users
must not alter Z offset from a filament profile.

- [ ] **Step 3: Document material safety**

State the enclosure and room-ventilation requirements for ABS and ASA. Explain
why the package excludes materials that need temperatures close to 260 C.

- [ ] **Step 4: Document recovery**

Provide exact steps to remove imported ET4 presets, restore the original
archive, rebuild `dist`, and verify SHA-256 hashes.

- [ ] **Step 5: Run all verification commands**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-ProfilePackage.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-profile.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate-profile.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-OrcaSmoke.ps1
git diff --check
```

Expected result: all commands return exit code 0 with no validation errors.

- [ ] **Step 6: Commit documentation**

```powershell
git add -- Anet_ET4-OrcaSlicer/README.md Anet_ET4-OrcaSlicer/CHANGELOG.md Anet_ET4-OrcaSlicer/docs
git commit -m "docs: add ET4 Orca production runbook"
```
