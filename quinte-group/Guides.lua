local _, Q = ...
-- Les guides sont des listes de quêtes : aucun article, aucune progression enregistrée.
local S = Quintessence.Style
local panel, selected, offset, expanded = nil, 1, 0, {}
local STATE = { done = 'Terminée', log = 'En cours', todo = 'À prendre', locked = 'Prérequis à terminer', low = 'Niveau insuffisant' }
local function read(fn, ...)
    local ok, value = Q.Call(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
local function state(guide, q)
    if read(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, q.id) == true then return 'done' end
    if Q.IsOnQuest(q.id) then return 'log' end
    local level = read(UnitLevel, 'player')
    if type(level) == 'number' and q.minLevel and level < q.minLevel then return 'low' end
    local visited = {}
    local function blocked(id)
        if visited[id] then return false end
        visited[id] = true
        if read(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, id) ~= true then return true end
        return false
    end
    for _, id in ipairs(q.requires or {}) do if blocked(id) then return 'locked' end end
    return 'todo'
end
local function xp(q)
    local value = read(GetQuestLogRewardXP, q.id)
    if type(value) == 'number' and value > 0 then return math.floor(value) end
    local reference = Q.REFERENCE_QUEST_INFO and Q.REFERENCE_QUEST_INFO[q.id]
    return q.xp or (reference and reference.xp)
end
local function sequence(guide, id)
    local rows, seen = {}, {}
    local function add(sid)
        if seen[sid] then return end
        seen[sid] = true
        local q = guide.quests[sid]
        if not q then return end
        for _, dep in ipairs(q.requires or {}) do add(dep) end
        rows[#rows + 1] = q
    end
    add(id)
    return rows
end
function Q.GuideQuestRows(guide, opened)
    local rows = {}
    for _, id in ipairs(guide.roots) do
        local steps = sequence(guide, id)
        local completed, totalXP, missingXP = 0, 0, 0
        for _, q in ipairs(steps) do
            if state(guide, q) == 'done' then completed = completed + 1 end
            local amount = xp(q)
            if amount then totalXP = totalXP + amount else missingXP = missingXP + 1 end
        end
        local function append(q, virtual, index)
            local row = {}
            for key, value in pairs(q) do row[key] = value end
            local title = read(C_QuestLog and C_QuestLog.GetTitleForQuestID, q.id)
            row.title = type(title) == 'string' and title ~= '' and title or q.title
            row.state = state(guide, q); row.xp = xp(q)
            row.complete = row.state == 'log' and read(C_QuestLog and C_QuestLog.IsComplete, q.id) == true
            row.virtual, row.parentQuest, row.stepIndex = virtual, id, index
            row.journeyDone, row.journeyTotal, row.totalXP, row.missingXP = completed, #steps, totalXP, missingXP
            rows[#rows + 1] = row
        end
        append(guide.quests[id], false)
        if opened and opened[id] then
            for i, q in ipairs(steps) do if q.id ~= id then append(q, true, i) end end
        end
    end
    return rows
end
local function holders(id)
    local out, seen = {}, {}
    for _, info in pairs(QuinteGroupDB.memberQuests or {}) do
        if type(info) == 'table' and type(info.name) == 'string' and type(info.updated) == 'number'
            and Q.Now() - info.updated <= 1800 and Q.InMyGroup(info.name) then
            local key = Quintessence.CanonicalKey(info.name)
            if not seen[key] then
                for _, quest in ipairs(info.quests or {}) do
                    if quest.id == id then out[#out + 1] = info.name; seen[key] = true; break end
                end
            end
        end
    end
    return out
end
local function tooltip(owner, q)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
    Q.Call(GameTooltip.SetHyperlink, GameTooltip, 'quest:' .. q.id)
    GameTooltip:AddLine(STATE[q.state], 1, 0.82, 0)
    if q.kind and q.kind ~= '' then GameTooltip:AddLine(Q.Safe(q.kind), 0.7, 0.7, 0.7, true) end
    if q.start and q.start ~= '' then GameTooltip:AddLine('Donneur : ' .. Q.Safe(q.start), 1, 1, 1, true) end
    if q.place and q.place ~= '' then GameTooltip:AddLine(Q.Safe(q.place), 1, 1, 1, true) end
    if q.objective and q.objective ~= '' then GameTooltip:AddLine(Q.Safe(q.objective), 1, 1, 1, true) end
    if q.note and q.note ~= '' then GameTooltip:AddLine(Q.Safe(q.note), 1, 0.82, 0, true) end
    GameTooltip:AddLine(Q.XPText(q.xp) .. ' · référence indicative hors réponse du client', 0.7, 0.7, 0.7, true)
    if q.rewardText and q.rewardText ~= '' then GameTooltip:AddLine('Récompenses (guide) : ' .. Q.Safe(q.rewardText), 1, 1, 1, true) end
    if not q.point then GameTooltip:AddLine('Emplacement du donneur non renseigné.', 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
end
function Q.RefreshGuides()
    if not panel or not panel:IsVisible() then return end
    local guide = Q.GUIDES[selected]
    if not guide then return end
    local rows = Q.GuideQuestRows(guide, expanded)
    panel.title:SetText(Q.Safe(guide.title) .. ' · Quêtes & prérequis')
    panel.count:SetText(#guide.roots .. ' suites · + pour déplier les prérequis')
    for i, button in ipairs(panel.guideButtons) do button:SetActive(i == selected) end
    offset = math.min(offset, math.max(0, #rows - #panel.rows))
    panel.scroll:SetMinMaxValues(0, math.max(0, #rows - #panel.rows)); panel.scroll:SetValue(offset)
    for i, row in ipairs(panel.rows) do
        local q = rows[offset + i]
        row:SetShown(q ~= nil)
        row.quest = q
        if q then
            local color = q.state == 'done' and S.hex.mint or (q.state == 'locked' or q.state == 'low') and S.hex.muted or S.hex.gold
            local prefix = q.virtual and ('    ' .. q.stepIndex .. '. ') or ''
            local progress = not q.virtual and q.journeyTotal > 1 and ('  ' .. q.journeyDone .. '/' .. q.journeyTotal) or ''
            row.name:SetText('|c' .. color .. prefix .. (q.level and q.level > 0 and ('[' .. q.level .. '] ') or '') .. Q.Safe(q.title) .. '|r' .. progress)
            local status = q.complete and 'À rendre' or STATE[q.state]
            local amount = Q.XPText(q.xp)
            if not q.virtual and q.journeyTotal > 1 then amount = amount .. ' · chaîne : ' .. Q.XPText(q.totalXP) .. (q.missingXP > 0 and ' + ?' or '') end
            row.status:SetText(amount .. ' · ' .. status)
            row.icon:SetTexture(q.state == 'done' and 'Interface\\RaidFrame\\ReadyCheck-Ready' or 'Interface\\Icons\\INV_Misc_Note_01')
            row.chain:SetShown(not q.virtual and q.journeyTotal > 1)
            row.chain:SetLabel(expanded[q.id] and '-' or '+')
            row.map:SetShown(q.point ~= nil); row.route:SetShown(q.point ~= nil and q.state ~= 'done')
            row.loot:SetShown(not q.virtual and #(q.items or {}) > 0)
            local share = q.state == 'log' and Q.CanShareQuest(q.id)
            q.groupHas = holders(q.id)
            row.action:SetShown(share or (q.state ~= 'done' and q.state ~= 'log' and #q.groupHas > 0))
            row.action:SetLabel(share and 'Partager' or 'Demander')
            row.action:SetEnabled(not share or (IsInGroup and IsInGroup()) or false)
        end
    end
end
function Q.CreateGuidesPanel(parent, width, height)
    panel = CreateFrame('Frame', nil, parent); panel:SetAllPoints()
    local left = S.Box(panel, S.colors.panel, S.colors.line); left:SetPoint('TOPLEFT'); left:SetSize(250, height)
    local heading = S.Heading(left, 'Guide Quintessence'); heading:SetPoint('TOPLEFT', 12, -14)
    panel.guideButtons, panel.rows, panel.sectionLabels = {}, {}, {}
    local section, y = nil, -44
    for i, guide in ipairs(Q.GUIDES) do
        if guide.section ~= section then
            section = guide.section
            local label = S.Text(left, 12, S.colors.gold); label:SetPoint('TOPLEFT', 12, y)
            label:SetText(section or 'Quêtes de zone'); panel.sectionLabels[#panel.sectionLabels + 1] = label; y = y - 25
        end
        local b = S.Button(left, guide.title, 230, 36, 'ghost'); b:SetPoint('TOPLEFT', 10, y)
        y = y - 42
        b:SetScript('OnClick', function() selected, offset, expanded = i, 0, {}; Q.RefreshGuides() end)
        panel.guideButtons[i] = b
    end
    local right = S.Box(panel, S.colors.panel, S.colors.line); right:SetPoint('TOPLEFT', 262, 0); right:SetSize(width - 262, height)
    panel.title = S.Text(right, 15, S.colors.gold); panel.title:SetPoint('TOPLEFT', 12, -14); panel.title:SetWidth(width - 290)
    panel.count = S.Text(right, 11, S.colors.muted); panel.count:SetPoint('TOPLEFT', 12, -40)
    for i = 1, math.floor((height - 74) / 42) do
        local row = S.Row(right, width - 280, 41); row:SetPoint('TOPLEFT', 1, -66 - (i - 1) * 42)
        row.icon = row:CreateTexture(nil, 'ARTWORK'); row.icon:SetPoint('LEFT', 28, 0); row.icon:SetSize(18, 18)
        row.name = S.Text(row, 12, S.colors.text); row.name:SetPoint('TOPLEFT', 50, -4); row.name:SetWidth(width - 608)
        row.status = S.Text(row, 11, S.colors.muted); row.status:SetPoint('BOTTOMLEFT', 50, 4); row.status:SetWidth(width - 608)
        row.chain = S.Button(row, '+', 22, 20, 'ghost'); row.chain:SetPoint('LEFT', 3, 0)
        row.chain:SetScript('OnClick', function() local q=row.quest; expanded[q.id]=not expanded[q.id]; Q.RefreshGuides() end)
        row.map = S.Button(row, 'Carte', 46, 20, 'ghost'); row.map:SetPoint('RIGHT', -140, 0)
        row.map:SetScript('OnClick', function() local q=row.quest; Q.Run('carte du guide', Q.ShowGuidePlace, q.point, q.title) end)
        row.route = S.Button(row, 'Chemin', 54, 20, 'ghost'); row.route:SetPoint('RIGHT', -192, 0)
        row.route:SetScript('OnClick', function() local q=row.quest; Q.Run('chemin du guide', Q.ShowGuidePlace, q.point, q.title, true) end)
        row.loot = S.Button(row, 'Butin', 46, 20, 'ghost'); row.loot:SetPoint('RIGHT', -88, 0)
        row.loot:SetScript('OnClick', function() local q=row.quest; q.rewards,q.rewardChoice=q.items,q.choice; Q.UI.ShowQuestRewards(q) end)
        row.action = S.Button(row, 'Partager', 72, 20, 'ghost'); row.action:SetPoint('RIGHT', -10, 0)
        row.action:SetScript('OnClick', function() local q=row.quest
            if q.state == 'log' then Q.ShareQuest(q.id,q.title) else Q.AskQuest(q.title,q.groupHas,q.id) end
        end)
        row:SetScript('OnEnter', function(self) if self.quest then tooltip(self, self.quest) end end)
        row:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
        panel.rows[i] = row
    end
    panel.scroll = S.Scrollbar(right, height - 80, function(value) if value ~= offset then offset = value; Q.RefreshGuides() end end)
    panel.scroll:SetPoint('TOPRIGHT', -6, -66)
    right:EnableMouseWheel(true); right:SetScript('OnMouseWheel', function(_,delta) offset=math.max(0,offset-delta); Q.RefreshGuides() end)
    panel:SetScript('OnShow', function() Q.Run('quêtes du guide', Q.RefreshGuides) end)
    local driver = CreateFrame('Frame')
    for _, event in ipairs({'QUEST_LOG_UPDATE','QUEST_TURNED_IN','QUEST_ACCEPTED','QUEST_REMOVED'}) do Q.Call(driver.RegisterEvent,driver,event) end
    driver:SetScript('OnEvent',function() Q.Run('états du guide',Q.RefreshGuides) end)
    return panel
end
