# Import, mise a jour et restauration

## Prerequis

- OrcaSlicer 2.4.3 ou plus recent.
- L'imprimante et le mini-PC Klipper deja fonctionnels dans Mainsail.
- Le paquet `dist/Anet_ET4_Klipper_Production.orca_printer`.
- L'adresse Moonraker actuelle. Le paquet utilise `192.168.18.152` comme valeur
  locale de depart.

L'import n'exige pas que l'imprimante soit allumee. Ne lancez pas une impression
pendant la sauvegarde, l'import ou la verification des profils.

## Sauvegarde avant import

Sous Windows, OrcaSlicer conserve ses donnees dans :

`C:\Users\Karl\AppData\Roaming\OrcaSlicer`

Le chemin portable equivalent est `%APPDATA%\OrcaSlicer`. Fermer OrcaSlicer,
puis executer :

```powershell
$source = Join-Path $env:APPDATA 'OrcaSlicer'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $env:USERPROFILE "Documents\OrcaSlicer-backup-$stamp"
Copy-Item -LiteralPath $source -Destination $backup -Recurse
Get-ChildItem -LiteralPath $backup
```

Conserver le chemin affiche. La copie du dossier complet couvre le profil local
`user\default` ainsi qu'un eventuel dossier de compte OrcaCloud. Ne copiez pas
les profils directement dans `AppData` pour installer ce paquet : utilisez
l'import Orca.

## Import du paquet

1. Demarrer OrcaSlicer.
2. Ouvrir `File > Import > Import Configs` (`Fichier > Importer` selon la
   traduction active).
3. Selectionner `dist/Anet_ET4_Klipper_Production.orca_printer`.
4. Accepter l'import des onze presets : une imprimante, trois processus et sept
   filaments.
5. Si Orca demande de remplacer un preset du meme nom, remplacer seulement les
   presets dont le nom commence par `ET4` ou `Anet ET4 Klipper`.
6. Redemarrer OrcaSlicer si un preset n'apparait pas immediatement.

## Selection de production

Choisir ces trois elements dans la vue `Prepare` :

| Type | Choix initial |
| --- | --- |
| Imprimante | `Anet ET4 Klipper 0.4 By Codex` |
| Processus | `ET4 0.20 Production By Codex` |
| Filament | `ET4 Generic PLA By Codex` ou le materiau reel |
| Plateau | `Textured PEI Plate` ou le type donnant acces a la temperature configuree |

Le nom de plateau dans Orca ne change pas la surface physique. Le profil donne
les memes temperatures de base aux principales familles de plateaux afin
d'eviter une chauffe a zero lors d'un changement d'affichage.

## Connexion Moonraker

1. Ouvrir les reglages de l'imprimante physique associee au preset.
2. Choisir `Moonraker` comme type d'hote.
3. Utiliser `192.168.18.152` si cette adresse est toujours celle du mini-PC.
4. Tester la connexion sans lancer d'impression.
5. Si l'adresse a change, corriger uniquement l'adresse dans Orca; ne modifier
   ni les macros ni les dimensions de la machine.

Le paquet ne contient aucun mot de passe ni jeton Moonraker. Une adresse locale
presente dans les commentaires de configuration du G-code n'est pas une
commande executee par Klipper.

## Verification avant le premier envoi

1. Charger un petit modele connu.
2. Trancher avec `ET4 0.20 Production By Codex`.
3. Inspecter l'apercu couche par couche, surtout la premiere couche, les
   supports, les deplacements et la position dans le volume 220 x 220 x 250 mm.
4. Verifier que les temperatures correspondent au filament reel.
5. Verifier que le debut ne contient pas une seconde purge ajoutee manuellement.
6. Envoyer seulement apres l'inspection.

Le G-code de depart attendu appelle, dans cet ordre :

```gcode
M190 S0
M109 S0
_PRINT_START_PHASE_INIT ...
_PRINT_START_PHASE_PREHEAT
_PRINT_START_PHASE_PROBING
_PRINT_START_PHASE_EXTRUDER
_PRINT_START_PHASE_PURGE
```

La fin doit contenir une seule commande `PRINT_END`.

## Mise a jour du paquet

1. Fermer Orca et refaire une sauvegarde du dossier de configuration.
2. Recuperer la nouvelle version du depot.
3. Executer les quatre commandes de validation du `README.md`.
4. Importer le nouveau fichier du dossier `dist`.
5. Remplacer uniquement les presets ET4 portant les memes noms.
6. Reappliquer les valeurs calibrees propres a vos bobines dans des copies de
   filament separees.

## Export apres calibration

Ne remplacez pas les profils generiques si vous voulez pouvoir les mettre a
jour facilement. Dupliquer le profil filament, ajouter la marque, le materiau
et la couleur au nom, enregistrer les calibrations, puis utiliser l'export de
configuration Orca pour creer une sauvegarde portable.

## Restauration complete

1. Fermer OrcaSlicer.
2. Renommer le dossier actuel au lieu de le supprimer.
3. Copier la sauvegarde a son emplacement original.
4. Relancer OrcaSlicer et verifier les presets.

Exemple, en remplacant le chemin de sauvegarde :

```powershell
$current = Join-Path $env:APPDATA 'OrcaSlicer'
$disabled = "$current.disabled-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Move-Item -LiteralPath $current -Destination $disabled
Copy-Item -LiteralPath 'C:\Users\Karl\Documents\OrcaSlicer-backup-YYYYMMDD-HHMMSS' `
  -Destination $current -Recurse
```

L'export utilisateur d'origine est aussi conserve, octet pour octet, dans
`source/Anet ET4.original.orca_printer`. Il sert de reference ou de solution de
repli, pas de source pour reconstruire le nouveau paquet.
