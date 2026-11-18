local _, Core = ...
--[[
  Tour.lua (1.51.0, T211) : visite guidée de la fenêtre Quintessence, un tour d'horizon d'une minute.
  Un cadre doré entoure une partie de la fenêtre et une bulle l'explique : Précédent, Suivant, Terminer la visite.
  Chaque module installé et visible pour le joueur a son étape : la visite ouvre son onglet pendant qu'elle l'explique.

  Proposée une fois par personnage, à la première ouverture de la fenêtre après l'accueil des nouveaux membres
  (QuintessenceDB.tourSeenBy[clé du personnage] = true, local au compte, jamais synchronisé ni lu par le site).
  Relance : /quinte visite, Aide > Visite guidée.
  Rien de protégé : nos propres cadres seulement, utilisable en combat. Fermer la fenêtre arrête la visite.
]]
local T = {}
Core.Tour = T
local S = Core.Style
-- Bulle assez large pour ses trois boutons côte à côte (T215 : à 340, Précédent passait sous « Terminer la visite »)
local BUBBLE_W, PAD, GAP = 420, 14, 8
local SKIP_W, PREV_W, NEXT_W = 150, 100, 110
T.BUBBLE_W, T.PAD, T.GAP = BUBBLE_W, PAD, GAP

-- Ce que fait chaque onglet, en une ou deux phrases (le détail reste dans Aide)
T.MODULE_TEXT = {
    craft = 'Qui peut fabriquer quoi dans la guilde. Ouvre chacun de tes métiers une fois en jeu : tes recettes sont partagées toutes seules.',
    caract = 'La fiche de chaque personnage de la guilde : équipement, talents, accès aux raids. La tienne se met à jour toute seule dès le niveau 10.',
    event = 'Le calendrier des raids et événements de la guilde. Un clic sur un événement pour t\'inscrire et choisir ton rôle.',
    bis = 'Note les objets que tu vises et consulte le butin de chaque donjon et raid : la guilde voit quels donjons servent à qui.',
    group = 'Inscris-toi pour un donjon, trouve ton groupe et suis les quêtes du donjon, avec leurs donneurs sur la carte.',
    map = 'SOS et PvP : attaqué par un joueur ennemi, le SOS envoie ta position à la guilde pour qu\'elle vienne t\'aider. Ton journal PvP se remplit tout seul.',
    layer = 'Sur quel layer sont les membres, pour en changer en un clic, avec le suivi des buffs mondiaux.',
    noire = 'Signale un joueur à éviter ou recommande un bon joueur. Un clic droit sur son portrait suffit.',
    ride = 'Le jeu de cartes de la guilde, à jouer entre membres connectés.',
    raid = 'Pour mener les raids : buffs et consommables, composition, appel et butin.',
    recrut = 'Trouver des joueurs sans guilde et préparer les messages de recrutement.',
    annonces = 'Annonces automatiques en guilde, joueurs, journal de guilde, chat et versions : réservé aux officiers.',
    settings = 'Ton profil, l\'apparence de la fenêtre (Moderne, WoW Classic ou Futuriste), sa taille et les voyages.',
    aide = 'Le mode d\'emploi de chaque onglet, en détail. La visite guidée se relance d\'ici.',
}

local function mine() return Core.CanonicalKey(Core.Key()) end
function T.Seen()
    local t = QuintessenceDB and QuintessenceDB.tourSeenBy
    return type(t) == 'table' and t[mine()] == true
end
function T.MarkSeen()
    QuintessenceDB = QuintessenceDB or {}
    if type(QuintessenceDB.tourSeenBy) ~= 'table' then QuintessenceDB.tourSeenBy = {} end
    QuintessenceDB.tourSeenBy[mine()] = true
end
--- Proposer la visite : une fois par personnage, accueil des nouveaux membres déjà vu (ou profil déjà fait).
function T.ShouldOffer()
    if T.Seen() or Core.GuildStatus() ~= 'ok' then return false end
    local P = Core.Profile
    if P and P.WelcomeSeen and not P.WelcomeSeen() then return false end
    return true
end

