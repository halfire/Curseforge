local _, Q = ...
--[[
  UI.lua : Interface utilisateur du module Quinte-group dans la fenêtre Quintessence (760 × 440).
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

local QUEST_ROWS = 9

local function createLevelingPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    -- Colonne gauche : Mes quêtes actives (276 × 400)
    local leftBox = S.Box(panel, S.colors.panel, S.colors.line)
    leftBox:SetPoint('TOPLEFT', 0, 0)
    leftBox:SetSize(276, 400)

    local myHeading = S.Heading(leftBox, 'Mon journal de quêtes')
    myHeading:SetPoint('TOPLEFT', 14, -12)

    panel.myRows = {}
    for i = 1, 9 do
        local row = S.Row(leftBox, 274, 26)
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

    -- Colonne droite : Quêtes en commun avec la guilde (472 × 400)
    local rightBox = S.Box(panel, S.colors.panel, S.colors.line)
    rightBox:SetPoint('TOPLEFT', 288, 0)
    rightBox:SetSize(472, 400)

    local sharedHeading = S.Heading(rightBox, 'Quêtes en commun avec la guilde')
    sharedHeading:SetPoint('TOPLEFT', 16, -12)

    panel.sharedCount = S.Text(rightBox, 11, S.colors.muted, 'RIGHT')
    panel.sharedCount:SetPoint('TOPRIGHT', -16, -12)
    -- XP des membres du groupe (envoyée par leur addon)
    panel.partyXP = S.Text(rightBox, 11, S.colors.muted)
    panel.partyXP:SetPoint('BOTTOMLEFT', 16, 10); panel.partyXP:SetWidth(440); panel.partyXP:SetWordWrap(true)

    panel.rows = {}
    for i = 1, QUEST_ROWS do
        local r = S.Row(rightBox, 470, 38)
        r:SetPoint('TOPLEFT', 1, -36 - (i - 1) * 39)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(22, 22); icon:SetPoint('LEFT', 12, 0)
        icon:SetTexture('Interface\\Icons\\INV_Misc_Book_08')
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local qText = S.Text(r, 13, S.colors.text)
        qText:SetPoint('TOPLEFT', 42, -5)
        qText:SetWidth(300)

        local mText = S.Text(r, 11, S.colors.muted)
        mText:SetPoint('TOPLEFT', 42, -21)
        mText:SetWidth(300)

        local invBtn = S.Button(r, 'Inviter', 96, 24, 'primary')
        invBtn:SetPoint('RIGHT', -12, 0)

        panel.rows[i] = { frame = r, qText = qText, mText = mText, invBtn = invBtn }
    end

    local emptyText = S.Text(rightBox, 12, S.colors.muted, 'CENTER')
    emptyText:SetPoint('CENTER', 0, -10)
    emptyText:SetWidth(380)
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
    p.sharedCount:SetText(#shared .. ' quête' .. (#shared > 1 and 's' or '') .. ' partagée' .. (#shared > 1 and 's' or ''))

    if #shared == 0 then
        p.emptyText:Show()
        for _, r in ipairs(p.rows) do r.frame:Hide() end
        return
    end
    p.emptyText:Hide()

    for i, r in ipairs(p.rows) do
        local q = shared[i]
        if q then
            r.frame:Show()
            r.qText:SetText(string.format('|c%s[%d]|r  %s', S.hex.gold, q.level or 0, Q.Safe(q.title)))

            local memberNames = {}
            for _, m in ipairs(q.members) do
                memberNames[#memberNames + 1] = string.format('|c%s%s|r (%d)', classHex(m.class), Q.Safe(m.name), m.level or 60)
            end
            r.mText:SetText('En cours chez : ' .. table.concat(memberNames, ', '))

            -- Bouton seulement s'il reste quelqu'un hors de notre groupe
            local outside = 0
            for _, m in ipairs(q.members) do if not Q.InMyGroup(m.name) then outside = outside + 1 end end
            r.invBtn:SetShown(outside > 0)
            r.invBtn:SetScript('OnClick', function()
                local sent = 0
                for _, m in ipairs(q.members) do if invitePlayer(m.name) ~= false then sent = sent + 1 end end
                Q.Print(sent .. ' invitation(s) envoyée(s) pour la quête : ' .. Q.Safe(q.title))
            end)
        else
            r.frame:Hide()
        end
    end
end

-- =========================================================================
-- ONGLET 2 : RECHERCHE DONJONS, BESOINS & ANTI-CONFLIT DE BUTIN
-- =========================================================================

local dungeonState = {
    selectedDungeon = 'DM',
    dungeonOffset = 0,
    memberOffset = 0,
    lootOffset = 0
}

local D_ROWS, M_ROWS, L_ROWS = 9, 4, 4

local function createDungeonsPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    -- 1. Barre de préférences en haut (760 × 38)
    local prefBox = S.Box(panel, S.colors.panel, S.colors.line)
    prefBox:SetPoint('TOPLEFT', 0, 0)
    prefBox:SetSize(760, 38)

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

    local noteInput = S.Input(prefBox, 286, 'Note (ex. clé UBRS dispo, farm BiS)…')
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

    -- 2. Colonne de gauche : Liste des donjons (276 × 352)
    local leftBox = S.Box(panel, S.colors.panel, S.colors.line)
    leftBox:SetPoint('TOPLEFT', 0, -48)
    leftBox:SetSize(276, 352)
    leftBox:EnableMouseWheel(true)
    leftBox:SetScript('OnMouseWheel', function(_, delta)
        dungeonState.dungeonOffset = math.max(0, dungeonState.dungeonOffset - delta * 2)
        UI.RefreshDungeons()
    end)

    local dungeonRows = {}
    for i = 1, D_ROWS do
        local row = S.Row(leftBox, 260, 36)
        row:SetPoint('TOPLEFT', 1, -6 - (i - 1) * 38)

        row.icon = row:CreateTexture(nil, 'ARTWORK')
        row.icon:SetSize(22, 22); row.icon:SetPoint('LEFT', 10, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = S.Text(row, 12, S.colors.text)
        row.name:SetPoint('TOPLEFT', 38, -4)
        row.name:SetWidth(174)

        row.count = S.Text(row, 11, S.colors.mint, 'RIGHT')
        row.count:SetPoint('TOPRIGHT', -8, -4)

        row.sub = S.Text(row, 10, S.colors.muted)
        row.sub:SetPoint('TOPLEFT', 38, -20)
        row.sub:SetWidth(214)

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
    panel.dungeonScroll:SetPoint('TOPLEFT', 264, -6)

    -- 3. Colonne de droite : Détails du donjon, membres et matrice de butin (472 × 352)
    local rightBox = S.Box(panel, S.colors.panel, S.colors.line)
    rightBox:SetPoint('TOPLEFT', 288, -48)
    rightBox:SetSize(472, 352)
    panel.rightBox = rightBox

    local dIcon = rightBox:CreateTexture(nil, 'ARTWORK')
    dIcon:SetSize(28, 28); dIcon:SetPoint('TOPLEFT', 14, -12)
    dIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    panel.dIcon = dIcon

    local dTitle = S.Text(rightBox, 15, S.colors.text)
    dTitle:SetPoint('TOPLEFT', 50, -11)
    dTitle:SetWidth(210)
    panel.dTitle = dTitle

    local dSub = S.Text(rightBox, 11, S.colors.muted)
    dSub:SetPoint('TOPLEFT', 50, -29)
    dSub:SetWidth(230)
    panel.dSub = dSub

    local btnInviteComp = S.Button(rightBox, 'Groupe sans conflit', 142, 24, 'primary')
    btnInviteComp:SetPoint('TOPRIGHT', -12, -12)
    btnInviteComp:SetScript('OnClick', function()
        Q.InviteCompatibleGroup(dungeonState.selectedDungeon)
    end)
    panel.btnInviteComp = btnInviteComp

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

    -- Bandeau d'état des conflits de butin
    local banner = S.Box(rightBox, S.colors.bg, S.colors.line)
    banner:SetPoint('TOPLEFT', 14, -48)
    banner:SetSize(444, 24)
    panel.banner = banner

    local bannerDot = S.Fill(banner, 'ARTWORK', S.colors.mint)
    bannerDot:SetSize(8, 8); bannerDot:SetPoint('LEFT', 10, 0)
    panel.bannerDot = bannerDot

    local bannerText = S.Text(banner, 11, S.colors.text)
    bannerText:SetPoint('LEFT', 24, 0)
    bannerText:SetWidth(410)
    panel.bannerText = bannerText

    -- Section 1 : Membres disponibles & rôles
    local mHeading = S.Heading(rightBox, 'Membres intéressés · clic pour chuchoter')
    mHeading:SetPoint('TOPLEFT', 14, -80)
    panel.mHeading = mHeading

    local memberBox = S.Box(rightBox, S.colors.bg, S.colors.line)
    memberBox:SetPoint('TOPLEFT', 14, -96)
    memberBox:SetSize(444, M_ROWS * 26 + 4)
    memberBox:EnableMouseWheel(true)
    memberBox:SetScript('OnMouseWheel', function(_, delta)
        dungeonState.memberOffset = math.max(0, dungeonState.memberOffset - delta)
        UI.RefreshDungeons()
    end)

    local memberRows = {}
    for i = 1, M_ROWS do
        local r = S.Row(memberBox, 442, 25)
        r:SetPoint('TOPLEFT', 1, -2 - (i - 1) * 26)

        local dot = S.Fill(r, 'ARTWORK', S.colors.mint)
        dot:SetSize(7, 7); dot:SetPoint('LEFT', 10, 0)

        local roleText = S.Text(r, 11, S.colors.text)
        roleText:SetPoint('LEFT', 22, 0); roleText:SetWidth(46)

        local nameText = S.Text(r, 12, S.colors.text)
        nameText:SetPoint('LEFT', 70, 0); nameText:SetWidth(155)

        local lootSummary = S.Text(r, 11, S.colors.muted)
        lootSummary:SetPoint('LEFT', 230, 0); lootSummary:SetWidth(135)

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
    lHeading:SetPoint('TOPLEFT', 14, -212)
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
    lootBox:SetPoint('TOPLEFT', 14, -228)
    lootBox:SetSize(444, L_ROWS * 27 + 4)
    lootBox:EnableMouseWheel(true)
    lootBox:SetScript('OnMouseWheel', function(_, delta)
        dungeonState.lootOffset = math.max(0, dungeonState.lootOffset - delta)
        UI.RefreshDungeons()
    end)

    local lootRows = {}
    for i = 1, L_ROWS do
        local r = S.Row(lootBox, 442, 26)
        r:SetPoint('TOPLEFT', 1, -2 - (i - 1) * 27)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(18, 18); icon:SetPoint('LEFT', 8, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local itemName = S.Text(r, 12, S.colors.text)
        itemName:SetPoint('LEFT', 32, 0); itemName:SetWidth(190)

        local membersList = S.Text(r, 11, S.colors.muted, 'RIGHT')
        membersList:SetPoint('RIGHT', -10, 0); membersList:SetWidth(210)

        local action = S.Button(r, 'Partager', 64, 20, 'ghost')
        action:SetPoint('RIGHT', -6, 0)
        action:Hide()

        r:SetScript('OnEnter', function(self)
            if self.quest then showQuestTooltip(self, self.quest) else showItemTooltip(self, self.itemID) end
        end)
        r:SetScript('OnLeave', hideTooltip)

        lootRows[i] = {
            frame = r,
            icon = icon,
            itemName = itemName,
            membersList = membersList,
            action = action
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
            r.name:SetText(Q.Safe(d.name))

            if d.totalMembers > 0 then
                r.count:SetText(d.totalMembers .. ' mbr')
                r.count:SetTextColor(unpack(S.colors.mint))
            else
                r.count:SetText('0')
                r.count:SetTextColor(unpack(S.colors.muted))
            end

            local lvlText = string.format('niv. %d-%d', d.minLvl or 13, d.maxLvl or 60)
            if d.new then lvlText = lvlText .. ' · |c' .. S.hex.gold .. 'Forever|r' end
            if d.hasConflicts then
                lvlText = lvlText .. ' · |c' .. S.hex.red .. d.conflictCount .. ' conflit(s)|r'
            elseif d.totalMembers > 1 and d.totalLoots > 0 then
                lvlText = lvlText .. ' · |c' .. S.hex.mint .. 'Sans conflit|r'
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
    p.dSub:SetText(string.format('Niveau %d-%d · %d membre(s) · %d butin(s)',
        selectedNeeds.minLvl or 13, selectedNeeds.maxLvl or 60, selectedNeeds.totalMembers, selectedNeeds.totalLoots))

    if selectedNeeds.hasConflicts then
        p.bannerDot:SetColorTexture(unpack(S.colors.red))
        p.bannerText:SetText(string.format('|c%s%d conflit(s) de butin :|r plusieurs membres convoitent le même objet.',
            S.hex.red, selectedNeeds.conflictCount))
    elseif selectedNeeds.totalMembers > 0 then
        p.bannerDot:SetColorTexture(unpack(S.colors.mint))
        p.bannerText:SetText('|c' .. S.hex.mint .. 'Répartition optimale :|r aucun doublon sur les objets convoités.')
    else
        p.bannerDot:SetColorTexture(unpack(S.colors.muted))
        p.bannerText:SetText('|c' .. S.hex.muted .. 'Aucun besoin enregistré sur ce donjon.|r')
    end

    local members = selectedNeeds.members
    p.mHeading:SetText(string.format('Membres intéressés (%d) · clic pour chuchoter', #members))
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
    p.questToggle:SetLabel(dungeonState.showQuests and 'Butins' or ('Quêtes (' .. #quests .. ')'))
    p.questToggle:SetActive(dungeonState.showQuests and true or false)
    if dungeonState.showQuests then
        local todo, toShare = 0, 0
        local grouped = IsInGroup and IsInGroup() and true or false
        for _, q in ipairs(quests) do
            if q.state == 'todo' then todo = todo + 1 end
            if q.shareable then toShare = toShare + 1 end
        end
        p.lHeading:SetText(string.format('Quêtes (%d) · %d à prendre · %d à partager', #quests, todo, toShare))
        p.bossLoot:SetLabel('Dire au groupe')
        p.bossLoot:SetEnabled(grouped and todo > 0)
        p.lootEmpty:SetShown(#quests == 0)
        p.lootEmpty:SetText('Aucune quête connue pour ce donjon.')
        dungeonState.lootOffset = math.max(0, math.min(dungeonState.lootOffset, math.max(0, #quests - L_ROWS)))
        for i = 1, L_ROWS do
            local r, q = p.lootRows[i], quests[dungeonState.lootOffset + i]
            if q then
                r.frame:Show(); r.frame.itemID = nil; r.frame.quest = q
                r.icon:SetTexture('Interface\\Icons\\INV_Misc_Note_01')
                r.itemName:SetText(string.format('|c%s[%d]|r %s', S.hex.gold, q.level, Q.Safe(q.title)))
                r.membersList:SetPoint('RIGHT', -74, 0); r.membersList:SetWidth(140)
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
                else
                    text = '|c' .. S.hex.muted .. 'faite|r'
                    r.action:Hide()
                end
                r.membersList:SetText(text)
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
            r.membersList:SetPoint('RIGHT', -10, 0); r.membersList:SetWidth(210)
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

local CODEX_ROWS = 10
local codexOffset = 0

local function createCodexPanel(parent)
    local panel = CreateFrame('Frame', nil, parent)
    panel:SetAllPoints()

    local searchInput = S.Input(panel, 280, 'Rechercher un objet ou une zone…')
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
    listBox:SetSize(760, 366)
    listBox:EnableMouseWheel(true)
    listBox:SetScript('OnMouseWheel', function(_, delta)
        codexOffset = math.max(0, codexOffset - delta * 2)
        UI.RefreshCodex(searchInput:GetText())
    end)

    local rows = {}
    for i = 1, CODEX_ROWS do
        local r = S.Row(listBox, 742, 34)
        r:SetPoint('TOPLEFT', 1, -6 - (i - 1) * 35)

        local icon = r:CreateTexture(nil, 'ARTWORK')
        icon:SetSize(22, 22); icon:SetPoint('LEFT', 12, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local nameText = S.Text(r, 13, S.colors.text)
        nameText:SetPoint('TOPLEFT', 42, -3)
        nameText:SetWidth(420)

        local metaText = S.Text(r, 10, S.colors.muted)
        metaText:SetPoint('TOPLEFT', 42, -19)
        metaText:SetWidth(540)

        local ilvlText = S.Text(r, 11, S.colors.gold, 'RIGHT')
        ilvlText:SetPoint('RIGHT', -14, 0)

        r:SetScript('OnEnter', function(self) showItemTooltip(self, self.itemLink or self.itemID) end)
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
    panel.scroll:SetPoint('TOPLEFT', 746, -6)

    local emptyText = S.Text(listBox, 12, S.colors.muted, 'CENTER')
    emptyText:SetPoint('CENTER', 0, 0)
    emptyText:SetWidth(460)
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
        { id = 'leveling', label = 'Quêtes partagées', w = 150 },
        { id = 'dungeons', label = 'Donjons & butin', w = 150 },
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
    title = 'Quêtes & Donjons',
    order = 45,
    icon = 'Interface\\Icons\\INV_Misc_Book_08',
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
        return Q.Summary and Q.Summary() or 'Recherche de donjon'
    end,
})
