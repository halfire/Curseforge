local _, Q = ...
--[[
  PvPBoard.lua (0.14.0, T218) : vendettas, primes et classement PvP interne, calculés par le site (/api/pvp).
  Chez un officier, Quinte-sync écrit Feed.lua (QuinteMapFeed), lu au /reload. L'addon garde le plus récent dans
  QuinteMapDB.board et le partage en jeu : un officier qui a un flux plus récent l'envoie à la guilde, un membre qui se
  connecte le demande ('boardask', avec la date du sien) et un officier lui répond en chuchotement. Seul un officier
  (rangs 0 et 1) est cru : un simple membre ne peut pas inventer une vendetta.
  Alerte : un joueur recherché (prime) ciblé ou survolé hors instance, une fois par 10 minutes et par joueur.
  0.15.0 (T223) : objectifs de la semaine (du mercredi au mercredi), primes tombées et chasseur de la semaine, calculés
  par le site aussi ; classement « week » compté depuis le reset du mercredi (weekStart).
]]
local B = {}
Q.Board = B
local MAX_VENDETTAS, MAX_RANK, MAX_VICTIMS, MAX_OBJECTIVES, MAX_HUNTS = 100, 50, 10, 6, 10
local ALERT_GAP, ASK_DELAY, SHARE_DELAY, ANSWER_GAP = 600, 30, 20, 600

local function secret(v) return type(issecretvalue) == 'function' and issecretvalue(v) end
local function int(v, min, max) return type(v) == 'number' and not secret(v) and v % 1 == 0 and v >= min and v <= max and v or nil end
local function str(v, max)
    if type(v) ~= 'string' or secret(v) or v == '' or #v > max or v:find('[%z\1-\31|]') then return nil end
    return v
end

-- Contrôle d'un flux (du site ou reçu en jeu) : une copie propre, ou nil
local function cleanVendetta(v)
    if type(v) ~= 'table' then return nil end
    local guid, name = str(v.guid, 60), str(v.name, 60)
    if not guid or not guid:find('^Player%-') or not name then return nil end
    local victims = {}
    for _, n in ipairs(type(v.victims) == 'table' and v.victims or {}) do
        local s = str(n, 60); if s and #victims < MAX_VICTIMS then victims[#victims + 1] = s end
    end
    return { guid = guid, name = name, class = str(v.class, 20), level = int(v.level, 1, 100),
        deaths = int(v.deaths, 0, 100000) or 0, greyDeaths = int(v.greyDeaths, 0, 100000) or 0, bounty = int(v.bounty, 0, 1000000) or 0,
        victims = victims, last = int(v.last, 0, 4e9) or 0, zone = str(v.zone, 60), avenger = str(v.avenger, 60),
        avengedAt = int(v.avengedAt, 0, 4e9) }
end
local function cleanRank(list)
    local out = {}
    for _, r in ipairs(type(list) == 'table' and list or {}) do
        local name = type(r) == 'table' and str(r.name, 60)
        if name and #out < MAX_RANK then
            out[#out + 1] = { name = name, kills = int(r.kills, 0, 1e6) or 0, greyKills = int(r.greyKills, 0, 1e6) or 0,
                deaths = int(r.deaths, 0, 1e6) or 0, battlegrounds = int(r.battlegrounds, 0, 1e6) or 0, won = int(r.won, 0, 1e6) or 0,
                bounties = int(r.bounties, 0, 1e6) or 0, bountyPoints = int(r.bountyPoints, 0, 1e7) or 0 }
        end
    end
    return out
end
local function cleanObjectives(list)
    local out = {}
    for _, o in ipairs(type(list) == 'table' and list or {}) do
        local title, text = type(o) == 'table' and str(o.title, 60), type(o) == 'table' and str(o.text, 200)
        local goal = type(o) == 'table' and int(o.goal, 1, 1000)
        if title and text and goal and #out < MAX_OBJECTIVES then
            out[#out + 1] = { id = str(o.id, 20), title = title, text = text, target = str(o.target, 60),
                done = math.min(goal, int(o.done, 0, 1000) or 0), goal = goal }
        end
    end
    return out
