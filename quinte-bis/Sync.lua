local _, Q = ...
--[[
  Synchro de guilde via le conteneur Quintessence (module « bis ») : un enregistrement « c:<Nom-Royaume> » par liste BiS.
  Chacun diffuse sa propre liste ; tout le monde relaie celles qu'il connaît. La plus récente gagne, et personne ne
  peut remplacer la liste d'un autre joueur par une liste à son nom.
]]
local BATCH, PART = 30, 5

local function bounded(t, maximum)
    if type(t) ~= 'table' then return false end
    local n = 0
    for _ in pairs(t) do n = n + 1; if n > maximum then return false end end
    return true
end
local function list(t, maximum)
    if not bounded(t, maximum) then return false end
    local n = 0
    for k in pairs(t) do n = n + 1; if not Q.integer(k, 1, maximum) then return false end end
    return n == #t
end

local function records(db)
    local out = {}
    for key, c in pairs(db.characters) do
        if type(c) == 'table' and c.updated then out['c:' .. key] = c end
    end
    return out
end

local function manifest(db)
    local batches, current = {}, {}
    for key, record in pairs(records(db)) do
        current[#current + 1] = { k = key, u = record.updated }
        if #current == BATCH then batches[#batches + 1] = current; current = {} end
    end
    if #current > 0 then batches[#batches + 1] = current end
    return batches
end

local function need(db, remote)
    if not list(remote, BATCH) then return {} end
    local known, wanted = records(db), {}
    for _, row in ipairs(remote) do
        if type(row) ~= 'table' or type(row.k) ~= 'string' or #row.k > 70 or not Q.integer(row.u, 0, Q.Now() + 300) then return {} end
        local mine = known[row.k]
        if row.k ~= 'c:' .. Q.Key() and (not mine or (mine.updated or 0) < row.u) then wanted[#wanted + 1] = row.k end
    end
    return #wanted > 0 and { { keys = wanted } } or {}
end

local function export(db, request)
    if type(request) ~= 'table' or not list(request.keys, BATCH) then return {} end
    local known, parts, current = records(db), {}, {}
    for _, key in ipairs(request.keys) do
        local c = type(key) == 'string' and known[key]
        if c then
            current[#current + 1] = { k = key, d = { name = c.name, realm = c.realm, class = c.class, level = c.level, updated = c.updated, items = c.items, seen = c.seen } }
            if #current == PART then parts[#parts + 1] = { records = current }; current = {} end
        end
    end
    if #current > 0 then parts[#parts + 1] = { records = current } end
    return parts
end

local function merge(db, part, sender, now, request)
    if type(part) ~= 'table' or not list(part.records, PART) or type(request) ~= 'table' or not list(request.keys, BATCH) then return false end
    local asked = {}
    for _, key in ipairs(request.keys) do asked[key] = true end
    local changed = false
    for _, row in ipairs(part.records) do
        if type(row) ~= 'table' or not asked[row.k] then return changed end
        local c = Q.ValidCharacter(row.d, now)
        -- la liste doit correspondre à sa clé et à un personnage de la guilde
        if c and row.k == 'c:' .. Q.CharKeyOf(c) and Q.sync:Member(Q.CharKeyOf(c)) then
            changed = Q.PutCharacter(c, sender) or changed
        end
    end
    return changed
end

local function cleanup(_, roster, now) return Q.Prune(roster, now) end

function Q.SyncInit()
    -- La synchro de guilde est gérée par le conteneur Quintessence (canal unique pour tous les modules)
    Q.sync = Quintessence:RegisterSync('bis', QuinteBisDB, { Manifest = manifest, Need = need, Export = export,
        Merge = merge, Cleanup = cleanup, Changed = Q.Changed })
end
Q.SyncAdapter = { Manifest = manifest, Need = need, Export = export, Merge = merge }
