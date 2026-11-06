local _, Core = ...
--[[
  Help.lua : onglet « Aide », pour tous : ce que fait chaque partie de l'addon et comment s'en servir, en langage simple.
  Un sujet n'apparaît que si son module est installé (et visible pour le joueur).
]]
local H = {}
Core.Help = H
local S = Core.Style
local W, HEIGHT, ROWS = 760, 440, 11

H.TOPICS = {
    { id = 'start', title = 'Bien démarrer', text = 'Quintessence réunit les outils de la guilde dans une seule fenêtre. Tape /quinte ou clique sur le bouton près de la mini-carte, puis choisis un onglet à gauche.\n\nTout se partage seul avec les membres connectés qui ont l\'addon : tu n\'as rien à envoyer. Plus il y a de membres connectés, plus les listes sont complètes.\n\nLes addons ne marchent que dans la guilde Quintessence.' },
    { id = 'craft', module = 'craft', title = 'Craft', text = 'Trouve qui peut fabriquer un objet dans la guilde.\n\n1. Ouvre chaque métier une fois en jeu : tes recettes sont alors enregistrées et partagées.\n2. Dans l\'onglet Craft, clique sur un métier à gauche, puis choisis une catégorie dans la liste déroulante, ou tape un nom dans la recherche.\n3. Clique sur une recette pour voir ses composants et les artisans, en ligne d\'abord.\n\nDans le chat : /qcraft suivi d\'un mot.' },
    { id = 'caract', module = 'caract', title = 'Fiches', text = 'La fiche de chaque personnage de la guilde : équipement, caractéristiques, talents, accès aux raids et métiers.\n\nTa fiche se met à jour toute seule. Elle est partagée à partir du niveau 10 : les personnages plus bas n\'apparaissent pas.\n\nLe bouton en haut à droite passe de la vue fiche à la vue liste. Une fiche non mise à jour depuis un mois disparaît, sauf au niveau 60.\n\nL\'addon note aussi la date et la zone de tes passages de niveau et le temps passé par zone, pour de futures statistiques de pex de la guilde.' },
    { id = 'bis', module = 'bis', title = 'BiS & donjons', text = 'Note les objets que tu vises, pour savoir quels donjons servent à qui.\n\nMa liste : une ligne par emplacement.\nButin des boss : clique sur la carte d\'une instance. Clic gauche sur un objet pour l\'ajouter à ta liste, clic droit pour l\'enlever.\nBesoins par donjon : les donjons classés selon le nombre de membres qui y cherchent quelque chose.\n\nSi tu ramasses un objet absent de la table d\'un boss, il y est ajouté et partagé à la guilde.' },
    { id = 'group', module = 'group', title = 'Donjons & Quêtes', text = 'Pour monter tes groupes et ne rater aucune quête.\n\nDonjons : choisis un donjon à gauche, puis « S\'inscrire » pour dire que tu cherches un groupe. Les inscrits s\'affichent à droite, avec un bouton pour les inviter.\nAfficher l\'entrée : place un repère sur la carte.\nQuêtes : la liste de celles du donjon. Le bouton Carte place un repère sur le donneur, et « Lieux des quêtes » les écrit toutes dans le chat.\n\nL\'onglet Quêtes partagées montre qui a les mêmes quêtes que toi.' },
    { id = 'map', module = 'map', title = 'SOS & Camp', text = 'SOS : attaqué par un joueur ennemi ? Tape /qsos ou clique sur le bouton SOS. La guilde reçoit ta position et peut venir t\'aider.\n\nVendetta : la liste de ceux qui nous ont tués. Une alerte sonne si l\'un d\'eux passe près de toi.\n\nCamp : pose un campement avec /qmap camp, ou approche-toi d\'un feu. Il s\'affiche sur la carte de tous les membres, pour venir profiter du bonus de repos.' },
    { id = 'event', module = 'event', title = 'Événements', text = 'Le calendrier des raids et événements de la guilde. Clique sur un événement pour t\'inscrire et choisir ton rôle.' },
    { id = 'raid', module = 'raid', title = 'Raid', text = 'Pour les raids : vérification des buffs et consommables, composition du groupe, appel et butin.' },
    { id = 'layer', module = 'layer', title = 'Layers', text = 'Montre sur quel layer sont les membres et permet d\'en changer en un clic, avec le suivi des world buffs.' },
    { id = 'ride', module = 'ride', title = 'Ride the Bus', text = 'Un jeu de cartes à jouer entre membres de la guilde.' },
    { id = 'recrut', module = 'recrut', title = 'Recrutement', text = 'Aide à trouver des joueurs sans guilde et à préparer les messages. Chaque envoi demande un clic.' },
    { id = 'officers', module = 'annonces', title = 'Officiers', text = 'Réservé aux deux rangs les plus hauts de la guilde.\n\nAnnonces : messages automatiques en guilde.\nJoueurs : notes et vitesse de leveling. Le relevé a lieu toutes les 5 minutes et chaque officier garde le sien.\nChat : le canal officier du jeu.\nVersions : qui doit mettre à jour ses addons.\nPack complet : le lien de téléchargement.' },
    { id = 'update', title = 'Mises à jour', text = 'Quand une nouvelle version existe, un message te prévient dans le chat.\n\n1. Ferme le jeu.\n2. Télécharge le pack sur quintessence-community.fr, page Addons.\n3. Dézippe-le dans le dossier Interface/AddOns de WoW Forever, en remplaçant les anciens dossiers.\n\nUn souci ? Demande à un officier.' },
}
--- Sujets à montrer à ce joueur.
function H.Topics()
    local out = {}
    for _, topic in ipairs(H.TOPICS) do
        local m = topic.module and Core.modules[topic.module]
        if not topic.module or (m and (not m.visible or m.visible())) then out[#out + 1] = topic end
    end
    return out
end

local panel
local selected = 'start'
local function render()
    local topics = H.Topics()
    local current = topics[1]
    for _, topic in ipairs(topics) do if topic.id == selected then current = topic end end
    selected = current.id
    for i, row in ipairs(panel.rows) do
        local topic = topics[i]
        if topic then
            row.topic = topic.id
            row.label:SetText(topic.title)
            row:SetSelected(topic.id == selected)
            row:Show()
        else row.topic = nil; row:Hide() end
    end
    panel.title:SetText(current.title)
    panel.text:SetText(current.text)
end
function H.Refresh()
    if panel and panel:IsVisible() then Core.Run('aide', render) end
end
function H.Select(id)
    selected = id
    H.Refresh()
end
local function create(parent)
    panel = CreateFrame('Frame', nil, parent); panel:SetAllPoints(parent)
    local box = S.Box(panel, S.colors.panel, S.colors.line); box:SetPoint('TOPLEFT', 0, 0); box:SetSize(190, HEIGHT)
    panel.rows = {}
    for i = 1, #H.TOPICS do
        local row = S.Row(box, 188, 32); row:SetPoint('TOPLEFT', 1, -2 - (i - 1) * 33)
        row.label = S.Text(row, 12); row.label:SetPoint('LEFT', 12, 0); row.label:SetWidth(168)
        row:SetScript('OnClick', function(self) if self.topic then H.Select(self.topic) end end)
        panel.rows[i] = row
    end
    local right = S.Box(panel, S.colors.panel, S.colors.line); right:SetPoint('TOPLEFT', 202, 0); right:SetSize(W - 202, HEIGHT)
    panel.title = S.Text(right, 16); panel.title:SetPoint('TOPLEFT', 20, -18)
    panel.text = S.Text(right, 13, S.colors.text); panel.text:SetPoint('TOPLEFT', 20, -50); panel.text:SetWidth(W - 242); panel.text:SetWordWrap(true)
    if panel.text.SetSpacing then panel.text:SetSpacing(3) end
    panel:SetScript('OnShow', function() Core.Run('aide', render) end)
    panel:Hide()
    return panel
end
Core:RegisterModule({
    id = 'aide', title = 'Aide', order = 950, icon = 'Interface\\Icons\\INV_Misc_QuestionMark', version = Core.version, width = W, height = HEIGHT,
    create = function(parent) return create(parent) end,
    refresh = function() H.Refresh() end,
    summary = function() return 'Comment fonctionne chaque onglet' end,
})
