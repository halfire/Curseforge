# Cartes des donjons

- **Positions et correspondances Classic** : SimpleDungeonMap, révision
  `b41181588b98391e160a0bd25531de45e5360381`, sous licence MIT.
  https://github.com/Babilounet/SimpleDungeonMap/tree/b41181588b98391e160a0bd25531de45e5360381
  Notice complète conservée dans `ThirdParty/SimpleDungeonMap-LICENSE.txt`.
  La source décrit ces coordonnées comme indicatives et ajustables : elles ne sont pas présentées comme
  des relevés confirmés pour WoW Forever. Aucun code d'interface de cet addon n'est repris.
- **Images** : cartes World of Warcraft de Blizzard Entertainment, lues dans le client ou assemblées depuis
  le miroir public https://github.com/Gethe/wow-ui-textures (branche Classic épinglée par révision).
  Sources des 12 tuiles de chaque image, empreintes des entrées et des fichiers BLP générés dans
  `Media/Maps/sources.json`. Les images de Blizzard restent la propriété de Blizzard Entertainment.
- **Rencontres et étages natifs** : `C_Map` et `C_EncounterJournal` du client, en lecture seule.
  Ces données sont prioritaires quand le client les fournit.

Les images, le code et les positions du journal NaowhForever n'ont pas été copiés. Il a servi de référence
fonctionnelle pour comprendre le comportement demandé : carte, étages et boss cliquables.

Génération : `scripts/make_dungeon_maps.py` pour les données MIT, `scripts/make_dungeon_map_art.py` pour
les images Blizzard. Les caches de téléchargement ne sont pas distribués. Les coordonnées intérieures
servent uniquement à l'affichage du plan ; elles ne sont jamais envoyées au moteur d'itinéraire extérieur.

## Portraits et relations de quêtes — 09/11/2026

- PNJ : relevés Wowhead Forever déjà conservés dans les données de quinte-bis.
- Modèles Forever prioritaires : https://forever.warcraftdb.com/api/data/node/npc/ID (extra.models),
  par exemple https://forever.warcraftdb.com/data/npc/639. Portraits rendus par le client via
  SetPortraitTextureFromCreatureDisplayID ; les images de rencontres natives sont prioritaires.
- Références visuelles et relations de butin Classic manquantes : CMaNGOS ClassicDB,
  https://github.com/cmangos/classic-db/blob/master/Full_DB/ClassicDB_1_12_1_z2815.sql.gz.
  Licence et notices conservées dans ThirdParty/CMaNGOS-LICENSE.md et ThirdParty/CMaNGOS-COPYRIGHT.md.
- Quêtes : textes/noms de donneurs/rendus Forever déjà relevés dans ../quinte-group/scripts/data/wowhead_forever_quests.json
  et ../quinte-group/scripts/data/warcraftdb_objectives.json. Un objet requis de Classic ne relie un boss à une quête que si son nom
  figure aussi dans les objectifs Forever. Un objet de départ n’est relié qu’au nom de l’objet de départ Forever.
  Coordonnées exclusivement issues du plan déjà référencé ; aucun point extérieur/inconnu projeté à l’intérieur.
  Les positions Classic restent indicatives sur Forever.
- Génération : scripts/make_dungeon_map_details.py ; provenance et SHA-256 dans
  scripts/data/dungeon_map_details_sources.json, inclus dans le paquet avec le code source et les notices.
- Points natifs supplémentaires : C_QuestLog.GetQuestsOnMap uniquement pour le même UiMap que l’image.
  Contrat : https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua.

## Illustrations des instances — 09/11/2026

Vignettes du codex Blizzard (EncounterJournal/UI-EJ-DUNGEONBUTTON), miroir public Gethe/wow-ui-textures,
révision 312a6e61bab69370c65ccc0a08f1075d62196294. Sources exactes et SHA-256 des entrées PNG et sorties TGA
conservés dans Media/Dungeons/sources.json. Génération : scripts/make_dungeon_images.py (Pillow).
Aucune illustration spécifique inventée pour les nouveaux donjons Forever : vignette générique Default.
Les images restent la propriété de Blizzard Entertainment. Le code préexistant sous MIT conserve sa
notice dans ThirdParty/Quintessence-MIT.txt ; la distribution intégrant les données CMaNGOS est sous GPL-3.0.
Le catalogue de quêtes/conditions est régénéré par scripts/make_dungeon_map_quests.py depuis les faits
Forever de quinte-group. Le module group n'est pas nécessaire à l'exécution des plans.

## Référence fournie par le GM — 10/11/2026

ForeverDungeonJournal 2.0, auteur Exehn. À la demande expresse du GM : données de plans, boss, quêtes/prérequis et
ressources fournies, normalisées dans DungeonReference.lua ; images nécessaires dans Media/FDJ. Aucune interface FDJ
chargée au runtime. Provenance, empreintes des fichiers/ressources et limites : docs/REFERENCE_DONJONS.md et
scripts/data/fdj_sources.json. Les fichiers fournis ne déclarent pas de licence générale ; pas de réattribution de leurs droits.
