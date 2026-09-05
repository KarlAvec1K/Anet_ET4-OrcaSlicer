# Anet ET4 Klipper - profils OrcaSlicer

Ce projet fournit un paquet OrcaSlicer reproductible pour une Anet ET4 sous
Klipper avec buse de 0.4 mm et extrudeur dual-drive Bowden.

Fichier a importer :

`dist/Anet_ET4_Klipper_Production.orca_printer`

Le paquet a ete valide avec OrcaSlicer 2.4.3 en tranchant localement un cube de
20 mm. Aucun test automatise ne se connecte a Moonraker et aucune commande
n'est envoyee a l'imprimante.

## Demarrage rapide

1. Fermer OrcaSlicer et sauvegarder `%APPDATA%\OrcaSlicer`.
2. Ouvrir OrcaSlicer 2.4.3 ou une version plus recente.
3. Utiliser `File > Import > Import Configs` et choisir le fichier du dossier
   `dist`.
4. Choisir `Anet ET4 Klipper 0.4` comme imprimante.
5. Choisir `ET4 0.20 Production` et le filament correspondant a la bobine.
6. Trancher, inspecter l'apercu, puis envoyer le fichier seulement apres cette
   verification.

Les instructions detaillees, la sauvegarde et la restauration se trouvent dans
[docs/IMPORT.md](docs/IMPORT.md).

## Contenu du paquet

- Imprimante : `Anet ET4 Klipper 0.4`.
- Processus : `ET4 0.16 Quality`, `ET4 0.20 Production`, `ET4 0.28 Draft`.
- Filaments : PLA, PLA+, Silk PLA, PETG, TPU 95A, ABS et ASA generiques.
- Demarrage : chauffe, homing, mesh adaptatif et purge geres par les macros
  Klipper en phases.
- Fin : `PRINT_END`, avec retract, levee et stationnement geres par Klipper.

`ET4 0.20 Production` est le point de depart recommande. Les valeurs filament
sont prudentes, mais une calibration par bobine reste necessaire avant la
production.

## Contrat machine

| Parametre | Valeur utilisee |
| --- | ---: |
| Volume Orca | 220 x 220 x 250 mm |
| Buse / filament | 0.4 mm / 1.75 mm |
| Vitesse XY firmware max | 250 mm/s |
| Acceleration firmware max | 800 mm/s2 |
| Vitesse de deplacement des profils | 150 a 180 mm/s |
| Acceleration des profils | 600 a 750 mm/s2 |
| Temperature profil hotend max | 250 C |
| Temperature profil bed max | 100 C |
| Retraction Bowden de base | 2.0 mm a 20 mm/s |
| Z-hop | 0.4 mm |

Le Z-offset, le PID, la rotation de l'extrudeur et le mesh ne doivent pas etre
compenses dans Orca. Ils appartiennent a la configuration Klipper. Voir
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) et
[docs/CALIBRATION.md](docs/CALIBRATION.md).

## Construire et verifier

Depuis la racine du projet :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ProfilePackage.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-profile.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-profile.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-OrcaSmoke.ps1
```

Le premier test controle les sources, les limites et les cas invalides. Le test
Orca lance l'executable installe avec un dossier de donnees temporaire, tranche
le cube fourni, puis inspecte le G-code produit.

## Arborescence

```text
config/       contrat et contenu du paquet
profiles/     sources JSON modifiables et revisionnables
scripts/      construction et validation deterministes
tests/        validations structurelles et tranchage Orca
source/       export original fourni, conserve sans modification
dist/         fichier final a importer
docs/         import, compatibilite et calibration
```

Documentation Orca officielle :

- [Profils utilisateur](https://github.com/OrcaSlicer/OrcaSlicer/wiki/user_profiles)
- [Guide de calibration](https://github.com/OrcaSlicer/OrcaSlicer/wiki/calibration_guide)

