local _, Core = ...
--[[
  Fenêtre commune « Quintessence » : en-tête, barre latérale de navigation (Accueil + un élément par module)
  et zone de contenu. Style : Quintessence.Style, interface moderne (sombre, plate) ou WoW Classic (cadre de dialogue,
  bannière de titre et boutons du jeu), choisie sur l'accueil.
  Taille : la fenêtre garde la même taille sur tous les onglets. Depuis 1.38.1 elle est 30 % plus grande (1290 × 746)
  sans que les textes grossissent : l'échelle reste celle de la 1.37.2 (fenêtre de 992 points ramenée à 864 points de
  large). Depuis 1.39.0 chaque onglet est mis en page pour toute la zone de contenu (1078 × 658, échelle 1) ; un module
  plus ancien, déclaré plus petit, y est affiché à l'échelle 1 et centré (jamais agrandi). Réglable de 50 à 200 %
  (QuintessenceDB.windowScale, accueil ou /quinte taille), sans jamais dépasser l'écran.
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]
local UI = {}
Core.UI = UI
local S = Core.Style
local SIDE_W, HEADER_H, PAD, NAV_H = 176, 52, 18, 32
-- Fenêtre 30 % plus grande que 992 × 574 (1.37.2), à la même échelle : plus de place, textes de la même taille
local TOTAL_W, TOTAL_H = 1290, 746
local CONTENT_W, CONTENT_H = TOTAL_W - SIDE_W - 2 * PAD, TOTAL_H - HEADER_H - 2 * PAD -- 1078 × 658
local HOME_W = CONTENT_W
local MODULE_W, MODULE_H = CONTENT_W, CONTENT_H -- taille déclarée par les modules (width, height)
local BASE_SCALE = 864 / 992 -- échelle à 100 % : celle de la 1.37.2, où les textes ont la bonne taille
local REFERENCE_W = TOTAL_W * BASE_SCALE -- largeur à 100 % : 1123 points
local SCALE_MIN, SCALE_MAX, SCALE_STEP, SCALE_DEFAULT = 50, 200, 10, 100
local SCREEN_MARGIN, MIN_FIT = 32, 0.25
local HOME_ICON = 'Interface\\Icons\\INV_Misc_Note_01'
UI.CONTENT_W, UI.CONTENT_H, UI.MODULE_W, UI.MODULE_H, UI.REFERENCE_W = CONTENT_W, CONTENT_H, MODULE_W, MODULE_H, REFERENCE_W

local frame, content, home, sidebar, locked
local nav, panels = {}, {}
local current

--- Taille choisie, en pour cent (50 à 200 par pas de 10, 100 par défaut).
function UI.ScalePercent()
    local pct = tonumber(QuintessenceDB and QuintessenceDB.windowScale) or SCALE_DEFAULT
    pct = math.floor(pct / SCALE_STEP + 0.5) * SCALE_STEP
    return math.max(SCALE_MIN, math.min(SCALE_MAX, pct))
end

--- Échelle de la fenêtre : la taille choisie, réduite si la fenêtre ne tient pas à l'écran.
function UI.WindowScale()
    local scale = BASE_SCALE * UI.ScalePercent() / 100
    local screenW = UIParent.GetWidth and UIParent:GetWidth()
    local screenH = UIParent.GetHeight and UIParent:GetHeight()
    if type(screenW) == 'number' and type(screenH) == 'number' and screenW > 0 and screenH > 0 then
        local room = math.min((screenW - SCREEN_MARGIN) / TOTAL_W, (screenH - SCREEN_MARGIN) / TOTAL_H)
        scale = math.min(scale, math.max(MIN_FIT, room))
    end
    return scale
end

local function fit()
    frame:SetSize(TOTAL_W, TOTAL_H)
    content:SetSize(CONTENT_W, CONTENT_H)
    frame:SetScale(UI.WindowScale())
end

-- Panneau d'un module : sa mise en page (width × height déclarés) à l'échelle 1, centrée ; réduite seulement si elle
-- dépasse la zone de contenu (les textes gardent la même taille dans tous les onglets)
local function place(id, panel)
    local m = Core.modules[id]
    local w = tonumber(m and m.width) or MODULE_W
    local h = tonumber(m and m.height) or MODULE_H
    if w <= 0 or h <= 0 then w, h = MODULE_W, MODULE_H end
    panel:ClearAllPoints()
    panel:SetSize(w, h)
    panel:SetScale(math.min(1, CONTENT_W / w, CONTENT_H / h))
    panel:SetPoint('CENTER', content, 'CENTER', 0, 0)
