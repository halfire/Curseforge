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
local SIDE_W, HEADER_H, PAD, NAV_H = 176, 52, 18, 30
local SIDE_COLLAPSED = 52 -- barre latérale repliée : icônes seules (QuintessenceDB.sidebarCollapsed)
local HEAD_H = 22         -- titre de section de la barre latérale
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
local SUBTITLE = 'Guilde PvE de l’Alliance · World of Warcraft: Forever'
UI.CONTENT_W, UI.CONTENT_H, UI.MODULE_W, UI.MODULE_H, UI.REFERENCE_W = CONTENT_W, CONTENT_H, MODULE_W, MODULE_H, REFERENCE_W

local frame, content, home, sidebar, locked, header
local display -- panneau Réglages > Affichage (UI.CreateDisplayPanel)
local nav, panels = {}, {}
local current
-- Appel d'une méthode facultative (cadres simulés des tests, clients anciens)
local function call(f, method, ...)
    if type(f) ~= 'table' and type(f) ~= 'userdata' then return nil end
    local fn = f[method]
    if type(fn) == 'function' then return fn(f, ...) end
end
local function num(v, default) return type(v) == 'number' and v or default end
local crumbs = {}   -- onglet choisi dans chaque module (S.Tabs, UI.SetCrumb), pour l'en-tête « Module › onglet »
local headings = {} -- titres de section de la barre latérale

-- Sections de la barre latérale (1.50.0). Un module peut choisir la sienne (section = 'moi' | 'guilde' | 'officiers' |
-- 'outils' dans RegisterModule) ; sinon la table ci-dessous, puis « Guilde ».
UI.SECTIONS = {
    { id = 'moi', title = 'Moi' },
    { id = 'guilde', title = 'Guilde' },
    { id = 'officiers', title = 'Officiers' },
    { id = 'outils', title = 'Aide & réglages' },
}
local SECTION_OF = { home = 'moi', caract = 'moi', raid = 'officiers', recrut = 'officiers', annonces = 'officiers',
    settings = 'outils', aide = 'outils' }
function UI.SectionOf(m)
    local id = type(m) == 'table' and m.id or m
    local wanted = type(m) == 'table' and m.section
    for _, sec in ipairs(UI.SECTIONS) do if sec.id == wanted then return wanted end end
    return SECTION_OF[id] or 'guilde'
end

--- Barre latérale repliée (icônes seules) ?
function UI.IsCollapsed() return QuintessenceDB ~= nil and QuintessenceDB.sidebarCollapsed == true end
local function sideWidth() return UI.IsCollapsed() and SIDE_COLLAPSED or SIDE_W end
local function totalWidth() return sideWidth() + CONTENT_W + 2 * PAD end

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
    frame:SetSize(totalWidth(), TOTAL_H)
    content:SetSize(CONTENT_W, CONTENT_H)
    content:ClearAllPoints(); content:SetPoint('TOPLEFT', sideWidth() + PAD, -HEADER_H - PAD)
    if sidebar then sidebar:SetWidth(sideWidth() - num(sidebar.inset, 0)) end
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
function UI.SetScalePercent(pct, keepCorner)
    pct = tonumber(pct)
    if not pct then return false end
    QuintessenceDB = QuintessenceDB or {}
    QuintessenceDB.windowScale = math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor(pct / SCALE_STEP + 0.5) * SCALE_STEP))
    if QuintessenceDB.windowScale == SCALE_DEFAULT then QuintessenceDB.windowScale = nil end
    if frame then
        if keepCorner and UI.KeepTopLeft then UI.KeepTopLeft(fit) else fit(); frame:ClearAllPoints(); frame:SetPoint('CENTER') end
        if display then UI.RefreshDisplay() end
    end
    return true
end

function UI.StepScale(delta) return UI.SetScalePercent(UI.ScalePercent() + delta * SCALE_STEP) end

local function syncText()
    -- Le blocage guilde prime sur la file : des messages préparés peuvent rester en attente sans jamais partir.
    local guild = Core.GuildStatus()
    if guild == 'none' or guild == 'other' then return 'Synchro : hors guilde', S.colors.red end
    if guild == 'pending' then return 'Synchro : lecture guilde', S.colors.gold end
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
    -- Barre repliée : seulement le point d'état de la synchro (détail en infobulle) et le bouton pour déplier
    local collapsed = UI.IsCollapsed()
    call(sidebar.syncLabel, 'SetShown', not collapsed)
    if sidebar.syncButton then S.Call(sidebar.syncButton, 'SetShown', not collapsed) end
    if sidebar.collapse then
        sidebar.collapse:SetLabel(collapsed and '»' or '«')
        sidebar.collapse:ClearAllPoints()
        if collapsed then sidebar.collapse:SetPoint('BOTTOM', 0, 14) else sidebar.collapse:SetPoint('BOTTOMRIGHT', -10, 52 - 9) end
    end
    call(sidebar.syncDot, 'ClearAllPoints')
    if collapsed then sidebar.syncDot:SetPoint('BOTTOM', 0, 52) else sidebar.syncDot:SetPoint('BOTTOMLEFT', 16, 52) end
end

-- ---------------------------------------------------------------------------
-- Accueil en tuiles (Home.lua) et Réglages > Affichage (interface, taille, synchro)
-- ---------------------------------------------------------------------------

