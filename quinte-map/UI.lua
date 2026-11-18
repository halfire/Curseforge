local _, Q = ...
--[[
  UI.lua : Interface utilisateur du module Quinte-map dans la fenêtre Quintessence (1078 × 658).
  Section « SOS et PvP » : SOS PvP sauvage (appel aux armes en 1 clic et alertes des membres agressés).
  Feux de campement et rares retirés en 0.13.0 (demande du GM).
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]

local UI = {}
Q.UI = UI
local S = Quintessence.Style

local function classHex(class)
    local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class or '']
    local hex = color and color.colorStr
    return (type(hex) == 'string' and hex:match('^%x%x%x%x%x%x%x%x$')) and hex or 'ffffffff'
end

local function invitePlayer(name)
    if not name then return false end
    if Quintessence and Quintessence.SameName and Q.PlayerName and Quintessence.SameName(name, Q.PlayerName()) then
        Q.Print('C\'est déjà toi (' .. Q.Safe(name) .. ') !')
        return false
    end
    if Quintessence and Quintessence.Invite then
        Quintessence.Invite(name)
    elseif C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
    return true
end

local mainFrame
local tabs = {}
local activeTab = 'sos'

-- =========================================================================
-- ONGLET 1 : SOS PVP SAUVAGE
-- =========================================================================

-- Onglet de la grande fenêtre Quintessence (1.38.1+) : 1078 × 658 à l'échelle 1, textes de la même taille qu'avant.
-- Chaque sous-onglet occupe PW × PH sous la barre d'onglets.
local W, H = 1078, 658
local PW, PH = W, H - 40
local LIST_ROWS = math.floor((PH - 106) / 41) -- 12

local function createSOSPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    -- Bandeau d'action principal
    local actionBox = S.Box(panel, S.colors.panel, S.colors.line)
    actionBox:SetPoint('TOPLEFT', 0, 0)
    actionBox:SetSize(PW, 56)

    local bannerIcon = actionBox:CreateTexture(nil, 'ARTWORK')
    bannerIcon:SetSize(34, 34); bannerIcon:SetPoint('LEFT', 14, 0)
    bannerIcon:SetTexture('Interface\\Icons\\INV_BannerPVP_02')
    bannerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local bannerTitle = S.Text(actionBox, 14, S.colors.text)
    bannerTitle:SetPoint('TOPLEFT', 58, -10)
    bannerTitle:SetText('Appel aux armes (SOS PvP sauvage)')

    local bannerDesc = S.Text(actionBox, 11, S.colors.muted)
    bannerDesc:SetPoint('TOPLEFT', 58, -30)
    bannerDesc:SetText('Transmet ta position exacte, ton layer et le nom de ton agresseur à toute la guilde.')

    local btnClearSOS = S.Button(actionBox, 'Lever mon alerte', 136, 30, 'ghost')
    btnClearSOS:SetPoint('RIGHT', -14, 0)
    btnClearSOS:SetScript('OnClick', function() Q.ClearSOS() end)

    local btnTriggerSOS = S.Button(actionBox, 'Déclencher le SOS PvP', 176, 30, 'danger')
    btnTriggerSOS:SetPoint('RIGHT', btnClearSOS, 'LEFT', -8, 0)
    btnTriggerSOS:SetScript('OnClick', function() Q.SendSOS() end)

    -- Conteneur des alertes en cours
    local listBox = S.Box(panel, S.colors.panel, S.colors.line)
    listBox:SetPoint('TOPLEFT', 0, -66)
    listBox:SetSize(PW, PH - 66)

    local listHeading = S.Heading(listBox, 'Membres en détresse · Carte ouvre la carte du monde sur leur position')
    listHeading:SetPoint('TOPLEFT', 16, -12)

    local rows = {}
    for i = 1, LIST_ROWS do
        local r = S.Row(listBox, PW - 2, 40)
        r:SetPoint('TOPLEFT', 1, -34 - (i - 1) * 41)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(24, 24); icon:SetPoint('LEFT', 14, 0)
        icon:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcon_8')

        local nameText = S.Text(r, 13, S.colors.text)
        nameText:SetPoint('TOPLEFT', 48, -5)
        nameText:SetWidth(PW - 390)

        local posText = S.Text(r, 11, S.colors.muted)
        posText:SetPoint('TOPLEFT', 48, -22)
        posText:SetWidth(PW - 390)

        local helpBtn = S.Button(r, 'Inviter en renfort', 130, 26, 'primary')
        helpBtn:SetPoint('RIGHT', -194, 0)

        local mapBtn = S.Button(r, 'Carte', 70, 26, 'ghost')
        mapBtn:SetPoint('RIGHT', -46, 0)

        local routeBtn = S.Button(r, 'Chemin', 64, 26, 'ghost')
        routeBtn:SetPoint('RIGHT', -122, 0)

        -- Masquer l'alerte d'un autre chez soi (ou lever la sienne)
        local hideBtn = S.Button(r, '×', 26, 26, 'ghost')
        hideBtn:SetPoint('RIGHT', -14, 0)

        rows[i] = {
            frame = r,
            name = nameText,
            pos = posText,
            helpBtn = helpBtn,
            routeBtn = routeBtn,
            mapBtn = mapBtn,
            hideBtn = hideBtn
        }
    end
    panel.rows = rows

    local emptyText = S.Text(listBox, 12, S.colors.muted, 'CENTER')
    emptyText:SetPoint('CENTER', 0, -10)
    emptyText:SetWidth(660)
    emptyText:SetWordWrap(true)
    emptyText:SetText('Aucun membre de Quintessence n\'est actuellement en détresse.\nUtilise le bouton « Déclencher le SOS PvP » ou /qsos si tu es attaqué ou campé.')
    panel.emptyText = emptyText

    return panel
