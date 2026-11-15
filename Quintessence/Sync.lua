local _, Core = ...
--[[
  Synchro de guilde unique pour tous les modules (LibQuinteSync v11, préfixe QUINTE3, protocole 3, T137).
  L'ancien préfixe QUINTE2 n'est plus qu'écouté : ses expéditeurs vont dans la liste des addons incompatibles (Versions.lua).
  Chaque module fournit le même adaptateur qu'avant (Manifest / Need / Export / Merge / Cleanup) ; le conteneur en fait
  un groupe par module (résumé, manifeste et delta séparés) et étiquette chaque échange avec l'identifiant du module :
  { m = 'craft', b = lot } , { m, q = demande } , { m, p = partie }.
  Les messages temps réel (Ride) passent par la même file, en priorité : { c = canal, d = données }.
]]
local Lib = LibStub('LibQuinteSync-1.0')
local PREFIX = 'QUINTE3' -- protocole 3 : les anciennes versions (QUINTE2, QUINTE1) ne se mélangent pas aux nouvelles
local LEGACY = 'QUINTE2' -- écouté seulement, pour repérer les membres qui n'ont pas mis à jour

local function moduleFor(wrapper)
    if type(wrapper) ~= 'table' or type(wrapper.m) ~= 'string' then return nil end
    return Core.syncModules[wrapper.m]
end

local mux = { LegacyPrefix = LEGACY }
function mux.SelfKey() return Core.Key() end
-- Membre entendu sur l'ancien protocole (version lue dans son annonce, ou nil)
function mux.Legacy(sender, version)
    if Core.Versions and Core.Versions.Legacy then Core.Run('incompatibles', Core.Versions.Legacy, sender, version) end
end
-- Mémoire des membres changée (nouveau membre, nouveau jour, départ) : le groupe « members » la diffuse
function mux.MemoryChanged() if Core.memberSync then Core.memberSync:NotifyLocal() end end
-- Un groupe de synchro par module (ordre stable)
function mux.Groups()
    local out = {}
    for id in pairs(Core.syncModules) do out[#out + 1] = id end
    table.sort(out)
    return out
end
-- Manifeste d'un module : ses lots, tels quels (le module borne la taille d'un lot)
function mux.Manifest(_, group)
    local m = Core.syncModules[group]
    if not m then return {} end
    local ok, batches = Core.Run('manifeste ' .. group, m.adapter.Manifest, m.data)
    return ok and type(batches) == 'table' and batches or {}
end
function mux.Need(_, remote, sender)
    local m = moduleFor(remote)
    if not m or type(remote.b) ~= 'table' then return {} end
    local ok, requests = Core.Run('demande ' .. remote.m, m.adapter.Need, m.data, remote.b, sender)
    local out = {}
    for i, request in ipairs(ok and type(requests) == 'table' and requests or {}) do out[i] = { m = remote.m, q = request } end
    return out
end
function mux.Export(_, request)
    local m = moduleFor(request)
    if not m then return {} end
    local ok, parts = Core.Run('export ' .. request.m, m.adapter.Export, m.data, request.q)
    local out = {}
    for i, part in ipairs(ok and type(parts) == 'table' and parts or {}) do out[i] = { m = request.m, p = part } end
    return out
end
function mux.Merge(_, part, sender, now, request)
    local m = moduleFor(part)
    if not m or type(request) ~= 'table' or request.m ~= part.m then return false end
    local ok, changed = Core.Run('fusion ' .. part.m, m.adapter.Merge, m.data, part.p, sender, now, request.q)
    if ok and changed and m.adapter.Changed then Core.Run('changement ' .. part.m, m.adapter.Changed, false) end
    return false -- le module concerné a déjà été prévenu
end
function mux.Cleanup(_, roster, now)
    for id, m in pairs(Core.syncModules) do
        if m.adapter.Cleanup then Core.Run('nettoyage ' .. id, m.adapter.Cleanup, m.data, roster, now) end
    end
end
function mux.Changed() end
-- Membres déjà vus dans la liste de guilde (hors ligne compris), sauvegardés d'une session à l'autre
function mux.Memory()
    if type(QuintessenceDB) ~= 'table' then return nil end
    if type(QuintessenceDB.members) ~= 'table' then QuintessenceDB.members = {} end
    return QuintessenceDB.members
