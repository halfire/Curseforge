local _, Q = ...
--[[
  UI.lua : Interface utilisateur du module Quinte-group dans la fenêtre Quintessence (1078 × 658).
  Trois sous-onglets :
    1. Quêtes partagées : journal local et regroupement en 1 clic sur les quêtes communes.
    2. Recherche donjons : besoins par donjon, matrice anti-conflit de butin et groupe compatible.
    3. Codex secret : encyclopédie partagée des nouveaux objets rares et épiques de WoW Forever.
  Règle Retail 12+ : uniquement nos propres cadres, aucune écriture dans les objets de Blizzard.
]]

local UI = {}
Q.UI = UI
local S = Quintessence.Style

local QUALITY_HEX = { [0] = 'ff9d9d9d', 'ffffffff', 'ff1eff00', 'ff0070dd', 'ffa335ee', 'ffff8000', 'ffe6cc80' }
local ROLE_TAGS = {
    TANK = '|cff6fa8ff[Tank]|r',
    HEALER = '|cff5cd1a8[Soin]|r',
    DAMAGER = '|cffe5545c[DPS]|r',
}

local function classHex(class)
    local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[class or '']
    local hex = color and color.colorStr
    return (type(hex) == 'string' and hex:match('^%x%x%x%x%x%x%x%x$')) and hex or 'ffffffff'
end

local function invitePlayer(name)
    if not name then return end
    -- Déjà dans notre groupe : pas d'invitation (le jeu répondrait « déjà dans un groupe »)
    if Q.InMyGroup and Q.InMyGroup(name) then return false end
    if Quintessence and Quintessence.Invite then
        Quintessence.Invite(name)
    elseif C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

local function showItemTooltip(owner, itemIDOrLink)
    if not itemIDOrLink or not GameTooltip then return end
    GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
    local link = type(itemIDOrLink) == 'number' and ('item:' .. itemIDOrLink) or tostring(itemIDOrLink)
    Q.Call(GameTooltip.SetHyperlink, GameTooltip, link)
    GameTooltip:Show()
end

--- Infobulle d'une quête de donjon : fiche du jeu (objectifs), puis ce que le groupe peut en faire.
local function showQuestTooltip(owner, q)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
    Q.Call(GameTooltip.SetHyperlink, GameTooltip, 'quest:' .. q.id)
    if GameTooltip.NumLines and GameTooltip:NumLines() == 0 then GameTooltip:AddLine(Q.Safe(q.title)) end
    if q.classes then GameTooltip:AddLine('Réservée à : ' .. q.classes, 1, 0.82, 0) end
    if q.minLevel then GameTooltip:AddLine('Niveau requis : ' .. q.minLevel, 1, 1, 1) end
    if q.tag then GameTooltip:AddLine('(' .. q.tag .. ')', 1, 0.82, 0) end
    if q.chain then
        -- Chaîne complète en puces : prérequis, cette quête, suites (Wowhead Forever)
        local STATE = { done = 'faite', log = 'en cours', todo = 'à faire', locked = 'à faire', low = 'à faire' }
        GameTooltip:AddLine('Chaîne de quêtes :', 1, 0.82, 0)
        for i, step in ipairs(q.chain) do
            -- Chaque étape décalée d'un cran de plus que la précédente
            local label = string.rep('    ', i - 1) .. '• ' .. Q.Safe(step.title or ('quête ' .. step.id))
            if step.here then
                GameTooltip:AddLine(label .. ' ← celle-ci', 0.36, 0.82, 0.66, true)
            else
                local where = step.inDungeon and 'dans ce donjon' or nil
                local note = (step.step or 'étape') .. (where and (', ' .. where) or '') .. ', ' .. (STATE[step.state] or 'à faire')
                GameTooltip:AddLine(label .. ' (' .. note .. ')', 1, 1, 1, true)
            end
        end
    elseif q.prev then
        local where = q.prevState == 'done' and 'faite' or (q.prevState == 'log' and 'en cours' or 'pas faite')
        GameTooltip:AddLine('Suite de : ' .. Q.Safe(q.prevTitle or ('quête ' .. q.prev)) .. ' (' .. where .. ')', 1, 1, 1, true)
    end
    if q.start then GameTooltip:AddLine('Donneur : ' .. Q.Safe(q.start), 1, 1, 1, true) end
    if not q.known then GameTooltip:AddLine('Classe et quête précédente non vérifiées', 0.6, 0.6, 0.6, true) end
    if q.state == 'log' then
        GameTooltip:AddLine(q.shareable and 'Partageable avec le groupe' or 'Ne peut pas être partagée', 1, 0.82, 0)
    end
    if #q.holders > 0 then GameTooltip:AddLine('L\'ont : ' .. Q.Safe(table.concat(q.holders, ', ')), 1, 1, 1, true) end
    if #q.groupMissing > 0 then GameTooltip:AddLine('Pas dans le journal de : ' .. Q.Safe(table.concat(q.groupMissing, ', ')), 1, 1, 1, true) end
    GameTooltip:Show()
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local mainFrame
local tabs = {}
local activeTab = 'leveling'

-- =========================================================================
-- ONGLET 1 : COMPAGNON LEVELING & QUÊTES PARTAGÉES
-- =========================================================================

-- Onglet de la grande fenêtre Quintessence (1.38.1+) : 1078 × 658 à l'échelle 1, textes de la même taille qu'avant.
-- Chaque sous-onglet occupe PW × PH sous la barre d'onglets.
local W, H = 1078, 658
local PW, PH = W, H - 40
local MY_W = 380                                   -- Quêtes : mes quêtes à gauche, quêtes en commun à droite
local SHARED_W = PW - MY_W - 12                    -- 686
local MY_ROWS = math.floor((PH - 154) / 27)        -- 17
local QUEST_ROWS = math.floor((PH - 76) / 39)      -- 13
local sharedOpen, sharedOffset = nil, 0 -- quête ouverte dans « Quêtes partagées », décalage de la molette

