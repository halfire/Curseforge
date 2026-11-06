local _, Q = ...
local Lib = LibStub('LibQuinteSync-1.0')
local function bounded(value, maximum)
    if type(value) ~= 'table' then return false end
    local n = 0
    for _ in pairs(value) do n = n + 1; if n > maximum then return false end end
    return true
end
local function array(value, maximum)
    if not bounded(value, maximum) then return false end
    local n = 0
    for k in pairs(value) do
        if not Q.Number(k, 1, maximum, true) then return false end
        n = n + 1
    end
    if #value ~= n then return false end
    for i = 1, n do if value[i] == nil then return false end end
    return true
end
local stringFields = {'name', 'realm', 'class', 'race', 'faction', 'guild', 'guildRank', 'spec'}
local numberFields = {sex = {1, 3, true}, level = {1, 1000, true}, itemLevel = {0, 10000}, updated = {0, 1e12, true}}
local statFields = {'health', 'power', 'strength', 'agility', 'stamina', 'intellect', 'spirit', 'armor', 'attackPower', 'spellPower'}
local resistanceFields = {'fire', 'frost', 'nature', 'shadow', 'arcane'}
local function field(target, source, name, kind, lo, hi, integer)
    local value = source[name]
    if value == nil then return true end
    local clean
    if kind == 'string' then clean = Q.String(value, hi) else clean = Q.Number(value, lo, hi, integer) end
    if clean == nil then return false end
    target[name] = clean; return true