end
local function cleanHunts(list)
    local out = {}
    for _, h in ipairs(type(list) == 'table' and list or {}) do
        local by = type(h) == 'table' and str(h.by, 60)
        if by and #out < MAX_HUNTS then
            out[#out + 1] = { by = by, target = str(h.target, 60) or '?', at = int(h.at, 0, 4e9) or 0, points = int(h.points, 0, 1000000) or 0 }
        end
    end
    return out
end
function B.Clean(feed)
    if type(feed) ~= 'table' or feed.format ~= 1 then return nil end
    local generated = int(feed.generated, 1, 4e9)
    if not generated or generated > Q.Now() + 3600 then return nil end
    local vendettas = {}
    for _, v in ipairs(type(feed.vendettas) == 'table' and feed.vendettas or {}) do
        local c = cleanVendetta(v); if c and #vendettas < MAX_VENDETTAS then vendettas[#vendettas + 1] = c end
    end
    local ranking = type(feed.ranking) == 'table' and feed.ranking or {}
    local hunter = type(feed.hunter) == 'table' and str(feed.hunter.name, 60)
        and { name = feed.hunter.name, points = int(feed.hunter.points, 0, 1e7) or 0, hunts = int(feed.hunter.hunts, 0, 1e6) or 0 } or nil
    local weekStart = int(feed.weekStart, 1, 4e9)
    return { format = 1, generated = generated, bountyDays = int(feed.bountyDays, 1, 3650) or 90, vendettas = vendettas,
        weekStart = weekStart and weekStart <= generated and weekStart or nil,
        objectives = cleanObjectives(feed.objectives), hunts = cleanHunts(feed.hunts), hunter = hunter,
        ranking = { week = cleanRank(ranking.week), month = cleanRank(ranking.month) } }
end

local function db()
    if type(QuinteMapDB.board) ~= 'table' then QuinteMapDB.board = nil end
    return QuinteMapDB.board
end
local index = {} -- guid → vendetta, pour l'alerte
local function reindex()
    index = {}
    local b = db()
    for _, v in ipairs(b and b.vendettas or {}) do index[v.guid] = v end
end
--- Garde ce flux s'il est plus récent que le nôtre ; true s'il a été pris.
function B.Take(feed, from)
    local clean = B.Clean(feed)
    local current = db()
    if not clean or (current and (tonumber(current.generated) or 0) >= clean.generated) then return false end
    clean.from = from
    QuinteMapDB.board = clean
    reindex()
    if Q.UI and Q.UI.Refresh then Q.UI.Refresh() end
    return true
end
function B.Get() return db() end
function B.Vendettas() local b = db(); return b and b.vendettas or {} end
function B.Ranking(period) local b = db(); return b and b.ranking and b.ranking[period == 'month' and 'month' or 'week'] or {} end
function B.Generated() local b = db(); return b and b.generated or nil end
function B.Objectives() local b = db(); return b and b.objectives or {} end
function B.Hunts() local b = db(); return b and b.hunts or {} end
function B.Hunter() local b = db(); return b and b.hunter or nil end
function B.WeekStart() local b = db(); return b and b.weekStart or nil end
--- Joueurs recherchés (prime > 0), la plus grosse prime d'abord (ordre du site).
function B.WantedList()
    local out = {}
    for _, v in ipairs(B.Vendettas()) do if v.bounty > 0 then out[#out + 1] = v end end
    return out
end
--- Joueur recherché (prime > 0) d'après son GUID.
function B.Wanted(guid)
    if type(guid) ~= 'string' or secret(guid) then return nil end
    local v = index[guid]
    return v and v.bounty > 0 and v or nil
end

-- Partage en jeu (canal qmap)
local function officer() return Q.PvP and Q.PvP.Share and Q.PvP.Share.IsOfficer and Q.PvP.Share.IsOfficer() end
local function senderOfficer(name) return Q.PvP and Q.PvP.Share and Q.PvP.Share.SenderIsOfficer and Q.PvP.Share.SenderIsOfficer(name) end
local function send(data, target) if Q.comm and Q.comm.Send then Q.comm:Send(data, target) end end
local function payload()
    local b = db()
    return b and { t = 'board', b = { format = 1, generated = b.generated, bountyDays = b.bountyDays, weekStart = b.weekStart,
        vendettas = b.vendettas, objectives = b.objectives, hunts = b.hunts, hunter = b.hunter, ranking = b.ranking } }
end
local answered = {}
function B.OnMessage(data, sender)
    if type(data) ~= 'table' then return end
    if data.t == 'board' then
        if not senderOfficer(sender) then return end
        B.Take(data.b, 'guild')
    elseif data.t == 'boardask' then
        local mine = db()
        if not (mine and officer()) then return end
        local theirs = int(data.g, 0, 4e9) or 0
        local who = Quintessence.CanonicalKey(sender)
        if mine.generated <= theirs or (answered[who] and Q.Now() - answered[who] < ANSWER_GAP) then return end
        answered[who] = Q.Now()
        send(payload(), sender)
    end
end

-- Alerte : joueur recherché ciblé ou survolé hors instance
local alerted = {}
local function inInstance()
    local ok, inside = pcall(IsInInstance or function() return false end)
    return ok and inside == true
end
function B.Check(unit)
    if not (UnitExists and UnitIsPlayer) then return end
    local okE, exists = pcall(UnitExists, unit); local okP, player = pcall(UnitIsPlayer, unit)
    if not (okE and exists == true and okP and player == true) or inInstance() then return end
    local ok, guid = pcall(UnitGUID, unit)
    local v = ok and B.Wanted(guid)
    if not v or (alerted[v.guid] and Q.Now() - alerted[v.guid] < ALERT_GAP) then return end
    alerted[v.guid] = Q.Now()
    local S = Quintessence.Style
    Q.Print('|c' .. S.hex.red .. 'Recherché :|r ' .. Q.Safe(v.name) .. ' — prime de ' .. v.bounty .. ' point' .. (v.bounty > 1 and 's' or '')
        .. ', ' .. v.deaths .. ' mort' .. (v.deaths > 1 and 's' or '') .. ' de la guilde' .. (#v.victims > 0 and (' (' .. Q.Safe(table.concat(v.victims, ', ')) .. ')') or '') .. '.')
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
end

function B.Init()
    reindex()
    local fresh = QuinteMapFeed ~= nil and B.Take(QuinteMapFeed, 'site')
    if C_Timer and C_Timer.After then
        -- Flux du site plus récent chez un officier : envoyé à la guilde ; sinon, demande à la connexion
        C_Timer.After(fresh and SHARE_DELAY or ASK_DELAY, function()
            Q.Run('vendettas', function()
                if fresh and officer() then local p = payload(); if p then send(p) end
                else send({ t = 'boardask', g = B.Generated() or 0 }) end
            end)
        end)
    end
    local f = CreateFrame('Frame')
    f:RegisterEvent('PLAYER_TARGET_CHANGED'); f:RegisterEvent('UPDATE_MOUSEOVER_UNIT')
    f:SetScript('OnEvent', function(_, event)
        Q.Run('alerte vendetta', B.Check, event == 'PLAYER_TARGET_CHANGED' and 'target' or 'mouseover')
    end)
end
