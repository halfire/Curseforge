local _, Q = ...
--[[
  Entrances.lua : entrée de chaque donjon, affichée par le bouton « Afficher l'entrée » de l'onglet Donjons
  (repère + flèche Blizzard et carte du monde ouverte, jamais d'écriture dans WorldMapFrame).

  Coordonnées relevées le 06/11/2026 dans les guides de Warcraft Tavern pour WoW Forever.
  `approx` : position notée de mémoire ou sources en désaccord, à confirmer en jeu.
  La carte est cherchée par le nom de la zone (français ou anglais), puis par son numéro Classic (`id`), car les
  numéros de Forever ne sont pas confirmés. Sans carte trouvée, la position reste écrite dans le chat.
]]
local ZONES = {
    ORGRIMMAR = { fr = 'Orgrimmar', en = 'Orgrimmar', id = 1454 },
    IRONFORGE = { fr = 'Forgefer', en = 'Ironforge', id = 1455 },
    STORMWIND = { fr = 'Hurlevent', en = 'Stormwind City', id = 1453 },
    TIRISFAL = { fr = 'Clairières de Tirisfal', en = 'Tirisfal Glades', id = 1420 },
    BARRENS = { fr = 'Les Tarides', en = 'The Barrens', id = 1413 },
    WESTFALL = { fr = 'Marche de l\'Ouest', en = 'Westfall', id = 1436 },
    SILVERPINE = { fr = 'Forêt des Pins-Argentés', en = 'Silverpine Forest', id = 1421 },
    ASHENVALE = { fr = 'Orneval', en = 'Ashenvale', id = 1440 },
    WETLANDS = { fr = 'Les Paluns', en = 'Wetlands', id = 1437 },
    DUNMOROGH = { fr = 'Dun Morogh', en = 'Dun Morogh', id = 1426 },
    STV = { fr = 'Vallée de Strangleronce', en = 'Stranglethorn Vale', id = 1434 },
    RIVERGLADES = { fr = 'Riverglades', en = 'Riverglades' },
    BADLANDS = { fr = 'Terres ingrates', en = 'Badlands', id = 1418 },
    TANARIS = { fr = 'Tanaris', en = 'Tanaris', id = 1446 },
    DESOLACE = { fr = 'Désolace', en = 'Desolace', id = 1443 },
    DUSTWALLOW = { fr = 'Marécage d\'Âprefange', en = 'Dustwallow Marsh', id = 1445 },
    SWAMP = { fr = 'Marais des Chagrins', en = 'Swamp of Sorrows', id = 1435 },
    STEPPES = { fr = 'Steppes ardentes', en = 'Burning Steppes', id = 1428 },
    AZSHARA = { fr = 'Azshara', en = 'Azshara', id = 1447 },
    FERALAS = { fr = 'Féralas', en = 'Feralas', id = 1444 },
    UNGORO = { fr = 'Cratère d\'Un\'Goro', en = 'Un\'Goro Crater', id = 1449 },
    EPL = { fr = 'Maleterres de l\'est', en = 'Eastern Plaguelands', id = 1423 },
    WPL = { fr = 'Maleterres de l\'ouest', en = 'Western Plaguelands', id = 1422 },
}
local BLACKROCK = 'Entrée du mont Rochenoire : descends la grande chaîne au centre de la montagne.'
local MONASTERY = 'Dans le bâtiment principal, chaque aile a son portail.'
local DIRE_MAUL = 'Le portail de cette aile donne sur la cour centrale ou la rue d\'entrée de Hache-Tripes.'
Q.ENTRANCES = {
    RFC = { zone = 'ORGRIMMAR', x = 52.8, y = 49.6, note = 'Faille de l\'Ombre, au centre d\'Orgrimmar.' },
    THANES = { zone = 'IRONFORGE', x = 43.5, y = 52.0, note = 'Dans la salle du trône, passage couvert de toiles à gauche : descends-le.' },
    LORDAERON = { zone = 'TIRISFAL', x = 61, y = 67, approx = true, note = 'Après la porte principale, escalier à gauche avant le donjon.' },
    WC = { zone = 'BARRENS', x = 46.0, y = 36.3, note = 'Grotte au-dessus de l\'oasis.' },
    DM = { zone = 'WESTFALL', x = 42, y = 72, note = 'Grand bâtiment au sud-ouest de Ruisselune, puis la mine.' },
    SFK = { zone = 'SILVERPINE', x = 44.5, y = 68.0, note = 'Au nord du village de Bois-du-Bûcher.' },
    EXCAV = { zone = 'WETLANDS', x = 48.1, y = 56.5, note = 'Le sentier commence près de la pierre de rencontre (53.9, 65.4).' },
    STOCKS = { zone = 'STORMWIND', x = 42, y = 58, note = 'Quartier des Canaux, près du quartier des Mages.' },
    BFD = { zone = 'ASHENVALE', x = 14.5, y = 14.6, note = 'Ruines englouties de la Grève de Zoram : plonge.' },
    SM_GY = { zone = 'TIRISFAL', x = 84, y = 32, note = MONASTERY .. ' Cimetière : tout à gauche.' },
    SM_LIB = { zone = 'TIRISFAL', x = 84, y = 32, note = MONASTERY },
    SM_ARM = { zone = 'TIRISFAL', x = 84, y = 32, note = MONASTERY },
    SM_CATH = { zone = 'TIRISFAL', x = 84, y = 32, note = MONASTERY },
    DALARAN = { zone = 'SILVERPINE', x = 69.3, y = 45.6, note = 'On entre par les égouts, côté Pins-Argentés.' },
    GNOMER = { zone = 'DUNMOROGH', x = 24, y = 40, note = 'Nord-ouest de Dun Morogh.' },
    RFK = { zone = 'BARRENS', x = 43, y = 90, note = 'Sud-ouest des Tarides.' },
    DROWNED = { zone = 'STV', x = 21.4, y = 27.9, note = 'Sous l\'eau, au large de la côte.' },
    RFD = { zone = 'BARRENS', x = 43, y = 95, approx = true, note = 'Sud des Tarides, dans le dédale de ronces.' },
    KROLDOK = { zone = 'RIVERGLADES', x = 37.5, y = 37.5, note = 'Grotte à l\'ouest des grandes portes de la forteresse.' },
    ULDA = { zone = 'BADLANDS', x = 44, y = 12, note = 'Nord des Terres ingrates. Entrée arrière vers (66, 43).' },
    ZF = { zone = 'TANARIS', x = 39, y = 20, note = 'Nord-ouest de Tanaris.' },
    MARA = { zone = 'DESOLACE', x = 38, y = 58, note = 'Porte de pierre à l\'ouest de la vallée, puis les cavernes.' },
    ALCAZ = { zone = 'DUSTWALLOW', x = 75, y = 15, note = 'Sous-sol du grand bâtiment de l\'île d\'Alcaz.' },
    ST = { zone = 'SWAMP', x = 70, y = 54, approx = true, note = 'Au milieu du lac : nage jusqu\'au temple.' },
    BRD = { zone = 'STEPPES', x = 29, y = 37, approx = true, note = BLACKROCK },
    LBRS = { zone = 'STEPPES', x = 29, y = 37, approx = true, note = BLACKROCK },
    BLACKMAW = { zone = 'AZSHARA', x = 38.7, y = 33.4, note = 'Tunnel des furbolgs ; le portail est tout au bout, côté Berceau-de-l\'Hiver.' },
    DME = { zone = 'FERALAS', x = 59, y = 45, approx = true, note = DIRE_MAUL },
    DMW = { zone = 'FERALAS', x = 59, y = 45, approx = true, note = DIRE_MAUL .. ' Clé en croissant requise.' },
    DMN = { zone = 'FERALAS', x = 59, y = 45, approx = true, note = DIRE_MAUL .. ' Clé en croissant requise.' },
    SHAPER = { zone = 'UNGORO', x = 48.1, y = 6.1, note = 'Colline au-dessus du Refuge des Marshal.' },
    STRAT = { zone = 'EPL', x = 27, y = 12, approx = true, note = 'Nord-ouest des Maleterres de l\'est.' },
    SCHOLO = { zone = 'WPL', x = 69.7, y = 73.2, approx = true, note = 'Île de Caer Darrow. Clé squelette requise.' },
}

local function plain(name)
    return (tostring(name or ''):lower():gsub('’', '\''))
end
-- Index nom de zone -> carte, lu une fois dans le jeu
local mapIndex
local function buildIndex()
    mapIndex = {}
    if not (C_Map and C_Map.GetMapChildrenInfo) then return end
    for _, root in ipairs({ 947, 946 }) do
        local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
        if ok and type(list) == 'table' then
            for _, info in ipairs(list) do
                local key = info.name and plain(info.name)
                if key and not mapIndex[key] then mapIndex[key] = info.mapID end
            end
        end
    end
end
local function findMap(fr, en, id)
    if not mapIndex then buildIndex() end
    local found = (fr and mapIndex[plain(fr)]) or (en and mapIndex[plain(en)])
    if found then return found end
    if id and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if ok and info then return id end
    end
    return nil
end
--- Numéro de carte d'une zone d'entrée, nil si le jeu ne la connaît pas.
function Q.EntranceMap(zoneKey)
    local zone = ZONES[zoneKey]
    if not zone then return nil end
    return findMap(zone.fr, zone.en, zone.id)
end
local function placeWaypoint(mapID, x, y, title, route, kind)
    local navigation = Quintessence and Quintessence.Navigation
    if route then
        if not navigation then Q.Print('Mets à jour le conteneur Quintessence pour utiliser les itinéraires.'); return false end
        local placed, reason = navigation.Start('group', mapID, x, y, title, kind)
        Q.Print(navigation.Message(reason))
        return placed
    end
    if navigation then navigation.Clear(nil, true) end
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
    if C_Map.CanSetUserWaypointOnMap then
        local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
        if not ok or not can then return false end
    end
    local ok = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    return ok
end
-- Carte du monde : C_Map.OpenWorldMap est protégée en combat. Le jeu la bloque (ADDON_ACTION_BLOCKED, BugGrabber du GM
-- le 12/11/2026, bouton Carte d'une quête de donjon) sans erreur Lua, donc `pcall` ne voit rien : en combat on ne
-- l'appelle pas, elle s'ouvre à la fin du combat (PLAYER_REGEN_ENABLED). Le repère et le texte du chat sont posés tout de suite.
local pendingMap, mapWaiter
local function openWorldMap(mapID)
    if not (C_Map and C_Map.OpenWorldMap) then return end
    if InCombatLockdown and InCombatLockdown() then
        pendingMap = mapID
        if not mapWaiter then
            mapWaiter = CreateFrame('Frame')
            Q.Call(mapWaiter.RegisterEvent, mapWaiter, 'PLAYER_REGEN_ENABLED')
            mapWaiter:SetScript('OnEvent', function()
                local id = pendingMap
                pendingMap = nil
                if id then Q.Run('carte', openWorldMap, id) end
            end)
        end
        Q.Print('La carte s\'ouvrira à la fin du combat (le jeu l\'interdit aux addons en combat).')
        return
    end
    pcall(C_Map.OpenWorldMap, mapID)
end
-- Les guides fournissent une zone et des coordonnées, jamais une position inventée depuis un objectif.
function Q.ShowGuidePlace(point, title, route)
    if type(point) ~= 'table' or type(point.x) ~= 'number' or type(point.y) ~= 'number'
        or point.x < 0 or point.x > 100 or point.y < 0 or point.y > 100 then return false end
    local mapID = findMap(point.fr, point.en, point.id)
    if not mapID then Q.Print('La carte de cette zone n’est pas disponible.'); return false end
    local placed = placeWaypoint(mapID, point.x, point.y, title, route, 'quest')
    openWorldMap(mapID)
    Q.Print(Q.Safe(title) .. ' : ' .. Q.Safe(point.fr) .. string.format(' (%.1f, %.1f), selon le guide.', point.x, point.y))
    return placed
end
--- Un clic : repère, flèche et carte ouverte sur l'entrée ; la position est toujours écrite dans le chat.
function Q.ShowDungeonEntrance(code, route)
    local e = Q.ENTRANCES[code]
    local d = Q.DUNGEON_BY_CODE and Q.DUNGEON_BY_CODE[code]
    local name = d and d.name or tostring(code)
    if not e then Q.Print('Entrée inconnue pour ' .. name .. '.'); return false end
    local zone = ZONES[e.zone]
    local text = string.format('%s : %s (%s, %s)%s. %s', name, zone.fr, e.x, e.y, e.approx and ', position approximative' or '', e.note)
    local mapID = Q.EntranceMap(e.zone)
    local placed = mapID and placeWaypoint(mapID, e.x, e.y, name, route, 'dungeon')
    if mapID then openWorldMap(mapID) end
    Q.Print(text .. (placed and '' or ' Repère impossible sur cette carte.'))
    return placed and true or false
end

-- Nom français des zones où l'on prend les quêtes (les lieux sont notés en anglais) ; Riverglades n'a pas de nom français connu
local ZONE_FR = {
    ['Alterac Mountains'] = 'Montagnes d\'Alterac', ['Arathi Highlands'] = 'Hautes-terres d\'Arathi', ['Ashenvale'] = 'Orneval',
    ['Azshara'] = 'Azshara', ['Badlands'] = 'Terres ingrates', ['Blasted Lands'] = 'Terres foudroyées',
    ['Burning Steppes'] = 'Steppes ardentes', ['Darkshore'] = 'Sombrivage', ['Darnassus'] = 'Darnassus',
    ['Deadwind Pass'] = 'Défilé de Deuillevent', ['Desolace'] = 'Désolace', ['Dun Morogh'] = 'Dun Morogh',
    ['Durotar'] = 'Durotar', ['Duskwood'] = 'Bois de la Pénombre', ['Dustwallow Marsh'] = 'Marécage d\'Âprefange',
    ['Eastern Plaguelands'] = 'Maleterres de l\'est', ['Elwynn Forest'] = 'Forêt d\'Elwynn', ['Felwood'] = 'Gangrebois',
    ['Feralas'] = 'Féralas', ['Hillsbrad Foothills'] = 'Contreforts de Hautebrande', ['Ironforge'] = 'Forgefer',
    ['Loch Modan'] = 'Loch Modan', ['Moonglade'] = 'Reflet-de-Lune', ['Mulgore'] = 'Mulgore', ['Orgrimmar'] = 'Orgrimmar',
    ['Redridge Mountains'] = 'Les Carmines', ['Searing Gorge'] = 'Gorge des Vents brûlants', ['Silithus'] = 'Silithus',
    ['Silverpine Forest'] = 'Forêt des Pins-Argentés', ['Stonetalon Mountains'] = 'Les Serres-Rocheuses',
    ['Stormwind City'] = 'Hurlevent', ['Stranglethorn Vale'] = 'Vallée de Strangleronce',
    ['Swamp of Sorrows'] = 'Marais des Chagrins', ['Tanaris'] = 'Tanaris', ['Teldrassil'] = 'Teldrassil',
    ['The Barrens'] = 'Les Tarides', ['The Hinterlands'] = 'Les Hinterlands', ['Thousand Needles'] = 'Mille pointes',
    ['Thunder Bluff'] = 'Les Pitons-du-Tonnerre', ['Tirisfal Glades'] = 'Clairières de Tirisfal', ['Undercity'] = 'Fossoyeuse',
    ['Un\'Goro Crater'] = 'Cratère d\'Un\'Goro', ['Western Plaguelands'] = 'Maleterres de l\'ouest', ['Westfall'] = 'Marche de l\'Ouest',
    ['Wetlands'] = 'Les Paluns', ['Winterspring'] = 'Berceau-de-l\'Hiver',
}

local function questPlace(questId)
    local finish = Q.REFERENCE_QUEST_TURNINS and Q.REFERENCE_QUEST_TURNINS[questId]
    if finish and Q.IsOnQuest(questId) and C_QuestLog and C_QuestLog.IsComplete then
        local ok, ready = pcall(C_QuestLog.IsComplete, questId)
        if ok and not (issecretvalue and issecretvalue(ready)) and ready == true then return finish end
    end
    return Q.DUNGEON_QUEST_PLACES and Q.DUNGEON_QUEST_PLACES[questId]
end
--- La quête a-t-elle un repère sur la carte du monde ou le plan du donjon ?
function Q.HasDungeonQuestPlace(questId, code)
    local p = questPlace(questId)
    return (p and p.start and (p.at or (p.x and p.y)) and true)
        or (code and Quintessence.HasDungeonQuestPin and Quintessence.HasDungeonQuestPin(code, questId)) or false
end
function Quintessence.HasDungeonQuestWaypoint(questId)
    local p = questPlace(questId)
    return p and p.start and p.x and p.y and not p.at and true or false
end
--- Phrase décrivant où prendre une quête, nil si le lieu est inconnu.
local function placeText(p, questId)
    if not (p and p.start) then return nil end
    local who = Q.Safe(p.start)
    local text
    if p.at == 'inside' then text = who .. (p.item and ' (objet trouvé)' or '') .. ', dans le donjon'
    elseif p.x then text = string.format('%s, %s (%.1f, %.1f)', who, ZONE_FR[p.zone] or p.zone or '?', p.x, p.y)
    else text = who end
    local info = Q.DUNGEON_QUEST_INFO and Q.DUNGEON_QUEST_INFO[questId]
    local note = (info and info.note) or p.note
    if note then text = text .. ' · ' .. note end
    return text
end
--- Un clic sur « Carte » : repère et carte sur le donneur ; quête prise dans le donjon, repère sur son entrée.
function Q.ShowDungeonQuestPlace(questId, title, code, route)
    local p = questPlace(questId)
    if not route and code and (not p or not p.x or p.at) and Quintessence.ShowDungeonQuestPin
        and Quintessence.ShowDungeonQuestPin(code, questId) then return true end
    local name = Q.Safe(title or ('quête ' .. tostring(questId)))
    if not (p and p.start) then Q.Print('Lieu inconnu pour ' .. name .. '.'); return false end
    Q.Print(name .. ' : ' .. placeText(p, questId) .. '.')
    if p.at then return code ~= nil and Q.ShowDungeonEntrance(code, route) end
    if not (p.x and p.y) then return false end
    local mapID = findMap(ZONE_FR[p.zone], p.zone, p.map)
    local placed = mapID and placeWaypoint(mapID, p.x, p.y, title, route, 'pickup')
    if mapID then openWorldMap(mapID) end
    if not placed then Q.Print('Repère impossible sur cette carte.') end
    return placed and true or false
end
function Quintessence.ShowDungeonQuestWaypoint(questId, title)
    if not Quintessence.HasDungeonQuestWaypoint(questId) then return false end
    return Q.ShowDungeonQuestPlace(questId, title)
end
--- Écrit dans le chat où prendre les quêtes encore à faire du donjon (une carte ne porte qu'un seul repère).
function Q.PrintDungeonQuestPlaces(code)
    local d = Q.DUNGEON_BY_CODE and Q.DUNGEON_BY_CODE[code]
    local shown = 0
    for _, q in ipairs(Q.DungeonQuests and Q.DungeonQuests(code) or {}) do
        if q.state ~= 'done' then
            local text = placeText(Q.DUNGEON_QUEST_PLACES and Q.DUNGEON_QUEST_PLACES[q.id], q.id)
            if shown == 0 then Q.Print('Lieux des quêtes : ' .. Q.Safe(d and d.name or tostring(code))) end
            Q.Print(string.format('[%d] %s : %s', q.level or 0, Q.Safe(q.title), text or 'lieu inconnu'))
            shown = shown + 1
        end
    end
    if shown == 0 then Q.Print('Aucune quête à prendre pour ce donjon.') end
    return shown
end
