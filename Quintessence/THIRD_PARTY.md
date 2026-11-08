# Moteur de voyage intégré

Quintessence embarque une adaptation de **Shortest Path Forever v1.22.48**, de **cjber**, sous
**GPL-3.0-or-later**. Les crédits et la licence de l’auteur restent dans Navigation/Engine/LICENSE ;
COPYING contient la GPL appliquée à la distribution combinée. LICENSE conserve la licence MIT du code
original Quintessence, qui reste disponible séparément sous ces termes. Les bibliothèques conservent leurs licences.

- Projet : https://github.com/cjber/shortest-path-forever
- Sources amont correspondantes : https://github.com/cjber/shortest-path-forever/tree/v1.22.48
- Archive officielle, version et SHA-256 : Navigation/engine.json.
- Origine des données terrain/transports : Navigation/Engine/THIRD_PARTY.md (conservé).
- Empreintes de tous les fichiers amont et liste des adaptations : Navigation/Engine/UPSTREAM.json.
- Reconstruction : QUINTE_NAV_ENGINE_ZIP=/chemin/archive.zip python3 scripts/vendor_navigation.py.

Adaptations Quintessence, 08/11/2026 : espace Lua séparé du conteneur ; noms des cadres et des données préfixés
QuintessenceTravel ; chemins des médias internes ; chargement XML par l’addon principal ; stockage dans
QuintessenceDB ; interface et commandes autonomes remplacées par Réglages > Voyages ; filtres indépendants
carte/minicarte ; identification des repères du moteur pour éviter une boucle de guidage automatique ;
erreurs remontées aussi au diagnostic Quintessence. Les échanges de statistiques, de mesures de transport,
les promotions d’addons et les intégrations /way, TomTom et RestedXP ne sont pas chargés.

Les sources Lua, XML, données, médias et scripts de construction sont inclus dans le paquet installé. Les
sources modifiées sont dans Navigation/Engine, avec les fichiers de licence et d’origine conservés.
Aucun code ni donnée de Naowh n’a été repris. Les limites de couverture/précision restent celles du terrain amont
et du client. Aucun trajet impossible n’est remplacé par une ligne droite présentée comme praticable.
