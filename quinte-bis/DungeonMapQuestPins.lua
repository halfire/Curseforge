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
local function questPins(code, id)
    local out, referenceTargets, seen = {}, {}, {}
    local details = Q.DUNGEON_MAP_QUEST_DETAILS and Q.DUNGEON_MAP_QUEST_DETAILS[code] or {}
    -- La référence prime pour un même lieu ; les anciens objectifs complémentaires restent disponibles.
    for source, list in ipairs({ (Q.REFERENCE_QUEST_PINS[code] or {})[id] or {}, (details[id] or {}).pins or {} }) do
        for _, point in ipairs(list) do
            local target = (point.kind or 'objective') .. ':' .. plain(point.target)
            local key = target .. ':' .. tostring(point.floor) .. ':' .. tostring(point.x) .. ':' .. tostring(point.y)
            if source == 1 then referenceTargets[target] = true end
            if not seen[key] and (source == 1 or not referenceTargets[target]) then
                out[#out + 1] = point; seen[key] = true
            end
        end
    end
    return out
end
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
    for _, raw in ipairs(Q.DUNGEON_MAP_QUESTS[code] or {}) do
        local id, meta = raw[1], details[raw[1]] or {}
        local info = Q.DUNGEON_MAP_QUEST_INFO and Q.DUNGEON_MAP_QUEST_INFO[id] or {}
        local reference = Q.REFERENCE_QUEST_INFO and Q.REFERENCE_QUEST_INFO[id]
        local journey = Q.QuestJourney(id)
        if reference then
            info = { class = reference.class }
            for _, step in ipairs(journey) do if not step.here and step.state ~= 'done' then info.prev = step.id; break end end
        end
        local done = C_QuestLog and read(C_QuestLog.IsQuestFlaggedCompleted, id)
        local title = C_QuestLog and read(C_QuestLog.GetTitleForQuestID, id)
        local active = C_QuestLog and read(C_QuestLog.IsOnQuest, id)
        local complete = active and C_QuestLog and read(C_QuestLog.IsComplete, id) == true
        local status = active and 'log' or done == true and 'done' or 'todo'
        if status == 'todo' then
            if number(info.class) and class and math.floor(info.class / class) % 2 ~= 1 then status = 'restricted'
            elseif info.prev and not (C_QuestLog and read(C_QuestLog.IsQuestFlaggedCompleted, info.prev) == true) then status = 'locked'
            elseif number(level) and number(info.level or raw[4]) and level < (info.level or raw[4]) then status = 'low' end
        end
        rows[#rows + 1] = { id = id, title = type(title) == 'string' and title ~= '' and title or raw[3],
            state = status, complete = complete, status = complete and 'À rendre' or STATE[status],
            start = (reference and reference.start) or meta.start,
            finish = (reference and reference.finish) or meta.finish,
            objective = (reference and reference.objectiveFR) or meta.objective,
            note = reference and reference.noteFR,
            pins = questPins(code, id) }
    end
    cache[code] = { version = version, rows = rows }
    return rows
end
local function tooltip(quest, located)
    if not GameTooltip then return end
    GameTooltip:SetText(Q.Safe(quest.title))
    GameTooltip:AddLine(quest.status or '', S.colors.gold[1], S.colors.gold[2], S.colors.gold[3], true)
    if quest.start and quest.start ~= '' then GameTooltip:AddLine('Départ : ' .. Q.Safe(quest.start), 1, 1, 1, true) end
    if quest.finish and quest.finish ~= '' then GameTooltip:AddLine('Retour : ' .. Q.Safe(quest.finish), 1, 1, 1, true) end
    if quest.objective and quest.objective ~= '' then GameTooltip:AddLine(Q.Safe(quest.objective), 1, 1, 1, true) end
    if quest.note and quest.note ~= '' then GameTooltip:AddLine(Q.Safe(quest.note), 1, 1, 1, true) end
    if not located then GameTooltip:AddLine('Position non renseignée.', 0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
end
local function questTooltip(pin)
    if not GameTooltip then return end
    GameTooltip:SetOwner(pin, 'ANCHOR_RIGHT')
    local first = pin.entries[1]
    if not first then return end
    tooltip(first.quest, true)
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
        if point.reference and data.reference and point.floor == level and number(point.x) and number(point.y) then
            found = { x = point.x, y = point.y, kind = point.kind, target = point.target }
        end
        for _, boss in ipairs(data.bosses) do
            if not found and not point.reference and plain(boss.name) == plain(point.target) and boss.floor == level and number(boss.x) and number(boss.y) then
                found = { x = boss.x, y = boss.y, kind = point.kind, target = point.target }; break
            end
        end
        local floor = data.floors[level]
        if not found and not point.reference and floor and (data.classic or (data.reference and floor.artName and Q.DUNGEON_MAPS[data.code]
            and plain(floor.artName) == plain(Q.DUNGEON_MAPS[data.code].art))) and floor.page == point.floor and number(point.x) and number(point.y) then
            found = { x = point.x, y = point.y, kind = point.kind, target = point.target }
        end
        if found and found.x >= 0 and found.x <= 1 and found.y >= 0 and found.y <= 1 then
            local key = found.x .. ':' .. found.y .. ':' .. found.kind
            if not seen[key] then seen[key] = true; out[#out + 1] = found end
        end
    end
    return out
end
function M.QuestMapRecords(code)
    local roots = M.QuestRecords(code)
    if cache[code].mapRows then return cache[code].mapRows end
    local out, seen = {}, {}
    local function add(quest)
        if seen[quest.id] then return end
        seen[quest.id] = true; quest.pins = questPins(code, quest.id); out[#out + 1] = quest
    end
    for _, quest in ipairs(roots) do add(quest) end
    for _, quest in ipairs(roots) do
        for _, step in ipairs(Q.QuestJourney(quest.id)) do
            if not step.here then step.parentQuest = quest.id; add(step) end
        end
    end
    cache[code].mapRows = out
    return out
end
local function hasOutsidePlace(quest)
    if Core.HasDungeonQuestWaypoint and Core.HasDungeonQuestWaypoint(quest.id) then return true end
    local ready = quest.complete
    local p = ready and Q.REFERENCE_QUEST_TURNINS and Q.REFERENCE_QUEST_TURNINS[quest.id] or Q.REFERENCE_QUEST_PLACES[quest.id]
    return p and number(p.map) and number(p.x) and number(p.y) or false
end
function M.HasQuestLocation(view, quest)
    if view.questData then
        if M.QuestFloor(view.questData, quest) then return true end
    end
    return hasOutsidePlace(quest)
end
function M.QuestFloor(data, quest)
    local record = { pins = questPins(data.code, quest.id) }
    local fallback
    local wanted = quest.complete and 'finish' or quest.state == 'log' and 'objective' or 'start'
    for level = 1, #data.floors do
        for _, point in ipairs(positions(record, data, level)) do
            fallback = fallback or level
            if point.kind == wanted then return level, true end
        end
    end
    return fallback
end
function M.SelectQuest(view, quest, insideOnly)
    if not view.questData then return false end
    local floor, preferred = M.QuestFloor(view.questData, quest)
    if not insideOnly and not preferred and hasOutsidePlace(quest) and
        (not floor or quest.complete or quest.state ~= 'log') then
        return Q.ShowJourneyPlace(quest.id, quest.title)
    end
    if floor then
        view.floor, view.selectedQuest = floor, quest.id
        if view.onQuestSelect then view.onQuestSelect() else M.RenderEmbedded(view) end
        return true
    end
    return false
end
function M.QuestPoints(data, level)
    local entries, byID = {}, {}
    for _, quest in ipairs(M.QuestMapRecords(data.code)) do
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
            pin:SetScript('OnClick', function(self)
                local entry = self.entries and self.entries[1]
                if entry and self.mapView then
                    local owner = self.mapView
                    owner.selectedQuest = entry.quest.id
                    owner.expandedQuests = owner.expandedQuests or {}
                    if entry.quest.parentQuest then owner.expandedQuests[entry.quest.parentQuest] = true end
                    if not owner.questList or not owner.questList:IsShown() then M.ToggleQuestList(owner) end
                    for index, quest in ipairs(Q.QuestDisplayRows(owner.questRecords, owner.expandedQuests)) do
                        if quest.id == entry.quest.id then
                            owner.questList.offset = math.max(0, index - #owner.questList.rows); break
                        end
                    end
                    if owner.onQuestSelect then owner.onQuestSelect() else M.RenderEmbedded(owner) end
                end
            end)
            view.questPins[i] = pin
        end
        pin.entries, pin.classic, pin.mapView = group.entries, data.classic, view
        pin:ClearAllPoints()
        pin:SetPoint('CENTER', view.canvas, 'TOPLEFT', math.min(width - 9, group.x * width + 17), -math.min(height - 9, group.y * height + 9))
        table.sort(group.entries, function(a, b)
            local function priority(entry)
                if entry.quest.id == view.selectedQuest then return 100 end
                if entry.quest.state == 'log' and entry.kind == 'finish' then return 90 end
                if entry.quest.state == 'log' then return 80 end
                if entry.quest.state == 'todo' and entry.kind == 'start' then return 70 end
                return entry.quest.state == 'done' and 0 or 10
            end
            return priority(a) > priority(b)
        end)
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
    view.expandedQuests = view.expandedQuests or {}
    local records = Q.QuestDisplayRows(view.questRecords or {}, view.expandedQuests)
    local offset = math.max(0, math.min(list.offset or 0, math.max(0, #records - #list.rows)))
    list.offset = offset
    for i, row in ipairs(list.rows) do
        local quest = records[offset + i]
        row.quest = quest; row:SetShown(quest ~= nil)
        if quest then
            local color = view.nativeStyle and (quest.state == 'done' and 'ff40d060' or quest.state == 'log' and 'ffffd100' or 'ffffffff') or quest.state == 'done' and S.hex.mint or quest.state == 'log' and S.hex.gold or S.hex.text
            row.label:SetText('|c' .. color .. Q.Safe(quest.title) .. '|r' .. (quest.hasPrerequisites and ('  ' .. quest.journeyDone .. '/' .. quest.journeyTotal) or ''))
            row.chain:SetShown(quest.hasPrerequisites and true or false)
            row.chain:SetLabel(view.expandedQuests[quest.id] and '-' or '+')
            local inset = quest.virtual and 32 or 0
            row.label:ClearAllPoints(); row.label:SetPoint('TOPLEFT', 28 + inset, -4); row.label:SetWidth(360 - inset - 48)
            row.state:ClearAllPoints(); row.state:SetPoint('TOPLEFT', 28 + inset, -20); row.state:SetWidth(360 - inset - 48)
            row.branch:SetShown(quest.virtual and true or false)
            row.stepIcon:SetShown(quest.virtual and true or false)
            row.stepIcon:SetTexture(quest.state == 'done' and 'Interface\\RaidFrame\\ReadyCheck-Ready' or quest.state == 'log' and ICON.finish or ICON.start)
            if quest.virtual then row.label:SetText('|c' .. color .. quest.stepIndex .. '. ' .. Q.Safe(quest.title) .. '|r') end
            local located = M.HasQuestLocation(view, quest)
            row.place:SetShown(located)
            row.state:SetText((quest.virtual and 'Prérequis · ' or '') .. quest.status .. (located and ' · repère connu' or ' · position non renseignée'))
            if row.SetSelected then row:SetSelected(quest.id == view.selectedQuest) end
        end
    end
end
function M.ToggleQuestList(view)
    if not view.questList then
        local list
        if view.nativeStyle then
            list = CreateFrame('Frame', nil, view.controls, 'BackdropTemplate')
            list:SetBackdrop({ bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background', edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border', tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            list:SetBackdropColor(0, 0, 0, 0.95)
        else list = S.Box(view.controls, S.colors.bg, S.colors.line) end
        view.questList = list
        list:SetSize(420, 304); list:SetPoint('TOPRIGHT', -6, -34); list.offset = 0
        list:SetFrameLevel(view.controls:GetFrameLevel() + 10)
        list:EnableMouseWheel(true); list:SetScript('OnMouseWheel', function(_, delta)
            list.offset = list.offset - delta; M.RefreshQuestList(view)
        end)
        list.rows = {}
        for i = 1, 8 do
            local row = view.nativeStyle and CreateFrame('Button', nil, list) or S.Row(list, 406, 34); row:SetSize(406, 34); row:SetPoint('TOPLEFT', 7, -7 - (i - 1) * 36)
            row.label = (view.nativeStyle and M.NativeText or S.Text)(row, 11); row.label:SetPoint('TOPLEFT', 28, -4); row.label:SetWidth(312)
            row.state = (view.nativeStyle and M.NativeText or S.Text)(row, 10, view.nativeStyle and {1,1,1} or S.colors.muted); row.state:SetPoint('TOPLEFT', 5, -19); row.state:SetWidth(335)
            row.chain = (view.nativeStyle and M.NativeButton or S.Button)(row, '+', 22, 22)
            row.chain:SetPoint('TOPLEFT', 1, -3)
            row.chain:SetScript('OnClick', function()
                if not row.quest then return end
                local id = row.quest.id; view.expandedQuests[id] = not view.expandedQuests[id]; M.RefreshQuestList(view)
            end)
            row.branch = row:CreateTexture(nil, 'ARTWORK'); row.branch:SetColorTexture(unpack(view.nativeStyle and {0.65,0.65,0.65,0.7} or S.colors.line))
            row.branch:SetPoint('TOPLEFT', 16, 0); row.branch:SetSize(1, 34)
            row.stepIcon = row:CreateTexture(nil, 'OVERLAY'); row.stepIcon:SetPoint('TOPLEFT', 36, -4); row.stepIcon:SetSize(16, 16)
            row.place = (view.nativeStyle and M.NativeButton or S.Button)(row, 'Carte', 44, 22)
            row.place:SetPoint('TOPRIGHT', -1, -3)
            row.place:SetScript('OnClick', function() if row.quest then M.SelectQuest(view, row.quest) end end)
            row:SetScript('OnEnter', function(self)
                if self.quest and GameTooltip then
                    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
                    tooltip(self.quest, M.HasQuestLocation(view, self.quest))
                end
            end)
            row:SetScript('OnClick', function(self)
                if self.quest then M.SelectQuest(view, self.quest) end
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