end

--- Change la taille (pour cent) ; la fenêtre ouverte est redessinée et recentrée.
function UI.SetScalePercent(pct)
    pct = tonumber(pct)
    if not pct then return false end
    QuintessenceDB = QuintessenceDB or {}
    QuintessenceDB.windowScale = math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor(pct / SCALE_STEP + 0.5) * SCALE_STEP))
    if QuintessenceDB.windowScale == SCALE_DEFAULT then QuintessenceDB.windowScale = nil end
    if frame then
        fit()
        frame:ClearAllPoints(); frame:SetPoint('CENTER')
        if home and home.sizeValue then home.sizeValue:SetText(UI.ScalePercent() .. ' %') end
    end
    return true
end

function UI.StepScale(delta) return UI.SetScalePercent(UI.ScalePercent() + delta * SCALE_STEP) end

local function syncText()
    local state = Core.sync and Core.sync:Status()
    if not state then return 'Synchro non démarrée', S.colors.muted end
    if not state.enabled then return 'Synchro coupée', S.colors.red end
    if state.queued > 0 then return 'Synchro : ' .. state.queued .. ' en attente', S.colors.gold end
    return 'Synchro active', S.colors.mint
end

local function renderSidebar()
    local label, color = syncText()
    sidebar.syncLabel:SetText(label)
    sidebar.syncDot:SetColorTexture(unpack(color))
end

-- ---------------------------------------------------------------------------
-- Accueil : une carte par module
-- ---------------------------------------------------------------------------

