# Création du projet CurseForge

## Champs prêts à copier

- Nom : **Quintessence**
- Résumé : **Les outils des membres de la guilde Quintessence pour WoW Forever : métiers, fiches, BiS, donjons, quêtes et entraide. Interface en français.**
- Jeu : World of Warcraft ; type : Addons. Choisir le type de version correspondant réellement à Forever dans la liste proposée ; ne pas sélectionner Retail ou Classic par approximation si Forever manque.
- Catégorie principale : Guild ; catégories secondaires pertinentes si proposées : Professions, Quests & Leveling, Map & Minimap.
- Licence de la distribution combinée : **GNU GPL v3 ou ultérieure** (moteur de voyage GPL ; code original MIT et licences tierces conservés). Voir Quintessence/COPYING et THIRD_PARTY.md.
- Site : https://quintessence-community.fr
- Langue : français.
- Icône : utiliser le blason de la guilde dont tu détiens les droits ; éviter les logos Blizzard et les images sans autorisation.

## Description du projet

Quintessence rassemble les outils d’entraide des membres de notre guilde PvE de l’Alliance sur WoW Forever, sur un serveur PvP. Toute l’interface est en français.

**Un seul téléchargement, plusieurs outils :**

- **Craft** : consulter les métiers, les recettes connues et leurs composants ; retrouver un artisan de la guilde.
- **Fiches** : consulter les personnages, leur équipement, leurs métiers et leurs accès aux raids et donjons.
- **BiS et butins** : préparer ses besoins, explorer les butins et les plans de donjons.
- **Donjons & Quêtes** : retrouver les quêtes de donjon et préparer une sortie avec les compagnons de guilde.
- **SOS et Camp** : signaler une difficulté et partager les points utiles entre membres.
- **Voyages et Versions** : préparer un itinéraire et suivre les versions installées.

Ouvre la fenêtre avec **/quinte** ou son bouton de minicarte. Le conteneur Quintessence est obligatoire ; les modules sont facultatifs. Les échanges entre membres passent par les messages d’addon du jeu. Les fonctions de guilde s’activent uniquement pour les membres de **Quintessence** : cette suite n’est pas destinée à toutes les guildes.

L’édition CurseForge contient uniquement les outils membres. Les outils de recrutement, de conduite de raid et les panneaux des officiers ne font pas partie de cette édition.

**Mises à jour :** CurseForge reçoit uniquement les versions Release validées. Les versions Bêta restent disponibles sur notre site et dans le canal Bêta de Quinte-sync. Quinte-sync est facultatif ; aucune clé de site n’est nécessaire pour installer l’édition membres.

L’addon ne contacte pas Internet. Quinte-sync peut, si tu actives la synchronisation, transmettre les fichiers de données du jeu au site de la guilde. Les informations et droits d’accès sont décrits dans notre politique de confidentialité : https://quintessence-community.fr/confidentialite.

Le moteur de voyage intégré provient de **Shortest Path Forever**, par **cjber**, sous GPL-3.0-or-later. Sources, modifications, crédits et licences sont inclus dans le téléchargement (Quintessence/THIRD_PARTY.md et COPYING). World of Warcraft appartient à Blizzard Entertainment ; ce projet communautaire n’est pas affilié à Blizzard.

## À faire une seule fois par le propriétaire

1. Se connecter au [portail auteurs](https://authors.curseforge.com/#/projects/create/choose-game), créer le projet World of Warcraft / Addons, puis copier les champs et la description ci-dessus. Ajouter des captures réelles de l’interface membres, sans données privées.
2. Noter le **Project ID** numérique affiché dans le tableau de bord du projet.
3. Dans GitHub, dépôt **halfire/Curseforge**, Settings → Secrets and variables → Actions : ajouter le secret **CF_API_KEY** avec le jeton généré dans ton compte CurseForge, et la variable **CF_PROJECT_ID** avec le numéro du projet. Ne jamais envoyer ce jeton dans un chat ni le déposer dans un fichier.
4. Facultatif : créer l’environnement GitHub **release** et désigner un validateur dans ses règles de protection (si ton offre GitHub le permet). Le workflow utilise cet environnement. L’autorisation de publication reste distincte du test d’une bêta.
5. Si la détection de version Forever échoue, régler **CF_GAME_VERSIONS** avec le nom exact proposé par CurseForge. Si Forever n’est pas proposé, demander sa prise en charge au support ; l’envoi s’arrête plutôt que de choisir un autre client.
6. Après validation de la bêta et promotion (voir README), pousser le dépôt généré : Pack CurseForge s’exécute au changement de pack.json. On peut aussi lancer Actions → Pack CurseForge → Run workflow. Le premier fichier déclenche l’examen du projet ; l’envoi réussi ne signifie pas que la modération a déjà approuvé le projet.
7. Vérifier le fichier dans Files, son statut et le contenu du ZIP. Le premier fichier doit être une **Release** pour la diffusion normale dans l’application.

Le code et les documents sont prêts localement. Le projet distant et ses secrets ne sont pas créés par ces fichiers. La première promotion générera l’archive conforme au nouveau contrôle ; l’ancien pack.json ne porte pas la preuve de validation et sera refusé par l’envoi.

Sources officielles consultées le 12 novembre 2026 :
- [Créer et soumettre un projet](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project)
- [API d’envoi](https://support.curseforge.com/support/solutions/articles/9000197321)
- [Conseils de soumission](https://support.curseforge.com/support/solutions/articles/9000199552)