local function renderHome()
    if Core.Home then Core.Home.Render() end
    renderSidebar()
end

local function createHome()
    home = Core.Home.Create(content)
    panels.home = home
end

--- Réglages > Affichage : état des boutons (thème, taille, synchro).
function UI.RefreshDisplay()
    if not display then return end
    local label, color = syncText()
    display.syncState:SetText(label); display.syncState:SetTextColor(unpack(color))
    display.toggle:SetLabel(QuintessenceDB and QuintessenceDB.syncEnabled == false and 'Activer la synchro' or 'Couper la synchro')
    local chosen = QuintessenceDB and S.ThemeName(QuintessenceDB.theme) or S.theme
    for name, button in pairs(display.themes) do button:SetActive(name == chosen) end
    display.sizeValue:SetText(UI.ScalePercent() .. ' %')
    if display.sides then
        display.sides.collapsed:SetActive(UI.IsCollapsed()); display.sides.open:SetActive(not UI.IsCollapsed())
    end
    if frame then renderSidebar() end
end

local function section(parent, y, heading, hint)
    local box = S.Box(parent, S.colors.panel, S.colors.line)
    box:SetPoint('TOPLEFT', 0, y); box:SetSize(CONTENT_W, 92)
    local h = S.Heading(box, heading); h:SetPoint('TOPLEFT', 14, -12)
    local text = S.Text(box, 11, S.colors.muted); text:SetPoint('TOPLEFT', 14, -32); text:SetWidth(500); text:SetWordWrap(true)
    text:SetText(hint)
    return box
end

--- Panneau Réglages > Affichage (1.49.0) : ce qui était en bas de l'ancien accueil.
function UI.CreateDisplayPanel(parent)
    display = CreateFrame('Frame', nil, parent)
    display:SetSize(CONTENT_W, CONTENT_H)
    local title = S.Text(display, 20, S.colors.text); title:SetPoint('TOPLEFT', 0, -2); title:SetText('Réglages — Affichage')
    local intro = S.Text(display, 12, S.colors.muted); intro:SetPoint('TOPLEFT', 0, -32); intro:SetWidth(CONTENT_W); intro:SetWordWrap(true)
    intro:SetText('Apparence et taille de la fenêtre, et synchro des addons avec les membres connectés.')

    -- Choix de l'interface : moderne ou WoW Classic ; le changement recharge l'interface
    local themeBox = section(display, -64, 'Interface', 'Apparence de la fenêtre. L’interface se recharge pour l’appliquer.')
    display.themes = {}
    local right = -14
    for i = #S.THEME_ORDER, 1, -1 do
        local name = S.THEME_ORDER[i]
        local button = S.Button(themeBox, S.THEMES[name].label, 124, 28, 'ghost'); button:SetPoint('RIGHT', right, 0)
        button:SetScript('OnClick', function() Core.SetTheme(name); UI.RefreshDisplay() end)
        display.themes[name] = button
        right = right - 132
    end

    -- Taille de la fenêtre : 100 % = 1123 points de large, textes à la taille de la 1.37.2
    local sizeBox = section(display, -168, 'Taille', 'De 50 à 200 %. La fenêtre ne dépasse jamais l’écran. Aussi : /quinte taille.')
    local reset = S.Button(sizeBox, '100 %', 64, 28, 'ghost'); reset:SetPoint('RIGHT', -14, 0)
    reset:SetScript('OnClick', function() UI.SetScalePercent(SCALE_DEFAULT) end)
    local larger = S.Button(sizeBox, '+', 32, 28, 'ghost'); larger:SetPoint('RIGHT', reset, 'LEFT', -10, 0)
    larger:SetScript('OnClick', function() UI.StepScale(1) end)
    display.sizeValue = S.Text(sizeBox, 13, S.colors.text, 'CENTER'); display.sizeValue:SetWidth(64)
    display.sizeValue:SetPoint('RIGHT', larger, 'LEFT', -4, 0)
    local smaller = S.Button(sizeBox, '−', 32, 28, 'ghost'); smaller:SetPoint('RIGHT', display.sizeValue, 'LEFT', -4, 0)
    smaller:SetScript('OnClick', function() UI.StepScale(-1) end)

    -- Synchro de guilde
    local syncBox = section(display, -272, 'Synchro de guilde', 'Échange des fiches, recettes et inscriptions avec les membres connectés.')
    display.syncState = S.Text(syncBox, 12); display.syncState:SetPoint('TOPLEFT', 14, -56)
    display.toggle = S.Button(syncBox, '', 170, 28, 'ghost'); display.toggle:SetPoint('RIGHT', -14, 0)
    display.toggle:SetScript('OnClick', function()
        Core:SetSyncEnabled(QuintessenceDB.syncEnabled == false)
        UI.RefreshDisplay()
    end)
    local now = S.Button(syncBox, 'Synchroniser maintenant', 200, 28, 'primary'); now:SetPoint('RIGHT', display.toggle, 'LEFT', -10, 0)
    now:SetScript('OnClick', function() if Core.sync then Core.sync:Announce(); Core.Print('Synchro demandée aux membres connectés.') end end)
    -- Barre latérale (1.50.0) : dépliée (noms des modules) ou repliée (icônes seules, fenêtre plus étroite)
    local sideBox = section(display, -376, 'Barre latérale', 'Repliée, elle ne montre que les icônes : la fenêtre est plus étroite. Aussi : bouton « en bas de la barre.')
    display.sides = {}
    local wide = S.Button(sideBox, 'Repliée', 150, 28, 'ghost'); wide:SetPoint('RIGHT', -14, 0)
    wide:SetScript('OnClick', function() UI.SetCollapsed(true); UI.RefreshDisplay() end)
    local open = S.Button(sideBox, 'Dépliée', 150, 28, 'ghost'); open:SetPoint('RIGHT', wide, 'LEFT', -10, 0)
    open:SetScript('OnClick', function() UI.SetCollapsed(false); UI.RefreshDisplay() end)
    display.sides.collapsed, display.sides.open = wide, open
    display:SetScript('OnShow', function() Core.Run('affichage', UI.RefreshDisplay) end)
    UI.RefreshDisplay()
    return display