end

function UI.RefreshSOS()
    local p = tabs.sos
    if not p or not p:IsVisible() then return end

    local alerts = Q.GetActiveSOS()
    if #alerts == 0 then
        p.emptyText:Show()
        for _, r in ipairs(p.rows) do r.frame:Hide() end
        return
    end

    p.emptyText:Hide()
    local now = Q.Now()

    for i, r in ipairs(p.rows) do
        local a = alerts[i]
        if a then
            r.frame:Show()
            local cHex = classHex(a.class)
            local elapsed = math.max(0, now - (a.time or 0))
            local elapsedText = (elapsed < 60) and (elapsed .. ' s') or (math.floor(elapsed / 60) .. ' min')

            local targetStr = a.targetName and ('  ·  Agresseur : |c' .. S.hex.red .. Q.Safe(a.targetName) .. '|r') or ''
            r.name:SetText(string.format('|c%s%s|r  ·  attaqué il y a |c%s%s|r%s',
                cHex, Q.Safe(a.name), S.hex.red, elapsedText, targetStr))

            r.pos:SetText(string.format('%s%s  ·  Coordonnées : |c' .. Quintessence.Style.hex.text .. '%.1f, %.1f|r  ·  |c%s%s|r',
                Q.Safe(a.zone or 'Inconnue'),
                (a.subzone and a.subzone ~= '') and (' (' .. Q.Safe(a.subzone) .. ')') or '',
                a.x or 0, a.y or 0, S.hex.gold, Q.LayerLabel(Q.LayerFor(a))))

            local mine = Quintessence.SameName and Quintessence.SameName(a.name, Q.PlayerName())
            if mine then
                r.helpBtn:SetLabel('Lever mon alerte')
                r.helpBtn:SetScript('OnClick', function() Q.ClearSOS() end)
            else
                r.helpBtn:SetLabel('Inviter en renfort')
                r.helpBtn:SetScript('OnClick', function()
                    invitePlayer(a.name)
                    Q.Print('Invitation de secours envoyée à ' .. Q.Safe(a.name) .. '.')
                end)
            end
            r.hideBtn:SetScript('OnClick', function() Q.DismissSOS(a.name) end)

            r.mapBtn:SetScript('OnClick', function()
                Q.ShowOnWorldMap(a.mapID, a.x, a.y, 'SOS ' .. a.name)
            end)
            r.routeBtn:SetScript('OnClick', function()
                Q.ShowRoute(a.mapID, a.x, a.y, 'SOS ' .. a.name)
            end)
        else
            r.frame:Hide()
        end
    end
end

-- =========================================================================
-- ONGLET 2 : VENDETTA PVP (QUI NOUS A TUÉS · VENGEANCE DE LA GUILDE)
-- =========================================================================

local VENDETTA_ROWS = math.floor((PH - 110) / 41) -- 12
local vendettaState = {
    mode = 'all',
    query = '',
    offset = 0,
}

