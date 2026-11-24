# LFG Forever 2.2.0

Code source de LFG Forever 2.2.0 par **Artefius**, fourni avec cette tâche.
Licence GPLv3 reproduite dans LICENSE. Les sources Lua et XML modifiées
sont incluses dans les packs. [Projet d’origine](https://www.curseforge.com/wow/addons/lfg-forever/files/9672192).

Modifications Quintessence du 19 novembre 2026 :

- Le module Donjons & Quêtes embarque les panneaux, les réglages, le journal et les avis. Les variables, clés, noms de cadres, réglages et événements propres à l’addon sont isolés des identifiants de l’addon autonome.
- L’onglet du jeu est ouvert pour lancer la recherche. Les activités du filtre sont appliquées localement aux résultats. Le sélecteur de langues de la requête est affiché en lecture seule.
- Les dialogues sont créés par Quintessence. Le lanceur dans la fenêtre Blizzard et l’inscription à UISpecialFrames ont été retirés. L’accès se fait depuis Quintessence, /qlfg, les raccourcis ou l’icône facultative.
- Les réglages et avis sont locaux. Les messages automatiques au clic et l’icône additionnelle sont désactivés par défaut. Traduction française intégrée.

Depuis la 0.36.1, les panneaux et réglages sont affichés dans Donjons & Quêtes. Les raccourcis ouvrent cet onglet et le module suit la taille de la fenêtre Quintessence.

Depuis la 0.36.2, la recherche et les langues reprennent l’appel du code amont au clic. En cas de refus du jeu, Quintessence conserve son onglet et utilise les annonces déjà reçues. Raccourcis et notes d’alliés s’éditent dans ce cadre. Les liens vers les panneaux natifs de WoW ont été retirés.

Depuis la 0.36.3, les panneaux suivent le thème de Quintessence, la notation est masquée et un bouton d’ouverture de Parcourir dans WoW est à nouveau disponible.

La 0.36.7 rétablit la requête au clic et le menu de langues du code fourni. Toutes les langues offertes sont cochées par défaut. Les résultats s’affichent dans Quintessence et le Cherche-groupe natif se charge à l’initiative du jeu.
