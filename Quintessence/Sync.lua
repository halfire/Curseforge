local _, Core = ...
--[[
  Synchro de guilde unique pour tous les modules (LibQuinteSync v6, préfixe QUINTE2, protocole 2).
  Chaque module fournit le même adaptateur qu'avant (Manifest / Need / Export / Merge / Cleanup) ; le conteneur en fait
  un groupe par module (résumé, manifeste et delta séparés) et étiquette chaque échange avec l'identifiant du module :
  { m = 'craft', b = lot } , { m, q = demande } , { m, p = partie }.
  Les messages temps réel (Ride) passent par la même file, en priorité : { c = canal, d = données }.
]]
local Lib = LibStub('LibQuinteSync-1.0')
local PREFIX = 'QUINTE2' -- protocole 2 : les anciennes versions (QUINTE1) ne se mélangent pas aux nouvelles

local function moduleFor(wrapper)
    if type(wrapper) ~= 'table' or type(wrapper.m) ~= 'string' then return nil end
    return Core.syncModules[wrapper.m]
end

local mux = {}
function mux.SelfKey() return Core.Key() end
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
