local _, Q = ...
-- Journal local : faits observés et attribution qualifiée, jamais un score ni une alerte.
-- Sources API et contrat : docs/PVP_DATA.md. Aucun code tiers repris.
local P = { ready = false }
Q.PvP = P
local MAX_EVENTS, MAX_MATCHES, KEEP = 1000, 30, 28 * 86400
local BYTE_BUDGET = 3 * 1024 * 1024 -- total du journal : relevés à soi d'abord, puis ceux reçus des membres (PvPShare.lua)
P.MAX_EVENTS, P.MAX_MATCHES, P.KEEP, P.BYTE_BUDGET = MAX_EVENTS, MAX_MATCHES, KEEP, BYTE_BUDGET
local weights = setmetatable({}, { __mode = "k" })
local actors, recentKills = {}, {}
local pendingDeath, alive = nil, true
local store, owner, match
local dueling, honorBaseline = false, nil
local registrationErrors = {}

local function secret(v)
    if type(issecretvalue) ~= 'function' then return false end
    local ok, result = pcall(issecretvalue, v)
    return not ok or result == true
end
local function get(fn, ...)
    if type(fn) ~= 'function' then return end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return end
    local function plain(v) if not secret(v) then return v end end
    return plain(a), plain(b), plain(c), plain(d), plain(e), plain(f), plain(g), plain(h)
