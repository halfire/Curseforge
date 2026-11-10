local _, Q = ...
Q.DUNGEON_QUESTS = Q.REFERENCE_QUESTS
-- Les coordonnées validées par le dossier fourni remplacent les anciennes et complètent les manquantes.
-- Les noms français déjà connus sont conservés ; les numéros de carte restent résolus dans Entrances.lua.
for id, place in pairs(Q.REFERENCE_QUEST_PLACES) do
    local previous = Q.DUNGEON_QUEST_PLACES[id] or {}
    local current = {}
    for key, value in pairs(previous) do current[key] = value end
    for key, value in pairs(place) do if value ~= nil then current[key] = value end end
    if previous.start then
        local same = not place.map
        for word in tostring(place.start or ''):gmatch('%S+') do
            if #word >= 4 and previous.start:lower():find(word:lower(), 1, true) then same = true end
        end
        if same then current.start = previous.start end
    end
    if place.map then current.at = nil end
    Q.DUNGEON_QUEST_PLACES[id] = current
end
local allowed = {}
for _, quests in pairs(Q.REFERENCE_QUESTS) do for _, quest in ipairs(quests) do allowed[quest[1]] = true end end
for id, info in pairs(Q.REFERENCE_QUEST_INFO) do
    for _, step in ipairs(info.prereqs or {}) do if allowed[id] then allowed[step.id] = true end end
end
for id in pairs(Q.DUNGEON_QUEST_PLACES) do if not allowed[id] then Q.DUNGEON_QUEST_PLACES[id] = nil end end
