# Moteur d'itinéraires

Quintessence appelle l'API publique v1 de **Shortest Path Forever**, de cjber. Aucun code ni donnée de ce moteur
n'est copié dans le conteneur ou les modules Quintessence. Le pack réunit les addons dans des dossiers séparés.

- Projet et documentation : https://github.com/cjber/shortest-path-forever
- Version distribuée : v1.22.48, archive officielle inchangée.
- Sources correspondantes : https://github.com/cjber/shortest-path-forever/tree/v1.22.48
- Licence du moteur : GPL-3.0-or-later ; texte dans `ShortestPathForever/LICENSE`.
- Origine des données de terrain et des transports : `ShortestPathForever/THIRD_PARTY.md`.
- Version, téléchargement et SHA-256 épinglés dans `Navigation/engine.json`.

Le moteur calcule les passages praticables à partir de ses données de terrain Forever et gère le tracé sur les
deux cartes. Les limites de couverture et de précision sont celles de sa version et du client de jeu. Le pont
Quintessence ne remplace jamais un échec par une ligne droite présentée comme un itinéraire.
