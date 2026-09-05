# Contrat de compatibilite

## Machine cible

Ce paquet cible l'Anet ET4 actuellement configuree sous Klipper sur le mini-PC
Debian 13. Il ne constitue pas un profil universel pour toutes les variantes
ET4 ou toutes les cartes controleur.

| Element | Contrat requis |
| --- | --- |
| Cinematique | Cartesian |
| Zone Orca | X 0..220, Y 0..220, Z 0..250 mm |
| Limite firmware XY | 250 mm/s |
| Limite firmware acceleration | 800 mm/s2 |
| Limite firmware Z | 12 mm/s et 50 mm/s2 |
| Buse | 0.4 mm |
| Filament | 1.75 mm |
| Extrudeur | Dual-drive Bowden, rotation calibree dans Klipper |
| Hotend | Maximum firmware 260 C; presets limites a 250 C |
| Bed | Maximum firmware 125 C; presets limites a 100 C |
| Hote | Moonraker, valeur initiale `192.168.18.152` |

La plage mecanique Klipper peut depasser legerement la zone de travail Orca
pour permettre le homing ou le stationnement. Il ne faut pas agrandir le volume
Orca sans une nouvelle verification mecanique.

## Macros Klipper obligatoires

Le profil n'utilise pas un simple `PRINT_START`. Il exige ces macros fournies
par la configuration installee sur le mini-PC :

- `_PRINT_START_PHASE_INIT`
- `_PRINT_START_PHASE_PREHEAT`
- `_PRINT_START_PHASE_PROBING`
- `_PRINT_START_PHASE_EXTRUDER`
- `_PRINT_START_PHASE_PURGE`
- `PRINT_END`

La phase `INIT` recoit les temperatures, les limites XY de la premiere couche,
le nombre de couches et le diametre de buse. Klipper effectue ensuite le homing,
le mesh adaptatif, la chauffe finale et la purge. Un nouveau mini-PC doit
restaurer ces macros avant d'utiliser les profils.

## Responsabilite Klipper

Les elements suivants restent dans `printer.cfg` et les fichiers inclus :

- broches, sens des moteurs, endstops et limites de mouvement;
- rotation distance de l'extrudeur;
- PID du hotend et du bed;
- type de thermistance et limites thermiques;
- Z-offset et configuration du capteur Z;
- mesh, homing, purge et stationnement;
- limites de vitesse et d'acceleration faisant autorite.

Orca ne doit pas emettre de limites machine capables de relever ces valeurs.
Le paquet garde `emit_machine_limits_to_gcode` desactive.

## Responsabilite Orca

Orca gere la geometrie de tranchage, les couches, les largeurs, les vitesses de
processus, le refroidissement, le flow par bobine, la retraction et le Z-hop.
La retraction firmware est desactivee : Orca produit les mouvements d'extrusion
et utilise 2.0 mm a 20 mm/s comme base Bowden, sauf TPU a 1.0 mm et 15 mm/s.

## Versions

- Valide avec OrcaSlicer 2.4.3 sous Windows.
- Le schema des profils annonce la version 2.4.0.1.
- Une version Orca plus recente doit passer `Test-ProfilePackage.ps1` et
  `Test-OrcaSmoke.ps1` avant que le paquet soit republie.

Le smoke test utilise des copies temporaires marquees `from: system` pour le
mode CLI. Orca CLI deduit la compatibilite des fichiers externes depuis
l'heritage systeme; le vrai paquet reste correctement marque `from: User` pour
l'import graphique. Le test verifie que ce champ est la seule difference.

## Materiaux et limites physiques

PLA, PLA+, Silk PLA, PETG et TPU 95A ont des bases prudentes pour la machine
ouverte. Chaque bobine doit tout de meme etre calibree et, au besoin, sechee.

ABS et ASA sont fournis pour une future enclosure. Ne pas les utiliser avant :

- d'avoir une enclosure stable;
- d'assurer une ventilation de la piece vers l'exterieur;
- d'avoir confirme que le hotend, le tube PTFE et tous les raccords supportent
  durablement 245 a 250 C;
- d'avoir verifie le cablage, la protection thermique et le comportement du bed
  a 100 C.

Une enclosure ne remplace pas la ventilation de la piece. Les materiaux qui
exigent une temperature proche ou superieure a 260 C, notamment PC haute
temperature, nylon haute temperature, PPS et PEEK, sont volontairement exclus.

## Modifications materielle futures

Un changement de buse, de hotend, d'extrudeur, de capteur Z, de dimensions ou de
carte controleur exige une nouvelle validation. Une migration vers une carte
SKR doit utiliser un nouveau profil d'imprimante ou une variante clairement
nommee; elle ne doit pas remplacer silencieusement ce contrat ET4.
