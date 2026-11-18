# Consignes CurseForge

Lire ../AGENTS.md et ../agents/REGLES.md, verrou Curseforge avant toute écriture.
Les dossiers d’addons et pack.json sont générés par la promotion d’une bêta validée depuis Quintessence/scripts/build_suite.py. Ne pas les modifier à la main. Seule une tâche Publier avec verrou tout lance la construction ou la promotion réelle.
Aucune bêta sur CurseForge. Liste blanche des huit addons membres (dont quinte-ban et, depuis T230, quinte-ride) et exclusion physique des fichiers officiers dans release_channels.py et dans l’uploader. Members.lua garde le repérage des destinataires, sans outil officier.
Secrets uniquement dans GitHub Actions, jamais lus ni affichés dans les journaux. Instructions propriétaire : PROJET-CURSEFORGE.md. Tant que la première promotion n’a pas eu lieu, l’ancien pack.json est volontairement refusé par le contrôle de validation.
T229 : le contrôle de l’uploader inclut quinte-ban ; tester le vrai pack.json pour éviter une liste autorisée obsolète.

Tests : python3 tests/test_upload.py ; test de promotion isolée dans ../Quintessence/tests/test_release_channels.py.

T83 : projet CurseForge 1786751, variable GitHub CF_PROJECT_ID. Le workflow accepte le secret existant CURSEFORGE en repli de CF_API_KEY ; aucune valeur de clé lue ni manipulée. Ancienne variable PROJECT (786751) ignorée.

T83 : workflow #44 réussi, fichier CurseForge 9582601 (1.44.3, Forever 1.60.1) reçu en Processing. CF_PROJECT_ID configuré dans GitHub à 1786751 ; secret existant CURSEFORGE utilisé sans le lire. Plus de secret manquant ; ne pas recréer de clé ni changer les permissions. Ancienne variable PROJECT ignorée.