local function renderHome()
    local list = Core:ModuleList()
    for i, card in ipairs(home.cards) do
        local m = list[i]
        if m then
            local ok, summary = true, nil
            if m.summary then ok, summary = Core.Run('résumé ' .. m.id, m.summary) end
            card.module = m.id
            card.icon:SetTexture(m.icon or HOME_ICON)
            card.title:SetText(m.title)
            card.version:SetText(m.version and ('v' .. m.version) or '')
            card.summary:SetText((ok and type(summary) == 'string' and summary ~= '') and summary or '')
            card:Show()
        else card:Hide() end
    end
    home.empty:SetShown(#list == 0)

    -- Centre de commandement (Command Center - Guild OS)
    local nMembers = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local isRaid = IsInRaid and IsInRaid()
    local groupStatus = nMembers > 0 and (isRaid and (nMembers .. ' en raid') or (nMembers .. ' en groupe')) or 'Solo'
    local sosActive = QuinteMapDB and QuinteMapDB.activeSOS
    local layerNum = QuinteLayerDB and QuinteLayerDB.currentLayer and ('Layer ' .. QuinteLayerDB.currentLayer) or 'Layer —'

    local hubText = '|c' .. S.hex.mint .. 'Groupe :|r ' .. groupStatus
    -- Sans quinte-layer (édition CurseForge), pas de layer affiché
    if Core.modules.layer then hubText = hubText .. '  |c' .. S.hex.muted .. '·|r  |c' .. S.hex.gold .. layerNum .. '|r' end
    if sosActive and sosActive.player then
        hubText = hubText .. '  |c' .. S.hex.muted .. '·|r  |c' .. S.hex.red .. 'SOS ' .. Core.Safe(sosActive.player) .. ' (' .. Core.Safe(sosActive.zone or '') .. ')|r'
    else
        hubText = hubText .. '  |c' .. S.hex.muted .. '·|r  |c' .. S.hex.mint .. 'Guilde opérationnelle|r'
    end
    if home.hubStatus then home.hubStatus:SetText(hubText) end

    local label, color = syncText()
    home.syncState:SetText(label); home.syncState:SetTextColor(unpack(color))
    home.toggle:SetLabel(QuintessenceDB and QuintessenceDB.syncEnabled == false and 'Activer la synchro' or 'Couper la synchro')
    local chosen = QuintessenceDB and S.ThemeName(QuintessenceDB.theme) or S.theme
    for name, button in pairs(home.themes) do button:SetActive(name == chosen) end
    if home.sizeValue then home.sizeValue:SetText(UI.ScalePercent() .. ' %') end
    renderSidebar()
end

local function createHome()
    home = CreateFrame('Frame', nil, content)
    home:SetAllPoints(content)
    local title = S.Text(home, 20, S.colors.text); title:SetPoint('TOPLEFT', 0, -2); title:SetText('Bienvenue dans Quintessence')
    local intro = S.Text(home, 12, S.colors.muted); intro:SetPoint('TOPLEFT', 0, -28); intro:SetWidth(HOME_W); intro:SetWordWrap(true)
    intro:SetText('Centre de commandement et de gestion de la guilde Quintessence. Les outils sont connectés en temps réel avec toute la guilde.')

    -- Bandeau Command Hub (Guild OS)
    local hubBanner = S.Box(home, S.colors.raised, S.colors.line)
    hubBanner:SetPoint('TOPLEFT', 0, -48); hubBanner:SetSize(HOME_W, 26)
    home.hubStatus = S.Text(hubBanner, 11); home.hubStatus:SetPoint('LEFT', 12, 0); home.hubStatus:SetWidth(HOME_W - 24)

    local heading = S.Heading(home, 'Modules installés'); heading:SetPoint('TOPLEFT', 0, -82)
    home.cards = {}
    -- Trois colonnes : 12 onglets au plus (10 modules, Officiers, Aide) sur 4 lignes, au-dessus des cartes du bas
    local cardW = (HOME_W - 24) / 3
    for i = 1, 15 do
        local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
        local card = S.Box(home, S.colors.panel, S.colors.line, 'Button')
        card:SetSize(cardW, 54)
        card:SetPoint('TOPLEFT', col * (cardW + 12), -100 - line * 60)
        card.icon = card:CreateTexture(nil, 'ARTWORK'); card.icon:SetSize(26, 26); card.icon:SetPoint('TOPLEFT', 10, -10)
        card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        card.title = S.Text(card, 13, S.colors.text); card.title:SetPoint('TOPLEFT', 46, -9)
        card.version = S.Text(card, 10, S.colors.muted, 'RIGHT'); card.version:SetPoint('TOPRIGHT', -10, -11)
        card.summary = S.Text(card, 10, S.colors.muted); card.summary:SetPoint('TOPLEFT', 46, -26); card.summary:SetPoint('RIGHT', -10, 0)
        card.summary:SetWordWrap(true); card.summary:SetJustifyV('TOP'); card.summary:SetHeight(22)
        local hl = S.Fill(card, 'HIGHLIGHT', { 1, 1, 1, 0.04 }); hl:SetAllPoints()
        card:SetScript('OnClick', function(self) if self.module then UI.Open(self.module) end end)
        home.cards[i] = card
    end
    home.empty = S.Text(home, 12, S.colors.muted); home.empty:SetPoint('TOPLEFT', 0, -110); home.empty:SetWidth(HOME_W); home.empty:SetWordWrap(true)
    home.empty:SetText('Aucun module installé. Ajoute les modules voulus à côté de Quintessence dans Interface/AddOns.')
    local syncCard = S.Box(home, S.colors.panel, S.colors.line)
    syncCard:SetPoint('BOTTOMLEFT', 0, 0); syncCard:SetSize(HOME_W, 64)
    local syncHeading = S.Heading(syncCard, 'Synchro de guilde'); syncHeading:SetPoint('TOPLEFT', 14, -10)
    home.syncState = S.Text(syncCard, 12); home.syncState:SetPoint('TOPLEFT', 14, -30)
    home.toggle = S.Button(syncCard, '', 150, 26, 'ghost'); home.toggle:SetPoint('RIGHT', -14, 0)
    home.toggle:SetScript('OnClick', function()
        Core:SetSyncEnabled(QuintessenceDB.syncEnabled == false)
        Core.Run('accueil', renderHome)
    end)
    local now = S.Button(syncCard, 'Synchroniser maintenant', 180, 26, 'primary'); now:SetPoint('RIGHT', home.toggle, 'LEFT', -10, 0)
    now:SetScript('OnClick', function() if Core.sync then Core.sync:Announce(); Core.Print('Synchro demandée aux membres connectés.') end end)
    -- Choix de l'interface : moderne (actuelle) ou WoW Classic ; le changement recharge l'interface
    local themeCard = S.Box(home, S.colors.panel, S.colors.line)
    themeCard:SetPoint('BOTTOMLEFT', 0, 72); themeCard:SetSize(HOME_W, 64)
    local themeHeading = S.Heading(themeCard, 'Interface'); themeHeading:SetPoint('TOPLEFT', 14, -10)
    local themeHint = S.Text(themeCard, 11, S.colors.muted); themeHint:SetPoint('TOPLEFT', 14, -30); themeHint:SetWidth(220)
    themeHint:SetWordWrap(true); themeHint:SetText('Apparence (l’interface se recharge).')
    -- Taille de la fenêtre : 100 % = 1123 points de large, textes à la taille de la 1.37.2
    local sizeHeading = S.Heading(themeCard, 'Taille'); sizeHeading:SetPoint('TOPLEFT', 250, -10)
    local smaller = S.Button(themeCard, '−', 26, 24, 'ghost'); smaller:SetPoint('TOPLEFT', 250, -30)
    smaller:SetScript('OnClick', function() UI.StepScale(-1) end)
    home.sizeValue = S.Text(themeCard, 12, S.colors.text, 'CENTER'); home.sizeValue:SetWidth(56)
    home.sizeValue:SetPoint('LEFT', smaller, 'RIGHT', 2, 0)
    local larger = S.Button(themeCard, '+', 26, 24, 'ghost'); larger:SetPoint('LEFT', home.sizeValue, 'RIGHT', 2, 0)
    larger:SetScript('OnClick', function() UI.StepScale(1) end)
    local reset = S.Button(themeCard, '100 %', 56, 24, 'ghost'); reset:SetPoint('LEFT', larger, 'RIGHT', 8, 0)
    reset:SetScript('OnClick', function() UI.SetScalePercent(SCALE_DEFAULT) end)
    home.themes = {}
    local right = -14
    for i = #S.THEME_ORDER, 1, -1 do
        local name = S.THEME_ORDER[i]
        local button = S.Button(themeCard, S.THEMES[name].label, 130, 26, 'ghost'); button:SetPoint('RIGHT', right, 0)
        button:SetScript('OnClick', function() Core.SetTheme(name); Core.Run('accueil', renderHome) end)
        home.themes[name] = button
        right = right - 140
    end
    home:SetScript('OnShow', function() Core.Run('accueil', renderHome) end)
    panels.home = home
end

-- ---------------------------------------------------------------------------
-- Barre latérale
-- ---------------------------------------------------------------------------

local function layoutNav()
    for _, item in pairs(nav) do item:Hide() end
    local list = { { id = 'home', title = 'Accueil', icon = HOME_ICON } }
    for _, m in ipairs(Core:ModuleList()) do if m.create then list[#list + 1] = m end end
    for i, entry in ipairs(list) do
        local item = nav[entry.id]
        if not item then
            item = S.Row(sidebar, sidebar.rowWidth or SIDE_W, NAV_H)
            item.icon = item:CreateTexture(nil, 'ARTWORK'); item.icon:SetSize(18, 18); item.icon:SetPoint('LEFT', 14, 0)
            item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            item.label = S.Text(item, 12); item.label:SetPoint('LEFT', 40, 0)
            item:SetScript('OnClick', function() UI.Open(entry.id) end)
            nav[entry.id] = item
        end
        item.icon:SetTexture(entry.icon or HOME_ICON)
        item.label:SetText(entry.title)
        -- Classique : onglets en texte or, blanc pour l'onglet ouvert (comme le jeu)
        item.label:SetTextColor(unpack(entry.id == current and S.colors.text or (S.IsClassic() and S.colors.gold or S.colors.muted)))
        item:ClearAllPoints()
        item:SetPoint('TOPLEFT', sidebar.rowX or 0, -10 - (i - 1) * (NAV_H + 1))
        item:SetSelected(entry.id == current)
        item:Show()
    end
end

local function startMoving() frame:StartMoving() end
local function stopMoving() frame:StopMovingOrSizing() end

local function createFrame()
    frame = CreateFrame('Frame', 'QuintessenceFrame', UIParent, BackdropTemplateMixin and 'BackdropTemplate' or nil)
    frame:SetPoint('CENTER')
    frame:SetFrameStrata('HIGH')
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag('LeftButton')
    frame:SetScript('OnDragStart', startMoving)
    frame:SetScript('OnDragStop', stopMoving)
end

-- Interface moderne : cadre plat sombre, en-tête avec blason, barre latérale pleine hauteur
local function createModern()
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
        frame:SetBackdropColor(unpack(S.colors.bg)); frame:SetBackdropBorderColor(unpack(S.colors.line))
    end
    -- En-tête
    local crest = frame:CreateTexture(nil, 'ARTWORK'); crest:SetSize(30, 30); crest:SetPoint('TOPLEFT', 14, -11)
    crest:SetTexture('Interface\\Icons\\INV_Misc_Head_Dragon_01'); crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = S.Text(frame, 16, S.colors.gold); title:SetPoint('TOPLEFT', 54, -12); title:SetText('QUINTESSENCE')
    local subtitle = S.Text(frame, 10, S.colors.muted); subtitle:SetPoint('TOPLEFT', 54, -31); subtitle:SetText('Guilde PvE de l’Alliance · World of Warcraft: Forever')
    local close = S.Button(frame, '×', 28, 28, 'ghost'); close:SetPoint('TOPRIGHT', -12, -12)
    close.label:SetFont(STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF', 18, '')
    close:SetScript('OnClick', function() frame:Hide() end)
    local divider = S.Fill(frame, 'ARTWORK', S.colors.line); divider:SetPoint('TOPLEFT', 1, -HEADER_H); divider:SetPoint('TOPRIGHT', -1, -HEADER_H); divider:SetHeight(1)

    -- Barre latérale
    sidebar = S.Box(frame, S.colors.side, S.colors.side)
    sidebar:SetPoint('TOPLEFT', 1, -HEADER_H - 1); sidebar:SetPoint('BOTTOMLEFT', 1, 1); sidebar:SetWidth(SIDE_W)
end

-- Interface WoW Classic : cadre de dialogue du jeu (bordure dorée, fond de pierre sombre), bannière de titre,
-- bouton de fermeture du jeu, barre latérale en encart à bordure d'infobulle
local function createClassic()
    local T = S.TEX
    if frame.SetBackdrop then
        frame:SetBackdrop(S.CLASSIC_WINDOW)
        frame:SetBackdropColor(1, 1, 1, 1); frame:SetBackdropBorderColor(1, 1, 1, 1)
    end
    -- Fond noir sous la texture de pierre, pour la lisibilité (et si la texture manquait au client)
    local under = frame:CreateTexture(nil, 'BACKGROUND', nil, -8); under:SetPoint('TOPLEFT', 11, -12); under:SetPoint('BOTTOMRIGHT', -12, 11)
    under:SetColorTexture(0, 0, 0, 0.55)
    -- Bannière de titre à cheval sur le bord supérieur
    local banner = frame:CreateTexture(nil, 'ARTWORK'); banner:SetTexture(T.dialogHeader); banner:SetSize(300, 64); banner:SetPoint('TOP', 0, 12)
    local title = S.Text(frame, 14, S.colors.gold, 'CENTER'); title:SetPoint('TOP', banner, 'TOP', 0, -14); title:SetText('Quintessence')
    local subtitle = S.Text(frame, 10, S.colors.muted, 'CENTER'); subtitle:SetPoint('TOP', 0, -32); subtitle:SetText('Guilde PvE de l’Alliance · World of Warcraft: Forever')
    local crest = frame:CreateTexture(nil, 'ARTWORK'); crest:SetSize(30, 30); crest:SetPoint('TOPLEFT', 18, -16)
    crest:SetTexture('Interface\\Icons\\INV_Misc_Head_Dragon_01'); crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Bouton de fermeture du jeu (croix dorée sur fond rouge)
    local close = CreateFrame('Button', nil, frame); close:SetSize(32, 32); close:SetPoint('TOPRIGHT', -5, -5)
    close:SetNormalTexture(T.closeUp); close:SetPushedTexture(T.closeDown); close:SetHighlightTexture(T.closeHighlight, 'ADD')
    close:SetScript('OnClick', function() frame:Hide() end)

    -- Barre latérale en encart
    sidebar = S.Box(frame, S.colors.side, S.colors.line)
    sidebar:SetPoint('TOPLEFT', 12, -HEADER_H); sidebar:SetPoint('BOTTOMLEFT', 12, 12); sidebar:SetWidth(SIDE_W - 8)
    sidebar.rowWidth, sidebar.rowX = SIDE_W - 16, 4
end

local function create()
    createFrame()
    if S.IsClassic() then createClassic() else createModern() end
    sidebar.syncDot = sidebar:CreateTexture(nil, 'ARTWORK'); sidebar.syncDot:SetSize(8, 8); sidebar.syncDot:SetPoint('BOTTOMLEFT', 16, 52)
    sidebar.syncLabel = S.Text(sidebar, 11, S.colors.muted); sidebar.syncLabel:SetPoint('LEFT', sidebar.syncDot, 'RIGHT', 8, 0)
    local syncButton = S.Button(sidebar, 'Synchroniser', (sidebar.rowWidth and SIDE_W - 8 or SIDE_W) - 28, 28, 'ghost')
    syncButton:SetPoint('BOTTOMLEFT', 14, 14)
    syncButton:SetScript('OnClick', function()
        if Core.sync then Core.sync:Announce(); Core.Print('Synchro demandée aux membres connectés.') end
        renderSidebar()
    end)

    content = CreateFrame('Frame', nil, frame)
    content:SetPoint('TOPLEFT', SIDE_W + PAD, -HEADER_H - PAD)
    createHome()
    frame:Hide()
end

-- Personnage hors de la guilde Quintessence : fenêtre réduite à un message, aucun module ouvert
local function showLocked(reason, guildName)
    if not locked then
        locked = CreateFrame('Frame', nil, content)
        locked:SetAllPoints(content)
        local icon = locked:CreateTexture(nil, 'ARTWORK'); icon:SetSize(48, 48); icon:SetPoint('TOP', 0, -60)
        icon:SetTexture('Interface\\Icons\\INV_Misc_Head_Dragon_01'); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        locked.title = S.Text(locked, 18, S.colors.gold, 'CENTER'); locked.title:SetPoint('TOP', icon, 'BOTTOM', 0, -16)
        locked.title:SetText('Réservé aux membres de ' .. Core.GUILD)
        locked.text = S.Text(locked, 12, S.colors.muted, 'CENTER'); locked.text:SetPoint('TOP', locked.title, 'BOTTOM', 0, -14)
        locked.text:SetWidth(HOME_W - 80); locked.text:SetWordWrap(true)
        panels.locked = locked
    end
    locked.text:SetText((reason == 'other' and ('Ce personnage est dans la guilde « ' .. Core.Safe(guildName or '?') .. ' ».')
        or 'Ce personnage n’est dans aucune guilde.')
        .. '\n\nLes addons Quintessence (synchro, SOS, quêtes…) ne fonctionnent que pour les membres de la guilde '
        .. Core.GUILD .. '. Rejoins-nous sur quintessence-community.fr, ils s’activeront tout seuls dès ton arrivée dans la guilde.')
    current = 'locked'
    for key, panel in pairs(panels) do if key ~= 'locked' then panel:Hide() end end
    for _, item in pairs(nav) do item:Hide() end
    fit()
    renderSidebar()
    frame:Show()
    locked:Show()
end

--- Ouvre la fenêtre sur un module (id) ou l'accueil ('home').
function UI.Open(id)
    if not frame then create() end
    local blocked, guildName = Core.GuildBlocked()
    if blocked then return showLocked(blocked, guildName) end
    if id == 'locked' then id = nil end
    id = id or (QuintessenceDB and QuintessenceDB.lastTab) or 'home'
    local m = Core.modules[id]
    if id ~= 'home' and not (m and m.create and (not m.visible or m.visible())) then id = 'home'; m = nil end
    if m and not panels[id] then
        local ok, panel = Core.Run('création ' .. id, m.create, content)
        if not ok or type(panel) ~= 'table' then id = 'home'; m = nil else panels[id] = panel end
    end
    current = id
    if QuintessenceDB then QuintessenceDB.lastTab = id end
    for key, panel in pairs(panels) do if key ~= id then panel:Hide() end end
    fit()
    if id ~= 'home' then place(id, panels[id]) end
    layoutNav()
    renderSidebar()
    frame:Show()
    panels[id]:Show()
    if m and m.refresh then Core.Run('onglet ' .. id, m.refresh) end
    if id == 'home' then Core.Run('accueil', renderHome) end
end

--- Ouvre ou ferme la fenêtre ; avec un id, bascule sur ce module s'il n'est pas déjà affiché.
function UI.Toggle(id)
    if frame and frame:IsShown() and (id == nil or id == current) then frame:Hide() else UI.Open(id) end
end

function UI.IsOpen(id) return frame ~= nil and frame:IsShown() and current == id end

-- Arrivée dans la guilde (ou départ) pendant que la fenêtre est ouverte : on la redessine
function UI.OnGuildChanged()
    if not (frame and frame:IsShown()) then return end
    local blocked = Core.GuildBlocked()
    if blocked or current == 'locked' then UI.Open(blocked and nil or 'home') end
end

function UI.OnModulesChanged()
    if frame and frame:IsShown() then layoutNav() end
end

-- Bouton du menu des addons (Retail) déclaré dans le .toc
function Quintessence_Toggle()
    Core.Run('fenêtre', UI.Toggle)
end
