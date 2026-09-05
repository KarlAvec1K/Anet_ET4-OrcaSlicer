# Anet ET4 OrcaSlicer Production Profiles Design

## Objective

Build a portable OrcaSlicer 2.4.3 profile package for Karl's Anet ET4. The
package must match the Klipper configuration running on the Debian 13 mini-PC,
provide conservative production presets for a 0.4 mm nozzle, and import on a
fresh OrcaSlicer installation without relying on the old `MyKlipper` user
profile.

The project lives at:

`C:\Users\Karl\OneDrive\Dev\Anet_ET4-OrcaSlicer`

## Verified Firmware Contract

The implementation must use these values from the live Klipper host at
`192.168.18.152`:

| Property | Firmware value | Profile rule |
| --- | ---: | --- |
| Kinematics | Cartesian | Generate Cartesian G-code |
| X travel | 0 to 220 mm | Use 220 mm printable width |
| Y travel | -10 to 230 mm | Use 220 mm printable depth from 0 to 220 |
| Z travel | -3 to 250 mm | Use 250 mm printable height |
| XY velocity | 250 mm/s | Keep process travel at or below 180 mm/s |
| XY acceleration | 800 mm/s2 | Keep every process acceleration at or below 750 mm/s2 |
| Z velocity | 12 mm/s | Record 12 mm/s in machine limits |
| Z acceleration | 50 mm/s2 | Record 50 mm/s2 in machine limits |
| Square corner velocity | 5 mm/s | Record a matching 5 mm/s planning limit |
| Nozzle | 0.4 mm | Create one 0.4 mm machine variant |
| Filament | 1.75 mm | Use 1.75 mm in every material preset |
| Hotend maximum | 260 C | Cap preset temperatures at 250 C |
| Bed maximum | 125 C | Cap preset temperatures at 100 C |
| Extruder | 3:1 dual-drive Bowden | Use Bowden retraction defaults |
| Extruder rotation distance | 23.132 mm | Keep calibration in Klipper, not Orca |
| Bed mesh | 5 by 5, adaptive macro | Pass first-layer bounds to Klipper |
| Moonraker host | 192.168.18.152 | Preconfigure the local connection |

Orca must use slicer-managed retraction. The active Klipper
`[firmware_retraction]` block contains an unretract extra length that is not
appropriate for ordinary slicer travel. The profile must keep
`use_firmware_retraction` disabled and emit normal extrusion moves.

## Project Layout

The project will contain these units:

```text
Anet_ET4-OrcaSlicer/
  README.md
  CHANGELOG.md
  config/profile-manifest.json
  docs/COMPATIBILITY.md
  docs/CALIBRATION.md
  docs/IMPORT.md
  docs/superpowers/specs/
  docs/superpowers/plans/
  profiles/printer/
  profiles/process/
  profiles/filament/
  scripts/build-profile.ps1
  scripts/validate-profile.ps1
  tests/fixtures/20mm-cube.stl
  source/Anet ET4.original.orca_printer
  dist/Anet_ET4_Klipper_Production.orca_printer
```

The JSON files under `profiles` form the source of truth. The build script
creates `bundle_structure.json` and the `.orca_printer` ZIP archive from those
files. The validation script checks source files and the rebuilt archive.

## Printer Profile

The printer preset will use the name `Anet ET4 Klipper 0.4 By Codex`. It will contain a
complete setting set and will not inherit from `MyKlipper` or another user
preset. Stable Orca defaults may remain explicit in the flattened profile.

The preset will configure:

- Klipper G-code flavor and relative extrusion.
- A 220 by 220 mm rectangular bed and 250 mm build height.
- Moonraker at `192.168.18.152`.
- One 0.4 mm nozzle with 1.75 mm filament.
- Slicer retraction of 2.0 mm at 20 mm/s.
- Deretraction at 20 mm/s with no extra prime amount.
- Retraction for travels of at least 1.0 mm and on layer changes.
- A 0.4 mm normal Z hop, wipe, and 70 percent retract-before-wipe.
- Travel planning that avoids crossing walls where Orca can find a reasonable
  route.
- Firmware-compatible speed and acceleration metadata for time estimation.
- Machine-limit emission disabled so sliced G-code cannot raise the validated
  Klipper limits.

The profile will remove settings for tool changers, filament cutters, chamber
heaters, air filtration, and multi-material systems. The ET4 does not provide
those devices.

## Start And End G-code

The start G-code will use the phased macros provided by the installed
`jschuh/klipper-macros` package:

```gcode
M190 S0
M109 S0
_PRINT_START_PHASE_INIT EXTRUDER={first_layer_temperature[initial_tool]} BED=[first_layer_bed_temperature] MESH_MIN={first_layer_print_min[0]},{first_layer_print_min[1]} MESH_MAX={first_layer_print_max[0]},{first_layer_print_max[1]} LAYERS={total_layer_count} NOZZLE_SIZE={nozzle_diameter[0]}
_PRINT_START_PHASE_PREHEAT
_PRINT_START_PHASE_PROBING
_PRINT_START_PHASE_EXTRUDER
_PRINT_START_PHASE_PURGE
```

Klipper will heat the bed, home the printer, probe a fresh mesh at print
temperature, heat the nozzle, and draw the configured 30 mm purge line. The
profile will not add a second purge line.