end
-- max : longueur ; toute autre valeur est ignorée (text(get(f)) reçoit aussi les valeurs suivantes de f : sur Forever,
-- GetGuildInfo('player') donne le nom du grade en 2e valeur, qui faisait planter l'initialisation du journal en 0.9.x)
local function text(v, max)
    if secret(v) or type(v) ~= 'string' or v == '' then return nil end
    if type(max) ~= 'number' or secret(max) then max = 120 end
    return v:sub(1, max)
end
local function number(v)
    if secret(v) or type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
local function clock() return number(get(GetTime)) or Q.Now() end
local function now() return number(get(GetServerTime)) or Q.Now() end
local function playerGuid(v) return text(v) and v:match('^Player%-') ~= nil end
local function later(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, function() Q.Run('journal PvP différé', fn) end)
    else fn() end
end
P.Secret, P.Clock, P.Now, P.Later, P.Get, P.IsPlayerGUID = secret, clock, now, later, get, playerGuid
local function actor(unit)
    local guid = text(get(UnitGUID, unit))
    if not guid then return nil end
    local name = (unit == 'player' and text((get(Q.PlayerName)))) or text((get(Quintessence.UnitFullName, unit)))
    local _, class = get(UnitClass, unit)
    local faction = text(get(UnitFactionGroup, unit), 20)
    local a = { guid = guid, name = name, class = text(class, 20), level = number(get(UnitLevel, unit)), faction = faction,
        race = text(get(UnitRace, unit), 60), guild = text((get(GetGuildInfo, unit))), sex = number(get(UnitSex, unit)) }
    actors[guid] = { value = a, at = clock() }
    return a
end
local function fromGUID(guid, name)
    if not text(guid) and not text(name) then return nil end
    local a = guid and actors[guid] and actors[guid].value
    return { guid = text(guid), name = text(name) or (a and a.name), class = a and a.class,
        level = a and a.level, faction = a and a.faction }
end
-- Membres observés, pas une preuve d'assistance : aucun partage de points inventé.
local function groupSnapshot()
    local raid = get(IsInRaid) == true
    local count = number(get(GetNumGroupMembers))
    local members, byGUID = {}, {}
    local function add(unit)
        local a = actor(unit)
        if a and playerGuid(a.guid) and not byGUID[a.guid] then
            a.connected = get(UnitIsConnected, unit)
            a.visible = get(UnitIsVisible, unit)
            a.dead = get(UnitIsDeadOrGhost, unit)
            a.inRange = get(UnitInRange, unit)
            a.petGUID = text(get(UnitGUID, unit == 'player' and 'pet' or unit:gsub('(%d+)$', 'pet%1')))
            members[#members + 1] = a
            byGUID[a.guid] = a
            if a.petGUID then byGUID[a.petGUID] = a end
        end
    end
    add('player')
    if raid then for i = 1, math.min(count or 0, 40) do add('raid' .. i) end
    else for i = 1, math.min(math.max(0, (count or 1) - 1), 4) do add('party' .. i) end end
    return { kind = raid and 'raid' or ((count and count > 0) and 'party' or 'solo'),
        reportedSize = count, members = members, participation = 'roster_only' }, byGUID
end
local function context()
    local inside, kind = get(IsInInstance)
    local name, instanceType, difficultyID, difficultyName, maxPlayers, _, _, instanceID = get(GetInstanceInfo)
    local mode = 'unknown'
    if kind == 'pvp' then mode = 'battleground'
    elseif kind == 'arena' then mode = 'arena'
    elseif inside == false then mode = 'world'
    elseif inside == true then mode = 'instance' end
    if dueling and mode == 'world' then mode = 'duel' end
    return { mode = mode, instanceType = text(instanceType or kind, 20), name = text(name),
        instanceID = number(instanceID), difficultyID = number(difficultyID), difficultyName = text(difficultyName), maxPlayers = number(maxPlayers) }
end
local function place()
    local mapID = number(get(C_Map and C_Map.GetBestMapForUnit, 'player'))
    local pos = mapID and get(C_Map and C_Map.GetPlayerMapPosition, mapID, 'player')
    local x, y
    if pos then x, y = get(pos.GetXY, pos) end
    x, y = number(x), number(y)
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then x, y = nil, nil end
    local wx, wy, wz, continentID = get(UnitPosition, 'player')
    return { mapID = mapID, x = x and x * 100, y = y and y * 100,
        worldX = number(wx), worldY = number(wy), worldZ = number(wz), continentID = number(continentID),
        zone = text(get(GetZoneText)), subzone = text(get(GetSubZoneText)),
        layer = number(get(Q.DetectCurrentLayer)), zid = number(get(Q.CurrentZid)), positionOf = 'reporter' }
end
local function diag(key)
    store.diagnostics[key] = (store.diagnostics[key] or 0) + 1
end
local function nextID()
    local c = store.characters[owner.guid]
    c.seq = c.seq + 1
    return c.origin .. ':' .. c.seq
end
local function trim(list, max, field)
    local cut = now() - KEEP
    while #list > 0 and (#list > max or (list[1][field] or 0) < cut) do
        table.remove(list, 1); diag('pruned')
    end
end
-- Estimation volontairement majorée du texte SavedVariables (échappement et indentation compris).
-- Cache faible : seules les tables des relevés modifiés sont recomptées, pas tout le journal.
local function weight(v)
    if type(v) == 'string' then return #v * 2 + 4 end
    if type(v) ~= 'table' then return 32 end
    local n = 8
    for k, value in pairs(v) do n = n + 48 + weight(k) + weight(value) end
    return n
end
--- Poids estimé d'un relevé, gardé en cache tant que le relevé ne change pas (P.Forget le recalcule).
function P.Weight(r)
    if type(r) ~= 'table' then return weight(r) end
    weights[r] = weights[r] or weight(r)
    return weights[r]
end
function P.Forget(r) if r then weights[r] = nil end end
P.Revision = 0 -- monte à chaque changement du journal (onglet Log PvP des officiers)
local function enforceBudget(changed)
    if changed then weights[changed] = nil end
    P.Revision = P.Revision + 1
    local total = 0
    for _, list in ipairs({ store.events, store.matches }) do
        for _, r in ipairs(list) do weights[r] = weights[r] or weight(r); total = total + weights[r] end
    end
    while total > BYTE_BUDGET do
        local e, m = store.events[1], store.matches[1]
        if not e and not m then break end
        local list = (e and (not m or e.at <= m.at)) and store.events or store.matches
        local removed = table.remove(list, 1)
        total = total - weights[removed]
        if removed == match then
            store.characters[owner.guid].activeMatchID = nil; match = nil
        end
        diag('budgetPruned')
    end
    store.diagnostics.estimatedBytes = total
    -- Les relevés reçus des membres (officier) se partagent ce qui reste du même budget
    if P.Share and P.Share.Enforce then P.Share.Enforce(BYTE_BUDGET - total) end
    -- Nouveau relevé ou partie revue : envoi aux officiers en ligne (PvPShare.lua), jamais pendant la collecte
    if changed and P.Share and P.Share.Changed then P.Share.Changed(changed) end
end
local function save(kind, other, evidence, captured)
    if not P.ready then return end
    local e = { schema = 1, id = nextID(), kind = kind, at = now(), source = 'self', reporter = owner,
        other = other, context = captured and captured.context or context(),
        location = captured and captured.location or place(), evidence = evidence or {}, matchID = match and match.id,
        group = captured and captured.group or groupSnapshot(),
        addonVersion = Q.version, groupSize = number(get(GetNumGroupMembers)), inRaid = get(IsInRaid) == true }
    store.events[#store.events + 1] = e
    trim(store.events, MAX_EVENTS, 'at')
    return e
end

function P.Observe(unit)
    if not P.ready then return end
    local a = actor(unit)
    if a and playerGuid(a.guid) and get(UnitCanAttack, 'player', unit) == true
        and get(UnitIsUnit, unit .. 'target', 'player') == true then
        actors[a.guid].targetedAt = clock()
    end
    local count = 0
    for guid, r in pairs(actors) do
        count = count + 1
        if clock() - r.at > 60 or count > 200 then actors[guid] = nil end
    end
end

local function recap()
    local link = text(get(C_DeathRecap and C_DeathRecap.GetRecapLink))
    local recapID = link and tonumber(link:match('death:(%d+)'))
    local rows = get(C_DeathRecap and C_DeathRecap.GetRecapEvents, recapID)
    local list, fatal = {}, nil
    if type(rows) == 'table' then
        for i = 1, math.min(#rows, 12) do
            local r = rows[i]
            if not secret(r) and type(r) == 'table' then
                local row = { sourceGUID = text(r.sourceGUID), sourceName = text(r.sourceName),
                    spellID = number(r.spellID), spellName = text(r.spellName), event = text(r.event, 40),
                    amount = number(r.amount), overkill = number(r.overkill), timestamp = number(r.timestamp) }
                list[#list + 1] = row
                if row.overkill and row.overkill >= 0 then fatal = row end
            end
        end
    end
    return list, fatal, recapID
end
function P.ResolveDeath()
    local pending = pendingDeath
    if not pending then return end
    pendingDeath = nil
    local rows, fatal, recapID = recap()
    local other, confidence, basis = nil, 'unknown', 'unavailable'
    if fatal and (fatal.sourceGUID or fatal.sourceName) then
        other = fromGUID(fatal.sourceGUID, fatal.sourceName)
        confidence, basis = 'identified', 'death_recap_fatal'
    else
        local candidate, at
        for _, r in pairs(actors) do
            if r.targetedAt and pending.clock - r.targetedAt >= 0 and pending.clock - r.targetedAt <= 10
                and (not at or r.targetedAt > at) then candidate, at = r.value, r.targetedAt end
        end
        if candidate then other, confidence, basis = candidate, 'probable', 'targeted_reporter' end
    end
    local e = save('death', other, { confidence = confidence, basis = basis, recap = rows, recapID = recapID }, pending)
    e.at, e.matchID = pending.at, pending.matchID
    e.pvp = other and playerGuid(other.guid) or false
    if not other or not other.guid then e.pvp = nil end
    enforceBudget(e)
end
function P.OnDeath()
    if not P.ready or (not alive) or pendingDeath then return end
    alive = false
    pendingDeath = { clock = clock(), at = now(), context = context(), location = place(), group = groupSnapshot(), matchID = match and match.id }
    local current = pendingDeath
    later(1, function()
        if pendingDeath ~= current then return end
        local rows = recap()
        if #rows > 0 then P.ResolveDeath() else later(1.5, function() if pendingDeath == current then P.ResolveDeath() end end) end
    end)
end
function P.OnAlive()
    if not P.ready or get(UnitIsDeadOrGhost, 'player') ~= false then return end
    -- Une résurrection très rapide ne doit pas écraser la mort précédente en attente.
    if pendingDeath then P.ResolveDeath() end
    alive = true
end
function P.OnKill(attackerGUID, victimGUID)
    if not P.ready or not playerGuid(victimGUID) or secret(attackerGUID) then return end
    local pet = text(get(UnitGUID, 'pet'))
    local group, members = groupSnapshot()
    local own = attackerGUID == owner.guid or (pet ~= nil and attackerGUID == pet)
    local killer = members[attackerGUID]
    if not own and not killer then return end
    local t = clock()
    if recentKills[victimGUID] and t - recentKills[victimGUID] < 5 then diag('duplicateKills'); return end
    recentKills[victimGUID] = t
    for guid, at in pairs(recentKills) do if t - at > 10 then recentKills[guid] = nil end end
    for _, unit in ipairs({ 'target', 'mouseover' }) do actor(unit) end
    local e = save(own and 'kill' or 'group_kill', fromGUID(victimGUID), { confidence = 'identified', basis = 'party_kill', attackerGUID = attackerGUID, pet = (killer and killer.petGUID == attackerGUID) or (pet ~= nil and attackerGUID == pet),
        killingBlowBy = killer or fromGUID(attackerGUID), creditedToReporter = own and true or false })
    e.group = group
    e.pvp = true
    enforceBudget(e)
end

local scoreNumbers = { 'killingBlows', 'honorableKills', 'deaths', 'honorGained', 'faction', 'damageDone', 'healingDone',
    'rating', 'ratingChange', 'prematchMMR', 'mmrChange', 'postmatchMMR', 'honorLevel', 'roleAssigned' }
local scoreTexts = { 'name', 'guid', 'classToken', 'className', 'raceName', 'talentSpec' }
local function cleanScore(r)
    if secret(r) or type(r) ~= 'table' then return nil end
    local out = { stats = {} }
    for _, k in ipairs(scoreNumbers) do out[k] = number(r[k]) end
    for _, k in ipairs(scoreTexts) do out[k] = text(r[k]) end
    local rows = not secret(r.stats) and r.stats
    if type(rows) == 'table' then
        for i = 1, math.min(#rows, 16) do
            local s = rows[i]
            if not secret(s) and type(s) == 'table' then
                out.stats[#out.stats + 1] = { id = number(s.pvpStatID), value = number(s.pvpStatValue), name = text(s.name), order = number(s.orderIndex) }
            end
        end
    end
    if not out.guid and not out.name then return nil end
    return out
end
function P.UpdateMatch()
    if not P.ready then return end
    local ctx = context()
    if ctx.mode ~= 'battleground' and ctx.mode ~= 'arena' then
        if match then
            local left = match
            if not match.endedAt then match.leftAt = now(); match.status = 'left'; match.revision = match.revision + 1 end
            store.characters[owner.guid].activeMatchID = nil; match = nil
            enforceBudget(left)
        end
        return
    end
    if match and match.context.instanceID ~= ctx.instanceID then
        match.status, match.leftAt = 'left', now(); match.revision = match.revision + 1
        local left = match
        match = nil
        enforceBudget(left)
    end
    if not match then
        match = { schema = 1, id = nextID(), reporter = owner, source = 'self', context = ctx,
            firstSeenAt = now(), at = now(), status = 'observed', revision = 1, scores = {}, addonVersion = Q.version }
        store.matches[#store.matches + 1] = match
        store.characters[owner.guid].activeMatchID = match.id
        trim(store.matches, MAX_MATCHES, 'at')
        get(RequestBattlefieldScoreData)
    end
end
function P.CaptureScores(winner, duration, completeEvent)
    if not P.ready then return end
    P.UpdateMatch()
    if not match then return end
    local complete = completeEvent or get(C_PvP and C_PvP.IsMatchComplete) == true
    local n = number(get(GetNumBattlefieldScores))
    local scores = {}
    for i = 1, math.min(n or 0, 80) do
        local raw = get(C_PvP and C_PvP.GetScoreInfo, i)
        if not raw and type(GetBattlefieldScore) == 'function' then
            local name, kb, hk, deaths, honor, faction, race, class = get(GetBattlefieldScore, i)
            raw = { name = name, killingBlows = kb, honorableKills = hk, deaths = deaths, honorGained = honor, faction = faction, raceName = race, className = class }
        end
        local s = cleanScore(raw)
        if s then scores[#scores + 1] = s end
    end
    -- Lecture vide ou masquée : préserver le dernier relevé, ne jamais convertir inconnu en zéro.
    if #scores > 0 then
        local old = {}; for _, s in ipairs(match.scores) do old[s.guid or s.name] = s end
        for _, s in ipairs(scores) do
            local prior = old[s.guid or s.name]
            if prior then
                for k, v in pairs(prior) do if s[k] == nil or (k == 'stats' and #s.stats == 0) then s[k] = v end end
            end
        end
        local seen = {}; for _, s in ipairs(scores) do seen[s.guid or s.name] = true end
        for key, s in pairs(old) do if not seen[key] then scores[#scores + 1] = s end end
        match.scores, match.scoresAt = scores, now()
        match.scoreRowsExpected = n
        match.scoresPartial = #scores ~= n
    else diag('scoresUnavailable') end
    if complete then
        match.status, match.endedAt = 'complete', match.endedAt or now()
        match.winner = number(winner) or number(get(C_PvP and C_PvP.GetActiveMatchWinner)) or match.winner
        match.duration = number(duration) or number(get(C_PvP and C_PvP.GetActiveMatchDuration)) or match.duration
    end
    match.updatedAt, match.revision = now(), match.revision + 1
    enforceBudget(match)
end
function P.Init()
    if P.ready then return end
    if Q.SOSOnly() then return end
    local status = Quintessence.GuildStatus and Quintessence.GuildStatus() or 'ok'
    if status ~= 'ok' then
        if status == 'pending' and (P.initAttempts or 0) < 12 then
            P.initAttempts = (P.initAttempts or 0) + 1
            later(5, P.Init)
        end
        return
    end
    QuinteMapDB.pvp = QuinteMapDB.pvp or { schema = 1 }
    store = QuinteMapDB.pvp
    if type(store) ~= 'table' or store.schema ~= 1 then
        Q.Error('journal PvP', 'Format inconnu : collecte suspendue, sauvegarde conservée.'); return
    end
    store.events, store.matches = store.events or {}, store.matches or {}
    store.characters, store.diagnostics = store.characters or {}, store.diagnostics or {}
    owner = actor('player')
    if not owner or not playerGuid(owner.guid) then
        if (P.initAttempts or 0) < 12 then P.initAttempts = (P.initAttempts or 0) + 1; later(5, P.Init) end
        return
    end
    local c = store.characters[owner.guid]
    if not c then
        c = { seq = 0, origin = owner.guid .. ':' .. now() .. ':' .. math.random(100000000, 999999999) }
        store.characters[owner.guid] = c
    end
    c.actor = owner
    for _, m in ipairs(store.matches) do if m.id == c.activeMatchID then match = m end end
    alive = get(UnitIsDeadOrGhost, 'player') ~= true
    P.ready = true
    store.diagnostics.unsupportedEvents = registrationErrors
    honorBaseline = number(get(GetPVPLifetimeStats))
    trim(store.events, MAX_EVENTS, 'at'); trim(store.matches, MAX_MATCHES, 'at')
    P.UpdateMatch()
    enforceBudget()
    if P.Share and P.Share.Start then P.Share.Start() end
end
function P.Store() return store end
function P.Owner() return owner end
function P.Character() return store and owner and store.characters[owner.guid] end
function P.Context() return context() end
function P.Debug()
    if not store then return end
    Q.Print(string.format('Journal PvP v%s : %s · %d événements · %d relevés BG/arène · %d retirés (28 jours / capacité).',
        tostring(store.schema), P.ready and 'actif' or 'en attente', #(store.events or {}), #(store.matches or {}), ((store.diagnostics or {}).pruned or 0) + ((store.diagnostics or {}).budgetPruned or 0)))
    if P.Share and P.Share.Status then Q.Print('Partage aux officiers : ' .. P.Share.Status()) end
end
local f = CreateFrame('Frame')
local events = { 'PLAYER_LOGIN', 'PLAYER_ENTERING_WORLD', 'PLAYER_GUILD_UPDATE', 'PLAYER_LOGOUT', 'PLAYER_DEAD', 'PLAYER_ALIVE', 'PLAYER_UNGHOST',
    'PARTY_KILL', 'PLAYER_PVP_KILLS_CHANGED', 'DUEL_REQUESTED', 'DUEL_FINISHED', 'UNIT_TARGET', 'PLAYER_TARGET_CHANGED', 'UPDATE_MOUSEOVER_UNIT', 'NAME_PLATE_UNIT_ADDED', 'PVP_MATCH_ACTIVE', 'PVP_MATCH_COMPLETE', 'UPDATE_BATTLEFIELD_SCORE' }
for _, ev in ipairs(events) do
    local ok = Q.Call(f.RegisterEvent, f, ev)
    if not ok then registrationErrors[#registrationErrors + 1] = ev end
end
f:SetScript('OnEvent', function(_, event, a, b)
    Q.Run('journal PvP ' .. event, function()
        if Q.SOSOnly() then return end
        local entering = event == 'PLAYER_LOGIN' or event == 'PLAYER_ENTERING_WORLD' or event == 'PLAYER_GUILD_UPDATE'
        if entering then
            P.Init()
        end
        if Quintessence.GuildStatus and Quintessence.GuildStatus() ~= 'ok' then return end
        if entering then
            if P.ready then P.UpdateMatch(); P.CaptureScores() end
        elseif P.ready then
            if event == 'PLAYER_DEAD' then P.OnDeath()
            elseif event == 'PLAYER_ALIVE' or event == 'PLAYER_UNGHOST' then P.OnAlive()
            elseif event == 'PARTY_KILL' then P.OnKill(a, b)
            elseif event == 'DUEL_REQUESTED' then dueling = true
            elseif event == 'DUEL_FINISHED' then dueling = false
            elseif event == 'PLAYER_PVP_KILLS_CHANGED' then
                local count = number(get(GetPVPLifetimeStats))
                if count and honorBaseline and count > honorBaseline then
                    local e = save('honor_credit', nil, { confidence = 'unknown', basis = 'lifetime_honor_counter',
                        delta = count - honorBaseline, total = count })
                    e.pvp = true
                    enforceBudget(e)
                end
                if count then honorBaseline = count end
            elseif event == 'PLAYER_LOGOUT' then if pendingDeath then P.ResolveDeath() end; P.CaptureScores()
            elseif event == 'PVP_MATCH_COMPLETE' then
                get(RequestBattlefieldScoreData)
                P.CaptureScores(a, b, true)
                local id = match and match.id
                later(2, function() if match and match.id == id then P.CaptureScores(a, b, true) end end)
            elseif event == 'PVP_MATCH_ACTIVE' then
                if match and match.endedAt then match = nil; store.characters[owner.guid].activeMatchID = nil end
                P.UpdateMatch()
            elseif event == 'UPDATE_BATTLEFIELD_SCORE' then
                if not P.lastScoreRead or clock() - P.lastScoreRead >= 5 or get(C_PvP and C_PvP.IsMatchComplete) == true then
                    P.lastScoreRead = clock(); P.CaptureScores()
                end
            elseif event == 'UNIT_TARGET' and text(a) and not a:find('^party') and not a:find('^raid') then P.Observe(a)
            elseif event == 'PLAYER_TARGET_CHANGED' then P.Observe('target')
            elseif event == 'UPDATE_MOUSEOVER_UNIT' then P.Observe('mouseover')
            elseif event == 'NAME_PLATE_UNIT_ADDED' and text(a) then P.Observe(a) end
        end
    end)
end)
