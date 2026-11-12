# Consignes CurseForge

Lire ../AGENTS.md et ../agents/REGLES.md, verrou Curseforge avant toute écriture.
Les dossiers d’addons et pack.json sont générés par la promotion d’une bêta validée depuis Quintessence/scripts/build_suite.py. Ne pas les modifier à la main. Seule une tâche Publier avec verrou tout lance la construction ou la promotion réelle.
Aucune bêta sur CurseForge. Liste blanche des six addons membres et exclusion physique des fichiers officiers dans release_channels.py et dans l’uploader. Members.lua garde le repérage des destinataires, sans outil officier.
Secrets uniquement dans GitHub Actions, jamais lus ni affichés dans les journaux. Instructions propriétaire : PROJET-CURSEFORGE.md. Tant que la première promotion n’a pas eu lieu, l’ancien pack.json est volontairement refusé par le contrôle de validation.
Tests : python3 tests/test_upload.py ; test de promotion isolée dans ../Quintessence/tests/test_release_channels.py.