end
function mux.Info() return Core.Info() end
function mux.Pong(sender, info) Core.Pong(sender, info) end
function mux.Problem(code, channel) Core.Problem(code, channel) end
-- Addons réservés à la guilde Quintessence : 'refuse' (autre guilde, sans guilde), 'wait' (guilde pas encore lue)
function mux.Blocked()
    local status = Core.GuildStatus()
    if status == 'ok' then return nil end
    return status == 'pending' and 'wait' or 'refuse'
end

-- Gestionnaire d'un canal temps réel : ses erreurs vont dans /quinte debug au lieu d'être avalées par la bibliothèque
local function listen(id, handler)
    Core.sync:Listen(id, function(data, sender, ...)
        Core.Seen(sender) -- il vient d'écrire : connecté, même si la liste de guilde n'est pas encore à jour
        Core.Run('canal ' .. id, handler, data, sender, ...)
    end)
end

function Core.SyncInit()
    if Core.sync then return end
    Core.sync = Lib:Register(PREFIX, {}, mux)
    for id, handler in pairs(Core.channels) do listen(id, handler) end
    if QuintessenceDB.syncEnabled == false then Core.sync:SetEnabled(false) end
end

function Core.StartSync()
    if Core.sync and not Core.started then Core.started = true; Core.sync:Start() end
end

function Core:SetSyncEnabled(value)
    QuintessenceDB.syncEnabled = value and true or false
    if Core.sync then Core.sync:SetEnabled(QuintessenceDB.syncEnabled) end
end

-- Poignée remise aux modules : mêmes méthodes que l'ancienne instance LibQuinteSync de chaque brique
-- (Announce, NotifyLocal, Status, SetEnabled, Member, roster, enabled…), mais toutes branchées sur la synchro commune.
local function handle(id)
    return setmetatable({ id = id }, { __index = function(handle, key)
        if key == 'Start' then return function() Core.StartSync() end end
        if key == 'SetEnabled' then return function(_, value) Core:SetSyncEnabled(value) end end
        local instance = Core.sync
        if not instance then
            if key == 'Status' then return function() return { enabled = false, queued = 0, buffers = 0, deferred = 'non démarrée', rejected = 0,
                sent = 0, failed = 0, retries = 0, received = 0, waiting = 0, strangers = 0, roster = 0, pending = 0, wants = 0 } end end
            if key == 'Member' then return function() return false end end
            if key == 'roster' then return {} end
            return function() end
        end
        local value = instance[key]
        -- (v11) changement local : seul le groupe de ce module est recalculé et diffusé
        if key == 'NotifyLocal' then
            local method = function() local sync = Core.sync; return sync:NotifyLocal(handle.id) end
            rawset(handle, key, method)
            return method
        end
        if type(value) == 'function' then
            -- Méthode gardée dans la poignée : les modules appellent sync:Member() pour chaque ligne de manifeste reçue,
            -- une nouvelle fermeture à chaque appel faisait du déchet. Elle relit la méthode à chaque appel.
            local method = function(_, ...) local sync = Core.sync; return sync[key](sync, ...) end
            rawset(handle, key, method)
            return method
        end
        return value
    end })
end

--- Partage les enregistrements d'un module avec la guilde. adapter : Manifest, Need, Export, Merge, Cleanup, Changed.
function Core:RegisterSync(id, data, adapter)
    assert(type(id) == 'string' and type(data) == 'table' and type(adapter) == 'table', 'synchro invalide')
    Core.syncModules[id] = { data = data, adapter = adapter }
    if not Core.sync and Core.ready then Core.SyncInit() end
    return handle(id)
end