end

-- ---------------------------------------------------------------------------
-- Barre latérale
-- ---------------------------------------------------------------------------

local function navTooltip(item)
    if not (UI.IsCollapsed() and GameTooltip and item.title) then return end
    GameTooltip:SetOwner(item, 'ANCHOR_RIGHT'); GameTooltip:SetText(item.title, (S.OnDark and S.OnDark('gold') or S.colors.gold)[1], (S.OnDark and S.OnDark('gold') or S.colors.gold)[2], (S.OnDark and S.OnDark('gold') or S.colors.gold)[3])
    GameTooltip:Show()
end

local function heading(id, title)
    local h = headings[id]
    if not h then
        h = S.Heading(sidebar, title)
        h.rule = S.Fill(sidebar, 'ARTWORK', S.colors.line); call(h.rule, 'SetHeight', 1)
        headings[id] = h
    end
    return h
end

-- Entrées groupées par section (Moi, Guilde, Officiers, Aide & réglages) ; repliée : icônes seules, sections séparées
-- par un filet, nom du module en infobulle.
local function layoutNav()
    for _, item in pairs(nav) do item:Hide() end
    for _, h in pairs(headings) do call(h, 'Hide'); call(h.rule, 'Hide') end
    local collapsed = UI.IsCollapsed()
    local rowX = num(sidebar.rowX, 0)
    local rowW = sideWidth() - num(sidebar.inset, 0) - 2 * rowX
    local groups = {}
    for _, sec in ipairs(UI.SECTIONS) do groups[sec.id] = {} end
    groups.moi[1] = { id = 'home', title = 'Accueil', icon = HOME_ICON }
    for _, m in ipairs(Core:ModuleList()) do
        if m.create then local list = groups[UI.SectionOf(m)]; list[#list + 1] = m end
    end
    local y = -8
    UI.lastNav = {} -- ordre affiché { { id, section, y }… } (diagnostic et tests)
    for _, sec in ipairs(UI.SECTIONS) do
        local list = groups[sec.id]
        if #list > 0 then
            local h = heading(sec.id, sec.title)
            call(h, 'ClearAllPoints'); call(h.rule, 'ClearAllPoints')
            if collapsed then
                if y < -8 then
                    call(h.rule, 'SetPoint', 'TOPLEFT', rowX + 10, y - 6); call(h.rule, 'SetWidth', rowW - 20); call(h.rule, 'Show')
                    y = y - 12
                end
            else
                call(h, 'SetPoint', 'TOPLEFT', rowX + 14, y - 8); call(h, 'Show')
                y = y - HEAD_H
            end
            for _, entry in ipairs(list) do
                local item = nav[entry.id]
                if not item then
                    item = S.Row(sidebar, rowW, NAV_H)
                    item.icon = S.Icon and S.Icon(item, 18) or item:CreateTexture(nil, 'ARTWORK')
                    item.icon:SetSize(18, 18); item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    item.label = S.Text(item, 12)
                    item:SetScript('OnClick', function() UI.Open(entry.id) end)
                    item:SetScript('OnEnter', navTooltip)
                    item:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
                    nav[entry.id] = item
                end
                item.title = entry.title
                item:SetSize(rowW, NAV_H)
                call(item.icon, 'ClearAllPoints'); item.icon:SetPoint('LEFT', collapsed and math.floor((rowW - 18) / 2) or 14, 0)
                item.icon:SetTexture(entry.icon or HOME_ICON)
                call(item.label, 'ClearAllPoints'); item.label:SetPoint('LEFT', 40, 0); item.label:SetText(entry.title)
                call(item.label, 'SetShown', not collapsed)
                -- Classique : onglets en texte or, blanc pour l'onglet ouvert (comme le jeu)
                item.label:SetTextColor(unpack(entry.id == current and S.colors.text or (S.IsClassic() and S.colors.gold or S.colors.muted)))
                item:ClearAllPoints()
                item:SetPoint('TOPLEFT', rowX, y)
                item:SetSelected(entry.id == current)
                item:Show()
                UI.lastNav[#UI.lastNav + 1] = { id = entry.id, section = sec.id, y = y }
                y = y - (NAV_H + 1)
            end
        end
    end
end

--- Plus de pastilles dans la barre latérale (T223, demande du GM) : les notifications sont sur la cloche et sur le
--- bouton de la minicarte. Gardée vide pour les modules qui l'appelleraient encore.
function UI.SetNavBadge() end

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
    local subtitle = S.Text(frame, 11, S.colors.muted); subtitle:SetPoint('TOPLEFT', 54, -31); subtitle:SetText(SUBTITLE)
    frame.crumb = subtitle
    local close = S.Button(frame, '×', 28, 28, 'ghost'); close:SetPoint('TOPRIGHT', -12, -12)
    frame.closeButton = close
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
    local subtitle = S.Text(frame, 10, S.colors.muted, 'CENTER'); subtitle:SetPoint('TOP', 0, -32); subtitle:SetText(SUBTITLE)
    frame.crumb = subtitle
    local crest = frame:CreateTexture(nil, 'ARTWORK'); crest:SetSize(30, 30); crest:SetPoint('TOPLEFT', 18, -16)
    crest:SetTexture('Interface\\Icons\\INV_Misc_Head_Dragon_01'); crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Bouton de fermeture du jeu (croix dorée sur fond rouge)
    local close = CreateFrame('Button', nil, frame); close:SetSize(32, 32); close:SetPoint('TOPRIGHT', -5, -5)
    close:SetNormalTexture(T.closeUp); close:SetPushedTexture(T.closeDown); close:SetHighlightTexture(T.closeHighlight, 'ADD')
    close:SetScript('OnClick', function() frame:Hide() end)
    frame.closeButton = close

    -- Barre latérale en encart
    sidebar = S.Box(frame, S.colors.side, S.colors.line)
    sidebar:SetPoint('TOPLEFT', 12, -HEADER_H); sidebar:SetPoint('BOTTOMLEFT', 12, 12); sidebar:SetWidth(SIDE_W - 8)
    sidebar.rowWidth, sidebar.rowX, sidebar.inset = SIDE_W - 16, 4, 8
end

-- ---------------------------------------------------------------------------
-- En-tête : fil d'Ariane, recherche, notifications ; coin d'agrandissement ; repli de la barre (1.50.0)
-- ---------------------------------------------------------------------------

local function moduleTitle(id)
    if id == 'home' then return 'Accueil' end
    local m = Core.modules[id]
    return m and m.title or id
end

local function renderCrumb()
    if not (frame and frame.crumb) then return end
    if not current or current == 'home' or current == 'locked' then frame.crumb:SetText(SUBTITLE); return end
    local text = moduleTitle(current)
    if crumbs[current] then text = text .. '  ›  ' .. crumbs[current] end
    frame.crumb:SetText(text)
end

--- Onglet affiché par un module (S.Tabs le fait tout seul avec options.module) : « Module › onglet » dans l'en-tête.
function UI.SetCrumb(id, label)
    if type(id) ~= 'string' then return end
    crumbs[id] = type(label) == 'string' and label ~= '' and label or nil
    if id == current then renderCrumb() end
end
function UI.Crumb() return frame and frame.crumb and frame.crumb:GetText() end

-- Notifications : ce que les modules signalent déjà à l'accueil (bandeaux d'urgence et lignes « À faire »),
-- rassemblé derrière un seul bouton de l'en-tête et recopié sur le bouton de la minicarte (T223).
local MAX_NOTES = 10
function UI.Notifications()
    local list, perModule = {}, {}
    if not (Core.Home and Core.Home.Collect) or Core.GuildBlocked() then return list, perModule end
    local ok, data = pcall(Core.Home.Collect, true)
    if not ok or type(data) ~= 'table' then return list, perModule end
    for _, a in ipairs(data.alerts or {}) do list[#list + 1] = { text = a.text, tone = 'red', action = a.action, module = a.module } end
    for _, t in ipairs(data.todo or {}) do
        list[#list + 1] = { text = t.text, tone = t.tone, action = t.action, module = t.module }
        if t.module and t.module ~= 'home' then perModule[t.module] = (perModule[t.module] or 0) + 1 end
    end
    return list, perModule
end

local function renderBell()
    if not (header and header.bell) then return end
    local list, perModule = UI.Notifications()
    header.notes = list
    local n = #list
    header.bell.badge:SetText(n > 99 and '99+' or tostring(n)); S.Call(header.bell.badge, 'SetShown', n > 0)
    call(header.bell.icon, 'SetDesaturated', n == 0)
    if Core.MinimapRefreshNotes then Core.MinimapRefreshNotes(list) end
    if header.notePanel and header.notePanel:IsShown() then UI.ShowNotifications(true) end
end
UI.RefreshNotifications = renderBell
function UI.NotificationPanel() return header and header.notePanel end

function UI.ShowNotifications(keep)
    local panel = header.notePanel
    if not panel then
        panel = S.Box(frame, S.colors.panel, S.colors.line)
        call(panel, 'SetFrameStrata', 'DIALOG'); call(panel, 'SetFrameLevel', 500); panel:SetWidth(380); call(panel, 'EnableMouse', true)
        panel:SetPoint('TOPRIGHT', header.bell, 'BOTTOMRIGHT', 0, -6)
        panel.title = S.Heading(panel, 'Notifications'); panel.title:SetPoint('TOPLEFT', 12, -10)
        panel.empty = S.Text(panel, 12, S.colors.muted); panel.empty:SetPoint('TOPLEFT', 12, -32); panel.empty:SetText('Rien à signaler pour le moment.')
        panel.rows = {}
        panel:Hide() -- un cadre neuf est visible : sans cela le premier clic le fermerait aussitôt
        header.notePanel = panel
    end
    if not keep and panel:IsShown() then panel:Hide(); return end
    local list = header.notes or {}
    for _, row in ipairs(panel.rows) do row:Hide() end
    for i = 1, math.min(#list, MAX_NOTES) do
        local note = list[i]
        local row = panel.rows[i]
        if not row then
            row = S.Row(panel, 356, 30)
            row.dot = S.Fill(row, 'ARTWORK', S.colors.gold); row.dot:SetSize(6, 6); row.dot:SetPoint('LEFT', 8, 0)
            row.text = S.Text(row, 12); row.text:SetPoint('LEFT', 22, 0); row.text:SetWidth(326)
            panel.rows[i] = row
        end
        row:SetPoint('TOPLEFT', 12, -28 - (i - 1) * 31)
        row.dot:SetColorTexture(unpack(S.Tone(note.tone == 'text' and 'gold' or note.tone)))
        row.text:SetText(note.text)
        row:SetScript('OnClick', function()
            panel:Hide()
            if type(note.action) == 'function' then Core.Run('notification', note.action)
            elseif note.module and note.module ~= 'home' then UI.Open(note.module) end
        end)
        row:Show()
    end
    S.Call(panel.empty, 'SetShown', #list == 0)
    panel:SetHeight(40 + math.max(1, math.min(#list, MAX_NOTES)) * 31)
    panel:Show()
end

-- Recherche commune : noms de modules, puis ce que chaque module sait chercher (champ search(texte) de RegisterModule,
-- qui renvoie { { text, hint, icon, action }… }). Rien n'est envoyé ni enregistré.
local MAX_RESULTS = 12
local function plain(text) return (tostring(text or ''):lower():gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')) end
function UI.Search(query)
    query = plain(query):match('^%s*(.-)%s*$')
    local out = {}
    if #query < 2 or Core.GuildBlocked() then return out end
    for _, m in ipairs(Core:ModuleList()) do
        if m.create and plain(m.title):find(query, 1, true) then
            out[#out + 1] = { text = m.title, hint = 'Ouvrir le module', icon = m.icon, action = function() UI.Open(m.id) end }
        end
    end
    for _, m in ipairs(Core:ModuleList()) do
        if type(m.search) == 'function' and #out < MAX_RESULTS then
            local ok, found = Core.Run('recherche ' .. m.id, m.search, query)
            if ok and type(found) == 'table' then
                for i = 1, math.min(#found, 5) do
                    local r = found[i]
                    if type(r) == 'table' and type(r.text) == 'string' and #out < MAX_RESULTS then
                        r.hint = r.hint or m.title; r.icon = r.icon or m.icon; r.module = m.id
                        out[#out + 1] = r
                    end
                end
            end
        end
    end
    return out
end

local function renderSearch()
    local box, panel = header.search, header.results
    local list = UI.Search(box:GetText() or '')
    header.found = list
    if #list == 0 and #(box:GetText() or '') < 2 then panel:Hide(); return end
    for _, row in ipairs(panel.rows) do row:Hide() end
    for i, r in ipairs(list) do
        local row = panel.rows[i]
        if not row then
            row = S.Row(panel, 316, 30)
            row.icon = S.Icon(row, 18); row.icon:SetPoint('LEFT', 8, 0)
            row.text = S.Text(row, 12); row.text:SetPoint('LEFT', 34, 6); row.text:SetWidth(272)
            row.hint = S.Text(row, 10, S.colors.muted); row.hint:SetPoint('LEFT', 34, -7); row.hint:SetWidth(272)
            panel.rows[i] = row
        end
        row:SetPoint('TOPLEFT', 2, -2 - (i - 1) * 31)
        row.icon:SetTexture(r.icon or HOME_ICON)
        row.text:SetText(r.text); row.hint:SetText(r.hint or '')
        row:SetScript('OnClick', function()
            panel:Hide(); box:SetText(''); box:ClearFocus()
            if type(r.action) == 'function' then Core.Run('résultat de recherche', r.action)
            elseif r.module then UI.Open(r.module) end
        end)
        row:Show()
    end
    S.Call(panel.empty, 'SetShown', #list == 0)
    panel:SetHeight(4 + math.max(1, #list) * 31)
    panel:Show()
end

local function createHeader()
    header = {}
    local right = frame.closeButton
    -- Notifications
    local bell = CreateFrame('Button', nil, frame); bell:SetSize(28, 28)
    bell:SetPoint('RIGHT', right, 'LEFT', -10, 0)
    bell.icon = bell:CreateTexture(nil, 'ARTWORK'); bell.icon:SetSize(22, 22); bell.icon:SetPoint('CENTER')
    bell.icon:SetTexture('Interface\\GossipFrame\\AvailableQuestIcon')
    bell.badge = S.Badge(bell, '', 'danger'); bell.badge:SetPoint('TOPRIGHT', 6, 4); bell.badge:Hide()
    bell:SetScript('OnClick', function() renderBell(); UI.ShowNotifications() end)
    S.Tooltip(bell, 'Notifications', 'Ce qui t’attend dans les modules : urgences et choses à faire.')
    header.bell = bell
    -- Recherche
    local box = S.Input(frame, 230, 'Rechercher (recette, joueur…)')
    box:SetPoint('RIGHT', bell, 'LEFT', -10, 0)
    box:SetScript('OnEnterPressed', function(self) local first = header.found and header.found[1]; if first then header.results.rows[1]:Click() else self:ClearFocus() end end)
    box:SetScript('OnEscapePressed', function(self) self:SetText(''); self:ClearFocus(); header.results:Hide() end)
    S.OnText(box, function() renderSearch() end)
    header.search = box
    local results = S.Box(frame, S.colors.panel, S.colors.line)
    call(results, 'SetFrameStrata', 'DIALOG'); call(results, 'SetFrameLevel', 500); results:SetWidth(320); call(results, 'EnableMouse', true)
    results:SetPoint('TOPLEFT', box, 'BOTTOMLEFT', 0, -4); results:Hide()
    results.empty = S.Text(results, 12, S.colors.muted); results.empty:SetPoint('TOPLEFT', 10, -10); results.empty:SetText('Aucun résultat.')
    results.rows = {}
    header.results = results
end

-- Coin d'agrandissement : tirer le coin agrandit ou réduit toute la fenêtre (même réglage que Réglages > Affichage),
-- le coin haut gauche ne bouge pas. Les modules gardent leur mise en page : la fenêtre change d'échelle.
local function cursorX()
    if type(GetCursorPosition) ~= 'function' then return nil end
    local x = GetCursorPosition()
    local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    return type(x) == 'number' and x / (scale or 1) or nil
end

function UI.KeepTopLeft(fn)
    local scale = frame:GetScale() or 1
    local left, top = frame.GetLeft and frame:GetLeft(), frame.GetTop and frame:GetTop()
    fn()
    local now = frame:GetScale() or 1
    if type(left) == 'number' and type(top) == 'number' and now > 0 then
        frame:ClearAllPoints(); frame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', left * scale / now, top * scale / now)
    end
end

local function createGrip()
    local grip = CreateFrame('Button', nil, frame); grip:SetSize(16, 16); grip:SetPoint('BOTTOMRIGHT', -3, 3)
    call(grip, 'SetFrameLevel', (frame.GetFrameLevel and frame:GetFrameLevel() or 1) + 20)
    call(grip, 'SetNormalTexture', 'Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
    call(grip, 'SetHighlightTexture', 'Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
    call(grip, 'SetPushedTexture', 'Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
    S.Tooltip(grip, 'Taille de la fenêtre', 'Tire le coin pour agrandir ou réduire la fenêtre.')
    grip:SetScript('OnMouseDown', function(self)
        local x = cursorX()
        if not x then return end
        self.startX, self.startPct = x, UI.ScalePercent()
        self.startW = totalWidth() * (frame:GetScale() or 1)
        self:SetScript('OnUpdate', function(me)
            local now = cursorX()
            if not now or not me.startW or me.startW <= 0 then return end
            local pct = me.startPct * (me.startW + (now - me.startX)) / me.startW
            pct = math.floor(pct / SCALE_STEP + 0.5) * SCALE_STEP
            if pct ~= UI.ScalePercent() then UI.SetScalePercent(pct, true) end
        end)
    end)
    grip:SetScript('OnMouseUp', function(self) self:SetScript('OnUpdate', nil) end)
    frame.grip = grip
end

--- Replie ou déplie la barre latérale (icônes seules) ; la fenêtre rétrécit d'autant.
function UI.SetCollapsed(value)
    QuintessenceDB = QuintessenceDB or {}
    QuintessenceDB.sidebarCollapsed = value and true or nil
    if not frame then return end
    UI.KeepTopLeft(fit)
    if current ~= 'locked' then layoutNav() end
    renderSidebar()
end

-- Interface Futuriste (1.50.0) : cadre presque noir, filet cyan lumineux sous l'en-tête, lignes de balayage, grands
-- crochets d'angle, titre en capitales espacées, barre latérale bordée d'un filet cyan.
local function createFuture()
    local c = S.colors
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = 'Interface\\Buttons\\WHITE8X8', edgeFile = 'Interface\\Buttons\\WHITE8X8', edgeSize = 1 })
        frame:SetBackdropColor(unpack(c.bg)); frame:SetBackdropBorderColor(unpack(c.line))
    end
    -- Lignes de balayage : un trait très pâle tous les 4 points, sur toute la fenêtre
    for y = 0, TOTAL_H, 4 do
        local scan = frame:CreateTexture(nil, 'BACKGROUND', nil, 1); scan:SetColorTexture(c.gold[1], c.gold[2], c.gold[3], 0.018)
        call(scan, 'SetPoint', 'TOPLEFT', 1, -y); call(scan, 'SetPoint', 'TOPRIGHT', -1, -y); call(scan, 'SetHeight', 1)
    end
    S.Brackets(frame, 22, 2)
    -- En-tête : bande plus sombre, titre espacé, filet lumineux (trait plein + halo)
    local band = frame:CreateTexture(nil, 'BACKGROUND', nil, 2); band:SetColorTexture(0, 0.02, 0.035, 0.9)
    call(band, 'SetPoint', 'TOPLEFT', 1, -1); call(band, 'SetPoint', 'TOPRIGHT', -1, -1); call(band, 'SetHeight', HEADER_H - 1)
    local crest = frame:CreateTexture(nil, 'ARTWORK'); crest:SetSize(28, 28); crest:SetPoint('TOPLEFT', 16, -12)
    crest:SetTexture('Interface\\Icons\\INV_Misc_Head_Dragon_01'); crest:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    call(crest, 'SetDesaturated', true); call(crest, 'SetVertexColor', c.gold[1], c.gold[2], c.gold[3], 1)
    local ring = S.Box(frame, { 0, 0, 0, 0 }, c.gold, 'Frame'); ring:SetSize(32, 32); ring:SetPoint('CENTER', crest, 'CENTER')
    local title = S.Text(frame, 15, c.gold); title:SetPoint('TOPLEFT', 56, -11); title:SetText(S.Spaced('Quintessence'))
    local subtitle = S.Text(frame, 10, c.muted); subtitle:SetPoint('TOPLEFT', 56, -31); subtitle:SetText(SUBTITLE)
    frame.crumb = subtitle
    local close = S.Button(frame, 'X', 28, 28, 'ghost'); close:SetPoint('TOPRIGHT', -14, -12)
    close:SetScript('OnClick', function() frame:Hide() end)
    frame.closeButton = close
    local line = S.Fill(frame, 'ARTWORK', c.gold); line:SetPoint('TOPLEFT', 1, -HEADER_H); line:SetPoint('TOPRIGHT', -1, -HEADER_H); line:SetHeight(1)
    local halo = S.Fill(frame, 'ARTWORK', { c.gold[1], c.gold[2], c.gold[3], 0.18 }); halo:SetPoint('TOPLEFT', 1, -HEADER_H - 1)
    halo:SetPoint('TOPRIGHT', -1, -HEADER_H - 1); halo:SetHeight(4)
    -- Barre latérale : fond plus sombre, filet cyan à droite
    sidebar = S.Box(frame, c.side, c.side)
    sidebar:SetPoint('TOPLEFT', 1, -HEADER_H - 5); sidebar:SetPoint('BOTTOMLEFT', 1, 1); sidebar:SetWidth(SIDE_W)
    local edge = S.Fill(sidebar, 'ARTWORK', { c.gold[1], c.gold[2], c.gold[3], 0.45 }); edge:SetPoint('TOPRIGHT'); edge:SetPoint('BOTTOMRIGHT'); edge:SetWidth(1)
end

local function create()
    createFrame()
    local kind = S.Kind and S.Kind() or 'modern'
    if kind == 'classic' then createClassic() elseif kind == 'future' then createFuture() else createModern() end
    sidebar.syncDot = sidebar:CreateTexture(nil, 'ARTWORK'); sidebar.syncDot:SetSize(8, 8); sidebar.syncDot:SetPoint('BOTTOMLEFT', 16, 52)
    sidebar.syncLabel = S.Text(sidebar, 11, S.colors.muted); sidebar.syncLabel:SetPoint('LEFT', sidebar.syncDot, 'RIGHT', 8, 0)
    local syncButton = S.Button(sidebar, 'Synchroniser', (sidebar.rowWidth and SIDE_W - 8 or SIDE_W) - 28, 28, 'ghost')
    syncButton:SetPoint('BOTTOMLEFT', 14, 14)
    syncButton:SetScript('OnClick', function()
        if Core.sync then
            Core.sync:Announce()
            if S.Toast then S.Toast('Synchro demandée aux membres connectés.', 'success') else Core.Print('Synchro demandée aux membres connectés.') end
        end
        renderSidebar()
    end)
    sidebar.syncButton = syncButton
    -- Replier / déplier la barre latérale (1.50.0)
    local collapse = S.Button(sidebar, '«', 24, 22, 'ghost')
    collapse:SetScript('OnClick', function() UI.SetCollapsed(not UI.IsCollapsed()) end)
    S.Tooltip(collapse, function() return UI.IsCollapsed() and 'Déplier la barre' or 'Replier la barre' end,
        'Icônes seules : la fenêtre est plus étroite.')
    sidebar.collapse = collapse
    local dotTip = CreateFrame('Frame', nil, sidebar); dotTip:SetSize(16, 16); dotTip:SetPoint('CENTER', sidebar.syncDot, 'CENTER')
    dotTip:EnableMouse(true)
    S.Tooltip(dotTip, function() return (syncText()) end)

    content = CreateFrame('Frame', nil, frame)
    content:SetPoint('TOPLEFT', SIDE_W + PAD, -HEADER_H - PAD)
    createHeader()
    createGrip()
    -- Notifications tenues à jour toutes les 15 s tant que la fenêtre est ouverte
    local elapsed = 0
    frame:SetScript('OnUpdate', function(_, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed >= 15 then elapsed = 0; if current ~= 'locked' then Core.Run('notifications', renderBell) end end
    end)
    if frame.HookScript then
        frame:HookScript('OnHide', function()
            if header.notePanel then header.notePanel:Hide() end
            if header.results then header.results:Hide() end
        end)
    end
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
    for _, h in pairs(headings) do call(h, 'Hide'); call(h.rule, 'Hide') end
    fit()
    renderSidebar()
    renderCrumb()
    frame:Show()
    locked:Show()
end

--- Ouvre la fenêtre sur un module (id) ou l'accueil ('home').
function UI.Open(id)
    if not frame then create() end
    local blocked, guildName = Core.GuildBlocked()
    if blocked then return showLocked(blocked, guildName) end
    if id == 'locked' then id = nil end
    -- Première ouverture d'un personnage sans profil : l'accueil s'ouvre dans sa propre fenêtre, pas dans l'addon (T202)
    if id == nil and Core.Profile and Core.Profile.ShouldWelcome() and Core.Profile.ShowWelcome then
        local ok, shown = Core.Run('accueil des nouveaux membres', Core.Profile.ShowWelcome)
        if ok and shown then Core.Profile.MarkWelcomeSeen(); return end
    end
    if id == 'profil' then Core.settingsTab = 'profile'; id = 'settings' end
    id = id or (QuintessenceDB and QuintessenceDB.lastTab) or 'home'
    if id == 'profil' then Core.settingsTab = 'profile'; id = 'settings' end
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
    renderCrumb()
    Core.Run('notifications', renderBell)
    frame:Show()
    panels[id]:Show()
    if m and m.refresh then Core.Run('onglet ' .. id, m.refresh) end
    if id == 'home' then Core.Run('accueil', renderHome) end
    -- Visite guidée proposée une fois par personnage, après l'accueil des nouveaux membres (Tour.lua)
    local Tour = Core.Tour
    if Tour and not Tour.Active() and Tour.ShouldOffer() then Core.Run('visite guidée', Tour.Start) end
end

--- Ouvre ou ferme la fenêtre ; avec un id, bascule sur ce module s'il n'est pas déjà affiché.
function UI.Toggle(id)
    if frame and frame:IsShown() and (id == nil or id == current) then frame:Hide() else UI.Open(id) end
end

function UI.Raise()
    if frame and frame.Raise then frame:Raise() end
end
-- Élève notre fenêtre de butin sans masquer ni modifier la carte du jeu.
function UI.RaiseAbove(strata, level)
    if not frame then return end
    if not frame.mapRaise then
        frame.mapRaise = true
        frame:HookScript('OnHide', function(self)
            self:SetFrameStrata(self.mapPreviousStrata or 'HIGH'); self:SetFrameLevel(self.mapPreviousLevel or 0)
            self.mapPreviousStrata, self.mapPreviousLevel = nil, nil
        end)
    end
    if not frame.mapPreviousStrata then
        frame.mapPreviousStrata, frame.mapPreviousLevel = frame:GetFrameStrata(), frame:GetFrameLevel()
    end
    frame:SetFrameStrata(strata or 'DIALOG'); frame:SetFrameLevel(level or 200)
    if frame.Raise then frame:Raise() end
end


--- Parties de la fenêtre pour la visite guidée (Tour.lua) : window, sidebar, content, search, bell, sync, collapse,
--- grip, ou nav et l'id d'un onglet de la barre. nil si la fenêtre n'est pas créée.
function UI.Element(name, id)
    if not frame then return nil end
    if name == 'window' then return frame end
    if name == 'sidebar' then return sidebar end
    if name == 'content' then return content end
    if name == 'search' then return header and header.search end
    if name == 'bell' then return header and header.bell end
    if name == 'sync' then return sidebar and sidebar.syncButton end
    if name == 'collapse' then return sidebar and sidebar.collapse end
    if name == 'grip' then return frame.grip end
    if name == 'nav' then return nav[id] end
end

function UI.AnyOpen() return frame ~= nil and frame:IsShown() end
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

-- ---------------------------------------------------------------------------
-- Touche « Envoyer le message prêt » (Bindings.xml, 1.50.0)
-- ---------------------------------------------------------------------------
-- Ancien envoi direct (1.50.0) gardé pour les modules inscrits par RegisterReadySender ; sur WoW Forever le jeu bloque
-- l'envoi par l'addon en guilde et dans les canaux publics : la touche utilise SecureSend.lua (RegisterReadyMessage).
-- (libellés des touches : SecureSend.lua ; la touche passe désormais par le bouton sécurisé QuintessenceSecureSend)
local readySenders = {}

--- Inscrit un envoi « prêt » : fn() envoie s'il y a quelque chose et renvoie true, sinon nil. order : plus petit d'abord.
function Core:RegisterReadySender(id, fn, order)
    if type(id) ~= 'string' or type(fn) ~= 'function' then return end
    for i = #readySenders, 1, -1 do if readySenders[i].id == id then table.remove(readySenders, i) end end
    readySenders[#readySenders + 1] = { id = id, fn = fn, order = tonumber(order) or 50 }
    table.sort(readySenders, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
end

--- Envoie le premier message prêt ; true si un message est parti (ou soumis au jeu).
function UI.SendReady()
    if Core.GuildBlocked() then return false end
    if Core.Announce and Core.Announce.SendPending then
        local ok, sent = pcall(Core.Announce.SendPending)
        if ok and sent then if S.Toast then S.Toast('Annonce de guilde envoyée.', 'success') end; return true end
    end
    for _, r in ipairs(readySenders) do
        local ok, sent = Core.Run('envoi prêt ' .. r.id, r.fn)
        if ok and sent then return true end
    end
    Core.Print('Aucun message prêt à envoyer.')
    return false
end

function Quintessence_SendReady()
    Core.Run('touche', UI.SendReady)
end
