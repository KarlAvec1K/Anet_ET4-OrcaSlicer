# Calibration de production

Les profils sont des points de depart conservateurs. Une calibration mecanique
et firmware correcte precede toujours les calibrations propres au filament.

## Avant toute calibration

1. Verifier le serrage mecanique, les courroies, les galets, le hotend, les
   raccords Bowden et le maintien du tube des deux cotes.
2. Verifier a froid que les temperatures hotend et bed sont plausibles et
   stables.
3. Nettoyer le plateau avec une methode compatible avec la surface. Utiliser la
   colle seulement comme couche d'adherence ou de separation adaptee au
   materiau.
4. Confirmer le homing et le capteur Z dans Mainsail avant une impression.
5. Utiliser le profil `ET4 0.20 Production` pour commencer.

La macro de depart calcule un mesh adaptatif frais pour la zone imprimee. Elle
ne repare pas un plateau desserre, un capteur instable ou un mauvais Z-offset.

## Separation des reglages

Reglages firmware a conserver dans Klipper :

- rotation distance de l'extrudeur;
- PID hotend et bed;
- Z-offset du capteur;
- mesh et limites mecaniques;
- pressure advance global si la configuration Klipper le force deja.

Reglages a enregistrer dans une copie du profil filament :

- temperature hotend et bed;
- flow ratio;
- maximum volumetric speed;
- pressure advance, seulement apres calibration et sans doublon firmware;
- refroidissement;
- retraction specifique au materiau.

Ne jamais corriger le Z-offset dans un profil filament. Si la premiere couche
est trop haute ou trop basse partout malgre un mesh coherent, regler le
Z-offset dans Klipper, verifier, puis sauvegarder la configuration firmware.

## Ordre recommande par bobine

Orca fournit les essais dans le menu `Calibration`. Apres chaque serie, creer
un nouveau projet pour quitter le mode calibration.

1. **Temperature** : choisir la zone qui donne adhesion inter-couche, ponts et
   surface propres sans degradation du filament.
2. **Maximum volumetric speed** : retenir une valeur sous le premier signe de
   sous-extrusion. Les presets commencent volontairement bas.
3. **Pressure Advance** : utiliser la variante Bowden. Enregistrer le resultat
   dans la copie du filament seulement si Klipper ne fixe pas deja cette valeur.
4. **Flow Ratio** : effectuer les deux passes Orca et enregistrer le facteur
   final dans le filament.
5. **Retraction** : chercher la plus petite distance qui retire le stringing
   sans creer de manque apres les deplacements.
6. **Premiere couche** : imprimer neuf petits carres repartis sur le plateau et
   verifier une largeur uniforme, sans espaces et sans buse qui gratte.
7. **Dimensions** : imprimer un cube de 20 mm, laisser refroidir, puis mesurer X,
   Y et Z avec un outil connu.

Guide Orca officiel :
[Calibration Guide](https://github.com/OrcaSlicer/OrcaSlicer/wiki/calibration_guide).

## Valeurs de depart

| Filament | Buse premiere/suite | Bed premiere/suite | Debit volumique max |
| --- | ---: | ---: | ---: |
| PLA | 215/210 C | 60/55 C | 8.0 mm3/s |
| PLA+ | 220/215 C | 60/55 C | 7.0 mm3/s |
| Silk PLA | 215/210 C | 60/55 C | 5.5 mm3/s |
| PETG | 240/235 C | 80/75 C | 6.0 mm3/s |
| TPU 95A | 220/215 C | 50/45 C | 2.5 mm3/s |
| ABS | 245/240 C | 100/95 C | 6.0 mm3/s |
| ASA | 250/245 C | 100/95 C | 5.5 mm3/s |

ABS et ASA exigent les conditions decrites dans `COMPATIBILITY.md` avant le
premier chauffage.

## Retraction et deplacements

La base PLA/PETG/ABS/ASA est 2.0 mm a 20 mm/s, avec deretraction a 20 mm/s,
wipe et Z-hop de 0.4 mm. Pour un test Bowden Orca, une plage de 1 a 6 mm par pas
de 0.2 mm permet de trouver le minimum propre. Ne conservez pas une distance
plus grande que necessaire : elle augmente le risque de bouchon et le delai de
reprise d'extrusion.

Le TPU commence a 1.0 mm et 15 mm/s. Si le TPU se comprime dans le dual-drive,
reduire la vitesse et verifier d'abord le chemin mecanique plutot que
d'augmenter la force de l'extrudeur.

Un test de deplacement doit contenir plusieurs tours separes. Inspecter :

- fils entre les tours;
- manque au redemarrage de chaque perimetre;
- marques de buse sur les pieces;
- tube Bowden qui se deplace ou sort du raccord;
- Z-hop reel pendant les deplacements hors perimetre.

## Premiere couche

Le processus utilise une couche initiale de 0.24 mm, une largeur de 0.50 mm,
20 mm/s et 300 mm/s2. Une bonne couche forme des lignes jointives et accroche
sur toute la zone sans transparence excessive ni bourrelet pousse sur les
cotes.

Si le defaut varie selon la position, verifier le montage du plateau, le mesh et
le capteur. Si le defaut est uniforme, regler le Z-offset. Ne compensez pas une
mauvaise hauteur avec un flow artificiellement eleve.

## Validation finale d'une bobine

1. Dupliquer le preset generique et le nommer avec marque, gamme, matiere et
   couleur.
2. Enregistrer les valeurs calibrees dans cette copie.
3. Trancher un cube de 20 mm et inspecter l'apercu.
4. Imprimer sous supervision, mesurer apres refroidissement et noter le
   resultat.
5. Exporter les presets calibres et conserver l'export avec la date et le lot de
   filament.