local function createLevelingPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    -- Colonne gauche : Mes quêtes actives
    local leftBox = S.Box(panel, S.colors.panel, S.colors.line)
    leftBox:SetPoint('TOPLEFT', 0, 0)
    leftBox:SetSize(MY_W, PH)

    local myHeading = S.Heading(leftBox, 'Mon journal de quêtes')
    myHeading:SetPoint('TOPLEFT', 14, -12)

    panel.myRows = {}
    for i = 1, MY_ROWS do
        local row = S.Row(leftBox, MY_W - 2, 26)
        row:SetPoint('TOPLEFT', 1, -34 - (i - 1) * 27)
        row.dot = S.Fill(row, 'ARTWORK', S.colors.gold)
        row.dot:SetSize(6, 6); row.dot:SetPoint('LEFT', 12, 0)
        row.lvl = S.Text(row, 11, S.colors.gold)
        row.lvl:SetPoint('LEFT', 24, 0); row.lvl:SetWidth(28)
        row.title = S.Text(row, 12, S.colors.text)
        row.title:SetPoint('LEFT', 54, 0); row.title:SetPoint('RIGHT', -10, 0)
        panel.myRows[i] = row
    end

    local btnSync = S.Button(leftBox, 'Scanner & diffuser mes quêtes', 248, 28, 'primary')
    btnSync:SetPoint('BOTTOMLEFT', 14, 14)
    -- Annonce de la progression des quêtes dans le chat du groupe (désactivée au départ)
    panel.announce = S.Button(leftBox, '', 248, 24, 'ghost')
    panel.announce:SetPoint('BOTTOMLEFT', 14, 48)
    panel.announce:SetScript('OnClick', function() Q.SetAnnounceProgress(not Q.AnnounceProgressOn()); UI.RefreshLeveling() end)
    btnSync:SetScript('OnClick', function()
        Q.BroadcastMyQuests(true)
        UI.RefreshLeveling()
    end)

    -- Colonne droite : Quêtes en commun avec la guilde
    local rightBox = S.Box(panel, S.colors.panel, S.colors.line)
    rightBox:SetPoint('TOPLEFT', MY_W + 12, 0)
    rightBox:SetSize(SHARED_W, PH)

    local sharedHeading = S.Heading(rightBox, 'Quêtes en commun avec la guilde')
    sharedHeading:SetPoint('TOPLEFT', 16, -12)
    sharedHeading:SetWidth(SHARED_W - 202)
    panel.sharedHeading = sharedHeading

    -- Liste des personnes d'une quête : retour à la liste, inviter tout le monde
    panel.back = S.Button(rightBox, 'Retour', 64, 22, 'ghost')
    panel.back:SetPoint('TOPRIGHT', -12, -8)
    panel.back:SetScript('OnClick', function() UI.ShowSharedQuest(nil) end)
    panel.inviteAll = S.Button(rightBox, 'Inviter tous', 88, 22, 'ghost')
    panel.inviteAll:SetPoint('TOPRIGHT', -82, -8)

    panel.sharedCount = S.Text(rightBox, 11, S.colors.muted, 'RIGHT')
    panel.sharedCount:SetPoint('TOPRIGHT', -16, -12)
    -- XP des membres du groupe (envoyée par leur addon)
    panel.partyXP = S.Text(rightBox, 11, S.colors.muted)
    panel.partyXP:SetPoint('BOTTOMLEFT', 16, 10); panel.partyXP:SetWidth(SHARED_W - 32); panel.partyXP:SetWordWrap(true)

    panel.rows = {}
    for i = 1, QUEST_ROWS do
        local r = S.Row(rightBox, SHARED_W - 2, 38)
        r:SetPoint('TOPLEFT', 1, -36 - (i - 1) * 39)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(22, 22); icon:SetPoint('LEFT', 12, 0)
        icon:SetTexture('Interface\\Icons\\INV_Misc_Book_08')
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local qText = S.Text(r, 13, S.colors.text)
        qText:SetPoint('TOPLEFT', 42, -5)
        qText:SetWidth(SHARED_W - 172)

        local mText = S.Text(r, 11, S.colors.muted)
        mText:SetPoint('TOPLEFT', 42, -21)
        mText:SetWidth(SHARED_W - 172)

        local count = S.Text(r, 12, S.colors.gold, 'RIGHT')
        count:SetPoint('RIGHT', -14, 0)
        count:SetWidth(100)

        local invBtn = S.Button(r, 'Inviter', 96, 24, 'primary')
        invBtn:SetPoint('RIGHT', -12, 0)

        -- Clic : sur une quête, ses personnes ; sur une personne, un chuchotement
        r:SetScript('OnClick', function(self)
            if self.sharedTitle then UI.ShowSharedQuest(self.sharedTitle)
            elseif self.memberName then Quintessence.Whisper(self.memberName) end
        end)

        panel.rows[i] = { frame = r, qText = qText, mText = mText, count = count, invBtn = invBtn }
    end

    rightBox:EnableMouseWheel(true)
    rightBox:SetScript('OnMouseWheel', function(_, delta)
        sharedOffset = math.max(0, sharedOffset - delta)
        UI.RefreshLeveling()
    end)

    local emptyText = S.Text(rightBox, 12, S.colors.muted, 'CENTER')
    emptyText:SetPoint('CENTER', 0, -10)
    emptyText:SetWidth(SHARED_W - 92)
    emptyText:SetWordWrap(true)
    emptyText:SetText('Aucune quête en commun détectée pour l\'instant.\nClique sur « Scanner & diffuser mes quêtes » pour comparer ton journal avec la guilde.')
    panel.emptyText = emptyText

    return panel
end

