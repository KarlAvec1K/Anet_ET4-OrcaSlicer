# Changelog

## 2026-09-05 - Production profile bundle 1

- Ajout du profil `Anet ET4 Klipper 0.4 @codex` compatible avec le contrat Klipper
  valide sur le mini-PC Debian 13.
- Ajout des processus 0.16 Quality, 0.20 Production et 0.28 Draft.
- Ajout des bases PLA, PLA+, Silk PLA, PETG, TPU 95A, ABS et ASA.
- Integration du demarrage Klipper en phases, du mesh adaptatif, de la purge et
  de `PRINT_END` sans G-code concurrent dans Orca.
- Construction deterministe du fichier
  `dist/Anet_ET4_Klipper_Production.orca_printer`.
- Validation des limites, des dependances, de la structure ZIP et des cas
  invalides.
- Test de tranchage reel d'un cube de 20 mm avec OrcaSlicer 2.4.3 dans un
  environnement isole.
- Conservation sans modification de l'export utilisateur original dans
  `source/Anet ET4.original.orca_printer`.
