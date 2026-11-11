local _, Q = ...
--[[
  PvPShare.lua : le journal PvP de chaque membre envoyé aux officiers en ligne, pour que le quinte-map.lua d'un officier
  (envoyé au site par Quinte-sync ou Officiers > Importer) contienne celui de toute la guilde.

  - Jamais sur le canal de guilde : chuchotement aux officiers en ligne seulement (rangs 0 et 1, Quintessence.Announce),
    canal temps réel 'qmap' du module (messages 'pvp' et 'pvpa'), noms par le conteneur (CanonicalKey, WhisperTarget).
  - Le membre n'envoie que ses propres relevés (personnage joué) : morts, coups fataux, crédits d'honneur, et les relevés
    BG/arène une fois la partie finie ou quittée (une partie en cours change toutes les 5 s). Rien en combat, en BG ou
    en arène : envoi à la sortie. 5 s après un nouveau relevé, par lots de 6 relevés / 8 Kio estimés au plus, un lot à la
    fois par officier, le suivant après son accusé de réception.
  - L'officier range chaque relevé TEL QUEL dans QuinteMapDB.pvp.guild (mêmes identifiants, même contenu : le site
    dédoublonne par identifiant et empreinte, site/docs/PVP_DATA.md), après vérification : le déclarant est l'expéditeur
    (une observation par déclarant, jamais celle d'un autre), identifiant « GUID:… » du déclarant, format et taille
    bornés, aucune valeur secrète. Il répond 'pvpa' (dernier numéro et révisions lus) ; le membre retient ce qui a été
    reçu par chaque officier (characters[guid].shared) et renvoie le reste quand l'officier est en ligne : à sa
    connexion (présence), toutes les 10 min, à chaque nouveau relevé. Sans réponse en 60 s (officier sans cette
    version) : nouvel essai dans 10 min, dans 1 h après trois échecs.
  - Budget : le journal entier (relevés à soi + reçus) reste sous P.BYTE_BUDGET (3 Mio estimés) ; les relevés à soi
    passent d'abord, les plus anciens reçus partent en premier. 28 jours, 1000 événements et 30 parties par déclarant.
  - Aucun classement : liste chronologique d'observations, jamais d'addition des témoins.
]]
local P = Q.PvP
local Sh = {}
P.Share = Sh

local SEND_DELAY, BUSY_RETRY, CATCHUP_EVERY, PRESENCE_DELAY, NEXT_BATCH = 5, 30, 600, 20, 2
local ACK_WAIT, RETRY_SOON, RETRY_LATE = 60, 600, 3600
local BATCH_RECORDS, BATCH_WEIGHT = 6, 8 * 1024
local MAX_IN = 20                                -- relevés acceptés par message reçu
local MAX_GUILD_EVENTS, MAX_GUILD_MATCHES = 5000, 300
local MAX_RECORD_WEIGHT = 128 * 1024
local SHARE_WINDOW = 14 * 86400                  -- un relevé plus vieux n'est plus envoyé (jamais reçu d'un officier)
local FORGET_OFFICER = 60 * 86400                -- accusés d'un officier jamais revu oubliés
Sh.SEND_DELAY, Sh.CATCHUP_EVERY, Sh.ACK_WAIT, Sh.BATCH_RECORDS = SEND_DELAY, CATCHUP_EVERY, ACK_WAIT, BATCH_RECORDS
Sh.MAX_GUILD_EVENTS, Sh.MAX_GUILD_MATCHES = MAX_GUILD_EVENTS, MAX_GUILD_MATCHES

local KINDS = { death = true, kill = true, group_kill = true, honor_credit = true }
local CONFIDENCE = { identified = true, probable = true, unknown = true }
local MODES = { world = true, battleground = true, arena = true, instance = true, duel = true, unknown = true }
local inflight, scheduled = {}, false
local index -- { events = { [id] = r }, matches = { [id] = r } } des relevés reçus, reconstruit à la demande
local stats = { sent = 0, received = 0, refused = 0, acked = 0 }
Sh.stats = stats

