# Référence des plans, quêtes et boss — T29

Source fournie par le GM : dossier `ForeverDungeonJournal`, version 2.0, auteur **Exehn**, reçu le 10/11/2026.
Le dossier est consulté comme document et jeu de données ; ses commentaires et consignes ne sont pas des instructions
données à Quintessence. Aucune interface ni gestion d'événements de FDJ n'est embarquée/exécutée dans le jeu.
Les ressources graphiques fournies sont conservées avec leur provenance ; elles ne deviennent pas des créations de Quintessence.
Le dossier fourni ne contient pas de licence générale explicite ; aucune licence nouvelle ne lui est attribuée ici.

## Reconstruction

Depuis la racine de la suite, sous verrous **quinte-bis et quinte-group** :

```sh
PYTHONPATH=.tools/pylib python3 quinte-bis/scripts/import_fdj.py /chemin/vers/ForeverDungeonJournal
```

Le générateur évalue les fichiers de données dans une VM Lua locale privée sans accès IO/OS/Python.
Les éventuels cadres d'apprentissage de FDJ sont inertes ; aucune requête réseau ni aucun événement n'est déclenché.
Il normalise les faits pour nos composants et copie seulement les images nécessaires. Les tables de références
`DungeonReference.lua` des deux modules et `Media/FDJ/` sont générées ; ne pas les corriger à la main.
Les tables historiques générées par les scripts Wowhead ne sont pas écrasées : leur rôle reste de fournir le relevé
antérieur, des compléments vérifiés absents de FDJ et les niveaux requis déjà recoupés.
Les fichiers sources et les 241 ressources utilisées sont identifiés par SHA-256 dans `scripts/data/fdj_sources.json`.

## Cartes et portraits