local function createVendettaPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    -- Bandeau supérieur d'action et filtres
    local topBox = S.Box(panel, S.colors.panel, S.colors.line)
    topBox:SetPoint('TOPLEFT', 0, 0)
    topBox:SetSize(PW, 56)

    local vIcon = topBox:CreateTexture(nil, 'ARTWORK')
    vIcon:SetSize(34, 34); vIcon:SetPoint('LEFT', 14, 0)
    vIcon:SetTexture('Interface\\Icons\\Ability_DualWield')
    vIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local vTitle = S.Text(topBox, 14, S.colors.text)
    vTitle:SetPoint('TOPLEFT', 58, -10)
    vTitle:SetText('Vendetta PvP · Qui a tué nos membres (Vengeance)')

    local vDesc = S.Text(topBox, 11, S.colors.muted)
    vDesc:SetPoint('TOPLEFT', 58, -30)
    vDesc:SetText('Détection automatique à ta mort en PvP sauvage, ou ajout manuel d\'un campeur ennemi.')

    local enemyInput = S.Input(topBox, 160, 'Nom de l\'ennemi…')
    enemyInput:SetPoint('RIGHT', -154, 0)
    panel.enemyInput = enemyInput

    local addBtn = S.Button(topBox, 'Signaler / Cible', 132, 26, 'danger')
    addBtn:SetPoint('RIGHT', -14, 0)
    local function doAddVendetta()
        local name = (enemyInput:GetText() or ''):match('^%s*(.-)%s*$')
        local eClass, eLevel = nil, nil
        if name == '' and UnitExists and UnitExists('target') and UnitIsPlayer and UnitIsPlayer('target') then
            local okN, rawN = pcall(UnitName, 'target')
            if okN and type(rawN) == 'string' and not (type(issecretvalue) == 'function' and issecretvalue(rawN)) then
                name = rawN
            end
            local okC, _, rawC = pcall(UnitClass, 'target')
            if okC and type(rawC) == 'string' and not (type(issecretvalue) == 'function' and issecretvalue(rawC)) then
                eClass = rawC
            end
            local okL, rawL = pcall(UnitLevel, 'target')
            if okL and not (type(issecretvalue) == 'function' and issecretvalue(rawL)) then
                eLevel = tonumber(rawL)
            end
        end
        if name ~= '' then
            Q.ReportKillByEnemy(name, eClass, eLevel)
            enemyInput:SetText('')
            UI.RefreshVendetta()
        else
            Q.Print('Saisis le nom du joueur ennemi ou cible-le avant de cliquer sur Signaler.')
        end
    end
    addBtn:SetScript('OnClick', doAddVendetta)
    enemyInput:SetScript('OnEnterPressed', function(self) doAddVendetta(); self:ClearFocus() end)

    -- Conteneur de la liste des ennemis
    local listBox = S.Box(panel, S.colors.panel, S.colors.line)
    listBox:SetPoint('TOPLEFT', 0, -66)
    listBox:SetSize(PW, PH - 66)
    listBox:EnableMouseWheel(true)
    listBox:SetScript('OnMouseWheel', function(_, delta)
        vendettaState.offset = math.max(0, vendettaState.offset - delta * 2)
        UI.RefreshVendetta()
    end)

    -- Barre de filtres interne à la liste
    local modeBtns = {}
    local modes = {
        { id = 'all', label = 'Tous', w = 74 },
        { id = 'active', label = 'À venger', w = 96 },
        { id = 'avenged', label = 'Vengés', w = 84 },
    }
    local mx = 14
    for _, m in ipairs(modes) do
        local b = S.Button(listBox, m.label, m.w, 22, 'ghost')
        b:SetPoint('TOPLEFT', mx, -8)
        b:SetScript('OnClick', function()
            vendettaState.mode = m.id
            vendettaState.offset = 0
            UI.RefreshVendetta()
        end)
        modeBtns[m.id] = b
        mx = mx + m.w + 6
    end
    panel.modeBtns = modeBtns

    local searchInput = S.Input(listBox, 320, 'Rechercher ennemi, victime, zone…')
    searchInput:SetPoint('TOPRIGHT', -14, -6)
    searchInput:SetScript('OnTextChanged', function(box)
        vendettaState.query = box:GetText() or ''
        box.placeholder:SetShown(vendettaState.query == '')
        vendettaState.offset = 0
        UI.RefreshVendetta()
    end)

    local rows = {}
    for i = 1, VENDETTA_ROWS do
        local r = S.Row(listBox, PW - 20, 39)
        r:SetPoint('TOPLEFT', 1, -38 - (i - 1) * 41)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(22, 22); icon:SetPoint('LEFT', 12, 0)
        icon:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcon_8')

        local enemyText = S.Text(r, 13, S.colors.text)
        enemyText:SetPoint('TOPLEFT', 44, -4)
        enemyText:SetWidth(PW - 395)

        local metaText = S.Text(r, 11, S.colors.muted)
        metaText:SetPoint('TOPLEFT', 44, -21)
        metaText:SetWidth(PW - 395)

        local avengeBtn = S.Button(r, 'Vengé !', 88, 24, 'primary')
        avengeBtn:SetPoint('RIGHT', -224, 0)

        local hopBtn = S.Button(r, 'Layer', 68, 24, 'ghost')
        hopBtn:SetPoint('RIGHT', -150, 0)

        local mapBtn = S.Button(r, 'Carte', 64, 24, 'ghost')
        mapBtn:SetPoint('RIGHT', -10, 0)

        local routeBtn = S.Button(r, 'Chemin', 64, 24, 'ghost')
        routeBtn:SetPoint('RIGHT', -80, 0)

        rows[i] = {
            frame = r,
            icon = icon,
            enemy = enemyText,
            meta = metaText,
            avengeBtn = avengeBtn,
            hopBtn = hopBtn,
            routeBtn = routeBtn,
            mapBtn = mapBtn,
        }
    end
    panel.rows = rows

    panel.scroll = S.Scrollbar(listBox, VENDETTA_ROWS * 41, function(offset)
        if offset ~= vendettaState.offset then
            vendettaState.offset = offset
            UI.RefreshVendetta()
        end
    end)
    panel.scroll:SetPoint('TOPLEFT', PW - 14, -38)

    local emptyText = S.Text(listBox, 12, S.colors.muted, 'CENTER')
    emptyText:SetPoint('CENTER', 0, -14)
    emptyText:SetWidth(660)
    emptyText:SetWordWrap(true)
    emptyText:SetText('Aucun tueur PvP enregistré.\nDès qu\'un joueur ennemi tue un membre de Quintessence, son nom, sa position et son layer apparaissent ici pour organiser la vengeance !')
    panel.emptyText = emptyText

    return panel
