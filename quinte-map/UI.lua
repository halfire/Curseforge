local _, Q = ...
--[[
  UI.lua : Interface utilisateur du module Quinte-map dans la fenêtre Quintessence (760 × 440).
  Deux sous-onglets :
    1. SOS PvP sauvage : appel aux armes en 1 clic et alertes des membres agressés.
    2. Feux de campement : carte et suivi des campements sociaux de la guilde.
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

local LIST_ROWS = 7

local function createSOSPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    -- Bandeau d'action principal (760 × 56)
    local actionBox = S.Box(panel, S.colors.panel, S.colors.line)
    actionBox:SetPoint('TOPLEFT', 0, 0)
    actionBox:SetSize(760, 56)

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

    -- Conteneur des alertes en cours (760 × 334)
    local listBox = S.Box(panel, S.colors.panel, S.colors.line)
    listBox:SetPoint('TOPLEFT', 0, -66)
    listBox:SetSize(760, 334)

    local listHeading = S.Heading(listBox, 'Membres en détresse · Carte ouvre la carte du monde sur leur position')
    listHeading:SetPoint('TOPLEFT', 16, -12)

    local rows = {}
    for i = 1, LIST_ROWS do
        local r = S.Row(listBox, 758, 40)
        r:SetPoint('TOPLEFT', 1, -34 - (i - 1) * 41)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(24, 24); icon:SetPoint('LEFT', 14, 0)
        icon:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcon_8')

        local nameText = S.Text(r, 13, S.colors.text)
        nameText:SetPoint('TOPLEFT', 48, -5)
        nameText:SetWidth(370)

        local posText = S.Text(r, 11, S.colors.muted)
        posText:SetPoint('TOPLEFT', 48, -22)
        posText:SetWidth(370)

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
    emptyText:SetWidth(460)
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

            r.pos:SetText(string.format('%s%s  ·  Coordonnées : |cffffffff%.1f, %.1f|r  ·  |c%s%s|r',
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

local VENDETTA_ROWS = 7
local vendettaState = {
    mode = 'all',
    query = '',
    offset = 0,
}

local function createVendettaPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    -- Bandeau supérieur d'action et filtres (760 × 56)
    local topBox = S.Box(panel, S.colors.panel, S.colors.line)
    topBox:SetPoint('TOPLEFT', 0, 0)
    topBox:SetSize(760, 56)

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

    -- Conteneur de la liste des ennemis (760 × 334)
    local listBox = S.Box(panel, S.colors.panel, S.colors.line)
    listBox:SetPoint('TOPLEFT', 0, -66)
    listBox:SetSize(760, 334)
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

    local searchInput = S.Input(listBox, 220, 'Rechercher ennemi, victime, zone…')
    searchInput:SetPoint('TOPRIGHT', -14, -6)
    searchInput:SetScript('OnTextChanged', function(box)
        vendettaState.query = box:GetText() or ''
        box.placeholder:SetShown(vendettaState.query == '')
        vendettaState.offset = 0
        UI.RefreshVendetta()
    end)

    local rows = {}
    for i = 1, VENDETTA_ROWS do
        local r = S.Row(listBox, 740, 39)
        r:SetPoint('TOPLEFT', 1, -38 - (i - 1) * 41)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(22, 22); icon:SetPoint('LEFT', 12, 0)
        icon:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcon_8')

        local enemyText = S.Text(r, 13, S.colors.text)
        enemyText:SetPoint('TOPLEFT', 44, -4)
        enemyText:SetWidth(365)

        local metaText = S.Text(r, 11, S.colors.muted)
        metaText:SetPoint('TOPLEFT', 44, -21)
        metaText:SetWidth(365)

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
    panel.scroll:SetPoint('TOPLEFT', 746, -38)

    local emptyText = S.Text(listBox, 12, S.colors.muted, 'CENTER')
    emptyText:SetPoint('CENTER', 0, -14)
    emptyText:SetWidth(480)
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

            r.enemy:SetText(string.format('|c%s%s|r%s  ·  Victime : |cffffffff%s|r (il y a %s)%s',
                eHex, Q.Safe(e.enemy), killsBadge, Q.Safe(e.victim or 'Membre'), elapsedText, statusBadge))

            r.meta:SetText(string.format('%s%s  ·  Coordonnées : |cffffffff%.1f, %.1f|r  ·  |c%s%s|r',
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
-- ONGLET 3 : FEUX DE CAMPEMENT (CAMPING)
-- =========================================================================

local function createCampPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    -- Bandeau de contrôle supérieur (760 × 56)
    local topBox = S.Box(panel, S.colors.panel, S.colors.line)
    topBox:SetPoint('TOPLEFT', 0, 0)
    topBox:SetSize(760, 56)

    local campIcon = topBox:CreateTexture(nil, 'ARTWORK')
    campIcon:SetSize(34, 34); campIcon:SetPoint('LEFT', 14, 0)
    campIcon:SetTexture('Interface\\Icons\\Spell_Fire_Fire')
    campIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local campTitle = S.Text(topBox, 14, S.colors.text)
    campTitle:SetPoint('TOPLEFT', 58, -10)
    campTitle:SetText('Feux de campement de la guilde')

    local campDesc = S.Text(topBox, 11, S.colors.muted)
    campDesc:SetPoint('TOPLEFT', 58, -30)
    campDesc:SetText('Partage ton campement sur la carte du monde pour offrir repos et buffs aux membres.')

    local removeBtn = S.Button(topBox, 'Replier', 100, 30, 'ghost')
    removeBtn:SetPoint('RIGHT', -14, 0)
    removeBtn:SetScript('OnClick', function() Q.RemoveCamp() end)

    local deployBtn = S.Button(topBox, 'Poser mon campement (30 min)', 200, 30, 'primary')
    deployBtn:SetPoint('RIGHT', removeBtn, 'LEFT', -8, 0)
    deployBtn:SetScript('OnClick', function() Q.DeployCamp() end)

    -- Conteneur des campements actifs (760 × 334)
    local listBox = S.Box(panel, S.colors.panel, S.colors.line)
    listBox:SetPoint('TOPLEFT', 0, -66)
    listBox:SetSize(760, 334)

    local listHeading = S.Heading(listBox, 'Campements actifs sur les layers')
    listHeading:SetPoint('TOPLEFT', 16, -12)

    local rows = {}
    for i = 1, LIST_ROWS do
        local r = S.Row(listBox, 758, 40)
        r:SetPoint('TOPLEFT', 1, -34 - (i - 1) * 41)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(24, 24); icon:SetPoint('LEFT', 14, 0)
        icon:SetTexture('Interface\\Icons\\Spell_Fire_Fire')
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local nameText = S.Text(r, 13, S.colors.text)
        nameText:SetPoint('TOPLEFT', 48, -5)
        nameText:SetWidth(370)

        local posText = S.Text(r, 11, S.colors.muted)
        posText:SetPoint('TOPLEFT', 48, -22)
        posText:SetWidth(370)

        local joinBtn = S.Button(r, 'Rejoindre', 130, 26, 'primary')
        joinBtn:SetPoint('RIGHT', -164, 0)

        local mapBtn = S.Button(r, 'Carte', 70, 26, 'ghost')
        mapBtn:SetPoint('RIGHT', -14, 0)

        local routeBtn = S.Button(r, 'Chemin', 64, 26, 'ghost')
        routeBtn:SetPoint('RIGHT', -92, 0)

        rows[i] = {
            frame = r,
            name = nameText,
            pos = posText,
            joinBtn = joinBtn,
            routeBtn = routeBtn,
            mapBtn = mapBtn
        }
    end
    panel.rows = rows

    local emptyText = S.Text(listBox, 12, S.colors.muted, 'CENTER')
    emptyText:SetPoint('CENTER', 0, -10)
    emptyText:SetWidth(460)
    emptyText:SetWordWrap(true)
    emptyText:SetText('Aucun feu de campement de guilde actuellement actif.\nPose le tien pour offrir repos et buffs sociaux aux membres de passage.')
    panel.emptyText = emptyText

    return panel
end

function UI.RefreshCamps()
    local p = tabs.camps
    if not p or not p:IsVisible() then return end

    local camps = Q.GetActiveCamps()
    if #camps == 0 then
        p.emptyText:Show()
        for _, r in ipairs(p.rows) do r.frame:Hide() end
        return
    end

    p.emptyText:Hide()
    local now = Q.Now()

    for i, r in ipairs(p.rows) do
        local c = camps[i]
        if c then
            r.frame:Show()
            local cHex = classHex(c.class)
            local remaining = math.max(0, (c.expiresAt or 0) - now)
            local mins = math.floor(remaining / 60)

            r.name:SetText(string.format('Campement de |c%s%s|r  ·  encore |c%s%d min|r', cHex, Q.Safe(c.owner), S.hex.mint, mins))
            r.pos:SetText(string.format('%s%s  ·  Coordonnées : |cffffffff%.1f, %.1f|r  ·  |c%s%s|r',
                Q.Safe(c.zone or 'Inconnue'),
                (c.subzone and c.subzone ~= '') and (' (' .. Q.Safe(c.subzone) .. ')') or '',
                c.x or 0, c.y or 0, S.hex.gold, Q.LayerLabel(Q.LayerFor(c))))

            r.joinBtn:SetScript('OnClick', function()
                invitePlayer(c.owner)
                Q.Print('Demande de groupe envoyée à ' .. c.owner .. ' pour rejoindre son campement.')
            end)

            r.mapBtn:SetScript('OnClick', function()
                Q.ShowOnWorldMap(c.mapID, c.x, c.y, 'Campement ' .. c.owner)
            end)
            r.routeBtn:SetScript('OnClick', function()
                Q.ShowRoute(c.mapID, c.x, c.y, 'Campement ' .. c.owner)
            end)
        else
            r.frame:Hide()
        end
    end
end

-- =========================================================================
-- RARES REPÉRÉS
-- =========================================================================

local function createRarePanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()
    local topBox = S.Box(panel, S.colors.panel, S.colors.line)
    topBox:SetPoint('TOPLEFT', 0, 0); topBox:SetSize(760, 56)
    local icon = topBox:CreateTexture(nil, 'ARTWORK')
    icon:SetSize(34, 34); icon:SetPoint('LEFT', 14, 0); icon:SetTexture('Interface\\Icons\\Ability_Hunter_SniperShot'); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = S.Text(topBox, 14, S.colors.text); title:SetPoint('TOPLEFT', 58, -10); title:SetText('Monstres rares repérés par la guilde')
    local desc = S.Text(topBox, 11, S.colors.muted); desc:SetPoint('TOPLEFT', 58, -30)
    desc:SetText('Cible, survole ou croise un rare : la guilde reçoit sa position et son layer (30 min).')
    panel.alertToggle = S.Button(topBox, '', 170, 30, 'ghost'); panel.alertToggle:SetPoint('RIGHT', -14, 0)
    panel.alertToggle:SetScript('OnClick', function()
        QuinteMapDB.settings.rareAlert = QuinteMapDB.settings.rareAlert == false and true or false
        UI.RefreshRares()
    end)
    local listBox = S.Box(panel, S.colors.panel, S.colors.line)
    listBox:SetPoint('TOPLEFT', 0, -66); listBox:SetSize(760, 334)
    local heading = S.Heading(listBox, 'Rares vus récemment'); heading:SetPoint('TOPLEFT', 16, -12)
    panel.rows = {}
    for i = 1, LIST_ROWS do
        local r = S.Row(listBox, 758, 40); r:SetPoint('TOPLEFT', 1, -34 - (i - 1) * 41)
        local nameText = S.Text(r, 13, S.colors.text); nameText:SetPoint('TOPLEFT', 16, -5); nameText:SetWidth(600)
        local posText = S.Text(r, 11, S.colors.muted); posText:SetPoint('TOPLEFT', 16, -22); posText:SetWidth(600)
        local mapBtn = S.Button(r, 'Carte', 70, 26, 'ghost'); mapBtn:SetPoint('RIGHT', -14, 0)
        panel.rows[i] = { frame = r, name = nameText, pos = posText, mapBtn = mapBtn }
    end
    local emptyText = S.Text(listBox, 12, S.colors.muted, 'CENTER')
    emptyText:SetPoint('CENTER', 0, -10); emptyText:SetWidth(460); emptyText:SetWordWrap(true)
    emptyText:SetText('Aucun rare repéré depuis 30 minutes.')
    panel.emptyText = emptyText
    return panel
end

function UI.RefreshRares()
    local p = tabs.rares
    if not p or not p:IsVisible() then return end
    p.alertToggle:SetLabel(QuinteMapDB.settings.rareAlert == false and 'Alertes dans le chat : non' or 'Alertes dans le chat : oui')
    local list, now = Q.GetActiveRares(), Q.Now()
    p.emptyText:SetShown(#list == 0)
    for i, row in ipairs(p.rows) do
        local r = list[i]
        if r then
            row.frame:Show()
            row.name:SetText(string.format('|c%s%s|r%s  ·  il y a %d min', S.hex.gold, Q.Safe(r.name), r.elite and ' (élite)' or '', math.floor((now - (r.time or now)) / 60)))
            row.pos:SetText(string.format('%s  ·  |cffffffff%.1f, %.1f|r  ·  |c%s%s|r  ·  vu par %s', Q.Safe(r.zone or 'Inconnue'), r.x or 0, r.y or 0,
                S.hex.gold, Q.LayerLabel(Q.LayerFor(r)), Q.Safe(Q.DisplayName(r.by or '?'))))
            row.mapBtn:SetScript('OnClick', function() Q.ShowOnWorldMap(r.mapID, r.x, r.y, r.name) end)
        else row.frame:Hide() end
    end
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
    UI.Refresh()
end

local function create(parent)
    mainFrame = CreateFrame('Frame', nil, parent)
    mainFrame:SetAllPoints(parent)

    local tabDefs = {
        { id = 'sos', label = 'SOS PvP sauvage', w = 148 },
        { id = 'vendetta', label = 'Vendetta (Vengeance)', w = 166 },
        { id = 'camps', label = 'Feux de campement', w = 158 },
        { id = 'rares', label = 'Rares repérés', w = 130 },
    }
    if Q.SOSOnly() then tabDefs = { tabDefs[1] } end

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

    mainFrame.status = S.Text(mainFrame, 11, S.colors.gold, 'RIGHT')
    mainFrame.status:SetPoint('TOPRIGHT', -2, -8)

    local content = CreateFrame('Frame', nil, mainFrame)
    content:SetPoint('TOPLEFT', 0, -40)
    content:SetPoint('BOTTOMRIGHT', 0, 0)

    tabs.sos = createSOSPanel(content)
    tabs.vendetta = createVendettaPanel(content)
    tabs.camps = createCampPanel(content)
    tabs.rares = createRarePanel(content)

    mainFrame:SetScript('OnShow', function() Q.Run('fenêtre', UI.Refresh) end)
    switchTab(activeTab or 'sos')
end

function UI.Refresh()
    if not mainFrame or not mainFrame:IsVisible() then return end
    if mainFrame.status and Q.Summary then
        mainFrame.status:SetText(Q.Summary())
    end
    if activeTab == 'sos' then UI.RefreshSOS() end
    if activeTab == 'vendetta' then UI.RefreshVendetta() end
    if activeTab == 'camps' then UI.RefreshCamps() end
    if activeTab == 'rares' then UI.RefreshRares() end
end

function UI.Open(tabId)
    if not Q.ready and Q.Init then Q.Init() end
    if Q.SOSOnly() then tabId = tabId and 'sos' or nil end
    if tabId and (tabId == 'sos' or tabId == 'vendetta' or tabId == 'camps' or tabId == 'rares') then
        activeTab = tabId
    end
    Quintessence.UI.Open('map')
    if mainFrame and tabId then switchTab(activeTab) end
end

function UI.Toggle() Quintessence.UI.Toggle('map') end

Quintessence:RegisterModule({
    id = 'map',
    title = Q.SOSOnly() and 'SOS' or 'SOS & Camps',
    order = 55,
    icon = 'Interface\\Icons\\INV_BannerPVP_02',
    version = Q.version,
    width = 760,
    height = 440,
    create = function(parent)
        create(parent)
        return mainFrame
    end,
    refresh = function() UI.Refresh() end,
    summary = function()
        if not Q.ready then return nil end
        return Q.Summary and Q.Summary() or 'Carte tactique'
    end,
})
