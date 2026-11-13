local _, Q = ...
-- États relus auprès du jeu, jamais sauvegardés ni déduits d'un simple titre identique.
local function read(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
end
-- Une réponse nulle du cache n'est pas une preuve d'absence d'XP.
function Q.QuestXP(id)
    local value = read(GetQuestLogRewardXP, id)
    if type(value) == 'number' and value > 0 then return math.floor(value), false end
    local meta = Q.REFERENCE_QUEST_INFO[id]
    value = meta and meta.xp
    if type(value) == 'number' and value >= 0 then return math.floor(value), true end
end
function Q.XPText(value)
    if value == nil then return 'XP inconnue' end
    local text = tostring(value)
    repeat local n; text, n = text:gsub('^(%d+)(%d%d%d)', '%1 %2') until n == 0
    return text .. ' XP'
end
function Q.QuestRewardItems(id)
    local info = Q.REFERENCE_QUEST_INFO[id]
    return info and info.rewardItems, info and info.rewardChoice == true
end
function Q.QuestXPSummary(id)
    local steps = Q.QuestJourney(id)
    local total, remaining, unknown, estimated = 0, 0, 0, false
    for _, step in ipairs(steps) do
        local xp, fallback = Q.QuestXP(step.id)
        if xp == nil then unknown = unknown + 1
        else
            total = total + xp
            if step.state ~= 'done' then remaining = remaining + xp end
            estimated = estimated or fallback
        end
    end
    return total, remaining, unknown, estimated
end
function Q.AddQuestXPTooltip(id, main)
    if not GameTooltip then return end
    local xp, fallback = Q.QuestXP(id)
    GameTooltip:AddLine(Q.XPText(xp) .. (fallback and ' (référence indicative)' or ''), 1, 0.82, 0, true)
    if main then
        local total, remaining, unknown, estimated = Q.QuestXPSummary(id)
        GameTooltip:AddLine('Chaîne : ' .. Q.XPText(total) .. (unknown > 0 and (' + ' .. unknown .. ' étape(s) inconnue(s)') or '')
            .. (estimated and ' (indicatif)' or ''), 1, 1, 1, true)
        GameTooltip:AddLine('Encore à gagner : ' .. Q.XPText(remaining), 1, 1, 1, true)
        GameTooltip:AddLine('Prérequis et quête du donjon compris ; suites postérieures exclues.', 0.7, 0.7, 0.7, true)
    end
end
function Q.QuestJourney(id)
    local info = Q.REFERENCE_QUEST_INFO[id]
    if not info then return {}, 0, 0 end
    local rows, seen, completed = {}, {}, 0
    local function add(sid, fallback, main)
        if seen[sid] then return end
        seen[sid] = true
        local state = read(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, sid) == true and 'done'
            or read(C_QuestLog and C_QuestLog.IsOnQuest, sid) == true and 'log' or 'todo'
        if state == 'done' then completed = completed + 1 end
        local title = read(C_QuestLog and C_QuestLog.GetTitleForQuestID, sid)
        local meta = Q.REFERENCE_QUEST_INFO[sid]
        local complete = state == 'log' and read(C_QuestLog and C_QuestLog.IsComplete, sid) == true
        rows[#rows + 1] = { id = sid, title = type(title) == 'string' and title ~= '' and title or fallback,
            state = state, here = main, start = meta and meta.start, pins = {},
            finish = meta and meta.finish, objective = meta and meta.objectiveFR, note = meta and meta.noteFR,
            complete = complete,
            status = state == 'done' and 'Terminée' or complete and 'À rendre' or state == 'log' and 'En cours' or 'À faire' }
    end
    for _, step in ipairs(info.prereqs or {}) do add(step.id, step.title, false) end
    add(id, info.title, true)
    for index, step in ipairs(rows) do step.stepIndex = index; step.depth = step.here and 0 or 1 end
    return rows, completed, #rows
end
function Q.QuestDisplayRows(quests, expanded)
    local out = {}
    for _, quest in ipairs(quests) do
        local steps, completed, total = Q.QuestJourney(quest.id)
        quest.journey, quest.journeyDone, quest.journeyTotal = steps, completed, total
        quest.hasPrerequisites = total > 1
        out[#out + 1] = quest
        if total > 1 and expanded and expanded[quest.id] then
            for _, step in ipairs(steps) do
                if not step.here then
                    step.virtual = true; step.parentQuest = quest.id; step.stateText = step.status
                    step.tag = 'prérequis'; step.level = 0; step.holders = {}; step.groupHas = {}; step.groupMissing = {}
                    out[#out + 1] = step
                end
            end
        end
    end
    return out
end
-- Un clic sur une étape ouvre son donneur ; aucun point intérieur n'est transformé en coordonnée extérieure.
function Q.ShowJourneyPlace(id, title)
    if Quintessence.HasDungeonQuestWaypoint and Quintessence.HasDungeonQuestWaypoint(id) then
        return Quintessence.ShowDungeonQuestWaypoint(id, title)
    end
    local ready = read(C_QuestLog and C_QuestLog.IsOnQuest, id) == true and read(C_QuestLog and C_QuestLog.IsComplete, id) == true
    local place = ready and Q.REFERENCE_QUEST_TURNINS and Q.REFERENCE_QUEST_TURNINS[id] or Q.REFERENCE_QUEST_PLACES[id]
    if not place or not place.map or not place.x or not place.y then
        Q.Print('Emplacement du donneur non renseigné pour ' .. Q.Safe(title) .. '.'); return false
    end
    local ok = false
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        ok = pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(place.map, place.x / 100, place.y / 100))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
    end
    if C_Map and C_Map.OpenWorldMap then pcall(C_Map.OpenWorldMap, place.map) end
    Q.Print(Q.Safe(title) .. ' : ' .. Q.Safe(place.start or 'donneur') .. string.format(' (%.1f, %.1f).', place.x, place.y))
    return ok
end
