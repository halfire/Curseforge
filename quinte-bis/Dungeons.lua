local _, Q = ...
--[[
  Donjons et raids de WoW Forever (liste de Wowhead Forever relevée le 04/11/2026 ; nouveaux donjons sous leur nom
  anglais, `new = true`). Les clés sont celles du site (site/app/game.php, activités du
  group finder) : garder les deux listes identiques quand Forever ajoute du contenu. Une clé inconnue reçue d'un
  membre plus à jour reste acceptée et s'affiche telle quelle.
]]
Q.DUNGEONS = {
    { key = 'RFC', name = 'Gouffre de Ragefeu', min = 13, max = 18 },
    { key = 'THANES', name = 'The Hall of Thanes', min = 13, max = 18, new = true },
    { key = 'LORDAERON', name = 'Ruins of Lordaeron', min = 15, max = 20, new = true },
    { key = 'WC', name = 'Cavernes des Lamentations', min = 17, max = 24 },
    { key = 'DM', name = 'Les Mortemines', min = 17, max = 26 },
    { key = 'SFK', name = 'Donjon d\'Ombrecroc', min = 22, max = 30 },
    { key = 'EXCAV', name = 'Excavation Site: Wetlands', min = 24, max = 29, new = true },
    { key = 'STOCKS', name = 'La Prison', min = 24, max = 32 },
    { key = 'BFD', name = 'Profondeurs de Brassenoire', min = 24, max = 32 },
    { key = 'SM_GY', name = 'Monastère écarlate — Cimetière', min = 26, max = 36 },
    { key = 'DALARAN', name = 'City of Dalaran', min = 28, max = 33, new = true },
    { key = 'GNOMER', name = 'Gnomeregan', min = 29, max = 38 },
    { key = 'RFK', name = 'Kraal de Tranchebauge', min = 29, max = 38 },
    { key = 'SM_LIB', name = 'Monastère écarlate — Bibliothèque', min = 29, max = 39 },
    { key = 'SM_ARM', name = 'Monastère écarlate — Armurerie', min = 32, max = 42 },
    { key = 'DROWNED', name = 'The Drowned City', min = 35, max = 40, new = true },
    { key = 'SM_CATH', name = 'Monastère écarlate — Cathédrale', min = 35, max = 45 },
    { key = 'RFD', name = 'Souilles de Tranchebauge', min = 37, max = 46 },
    { key = 'KROLDOK', name = 'Krol\'dok Stronghold', min = 40, max = 45, new = true },
    { key = 'ULDA', name = 'Uldaman', min = 41, max = 51 },
    { key = 'ZF', name = 'Zul\'Farrak', min = 44, max = 54 },
    { key = 'MARA', name = 'Maraudon', min = 46, max = 55 },
    { key = 'ALCAZ', name = 'Alcaz Prison', min = 48, max = 53, new = true },
    { key = 'ST', name = 'Temple d\'Atal\'Hakkar', min = 50, max = 60 },
    { key = 'BRD', name = 'Profondeurs de Rochenoire', min = 52, max = 60 },
    { key = 'BLACKMAW', name = 'Blackmaw Hold', min = 55, max = 60, new = true },
    { key = 'LBRS', name = 'Pic Rochenoire inférieur', min = 55, max = 60 },
    { key = 'DME', name = 'Hache-Tripes Est', min = 55, max = 60 },
    { key = 'DMW', name = 'Hache-Tripes Ouest', min = 57, max = 60 },
    { key = 'DMN', name = 'Hache-Tripes Nord', min = 57, max = 60 },
    { key = 'SHAPER', name = 'Shaper\'s Terrace', min = 58, max = 60, new = true },
    { key = 'STRAT', name = 'Stratholme', min = 58, max = 60 },
    { key = 'SCHOLO', name = 'Scholomance', min = 58, max = 60 },
    { key = 'UBRS', name = 'Pic Rochenoire supérieur', min = 55, max = 60, raid = true },
    { key = 'ONY', name = 'Repaire d\'Onyxia', min = 60, max = 60, raid = true },
    -- Raids vanilla (tables de butin dans RaidLoot.lua, en attendant celles de Forever)
    { key = 'MC', name = 'Cœur du Magma', min = 60, max = 60, raid = true },
    { key = 'BWL', name = 'Repaire de l\'Aile noire', min = 60, max = 60, raid = true },
    { key = 'ZG', name = 'Zul\'Gurub', min = 60, max = 60, raid = true },
    { key = 'AQ20', name = 'Ruines d\'Ahn\'Qiraj', min = 60, max = 60, raid = true },
    { key = 'AQ40', name = 'Temple d\'Ahn\'Qiraj', min = 60, max = 60, raid = true },
    { key = 'NAXX', name = 'Naxxramas', min = 60, max = 60, raid = true },
    { key = 'HYJAL', name = 'Sommet d\'Hyjal', min = 60, max = 60, raid = true },
    { key = 'BARROW', name = 'Barrow Deeps', min = 60, max = 60, raid = true },
    -- Hors instance : artisanat, quêtes, réputation, PvP…
    { key = 'CRAFT', name = 'Artisanat', other = true },
    { key = 'QUEST', name = 'Quête', other = true },
    { key = 'REP', name = 'Réputation', other = true },
    { key = 'PVP', name = 'PvP', other = true },
    { key = 'WORLD', name = 'Monde (élite, butin rare)', other = true },
}
Q.DUNGEON_BY_KEY = {}
Q.LEVELING_SOURCES = {}
for i, d in ipairs(Q.DUNGEONS) do
    d.order = i
    Q.DUNGEON_BY_KEY[d.key] = d
    if not d.raid then
        Q.LEVELING_SOURCES[#Q.LEVELING_SOURCES + 1] = d
    end
end

function Q.DungeonName(key)
    local d = key and Q.DUNGEON_BY_KEY[key]
    return d and d.name or (key or 'Source inconnue')
end
function Q.DungeonLevels(key)
    local d = key and Q.DUNGEON_BY_KEY[key]
    if not d or not d.min then return '' end
    return d.min == d.max and ('niv. ' .. d.min) or (d.min .. '-' .. d.max)
end
