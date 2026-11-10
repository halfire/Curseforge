local _, Q = ...
-- Les plans et quêtes du dossier de référence passent par nos composants, sans charger son interface.
Q.DUNGEON_MAP_QUESTS = Q.REFERENCE_QUESTS
for id, place in pairs(Q.REFERENCE_QUEST_PLACES) do
    local meta = Q.REFERENCE_QUEST_INFO[id]
    if meta then meta.place = place end
end
local byKey = {}
for _, entry in ipairs(Q.DUNGEON_LOOT) do byKey[entry.key] = entry end
for code, map in pairs(Q.REFERENCE_MAPS) do
    local entry = byKey[code]
    if not entry then entry = { key = code, bosses = {} }; Q.DUNGEON_LOOT[#Q.DUNGEON_LOOT + 1] = entry; byKey[code] = entry end
    local names = {}
    for _, boss in ipairs(entry.bosses) do names[boss.name] = true end
    for _, boss in ipairs(map.bosses) do
        if not names[boss.name] and not boss.quest then entry.bosses[#entry.bosses + 1] = { name = boss.name, items = {} }; names[boss.name] = true end
    end
end
-- Complément des objets portables explicitement déclarés dans loot ; probableLoot et objets sans ID exclus.
-- Une absence de FDJ ne retire jamais un objet du relevé Wowhead ni une découverte de la guilde.
for code, bosses in pairs(Q.REFERENCE_EQUIPMENT) do
    local entry = byKey[code]
    if not entry then entry = { key = code, bosses = {} }; Q.DUNGEON_LOOT[#Q.DUNGEON_LOOT + 1] = entry; byKey[code] = entry end
    local seen, named = {}, {}
    for _, boss in ipairs(entry.bosses) do
        named[boss.name] = boss
        for _, item in ipairs(boss.items) do seen[item[1]] = true end
    end
    for _, ref in ipairs(bosses) do
        local target = named[ref.name]
        if not target then target = { name = ref.name, items = {} }; entry.bosses[#entry.bosses + 1] = target; named[ref.name] = target end
        local own = {}
        for _, item in ipairs(target.items) do own[item[1]] = true end
        for _, item in ipairs(ref.items) do
            if not own[item[1]] then
                target.items[#target.items + 1] = { item[1], item[2], item[3] }; own[item[1]] = true
            end
        end
    end
end