--- Canal de messages temps réel d'un module (ex. Ride). handler(data, sender, channel).
function Core:RegisterChannel(id, handler)
    assert(type(id) == 'string' and type(handler) == 'function', 'canal invalide')
    Core.channels[id] = handler -- branché sur la synchro dès qu'elle existe (voir SyncInit)
    if Core.sync then listen(id, handler) end
    local channel = handle(id)
    rawset(channel, 'Send', function(_, data, target)
        if not Core.sync then return false end
        Core.sync:Message(id, data, target)
        return true
    end)
    return channel
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Registre commun des membres (v11, groupe « members ») : la mémoire des membres vus dans la liste de guilde
-- (QuintessenceDB.members, 45 jours) est partagée. Chaque client connaît alors les mêmes personnages et accepte les mêmes
-- données : sans cela, un reroll jamais vu en ligne par un client rendait les résumés toujours différents, et chaque
-- résumé relançait une comparaison complète (T135, P1). Un départ constaté sur une liste complète (gone) se propage aussi.
-- Le canal GUILD garantit que l'expéditeur est de la guilde ; un faux nom ajouté par un membre n'ouvre rien d'autre que
-- l'acceptation des données de ce nom.
-- ---------------------------------------------------------------------------------------------------------------------
local DAY, KEEP, MAX_MEMBERS, BATCH, PART = 86400, 45 * 86400, 2000, 30, 15
local function memory() return mux.Memory() or {} end
local function stampOf(m) return math.max(tonumber(m.seen) or 0, tonumber(m.gone) or 0) end
local function dayOf(m) return math.floor(stampOf(m) / DAY) end
local function shortText(v, n) return type(v) == 'string' and v ~= '' and #v <= n and not v:find('[%z\1-\31|]') end
local members = {}
function members.Manifest()
    local batches, current = {}, {}
    for who, m in pairs(memory()) do
        if type(m) == 'table' and shortText(who, 60) and type(m.seen) == 'number' then
            current[#current + 1] = { k = who, d = dayOf(m), g = m.gone and 1 or nil }
            if #current == BATCH then batches[#batches + 1] = current; current = {} end
        end
    end
    if #current > 0 then batches[#batches + 1] = current end
    return batches
end
function members.Need(_, remote)
    if type(remote) ~= 'table' or #remote > BATCH then return {} end
    local mine, today, wanted = memory(), math.floor(Core.Now() / DAY), {}
    for _, row in ipairs(remote) do
        if type(row) ~= 'table' or not shortText(row.k, 60) or type(row.d) ~= 'number' or row.d > today + 1 then return {} end
        local m = mine[row.k]
        -- (même jour : un départ compte quand même, sinon il attendait le lendemain)
        if row.d >= today - KEEP / DAY and (type(m) ~= 'table' or row.d > dayOf(m) or (row.g and not m.gone and row.d == dayOf(m))) then
            wanted[#wanted + 1] = row.k
        end
    end
    return #wanted > 0 and { { keys = wanted } } or {}
end
function members.Export(_, request)
    if type(request) ~= 'table' or type(request.keys) ~= 'table' or #request.keys > BATCH then return {} end
    local mine, parts, current = memory(), {}, {}
    for _, who in ipairs(request.keys) do
        local m = type(who) == 'string' and mine[who]
        if type(m) == 'table' and type(m.name) == 'string' then
            current[#current + 1] = { k = who, n = m.name, c = m.class, l = m.level, s = m.seen, g = m.gone }
            if #current == PART then parts[#parts + 1] = { r = current }; current = {} end
        end
    end
    if #current > 0 then parts[#parts + 1] = { r = current } end
    return parts
end
function members.Merge(_, part, _, now, request)
    if type(part) ~= 'table' or type(part.r) ~= 'table' or #part.r > PART or type(request) ~= 'table' or type(request.keys) ~= 'table' then return false end
    local asked = {}
    for _, who in ipairs(request.keys) do asked[who] = true end
    local mine, changed, size = memory(), false, Core.Count(memory())
    for _, row in ipairs(part.r) do
        local seen, gone = tonumber(row.s), row.g ~= nil and tonumber(row.g) or nil
        if type(row) == 'table' and asked[row.k] and shortText(row.n, 60) and Core.CanonicalKey(row.n) == row.k and seen
            and seen <= now + 300 and seen >= now - KEEP and (row.g == nil or (gone and gone <= now + 300)) then
            local m = mine[row.k]
            local incoming = math.max(seen, gone or 0)
            if (type(m) == 'table' and incoming > stampOf(m)) or (type(m) ~= 'table' and size < MAX_MEMBERS) then
                if type(m) ~= 'table' then size = size + 1 end
                mine[row.k] = { name = row.n, class = shortText(row.c, 20) and row.c or nil, level = tonumber(row.l),
                    seen = seen, gone = gone, shared = true }
                changed = true
                -- Départ appris : il n'est plus membre tout de suite (s'il n'est que retenu, pas vu dans notre liste)
                local roster = Core.sync and Core.sync.roster
                if gone and gone >= seen and type(roster) == 'table' and roster[row.k] and roster[row.k].remembered then roster[row.k] = nil end
            end
        end
    end
    return changed
end
Core.memberSync = Core:RegisterSync('members', {}, members)
Core.MembersAdapter = members