end
local function validate(value, recordKey, now)
    if not bounded(value, 25) or not Q.String(recordKey) then return nil end
    local clean = {}
    for _, name in ipairs(stringFields) do if not field(clean, value, name, 'string') then return nil end end
    for name, limits in pairs(numberFields) do
        if not field(clean, value, name, 'number', unpack(limits)) then return nil end
    end
    if not field(clean, value, 'talents', 'string', nil, 2048) then return nil end
    if not clean.name or not clean.realm or not clean.updated or clean.updated > now + 300 then return nil end
    if Lib.CanonicalKey(clean.name .. '-' .. clean.realm:gsub('%s', '')) ~= Lib.CanonicalKey(recordKey) then return nil end
    if clean.class and not clean.class:match('^[A-Z_]+$') then return nil end
    if clean.faction and clean.faction ~= 'Alliance' and clean.faction ~= 'Horde' and clean.faction ~= 'Neutral' then return nil end
    if value.stats ~= nil then
        if not bounded(value.stats, 11) then return nil end
        local stats = {}
        for _, name in ipairs(statFields) do if not field(stats, value.stats, name, 'number', 0, 1e12) then return nil end end
        if value.stats.resistances ~= nil then
            if not bounded(value.stats.resistances, 5) then return nil end
            stats.resistances = {}
            for _, name in ipairs(resistanceFields) do
                if not field(stats.resistances, value.stats.resistances, name, 'number', -100000, 100000) then return nil end
            end
        end
        clean.stats = stats
    end
    if value.pvp ~= nil then
        if not bounded(value.pvp, 3) then return nil end
        clean.pvp = {}
        if not field(clean.pvp, value.pvp, 'rank', 'number', 0, 100, true)
            or not field(clean.pvp, value.pvp, 'rankName', 'string')
            or not field(clean.pvp, value.pvp, 'honorableKills', 'number', 0, 1e10, true) then return nil end
    end
    -- Accès de raid et clés (Attunements.lua) : n'étaient pas recopiés, donc jamais vus chez les autres ni sur le site
    -- pour une fiche reçue. Clés inconnues acceptées (version plus récente), valeurs booléennes seulement.
    if value.attunements ~= nil then
        if not bounded(value.attunements, 32) then return nil end
        clean.attunements = {}
        for k, v in pairs(value.attunements) do
            if not Q.String(k, 16) or not k:match('^[%l%d_]+$') or type(v) ~= 'boolean' then return nil end
            clean.attunements[k] = v
        end
    end
    -- Raids verrouillés cette semaine : { CLÉ = fin du verrou } (clés RAID_EVENTS du site), dates proches seulement
    if value.lockouts ~= nil then
        if not bounded(value.lockouts, 16) then return nil end
        clean.lockouts = {}
        for k, v in pairs(value.lockouts) do
            if not Q.String(k, 12) or not k:match('^[%u%d_]+$') or not Q.Number(v, 0, now + 30 * 86400, true) then return nil end
            clean.lockouts[k] = v
        end
    end
    -- Journal de pex (Journey.lua) : { since, start, min, levels = { { niveau, date, carte, minutes } }, zones = { [carte] = minutes } }
    if value.pex ~= nil then
        local p = value.pex
        if not bounded(p, 5) or not array(p.levels, 80) or not bounded(p.zones, 64) then return nil end
        clean.pex = {levels = {}, zones = {}}
        if not field(clean.pex, p, 'since', 'number', 0, now + 300, true) or not field(clean.pex, p, 'start', 'number', 1, 1000, true)
            or not field(clean.pex, p, 'min', 'number', 0, 5000000) then return nil end
        for i, row in ipairs(p.levels) do
            if not array(row, 4) or not Q.Number(row[1], 1, 1000, true) or not Q.Number(row[2], 0, now + 300, true)
                or not Q.Number(row[3], 0, 1e7, true) or not Q.Number(row[4], 0, 5000000) then return nil end
            clean.pex.levels[i] = {row[1], row[2], row[3], row[4]}
        end
        for map, minutes in pairs(p.zones) do
            if not Q.Number(map, 1, 1e7, true) or not Q.Number(minutes, 0, 5000000) then return nil end
            clean.pex.zones[map] = minutes
        end
    end
    if value.professions ~= nil then
        if not array(value.professions, 16) then return nil end
        clean.professions = {}; local names = {}
        for _, row in ipairs(value.professions) do
            if not bounded(row, 3) then return nil end
            local p = {}
            if not field(p, row, 'name', 'string') or not p.name or names[p.name]
                or not field(p, row, 'skill', 'number', 0, 10000)
                or not field(p, row, 'maxSkill', 'number', 0, 10000) then return nil end
            if p.skill and p.maxSkill and p.skill > p.maxSkill then return nil end
            names[p.name] = true; clean.professions[#clean.professions + 1] = p
        end
        table.sort(clean.professions, function(a, b) return a.name < b.name end)
    end
    if value.equipment ~= nil then
        if not array(value.equipment, 19) then return nil end
        clean.equipment = {}; local slots = {}
        for _, row in ipairs(value.equipment) do
            if not bounded(row, 6) then return nil end
            local e = {}
            if not field(e, row, 'slot', 'number', 1, 19, true) or not e.slot or slots[e.slot]
                or not field(e, row, 'item', 'number', 1, 1e9, true) or not e.item
                or not field(e, row, 'name', 'string')
                or not field(e, row, 'ilvl', 'number', 0, 10000)
                or not field(e, row, 'enchant', 'number', 0, 1e9, true)
                or not field(e, row, 'quality', 'number', 0, 8, true) then return nil end
            slots[e.slot] = true; clean.equipment[#clean.equipment + 1] = e
        end
        table.sort(clean.equipment, function(a, b) return a.slot < b.slot end)
    end
    return clean
end
-- Personnage pas connecté depuis un mois : fiche retirée, sauf au niveau maximum (60 sur Forever). La date d'une
-- fiche avance à chaque déconnexion. Fiches retirées notées dans db.purged pour ne pas être redemandées.
local INACTIVE, MAX_LEVEL, PURGE_MEMORY = 30 * 86400, 60, 60 * 86400
local function inactive(c, now)
    if now >= 1793808000 and (tonumber(c.updated) or 0) < 1793808000 then return true end -- fiche de la bêta (RESET_AT)
    return (tonumber(c.level) or 0) < MAX_LEVEL and (tonumber(c.updated) or 0) < now - INACTIVE
end
local function purgedAt(db, key) return type(db.purged) == 'table' and db.purged[Lib.CanonicalKey(key)] or nil end
Q.INACTIVE, Q.MAX_LEVEL = INACTIVE, MAX_LEVEL
-- Sous le niveau 10, une fiche n'est ni partagée, ni acceptée, ni affichée (le joueur garde seulement la sienne)
local MIN_LEVEL = 10
Q.MIN_LEVEL = MIN_LEVEL
local function tooLow(c) return (tonumber(c.level) or 0) < MIN_LEVEL end
-- Sortie de WoW Forever (4 novembre 2026) : toute fiche d'avant le 04/11/2026 16:00 UTC (bêta) est effacée une fois
-- (Q.ResetBeforeLaunch, appelé à l'initialisation) et refusée ensuite par la synchro. Le site fait de même (v16).
local RESET_AT = 1793808000
Q.RESET_AT = RESET_AT
-- (seulement une fois l'heure passée : un client à l'heure d'avant n'efface rien, il le fera au chargement suivant)
local function launched(now) return (now or Q.Now()) >= RESET_AT end
function Q.ResetBeforeLaunch(db)
    if (tonumber(db.resetAt) or 0) >= RESET_AT or not launched() then return 0 end
    local n = 0
    for key, c in pairs(db.characters) do
        if type(c) ~= 'table' or (tonumber(c.updated) or 0) < RESET_AT then db.characters[key] = nil; n = n + 1 end
    end
    db.purged, db.resetAt = nil, RESET_AT
    return n
end
local function existing(db, key)
    local canonical = Lib.CanonicalKey(key)
    for stored, c in pairs(db.characters) do if Lib.CanonicalKey(stored) == canonical then return c, stored end end
end
-- Fiches déjà validées (une fiche n'est jamais modifiée sur place : relevé et fusion la remplacent) : le manifeste,
-- relu à chaque résumé reçu, revalidait chaque fiche en entier (100 fiches équipées : 5 ms à chaque fois).
local checked = setmetatable({}, {__mode = 'k'})
local function manifest(db)
    local batches, batch, now = {}, {}, Q.Now()
    for key, c in pairs(db.characters) do
        if not tooLow(c) and (checked[c] == key or validate(c, key, now)) then
            checked[c] = key
            batch[#batch + 1] = {key = key, updated = c.updated}
            if #batch == 20 then batches[#batches + 1] = batch; batch = {} end
        end
    end
    if #batch > 0 then batches[#batches + 1] = batch end
    return batches
end
local function need(db, remote)
    if not array(remote, 20) then return {} end
    for _, row in ipairs(remote) do
        if not bounded(row, 2) or not Q.String(row.key) or not Q.Number(row.updated, 0, Q.Now() + 300, true) then return {} end
    end
    local result = {}
    for _, row in ipairs(remote) do
        local old = existing(db, row.key)
        local gone = purgedAt(db, row.key)
        if Q.sync:Member(row.key) and row.updated >= Q.Now() - 60 * 86400 and (row.updated >= RESET_AT or not launched()) and not (gone and row.updated <= gone)
            and (not old or old.source ~= 'self' and row.updated > (old.updated or 0)) then
            result[#result + 1] = {key = row.key}
        end
    end
    return result
end
local function export(db, request)
    if not bounded(request, 1) or not Q.String(request.key) then return {} end
    local c = db.characters[request.key]
    if not c then return {} end
    local clean = validate(c, request.key, Q.Now())
    if not clean or tooLow(clean) then return {} end
    return {{key = request.key, character = clean}}
end
local function merge(db, part, sender, now, request)
    if not bounded(part, 2) or not request or part.key ~= request.key or not Q.String(part.key) or not Q.String(sender)
        or not Q.sync:Member(part.key) then return false end
    local old, storedKey = existing(db, part.key)
    if old and old.source == 'self' then return false end
    if not old and not bounded(db.characters, 999) then return false end
    local clean = validate(part.character, part.key, now)
    if not clean or tooLow(clean) or clean.updated < now - 60 * 86400 or old and clean.updated <= (old.updated or 0) then return false end
    local gone = purgedAt(db, part.key)
    if not old and ((gone and clean.updated <= gone) or inactive(clean, now)) then return false end
    clean.source, clean.syncedFrom, clean.syncedAt = 'sync', sender, now
    db.characters[storedKey or part.key] = clean
    return true
end
local function cleanup(db, roster, now)
    local mine = Q.Key and Q.Key() or Quintessence.Key()
    for key, c in pairs(db.characters) do
        if type(c) == 'table' and key ~= mine and inactive(c, now) then
            -- (aussi nos propres autres personnages : le perso connecté n'est jamais retiré)
            db.purged = db.purged or {}
            db.purged[Lib.CanonicalKey(key)] = tonumber(c.updated) or 0
            db.characters[key] = nil
        elseif type(c) == 'table' and c.source ~= 'self' and (tooLow(c) or
            not roster[Lib.CanonicalKey(key)] or not Q.Number(c.updated, now - 60 * 86400, now + 300, true)) then
            db.characters[key] = nil
        end
    end
    for key, at in pairs(db.purged or {}) do
        if type(at) ~= 'number' or at < now - PURGE_MEMORY then db.purged[key] = nil end
    end
end
function Q.SyncInit()
    -- La synchro de guilde est gérée par le conteneur Quintessence (canal unique pour tous les modules)
    Q.sync = Quintessence:RegisterSync('caract', QuinteCaractDB, {Manifest = manifest, Need = need,
        Export = export, Merge = merge, Cleanup = cleanup, Changed = Q.Changed})
end
Q.SyncAdapter = {Validate = validate, Manifest = manifest, Need = need, Export = export, Merge = merge, Cleanup = cleanup}
