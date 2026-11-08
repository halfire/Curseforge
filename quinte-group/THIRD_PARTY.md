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