function UI.RefreshLeveling()
    local p = tabs.leveling
    if not p or not p:IsVisible() then return end

    local myQuests = Q.GetMyQuests and Q.GetMyQuests() or {}
    for i, row in ipairs(p.myRows) do
        local mq = myQuests[i]
        if mq then
            row.lvl:SetText('[' .. (mq.level or 0) .. ']')
            row.title:SetText(Q.Safe(mq.title))
            row:Show()
        else
            row:Hide()
        end
    end

    p.announce:SetLabel(Q.AnnounceProgressOn() and 'Progression annoncée au groupe : oui' or 'Progression annoncée au groupe : non')
    p.announce:SetActive(Q.AnnounceProgressOn())
    local xp = Q.PartyXP and Q.PartyXP() or {}
    if #xp > 0 then
        local parts = {}
        for _, m in ipairs(xp) do parts[#parts + 1] = string.format('%s %d (%d %%)', Q.Safe(Quintessence.DisplayName(m.name)), m.level, m.percent) end
        p.partyXP:SetText('|c' .. S.hex.gold .. 'XP du groupe :|r ' .. table.concat(parts, ' · '))
    else p.partyXP:SetText('') end

    local shared = Q.FindSharedQuests and Q.FindSharedQuests(myQuests) or {}
    -- Quête ouverte : ses personnes, ou retour à la liste si plus personne ne l'a
    local opened
    for _, q in ipairs(shared) do if q.title == sharedOpen then opened = q end end
    if not opened then sharedOpen, sharedOffset = nil, 0 end

    p.back:SetShown(opened ~= nil)
    p.inviteAll:SetShown(false)
    p.sharedCount:SetShown(opened == nil)

    if opened then
        p.sharedHeading:SetText(Q.Safe(opened.title))
        p.emptyText:Hide()
        local outside = 0
        for _, m in ipairs(opened.members) do if not Q.InMyGroup(m.name) then outside = outside + 1 end end
        p.inviteAll:SetShown(outside > 0)
        p.inviteAll:SetScript('OnClick', function()
            local sent = 0
            for _, m in ipairs(opened.members) do
                if not Q.InMyGroup(m.name) and invitePlayer(m.name) ~= false then sent = sent + 1 end
            end
            Q.Print(sent .. ' invitation(s) envoyée(s) pour la quête : ' .. Q.Safe(opened.title))
        end)
        sharedOffset = math.max(0, math.min(sharedOffset, math.max(0, #opened.members - QUEST_ROWS)))
        for i, r in ipairs(p.rows) do
            local m = opened.members[sharedOffset + i]
            if m then
                local inGroup = Q.InMyGroup(m.name)
                r.frame:Show()
                r.frame.sharedTitle = nil
                r.frame.memberName = m.name
                r.count:SetText('')
                r.qText:SetPoint('TOPLEFT', 42, -5)
                r.qText:SetText(string.format('|c%s%s|r |c%sniv. %d|r', classHex(m.class), Q.Safe(m.name), S.hex.muted, m.level or 60))
                local where = Quintessence.Layer and Quintessence.Layer.Where and Quintessence.Layer.Where(m.name)
                r.mText:SetText(inGroup and ('|c' .. S.hex.mint .. 'dans ton groupe|r') or (where and Q.Safe(where) or ''))
                r.invBtn:SetShown(not inGroup)
                r.invBtn:SetScript('OnClick', function()
                    if invitePlayer(m.name) ~= false then Q.Print('Invitation envoyée à ' .. Q.Safe(m.name) .. '.') end
                end)
            else
                r.frame:Hide()
            end
        end
        return
    end

    p.sharedHeading:SetText('Quêtes en commun avec la guilde')
    p.sharedCount:SetText(#shared .. ' quête' .. (#shared > 1 and 's' or '') .. ' partagée' .. (#shared > 1 and 's' or ''))

    if #shared == 0 then
        p.emptyText:Show()
        for _, r in ipairs(p.rows) do r.frame:Hide() end
        return
    end
    p.emptyText:Hide()

    sharedOffset = math.max(0, math.min(sharedOffset, math.max(0, #shared - QUEST_ROWS)))
    for i, r in ipairs(p.rows) do
        local q = shared[sharedOffset + i]
        if q then
            r.frame:Show()
            r.frame.sharedTitle = q.title
            r.frame.memberName = nil
            r.qText:SetPoint('TOPLEFT', 42, -12)
            r.qText:SetText(string.format('|c%s[%d]|r  %s', S.hex.gold, q.level or 0, Q.Safe(q.title)))
            r.mText:SetText('')
            r.count:SetText(#q.members .. (#q.members > 1 and ' personnes' or ' personne'))
            r.invBtn:Hide()
        else
            r.frame:Hide()
        end
    end
end

--- Ouvre la liste des personnes d'une quête en commun (nil : retour à la liste des quêtes).
function UI.ShowSharedQuest(title)
    sharedOpen, sharedOffset = title, 0
    UI.RefreshLeveling()
end

-- =========================================================================
-- ONGLET 2 : RECHERCHE DONJONS, BESOINS & ANTI-CONFLIT DE BUTIN
-- =========================================================================

local dungeonState = {
    selectedDungeon = 'DM',
    dungeonOffset = 0,
    memberOffset = 0,
    lootOffset = 0,
    showQuests = true -- quêtes du donjon affichées d'abord, les butins au clic
}

local DL_W = 260                                   -- Donjons : liste à gauche, détail à droite
local DR_W = PW - DL_W - 12                        -- 806
local IW = DR_W - 28                               -- 778 : largeur intérieure du détail
local D_ROWS = math.floor((PH - 58) / 38)          -- 14 donjons
local M_ROWS = 8                                   -- membres inscrits
local L_ROWS = math.floor((PH - 48 - 96 - (M_ROWS * 26 + 4) - 28 - 18) / 27) -- objets recherchés
local LOOT_Y = -96 - (M_ROWS * 26 + 4) - 12

local function createDungeonsPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    -- 1. Barre de préférences en haut
    local prefBox = S.Box(panel, S.colors.panel, S.colors.line)
    prefBox:SetPoint('TOPLEFT', 0, 0)
    prefBox:SetSize(PW, 38)

    local roleLabel = S.Text(prefBox, 11, S.colors.gold)
    roleLabel:SetPoint('LEFT', 12, 0)
    roleLabel:SetText('Mon rôle :')

    local currentRole = (QuinteGroupDB and QuinteGroupDB.myPreferences and QuinteGroupDB.myPreferences.role) or 'DAMAGER'
    local roleButtons = {}
    local roles = {
        { id = 'TANK', label = 'Tank', w = 64 },
        { id = 'HEALER', label = 'Soigneur', w = 78 },
        { id = 'DAMAGER', label = 'DPS', w = 58 },
    }

    local posX = 76
    for _, r in ipairs(roles) do
        local b = S.Button(prefBox, r.label, r.w, 24, 'ghost')
        b:SetPoint('LEFT', posX, 0)
        b:SetActive(r.id == currentRole)
        b:SetScript('OnClick', function()
            currentRole = r.id
            for id, btn in pairs(roleButtons) do btn:SetActive(id == currentRole) end
        end)
        roleButtons[r.id] = b
        posX = posX + r.w + 6
    end
    panel.roleButtons = roleButtons

    local noteInput = S.Input(prefBox, 286 + PW - 760, 'Note (ex. clé UBRS dispo, farm BiS)…')
    noteInput:SetPoint('LEFT', posX + 8, 0)
    panel.noteInput = noteInput

    local btnSavePref = S.Button(prefBox, 'S\'inscrire sur ce donjon', 166, 24, 'primary')
    btnSavePref:SetPoint('RIGHT', -10, 0)
    btnSavePref:SetScript('OnClick', function()
        local note = noteInput:GetText()
        local sel = dungeonState.selectedDungeon
        -- Ajoute ou retire CE donjon ; les autres inscriptions restent
        local signed = Q.ToggleDungeonSignup(sel, currentRole, note)
        local list = Q.MySignups()
        Q.Print(string.format('%s %s (rôle %s). Inscrit sur %d donjon(s)%s.', signed and 'Inscrit sur' or 'Désinscrit de', Q.Safe(sel),
            currentRole, #list, #list > 0 and (' : ' .. table.concat(list, ', ')) or ''))
    end)
    panel.btnSavePref = btnSavePref

    -- 2. Colonne de gauche : Liste des donjons, noms courts
    local leftBox = S.Box(panel, S.colors.panel, S.colors.line)
    leftBox:SetPoint('TOPLEFT', 0, -48)
    leftBox:SetSize(DL_W, PH - 48)
    leftBox:EnableMouseWheel(true)
    leftBox:SetScript('OnMouseWheel', function(_, delta)
        dungeonState.dungeonOffset = math.max(0, dungeonState.dungeonOffset - delta * 2)
        UI.RefreshDungeons()
    end)

    local dungeonRows = {}
    for i = 1, D_ROWS do
        local row = S.Row(leftBox, DL_W - 16, 36)
        row:SetPoint('TOPLEFT', 1, -6 - (i - 1) * 38)

        row.icon = row:CreateTexture(nil, 'ARTWORK')
        row.icon:SetSize(22, 22); row.icon:SetPoint('LEFT', 10, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = S.Text(row, 12, S.colors.text)
        row.name:SetPoint('TOPLEFT', 38, -4)
        row.name:SetWidth(DL_W - 98)

        row.count = S.Text(row, 11, S.colors.mint, 'RIGHT')
        row.count:SetPoint('TOPRIGHT', -8, -4)

        row.sub = S.Text(row, 10, S.colors.muted)
        row.sub:SetPoint('TOPLEFT', 38, -20)
        row.sub:SetWidth(DL_W - 60)

        row:SetScript('OnClick', function()
            if row.dungeonCode then
                dungeonState.selectedDungeon = row.dungeonCode
                dungeonState.memberOffset = 0
                dungeonState.lootOffset = 0
                UI.RefreshDungeons()
            end
        end)

        dungeonRows[i] = row
    end
    panel.dungeonRows = dungeonRows

    panel.dungeonScroll = S.Scrollbar(leftBox, D_ROWS * 38 - 4, function(offset)
        if offset ~= dungeonState.dungeonOffset then
            dungeonState.dungeonOffset = offset
            UI.RefreshDungeons()
        end
    end)
    panel.dungeonScroll:SetPoint('TOPLEFT', DL_W - 12, -6)

    -- 3. Colonne de droite : Détails du donjon, membres et matrice de butin
    local rightBox = S.Box(panel, S.colors.panel, S.colors.line)
    rightBox:SetPoint('TOPLEFT', DL_W + 12, -48)
    rightBox:SetSize(DR_W, PH - 48)
    panel.rightBox = rightBox

    local dIcon = rightBox:CreateTexture(nil, 'ARTWORK')
    dIcon:SetSize(28, 28); dIcon:SetPoint('TOPLEFT', 14, -12)
    dIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    panel.dIcon = dIcon

    local dTitle = S.Text(rightBox, 15, S.colors.text)
    dTitle:SetPoint('TOPLEFT', 50, -11)
    dTitle:SetWidth(DR_W - 390)
    panel.dTitle = dTitle

    local dSub = S.Text(rightBox, 11, S.colors.muted)
    dSub:SetPoint('TOPLEFT', 50, -29)
    dSub:SetWidth(DR_W - 390)
    panel.dSub = dSub

    local btnInviteComp = S.Button(rightBox, 'Groupe sans conflit', 142, 24, 'primary')
    btnInviteComp:SetPoint('TOPRIGHT', -12, -12)
    btnInviteComp:SetScript('OnClick', function()
        Q.InviteCompatibleGroup(dungeonState.selectedDungeon)
    end)
    panel.btnInviteComp = btnInviteComp
    panel.btnDungeonMap = S.Button(rightBox, 'Plans', 70, 24, 'ghost')
    panel.btnDungeonMap:SetScript('OnClick', function()
        if Quintessence.ShowDungeonMap then Quintessence.ShowDungeonMap(dungeonState.selectedDungeon)
        else Q.Print('Installe quinte-bis pour consulter les plans de donjons.') end
    end)

    local btnInviteAll = S.Button(rightBox, 'Inviter tous', 88, 24, 'ghost')
    btnInviteAll:SetPoint('RIGHT', btnInviteComp, 'LEFT', -6, 0)
    btnInviteAll:SetScript('OnClick', function()
        local needs = Q.GetDungeonNeeds(dungeonState.selectedDungeon)
        local count = 0
        local myName = Q.PlayerName and Q.PlayerName()
        for _, m in ipairs(needs.members) do
            if m.name ~= myName and not m.inGroup and invitePlayer(m.name) ~= false then
                count = count + 1
            end
        end
        Q.Print(string.format('%d invitation(s) envoyée(s) pour %s.', count, needs.name))
    end)
    panel.btnInviteAll = btnInviteAll
    panel.btnDungeonMap:SetPoint('RIGHT', btnInviteAll, 'LEFT', -6, 0)

    -- Bandeau d'état des conflits de butin
    local banner = S.Box(rightBox, S.colors.bg, S.colors.line)
    banner:SetPoint('TOPLEFT', 14, -48)
    banner:SetSize(IW, 24)
    panel.banner = banner

    local bannerDot = S.Fill(banner, 'ARTWORK', S.colors.mint)
    bannerDot:SetSize(8, 8); bannerDot:SetPoint('LEFT', 10, 0)
    panel.bannerDot = bannerDot

    local bannerText = S.Text(banner, 11, S.colors.text)
    bannerText:SetPoint('LEFT', 24, 0)
    bannerText:SetWidth(IW - 334)
    panel.bannerText = bannerText

    -- Repère, flèche et carte ouverte sur l'entrée du donjon affiché
    panel.btnEntrance = S.Button(banner, 'Afficher l\'entrée', 108, 20, 'ghost')
    panel.btnEntrance:SetPoint('RIGHT', -68, 0)
    panel.btnEntrance:SetScript('OnClick', function() Q.Run('entrée', Q.ShowDungeonEntrance, dungeonState.selectedDungeon) end)
    panel.btnEntranceRoute = S.Button(banner, 'Chemin', 60, 20, 'ghost')
    panel.btnEntranceRoute:SetPoint('RIGHT', -2, 0)
    panel.btnEntranceRoute:SetScript('OnClick', function()
        Q.Run('chemin entrée', Q.ShowDungeonEntrance, dungeonState.selectedDungeon, true)
    end)
    -- Où prendre les quêtes : ouvre leur liste (bouton « Carte » sur chaque ligne) et écrit les lieux dans le chat
    panel.btnQuestPlaces = S.Button(banner, 'Lieux des quêtes', 112, 20, 'ghost')
    panel.btnQuestPlaces:SetPoint('RIGHT', panel.btnEntrance, 'LEFT', -6, 0)
    panel.btnQuestPlaces:SetScript('OnClick', function()
        dungeonState.showQuests = true; dungeonState.lootOffset = 0; UI.RefreshDungeons()
        Q.Run('lieux des quêtes', Q.PrintDungeonQuestPlaces, dungeonState.selectedDungeon)
    end)

    -- Section 1 : Membres disponibles & rôles
    local mHeading = S.Heading(rightBox, 'Membres inscrits · clic pour chuchoter')
    mHeading:SetPoint('TOPLEFT', 14, -80)
    panel.mHeading = mHeading

    -- Officiers : vider les inscriptions du donjon affiché (Maj-clic : tous les donjons), deuxième clic pour confirmer
    panel.btnReset = S.Button(rightBox, 'Vider les inscriptions', 132, 18, 'danger')
    panel.btnReset:SetPoint('TOPRIGHT', -12, -77)
    panel.btnReset:SetScript('OnClick', function(self)
        local all = IsShiftKeyDown and IsShiftKeyDown() and true or false
        local now = GetTime and GetTime() or 0
        if not (self.armed and now - self.armed < 5 and self.armedAll == all) then
            self.armed, self.armedAll = now, all
            self:SetLabel(all and 'Confirmer : tous' or 'Confirmer')
            if C_Timer and C_Timer.After then
                C_Timer.After(5, function()
                    if self.armed == now then self.armed = nil; self:SetLabel('Vider les inscriptions') end
                end)
            end
            return
        end
        self.armed = nil
        self:SetLabel('Vider les inscriptions')
        local ok, err = Q.ResetSignups(not all and dungeonState.selectedDungeon or nil)
        if not ok then Q.Print(err) end
    end)
    if panel.btnReset.HookScript then panel.btnReset:HookScript('OnEnter', function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, 'ANCHOR_TOP')
        GameTooltip:AddLine('Vider les inscriptions', 1, 0.82, 0)
        GameTooltip:AddLine('Retire les inscriptions de ce donjon chez toute la guilde, même les absents.', 1, 1, 1, true)
        GameTooltip:AddLine('Maj-clic : tous les donjons. Cliquer deux fois pour confirmer.', 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    panel.btnReset:HookScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end) end

    local memberBox = S.Box(rightBox, S.colors.bg, S.colors.line)
    memberBox:SetPoint('TOPLEFT', 14, -96)
    memberBox:SetSize(IW, M_ROWS * 26 + 4)
    memberBox:EnableMouseWheel(true)
    memberBox:SetScript('OnMouseWheel', function(_, delta)
        dungeonState.memberOffset = math.max(0, dungeonState.memberOffset - delta)
        UI.RefreshDungeons()
    end)

    local memberRows = {}
    for i = 1, M_ROWS do
        local r = S.Row(memberBox, IW - 2, 25)
        r:SetPoint('TOPLEFT', 1, -2 - (i - 1) * 26)

        local dot = S.Fill(r, 'ARTWORK', S.colors.mint)
        dot:SetSize(7, 7); dot:SetPoint('LEFT', 10, 0)

        local roleText = S.Text(r, 11, S.colors.text)
        roleText:SetPoint('LEFT', 22, 0); roleText:SetWidth(46)

        local nameText = S.Text(r, 12, S.colors.text)
        nameText:SetPoint('LEFT', 70, 0); nameText:SetWidth(255)

        local lootSummary = S.Text(r, 11, S.colors.muted)
        lootSummary:SetPoint('LEFT', 330, 0); lootSummary:SetWidth(IW - 407)

        local invBtn = S.Button(r, 'Inviter', 64, 20, 'ghost')
        invBtn:SetPoint('RIGHT', -6, 0)

        r:SetScript('OnClick', function(self)
            if self.memberName and not Quintessence.SameName(self.memberName, Q.PlayerName()) then
                Quintessence.Whisper(self.memberName)
            end
        end)

        memberRows[i] = {
            frame = r,
            dot = dot,
            roleText = roleText,
            nameText = nameText,
            lootSummary = lootSummary,
            invBtn = invBtn
        }
    end
    panel.memberRows = memberRows

    local memberEmpty = S.Text(memberBox, 11, S.colors.muted, 'CENTER')
    memberEmpty:SetPoint('CENTER', 0, 0)
    memberEmpty:SetText('Aucun membre inscrit sur ce donjon pour l\'instant.')
    panel.memberEmpty = memberEmpty

    -- Section 2 : Matrice des butins convoités & anti-conflit
    local lHeading = S.Heading(rightBox, 'Butins convoités & concurrence')
    lHeading:SetPoint('TOPLEFT', 14, LOOT_Y)
    panel.lHeading = lHeading
    -- Bascule : butins convoités ↔ quêtes à prendre avant le donjon ; lien vers le butin des boss (quinte-bis)
    panel.questToggle = S.Button(rightBox, 'Quêtes', 76, 20, 'ghost')
    panel.questToggle:SetPoint('TOPRIGHT', -100, -206)
    panel.questToggle:SetScript('OnClick', function()
        dungeonState.showQuests = not dungeonState.showQuests; dungeonState.lootOffset = 0; UI.RefreshDungeons()
    end)
    panel.bossLoot = S.Button(rightBox, 'Butin des boss', 82, 20, 'ghost')
    panel.bossLoot:SetPoint('TOPRIGHT', -12, -206)
    panel.bossLoot:SetScript('OnClick', function()
        if dungeonState.showQuests then Q.AnnounceMissingQuests(dungeonState.selectedDungeon); return end
        local show = Quintessence.ShowBossLoot
        if show then show(dungeonState.selectedDungeon) else Q.Print('Installe quinte-bis pour voir le butin des boss.') end
    end)

    local lootBox = S.Box(rightBox, S.colors.bg, S.colors.line)
    lootBox:SetPoint('TOPLEFT', 14, LOOT_Y - 16)
    lootBox:SetSize(IW, L_ROWS * 27 + 4)
    lootBox:EnableMouseWheel(true)
    lootBox:SetScript('OnMouseWheel', function(_, delta)
        dungeonState.lootOffset = math.max(0, dungeonState.lootOffset - delta)
        UI.RefreshDungeons()
    end)

    local lootRows = {}
    for i = 1, L_ROWS do
        local r = S.Row(lootBox, IW - 2, 26)
        r:SetPoint('TOPLEFT', 1, -2 - (i - 1) * 27)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(18, 18); icon:SetPoint('LEFT', 8, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local itemName = S.Text(r, 12, S.colors.text)
        itemName:SetPoint('LEFT', 32, 0); itemName:SetWidth(310)

        local membersList = S.Text(r, 11, S.colors.muted, 'RIGHT')
        membersList:SetPoint('RIGHT', -10, 0); membersList:SetWidth(IW - 360)

        local action = S.Button(r, 'Partager', 64, 20, 'ghost')
        action:SetPoint('RIGHT', -6, 0)
        action:Hide()

        -- Repère sur le donneur de la quête
        local place = S.Button(r, 'Carte', 46, 20, 'ghost')
        place:SetPoint('RIGHT', -74, 0)
        place:Hide()
        local route = S.Button(r, 'Chemin', 54, 20, 'ghost')
        route:SetPoint('RIGHT', -124, 0)
        route:Hide()

        r:SetScript('OnEnter', function(self)
            if self.quest then showQuestTooltip(self, self.quest) else showItemTooltip(self, self.itemID) end
        end)
        r:SetScript('OnClick', function(self) if self.itemID then Quintessence.LinkItem(self.itemID) end end)
        r:SetScript('OnLeave', hideTooltip)

        lootRows[i] = {
            frame = r,
            icon = icon,
            itemName = itemName,
            membersList = membersList,
            action = action,
            route = route,
            place = place
        }
    end
    panel.lootRows = lootRows

    local lootEmpty = S.Text(lootBox, 11, S.colors.muted, 'CENTER')
    lootEmpty:SetPoint('CENTER', 0, 0)
    lootEmpty:SetText('Aucun butin spécifique déclaré pour ce donjon.')
    panel.lootEmpty = lootEmpty

    return panel
end

function UI.RefreshDungeons()
    local p = tabs.dungeons
    if not p or not p:IsVisible() then return end

    local allNeeds = Q.GetAllDungeonNeeds and Q.GetAllDungeonNeeds() or {}
    local dCount = #allNeeds
    if dCount == 0 then return end

    dungeonState.dungeonOffset = math.max(0, math.min(dungeonState.dungeonOffset, math.max(0, dCount - D_ROWS)))
    p.dungeonScroll:SetMinMaxValues(0, math.max(0, dCount - D_ROWS))
    p.dungeonScroll:SetValue(dungeonState.dungeonOffset)

    local selectedNeeds = nil
    for _, nd in ipairs(allNeeds) do
        if nd.code == dungeonState.selectedDungeon then
            selectedNeeds = nd
            break
        end
    end
    if not selectedNeeds and allNeeds[1] then
        selectedNeeds = allNeeds[1]
        dungeonState.selectedDungeon = selectedNeeds.code
    end

    for i = 1, D_ROWS do
        local r = p.dungeonRows[i]
        local d = allNeeds[dungeonState.dungeonOffset + i]
        if d then
            r:Show()
            r.dungeonCode = d.code
            r:SetSelected(d.code == dungeonState.selectedDungeon)
            r.icon:SetTexture('Interface\\Icons\\' .. (d.icon or 'INV_Misc_QuestionMark'))
            r.name:SetText(Q.Safe(d.short or d.name))

            if d.totalMembers > 0 then
                r.count:SetText(d.totalMembers .. ' mbr')
                r.count:SetTextColor(unpack(S.colors.mint))
            else
                r.count:SetText('0')
                r.count:SetTextColor(unpack(S.colors.muted))
            end

            -- Colonne étroite : l'état du butin passe avant la mention Forever (reprise à droite)
            local lvlText = string.format('niv. %d-%d', d.minLvl or 13, d.maxLvl or 60)
            if d.hasConflicts then
                lvlText = lvlText .. ' · |c' .. S.hex.red .. d.conflictCount .. ' conflit(s)|r'
            elseif d.totalMembers > 1 and d.totalLoots > 0 then
                lvlText = lvlText .. ' · |c' .. S.hex.mint .. 'Sans conflit|r'
            elseif d.new then
                lvlText = lvlText .. ' · |c' .. S.hex.gold .. 'Forever|r'
            end
            r.sub:SetText(lvlText)
        else
            r:Hide()
        end
    end

    if not selectedNeeds then return end

    -- Bouton d'inscription : ajoute ou retire le donjon affiché, les autres inscriptions restent
    if p.btnSavePref then
        p.btnSavePref:SetLabel(Q.IsSignedUp(selectedNeeds.code) and 'Me désinscrire' or 'S\'inscrire sur ce donjon')
    end

    p.dIcon:SetTexture('Interface\\Icons\\' .. (selectedNeeds.icon or 'INV_Misc_QuestionMark'))
    p.dTitle:SetText(Q.Safe(selectedNeeds.name))
    p.dSub:SetText(string.format('Niveau %d-%d · %d membre(s) · %d butin(s)%s',
        selectedNeeds.minLvl or 13, selectedNeeds.maxLvl or 60, selectedNeeds.totalMembers, selectedNeeds.totalLoots,
        selectedNeeds.new and (' · |c' .. S.hex.gold .. 'Forever|r') or ''))

    if selectedNeeds.hasConflicts then
        p.bannerDot:SetColorTexture(unpack(S.colors.red))
        p.bannerText:SetText(string.format('|c%s%d conflit(s) de butin :|r même objet convoité.',
            S.hex.red, selectedNeeds.conflictCount))
    elseif selectedNeeds.totalMembers > 0 then
        p.bannerDot:SetColorTexture(unpack(S.colors.mint))
        p.bannerText:SetText('|c' .. S.hex.mint .. 'Répartition optimale :|r aucun doublon de butin.')
    else
        p.bannerDot:SetColorTexture(unpack(S.colors.muted))
        p.bannerText:SetText('|c' .. S.hex.muted .. 'Aucun besoin enregistré sur ce donjon.|r')
    end

    local announce = Quintessence.Announce
    p.btnEntranceRoute:SetShown(Q.ENTRANCES[dungeonState.selectedDungeon] ~= nil)
    p.btnReset:SetShown(announce and announce.IsOfficer and announce.IsOfficer() and true or false)

    local members = selectedNeeds.members
    -- Non inscrits qui ont des objets BiS ici : comptés à part, jamais dans la liste (seule l'inscription y fait entrer)
    local bisOnly = selectedNeeds.bisOnly or {}
    local bisText = ''
    if #bisOnly > 0 then
        local mine = false
        for _, b in ipairs(bisOnly) do if b.isPlayer then mine = true end end
        bisText = string.format(' · |c%s+%d en BiS%s|r', S.hex.muted, #bisOnly, mine and ' (toi compris)' or '')
    end
    p.mHeading:SetText(string.format('Membres inscrits (%d)%s', #members, bisText))
    p.memberEmpty:SetShown(#members == 0)
    dungeonState.memberOffset = math.max(0, math.min(dungeonState.memberOffset, math.max(0, #members - M_ROWS)))

    for i = 1, M_ROWS do
        local r = p.memberRows[i]
        local m = members[dungeonState.memberOffset + i]
        if m then
            r.frame:Show()
            r.frame.memberName = m.name
            r.dot:SetColorTexture(unpack(m.online and S.colors.mint or S.colors.line))
            r.roleText:SetText(ROLE_TAGS[m.role] or ROLE_TAGS.DAMAGER)

            local cHex = classHex(m.class)
            local selfTag = m.isPlayer and (' |c' .. S.hex.gold .. '(toi)|r')
                or (m.inGroup and (' |c' .. S.hex.mint .. '(groupe)|r') or '')
            r.nameText:SetText(string.format('|c%s%s|r |c%sniv. %d|r%s', cHex, Q.Safe(m.name), S.hex.muted, m.level or 60, selfTag))

            if #m.items > 0 then
                r.lootSummary:SetText('|c' .. S.hex.gold .. #m.items .. ' objet(s) ciblé(s)|r')
            elseif m.note and m.note ~= '' then
                r.lootSummary:SetText(Q.Safe(m.note))
            else
                -- Où il est (dernière position partagée par quinte-layer), comme la zone du chef dans la recherche de groupe du jeu
                local where = Quintessence.Layer and Quintessence.Layer.Where and Quintessence.Layer.Where(m.name)
                r.lootSummary:SetText(where and ('Disponible · ' .. Q.Safe(where)) or 'Disponible')
            end

            r.invBtn:SetShown(not m.isPlayer and not m.inGroup)
            r.invBtn:SetScript('OnClick', function()
                invitePlayer(m.name)
                Q.Print('Invitation envoyée à ' .. m.name .. '.')
            end)
        else
            r.frame:Hide()
        end
    end

    local quests = Q.DungeonQuests and Q.DungeonQuests(selectedNeeds.code) or {}
    local questCount = #quests
    if Q.ChainOrder then quests = Q.ChainOrder(quests) end
    p.questToggle:SetLabel(dungeonState.showQuests and 'Butins' or ('Quêtes (' .. questCount .. ')'))
    p.questToggle:SetActive(dungeonState.showQuests and true or false)
    if dungeonState.showQuests then
        local todo, toShare = 0, 0
        local grouped = IsInGroup and IsInGroup() and true or false
        for _, q in ipairs(quests) do
            if q.state == 'todo' and not q.virtual then todo = todo + 1 end
            if q.shareable then toShare = toShare + 1 end
        end
        p.lHeading:SetText(string.format('Quêtes (%d) · %d à prendre · %d à partager', questCount, todo, toShare))
        p.bossLoot:SetLabel('Dire au groupe')
        p.bossLoot:SetEnabled(grouped and todo > 0)
        p.lootEmpty:SetShown(questCount == 0)
        p.lootEmpty:SetText('Aucune quête connue pour ce donjon.')
        dungeonState.lootOffset = math.max(0, math.min(dungeonState.lootOffset, math.max(0, #quests - L_ROWS)))
        for i = 1, L_ROWS do
            local r, q = p.lootRows[i], quests[dungeonState.lootOffset + i]
            if q then
                r.frame:Show(); r.frame.itemID = nil; r.frame.quest = q
                r.icon:SetTexture('Interface\\Icons\\INV_Misc_Note_01')
                -- Suite d'une chaîne : décalée d'un cran par étape (6 crans au plus), sous la précédente
                local depth = math.min(q.depth or 0, 6)
                local indent = depth > 0 and (string.rep('   ', depth - 1) .. '|c' .. S.hex.muted .. '└|r ') or ''
                if q.virtual then
                    -- Étape de la chaîne faite hors de ce donjon : ligne d'information, sans action
                    r.itemName:SetText(string.format('%s|c%s%s (%s)|r', indent, S.hex.muted, Q.Safe(q.title or ('quête ' .. q.id)), q.tag))
                    r.itemName:SetWidth(285)
                    r.membersList:SetPoint('RIGHT', -182, 0); r.membersList:SetWidth(IW - 506)
                    r.place:Hide(); r.route:Hide(); r.action:Hide()
                    r.membersList:SetText('|c' .. (q.state == 'done' and S.hex.mint or S.hex.muted) .. q.stateText .. '|r')
                else
                r.itemName:SetText(string.format('%s|c%s[%d]|r %s%s', indent, S.hex.gold, q.level, Q.Safe(q.title),
                    q.tag and (' |c' .. S.hex.muted .. '(' .. q.tag .. ')|r') or ''))
                r.itemName:SetWidth(285)
                r.membersList:SetPoint('RIGHT', -182, 0); r.membersList:SetWidth(IW - 506)
                r.place:SetShown(q.state ~= 'done' and Q.HasDungeonQuestPlace(q.id))
                r.place:SetScript('OnClick', function() Q.Run('lieu de quête', Q.ShowDungeonQuestPlace, q.id, q.title, selectedNeeds.code) end)
                r.route:SetShown(q.state ~= 'done' and Q.HasDungeonQuestPlace(q.id))
                r.route:SetScript('OnClick', function()
                    Q.Run('chemin quête', Q.ShowDungeonQuestPlace, q.id, q.title, selectedNeeds.code, true)
                end)
                local text
                if q.state == 'log' then
                    text = q.complete and ('|c' .. S.hex.gold .. 'à rendre|r') or ('|c' .. S.hex.mint .. 'en cours|r')
                    if q.shareable and #q.groupMissing > 0 then text = text .. ' · manque à ' .. Q.Safe(table.concat(q.groupMissing, ', '))
                    elseif not q.shareable then text = text .. ' · non partageable' end
                    r.action:SetLabel('Partager')
                    r.action:SetShown(q.shareable)
                    r.action:SetEnabled(grouped)
                    r.action:SetScript('OnClick', function() Q.ShareQuest(q.logId, q.title) end)
                elseif q.state == 'todo' then
                    text = '|c' .. S.hex.gold .. 'à prendre|r'
                    if #q.groupHas > 0 then text = text .. ' · ' .. Q.Safe(table.concat(q.groupHas, ', ')) .. ' l\'a'
                    elseif #q.holders > 0 then text = text .. ' · ' .. Q.Safe(table.concat(q.holders, ', ')) end
                    r.action:SetLabel('Demander')
                    r.action:SetShown(#q.groupHas > 0)
                    r.action:SetEnabled(true)
                    r.action:SetScript('OnClick', function() Q.AskQuest(q.title, q.groupHas, q.id) end)
                elseif q.state == 'locked' then
                    text = '|c' .. S.hex.muted .. 'après : ' .. Q.Safe(q.prevTitle or 'quête précédente') .. '|r'
                    r.action:Hide()
                elseif q.state == 'low' then
                    text = '|c' .. S.hex.muted .. 'niveau ' .. q.minLevel .. ' requis|r'
                    r.action:Hide()
                else
                    text = '|c' .. S.hex.muted .. 'faite|r'
                    r.action:Hide()
                end
                r.membersList:SetText(text)
                end
            else r.frame:Hide(); r.frame.quest = nil end
        end
        return
    end
    p.bossLoot:SetLabel('Butin des boss')
    p.bossLoot:SetEnabled(true)
    p.lootEmpty:SetText('Aucun butin spécifique déclaré pour ce donjon.')
    local loots = selectedNeeds.loots
    p.lHeading:SetText(string.format('Butins convoités & concurrence (%d)', #loots))
    p.lootEmpty:SetShown(#loots == 0)
    dungeonState.lootOffset = math.max(0, math.min(dungeonState.lootOffset, math.max(0, #loots - L_ROWS)))

    for i = 1, L_ROWS do
        local r = p.lootRows[i]
        local lt = loots[dungeonState.lootOffset + i]
        if lt then
            r.frame:Show()
            r.frame.itemID = lt.id
            r.frame.quest = nil
            r.action:Hide()
            r.place:Hide()
            r.route:Hide()
            r.itemName:SetWidth(310)
            r.membersList:SetPoint('RIGHT', -10, 0); r.membersList:SetWidth(IW - 360)
            r.icon:SetTexture(lt.icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
            local qHex = QUALITY_HEX[lt.quality or 3] or 'ffffffff'
            r.itemName:SetText('|c' .. qHex .. Q.Safe(lt.name) .. '|r')

            local names = {}
            for _, mem in ipairs(lt.members) do
                names[#names + 1] = '|c' .. classHex(mem.class) .. Q.Safe(mem.name) .. '|r'
            end
            if lt.hasConflict then
                r.membersList:SetText('|c' .. S.hex.red .. 'Conflit :|r ' .. table.concat(names, ', '))
            else
                r.membersList:SetText('|c' .. S.hex.mint .. 'Exclusif :|r ' .. (names[1] or ''))
            end
        else
            r.frame:Hide()
        end
    end
end

-- =========================================================================
-- ONGLET 3 : LE CODEX SECRET DE QUINTESSENCE
-- =========================================================================

local CODEX_ROWS = math.floor((PH - 44) / 35) -- 16
local codexOffset = 0

local function createCodexPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    local searchInput = S.Input(panel, 420, 'Rechercher un objet ou une zone…')
    searchInput:SetPoint('TOPLEFT', 0, 0)
    searchInput:SetScript('OnTextChanged', function(self)
        if self.placeholder then self.placeholder:SetShown((self:GetText() or '') == '') end
        codexOffset = 0
        UI.RefreshCodex(self:GetText())
    end)
    panel.searchInput = searchInput

    local countText = S.Text(panel, 12, S.colors.muted, 'RIGHT')
    countText:SetPoint('TOPRIGHT', -2, -6)
    panel.countText = countText

    local listBox = S.Box(panel, S.colors.panel, S.colors.line)
    listBox:SetPoint('TOPLEFT', 0, -34)
    listBox:SetSize(PW, PH - 34)
    listBox:EnableMouseWheel(true)
    listBox:SetScript('OnMouseWheel', function(_, delta)
        codexOffset = math.max(0, codexOffset - delta * 2)
        UI.RefreshCodex(searchInput:GetText())
    end)

    local rows = {}
    for i = 1, CODEX_ROWS do
        local r = S.Row(listBox, PW - 18, 34)
        r:SetPoint('TOPLEFT', 1, -6 - (i - 1) * 35)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(22, 22); icon:SetPoint('LEFT', 12, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local nameText = S.Text(r, 13, S.colors.text)
        nameText:SetPoint('TOPLEFT', 42, -3)
        nameText:SetWidth(640)

        local metaText = S.Text(r, 10, S.colors.muted)
        metaText:SetPoint('TOPLEFT', 42, -19)
        metaText:SetWidth(PW - 220)

        local ilvlText = S.Text(r, 11, S.colors.gold, 'RIGHT')
        ilvlText:SetPoint('RIGHT', -14, 0)

        r:SetScript('OnEnter', function(self) showItemTooltip(self, self.itemLink or self.itemID) end)
        r:SetScript('OnClick', function(self)
            if self.itemLink or self.itemID then Quintessence.LinkItem(self.itemLink or self.itemID) end
        end)
        r:SetScript('OnLeave', hideTooltip)

        rows[i] = { frame = r, icon = icon, nameText = nameText, metaText = metaText, ilvlText = ilvlText }
    end
    panel.rows = rows

    panel.scroll = S.Scrollbar(listBox, CODEX_ROWS * 35 - 4, function(offset)
        if offset ~= codexOffset then
            codexOffset = offset
            UI.RefreshCodex(searchInput:GetText())
        end
    end)
    panel.scroll:SetPoint('TOPLEFT', PW - 14, -6)

    local emptyText = S.Text(listBox, 12, S.colors.muted, 'CENTER')
    emptyText:SetPoint('CENTER', 0, 0)
    emptyText:SetWidth(660)
    emptyText:SetWordWrap(true)
    emptyText:SetText('Le Codex secret est vide pour l\'instant.\nChaque objet rare ou épique ramassé en donjon ou raid par la guilde est automatiquement archivé ici.')
    panel.emptyText = emptyText

    return panel
end

function UI.RefreshCodex(filter)
    local p = tabs.codex
    if not p or not p:IsVisible() then return end

    local totalCount = Q.GetCodexItemCount and Q.GetCodexItemCount() or 0
    p.countText:SetText(string.format('Codex de Quintessence : |c%s%d|r objet(s) découvert(s)', S.hex.gold, totalCount))

    local items = Q.GetCodexItems and Q.GetCodexItems(filter) or {}
    codexOffset = math.max(0, math.min(codexOffset, math.max(0, #items - CODEX_ROWS)))
    p.scroll:SetMinMaxValues(0, math.max(0, #items - CODEX_ROWS))
    p.scroll:SetValue(codexOffset)

    if #items == 0 then
        p.emptyText:Show()
        for _, r in ipairs(p.rows) do r.frame:Hide() end
        return
    end
    p.emptyText:Hide()

    for i, r in ipairs(p.rows) do
        local item = items[codexOffset + i]
        if item then
            r.frame:Show()
            r.frame.itemID = item.id
            r.frame.itemLink = item.link
            local _, tex = Q.GetItemDisplayInfo(item.id)
            r.icon:SetTexture(tex or 'Interface\\Icons\\INV_Misc_QuestionMark')
            local qHex = QUALITY_HEX[item.quality or 4] or 'ffa335ee'
            r.nameText:SetText(item.link or ('|c' .. qHex .. Q.Safe(item.name) .. '|r'))
            r.metaText:SetText(string.format('Découvert par |cffffffff%s|r · %s', Q.Safe(item.finder or 'Guilde'), Q.Safe(item.zone or 'Inconnue')))
            r.ilvlText:SetText('iLvl ' .. (item.ilvl or 60))
        else
            r.frame:Hide()
        end
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
        { id = 'dungeons', label = 'Donjons', w = 110 },
        { id = 'leveling', label = 'Quêtes partagées', w = 150 },
        { id = 'codex', label = 'Codex secret', w = 136 },
    }
    if Q.NoCodex() then tabDefs[3] = nil end

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

    tabs.leveling = createLevelingPanel(content)
    tabs.dungeons = createDungeonsPanel(content)
    tabs.codex = createCodexPanel(content)

    mainFrame:SetScript('OnShow', function() Q.Run('fenêtre', UI.Refresh) end)
    switchTab('dungeons')
end

function UI.Refresh()
    if not mainFrame or not mainFrame:IsVisible() then return end
    if mainFrame.status and Q.Summary then
        mainFrame.status:SetText(Q.Summary())
    end
    if activeTab == 'leveling' then UI.RefreshLeveling() end
    if activeTab == 'dungeons' then UI.RefreshDungeons() end
    if activeTab == 'codex' then UI.RefreshCodex() end
end

function UI.Open()
    if not Q.ready and Q.Init then Q.Init() end
    Quintessence.UI.Open('group')
end

function UI.Toggle() Quintessence.UI.Toggle('group') end

Quintessence:RegisterModule({
    id = 'group',
    title = 'Donjons & Quêtes',
    order = 45,
    icon = 'Interface\\Icons\\INV_Misc_Book_08',
    version = Q.version,
    width = W,
    height = H,
    create = function(parent)
        create(parent)
        return mainFrame
    end,
    refresh = function() UI.Refresh() end,
    summary = function()
        if not Q.ready then return nil end
        return Q.Summary and Q.Summary() or 'Recherche de donjon'
    end,
})
