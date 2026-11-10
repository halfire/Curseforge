local _, Q = ...
-- Les fiches restent publiques dans la guilde ; leurs compteurs passent uniquement en chuchotements.
local Core, comm, sent, asked = Quintessence, nil, {}, {}
local function roster()
    local ok, n = pcall(GetNumGuildMembers or function() end)
    n = ok and Q.Number(n, 0, 2000, true)
    local out = {}
    if not n or type(GetGuildRosterInfo) ~= 'function' then return out end
    for i = 1, n do
        local good, name, _, rank, _, _, _, _, _, online = pcall(GetGuildRosterInfo, i)
        name = good and Q.String(name, 100)
        if name and Q.Number(rank, 0, 100, true) and not Q.Secret(online) then
            out[#out + 1] = {name = name, rank = rank, online = online == true or online == 1}
        end
    end
    return out
end
local function rankOf(name)
    if Core.GuildStatus and Core.GuildStatus() ~= 'ok' then return nil end
    if not name then
        local ok, guild, _, rank = pcall(GetGuildInfo or function() end, 'player')
        if ok and Q.String(guild) and guild:lower() == 'quintessence' and Q.Number(rank, 0, 100, true) then return rank end
        name = Core.PlayerName()
    end
    for _, row in ipairs(roster()) do if Core.SameName(row.name, name) then return row.rank end end
end
function Q.StatisticsOfficer(name)
    local rank = rankOf(name)
    return rank ~= nil and rank <= 1
end
local function privateDB()
    if type(QuinteCaractDB.statistics) ~= 'table' then QuinteCaractDB.statistics = {} end
    return QuinteCaractDB.statistics
end
function Q.StatisticsFor(c)
    if not Q.StatisticsOfficer() then return nil end
    if c.source == 'self' then return c.gameStats end
    if not Q.String(c.name) or not Q.String(c.realm) then return nil end
    local r = privateDB()[Core.CanonicalKey(c.name .. '-' .. c.realm)]
    return r and r.gameStats
end
function Q.CleanStatisticsPrivacy()
    local rank = rankOf()
    local allowed = rank ~= nil and rank <= 1
    for key, c in pairs(QuinteCaractDB.characters) do
        if type(c) == 'table' and c.gameStats and c.source ~= 'self' then
            if allowed then
                local clean = Q.SyncAdapter.Validate(c, key, Q.Now())
                if clean then
                    privateDB()[Core.CanonicalKey(key)] = {name = c.name, realm = c.realm, level = c.level,
                        updated = c.gameStats.at, source = 'sync', gameStats = clean.gameStats}
                end
            end
            c.gameStats = nil
        end
    end
    -- Rang encore inconnu au login : conserver les copies sans permettre leur lecture.
    if rank and rank > 1 then QuinteCaractDB.statistics = {} end
end
local function sendMine(target, known)
    if not comm or not Q.StatisticsOfficer(target) then return end
    local c = QuinteCaractDB.characters[Q.Key()]
    local s = Q.CollectGameStatistics()
    if not c or (c.level or 0) < Q.MIN_LEVEL or not s or known == s.at then return end
    local key = Core.CanonicalKey(target)
    if sent[key] and sent[key].at == s.at and Q.Now() - sent[key].time < 60 then return end
    local data = {name = c.name, realm = c.realm, level = c.level, updated = s.at, gameStats = s}
    if comm:Send({t = 'stats', key = Q.Key(), d = data}, target) then sent[key] = {at = s.at, time = Q.Now()} end
end
function Q.PublishStatistics()
    if not comm then return end
    for _, row in ipairs(roster()) do
        if row.online and row.rank <= 1 and not Core.SameName(row.name, Core.PlayerName()) then
            local previous = sent[Core.CanonicalKey(row.name)]
            local s = Q.CollectGameStatistics()
            if s and (not previous or previous.at ~= s.at) then sendMine(row.name) end
        end
    end
end
function Q.ReceivePrivateStatistics(data, sender, channel)
    if channel ~= 'WHISPER' or type(data) ~= 'table' or not Q.String(sender) then return end
    if data.t == 'ask' then
        if Q.StatisticsOfficer(sender) then sendMine(sender, Q.Number(data.at, 0, Q.Now() + 300, true)) end
        return
    end
    if data.t ~= 'stats' or not Q.StatisticsOfficer() or not Q.String(data.key)
        or not Core.SameName(data.key, sender) then return end
    local clean = Q.SyncAdapter.Validate(data.d, data.key, Q.Now())
    if not clean or not clean.gameStats or (clean.level or 0) < Q.MIN_LEVEL then return end
    local key, db = Core.CanonicalKey(data.key), privateDB()
    local old = db[key]
    if old and old.gameStats.at >= clean.gameStats.at then return end
    local n = 0; for _ in pairs(db) do n = n + 1 end
    if not old and n >= 1000 then return end
    db[key] = {name = clean.name, realm = clean.realm, level = clean.level,
        updated = clean.gameStats.at, source = 'sync', gameStats = clean.gameStats}
    if Q.UI then Q.UI.OnDataChanged() end
end
function Q.StatisticsPrivacyTick()
    Q.CleanStatisticsPrivacy()
    if not comm then return end
    Q.PublishStatistics()
    if Q.StatisticsOfficer() then
        for _, row in ipairs(roster()) do
            local key = Core.CanonicalKey(row.name)
            if row.online and not Core.SameName(row.name, Core.PlayerName()) and (not asked[key] or Q.Now() - asked[key] >= 120) then
                local known = privateDB()[key]
                comm:Send({t = 'ask', at = known and known.gameStats.at or 0}, row.name)
                asked[key] = Q.Now()
            end
        end
    end
    if Q.UI then Q.UI.OnDataChanged() end
end
function Q.InitStatisticsPrivacy()
    comm = Core:RegisterChannel('qcstats', Q.ReceivePrivateStatistics)
    Q.CleanStatisticsPrivacy()
    if C_Timer and C_Timer.After then
        local function loop() Q.Run('statistiques privées', Q.StatisticsPrivacyTick); C_Timer.After(120, loop) end
        C_Timer.After(10, loop)
    end
end
local frame = CreateFrame('Frame')
for _, e in ipairs({'GUILD_ROSTER_UPDATE', 'PLAYER_GUILD_UPDATE'}) do pcall(frame.RegisterEvent, frame, e) end
frame:SetScript('OnEvent', function()
    if Q.ready and not Q.disabled then Q.Run('droits des statistiques', Q.StatisticsPrivacyTick) end
end)
