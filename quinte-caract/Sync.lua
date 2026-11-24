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
    if not bounded(value, 28) or not Q.String(recordKey) then return nil end
    local clean = {}
    for _, name in ipairs(stringFields) do
        -- (royaume vide permis : clé « Prénom Nom- » d'un joueur dont le jeu cache le royaume, client Forever 71037)
        if name == 'realm' and value.realm == '' then clean.realm = ''
        elseif not field(clean, value, name, 'string') then return nil end
    end
    for name, limits in pairs(numberFields) do
        if not field(clean, value, name, 'number', unpack(limits)) then return nil end
    end
    if not field(clean, value, 'talents', 'string', nil, 2048) then return nil end
    if not clean.name or not clean.realm or not clean.updated or clean.updated > now + 300 then return nil end
    if Lib.CanonicalKey(clean.name .. '-' .. clean.realm:gsub('%s', '')) ~= Lib.CanonicalKey(recordKey) then return nil end
    if clean.class and not clean.class:match('^[A-Z_]+$') then return nil end
    if clean.faction and clean.faction ~= 'Alliance' and clean.faction ~= 'Horde' and clean.faction ~= 'Neutral' then return nil end
    if value.main ~= nil or value.family ~= nil or value.mainUpdated ~= nil then
        if not Q.String(value.main) or not Q.String(value.family, 64)
            or not value.family:match('^[%w:]+$') or not Q.Number(value.mainUpdated, 0, now + 300, true)
            or not value.main:match('^.+%-') or value.main:find('|', 1, true) then return nil end
        clean.main, clean.family, clean.mainUpdated = value.main, value.family, value.mainUpdated
    end
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
    if value.gameStats ~= nil then
        local s = value.gameStats
        local states = {ok = true, partial = true, empty = true, absent = true, restricted = true, error = true}
        if not bounded(s, 4) or not Q.String(s.state, 16) or not states[s.state]
            or not Q.Number(s.at, 0, now + 300, true) or not bounded(s.categories, 128) or not array(s.rows, 512) then return nil end
        local out, seen, bytes = {state = s.state, at = s.at, categories = {}, rows = {}}, {}, 0
        for id, label in pairs(s.categories) do
            if not Q.Number(id, 1, 1e9, true) or not Q.String(label, 100) then return nil end
            bytes = bytes + #label; out.categories[id] = label
        end
        for _, row in ipairs(s.rows) do
            if not array(row, 4) or #row ~= 4 or not Q.Number(row[1], 1, 1e9, true)
                or not Q.Number(row[2], 1, 1e9, true) or not out.categories[row[2]] or seen[row[1]]
                or not Q.String(row[3], 100) or not Q.String(row[4], 100) then return nil end
            bytes = bytes + #row[3] + #row[4]; seen[row[1]] = true
            out.rows[#out.rows + 1] = {row[1], row[2], row[3], row[4]}
        end
        if bytes > 40000 or (s.state ~= 'ok' and s.state ~= 'partial' and #out.rows > 0) then return nil end
        clean.gameStats = out
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
-- Index clé normalisée → clé rangée (T137) : la recherche parcourait toutes les fiches pour chaque entrée de manifeste
-- (9,4 ms par manifeste complet de 300 fiches, 0,09 ms avec l'index). Reconstruit quand une fiche apparaît ou disparaît.
-- strict (fusion) : une clé absente de l'index relance toujours la recherche complète, pour ne jamais prendre notre propre
-- fiche pour une inconnue ; sinon (manifestes) l'index est reconstruit au plus toutes les 2 s.
local index, indexedFor, indexedAt = {}, nil, -100
local function existing(db, key, strict)
    if db.characters[key] then return db.characters[key], key end
    local canonical = Lib.CanonicalKey(key)
    local stored = indexedFor == db.characters and index[canonical]
    if stored and db.characters[stored] then return db.characters[stored], stored end
    local clock = GetTime and GetTime() or 0
    if not strict and indexedFor == db.characters and clock - indexedAt < 2 then return nil end
    index, indexedFor, indexedAt = {}, db.characters, clock
    for k in pairs(db.characters) do index[Lib.CanonicalKey(k)] = k end
    stored = index[canonical]
    if stored then return db.characters[stored], stored end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Fiches en morceaux (T137, protocole 3) : chaque partie a sa date, et seules les parties plus récentes voyagent.
-- Avant : la fiche entière (8 messages) repartait pour une montée de métier, les stats ou le pex horaire ; les stats seules
-- tiennent en 2 messages, les métiers en 1. Les dates sont dans QuinteCaractDB.partStamps[clé] = { t = { partie = date },
-- h = { partie = empreinte } } (h : nos fiches seulement) ; les fiches elles-mêmes gardent le même format (site inchangé).
-- ---------------------------------------------------------------------------------------------------------------------
local PARTS = {
    id = {'name', 'realm', 'class', 'race', 'faction', 'guild', 'guildRank', 'spec', 'sex', 'level', 'itemLevel', 'main', 'family', 'mainUpdated'},
    eq = {'equipment'}, ta = {'talents'}, pr = {'professions'}, st = {'stats', 'pvp'}, px = {'pex'}, at = {'attunements', 'lockouts'},
}
local PART_ORDER = {'id', 'eq', 'ta', 'pr', 'st', 'px', 'at'}
Q.PARTS = PARTS
local function stampsStore(db)
    if type(db.partStamps) ~= 'table' then db.partStamps = {} end
    return db.partStamps
end
local function partValue(c, part)
    local out = {}
    for _, field in ipairs(PARTS[part]) do out[field] = c[field] end
    return out
end
-- Équipement sans les noms d'objets (relus en jeu chez celui qui reçoit) : 3 messages au lieu de 2 sinon
local function withoutNames(equipment)
    if type(equipment) ~= 'table' then return equipment end
    local out = {}
    for i, e in ipairs(equipment) do
        out[i] = {slot = e.slot, item = e.item, ilvl = e.ilvl, enchant = e.enchant, quality = e.quality}
    end
    return out
end
-- Dates des parties d'une fiche ; pour nos propres fiches, une partie dont le contenu a changé prend la date de la fiche
local function stamps(db, key, c)
    local all = stampsStore(db)
    local entry = all[key]
    if type(entry) ~= 'table' or type(entry.t) ~= 'table' then entry = {t = {}}; all[key] = entry end
    local updated = tonumber(c.updated) or 0
    if c.source == 'self' then
        if type(entry.h) ~= 'table' then entry.h = {} end
        for _, part in ipairs(PART_ORDER) do
            local value = partValue(c, part)
            if part == 'eq' then value.equipment = withoutNames(value.equipment) end
            local h = Lib.Fingerprint(value)
            if entry.h[part] ~= h or not entry.t[part] then entry.h[part], entry.t[part] = h, updated end
        end
    end
    for _, part in ipairs(PART_ORDER) do
        local t = tonumber(entry.t[part])
        if not t or t > updated then entry.t[part] = updated end
    end
    return entry.t
end
Q.PartStamps = stamps
-- Fiches déjà validées (une fiche n'est jamais modifiée sur place : relevé et fusion la remplacent) : le manifeste,
-- relu à chaque résumé reçu, revalidait chaque fiche en entier (100 fiches équipées : 5 ms à chaque fois).
local checked = setmetatable({}, {__mode = 'k'})
local function manifest(db)
    local batches, batch, now = {}, {}, Q.Now()
    for key, c in pairs(db.characters) do
        if not tooLow(c) and (checked[c] == key or validate(c, key, now)) then
            checked[c] = key
            -- p : âge de chaque partie par rapport à la fiche (0 omis : partie changée à la dernière mise à jour)
            local t, p = stamps(db, key, c), nil
            for _, part in ipairs(PART_ORDER) do
                local age = c.updated - t[part]
                if age > 0 then p = p or {}; p[part] = age end
            end
            batch[#batch + 1] = {key = key, updated = c.updated, p = p}
            if #batch == 20 then batches[#batches + 1] = batch; batch = {} end
        end
    end
    if #batch > 0 then batches[#batches + 1] = batch end
    return batches
end
local function need(db, remote)
    if not array(remote, 20) then return {} end
    for _, row in ipairs(remote) do
        if not bounded(row, 3) or not Q.String(row.key) or not Q.Number(row.updated, 0, Q.Now() + 300, true) then return {} end
        if row.p ~= nil then
            if not bounded(row.p, #PART_ORDER) then return {} end
            for part, age in pairs(row.p) do if not PARTS[part] or not Q.Number(age, 0, 1e12, true) then return {} end end
        end
    end
    local result = {}
    for _, row in ipairs(remote) do
        local old, stored = existing(db, row.key)
        local gone = purgedAt(db, row.key)
        if Q.sync:Member(row.key) and row.updated >= Q.Now() - 60 * 86400 and (row.updated >= RESET_AT or not launched()) and not (gone and row.updated <= gone)
            and (not old or old.source ~= 'self' and row.updated > (old.updated or 0)) then
            if not old then result[#result + 1] = {key = row.key} -- fiche inconnue : en entier
            else
                -- seulement les parties plus récentes que les nôtres (liste vide : seule la date avance)
                local mine, parts = stamps(db, stored, old), {}
                for _, part in ipairs(PART_ORDER) do
                    if row.updated - ((row.p or {})[part] or 0) > (mine[part] or 0) then parts[#parts + 1] = part end
                end
                result[#result + 1] = {key = row.key, parts = parts}
            end
        end
    end
    return result
end
local function export(db, request)
    if not bounded(request, 2) or not Q.String(request.key) then return {} end
    local c = db.characters[request.key]
    if not c then return {} end
    local clean = validate(c, request.key, Q.Now())
    if not clean or tooLow(clean) then return {} end
    -- Les compteurs ne voyagent jamais avec les fiches diffusées à toute la guilde.
    clean.gameStats = nil
    clean.equipment = withoutNames(clean.equipment)
    local t = stamps(db, request.key, c)
    local s = {}
    for _, part in ipairs(PART_ORDER) do s[part] = t[part] end
    if request.parts == nil then return {{key = request.key, character = clean, s = s}} end
    if not array(request.parts, #PART_ORDER) then return {} end
    local d = {}
    for _, part in ipairs(request.parts) do
        if not PARTS[part] then return {} end
        for _, field in ipairs(PARTS[part]) do d[field] = clean[field] end
    end
    return {{key = request.key, u = clean.updated, s = s, d = d}}
end
-- Noms d'objets relus en jeu pour l'équipement reçu sans noms ; un objet pas encore connu du jeu est demandé, et son nom
-- rempli à son arrivée (ITEM_DATA_LOAD_RESULT, voir Q.FillItemNames).
local waitingNames = {}
local function itemName(item)
    local fn = (C_Item and C_Item.GetItemNameByID) or (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not fn then return nil end
    local ok, name = pcall(fn, item)
    if ok and type(name) == 'string' and name ~= '' and not (issecretvalue and issecretvalue(name)) then return name end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item) end
    waitingNames[item] = true
end
local function addNames(equipment)
    for _, e in ipairs(equipment or {}) do if e.name == nil and e.item then e.name = itemName(e.item) end end
end
function Q.FillItemNames(item)
    if not waitingNames[item] then return end
    local name = itemName(item)
    if not name then return end
    waitingNames[item] = nil
    for _, c in pairs(QuinteCaractDB.characters) do
        for _, e in ipairs(type(c) == 'table' and c.source == 'sync' and c.equipment or {}) do
            if e.item == item and e.name == nil then e.name = name end
        end
    end
    if Q.UI then Q.UI.OnDataChanged() end
end
local function cleanStamps(s, updated)
    local out = {}
    for _, part in ipairs(PART_ORDER) do
        local t = type(s) == 'table' and s[part]
        out[part] = Q.Number(t, 0, updated, true) and t or updated
    end
    return out
end
local function merge(db, part, sender, now, request)
    if not bounded(part, 4) or not request or part.key ~= request.key or not Q.String(part.key) or not Q.String(sender)
        or not Q.sync:Member(part.key) then return false end
    local old, storedKey = existing(db, part.key, true)
    if old and old.source == 'self' then return false end
    if not old and not bounded(db.characters, 999) then return false end
    local character, received = part.character, nil
    if request.parts ~= nil then
        -- Parties seulement : posées sur la fiche que nous avons déjà, puis toute la fiche est revalidée
        if not old or type(part.d) ~= 'table' or not bounded(part.d, 32) or not array(request.parts, #PART_ORDER) then return false end
        character, received = {}, {}
        for k, v in pairs(old) do
            if k ~= 'source' and k ~= 'syncedFrom' and k ~= 'syncedAt' then character[k] = v end
        end
        for _, name in ipairs(request.parts) do
            if not PARTS[name] then return false end
            received[name] = true
            for _, field in ipairs(PARTS[name]) do character[field] = part.d[field] end
        end
        character.updated = part.u
    end
    local clean = validate(character, part.key, now)
    if clean then clean.gameStats = nil end
    if not clean or tooLow(clean) or clean.updated < now - 60 * 86400 or old and clean.updated <= (old.updated or 0) then return false end
    local gone = purgedAt(db, part.key)
    if not old and ((gone and clean.updated <= gone) or inactive(clean, now)) then return false end
    clean.source, clean.syncedFrom, clean.syncedAt = 'sync', sender, now
    addNames(clean.equipment)
    local key = storedKey or part.key
    db.characters[key] = clean
    if not storedKey and indexedFor == db.characters then index[Lib.CanonicalKey(key)] = key end
    -- Dates des parties : celles reçues prennent celles de l'expéditeur, les autres gardent les nôtres
    local theirs, entry = cleanStamps(part.s, clean.updated), stampsStore(db)[key]
    if type(entry) ~= 'table' or type(entry.t) ~= 'table' or not received then stampsStore(db)[key] = {t = theirs}
    else for name in pairs(received) do entry.t[name] = theirs[name] end end
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
    for key in pairs(stampsStore(db)) do if not db.characters[key] then db.partStamps[key] = nil end end
end
function Q.SyncInit()
    -- La synchro de guilde est gérée par le conteneur Quintessence (canal unique pour tous les modules)
    Q.sync = Quintessence:RegisterSync('caract', QuinteCaractDB, {Manifest = manifest, Need = need,
        Export = export, Merge = merge, Cleanup = cleanup, Changed = Q.Changed})
end
Q.SyncAdapter = {Validate = validate, Manifest = manifest, Need = need, Export = export, Merge = merge, Cleanup = cleanup}
local itemFrame = CreateFrame('Frame')
pcall(itemFrame.RegisterEvent, itemFrame, 'ITEM_DATA_LOAD_RESULT')
itemFrame:SetScript('OnEvent', function(_, _, item, success) if success and Q.Run then Q.Run('noms des objets', Q.FillItemNames, item) end end)

-- ---------------------------------------------------------------------------------------------------------------------
-- Fenêtre /quinte debug (conteneur 1.52.11, T252) : état de nos fiches, de la nôtre surtout (vérifiée ? annoncée ?), et
-- fiches reçues en retard sur le niveau de la liste de guilde. Lecture seule.
-- ---------------------------------------------------------------------------------------------------------------------
function Q.DiagnosticLines()
    local db, out = QuinteCaractDB, {}
    local D = Quintessence.Diagnostic or {}
    local when, ago = D.When or tostring, D.Ago or function() return '?' end
    out[#out + 1] = 'Module ' .. tostring(Q.version) .. ' · prêt ' .. tostring(Q.ready) .. ' · collecte suspendue ' .. tostring(Q.disabled or false)
        .. ' · relevés ' .. tostring(Q.scans) .. ' · changements ' .. tostring(Q.changes) .. ' · erreurs ' .. #(Q.errors or {})
    if type(db) ~= 'table' or type(db.characters) ~= 'table' then out[#out + 1] = 'QuinteCaractDB absente ou illisible.'; return out end
    local now, mine = Q.Now(), Q.Key()
    local total, own, received, old = 0, 0, 0, 0
    for _, c in pairs(db.characters) do
        if type(c) == 'table' then
            total = total + 1
            if c.source == 'self' then own = own + 1 else
                received = received + 1
                if (tonumber(c.updated) or 0) < now - 3 * 86400 then old = old + 1 end
            end
        end
    end
    out[#out + 1] = 'Fiches : ' .. total .. ' (à moi ' .. own .. ', reçues ' .. received .. ', reçues il y a plus de 3 jours ' .. old .. ')'
    local c, stored = existing(db, mine, true)
    if not c then out[#out + 1] = 'Ma fiche (' .. tostring(mine) .. ') : absente'
    else
        local clean = validate(c, stored, now)
        local fields = 0; for _ in pairs(c) do fields = fields + 1 end
        out[#out + 1] = 'Ma fiche : niveau ' .. tostring(c.level) .. ' · relevée le ' .. when(c.updated) .. ' (il y a ' .. ago(c.updated, now) .. ') · source '
            .. tostring(c.source) .. ' · ' .. fields .. ' champs · vérification ' .. (clean and 'OK' or 'REFUSÉE') .. (tooLow(c) and ' · niveau trop bas pour être partagée' or '')
        if not clean then
            -- Champ responsable : la vérification refaite sans chacun d'eux
            for field in pairs(c) do
                local copy = {}
                for k, v in pairs(c) do if k ~= field then copy[k] = v end end
                if validate(copy, stored, now) then out[#out + 1] = '  champ refusé : ' .. tostring(field) end
            end
        end
        local announced, entries = false, 0
        for _, batch in ipairs(manifest(db)) do
            for _, row in ipairs(batch) do entries = entries + 1; if row.key == stored then announced = true end end
        end
        out[#out + 1] = 'Annoncée aux autres : ' .. (announced and 'oui' or 'NON') .. ' · fiches annoncées ' .. entries
        local t = (db.partStamps or {})[stored]
        if type(t) == 'table' and type(t.t) == 'table' then
            local parts = {}
            for _, part in ipairs(PART_ORDER) do parts[#parts + 1] = part .. ' ' .. ago(t.t[part], now) end
            out[#out + 1] = 'Parties (âge) : ' .. table.concat(parts, ' · ')
        end
    end
    -- Fiches reçues en retard sur la liste de guilde (niveau plus haut dans la liste)
    local roster = Quintessence.sync and Quintessence.sync.roster or {}
    local late = {}
    for key, x in pairs(db.characters) do
        if type(x) == 'table' and x.source ~= 'self' then
            local r = roster[Lib.CanonicalKey(key)]
            if type(r) == 'table' and type(r.level) == 'number' and type(x.level) == 'number' and r.level > x.level then
                late[#late + 1] = { name = tostring(x.name or key), fiche = x.level, liste = r.level, at = x.updated, from = x.syncedFrom }
            end
        end
    end
    table.sort(late, function(a, b) return (a.at or 0) < (b.at or 0) end)
    out[#out + 1] = 'Fiches en retard sur la liste de guilde : ' .. #late
    for i = 1, math.min(#late, 25) do
        local l = late[i]
        out[#out + 1] = '  ' .. l.name .. ' : fiche ' .. l.fiche .. ', liste ' .. l.liste .. ' · fiche du ' .. when(l.at) .. ' · reçue de ' .. tostring(l.from or '?')
    end
    return out
end
if Quintessence.RegisterDiagnostic then Quintessence.RegisterDiagnostic('caract', 'Fiches (quinte-caract)', function() return Q.DiagnosticLines() end) end
