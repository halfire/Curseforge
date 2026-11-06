local _, Q = ...
--[[
  Vendetta.lua : Registre PvP & Vengeance de la guilde Quintessence.
  - Détecte automatiquement quel joueur ennemi t'a attaqué ou tué en PvP sauvage
    via les événements d'unités autorisés sur Midnight 12.0 / WoW Forever
    (PLAYER_TARGET_CHANGED, UPDATE_MOUSEOVER_UNIT, NAME_PLATE_UNIT_ADDED, UNIT_TARGET,
    PLAYER_DEAD, PLAYER_PVP_KILLS_CHANGED — sans COMBAT_LOG_EVENT_UNFILTERED qui est restreint).
  - Partage en temps réel avec toute la guilde : nom du tueur, classe, victime,
    zone, coordonnées X/Y, Layer et nombre de meurtres.
  - Alerte automatique quand un membre cible, survole ou croise un tueur recherché.
  - Détecte automatiquement (sur victoire honorable PvP ou d'un clic) quand un membre venge la victime !
]]

local VENDETTA_TTL = 7 * 86400 -- 7 jours d'historique
local ATTACKER_WINDOW = 45 -- secondes entre le dernier contact hostile et PLAYER_DEAD
local lastAttacker = nil
local knownEnemies = {} -- cache local { [name] = { class = ..., level = ... } }
local spottedCooldown = {}

local function isSecret(v)
    return type(issecretvalue) == 'function' and issecretvalue(v)
end

local function safeString(v)
    if v == nil or isSecret(v) or type(v) ~= 'string' then return nil end
    return v
end

local function safeBool(ok, val)
    if not ok or isSecret(val) then return false end
    return val and true or false
end

local function enemyKey(name)
    name = safeString(name)
    if not name then return nil end
    local clean = name:match('^%s*(.-)%s*$')
    if clean == '' then return nil end
    return clean:lower()
end

function Q.GetLastAttacker()
    if lastAttacker and (Q.Now() - (lastAttacker.time or 0)) <= ATTACKER_WINDOW then
        return lastAttacker
    end
    return nil
end

-- Enregistre un joueur ennemi hostile (ciblé, en combat ou nous ciblant) pour l'associer à une mort PvP ou un SOS
function Q.RecordEnemyAttack(enemyName, enemyClass, enemyLevel, spellName)
    enemyName = safeString(enemyName)
    if not enemyName or enemyName == '' then return end
    local k = enemyKey(enemyName)
    if not k then return end
    local cached = knownEnemies[k]
    local cleanClass = safeString(enemyClass) or (cached and cached.class) or nil
    local cleanLevel = (not isSecret(enemyLevel) and tonumber(enemyLevel)) or (cached and cached.level) or nil
    if cleanClass or cleanLevel then
        knownEnemies[k] = {
            class = cleanClass or (cached and cached.class),
            level = cleanLevel or (cached and cached.level),
        }
    end
    lastAttacker = {
        name = enemyName,
        class = cleanClass,
        level = cleanLevel,
        spell = safeString(spellName),
        time = Q.Now(),
    }
end

-- Enregistre qu'un joueur ennemi a tué un membre de Quintessence (automatique à PLAYER_DEAD ou manuel)
function Q.ReportKillByEnemy(enemyName, enemyClass, enemyLevel, spellName)
    enemyName = safeString(enemyName)
    if not enemyName then return nil end
    enemyName = enemyName:match('^%s*(.-)%s*$')
    local k = enemyKey(enemyName)
    if not k then return nil end

    if not QuinteMapDB.vendetta then QuinteMapDB.vendetta = {} end
    local cached = knownEnemies[k]
    local x, y, mapID = Q.GetPlayerCoordinates()
    local zone = safeString(GetZoneText and GetZoneText()) or 'Inconnue'
    local subzone = safeString(GetSubZoneText and GetSubZoneText()) or ''
    local layer = Q.DetectCurrentLayer and Q.DetectCurrentLayer()
    local myName = Q.PlayerName()
    local _, rawMyClass = UnitClass and UnitClass('player')
    local myClass = safeString(rawMyClass)
    local now = Q.Now()

    local existing = QuinteMapDB.vendetta[k]
    local kills = (existing and existing.kills or 0) + 1
    local victims = (existing and type(existing.victims) == 'table') and existing.victims or {}
    local foundVictim = false
    for _, v in ipairs(victims) do
        if v == myName then foundVictim = true; break end
    end
    if not foundVictim and myName then victims[#victims + 1] = myName end

    local entry = {
        key = k,
        enemy = enemyName,
        enemyClass = safeString(enemyClass) or (cached and cached.class) or (existing and existing.enemyClass) or 'WARRIOR',
        enemyLevel = (not isSecret(enemyLevel) and tonumber(enemyLevel)) or (cached and cached.level) or (existing and existing.enemyLevel) or nil,
        victim = myName,
        victimClass = myClass or 'WARRIOR',
        victims = victims,
        kills = kills,
        zone = zone,
        subzone = subzone,
        mapID = mapID,
        x = x,
        y = y,
        layer = layer,
        spell = safeString(spellName) or (existing and existing.spell) or nil,
        time = now,
        avenged = false,
        avengedBy = nil,
        avengedAt = nil,
    }

    QuinteMapDB.vendetta[k] = entry

    if Q.comm and Q.comm.Send then
        Q.comm:Send({
            t = 'vendetta',
            entry = entry,
        })
    end

    Q.Print(string.format('|cffff2020[Vendetta PvP]|r Tué par |cffffffff%s|r à %s (%.1f, %.1f · %s) — signalé à la guilde pour vengeance !',
        Q.Safe(enemyName), Q.Safe(zone), x or 0, y or 0, Q.LayerLabel(layer)))

    if Q.UpdateWorldMapPins then Q.UpdateWorldMapPins() end
    if Q.UI and Q.UI.RefreshVendetta then Q.UI.RefreshVendetta() end
    return entry
end

-- Marque un ennemi comme vengé (automatique sur victoire honorable PvP ou via le bouton « Vengé ! »)
function Q.MarkVendettaAvenged(enemyName, avengerName)
    local k = enemyKey(enemyName)
    if not k or not QuinteMapDB.vendetta or not QuinteMapDB.vendetta[k] then return false end
    local entry = QuinteMapDB.vendetta[k]
    local avenger = safeString(avengerName) or Q.PlayerName()
    local now = Q.Now()
    local zone = safeString(GetZoneText and GetZoneText()) or entry.zone or 'Inconnue'

    entry.avenged = true
    entry.avengedBy = avenger
    entry.avengedAt = now

    if Q.comm and Q.comm.Send then
        Q.comm:Send({
            t = 'vendetta_avenged',
            key = k,
            enemy = entry.enemy,
            victim = entry.victim,
            avengedBy = avenger,
            zone = zone,
            time = now,
        })
    end

    Q.Print(string.format('|cff5cd1a8[VENGEANCE ACCOMPLIE]|r |cffffffff%s|r a vengé |cffffffff%s|r en éliminant |cffff5555%s|r à %s !',
        Q.Safe(avenger), Q.Safe(entry.victim or 'la guilde'), Q.Safe(entry.enemy), Q.Safe(zone)))

    if Q.UI and Q.UI.RefreshVendetta then Q.UI.RefreshVendetta() end
    return true
end

-- Supprime une entrée de la liste de Vendetta
function Q.RemoveVendetta(enemyName)
    local k = enemyKey(enemyName)
    if not k or not QuinteMapDB.vendetta then return false end
    QuinteMapDB.vendetta[k] = nil
    if Q.UI and Q.UI.RefreshVendetta then Q.UI.RefreshVendetta() end
    return true
end

-- Réception réseau d'un meurtre PvP signalé par un membre
function Q.OnReceiveVendetta(data, sender)
    if not data or type(data.entry) ~= 'table' or not sender then return end
    local inc = data.entry
    local k = enemyKey(inc.enemy)
    if not k then return end

    if not QuinteMapDB.vendetta then QuinteMapDB.vendetta = {} end
    local existing = QuinteMapDB.vendetta[k]
    inc.key = k
    inc.victim = inc.victim or sender
    inc.kills = math.max(tonumber(inc.kills) or 1, (existing and existing.kills or 0) + 1)
    QuinteMapDB.vendetta[k] = inc

    if QuinteMapDB.settings and QuinteMapDB.settings.chatAlert then
        Q.Print(string.format('|cffff2020[Vendetta Guilde]|r |cffffffff%s|r a été tué par |cffff5555%s|r à %s (%.1f, %.1f · %s) !',
            Q.Safe(inc.victim), Q.Safe(inc.enemy), Q.Safe(inc.zone or 'Inconnue'),
            inc.x or 0, inc.y or 0, Q.LayerLabel(inc.layer)))
    end

    if Q.UpdateWorldMapPins then Q.UpdateWorldMapPins() end
    if Q.UI and Q.UI.RefreshVendetta then Q.UI.RefreshVendetta() end
end

-- Réception réseau d'une vengeance accomplie par un membre
function Q.OnReceiveVendettaAvenged(data, sender)
    if not data or not data.enemy then return end
    local k = enemyKey(data.enemy)
    if not k then return end
    if not QuinteMapDB.vendetta then QuinteMapDB.vendetta = {} end

    local entry = QuinteMapDB.vendetta[k]
    local avenger = data.avengedBy or sender or 'Un membre'
    if entry then
        entry.avenged = true
        entry.avengedBy = avenger
        entry.avengedAt = data.time or Q.Now()
    end

    if QuinteMapDB.settings and QuinteMapDB.settings.chatAlert then
        Q.Print(string.format('|cff5cd1a8[VENGEANCE ACCOMPLIE]|r |cffffffff%s|r a vengé |cffffffff%s|r en éliminant |cffff5555%s|r !',
            Q.Safe(avenger), Q.Safe(data.victim or (entry and entry.victim) or 'la guilde'), Q.Safe(data.enemy)))
    end

    if Q.UI and Q.UI.RefreshVendetta then Q.UI.RefreshVendetta() end
end

-- Liste filtrée et triée des cibles de Vendetta
function Q.GetVendettaList(filterMode, query)
    local list = {}
    if not QuinteMapDB or not QuinteMapDB.vendetta then return list end
    local now = Q.Now()
    local needle = (query or ''):lower()

    for k, entry in pairs(QuinteMapDB.vendetta) do
        if (now - (entry.time or 0)) > VENDETTA_TTL then
            QuinteMapDB.vendetta[k] = nil
        else
            local modeOK = true
            if filterMode == 'active' then modeOK = not entry.avenged
            elseif filterMode == 'avenged' then modeOK = entry.avenged and true or false end

            local searchOK = true
            if needle ~= '' then
                local hay = ((entry.enemy or '') .. ' ' .. (entry.victim or '') .. ' ' .. (entry.zone or '') .. ' ' .. (entry.subzone or '')):lower()
                searchOK = hay:find(needle, 1, true) ~= nil
            end

            if modeOK and searchOK then
                list[#list + 1] = entry
            end
        end
    end

    table.sort(list, function(a, b)
        if (not a.avenged) ~= (not b.avenged) then
            return not a.avenged
        end
        return (a.time or 0) > (b.time or 0)
    end)
    return list
end

function Q.GetActiveVendettaCount()
    return #Q.GetVendettaList('active')
end

-- Inspecte une unité sans jamais déclencher d'action protégée ni d'erreur sur valeur secrète Midnight 12.0
function Q.CheckUnitForVendetta(unit, recordAsAttacker)
    if not unit or not UnitExists then return end
    if not safeBool(pcall(UnitExists, unit)) then return end
    if UnitIsPlayer and not safeBool(pcall(UnitIsPlayer, unit)) then return end
    if UnitCanAttack and not safeBool(pcall(UnitCanAttack, 'player', unit)) then return end

    local okN, rawName = pcall(UnitName, unit)
    local name = okN and safeString(rawName) or nil
    local k = enemyKey(name)
    if not k then return end

    local class, level = nil, nil
    if UnitClass then
        local okC, _, rawClass = pcall(UnitClass, unit)
        if okC then class = safeString(rawClass) end
    end
    if UnitLevel then
        local okL, rawLevel = pcall(UnitLevel, unit)
        if okL and not isSecret(rawLevel) then level = tonumber(rawLevel) end
    end

    -- Mise à jour sur place : une table neuve à chaque survol, plaque ou changement de cible créait des déchets
    local cached = knownEnemies[k]
    if cached then
        cached.class, cached.level = class, level
    else
        knownEnemies[k] = { class = class, level = level }
    end

    -- Si c'est notre cible hostile, ou s'il nous cible / est en combat, on le mémorise comme agresseur potentiel
    local isAggro = recordAsAttacker or (unit == 'target')
    if not isAggro and UnitIsUnit then
        isAggro = safeBool(pcall(UnitIsUnit, unit .. 'target', 'player'))
    end
    if isAggro then
        Q.RecordEnemyAttack(name, class, level)
    end

    if QuinteMapDB and QuinteMapDB.vendetta and QuinteMapDB.vendetta[k] then
        local entry = QuinteMapDB.vendetta[k]
        if class then entry.enemyClass = class end
        if level and level > 0 then entry.enemyLevel = level end
        if not entry.avenged then
            local now = Q.Now()
            if not spottedCooldown[k] or (now - spottedCooldown[k]) > 30 then
                spottedCooldown[k] = now
                local x, y, mapID = Q.GetPlayerCoordinates()
                entry.zone = safeString(GetZoneText and GetZoneText()) or entry.zone
                entry.subzone = safeString(GetSubZoneText and GetSubZoneText()) or entry.subzone
                entry.mapID = mapID or entry.mapID
                entry.x = (x and x > 0) and x or entry.x
                entry.y = (y and y > 0) and y or entry.y
                entry.layer = Q.DetectCurrentLayer and Q.DetectCurrentLayer() or entry.layer
                Q.Print(string.format('|cffff2020[CIBLE VENDETTA REPÉRÉE]|r |cffffffff%s|r (meurtrier de %s) est devant toi à %s (%s) !',
                    Q.Safe(entry.enemy), Q.Safe(entry.victim or 'la guilde'), Q.Safe(entry.zone or 'Inconnue'), Q.LayerLabel(entry.layer)))
                if PlaySound and QuinteMapDB.settings and QuinteMapDB.settings.soundAlert then
                    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
                end
                if Q.UI and Q.UI.RefreshVendetta then Q.UI.RefreshVendetta() end
            end
        end
    end
end

function Q.InitVendetta()
    local f = CreateFrame('Frame')
    -- Uniquement des événements autorisés sur Midnight 12.0 / WoW Forever (jamais COMBAT_LOG_EVENT_UNFILTERED)
    local events = {
        'PLAYER_DEAD',
        'PLAYER_TARGET_CHANGED',
        'UPDATE_MOUSEOVER_UNIT',
        'NAME_PLATE_UNIT_ADDED',
        'UNIT_TARGET',
        'PLAYER_PVP_KILLS_CHANGED',
    }
    for _, ev in ipairs(events) do Q.Call(f.RegisterEvent, f, ev) end

    -- Gestionnaire sans fermeture créée à chaque événement : UNIT_TARGET arrive des dizaines de fois par seconde en raid
    local function onEvent(event, arg1)
        if event == 'PLAYER_TARGET_CHANGED' then
            Q.CheckUnitForVendetta('target', true)
        elseif event == 'UPDATE_MOUSEOVER_UNIT' then
            Q.CheckUnitForVendetta('mouseover', false)
        elseif event == 'NAME_PLATE_UNIT_ADDED' and type(arg1) == 'string' then
            Q.CheckUnitForVendetta(arg1, false)
        elseif event == 'UNIT_TARGET' and type(arg1) == 'string' and arg1 ~= 'player'
            and not arg1:find('^raid') and not arg1:find('^party') then
            -- Les membres du groupe/raid (et leurs familiers) ne sont jamais des ennemis à venger
            Q.CheckUnitForVendetta(arg1, false)
        elseif event == 'PLAYER_DEAD' then
            local attacker = Q.GetLastAttacker()
            if not attacker then
                Q.CheckUnitForVendetta('target', true)
                attacker = Q.GetLastAttacker()
            end
            if attacker and attacker.name then
                Q.ReportKillByEnemy(attacker.name, attacker.class, attacker.level, attacker.spell)
                lastAttacker = nil
            end
        elseif event == 'PLAYER_PVP_KILLS_CHANGED' then
            local attacker = Q.GetLastAttacker()
            if attacker and attacker.name then
                local k = enemyKey(attacker.name)
                if k and QuinteMapDB and QuinteMapDB.vendetta and QuinteMapDB.vendetta[k] and not QuinteMapDB.vendetta[k].avenged then
                    Q.MarkVendettaAvenged(attacker.name, Q.PlayerName())
                end
            end
        end
    end
    f:SetScript('OnEvent', function(_, event, arg1)
        Q.Run(event, onEvent, event, arg1)
    end)
end