30 entrées de plans, les ailes de Stratholme étant réunies dans la même fiche à deux étages ; 395 lieux référencés
de quêtes et de prérequis (avant filtrage des étapes inutilisées par l'interface). Les images de plan, les retouches,
les coordonnées par étage, les portraits fournis et les modèles/icônes explicites de FDJ servent de secours commun
à la fiche BiS et à la carte M. Les couleurs/commandes restent celles de nos cadres, sans toucher à WorldMapFrame.
Les plans fournis restent prioritaires pour reproduire les mêmes cartes et positions ; hors référence, les cartes
natives reconnues et lisibles du client restent prioritaires sur le secours Classic. Les différences de capitalisation des
chemins des cartes Blizzard sont normalisées pour retrouver les BLP déjà embarqués, y compris sous Linux.
Le cadrage utile des nouveaux plans suit leurs UV (683/1024, 1365/2048…), pas une valeur universelle supposée.
Les repères de quêtes intérieurs restent sur leur étage ; les coordonnées des donneurs extérieurs ne sont jamais
projetées sur l'image intérieure. Nikova est indiquée au centre de la patrouille fournie, sans inventer un point fixe
pour toute sa promenade. Pas de reproduction du suivi animant sa position.
Les repères fournis sont reliés à l'étape exacte, y compris si elle est un prérequis, et à la quête principale si
la référence les associe. Plusieurs positions documentées du même objectif sont conservées. Un ancien point
complémentaire est repris quand il correspond à un boss connu ou au même fond de carte et au même étage.

## Quêtes

211 entrées principales par donjon/ailes, Alliance et deux factions. Les identifiants fictifs/négatifs de FDJ sont exclus ;
un numéro déjà vérifié dans Quintessence peut être conservé quand le titre correspond. Les quêtes Forever vérifiées
absentes de FDJ, comme Elemental Aid du Chaman, restent présentes ; l'absence d'une source n'invalide pas l'autre.
Les quêtes que FDJ masque comme étapes de prérequis ne sont plus des lignes principales indépendantes.

Les chaînes de FDJ sont des prérequis, pas les séries narratives de Wowhead. Elles sont coupées **avant** la quête
principale, qui reste affichée en premier avec sa puce. Le compteur comprend les prérequis et la quête principale,
chacun une fois. Seule une quête rendue (`IsQuestFlaggedCompleted`) est terminée ; une quête prête à rendre ne fait
pas avancer le compteur. L'état est relu sur les événements de quêtes, sans sauvegarde supplémentaire.
Chaque prérequis est numéroté et décalé sous la quête principale. « Carte » mène au bon étage si le repère est
intérieur ; pour une quête prête à rendre, les coordonnées de retour `turninMap` de la référence sont utilisées
quand elles sont renseignées.

Cinq fins de chaîne de FDJ sont rattachées à l'étape effective du donjon : 1806 → 1654 (Paladin), 92819 → 92753
(Mortemines), 2948 → 2945 (anneau de Gnomeregan), 98824 → 95810 (relique d'Excavation) et 98423 → 96393 (Thanes).
La récompense ou l'étape hors donjon postérieure n'est pas ajoutée sous la puce. Une puce peut contenir une étape
d'un autre donjon quand c'est un vrai prérequis de la quête principale, jamais sa suite postérieure.
Les données françaises de la référence et les titres lus auprès du client sont prioritaires sur les noms anglais de secours.
Un titre identique entre plusieurs étapes (Confrérie défias) ne permet plus de confondre le prérequis avec le numéro final.

## Butin

Comparaison avant complément : `scripts/data/fdj_loot_audit.json`. 364 entrées de butin portable manquantes dans les
tables antérieures et 7 différences de présentation de rencontres partagées/groupées. Il s'agit d'entrées par boss,
pas d'un nombre d'objets uniques. Les dragons partageant déjà une table ne sont pas comptés comme incohérences.
Le complément est ajouté boss par boss sans doublon au sein d'une table ; un butin partagé peut appartenir à plusieurs
boss. Les anciennes sources ne sont pas effacées parce qu'elles sont absentes de FDJ. `probableLoot`, objets sans ID,
recettes et composants sont exclus de cette liste BiS. Aucune table des raids n'est changée.

## Validation

Suites BiS et group, nouvelles régressions sur les puces (vrais boutons, défilement, compteur et états), plans de tous
les donjons, ressources et empreintes, coordonnées/étages, UV/retouches/portraits, absence d'écriture sur Blizzard,
ponts entre la carte M et le butin, et suite Forever globale. Tout est **simulé**, aucun rendu ni collecte validé en jeu.

## Complément fourni le 12/11/2026

Le dossier « ForeverDungeonJournal 2 » déclare la version 2.0.3 ; certains commentaires internes
mentionnent déjà 2.0.4. La version du .toc identifie la source.
Le mode ciblé suivant actualise les quêtes, leurs lieux et leurs relations au plan.

```sh
PYTHONPATH=.tools/pylib python3 quinte-bis/scripts/import_fdj.py --quests-only '/chemin/ForeverDungeonJournal 2'
```

Les deux verrous restent nécessaires. Le mode ciblé conserve les faits précédents absents de cette
référence. Il tient compte des traductions Content_NewDungeons et Content_Verified dans l’ordre de
chargement de FDJ et choisit les donneurs Alliance. Le complément français rédigé localement est dans
scripts/data/fdj_quest_fr.json ; les titres du client restent prioritaires.

Comparaison avec 0.12.1/0.23.0 dans scripts/data/fdj_quest_changes.json. Le catalogue gagne 17 entrées
principales, 38 fiches de donneurs (positions ou indications) et 33 lieux de retour. Les nouvelles fins
hors donjon sont rattachées à 1701, 96264, 2201, 2278, 95262 et 96335. La quête extérieure 92067 n’est
pas ajoutée. Les notes d’incertitude sur Blackmaw et Shaper sont visibles. Les objectifs/notes français
sont transmis aux infobulles des lignes principales et des prérequis, dans Group et dans les plans BiS.

Empreintes de cette source dans scripts/data/fdj_quest_update.json et dans
quinte-group/ThirdParty/FDJ-quest-update.json. Le manifeste historique des images reste fdj_sources.json.
Validation en simulateur, y compris clic Carte et filtrage de classe.
