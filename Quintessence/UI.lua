local _, Core = ...
--[[
  Fenêtre commune « Quintessence » : en-tête, barre latérale de navigation (Accueil + un élément par module)
  et zone de contenu qui prend la taille du panneau du module. Style : Quintessence.Style, interface moderne (sombre,
  plate) ou WoW Classic (cadre de dialogue, bannière de titre et boutons du jeu), choisie sur l'accueil.
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]
local UI = {}
Core.UI = UI
local S = Core.Style
local SIDE_W, HEADER_H, PAD, NAV_H = 176, 52, 18, 32
local HOME_W, HOME_H = 680, 600
local HOME_ICON = 'Interface\\Icons\\INV_Misc_Note_01'

local frame, content, home, sidebar, locked
local nav, panels = {}, {}
local current

local function moduleSize(id)
    if id == 'home' then return HOME_W, HOME_H end
    local m = Core.modules[id]
    return (m and m.width) or HOME_W, (m and m.height) or HOME_H
end

local function fit(width, height)
    local totalW, totalH = SIDE_W + PAD + width + PAD, HEADER_H + PAD + height + PAD
    frame:SetSize(totalW, totalH)
    content:SetSize(width, height)
    local screenW = UIParent.GetWidth and UIParent:GetWidth() or totalW
    local screenH = UIParent.GetHeight and UIParent:GetHeight() or totalH
    if type(screenW) == 'number' and type(screenH) == 'number' and screenW > 0 and screenH > 0 then
        frame:SetScale(math.min(1, (screenW - 40) / totalW, (screenH - 40) / totalH))
    end
end

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
    for i = 1, 10 do
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        local card = S.Box(home, S.colors.panel, S.colors.line, 'Button')
        card:SetSize((HOME_W - 12) / 2, 54)
        card:SetPoint('TOPLEFT', col * ((HOME_W - 12) / 2 + 12), -100 - line * 60)
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
    local themeHint = S.Text(themeCard, 11, S.colors.muted); themeHint:SetPoint('TOPLEFT', 14, -30); themeHint:SetWidth(300)
    themeHint:SetWordWrap(true); themeHint:SetText('Change l’apparence de toutes les fenêtres (l’interface se recharge).')
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
    fit(HOME_W, 320)
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
    if id ~= 'home' and not (m and m.create) then id = 'home'; m = nil end
    if m and not panels[id] then
        local ok, panel = Core.Run('création ' .. id, m.create, content)
        if not ok or type(panel) ~= 'table' then id = 'home'; m = nil else panels[id] = panel end
    end
    current = id
    if QuintessenceDB then QuintessenceDB.lastTab = id end
    for key, panel in pairs(panels) do if key ~= id then panel:Hide() end end
    fit(moduleSize(id))
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