end

function UI.RefreshVendetta()
    local p = tabs.vendetta
    if not p or not p:IsVisible() then return end

    for id, b in pairs(p.modeBtns or {}) do
        b:SetActive(id == vendettaState.mode)
    end

    local list = Q.GetVendettaList and Q.GetVendettaList(vendettaState.mode, vendettaState.query) or {}
    local maxOffset = math.max(0, #list - VENDETTA_ROWS)
    if vendettaState.offset > maxOffset then vendettaState.offset = maxOffset end
    p.scroll:SetMinMaxValues(0, maxOffset)
    p.scroll:SetValue(vendettaState.offset)
    p.scroll:SetShown(maxOffset > 0)
    p.emptyText:SetShown(#list == 0)

    local now = Q.Now()
    for i = 1, VENDETTA_ROWS do
        local r = p.rows[i]
        local e = list[vendettaState.offset + i]
        if e then
            r.frame:Show()
            local eHex = classHex(e.enemyClass)
            local elapsed = math.max(0, now - (e.time or 0))
            local elapsedText = (elapsed < 60) and (elapsed .. ' s') or (elapsed < 3600 and (math.floor(elapsed / 60) .. ' min') or (math.floor(elapsed / 3600) .. ' h'))
            local killsBadge = (e.kills and e.kills > 1) and (' |c' .. S.hex.red .. '(×' .. e.kills .. ' meurtres)|r') or ''
            local statusBadge = e.avenged
                and ('  |c' .. S.hex.mint .. '[Vengé par ' .. Q.Safe(e.avengedBy or 'la guilde') .. ']|r')
                or ('  |c' .. S.hex.red .. '[À VENGER]|r')

            r.enemy:SetText(string.format('|c%s%s|r%s  ·  Victime : |c' .. Quintessence.Style.hex.text .. '%s|r (il y a %s)%s',
                eHex, Q.Safe(e.enemy), killsBadge, Q.Safe(e.victim or 'Membre'), elapsedText, statusBadge))

            r.meta:SetText(string.format('%s%s  ·  Coordonnées : |c' .. Quintessence.Style.hex.text .. '%.1f, %.1f|r  ·  |c%s%s|r',
                Q.Safe(e.zone or 'Inconnue'),
                (e.subzone and e.subzone ~= '') and (' (' .. Q.Safe(e.subzone) .. ')') or '',
                e.x or 0, e.y or 0, S.hex.gold, Q.LayerLabel(e.layer)))

            if e.avenged then
                r.avengeBtn:SetLabel('Vengé')
                r.avengeBtn:SetActive(false)
                if r.avengeBtn.Disable then r.avengeBtn:Disable() end
            else
                r.avengeBtn:SetLabel('Vengé !')
                r.avengeBtn:SetActive(true)
                if r.avengeBtn.Enable then r.avengeBtn:Enable() end
                r.avengeBtn:SetScript('OnClick', function()
                    Q.MarkVendettaAvenged(e.enemy)
                end)
            end

            r.hopBtn:SetLabel(Q.LayerLabel(e.layer))
            r.hopBtn:SetScript('OnClick', function()
                invitePlayer(e.victim)
                Q.Print('Demande de groupe envoyée à ' .. (e.victim or 'la victime') .. ' pour rejoindre son ' .. Q.LayerLabel(e.layer) .. ' et traquer ' .. e.enemy .. '.')
            end)

            r.mapBtn:SetScript('OnClick', function()
                Q.ShowOnWorldMap(e.mapID, e.x, e.y, 'Vendetta : ' .. e.enemy)
            end)
            r.routeBtn:SetScript('OnClick', function()
                Q.ShowRoute(e.mapID, e.x, e.y, 'Vendetta : ' .. e.enemy)
            end)
        else
            r.frame:Hide()
        end
    end
end

-- =========================================================================
-- VENDETTAS, PRIMES ET CLASSEMENT (0.14.0, T218) : calculés par le site, reçus par Quinte-sync ou en jeu
-- =========================================================================

local BOARD_ROWS = math.floor((PH - 76) / 31) -- 18
local boardState = { offset = 0, period = 'week' }
local function ago(at)
    local d = math.floor(math.max(0, Q.Now() - (tonumber(at) or 0)) / 86400)
    return d == 0 and 'aujourd’hui' or (d == 1 and 'hier' or ('il y a ' .. d .. ' j'))
end
local function boardStatus()
    local g = Q.Board and Q.Board.Generated()
    if not g then return 'Pas encore de liste : elle arrive du site par Quinte-sync chez un officier, puis en jeu.' end
    return 'Calculé par le site ' .. ago(g) .. ' (' .. date('%d/%m %H:%M', g) .. ').'
end
local function boardPanel(parent, kind)
    local panel = CreateFrame('Frame', nil, parent); panel:SetAllPoints()
    local top = S.Box(panel, S.colors.panel, S.colors.line); top:SetPoint('TOPLEFT', 0, 0); top:SetSize(PW, 56)
    local icon = top:CreateTexture(nil, 'ARTWORK'); icon:SetSize(34, 34); icon:SetPoint('LEFT', 14, 0)
    icon:SetTexture(kind == 'rank' and 'Interface\\Icons\\INV_Misc_Trophy_03' or 'Interface\\Icons\\Ability_Rogue_FeignDeath')
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = S.Text(top, 14, S.colors.text); title:SetPoint('TOPLEFT', 58, -10)
    title:SetText(kind == 'rank' and 'Classement PvP de la guilde' or 'Vendettas et primes')
    panel.status = S.Text(top, 11, S.colors.muted); panel.status:SetPoint('TOPLEFT', 58, -30); panel.status:SetWidth(PW - 330)
    if kind == 'rank' then
        panel.periods = {}
        for i, def in ipairs({ { 'week', 'Cette semaine' }, { 'month', '30 jours' } }) do
            local b = S.Button(top, def[2], 120, 28, 'ghost'); b:SetPoint('RIGHT', -14 - (2 - i) * 128, 0)
            b:SetScript('OnClick', function() boardState.period = def[1]; boardState.offset = 0; UI.RefreshBoard() end)
            panel.periods[def[1]] = b
        end
    end
    if kind == 'vendetta' then
        -- Objectifs de la semaine, avis de recherche, dernières primes tombées (0.15.0, T223) : plus de liste de noms
        local body = S.Box(panel, S.colors.panel, S.colors.line); body:SetPoint('TOPLEFT', 0, -66); body:SetSize(PW, PH - 66)
        local function heading(text, y)
            local h = S.Text(body, 12, S.colors.gold); h:SetPoint('TOPLEFT', 16, y); h:SetText(text); return h
        end
        panel.objHead = heading('Objectifs de la semaine', -12)
        panel.objectives = {}
        local OW = math.floor((PW - 32 - 3 * 10) / 4)
        for i = 1, 4 do
            local o = S.Box(body, S.colors.raised or S.colors.panel, S.colors.line); o:SetSize(OW, 96)
            o:SetPoint('TOPLEFT', 16 + (i - 1) * (OW + 10), -32)
            o.title = S.Text(o, 12, S.colors.text); o.title:SetPoint('TOPLEFT', 10, -8); o.title:SetWidth(OW - 20)
            o.text = S.Text(o, 10, S.colors.muted); o.text:SetPoint('TOPLEFT', 10, -26); o.text:SetWidth(OW - 20)
            o.text:SetWordWrap(true); if o.text.SetMaxLines then o.text:SetMaxLines(3) end
            o.bar = S.Box(o, S.colors.line, S.colors.line); o.bar:SetSize(OW - 70, 8); o.bar:SetPoint('BOTTOMLEFT', 10, 10)
            o.fill = o.bar:CreateTexture(nil, 'ARTWORK'); o.fill:SetPoint('LEFT'); o.fill:SetHeight(8)
            o.fill:SetColorTexture(unpack(S.colors.gold))
            o.count = S.Text(o, 11, S.colors.text, 'RIGHT'); o.count:SetPoint('BOTTOMRIGHT', -10, 7); o.count:SetWidth(54)
            o:Hide(); panel.objectives[i] = o
        end
        panel.wantedHead = heading('Avis de recherche', -142)
        panel.posters = {}
        local CW = math.floor((PW - 32 - 2 * 12) / 3)
        for i = 1, 3 do
            local c = S.Box(body, S.colors.raised or S.colors.panel, i == 1 and S.colors.gold or S.colors.line); c:SetSize(CW, 178)
            c:SetPoint('TOPLEFT', 16 + (i - 1) * (CW + 12), -162)
            c.head = S.Text(c, 10, S.colors.red, 'CENTER'); c.head:SetPoint('TOP', 0, -10); c.head:SetWidth(CW - 20)
            c.name = S.Text(c, 16, S.colors.text, 'CENTER'); c.name:SetPoint('TOP', 0, -28); c.name:SetWidth(CW - 20)
            c.info = S.Text(c, 10, S.colors.muted, 'CENTER'); c.info:SetPoint('TOP', 0, -52); c.info:SetWidth(CW - 20)
            c.bounty = S.Text(c, 24, S.colors.gold, 'CENTER'); c.bounty:SetPoint('TOP', 0, -72); c.bounty:SetWidth(CW - 20)
            c.deaths = S.Text(c, 11, S.colors.text, 'CENTER'); c.deaths:SetPoint('TOP', 0, -112); c.deaths:SetWidth(CW - 20)
            c.seen = S.Text(c, 10, S.colors.muted, 'CENTER'); c.seen:SetPoint('TOP', 0, -134); c.seen:SetWidth(CW - 20)
            c.seen:SetWordWrap(true)
            c:Hide(); panel.posters[i] = c
        end
        panel.noWanted = S.Text(body, 12, S.colors.muted, 'CENTER'); panel.noWanted:SetPoint('TOP', 0, -230); panel.noWanted:SetWidth(PW - 80)
        panel.noWanted:SetWordWrap(true)
        panel.huntHead = heading('Dernières primes tombées', -356)
        panel.hunter = S.Text(body, 12, S.colors.text, 'RIGHT'); panel.hunter:SetPoint('TOPRIGHT', -16, -356); panel.hunter:SetWidth(PW / 2)
        panel.hunts = {}
        for i = 1, 6 do
            local t = S.Text(body, 12, S.colors.text); t:SetPoint('TOPLEFT', 24, -378 - (i - 1) * 22); t:SetWidth(PW - 48)
            panel.hunts[i] = t
        end
        panel.rows = {}
        panel.empty = S.Text(body, 12, S.colors.muted, 'CENTER'); panel.empty:SetPoint('CENTER', 0, -10); panel.empty:SetWidth(660)
        panel.empty:SetWordWrap(true); panel.empty:Hide()
        panel.kind = kind
        return panel
    end
    local list = S.Box(panel, S.colors.panel, S.colors.line); list:SetPoint('TOPLEFT', 0, -66); list:SetSize(PW, PH - 66)
    list:EnableMouseWheel(true)
    list:SetScript('OnMouseWheel', function(_, delta) boardState.offset = math.max(0, boardState.offset - delta * 3); UI.RefreshBoard() end)
    panel.heading = S.Text(list, 11, S.colors.gold); panel.heading:SetPoint('TOPLEFT', 16, -12); panel.heading:SetWidth(PW - 32)
    panel.heading:SetText('Membre · kills normaux · grey kills · morts · champs de bataille · primes tombées')
    panel.rows = {}
    for i = 1, BOARD_ROWS do
        local r = S.Row(list, PW - 2, 30); r:SetPoint('TOPLEFT', 1, -34 - (i - 1) * 31)
        r.main = S.Text(r, 12, S.colors.text); r.main:SetPoint('LEFT', 14, 0); r.main:SetWidth(PW - 30)
        panel.rows[i] = r
    end
    panel.empty = S.Text(list, 12, S.colors.muted, 'CENTER'); panel.empty:SetPoint('CENTER', 0, -10); panel.empty:SetWidth(660)
    panel.empty:SetWordWrap(true)
    panel.kind = kind
    return panel
end
local function pts(n) return n .. ' pt' .. (n > 1 and 's' or '') end
--- Onglet Vendettas : objectifs de la semaine, trois avis de recherche, dernières primes tombées (0.15.0, T223).
function UI.RefreshWanted(p)
    local hex = Quintessence.Style.hex
    local B = Q.Board
    local objectives = B and B.Objectives() or {}
    for i, o in ipairs(p.objectives) do
        local d = objectives[i]
        if d then
            local done = d.done >= d.goal
            o.title:SetText((done and '|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t ' or '') .. Q.Safe(d.title))
            o.text:SetText(Q.Safe(d.text))
            o.fill:SetWidth(math.max(1, math.floor((o.bar:GetWidth() or 1) * math.min(1, d.done / math.max(1, d.goal)))))
            o.fill:SetShown(d.done > 0)
            o.count:SetText(math.min(d.done, d.goal) .. ' / ' .. d.goal)
            o:Show()
        else o:Hide() end
    end
    p.objHead:SetShown(#objectives > 0)
    local wanted = B and B.WantedList() or {}
    for i, c in ipairs(p.posters) do
        local v = wanted[i]
        if v then
            c.head:SetText(i == 1 and 'ENNEMI PUBLIC N°1' or 'RECHERCHÉ')
            c.name:SetText(Q.Safe(v.name))
            c.info:SetText((v.level and ('niveau ' .. v.level) or 'niveau inconnu') .. (v.class and (' · ' .. Q.Safe(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[v.class] or v.class)) or ''))
            c.bounty:SetText(pts(v.bounty))
            c.deaths:SetText(v.deaths .. ' membre' .. (v.deaths > 1 and 's' or '') .. ' tué' .. (v.deaths > 1 and 's' or '')
                .. ((v.greyDeaths or 0) > 0 and ('  ·  |c' .. hex.red .. 'ganker|r') or ''))
            c.seen:SetText('vu ' .. ago(v.last) .. (v.zone and (' · ' .. Q.Safe(v.zone)) or ''))
            c:Show()
        else c:Hide() end
    end
    p.noWanted:SetText(B and B.Generated() and 'Personne n’est recherché : tous les membres tués ont été vengés. Bravo !'
        or 'Pas encore de liste : elle arrive du site par Quinte-sync chez un officier, puis en jeu.')
    p.noWanted:SetShown(#wanted == 0)
    local hunts = B and B.Hunts() or {}
    for i, t in ipairs(p.hunts) do
        local h = hunts[i]
        if h then
            t:SetText('|c' .. hex.gold .. Q.Safe(h.by) .. '|r a abattu ' .. Q.Safe(h.target) .. '  |c' .. hex.mint .. '+' .. pts(h.points) .. '|r  ·  ' .. ago(h.at))
            t:Show()
        else t:Hide() end
    end
    p.huntHead:SetShown(#hunts > 0)
    local hunter = B and B.Hunter()
    p.hunter:SetText(hunter and ('Chasseur de la semaine : |c' .. hex.gold .. Q.Safe(hunter.name) .. '|r (' .. pts(hunter.points) .. ')') or '')
end
function UI.Tab(id) return tabs[id] end
function UI.RefreshBoard()
    local p = tabs[activeTab]
    if not (p and (p.kind == 'rank' or p.kind == 'vendetta')) then return end
    p.status:SetText(boardStatus())
    local hex = Quintessence.Style.hex
    local lines = {}
    if p.kind == 'rank' then
        for id, b in pairs(p.periods) do b:SetActive(id == boardState.period) end
        for i, r in ipairs(Q.Board and Q.Board.Ranking(boardState.period) or {}) do
            lines[#lines + 1] = string.format('%d. |c%s%s|r  ·  |c%s%d kill%s|r  ·  %d grey kill%s  ·  %d mort%s  ·  %d BG (%d gagné%s)  ·  %d prime%s%s',
                i, hex.gold, Q.Safe(r.name), hex.mint, r.kills, r.kills > 1 and 's' or '', r.greyKills, r.greyKills > 1 and 's' or '',
                r.deaths, r.deaths > 1 and 's' or '', r.battlegrounds, r.won, r.won > 1 and 's' or '', r.bounties, r.bounties > 1 and 's' or '',
                (r.bountyPoints or 0) > 0 and (' (' .. r.bountyPoints .. ' pts)') or '')
        end
        local ws = boardState.period == 'week' and Q.Board and Q.Board.WeekStart()
        p.heading:SetText('Membre · kills normaux · grey kills · morts · champs de bataille · primes tombées'
            .. (ws and ('  —  semaine depuis le mercredi ' .. date('%d/%m', ws)) or ''))
        p.empty:SetText('Rien sur cette période. Le classement vient du journal PvP des membres, calculé par le site.')
    else
        return UI.RefreshWanted(p)
    end
    boardState.offset = math.max(0, math.min(boardState.offset, math.max(0, #lines - BOARD_ROWS)))
    for i, r in ipairs(p.rows) do
        local text = lines[boardState.offset + i]
        if text then r.main:SetText(text); r:Show() else r:Hide() end
    end
    p.empty:SetShown(#lines == 0)
end

-- =========================================================================
-- CONTENEUR ET NAVIGATION
-- =========================================================================

local function switchTab(tabId)
    activeTab = tabId
    for id, p in pairs(tabs) do
        if id == tabId then p:Show() else p:Hide() end
    end
    if mainFrame.tabButtons then
        for id, btn in pairs(mainFrame.tabButtons) do
            btn:SetActive(id == tabId)
        end
    end
    if mainFrame.tabBar and mainFrame.tabBar.Mark then mainFrame.tabBar:Mark(tabId) end
    UI.Refresh()
end

local function create(parent)
    mainFrame = CreateFrame('Frame', nil, parent)
    mainFrame:SetAllPoints(parent)

    local tabDefs = {
        { id = 'sos', label = 'SOS PvP sauvage', w = 148 },
        { id = 'vendettas', label = 'Vendettas et primes', w = 168 },
        { id = 'classement', label = 'Classement', w = 120 },
    }

    -- Barre d'onglets commune du conteneur (1.50.0) : onglet choisi affiché dans l'en-tête « Module › onglet »
    if S.Tabs then
        mainFrame.tabBar = S.Tabs(mainFrame, tabDefs, switchTab, { module = 'map', gap = 8 })
        mainFrame.tabButtons = mainFrame.tabBar.buttons
    else
        local tabBtns = {}
        local posX = 0
        for _, def in ipairs(tabDefs) do
            local btn = S.Button(mainFrame, def.label, def.w, 28, 'ghost')
            btn:SetPoint('TOPLEFT', posX, 0)
            btn:SetScript('OnClick', function() switchTab(def.id) end)
            tabBtns[def.id] = btn
            posX = posX + def.w + 8
        end
        mainFrame.tabButtons = tabBtns
    end

    mainFrame.status = S.Text(mainFrame, 11, S.colors.gold, 'RIGHT')
    mainFrame.status:SetPoint('TOPRIGHT', -2, -8)

    local content = CreateFrame('Frame', nil, mainFrame)
    content:SetPoint('TOPLEFT', 0, -40)
    content:SetPoint('BOTTOMRIGHT', 0, 0)

    tabs.sos = createSOSPanel(content)
    tabs.vendettas = boardPanel(content, 'vendetta')
    tabs.classement = boardPanel(content, 'rank')

    mainFrame:SetScript('OnShow', function() Q.Run('fenêtre', UI.Refresh) end)
    switchTab(activeTab or 'sos')
end

function UI.Refresh()
    if not mainFrame or not mainFrame:IsVisible() then return end
    if mainFrame.status and Q.Summary then
        mainFrame.status:SetText(Q.Summary())
    end
    if activeTab == 'sos' then UI.RefreshSOS() end
    if activeTab == 'vendettas' or activeTab == 'classement' then UI.RefreshBoard() end
end

function UI.Open(tabId)
    if not Q.ready and Q.Init then Q.Init() end
    if tabId == 'vendetta' then tabId = 'vendettas' end
    if tabId and (tabId == 'sos' or tabs[tabId]) then
        activeTab = tabId
    end
    Quintessence.UI.Open('map')
    if mainFrame and tabId then switchTab(activeTab) end
end

function UI.Toggle() Quintessence.UI.Toggle('map') end

-- Accueil de Quintessence (conteneur 1.49.0) : bandeau SOS (même en édition SOS seul) et tuile PvP de la semaine
local DAYS = { 'dim.', 'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.' }
function Q.Home()
    if not Q.ready then return nil end
    local out = {}
    local list = Q.GetActiveSOS()
    local a = list[1]
    if a then
        out.alert = { text = 'SOS de ' .. Q.Safe(Q.DisplayName(a.name or '?')) .. ' — ' .. Q.Safe(a.zone or 'zone inconnue')
            .. (a.layer and (' (' .. Q.LayerLabel(a.layer) .. ')') or '') .. (#list > 1 and (' · ' .. #list .. ' alertes en cours') or ''),
            button = a.mapID and 'Chemin' or 'Voir le SOS',
            action = function()
                if a.mapID and Q.ShowRoute then Q.ShowRoute(a.mapID, a.x, a.y, 'SOS ' .. a.name) else UI.Open('sos') end
            end }
    end
    local P = Q.PvP
    if not P then return out end
    local since = Quintessence.WeekStart and Quintessence.WeekStart() or (Q.Now() - 7 * 86400)
    local w = P.Week and P.Week(since)
    local from = 'Depuis ' .. DAYS[tonumber(date('%w', since)) + 1] .. ' ' .. tonumber(date('%H', since)) .. ' h (reset de la semaine)'
    local lines
    if w then
        lines = { { 'Victoires honorables notées : ' .. w.honor, 'text' }, { 'Coups fatals de ton groupe : ' .. w.groupKills, 'text' },
            { 'Morts face à des joueurs : ' .. w.deaths, w.deaths > 0 and 'red' or 'text' },
            { 'Champs de bataille : ' .. w.played .. ' joué' .. (w.played > 1 and 's' or '') .. ', ' .. w.won .. ' gagné' .. (w.won > 1 and 's' or ''), 'text' },
            { from, 'muted' } }
    else lines = { { 'Journal PvP pas encore actif sur ce personnage.', 'muted' }, { from, 'muted' } } end
    out.tile = { title = 'PvP cette semaine', icon = 'Interface\\Icons\\INV_BannerPVP_02', order = 10,
        value = w and w.kills or '—', label = (w and w.kills == 1) and 'coup fatal' or 'coups fatals', lines = lines,
        hint = 'Clic : ouvrir la carte et les SOS', action = function() UI.Open() end }
    return out
end

Quintessence:RegisterModule({
    id = 'map',
    title = 'SOS et PvP',
    order = 55,
    icon = 'Interface\\Icons\\INV_BannerPVP_02',
    version = Q.version,
    width = W,
    height = H,
    create = function(parent)
        create(parent)
        return mainFrame
    end,
    refresh = function() UI.Refresh() end,
    home = function() return Q.Home() end,
    summary = function()
        if not Q.ready then return nil end
        return Q.Summary and Q.Summary() or 'Carte tactique'
    end,
})
