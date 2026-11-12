# Quintessence pour CurseForge

Édition membres uniquement : conteneur, Craft, Fiches, BiS, Donjons & Quêtes et Carte/SOS. Les fonctions de guilde exigent l’appartenance à Quintessence. Description prête à copier et création du projet : [PROJET-CURSEFORGE.md](PROJET-CURSEFORGE.md).

Ce dépôt est généré lors de la **promotion d’une Bêta validée en Release**, par `Quintessence/scripts/build_suite.py --channel release --promote-beta --validated-sha256 <empreinte>`. Ne pas modifier les dossiers d’addons à la main. La construction Bêta ne touche jamais ce dépôt.

Le générateur retire Announce.lua, Officers.lua, GuildLog.lua et PvPLog.lua et leurs entrées .toc. Members.lua garde seulement le repérage des destinataires officiers pour l’envoi des observations personnelles des membres. Aucun panneau officier, recrutement ou conduite de raid n’est distribué. Crédits, sources et licences sont conservés.

Pousser un nouveau pack.json Release sur main déclenche Pack CurseForge, environnement `release`. Configurer le secret CF_API_KEY et la variable CF_PROJECT_ID dans **ce dépôt GitHub**. CF_GAME_VERSIONS permet de préciser le nom exact du client. L’envoi refuse une bêta, une composition différente et les fichiers officiers ; il échoue si les réglages manquent. Aucun envoi n’est lancé par une construction locale.

T83 : projet CurseForge 1786751, variable GitHub CF_PROJECT_ID. Le workflow accepte le secret existant CURSEFORGE en repli de CF_API_KEY ; aucune valeur de clé lue ni manipulée. Ancienne variable PROJECT (786751) ignorée.
