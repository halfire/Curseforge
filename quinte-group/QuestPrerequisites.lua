local _, Q = ...
-- États relus auprès du jeu, jamais sauvegardés ni déduits d'un simple titre identique.
local function read(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not (issecretvalue and issecretvalue(value)) then return value end
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
        rows[#rows + 1] = { id = sid, title = type(title) == 'string' and title ~= '' and title or fallback,
            state = state, here = main, start = meta and meta.start, pins = {},
            status = state == 'done' and 'Terminée' or state == 'log' and 'En cours' or 'À faire' }
    end
    for _, step in ipairs(info.prereqs or {}) do add(step.id, step.title, false) end
    add(id, info.title, true)
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
function Q.ShowJourneyPlace(id, title, code)
    if Q.ShowDungeonQuestPlace then return Q.ShowDungeonQuestPlace(id, title, code) end
    local place = Q.REFERENCE_QUEST_PLACES[id]
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
