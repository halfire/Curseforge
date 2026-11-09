local _, Q = ...
-- Toutes les quêtes du catalogue sont listées ; seuls les emplacements connus reçoivent un repère.
-- Aucune coordonnée de zone extérieure n'est projetée sur l'image du donjon.
local Core, S, M = Quintessence, Quintessence.Style, Q.DungeonMaps
local version, cache = 0, {}
local STATE = { todo = 'Non prise', log = 'En cours', done = 'Terminée', locked = 'Prérequis à faire',
    low = 'Niveau insuffisant', restricted = 'Autre classe / conditions à vérifier' }
local KIND = { start = 'Départ', finish = 'À rendre', objective = 'Objectif' }
local ICON = { start = 'Interface\\GossipFrame\\AvailableQuestIcon', finish = 'Interface\\GossipFrame\\ActiveQuestIcon',
    objective = 'Interface\\GossipFrame\\BattleMasterGossipIcon' }
local function readable(v) return not (issecretvalue and issecretvalue(v)) end
local function number(v) return readable(v) and type(v) == 'number' and v == v and math.abs(v) < math.huge end
local function read(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, value = pcall(fn, ...)
    if ok and readable(value) then return value end
end
local function plain(s) return readable(s) and type(s) == 'string' and s:lower():gsub('[%s%p]', '') or '' end
function M.QuestVersion() return version end
function M.QuestRecords(code)
    local previous = cache[code]
    if previous and previous.version == version then return previous.rows end
    local rows = {}
    local classBits = { WARRIOR=1, PALADIN=2, HUNTER=4, ROGUE=8, PRIEST=16, SHAMAN=64, MAGE=128, WARLOCK=256, DRUID=1024 }
    local class
    if type(UnitClass) == 'function' then
        local ok, _, token = pcall(UnitClass, 'player')
        if ok and readable(token) and type(token) == 'string' then class = classBits[token] end
    end
    local level = read(UnitLevel, 'player')
    local details = Q.DUNGEON_MAP_QUEST_DETAILS and Q.DUNGEON_MAP_QUEST_DETAILS[code] or {}
    for _, raw in ipairs(Q.DUNGEON_QUESTS[code] or {}) do
        local id, meta = raw[1], details[raw[1]] or {}
        local info = Q.DUNGEON_QUEST_INFO and Q.DUNGEON_QUEST_INFO[id] or {}
        local done = C_QuestLog and read(C_QuestLog.IsQuestFlaggedCompleted, id)
        local title = C_QuestLog and read(C_QuestLog.GetTitleForQuestID, id)
        local active = Q.IsOnQuest and Q.IsOnQuest(id)
        local complete = active and C_QuestLog and read(C_QuestLog.IsComplete, id) == true
        local status = active and 'log' or done == true and 'done' or 'todo'
        if status == 'todo' then
            if number(info.class) and class and math.floor(info.class / class) % 2 ~= 1 then status = 'restricted'
            elseif info.prev and not (C_QuestLog and read(C_QuestLog.IsQuestFlaggedCompleted, info.prev) == true) then status = 'locked'
            elseif number(level) and number(info.level or raw[4]) and level < (info.level or raw[4]) then status = 'low' end
        end
        rows[#rows + 1] = { id = id, title = type(title) == 'string' and title ~= '' and title or raw[3],
            state = status, status = complete and 'À rendre' or STATE[status],
            start = meta.start, finish = meta.finish, objective = meta.objective, pins = meta.pins or {} }
    end
    cache[code] = { version = version, rows = rows }
    return rows
end
local function tooltip(quest, points)
    if not GameTooltip then return end
    GameTooltip:SetText(Q.Safe(quest.title))
    GameTooltip:AddLine(quest.status or '', S.colors.gold[1], S.colors.gold[2], S.colors.gold[3], true)
    if quest.start and quest.start ~= '' then GameTooltip:AddLine('Départ : ' .. Q.Safe(quest.start), 1, 1, 1, true) end
    if quest.finish and quest.finish ~= '' then GameTooltip:AddLine('Retour : ' .. Q.Safe(quest.finish), 1, 1, 1, true) end
    if quest.objective and quest.objective ~= '' then GameTooltip:AddLine(Q.Safe(quest.objective), 1, 1, 1, true) end
    if not points or #points == 0 then GameTooltip:AddLine('Position intérieure non renseignée : aucun repère inventé.', 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
end
local function questTooltip(pin)
    if not GameTooltip then return end
    GameTooltip:SetOwner(pin, 'ANCHOR_RIGHT')
    local first = pin.entries[1]
    if not first then return end
    tooltip(first.quest, { pin })
    GameTooltip:AddLine((KIND[first.kind] or 'Objectif') .. ' : ' .. Q.Safe(first.target or ''), 1, 1, 1, true)
    for i = 2, #pin.entries do
        local entry = pin.entries[i]
        GameTooltip:AddLine(Q.Safe(entry.quest.title) .. ' — ' .. entry.quest.status, 1, 0.82, 0, true)
    end
    if pin.classic then GameTooltip:AddLine('Position du plan Classic, indicative sur Forever.', 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
end
local function positions(record, data, level)
    local out, seen = {}, {}
    for _, point in ipairs(record.pins) do
        local found
        for _, boss in ipairs(data.bosses) do
            if plain(boss.name) == plain(point.target) and boss.floor == level and number(boss.x) and number(boss.y) then
                found = { x = boss.x, y = boss.y, kind = point.kind, target = point.target }; break
            end
        end
        local floor = data.floors[level]
        if not found and data.classic and floor and floor.page == point.floor and number(point.x) and number(point.y) then
            found = { x = point.x, y = point.y, kind = point.kind, target = point.target }
        end
        if found then
            local key = found.x .. ':' .. found.y .. ':' .. found.kind
            if not seen[key] then seen[key] = true; out[#out + 1] = found end
        end
    end
    return out
end
function M.QuestPoints(data, level)
    local entries, byID = {}, {}
    for _, quest in ipairs(M.QuestRecords(data.code)) do
        byID[quest.id] = quest
        for _, point in ipairs(positions(quest, data, level)) do
            point.quest = quest; entries[#entries + 1] = point
        end
    end
    -- Coordonnées natives uniquement sur LE même UiMap que l'image native, jamais sur une carte extérieure.
    local floor = data.floors[level]
    if floor and floor.mapID and C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local native = read(C_QuestLog.GetQuestsOnMap, floor.mapID)
        if type(native) == 'table' then
            for _, point in ipairs(native) do
                if number(point.questID) and number(point.x) and number(point.y) and point.x >= 0 and point.x <= 1
                    and point.y >= 0 and point.y <= 1 and byID[point.questID] then
                    entries[#entries + 1] = { quest = byID[point.questID], kind = 'objective', x = point.x, y = point.y, native = true }
                end
            end
        end
    end
    return entries
end
function M.DrawQuestPins(view, data, level, width, height)
    view.questPins = view.questPins or {}
    local groups, order = {}, {}
    for _, point in ipairs(M.QuestPoints(data, level)) do
        local key = string.format('%.4f:%.4f', point.x, point.y)
        if not groups[key] then groups[key] = { x = point.x, y = point.y, entries = {} }; order[#order + 1] = groups[key] end
        local group = groups[key]
        local duplicate = false
        for _, entry in ipairs(group.entries) do if entry.quest.id == point.quest.id and entry.kind == point.kind then duplicate = true end end
        if not duplicate then group.entries[#group.entries + 1] = point end
    end
    for i, group in ipairs(order) do
        local pin = view.questPins[i]
        if not pin then
            pin = CreateFrame('Button', nil, view.canvas); pin:SetSize(18, 18)
            pin.icon = pin:CreateTexture(nil, 'OVERLAY'); pin.icon:SetAllPoints()
            pin:SetScript('OnEnter', questTooltip); pin:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
            pin:SetScript('OnClick', function(self) questTooltip(self) end)
            view.questPins[i] = pin
        end
        pin.entries, pin.classic = group.entries, data.classic
        pin:ClearAllPoints()
        pin:SetPoint('CENTER', view.canvas, 'TOPLEFT', math.min(width - 9, group.x * width + 17), -math.min(height - 9, group.y * height + 9))
        pin.icon:SetTexture(ICON[group.entries[1].kind] or ICON.objective)
        local selected = false
        for _, entry in ipairs(group.entries) do if entry.quest.id == view.selectedQuest then selected = true end end
        pin:SetSize(selected and 24 or 18, selected and 24 or 18)
        local state = group.entries[1].quest.state
        if selected then state = 'selected' end
        if state == 'selected' then pin.icon:SetVertexColor(1, 1, 0.3)
        elseif state == 'done' then pin.icon:SetVertexColor(0.4, 0.9, 0.5)
        elseif state == 'log' then pin.icon:SetVertexColor(0.4, 0.75, 1)
        elseif state == 'locked' or state == 'low' or state == 'restricted' then pin.icon:SetVertexColor(0.6, 0.6, 0.6)
        else pin.icon:SetVertexColor(1, 1, 1) end
        pin:Show()
    end
end
function M.RefreshQuestList(view)
    local list = view.questList
    if not list or not list:IsShown() then return end
    local records = view.questRecords or {}
    local offset = math.max(0, math.min(list.offset or 0, math.max(0, #records - #list.rows)))
    list.offset = offset
    for i, row in ipairs(list.rows) do
        local quest = records[offset + i]
        row.quest = quest; row:SetShown(quest ~= nil)
        if quest then
            local color = quest.state == 'done' and S.hex.mint or quest.state == 'log' and S.hex.gold or S.hex.text
            row.label:SetText('|c' .. color .. Q.Safe(quest.title) .. '|r')
            row.state:SetText(quest.status .. (#quest.pins > 0 and ' · repère connu' or ' · position non renseignée'))
        end
    end
end
function M.ToggleQuestList(view)
    if not view.questList then
        local list = S.Box(view.controls, S.colors.bg, S.colors.line); view.questList = list
        list:SetSize(360, 304); list:SetPoint('TOPRIGHT', -6, -34); list.offset = 0
        list:SetFrameLevel(view.controls:GetFrameLevel() + 10)
        list:EnableMouseWheel(true); list:SetScript('OnMouseWheel', function(_, delta)
            list.offset = list.offset - delta; M.RefreshQuestList(view)
        end)
        list.rows = {}
        for i = 1, 8 do
            local row = S.Row(list, 346, 34); row:SetPoint('TOPLEFT', 7, -7 - (i - 1) * 36)
            row.label = S.Text(row, 11); row.label:SetPoint('TOPLEFT', 5, -4); row.label:SetWidth(335)
            row.state = S.Text(row, 10, S.colors.muted); row.state:SetPoint('TOPLEFT', 5, -19); row.state:SetWidth(335)
            row:SetScript('OnEnter', function(self)
                if self.quest and GameTooltip then GameTooltip:SetOwner(self, 'ANCHOR_LEFT'); tooltip(self.quest, self.quest.pins) end
            end)
            row:SetScript('OnClick', function(self)
                if not self.quest or not view.questData then return end
                for level = 1, #view.questData.floors do
                    for _, point in ipairs(M.QuestPoints(view.questData, level)) do
                        if point.quest.id == self.quest.id then
                            view.floor, view.selectedQuest = level, self.quest.id
                            if view.onQuestSelect then view.onQuestSelect() end
                            return
                        end
                    end
                end
            end)
            row:SetScript('OnLeave', function() if GameTooltip then GameTooltip:Hide() end end)
            list.rows[i] = row
        end
    else view.questList:SetShown(not view.questList:IsShown()) end
    M.RefreshQuestList(view)
end
local events = CreateFrame('Frame')
for _, event in ipairs({ 'QUEST_LOG_UPDATE', 'QUEST_ACCEPTED', 'QUEST_REMOVED', 'QUEST_TURNED_IN', 'PLAYER_LEVEL_UP', 'QUEST_DATA_LOAD_RESULT' }) do events:RegisterEvent(event) end
local queued
local function refresh() queued = nil; if M.RefreshVisible then Q.Run('quêtes du plan', M.RefreshVisible) end end
events:SetScript('OnEvent', function()
    version = version + 1
    if not queued and C_Timer and C_Timer.After then queued = true; C_Timer.After(0.1, refresh)
    elseif not C_Timer or not C_Timer.After then refresh() end
end)