The end G-code will contain `PRINT_END`. Klipper will retract, lift Z, park the
toolhead, present the bed, clear the mesh, switch off heaters and fans, and
disable the steppers.

## Process Presets

All process presets will use a 0.24 mm first layer, 0.50 mm first-layer line
width, 20 mm/s first-layer speed, three walls, and wall-avoidance travel. They
will keep Z hop and retract active between separate objects.

| Preset | Layer | Outer wall | Inner wall | Sparse infill | Travel | Main acceleration |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ET4 0.16 Quality By Codex | 0.16 mm | 30 mm/s | 45 mm/s | 55 mm/s | 150 mm/s | 600 mm/s2 |
| ET4 0.20 Production By Codex | 0.20 mm | 35 mm/s | 50 mm/s | 60 mm/s | 160 mm/s | 700 mm/s2 |
| ET4 0.28 Draft By Codex | 0.28 mm | 40 mm/s | 60 mm/s | 70 mm/s | 180 mm/s | 750 mm/s2 |

Each preset will use 300 mm/s2 for the first layer and no more than 550 mm/s2
for external walls. Material maximum volumetric flow will reduce speed when a
filament cannot sustain the requested process speed.

The 0.20 Production preset will serve as the default. It will use 15 percent
gyroid infill and four top and bottom shell layers. Users can change infill,
supports, brim, and wall count for each model without altering the machine
contract.

## Filament Presets

Temperatures provide safe starting points. The documentation will instruct the
operator to run Orca temperature, flow-rate, pressure-advance, and retraction
calibrations for each physical spool before treating the values as final.

| Preset | Nozzle first/rest | Bed first/rest | Max flow | Part cooling | Operating note |
| --- | ---: | ---: | ---: | --- | --- |
| ET4 Generic PLA By Codex | 215/210 C | 60/55 C | 8.0 mm3/s | 0 then 100 percent | Open printer |
| ET4 Generic PLA+ By Codex | 220/215 C | 60/55 C | 7.0 mm3/s | 0 then 100 percent | Open printer |
| ET4 Silk PLA By Codex | 215/210 C | 60/55 C | 5.5 mm3/s | 0 then 100 percent | Eryone Silk starting point |
| ET4 Generic PETG By Codex | 240/235 C | 80/75 C | 6.0 mm3/s | 0 then 30 percent | Dry filament recommended |
| ET4 Generic TPU 95A By Codex | 220/215 C | 50/45 C | 2.5 mm3/s | 0 then 60 percent | Slow feed, 1 mm retraction |
| ET4 Generic ABS By Codex | 245/240 C | 100/95 C | 6.0 mm3/s | 0 percent, bridge only | Enclosure and room ventilation required |
| ET4 Generic ASA By Codex | 250/245 C | 100/95 C | 5.5 mm3/s | 0 percent, bridge only | Enclosure and room ventilation required |

The package will exclude polycarbonate, nylon, PPS, PEEK, and other materials
that need hotend temperatures near or above the ET4 firmware limit. The
documentation will also state that an enclosure does not remove the need for
room ventilation when printing ABS or ASA.

## Build And Validation

`build-profile.ps1` will perform a deterministic build. It will parse each
source JSON file, create the Orca bundle manifest, place printer, process, and
filament files in their required archive paths, and write the production
archive under `dist`.

`validate-profile.ps1` will fail when it finds any of these conditions:

- Invalid JSON or a missing referenced preset.
- A dependency on `MyKlipper` or another user-only profile.
- A nozzle target over 250 C or bed target over 100 C.
- A machine speed over 250 mm/s or acceleration over 800 mm/s2.
- A process travel speed over 180 mm/s or acceleration over 750 mm/s2.
- Firmware retraction enabled.
- Missing phased start macros, `PRINT_END`, mesh bounds, layer count, or nozzle
  diameter placeholders.
- Missing purge behavior, Z hop, wipe, or object-crossing controls.
- An unexpected file, absolute path, or path traversal entry in the archive.
- A bundle manifest that does not list every included preset exactly once.

The implementation will test the package against OrcaSlicer 2.4.3 in an
isolated data directory. It will import or load all presets, slice the included
20 mm cube, and inspect the generated G-code for the expected macro sequence,
temperature bounds, travel limits, retraction, and end macro. These tests will
not connect to Moonraker or send commands to the printer.

## Installation And Recovery

`README.md` and `docs/IMPORT.md` will cover:

1. Importing the `.orca_printer` bundle into OrcaSlicer 2.4.3 or later.
2. Selecting the ET4 printer, process, and filament presets.
3. Testing the Moonraker connection on the local network.
4. Exporting a backup after spool-specific calibration.
5. Restoring from the original user export and removing the imported presets.

The project will retain the supplied `Anet ET4.orca_printer` unchanged under
`source` for comparison and recovery.

## Acceptance Criteria

The work is complete when:

- A clean validation run reports no JSON, dependency, limit, or archive errors.
- OrcaSlicer 2.4.3 loads the printer and all ten supporting presets without a
  type error.
- Orca slices the 20 mm cube with each process preset.
- Generated G-code contains the five phased start macros and one `PRINT_END`.
- Generated G-code stays within the firmware temperature, speed, acceleration,
  and extrusion constraints.
- The documentation lets a third party import, select, calibrate, back up, and
  recover the profiles without editing JSON.
- No validation step heats, homes, moves, or extrudes on the physical printer.