local function core() return Quintessence end
local function announce() return Quintessence and Quintessence.Announce end
local function key(name) return Quintessence.CanonicalKey(name) end
local function isOfficer() local a = announce(); return a and a.IsOfficer and a.IsOfficer() == true end
local function senderIsOfficer(name) local a = announce(); return a and a.SenderIsOfficer and a.SenderIsOfficer(name) == true end
local function guildOk() return not (core().GuildStatus and core().GuildStatus() ~= 'ok') end
local function now() return P.Now() end
local function seqOf(id, origin)
    if type(id) ~= 'string' or type(origin) ~= 'string' or #id > 160 then return nil end
    if id:sub(1, #origin + 1) ~= origin .. ':' then return nil end
    local n = id:sub(#origin + 2)
    if not n:match('^%d+$') or #n > 9 then return nil end
    return tonumber(n)
end
Sh.SeqOf = seqOf

-- ---------------------------------------------------------------------------------------------------------------------
-- Chez l'officier : relevés reçus (QuinteMapDB.pvp.guild)
-- ---------------------------------------------------------------------------------------------------------------------
local function guild(create)
    local store = P.Store()
    if not store then return nil end
    local g = store.guild
    if g == nil and not create then return nil end -- créé à la première réception, jamais chez un simple membre
    if g == nil then g = { schema = 1, events = {}, matches = {}, reporters = {} }; store.guild = g end
    if type(g) ~= 'table' or g.schema ~= 1 then return nil end -- format inconnu (version future) : laissé tel quel
    g.events, g.matches, g.reporters = g.events or {}, g.matches or {}, g.reporters or {}
    return g
end
Sh.Guild = guild
local function buildIndex(g)
    if index and index.g == g then return index end
    index = { g = g, events = {}, matches = {} }
    for _, r in ipairs(g.events) do if type(r) == 'table' and r.id then index.events[r.id] = r end end
    for _, r in ipairs(g.matches) do if type(r) == 'table' and r.id then index.matches[r.id] = r end end
    return index
end
-- Valeur sûre à garder telle quelle : texte court, nombre fini, booléen, tables bornées (clés texte ou liste 1..n)
local function plain(v, depth)
    if P.Secret(v) then return false end
    local t = type(v)
    if t == 'string' then return #v <= 256 end
    if t == 'number' then return v == v and v ~= math.huge and v ~= -math.huge end
    if t == 'boolean' then return true end
    if t ~= 'table' or depth > 8 then return false end
    local n = 0
    for k, x in pairs(v) do
        n = n + 1
        if n > 256 or P.Secret(k) then return false end
        if type(k) == 'number' then
            if k ~= math.floor(k) or k < 1 or k > 256 then return false end
        elseif type(k) ~= 'string' or not k:match('^[%a][%w_]*$') or #k > 64 then return false end
        if not plain(x, depth + 1) then return false end
    end
    return true
end
--- Relevé reçu valable ? kind 'event' | 'match' ; l'expéditeur doit être le déclarant. Renvoie son numéro.
function Sh.Check(r, kind, sender, origin)
    if type(r) ~= 'table' or P.Secret(r) then return nil end
    local n = seqOf(r.id, origin)
    if not n or r.schema ~= 1 or r.source ~= 'self' or type(r.reporter) ~= 'table' then return nil end
    local guid, name = r.reporter.guid, r.reporter.name
    if not P.IsPlayerGUID(guid) or type(name) ~= 'string' or name == '' or origin:sub(1, #guid + 1) ~= guid .. ':' then return nil end
    if key(name) ~= key(sender) then return nil end -- jamais l'observation d'un autre
    if type(r.context) ~= 'table' or not MODES[r.context.mode] then return nil end
    local at = kind == 'event' and r.at or r.firstSeenAt
    local t = now()
    if type(at) ~= 'number' or at > t + 300 or at < t - P.KEEP then return nil end
    if kind == 'event' then
        if not KINDS[r.kind] or type(r.evidence) ~= 'table' or not CONFIDENCE[r.evidence.confidence] then return nil end
    else
        if r.context.mode ~= 'battleground' and r.context.mode ~= 'arena' then return nil end
        if r.status ~= 'complete' and r.status ~= 'left' then return nil end
        if type(r.revision) ~= 'number' or r.revision < 1 or r.revision ~= math.floor(r.revision) then return nil end
        if type(r.scores) ~= 'table' or #r.scores > 80 then return nil end
    end
    if not plain(r, 0) or P.Weight(r) > MAX_RECORD_WEIGHT then return nil end
    return n
end
local function insertSorted(list, r, field)
    local i = #list
    while i > 0 and (list[i][field] or 0) > (r[field] or 0) do i = i - 1 end
    table.insert(list, i + 1, r)
end
local function dropReporterExcess(list, guid, max, field)
    local count = 0
    for _, r in ipairs(list) do if r.reporter and r.reporter.guid == guid then count = count + 1 end end
    local i = 1
    while count > max and i <= #list do
        local r = list[i]
        if r.reporter and r.reporter.guid == guid then
            table.remove(list, i); count = count - 1
            if index then index[field][r.id] = nil end
        else i = i + 1 end
    end
end
--- Budget des relevés reçus = ce que laissent les relevés à soi (appelé par PvP.lua après son propre élagage).
function Sh.Enforce(room)
    local g = guild()
    if not g then return end
    local idx = buildIndex(g)
    local cut = now() - P.KEEP
    local diag = P.Store().diagnostics
    local function drop(list, field)
        local r = table.remove(list, 1)
        idx[field][r.id] = nil
        diag.guildPruned = (diag.guildPruned or 0) + 1
        return r
    end
    for _, pair in ipairs({ { g.events, 'events', MAX_GUILD_EVENTS }, { g.matches, 'matches', MAX_GUILD_MATCHES } }) do
        local list, field, max = pair[1], pair[2], pair[3]
        while #list > 0 and (#list > max or (list[1].at or 0) < cut) do drop(list, field) end
    end
    local total = 0
    for _, list in ipairs({ g.events, g.matches }) do for _, r in ipairs(list) do total = total + P.Weight(r) end end
    room = math.max(0, room or P.BYTE_BUDGET)
    while total > room do
        local e, m = g.events[1], g.matches[1]
        if not e and not m then break end
        local useEvents = e and (not m or (e.at or 0) <= (m.at or 0))
        local r = drop(useEvents and g.events or g.matches, useEvents and 'events' or 'matches')
        total = total - P.Weight(r)
    end
    diag.guildBytes = total
    -- Déclarants : seulement ceux qui ont encore des relevés
    local live = {}
    for _, list in ipairs({ g.events, g.matches }) do for _, r in ipairs(list) do live[r.reporter.guid] = true end end
    for guid in pairs(g.reporters) do if not live[guid] then g.reporters[guid] = nil end end
end
local function receive(data, sender)
    if not (P.ready and isOfficer()) then return end
    local origin = data.o
    if type(origin) ~= 'string' or #origin > 120 then return end
    local events = type(data.e) == 'table' and data.e or {}
    local matches = type(data.m) == 'table' and data.m or {}
    if #events + #matches > MAX_IN then stats.refused = stats.refused + 1; return end
    local g = guild(true)
    if not g then return end
    local idx = buildIndex(g)
    local last, revisions, added, reporter = 0, {}, 0, nil
    for i = 1, #events do
        local r = events[i]
        local n = Sh.Check(r, 'event', sender, origin)
        if n then
            last = math.max(last, n); reporter = r.reporter
            if not idx.events[r.id] then -- événement immuable : le premier reçu est gardé
                insertSorted(g.events, r, 'at'); idx.events[r.id] = r; added = added + 1
            end
        else
            stats.refused = stats.refused + 1
            local m = type(r) == 'table' and seqOf(r.id, origin)
            if m then last = math.max(last, m) end -- illisible : compté comme lu, jamais redemandé
        end
    end
    for i = 1, #matches do
        local r = matches[i]
        local n = Sh.Check(r, 'match', sender, origin)
        if n then
            reporter = r.reporter
            local old = idx.matches[r.id]
            if not old or (old.revision or 0) < r.revision then
                if old then
                    for j, x in ipairs(g.matches) do if x == old then table.remove(g.matches, j); break end end
                    P.Forget(old)
                end
                insertSorted(g.matches, r, 'at'); idx.matches[r.id] = r; added = added + 1
            end
            revisions[r.id] = math.max(r.revision, old and old.revision or 0)
        else
            stats.refused = stats.refused + 1
            if type(r) == 'table' and seqOf(r.id, origin) and type(r.revision) == 'number' then revisions[r.id] = r.revision end
        end
    end
    if reporter then
        local rep = g.reporters[reporter.guid] or {}
        rep.name, rep.at = reporter.name, now()
        rep.sender = key(sender)
        g.reporters[reporter.guid] = rep
        dropReporterExcess(g.events, reporter.guid, P.MAX_EVENTS, 'events')
        dropReporterExcess(g.matches, reporter.guid, P.MAX_MATCHES, 'matches')
    end
    stats.received = stats.received + added
    if added > 0 then
        P.Revision = P.Revision + 1
        -- Tout le journal repasse sous le budget (les relevés à soi d'abord)
        local own = P.Store().diagnostics.estimatedBytes or 0
        Sh.Enforce(P.BYTE_BUDGET - own)
        if Sh.OnReceived then Sh.OnReceived() end
    end
    if Q.comm and Q.comm.Send then Q.comm:Send({ t = 'pvpa', o = origin, s = last, m = revisions }, sender) end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Chez chaque membre : ce qui reste à envoyer à chaque officier
-- ---------------------------------------------------------------------------------------------------------------------
local function sharedFor(officer)
    local c = P.Character()
    c.shared = type(c.shared) == 'table' and c.shared or {}
    local s = c.shared[officer]
    if type(s) ~= 'table' then s = { seq = 0, m = {} }; c.shared[officer] = s end
    s.seq, s.m = tonumber(s.seq) or 0, type(s.m) == 'table' and s.m or {}
    return s
end
--- Relevés du personnage joué que cet officier n'a pas encore confirmés (les plus anciens d'abord).
function Sh.Pending(officer)
    local store, owner, c = P.Store(), P.Owner(), P.Character()
    if not (store and owner and c) then return {} end
    local s, cut, out = sharedFor(officer), now() - SHARE_WINDOW, {}
    for _, e in ipairs(store.events) do
        local n = e.reporter and e.reporter.guid == owner.guid and seqOf(e.id, c.origin)
        if n and n > s.seq and (e.at or 0) >= cut and P.Weight(e) <= MAX_RECORD_WEIGHT then out[#out + 1] = { r = e, n = n } end
    end
    table.sort(out, function(a, b) return a.n < b.n end)
    for _, m in ipairs(store.matches) do
        if m.reporter and m.reporter.guid == owner.guid and seqOf(m.id, c.origin) and (m.status == 'complete' or m.status == 'left')
            and (s.m[m.id] or 0) < (m.revision or 0) and (m.at or 0) >= cut and P.Weight(m) <= MAX_RECORD_WEIGHT then
            out[#out + 1] = { r = m, match = true }
        end
    end
    return out
end
local function busy()
    if P.Get(InCombatLockdown) == true then return 'combat' end
    local _, kind = P.Get(IsInInstance)
    if kind == 'pvp' or kind == 'arena' then return 'champ de bataille' end
    return nil
end
local function officersOnline()
    local a = announce()
    if not (a and a.OnlineOfficers) then return {} end
    local me, out = key(Q.PlayerName()), {}
    for _, k in ipairs(a.OnlineOfficers() or {}) do if k ~= me then out[#out + 1] = k end end
    return out
end
Sh.OfficersOnline = officersOnline
--- Un lot vers un officier (rien s'il en attend déjà un, ou s'il ne répond pas depuis peu).
function Sh.SendTo(officer)
    if not (P.ready and Q.comm and Q.comm.Send and guildOk()) then return false end
    local s = sharedFor(officer)
    if inflight[officer] or (tonumber(s.retryAt) or 0) > now() then return false end
    local list = Sh.Pending(officer)
    if #list == 0 then return false end
    local events, matches, weight = {}, {}, 0
    for _, item in ipairs(list) do
        local w = P.Weight(item.r)
        if #events + #matches > 0 and (#events + #matches >= BATCH_RECORDS or weight + w > BATCH_WEIGHT) then break end
        if item.match then matches[#matches + 1] = item.r else events[#events + 1] = item.r end
        weight = weight + w
    end
    local mark = {}
    inflight[officer] = mark
    s.sentAt = now()
    stats.sent = stats.sent + #events + #matches
    Q.comm:Send({ t = 'pvp', v = 1, o = P.Character().origin, e = events, m = matches }, officer)
    P.Later(ACK_WAIT, function()
        if inflight[officer] ~= mark then return end
        inflight[officer] = nil
        s.fails = (tonumber(s.fails) or 0) + 1
        s.retryAt = now() + (s.fails >= 3 and RETRY_LATE or RETRY_SOON)
    end)
    return true
end
--- Envoie à tous les officiers en ligne (ou plus tard : combat, BG, arène).
function Sh.Flush()
    if not (P.ready and guildOk()) or Q.SOSOnly() then return end
    if busy() then Sh.Schedule(BUSY_RETRY); return end
    for _, officer in ipairs(officersOnline()) do Sh.SendTo(officer) end
end
function Sh.Schedule(delay)
    if scheduled then return end
    scheduled = true
    P.Later(delay or SEND_DELAY, function() scheduled = false; Sh.Flush() end)
end
local function onAck(data, sender)
    local c = P.Character()
    if not (P.ready and c and data.o == c.origin and senderIsOfficer(sender)) then return end
    local officer = key(sender)
    local s = sharedFor(officer)
    local n = tonumber(data.s)
    if n and n > s.seq and n <= (tonumber(c.seq) or 0) then s.seq = math.floor(n) end
    if type(data.m) == 'table' then
        for id, rev in pairs(data.m) do
            if type(id) == 'string' and seqOf(id, c.origin) and type(rev) == 'number' and rev > (s.m[id] or 0) then s.m[id] = rev end
        end
    end
    s.at, s.fails, s.retryAt = now(), 0, nil
    inflight[officer] = nil
    stats.acked = stats.acked + 1
    -- La suite, s'il en reste (un lot à la fois)
    if #Sh.Pending(officer) > 0 then P.Later(NEXT_BATCH, function() if not busy() then Sh.SendTo(officer) else Sh.Schedule(BUSY_RETRY) end end) end
end
--- Accusés d'officiers jamais revus et parties disparues oubliés.
local function cleanShared()
    local store = P.Store()
    local live = {}
    for _, m in ipairs(store.matches) do live[m.id] = true end
    for _, c in pairs(store.characters) do
        if type(c) == 'table' and type(c.shared) == 'table' then
            for officer, s in pairs(c.shared) do
                if type(s) ~= 'table' or (tonumber(s.at) or tonumber(s.sentAt) or 0) < now() - FORGET_OFFICER then c.shared[officer] = nil
                elseif type(s.m) == 'table' then for id in pairs(s.m) do if not live[id] then s.m[id] = nil end end end
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Messages, démarrage et état
-- ---------------------------------------------------------------------------------------------------------------------
function Sh.OnMessage(data, sender)
    if type(data) ~= 'table' or type(sender) ~= 'string' or P.Secret(sender) or Q.SOSOnly() or not guildOk() then return end
    if data.t == 'pvp' then receive(data, sender)
    elseif data.t == 'pvpa' then onAck(data, sender) end
end
--- Nouveau relevé enregistré (PvP.lua) : envoi 5 s plus tard, regroupé.
function Sh.Changed(r)
    local owner = P.Owner()
    if not (owner and type(r) == 'table' and r.reporter and r.reporter.guid == owner.guid) then return end
    if r.status == 'observed' then return end -- partie en cours : envoyée finie ou quittée
    Sh.Schedule(SEND_DELAY)
end
function Sh.Start()
    if Sh.started then return end
    Sh.started = true
    Q.Run('partage PvP', cleanShared)
    local function loop()
        Sh.Flush()
        P.Later(CATCHUP_EVERY, loop)
    end
    P.Later(60, loop) -- liste de guilde et rangs lus d'abord
    if core().OnPresence then
        core():OnPresence(function(name, online)
            if not online or not senderIsOfficer(name) then return end
            local officer = key(name)
            P.Later(PRESENCE_DELAY, function()
                local s = sharedFor(officer)
                s.retryAt = nil -- il revient : peut-être avec une version qui répond
                if not busy() then Sh.SendTo(officer) else Sh.Schedule(BUSY_RETRY) end
            end)
        end)
    end
end
--- Texte d'état (onglet Log PvP, /qmap debug).
function Sh.Status()
    local store, c = P.Store(), P.Character()
    if not (store and c) then return 'journal en attente.' end
    local officers, waiting = officersOnline(), 0
    for _, officer in ipairs(officers) do waiting = math.max(waiting, #Sh.Pending(officer)) end
    local text = string.format('%d officier(s) en ligne, %d relevé(s) à envoyer', #officers, waiting)
    local why = busy()
    if why and waiting > 0 then text = text .. ' (attente : ' .. why .. ')' end
    local g = isOfficer() and guild()
    if g then
        local n = 0
        for _ in pairs(g.reporters) do n = n + 1 end
        text = text .. string.format(' · reçus : %d événement(s), %d relevé(s) BG de %d membre(s), ≈ %d / %d Kio',
            #g.events, #g.matches, n, math.floor(((store.diagnostics.estimatedBytes or 0) + (store.diagnostics.guildBytes or 0)) / 1024),
            math.floor(P.BYTE_BUDGET / 1024))
    end
    return text .. '.'
end
