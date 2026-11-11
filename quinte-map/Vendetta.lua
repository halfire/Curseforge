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

-- Compatibilité des anciens appels : aucun registre, message ni émission Vendetta.
function Q.ReportKillByEnemy() return nil end
function Q.MarkVendettaAvenged() return false end
function Q.RemoveVendetta() return false end
function Q.OnReceiveVendetta() end
function Q.OnReceiveVendettaAvenged() end
function Q.GetVendettaList() return {} end
function Q.GetActiveVendettaCount() return 0 end

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

end

function Q.InitVendetta()
    local f = CreateFrame('Frame')
    -- Uniquement des événements autorisés sur Midnight 12.0 / WoW Forever (jamais COMBAT_LOG_EVENT_UNFILTERED)
    local events = {
        'PLAYER_TARGET_CHANGED',
        'UPDATE_MOUSEOVER_UNIT',
        'NAME_PLATE_UNIT_ADDED',
        'UNIT_TARGET',
    }
    for _, ev in ipairs(events) do Q.Call(f.RegisterEvent, f, ev) end

    -- Gestionnaire sans fermeture créée à chaque événement : UNIT_TARGET arrive des dizaines de fois par seconde en raid
    local function onEvent(event, arg1)
        -- Le journal qualifié remplace l'attribution automatique historique ; SOS et saisie manuelle préservés.
        if Q.PvP and Q.PvP.ready and (event == 'PLAYER_DEAD' or event == 'PLAYER_PVP_KILLS_CHANGED') then return end
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
        end
    end
    f:SetScript('OnEvent', function(_, event, arg1)
        Q.Run(event, onEvent, event, arg1)
    end)
end