-- Étapes de cette visite : l'en-tête et la barre, puis un onglet par module visible (ordre de la barre), puis la fin
function T.Steps()
    local UI = Core.UI
    local steps = {
        { id = 'start', title = 'Bienvenue dans Quintessence',
          text = 'Un petit tour d\'horizon de la fenêtre de la guilde, en une minute. Tu peux arrêter quand tu veux et la relancer plus tard.' },
        { id = 'sidebar', target = 'sidebar', side = 'right', title = 'Tous les outils à gauche',
          text = 'La barre de gauche range les onglets par section : Moi, Guilde, Officiers (si tu en es un), Aide & réglages.' },
    }
    for _, entry in ipairs(UI.lastNav or {}) do
        local m = Core.modules[entry.id]
        local text = entry.id == 'home'
            and 'Ce qui compte aujourd\'hui : prochain événement, choses à faire, PvP et raids de la semaine, donjons, SOS.'
            or T.MODULE_TEXT[entry.id] or (m and m.summary and select(2, pcall(m.summary)))
        if type(text) == 'string' and text ~= '' then
            steps[#steps + 1] = { id = 'nav:' .. entry.id, target = 'nav', nav = entry.id, open = entry.id, side = 'right',
                title = entry.id == 'home' and 'Accueil' or (m and m.title or entry.id), text = text }
        end
    end
    local tail = {
        { id = 'search', target = 'search', side = 'below', title = 'Rechercher',
          text = 'Une recette, un joueur, un onglet : tape quelques lettres, Entrée ouvre le premier résultat.' },
        { id = 'bell', target = 'bell', side = 'below', title = 'Notifications',
          text = 'La pastille rouge compte ce qui t\'attend dans les modules : urgences et choses à faire.' },
        { id = 'sync', target = 'sync', side = 'right', title = 'Synchro de la guilde',
          text = 'Tout se partage seul avec les membres connectés qui ont l\'addon. Le point vert dit que la synchro marche.' },
        { id = 'collapse', target = 'collapse', side = 'right', title = 'Replier la barre',
          text = 'Icônes seules : la fenêtre devient plus étroite. Un clic de plus pour la déplier.' },
        { id = 'grip', target = 'grip', side = 'left', title = 'Taille de la fenêtre',
          text = 'Tire ce coin pour agrandir ou réduire la fenêtre (de 50 à 200 %), ou règle-la dans Réglages > Affichage.' },
        { id = 'end', title = 'À toi de jouer !',
          text = 'Bonne aventure dans la guilde. La visite se relance par le bouton « Recommencer la visite » de l\'onglet Aide, ou par /quinte visite.' },
    }
    for _, step in ipairs(tail) do steps[#steps + 1] = step end
    return steps
end

local tour -- cadres de la visite (créés une fois)
local state = { steps = nil, index = 0 }

local function create(window)
    tour = {}
    -- Cadre doré qui entoure la partie expliquée (pulsation douce tant qu'il est visible)
    local ring = S.Box(window, { 0, 0, 0, 0 }, S.colors.gold, 'Frame')
    ring:SetFrameStrata('DIALOG'); ring:SetFrameLevel(400)
    if ring.EnableMouse then ring:EnableMouse(false) end
    local glow = S.Fill(ring, 'BACKGROUND', { S.colors.gold[1], S.colors.gold[2], S.colors.gold[3], 0.10 })
    glow:SetAllPoints()
    local t = 0
    ring:SetScript('OnUpdate', function(self, dt)
        t = t + (tonumber(dt) or 0)
        if self.SetAlpha then self:SetAlpha(0.65 + 0.35 * math.abs(math.sin(t * 2.4))) end
    end)
    ring:Hide()
    tour.ring = ring
    -- Bulle d'explication
    local bubble = S.Box(window, S.colors.panel, S.colors.gold)
    bubble:SetFrameStrata('DIALOG'); bubble:SetFrameLevel(410); bubble:SetWidth(BUBBLE_W)
    if bubble.EnableMouse then bubble:EnableMouse(true) end
    bubble.count = S.Text(bubble, 11, S.colors.muted); bubble.count:SetPoint('TOPRIGHT', -14, -14)
    bubble.title = S.Text(bubble, 15, S.colors.gold); bubble.title:SetPoint('TOPLEFT', 16, -12); bubble.title:SetWidth(BUBBLE_W - 90)
    bubble.text = S.Text(bubble, 12, S.colors.text); bubble.text:SetPoint('TOPLEFT', 16, -40); bubble.text:SetWidth(BUBBLE_W - 32)
    bubble.text:SetWordWrap(true)
    if bubble.text.SetSpacing then bubble.text:SetSpacing(2) end
    bubble.next = S.Button(bubble, 'Suivant', NEXT_W, 26, 'primary'); bubble.next:SetPoint('BOTTOMRIGHT', -PAD, 12)
    bubble.prev = S.Button(bubble, 'Précédent', PREV_W, 26, 'ghost'); bubble.prev:SetPoint('RIGHT', bubble.next, 'LEFT', -GAP, 0)
    bubble.skip = S.Button(bubble, 'Terminer la visite', SKIP_W, 26, 'ghost'); bubble.skip:SetPoint('BOTTOMLEFT', PAD, 12)
    bubble.next:SetScript('OnClick', function() Core.Run('visite guidée', T.Next) end)
    bubble.prev:SetScript('OnClick', function() Core.Run('visite guidée', T.Previous) end)
    bubble.skip:SetScript('OnClick', function() Core.Run('visite guidée', T.Stop) end)
    bubble:Hide()
    tour.bubble = bubble
    if window.HookScript then window:HookScript('OnHide', function() if state.steps then T.Stop() end end) end
end

-- Hauteur de la bulle d'après son texte (FontString:GetStringHeight, 3 lignes à défaut)
local function fitBubble(b)
    local h = b.text.GetStringHeight and b.text:GetStringHeight()
    if type(h) ~= 'number' or h <= 0 then h = 48 end
    b:SetHeight(math.floor(40 + h + 54))
end

local function show()
    local UI = Core.UI
    local window = UI.Element('window')
    if not window then return T.Stop() end
    if not tour then create(window) end
    local step = state.steps[state.index]
    if step.open then UI.Open(step.open) end
    local b, ring = tour.bubble, tour.ring
    b.title:SetText(step.title)
    b.text:SetText(step.text)
    b.count:SetText(state.index .. ' / ' .. #state.steps)
    local first, last = state.index == 1, state.index == #state.steps
    b.next:SetLabel(first and 'Commencer' or (last and 'Terminer' or 'Suivant'))
    S.Call(b.prev, 'SetShown', not first)
    b.skip:SetLabel(first and 'Plus tard' or 'Terminer la visite')
    S.Call(b.skip, 'SetShown', not last)
    fitBubble(b)
    local target = step.target and UI.Element(step.target, step.nav)
    local visible = target and (not target.IsVisible or target:IsVisible())
    b:ClearAllPoints(); ring:ClearAllPoints()
    if visible then
        ring:SetPoint('TOPLEFT', target, 'TOPLEFT', -4, 4); ring:SetPoint('BOTTOMRIGHT', target, 'BOTTOMRIGHT', 4, -4)
        ring:Show()
        if step.side == 'below' then b:SetPoint('TOPRIGHT', target, 'BOTTOMRIGHT', 0, -14)
        elseif step.side == 'left' then b:SetPoint('BOTTOMRIGHT', target, 'TOPLEFT', -10, 10)
        elseif step.target == 'sidebar' then b:SetPoint('TOPLEFT', target, 'TOPRIGHT', 16, -40)
        else b:SetPoint('LEFT', target, 'RIGHT', 16, 0) end
    else
        ring:Hide()
        b:SetPoint('CENTER', window, 'CENTER', 0, 40)
    end
    b:Show()
    state.shown = step.id
end

--- Lance la visite (fenêtre ouverte sur l'accueil si besoin). Marque la visite vue pour ce personnage.
function T.Start()
    local UI = Core.UI
    if Core.GuildBlocked() then return false end
    if not UI.AnyOpen() then UI.Open('home') end
    if not UI.Element('window') then return false end
    T.MarkSeen()
    state.steps, state.index = T.Steps(), 1
    show()
    return true
end
function T.Next()
    if not state.steps then return end
    if state.index >= #state.steps then return T.Stop() end
    state.index = state.index + 1
    show()
end
function T.Previous()
    if not state.steps or state.index <= 1 then return end
    state.index = state.index - 1
    show()
end
function T.Stop()
    state.steps, state.index, state.shown = nil, 0, nil
    if tour then tour.bubble:Hide(); tour.ring:Hide() end
end
function T.Active() return state.steps ~= nil end
--- Étape affichée (tests, diagnostic) : id, numéro, nombre d'étapes.
function T.Current() return state.shown, state.index, state.steps and #state.steps or 0 end
function T.Bubble() return tour and tour.bubble end
function T.Ring() return tour and tour.ring end
