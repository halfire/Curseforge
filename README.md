# Quintessence pour CurseForge

Addons de la guilde **Quintessence**, réservés à ses membres (ils ne s'activent que dans la guilde) :
Craft, Fiches, BiS & donjons, Donjons & Quêtes, SOS et Versions.

Ce dépôt est généré : ne pas modifier les dossiers d'addons à la main. Ils sont réécrits par
`Quintessence/scripts/build_suite.py` ; pousser un nouveau `pack.json` sur `main` envoie la version sur CurseForge.

Réglages GitHub (Settings → Secrets and variables → Actions) : secret `CF_API_KEY`, variable `CF_PROJECT_ID` et, si
besoin, variable `CF_GAME_VERSIONS` (nom exact de la version du jeu). Sans jeton ou sans projet, l'envoi échoue (croix rouge).
